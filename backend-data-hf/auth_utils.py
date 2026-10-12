from jose import JWTError, jwt
from passlib.context import CryptContext
from datetime import datetime, timedelta, timezone
import os
from typing import Optional
from dotenv import load_dotenv

load_dotenv()

# Secret key to sign JWT tokens (Must be configured via JWT_SECRET)
SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError(
        "FATAL SECURITY ERROR: 'JWT_SECRET' environment variable is not set. "
        "Refusing to start with an insecure fallback secret."
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 1 week

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def create_reset_password_token(email: str):
    """
    Creates a JWT token for password reset that expires in 15 minutes.
    """
    to_encode = {"sub": email, "type": "reset_password"}
    expire = datetime.now(timezone.utc) + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

import uuid
from fastapi import Depends, HTTPException, status, Header
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from connection import get_db
from models import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)

# Distinct Supabase JWT Secret for mobile token verification (never conflate with SECRET_KEY)
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")

async def _resolve_user_from_token(
    token: Optional[str],
    db: AsyncSession
) -> Optional[User]:
    """
    Unified cryptographic user resolution supporting:
    1. Local custom JWT (FastAPI web client signed with JWT_SECRET)
    2. Supabase Auth JWT (Mobile client token verified via SUPABASE_JWT_SECRET / HS256)
    Untrusted client headers (X-User-ID / X-User-Email) are strictly dropped.
    """
    if not token:
        return None

    sub = None
    email = None
    is_supabase = False
    email_confirmed = False

    # 1. Attempt verification with application SECRET_KEY
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub") or payload.get("email")
        sub = payload.get("id") or (payload.get("sub") if "@" not in str(payload.get("sub", "")) else None)
        email_confirmed = True
    except JWTError:
        # 2. Attempt cryptographic verification with SUPABASE_JWT_SECRET
        if SUPABASE_JWT_SECRET:
            try:
                payload = jwt.decode(
                    token, 
                    SUPABASE_JWT_SECRET, 
                    algorithms=["HS256"], 
                    options={"verify_aud": False}
                )
                email = payload.get("email")
                sub = payload.get("sub")
                is_supabase = True
                email_confirmed = bool(payload.get("email_confirmed_at"))
            except JWTError:
                return None
        else:
            return None

    # 3. If Supabase token, check matching by supabase_uid first
    if is_supabase and sub:
        result = await db.execute(select(User).where(User.supabase_uid == str(sub)))
        user = result.scalars().first()
        if user:
            return user

    # 4. Lookup user by verified UUID / sub
    if sub:
        try:
            u_uuid = uuid.UUID(sub)
            result = await db.execute(select(User).where(User.id == u_uuid))
            user = result.scalars().first()
            if user:
                return user
        except Exception:
            pass

    # 5. Lookup user by verified Email
    if email:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalars().first()
        if user:
            # If Supabase login, only link account if Supabase email is confirmed
            if is_supabase:
                if not email_confirmed:
                    # Prevent account takeover via unconfirmed Supabase email
                    return None
                if not user.supabase_uid and sub:
                    user.supabase_uid = str(sub)
                    try:
                        await db.commit()
                        await db.refresh(user)
                    except Exception:
                        await db.rollback()
            return user

    # 6. Auto-provision in public.users if cryptographically verified via Supabase
    if is_supabase and (email or sub):
        try:
            user_id = uuid.UUID(sub) if (sub and len(sub) == 36) else uuid.uuid4()
            user_email = email or f"user_{str(user_id)[:8]}@supabase.user"
            username = email.split('@')[0] if email else f"user_{str(user_id)[:8]}"

            base_username = username
            idx = 1
            while True:
                u_check = await db.execute(select(User).where(User.username == username))
                if not u_check.scalars().first():
                    break
                username = f"{base_username}{idx}"
                idx += 1

            new_user = User(
                id=user_id,
                email=user_email,
                username=username,
                supabase_uid=str(sub) if sub else None,
                is_verified=email_confirmed,
            )
            db.add(new_user)
            await db.commit()
            await db.refresh(new_user)
            return new_user
        except Exception:
            await db.rollback()

    return None

async def get_current_user(
    token: Optional[str] = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    user = await _resolve_user_from_token(token, db)
    if user is None:
        raise credentials_exception
    return user

async def get_current_user_optional(
    token: Optional[str] = Depends(oauth2_scheme_optional),
    db: AsyncSession = Depends(get_db)
) -> Optional[User]:
    """
    Optional authentication: returns the User object if a cryptographically verified token is present, 
    otherwise returns None without raising a 401 error.
    """
    return await _resolve_user_from_token(token, db)

