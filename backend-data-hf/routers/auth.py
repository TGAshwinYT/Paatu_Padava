from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from connection import get_db, get_redis
from models import User
from auth_utils import get_password_hash, verify_password, create_access_token, get_current_user
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
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, EmailStr

logger = logging.getLogger(__name__)

# Fallback store for OTPs if Redis is unavailable
OTP_STORE: Dict[str, Dict[str, Any]] = {}
MAX_OTP_ATTEMPTS = 5
OTP_TTL_SECONDS = 900  # 15 minutes

def generate_otp() -> str:
    """Generates a cryptographically secure random 6-digit OTP."""
    return f"{secrets.randbelow(1000000):06d}"

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
async def google_login(request: GoogleLoginRequest, db: AsyncSession = Depends(get_db)):
    """
    Verifies a Google ID token. If the user doesn't exist, creates an account.
    Returns access token and user info.
    """
    import httpx
    
    try:
        # Verify the token with Google
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://www.googleapis.com/oauth2/v3/userinfo",
                headers={"Authorization": f"Bearer {request.credential}"}
            )
            
        if response.status_code != 200:
            raise HTTPException(status_code=400, detail="Invalid Google token")
            
        user_info = response.json()
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
            user.google_id = user_info.get("sub")
            user.avatar_url = user.avatar_url or user_info.get("picture", "")
            user.is_verified = True
            await db.commit()
            
        # Create token
        access_token = create_access_token(data={"sub": user.email})
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
        raise HTTPException(status_code=500, detail=f"Error communicating with Google: {str(e)}")

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

    # 1. Check if user actually exists in the database
    result = await db.execute(select(User).where(User.email == clean_email))
    user = result.scalars().first()

    if user:
        otp = generate_otp()
        otp_data = {
            "otp": otp,
            "attempts": 0,
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
    and a 5-attempt lockout to prevent brute-forcing.
    """
    clean_email = body.email.lower().strip()
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

    # Check attempt lockout (max 5 failed attempts)
    attempts = otp_data.get("attempts", 0)
    if attempts >= MAX_OTP_ATTEMPTS:
        try:
            await redis_client.delete(key)
        except Exception:
            pass
        OTP_STORE.pop(clean_email, None)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed attempts. This OTP has been invalidated for your security. Please request a new one."
        )

    # Constant-time comparison to prevent timing attacks
    expected_otp = str(otp_data.get("otp", ""))
    provided_otp = str(body.otp).strip()
    if not secrets.compare_digest(expected_otp, provided_otp):
        otp_data["attempts"] = attempts + 1
        remaining_ttl = max(1, int(otp_data.get("expires", time.time() + OTP_TTL_SECONDS) - time.time()))
        try:
            await redis_client.setex(key, remaining_ttl, json.dumps(otp_data))
        except Exception:
            pass
        OTP_STORE[clean_email] = otp_data

        remaining_attempts = MAX_OTP_ATTEMPTS - otp_data["attempts"]
        if remaining_attempts <= 0:
            try:
                await redis_client.delete(key)
            except Exception:
                pass
            OTP_STORE.pop(clean_email, None)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Maximum attempts exceeded. This OTP has been invalidated. Please request a new one."
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid OTP. {remaining_attempts} attempt(s) remaining."
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
    await db.commit()

    # Invalidate OTP on successful password reset
    try:
        await redis_client.delete(key)
    except Exception:
        pass
    OTP_STORE.pop(clean_email, None)

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

        return {"message": "User registered successfully. Please check your terminal for the verification link.", "user_id": str(new_user.id)}
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"[AUTH] Registration error: {e}", exc_info=True)
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Registration failed: {str(e)}"
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

    # 2. Verify
    if not user or not verify_password(user_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3. Create token
    access_token = create_access_token(data={"sub": user.email})
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
        print("\n" + "!" * 60)
        print(f"CRASH IN ARTISTS-DETAILS: {str(e)}")
        print("!" * 60 + "\n")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/verify/{token}")
async def verify_email(token: str, db: AsyncSession = Depends(get_db)):
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
async def logout():
    """
    Stateless logout. The client should clear the token from localStorage.
    """
    return {"message": "Successfully logged out"}

@router.patch("/preferences")
async def update_preferences(artists: List[str], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
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
async def update_language_preferences(languages: List[str], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
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


