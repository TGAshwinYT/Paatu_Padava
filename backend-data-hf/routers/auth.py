from fastapi import APIRouter, Body, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from connection import get_db, get_redis
from models import User
from auth_utils import get_password_hash, verify_password, create_access_token, get_current_user, get_current_user_optional
from email_utils import send_verification_email
from utils.email import send_password_reset_email
from limiter_config import limiter
from utils.location import SUPPORTED_LANGUAGES
import uuid
import random
import time
import json
import secrets
import logging
from typing import Annotated, Dict, Any, List, Optional
from pydantic import BaseModel, EmailStr, StringConstraints

logger = logging.getLogger(__name__)

# Fallback store for OTPs if Redis is unavailable
OTP_STORE: Dict[str, Dict[str, Any]] = {}
OTP_FAIL_STORE: Dict[str, int] = {}
OTP_LOCKOUT_STORE: Dict[str, float] = {}
MAX_OTP_ATTEMPTS = 5
OTP_TTL_SECONDS = 900  # 15 minutes
LOCKOUT_DURATION_SECONDS = 900  # 15 minutes

def generate_otp() -> str:
    """Generates a cryptographically secure random 6-digit OTP."""
    return f"{secrets.randbelow(1000000):06d}"

async def is_email_locked_out(clean_email: str, redis_client) -> bool:
    lockout_key = f"otp_lockout:{clean_email}"
    try:
        val = await redis_client.get(lockout_key)
        if val:
            return True
    except Exception:
        pass
    locked_until = OTP_LOCKOUT_STORE.get(clean_email)
    if locked_until:
        if time.time() < locked_until:
            return True
        else:
            OTP_LOCKOUT_STORE.pop(clean_email, None)
    return False

async def get_email_otp_fails(clean_email: str, redis_client) -> int:
    fails_key = f"otp_fails:{clean_email}"
    try:
        val = await redis_client.get(fails_key)
        if val is not None:
            return int(val)
    except Exception:
        pass
    return OTP_FAIL_STORE.get(clean_email, 0)

async def increment_email_otp_fails(clean_email: str, redis_client) -> int:
    fails_key = f"otp_fails:{clean_email}"
    try:
        new_fails = await redis_client.incr(fails_key)
        await redis_client.expire(fails_key, LOCKOUT_DURATION_SECONDS)
        return int(new_fails)
    except Exception:
        pass
    fails = OTP_FAIL_STORE.get(clean_email, 0) + 1
    OTP_FAIL_STORE[clean_email] = fails
    return fails

async def set_email_lockout(clean_email: str, redis_client):
    lockout_key = f"otp_lockout:{clean_email}"
    try:
        await redis_client.setex(lockout_key, LOCKOUT_DURATION_SECONDS, "1")
    except Exception:
        pass
    OTP_LOCKOUT_STORE[clean_email] = time.time() + LOCKOUT_DURATION_SECONDS

async def clear_email_otp_state(clean_email: str, redis_client):
    try:
        await redis_client.delete(f"otp:{clean_email}")
        await redis_client.delete(f"otp_fails:{clean_email}")
        await redis_client.delete(f"otp_lockout:{clean_email}")
    except Exception:
        pass
    OTP_STORE.pop(clean_email, None)
    OTP_FAIL_STORE.pop(clean_email, None)
    OTP_LOCKOUT_STORE.pop(clean_email, None)

router = APIRouter(prefix="/api/auth", tags=["auth"])

class UserCreate(BaseModel):
    email: EmailStr
    username: str
    password: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class ForgotPasswordRequest(BaseModel):
    email: EmailStr

class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str
    new_password: str

class GoogleLoginRequest(BaseModel):
    credential: str

