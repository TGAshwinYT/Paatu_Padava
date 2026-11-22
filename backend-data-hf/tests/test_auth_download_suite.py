"""
Regression and Security Test Suite for Auth, Token Refresh, Download, and Utils.
Covers:
- Password verification handling of None (Google-only accounts)
- /api/auth/login behavior for normal and Google-only users
- /api/auth/refresh grace period and expiration semantics
- /api/auth/register sanitization and exception masking
- /api/music/download Latin-1 header safety for Tamil / Unicode titles (RFC 6266)
- /api/music/liked pagination bounds enforcement
- /api/test-location SSRF / X-Forwarded-For sanitization & authentication
- /api/config/scraper/report-failure authentication
"""

import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch
import urllib.parse
from datetime import datetime, timedelta, timezone

# Ensure backend-data-hf directory is in Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

if not os.environ.get("JWT_SECRET"):
    os.environ["JWT_SECRET"] = "test_jwt_secret_for_ci_and_local_testing_minimum_32_chars"

import jwt
from fastapi.testclient import TestClient
from main import app
from connection import get_db, get_redis
from auth_utils import (
    verify_password,
    get_password_hash,
    create_access_token,
    SECRET_KEY,
    ALGORITHM,
    get_current_user,
)
from models import User
from services.download_service import create_download_streaming_response


class TestAuthAndVerifyPassword(unittest.TestCase):
    """Verifies Argon2 password hashing and Google-only user protection."""

    def test_verify_password_with_valid_hash(self):
        password = "SecurePassword123!"
        hashed = get_password_hash(password)
        self.assertTrue(verify_password(password, hashed))
        self.assertFalse(verify_password("WrongPassword123!", hashed))

    def test_verify_password_with_none_hashed_password(self):
        """Google-only accounts store hashed_password as None and must never crash with 500."""
        self.assertFalse(verify_password("SomePassword123!", None))
        self.assertFalse(verify_password("", None))
        self.assertFalse(verify_password(None, None))
        self.assertFalse(verify_password(None, "some_hash"))

    def test_verify_password_with_invalid_hash_string(self):
        """Malformed hash strings must return False without raising unhandled exceptions."""
        self.assertFalse(verify_password("SomePassword123!", "not_a_valid_argon2_hash"))
        self.assertFalse(verify_password("SomePassword123!", ""))


