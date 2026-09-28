---
name: backend-guidelines
description: FastAPI backend conventions, error handling, request validation, authentication security, and rate limiting standards for Paatu Padava.
---

# Backend Engineering Guidelines (FastAPI & Python 3.13)

## 1. APIRouter Conventions & Modular Architecture
- Group routes strictly by functional domain:
  - `/api/music`: Audio stream resolution, search, catalog, lyrics, likes, smart shuffle.
  - `/api/auth`: Registration, login, Google OAuth, password reset, user session.
  - `/api/history`: Playback events, search queries, click-through tracking.
  - `/api/playlists`: Spotify URL preview, one-click catalog import.
  - `/api/users`: Export/import data, artist follows, account deletion.
- Always declare tags for automatic Swagger/OpenAPI documentation generation:
  ```python
  router = APIRouter(prefix="/api/music", tags=["music"])
  ```

## 2. Request Validation & Pydantic v2 Schemas
- Never accept unvalidated raw JSON dictionaries in route handlers.
- Use explicit Pydantic v2 `BaseModel` classes with type annotations, field constraints, and field descriptions:
  ```python
  from pydantic import BaseModel, Field

  class LikeSongRequest(BaseModel):
      yt_video_id: str = Field(..., min_length=5, max_length=100)
      title: str = Field(..., min_length=1, max_length=255)
      artist: str = Field(..., min_length=1, max_length=255)
      cover_url: str = Field(default="")
      audio_url: str = Field(default="")
      language: str = Field(default="tamil")
  ```

## 3. Error Handling & HTTP Status Codes
- Raise standard `HTTPException` with clear, actionable `detail` messages.
- Use precise HTTP status codes:
  - `200 OK`: Successful retrieval or synchronous mutation.
  - `201 Created`: Resource successfully created (registration, playlist creation).
  - `400 Bad Request`: Validation failure or malformed payload.
  - `401 Unauthorized`: Missing or invalid Bearer token.
  - `403 Forbidden`: Resource belongs to another user (security breach attempt).
  - `404 Not Found`: Track, artist, or playlist does not exist.
  - `429 Too Many Requests`: SlowAPI rate limit triggered.

## 4. Rate Limiting & Denial of Service Protection
- Apply SlowAPI limiters on sensitive or resource-intensive endpoints:
  ```python
  @router.post("/login")
  @limiter.limit("5/minute")
  async def login(request: Request, ...):
  ```
- Password reset OTP attempts must be strictly capped (`MAX_OTP_ATTEMPTS = 5`) with constant-time string comparison:
  ```python
  secrets.compare_digest(stored_otp, provided_otp)
  ```

## 5. Streaming & Media Decryption
- JioSaavn CDN direct streams are 320kbps AAC protected with DES cipher. Decrypt synchronously or via threadpool:
  ```python
  cipher = DES.new(SAAVN_SECRET_KEY, DES.MODE_ECB)
  decrypted_url = unpad(cipher.decrypt(base64.b64decode(enc_url)), 8).decode('utf-8')
  ```
- Always provide fallback to YouTube audio stream resolution when direct CDN link fails.

## 6. Testing & CI Verification
- Maintain 100% test pass rate for all unit and integration tests under `backend-data-hf/tests/`:
  ```bash
  python -m unittest discover -s backend-data-hf/tests -p "test_*.py"
  ```
