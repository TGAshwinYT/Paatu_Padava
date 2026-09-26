from jose import JWTError, jwt
from passlib.context import CryptContext
from datetime import datetime, timedelta
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
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def create_reset_password_token(email: str):
    """
    Creates a JWT token for password reset that expires in 15 minutes.
    """
    to_encode = {"sub": email, "type": "reset_password"}
    expire = datetime.utcnow() + timedelta(minutes=15)
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

async def _resolve_user_from_token_or_headers(
    token: Optional[str],
    x_user_id: Optional[str],
    x_user_email: Optional[str],
    db: AsyncSession
) -> Optional[User]:
    """
    Unified user resolution supporting:
    1. Local custom JWT (FastAPI web client signed with JWT_SECRET)
    2. Supabase Auth JWT (Mobile client token containing sub & email)
    3. Explicit X-User-ID / X-User-Email service headers
    """
    sub = None
    email = None

    if token:
        # Try local JWT secret verification
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
            email = payload.get("sub")
        except JWTError:
            # Fallback: Parse Supabase JWT claims
            try:
                claims = jwt.get_unverified_claims(token)
                email = claims.get("email")
                sub = claims.get("sub")
            except Exception:
                pass

    if not email and x_user_email:
        email = x_user_email
    if not sub and x_user_id:
        sub = x_user_id

    # 1. Lookup by Email
    if email:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalars().first()
        if user:
            return user

    # 2. Lookup by UUID / sub
    if sub:
        try:
            u_uuid = uuid.UUID(sub)
            result = await db.execute(select(User).where(User.id == u_uuid))
            user = result.scalars().first()
            if user:
                return user
        except Exception:
            pass

    # 3. Auto-provision in public.users if authenticated via Supabase
    if email or sub:
        try:
            user_id = uuid.UUID(sub) if sub else uuid.uuid4()
            user_email = email or f"user_{str(user_id)[:8]}@supabase.user"
            username = email.split('@')[0] if email else f"user_{str(user_id)[:8]}"
            new_user = User(
                id=user_id,
                email=user_email,
                username=username,
                is_verified=True,
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
    x_user_id: Optional[str] = Header(None, alias="X-User-ID"),
    x_user_email: Optional[str] = Header(None, alias="X-User-Email"),
    db: AsyncSession = Depends(get_db)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    user = await _resolve_user_from_token_or_headers(token, x_user_id, x_user_email, db)
    if user is None:
        raise credentials_exception
    return user

async def get_current_user_optional(
    token: Optional[str] = Depends(oauth2_scheme_optional),
    x_user_id: Optional[str] = Header(None, alias="X-User-ID"),
    x_user_email: Optional[str] = Header(None, alias="X-User-Email"),
    db: AsyncSession = Depends(get_db)
) -> Optional[User]:
    """
    Optional authentication: returns the User object if a valid token or user identity is present, 
    otherwise returns None without raising a 401 error.
    """
    return await _resolve_user_from_token_or_headers(token, x_user_id, x_user_email, db)