@router.post("/google")
@limiter.limit("10/minute")
async def google_login(request: Request, body: GoogleLoginRequest, db: AsyncSession = Depends(get_db)):
    """
    Verifies a Google ID token or OAuth token with Google's tokeninfo API.
    Validates audience (aud) and email verification before authenticating user.
    """
    import httpx
    import os

    google_client_id = os.getenv("GOOGLE_CLIENT_ID")
    user_info = None

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            # 1. First attempt verification via Google ID token endpoint
            id_resp = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": body.credential},
            )
            if id_resp.status_code == 200:
                user_info = id_resp.json()
            else:
                # 2. Fall back to userinfo endpoint with access token
                userinfo_resp = await client.get(
                    "https://www.googleapis.com/oauth2/v3/userinfo",
                    headers={"Authorization": f"Bearer {body.credential}"}
                )
                if userinfo_resp.status_code == 200:
                    user_info = userinfo_resp.json()
                    # Also query tokeninfo with access token to verify aud/azp
                    access_tokeninfo_resp = await client.get(
                        "https://oauth2.googleapis.com/tokeninfo",
                        params={"access_token": body.credential},
                    )
                    if access_tokeninfo_resp.status_code == 200:
                        ati_data = access_tokeninfo_resp.json()
                        user_info["aud"] = ati_data.get("aud") or ati_data.get("azp")

        if not user_info:
            raise HTTPException(status_code=400, detail="Invalid Google token")

        # 3. Verify audience if GOOGLE_CLIENT_ID is configured
        if google_client_id:
            token_aud = user_info.get("aud") or user_info.get("azp")
            allowed_ids = [cid.strip() for cid in google_client_id.split(",") if cid.strip()]
            if not token_aud or not any(token_aud == cid or token_aud.startswith(cid) for cid in allowed_ids):
                raise HTTPException(status_code=401, detail="Google token was not issued for this application")

        # 4. Verify email is verified by Google
        email_verified = user_info.get("email_verified")
        if email_verified is False or str(email_verified).lower() == "false":
            raise HTTPException(status_code=403, detail="Google account email is not verified")

        email = user_info.get("email")
        if not email:
            raise HTTPException(status_code=400, detail="Google token didn't contain an email")
            
        # Check if user exists
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalars().first()
        
        if not user:
            # Create a new user for Google Sign-in
            google_id = user_info.get("sub")
            name = user_info.get("name", email.split("@")[0])
            picture = user_info.get("picture", "")
            
            # Generate a random username to avoid collisions on signup via Google
            base_username = name.replace(" ", "").lower()
            import re
            base_username = re.sub(r'[^a-z0-9]', '', base_username)
            if not base_username: 
                base_username = "user"
                
            username = base_username
            
            # Uniqueness check for username
            username_idx = 1
            while True:
                username_check = await db.execute(select(User).where(User.username == username))
                if not username_check.scalars().first():
                    break
                username = f"{base_username}{username_idx}"
                username_idx += 1
            
            user = User(
                email=email,
                username=username,
                hashed_password=None,  # No password for Google users
                google_id=google_id,
                avatar_url=picture,
                is_verified=True,     # Google emails are pre-verified
                verification_token=None
            )
            db.add(user)
            await db.commit()
            await db.refresh(user)
            
        # If user exists but logs in with Google, link account
        elif not user.google_id:
            # Prevent account pre-hijacking: if account was unverified, clear the attacker's password
            if not user.is_verified:
                user.hashed_password = None
                user.verification_token = None
            user.google_id = user_info.get("sub")
            user.avatar_url = user.avatar_url or user_info.get("picture", "")
            user.is_verified = True
            await db.commit()
            
        # Create token with token_version
        user_tv = getattr(user, "token_version", 1) or 1
        access_token = create_access_token(data={"sub": user.email, "tv": user_tv})
        return {
            "access_token": access_token, 
            "token_type": "bearer",
            "user": {
                "id": str(user.id),
                "email": user.email,
                "username": user.username,
                "avatar": user.avatar_url
            }
        }
        
    except httpx.RequestError as e:
        logger.warning("[AUTH] Google token verification network error: %s", e)
        raise HTTPException(status_code=500, detail="Unable to communicate with Google authentication service")

