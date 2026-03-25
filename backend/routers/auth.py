from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from connection import get_db
from models import User
from auth_utils import get_password_hash, verify_password, create_access_token, get_current_user
from email_utils import send_verification_email
from utils.email import send_password_reset_email
import uuid
from typing import List
from pydantic import BaseModel, EmailStr
import random
import time
import json
from typing import Dict, Any

# Temporary in-memory store for OTPs
# Format: {email: {"otp": str, "expires": float}}
OTP_STORE: Dict[str, Dict[str, Any]] = {}

def generate_otp() -> str:
    """Generates a random 6-digit OTP."""
    return f"{random.randint(0, 999999):06d}"

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

@router.post("/forgot-password")
async def forgot_password(request: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    """
    Initiates password reset by generating a 6-digit OTP and printing it to the terminal.
    """
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalars().first()
    
    if user:
        otp = generate_otp()
        OTP_STORE[request.email] = {
            "otp": otp,
            "expires": time.time() + 900 # 15 minutes
        }
        
        # Call the real email utility
        send_password_reset_email(request.email, otp)
        
    # Always return success to avoid email enumeration
    return {"message": "If an account exists, an OTP has been sent to your email."}

@router.post("/reset-password")
async def reset_password(request: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    """
    Updates the user's password using a valid 6-digit OTP.
    """
    otp_data = OTP_STORE.get(request.email)
    
    if not otp_data:
        raise HTTPException(status_code=400, detail="No OTP found for this email block. Please request a new one.")
        
    if otp_data["otp"] != request.otp:
        raise HTTPException(status_code=400, detail="Invalid OTP. Please check and try again.")
        
    if time.time() > otp_data["expires"]:
        del OTP_STORE[request.email]
        raise HTTPException(status_code=400, detail="OTP has expired. Please request a new one.")
        
    # Valid OTP, update password
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalars().first()
    
    if not user:
        # This shouldn't happen if they have an OTP, but for safety:
        raise HTTPException(status_code=404, detail="User not found")
        
    # Update password
    user.hashed_password = get_password_hash(request.new_password)
    await db.commit()
    
    # Clear OTP from store
    del OTP_STORE[request.email]
    
    return {"message": "Password updated successfully. You can now log in with your new password."}

@router.post("/register")
async def register(user_data: UserCreate, db: AsyncSession = Depends(get_db)):
    try:
        # Sanitize and check password length (8 to 128 characters)
        if len(user_data.password) < 8 or len(user_data.password) > 128:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be between 8 and 128 characters"
            )

        # 1. Check if user already exists
        result = await db.execute(select(User).where(User.email == user_data.email))
        if result.scalars().first():
            raise HTTPException(status_code=400, detail="Email already registered")

        result = await db.execute(select(User).where(User.username == user_data.username))
        if result.scalars().first():
            raise HTTPException(status_code=400, detail="Username already taken")

        # 2. Create new user
        verification_token = str(uuid.uuid4())
        new_user = User(
            email=user_data.email,
            username=user_data.username,
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
        # Re-raise HTTPExceptions (like 400) to avoid catching them as general errors
        raise he
    except Exception as e:
        print(f"REGISTRATION ERROR: {str(e)}")
        # Rollback in case of DB error
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Registration failed: {str(e)}"
        )

@router.post("/login")
async def login(user_data: UserLogin, db: AsyncSession = Depends(get_db)):
    # Sanitize and check password length
    if len(user_data.password) < 8 or len(user_data.password) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid password length"
        )

    # 1. Fetch user
    result = await db.execute(select(User).where(User.email == user_data.email))
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
        "favoriteArtists": user.favorite_artists
    }

@router.get("/me/artists-details")
async def get_user_artists_details(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Fetches the current user's favorite artists names from DB and 
    aggregates their details (id, name, image) from JioSaavn.
    """
    from services import saavn
    import asyncio
    
    # 1. Fetch user favorite_artists names
    result = await db.execute(select(User.favorite_artists).where(User.id == user.id))
    artists_json = result.scalar_one()
    
    try:
        artist_names = json.loads(artists_json)
    except:
        artist_names = []
        
    if not artist_names:
        return []

    # 2. Fetch details from Saavn for each artist
    async def get_artist_info(name):
        try:
            results = await saavn.search_artists(name)
            if results:
                best_match = results[0]
                return {
                    "id": best_match.get("id"),
                    "name": best_match.get("name"),
                    "image": best_match.get("imageUrl")
                }
        except:
            pass
        return {"id": name, "name": name, "image": ""}

    tasks = [get_artist_info(name) for name in artist_names]
    artist_details = await asyncio.gather(*tasks)
    
    return [a for a in artist_details if a]

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