class TestAuthEndpointsIntegration(unittest.TestCase):
    """Tests /api/auth/login, /api/auth/refresh, and /api/auth/register."""

    def setUp(self):
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_login_google_only_user_returns_401_not_500(self):
        """A user registered exclusively via Google OAuth has hashed_password=None.
        Attempting password login must return 401 Unauthorized, never 500 Internal Server Error."""
        mock_user = User(
            email="google_user@example.com",
            username="google_user",
            hashed_password=None,  # Google-only user
            google_id="google_sub_12345",
            is_verified=True,
        )

        mock_session = AsyncMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = mock_user
        mock_result = MagicMock()
        mock_result.scalars.return_value = mock_scalars
        mock_session.execute.return_value = mock_result

        async def override_get_db():
            yield mock_session

        app.dependency_overrides[get_db] = override_get_db

        response = self.client.post(
            "/api/auth/login",
            json={"email": "google_user@example.com", "password": "RandomPassword123!"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json().get("detail"), "Incorrect email or password")

    def test_login_successful_with_password(self):
        """Regular user with valid Argon2 password logs in successfully with 200."""
        raw_password = "ValidPassword123!"
        hashed = get_password_hash(raw_password)
        mock_user = User(
            email="regular_user@example.com",
            username="regular_user",
            hashed_password=hashed,
            is_verified=True,
        )

        mock_session = AsyncMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = mock_user
        mock_result = MagicMock()
        mock_result.scalars.return_value = mock_scalars
        mock_session.execute.return_value = mock_result

        async def override_get_db():
            yield mock_session

        app.dependency_overrides[get_db] = override_get_db

        response = self.client.post(
            "/api/auth/login",
            json={"email": "regular_user@example.com", "password": raw_password},
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("access_token", data)
        self.assertEqual(data.get("token_type"), "bearer")
        self.assertEqual(data.get("user", {}).get("email"), "regular_user@example.com")

    def test_login_invalid_password_returns_401(self):
        raw_password = "ValidPassword123!"
        hashed = get_password_hash(raw_password)
        mock_user = User(
            email="regular_user@example.com",
            username="regular_user",
            hashed_password=hashed,
            is_verified=True,
        )

        mock_session = AsyncMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = mock_user
        mock_result = MagicMock()
        mock_result.scalars.return_value = mock_scalars
        mock_session.execute.return_value = mock_result

        async def override_get_db():
            yield mock_session

        app.dependency_overrides[get_db] = override_get_db

        response = self.client.post(
            "/api/auth/login",
            json={"email": "regular_user@example.com", "password": "WrongPassword123!"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json().get("detail"), "Incorrect email or password")

    def test_refresh_token_valid(self):
        """Active or recently expired token (<48h) can be refreshed into a new JWT."""
        mock_user = User(
            email="refresh_user@example.com",
            username="refresh_user",
            hashed_password="hashed_placeholder",
            is_verified=True,
        )

        mock_session = AsyncMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = mock_user
        mock_result = MagicMock()
        mock_result.scalars.return_value = mock_scalars
        mock_session.execute.return_value = mock_result

        async def override_get_db():
            yield mock_session

        app.dependency_overrides[get_db] = override_get_db

        valid_token = create_access_token(data={"sub": "refresh_user@example.com"})

        response = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {valid_token}"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("access_token", response.json())

    def test_refresh_token_expired_beyond_48h_grace_period_rejected(self):
        """A token expired for more than 48 hours is strictly rejected with 401."""
        expired_ts = (datetime.now(timezone.utc) - timedelta(hours=49)).timestamp()
        expired_payload = {
            "sub": "old_user@example.com",
            "exp": expired_ts,
        }
        expired_token = jwt.encode(expired_payload, SECRET_KEY, algorithm=ALGORITHM)

        response = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {expired_token}"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertIn("renewal grace period", response.json().get("detail", ""))

    def test_register_masks_raw_internal_exception(self):
        """Database or unexpected exceptions during registration must never leak raw traceback text."""
        mock_session = AsyncMock()
        # Simulate an unexpected internal database error
        mock_session.execute.side_effect = Exception("FATAL: connection pool exhausted at postgresql://user:pass@secret_db:5432")

        async def override_get_db():
            yield mock_session

        app.dependency_overrides[get_db] = override_get_db

        response = self.client.post(
            "/api/auth/register",
            json={"email": "newuser@example.com", "username": "newuser", "password": "Password123!"},
        )
        self.assertEqual(response.status_code, 400)
        detail = response.json().get("detail", "")
        self.assertNotIn("secret_db", detail)
        self.assertNotIn("connection pool exhausted", detail)
        self.assertEqual(detail, "Registration failed. Please check your information and try again.")


class TestDownloadLatin1Headers(unittest.IsolatedAsyncioTestCase):
    """Verifies that song titles in Tamil and other non-Latin scripts do not crash /download with a 500."""

    async def test_tamil_song_title_content_disposition_is_strictly_latin1_encodable(self):
        """
        Tamil Unicode characters (e.g. 'ஆலப்போறான் தமிழன்') cannot be encoded in Latin-1.
        Headers must supply a sanitized ASCII fallback in filename= and percent-encoded UTF-8 in filename*=.
        """
        tamil_title = "ஆலப்போறான் தமிழன்"
        tamil_artist = "A.R. Rahman"
        dummy_audio_url = "https://snoidcdnems01.cdns.jio.com/audio/sample.mp3"

        # Mock upstream audio stream request
        mock_stream_response = AsyncMock()
        mock_stream_response.status_code = 200
        mock_stream_response.headers = {"content-length": "1048576"}
        async def mock_aiter(*args, **kwargs):
            yield b"FAKE_AUDIO_DATA_CHUNK"
        mock_stream_response.aiter_bytes = mock_aiter

        with patch("httpx.AsyncClient.send", return_value=mock_stream_response):
            response = await create_download_streaming_response(
                dummy_audio_url,
                title=tamil_title,
                artist=tamil_artist,
            )

            content_disp = response.headers.get("Content-Disposition")
            self.assertIsNotNone(content_disp)

            # 1. Critical Assertion: The header MUST be encodable as Latin-1 without raising UnicodeEncodeError!
            try:
                encoded_header = content_disp.encode("latin-1")
                self.assertIsInstance(encoded_header, bytes)
            except UnicodeEncodeError as e:
                self.fail(f"Content-Disposition header is not Latin-1 encodable: {e}")

            # 2. Verify filename= contains ASCII fallback
            self.assertIn('filename="Track - AR Rahman.mp3"', content_disp)

            # 3. Verify filename*= contains full percent-encoded Tamil title and artist
            expected_quoted = urllib.parse.quote(f"{tamil_title} - {tamil_artist}.mp3")
            self.assertIn(f"filename*=UTF-8''{expected_quoted}", content_disp)

    async def test_english_song_title_content_disposition(self):
        """Standard English titles preserve ASCII in both filename= and filename*=."""
        title = "Hukum - Thalaivar Alappara"
        artist = "Anirudh Ravichander"
        dummy_audio_url = "https://snoidcdnems01.cdns.jio.com/audio/sample.mp3"

        mock_stream_response = AsyncMock()
        mock_stream_response.status_code = 200
        mock_stream_response.headers = {}
        async def mock_aiter(*args, **kwargs):
            yield b"FAKE_AUDIO_DATA"
        mock_stream_response.aiter_bytes = mock_aiter

        with patch("httpx.AsyncClient.send", return_value=mock_stream_response):
            response = await create_download_streaming_response(
                dummy_audio_url,
                title=title,
                artist=artist,
            )
            content_disp = response.headers.get("Content-Disposition")
            self.assertIn('filename="Hukum - Thalaivar Alappara - Anirudh Ravichander.mp3"', content_disp)
            # Must encode to Latin-1 cleanly
            content_disp.encode("latin-1")


class TestSecurityAndUtilsEndpoints(unittest.TestCase):
    """Tests /api/music/liked bounds, /api/test-location, and /api/config/scraper/report-failure."""

    def setUp(self):
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_liked_songs_limit_capped(self):
        """Limit parameter on /api/music/liked must reject values > 100 with 422 validation error."""
        mock_user = User(
            email="liked_user@example.com",
            username="liked_user",
            is_verified=True,
        )
        app.dependency_overrides[get_current_user] = lambda: mock_user

        response = self.client.get("/api/music/liked?limit=101")
        self.assertEqual(response.status_code, 422)

        response_neg = self.client.get("/api/music/liked?limit=0")
        self.assertEqual(response_neg.status_code, 422)

        response_neg_offset = self.client.get("/api/music/liked?offset=-1")
        self.assertEqual(response_neg_offset.status_code, 422)

    def test_report_failure_requires_authentication(self):
        """POST /api/config/scraper/report-failure must reject unauthenticated requests with 401."""
        response = self.client.post(
            "/api/config/scraper/report-failure",
            json={"client_name": "ANDROID_VR", "reason": "Decryption failed"},
        )
        self.assertEqual(response.status_code, 401)

    def test_test_location_requires_authentication(self):
        """GET /api/test-location must reject unauthenticated requests with 401."""
        response = self.client.get("/api/test-location")
        self.assertEqual(response.status_code, 401)

    @patch("httpx.AsyncClient.get")
    def test_test_location_sanitizes_malicious_x_forwarded_for(self, mock_get):
        """Malicious X-Forwarded-For injection or SSRF targets must never be placed into outbound URL."""
        mock_user = User(
            email="admin_user@example.com",
            username="admin_user",
            is_verified=True,
        )
        app.dependency_overrides[get_current_user] = lambda: mock_user

        mock_resp = MagicMock()
        mock_resp.json.return_value = {
            "query": "1.2.3.4",
            "status": "success",
            "country": "India",
            "regionName": "Tamil Nadu",
            "city": "Chennai",
            "isp": "Jio",
        }
        mock_get.return_value = mock_resp

        # Inject SSRF payload in X-Forwarded-For
        self.client.get(
            "/api/test-location",
            headers={"X-Forwarded-For": "169.254.169.254/latest/meta-data"},
        )

        # Verify that the malicious URL string was NOT appended
        called_url = mock_get.call_args[0][0]
        self.assertEqual(called_url, "http://ip-api.com/json/")


if __name__ == "__main__":
    unittest.main()