@router.post("/forgot-password")
@limiter.limit("3/minute")
async def forgot_password(
    request: Request,
    body: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
    redis_client = Depends(get_redis)
):
    """
    Initiates password reset by generating a cryptographically secure 6-digit OTP
    and sending it via email. Verifies user existence in database, but always returns
    a generic success message to prevent email enumeration.
    """
    clean_email = body.email.lower().strip()

    # 0. Check account lockout (per-email lockout to prevent brute-forcing)
    if await is_email_locked_out(clean_email, redis_client):
        logger.info("[AUTH] Password reset requested for locked-out account %s (suppressed)", clean_email)
        return {"message": "If an account exists, an OTP has been sent to your email."}

    # 1. Check if user actually exists in the database
    result = await db.execute(select(User).where(User.email == clean_email))
    user = result.scalars().first()

    if user:
        otp = generate_otp()
        otp_data = {
            "otp": otp,
            "expires": time.time() + OTP_TTL_SECONDS
        }
        key = f"otp:{clean_email}"
        try:
            await redis_client.setex(key, OTP_TTL_SECONDS, json.dumps(otp_data))
        except Exception as err:
            logger.warning("[AUTH] Redis setex failed for OTP, using in-memory fallback: %s", err)
            OTP_STORE[clean_email] = otp_data

        logger.info("[AUTH] Password reset OTP generated for verified account")
        send_password_reset_email(user.email, otp)
    else:
        logger.info("[AUTH] Password reset requested for unverified/non-existent account (suppressed)")

    # Always return success message to avoid email enumeration
    return {"message": "If an account exists, an OTP has been sent to your email."}


@router.post("/reset-password")
@limiter.limit("5/minute")
async def reset_password(
    request: Request,
    body: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db),
    redis_client = Depends(get_redis)
):
    """
    Updates user password using a valid 6-digit OTP.
    Enforces Redis-backed storage, rate limiting, constant-time comparison,
    and a 5-attempt per-email lockout to prevent brute-forcing across OTP regenerations.
    """
    clean_email = body.email.lower().strip()

    # 0. Check account lockout (per-email lockout)
    if await is_email_locked_out(clean_email, redis_client):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account is temporarily locked out due to too many failed OTP attempts. Please try again in 15 minutes."
        )

    key = f"otp:{clean_email}"

    otp_data = None
    try:
        raw_otp = await redis_client.get(key)
        if raw_otp:
            otp_data = json.loads(raw_otp) if isinstance(raw_otp, str) else raw_otp
    except Exception as err:
        logger.warning("[AUTH] Redis get failed for OTP, checking fallback store: %s", err)

    if not otp_data:
        otp_data = OTP_STORE.get(clean_email)

    if not otp_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No valid OTP found for this email or it has expired. Please request a new one."
        )

    # Check expiration
    if time.time() > otp_data.get("expires", 0):
        try:
            await redis_client.delete(key)
        except Exception:
            pass
        OTP_STORE.pop(clean_email, None)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP has expired. Please request a new one."
        )

    # Constant-time comparison to prevent timing attacks
    expected_otp = str(otp_data.get("otp", ""))
    provided_otp = str(body.otp).strip()
    if not secrets.compare_digest(expected_otp, provided_otp):
        # Track failed attempts per email across all OTP cycles
        fails = await increment_email_otp_fails(clean_email, redis_client)
        if fails >= MAX_OTP_ATTEMPTS:
            await set_email_lockout(clean_email, redis_client)
            try:
                await redis_client.delete(key)
            except Exception:
                pass
            OTP_STORE.pop(clean_email, None)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many failed attempts. Account is locked out for 15 minutes."
            )
        remaining = MAX_OTP_ATTEMPTS - fails
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid OTP. {remaining} attempt(s) remaining."
        )

    # Valid OTP verified - update user password
    result = await db.execute(select(User).where(User.email == clean_email))
    user = result.scalars().first()

    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if len(body.new_password) < 8 or len(body.new_password) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be between 8 and 128 characters"
        )

    user.hashed_password = get_password_hash(body.new_password)
    # Session revocation: increment token_version so all active tokens are immediately invalidated
    user.token_version = (user.token_version or 1) + 1
    await db.commit()

    # Clear OTP and failure count state upon successful password reset
    await clear_email_otp_state(clean_email, redis_client)

    return {"message": "Password updated successfully. You can now log in with your new password."}


@router.post("/register")
@limiter.limit("5/minute")
async def register(
    request: Request,
    user_data: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    try:
        # Sanitize and check password length (8 to 128 characters)
        if len(user_data.password) < 8 or len(user_data.password) > 128:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be between 8 and 128 characters"
            )

        # 1. Check if user already exists
        result = await db.execute(select(User).where(User.email == user_data.email.lower().strip()))
        if result.scalars().first():
            raise HTTPException(status_code=400, detail="Email already registered")

        result = await db.execute(select(User).where(User.username == user_data.username.strip()))
        if result.scalars().first():
            raise HTTPException(status_code=400, detail="Username already taken")

        # 2. Create new user
        verification_token = str(uuid.uuid4())
        new_user = User(
            email=user_data.email.lower().strip(),
            username=user_data.username.strip(),
            hashed_password=get_password_hash(user_data.password),
            verification_token=verification_token,
            is_verified=False
        )
        db.add(new_user)
        await db.commit()
        await db.refresh(new_user)

        # 3. Send mock verification email
        send_verification_email(new_user.email, verification_token)

        return {"message": "User registered successfully. Please check your email for the verification link.", "user_id": str(new_user.id)}
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"[AUTH] Registration error: {e}", exc_info=True)
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration failed. Please check your information and try again."
        )


@router.post("/login")
@limiter.limit("5/minute")
async def login(
    request: Request,
    user_data: UserLogin,
    db: AsyncSession = Depends(get_db)
):
    # Sanitize and check password length
    if len(user_data.password) < 8 or len(user_data.password) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid password length"
        )

    # 1. Fetch user
    result = await db.execute(select(User).where(User.email == user_data.email.lower().strip()))
    user = result.scalars().first()

    # 2. Verify (handles Google-only users where hashed_password is None gracefully without 500)
    if not user or not user.hashed_password or not verify_password(user_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3. Enforce email verification
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email is not verified. Please verify your email before logging in."
        )

    # 4. Create token with token_version for session tracking
    user_tv = getattr(user, "token_version", 1) or 1
    access_token = create_access_token(data={"sub": user.email, "tv": user_tv})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": str(user.id),
            "email": user.email,
            "username": user.username
        }
    }

@router.get("/me")
async def get_me(user: User = Depends(get_current_user)):
    """
    Returns the current authenticated user's profile.
    """
    return {
        "id": str(user.id),
        "email": user.email,
        "username": user.username,
        "favoriteArtists": user.favorite_artists,
        "preferredLanguages": user.preferred_languages
    }

@router.get("/me/artists-details")
async def get_user_artists_details(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Fetches the current user's favorite artists names from DB and 
    aggregates their details (id, name, image) from JioSaavn.
    Bulletproofed to handle null/empty preferences and API failures.
    """
    from services import youtube
    import asyncio
    import json
    
    try:
        # 1. Fetch user favorite_artists names
        result = await db.execute(select(User.favorite_artists).where(User.id == user.id))
        artists_json = result.scalar_one_or_none()
        
        # 🚨 BULLETPROOF CHECK 🚨
        if not artists_json or artists_json == "[]" or artists_json == "":
            return []
            
        try:
            artist_names = json.loads(artists_json)
            if not isinstance(artist_names, list):
                return []
        except:
            return []
            
        if not artist_names:
            return []

        # 2. Fetch details from Saavn for each artist
        async def get_artist_info(name):
            if not name: return None
            try:
                # Search for the artist to get their ID and Image from YouTube
                results = await youtube.search_artists_youtube(name, limit=1)
                if results:
                    best_match = results[0]
                    return {
                        "id": best_match.get("id"),
                        "name": best_match.get("name") or name,
                        "image": best_match.get("image") or ""
                    }
            except Exception as inner_e:
                print(f"Warning: Failed to fetch info for artist {name}: {inner_e}")
            
            # Fallback for individual artist failures
            return {"id": name, "name": name, "image": ""}

        tasks = [get_artist_info(name) for name in artist_names]
        artist_details = await asyncio.gather(*tasks)
        
        # Filter out invalid entries
        return [a for a in artist_details if a]
        
    except Exception as e:
        logger.error("Failed to fetch artists-details for user %s: %s", user.id, e)
        raise HTTPException(status_code=500, detail="Failed to fetch artist details")

@router.get("/verify/{token}")
@limiter.limit("10/minute")
async def verify_email(request: Request, token: str, db: AsyncSession = Depends(get_db)):
    """
    Verifies a user's email using the token sent via email.
    """
    result = await db.execute(select(User).where(User.verification_token == token))
    user = result.scalars().first()
    
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired verification token")
    
    user.is_verified = True
    user.verification_token = None # Clear token after verification
    await db.commit()
    
    return {"message": "Email verified successfully! You can now log in."}

@router.post("/logout")
@limiter.limit("10/minute")
async def logout(
    request: Request,
    user: Optional[User] = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Server-side session revocation: increments user.token_version so all active
    JWTs signed with older versions are immediately invalidated.
    """
    if user:
        user.token_version = (user.token_version or 1) + 1
        try:
            await db.commit()
        except Exception as e:
            logger.warning("[AUTH] Error committing token_version on logout: %s", e)
            await db.rollback()
    return {"message": "Successfully logged out"}

class RefreshTokenRequest(BaseModel):
    refresh_token: Optional[str] = None

@router.post("/refresh")
@limiter.limit("15/minute")
async def refresh_token(
    request: Request,
    body: Optional[RefreshTokenRequest] = None,
    db: AsyncSession = Depends(get_db)
):
    """
    Stateless silent token refresh:
    Extracts expired/current JWT token from Authorization header or body,
    verifies identity, checks token_version against revocation,
    and issues a fresh JWT without interrupting user session.
    """
    from auth_utils import jwt, JWTError, SECRET_KEY, ALGORITHM, create_access_token

    raw_token = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        raw_token = auth_header[7:].strip()
    elif body and body.refresh_token:
        raw_token = body.refresh_token.strip()

    if not raw_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization token or refresh token required"
        )

    try:
        from datetime import datetime, timezone
        # Decode token payload without enforcing expiration check so recently expired tokens can refresh
        payload = jwt.decode(raw_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": False})
        email: str = payload.get("sub")
        if not email:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")

        # Enforce max 48-hour renewal window from expiration timestamp
        exp = payload.get("exp")
        if exp is not None:
            now_ts = datetime.now(timezone.utc).timestamp()
            if now_ts - float(exp) > 172800:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Refresh token expired beyond renewal grace period (48h). Please log in again."
                )
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authorization token")

    # Verify user exists in database
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User account not found")

    user_tv = getattr(user, "token_version", 1) or 1
    token_tv = payload.get("tv")
    if token_tv is not None and token_tv != user_tv:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked. Please log in again.")
    if token_tv is None and user_tv > 1:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked. Please log in again.")

    new_token = create_access_token(data={"sub": user.email, "tv": user_tv})
    return {
        "access_token": new_token,
        "token_type": "bearer",
        "user": {
            "id": str(user.id),
            "email": user.email,
            "username": user.username,
            "avatar": user.avatar_url
        }
    }

@router.patch("/preferences")
async def update_preferences(
    artists: Annotated[List[Annotated[str, StringConstraints(max_length=100)]], Body(max_length=100)],
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Updates the user's favorite artists for personalized recommendations.
    """
    try:
        # Sync with DB instance
        result = await db.execute(select(User).where(User.id == user.id))
        db_user = result.scalar_one()
        
        db_user.favorite_artists = json.dumps(artists)
        await db.commit()
        return {"message": "Preferences updated", "artists": artists}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to save preferences")

@router.patch("/language-preferences")
@router.patch("/preferences/languages")
async def update_language_preferences(
    languages: Annotated[List[Annotated[str, StringConstraints(max_length=100)]], Body(max_length=100)],
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Updates the user's preferred languages for regional and personalized music.
    Validates against canonical SUPPORTED_LANGUAGES set.
    """
    if not languages:
        raise HTTPException(status_code=400, detail="At least one preferred language must be provided")

    clean_languages = [str(l).lower().strip() for l in languages if l]
    invalid_languages = [l for l in clean_languages if l not in SUPPORTED_LANGUAGES]
    if invalid_languages:
        raise HTTPException(
            status_code=400, 
            detail=f"Unsupported language(s): {', '.join(invalid_languages)}. Supported: {', '.join(SUPPORTED_LANGUAGES)}"
        )

    try:
        result = await db.execute(select(User).where(User.id == user.id))
        db_user = result.scalar_one()
        
        db_user.preferred_languages = json.dumps(clean_languages)
        await db.commit()
        return {"message": "Language preferences updated", "languages": clean_languages}
    except Exception as e:
        await db.rollback()
        logger.error("Failed to save language preferences: %s", e)
        raise HTTPException(status_code=500, detail="Failed to save language preferences")


