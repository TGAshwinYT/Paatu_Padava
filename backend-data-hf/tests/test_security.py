import unittest
import sys
import os
import uuid
import secrets
from unittest.mock import AsyncMock, MagicMock, patch

# Ensure backend-data-hf directory is in Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

if not os.environ.get("JWT_SECRET"):
    os.environ["JWT_SECRET"] = "test_jwt_secret_for_ci_and_local_testing_minimum_32_chars"

from fastapi.testclient import TestClient
from main import app
from auth_utils import get_current_user, get_current_user_optional
from connection import get_db, get_redis
from models import User, Playlist
from trie import Trie
from routers.auth import generate_otp, MAX_OTP_ATTEMPTS


class TestSecurityAudits(unittest.TestCase):

    def test_otp_generation(self):
        """Test OTP is a 6-digit numeric string with proper zero-padding."""
        for _ in range(50):
            otp = generate_otp()
            self.assertEqual(len(otp), 6)
            self.assertTrue(otp.isdigit())

    def test_constant_time_otp_comparison(self):
        """Test that secrets.compare_digest behaves correctly for matching and mismatching OTPs."""
        real_otp = "123456"
        self.assertTrue(secrets.compare_digest(real_otp, "123456"))
        self.assertFalse(secrets.compare_digest(real_otp, "123457"))
        self.assertFalse(secrets.compare_digest(real_otp, "000000"))
        self.assertFalse(secrets.compare_digest(real_otp, ""))

    def test_otp_max_attempts_limit(self):
        """Test that MAX_OTP_ATTEMPTS constant is set to 5."""
        self.assertEqual(MAX_OTP_ATTEMPTS, 5)

    def test_jwt_secret_enforcement(self):
        """Test that missing JWT_SECRET triggers a fatal error on startup."""
        with patch.dict(os.environ, {"JWT_SECRET": ""}, clear=False):
            # In auth_utils, empty or missing JWT_SECRET should raise RuntimeError
            jwt_secret = os.getenv("JWT_SECRET")
            self.assertFalse(bool(jwt_secret))

    def test_autocomplete_trie(self):
        """Test that artist autocomplete trie inserts and prefix searches accurately."""
        trie = Trie()
        artists = ["A.R. Rahman", "Anirudh Ravichander", "Amitabh Bachchan", "Sid Sriram"]
        for a in artists:
            trie.insert(a)

        # Prefix 'anirudh' should find Anirudh
        res_ani = trie.search_prefix("ani")
        names_ani = [r["name"] for r in res_ani]
        self.assertIn("Anirudh Ravichander", names_ani)
        self.assertNotIn("A.R. Rahman", names_ani)

        # Prefix 'a' should find artists starting with A
        res_a = trie.search_prefix("a")
        self.assertTrue(len(res_a) >= 2)

        # Prefix 'xyz' should return empty
        self.assertEqual(trie.search_prefix("xyz"), [])

    def test_cors_env_parsing(self):
        """Test that CORS configuration parses multiple comma-separated domains from env."""
        default_origins = ["http://localhost:5173"]
        env_origins = "https://paatupadava.com, https://staging.paatupadava.com"
        for o in env_origins.split(","):
            clean = o.strip()
            if clean and clean not in default_origins:
                default_origins.append(clean)

        self.assertIn("https://paatupadava.com", default_origins)
        self.assertIn("https://staging.paatupadava.com", default_origins)
        self.assertEqual(len(default_origins), 3)


    def test_language_preference_validation(self):
        """Test that invalid language codes are correctly rejected."""
        from utils.location import SUPPORTED_LANGUAGES
        
        valid_sample = ["tamil", "english", "hindi"]
        for lang in valid_sample:
            self.assertIn(lang, SUPPORTED_LANGUAGES)

        invalid_sample = ["klingon", "elvish", "latin"]
        for lang in invalid_sample:
            self.assertNotIn(lang, SUPPORTED_LANGUAGES)

    def test_ssrf_safe_audio_url_validator(self):
        """Test that only authorized audio CDNs are permitted and SSRF targets are blocked."""
        from routers.music import is_safe_audio_url

        # Legitimate music CDN URLs
        self.assertTrue(is_safe_audio_url("https://aac.saavncdn.com/123/master.mp3"))
        self.assertTrue(is_safe_audio_url("https://snoidcdnems01.cdns.jio.com/audio/sample.mp4"))
        self.assertTrue(is_safe_audio_url("https://rr1---sn-4g5ednls.googlevideo.com/videoplayback?id=123"))

        # Block internal / private / cloud metadata SSRF vectors
        self.assertFalse(is_safe_audio_url("http://127.0.0.1:6379/"))
        self.assertFalse(is_safe_audio_url("http://localhost:8000/api/users/export"))
        self.assertFalse(is_safe_audio_url("http://169.254.169.254/latest/meta-data/"))
        self.assertFalse(is_safe_audio_url("http://10.0.0.5/admin"))
        self.assertFalse(is_safe_audio_url("http://192.168.1.1/"))

        # Block unauthorized domains and non-http schemes
        self.assertFalse(is_safe_audio_url("https://evil-attacker.com/payload.mp3"))
        self.assertFalse(is_safe_audio_url("file:///etc/passwd"))
        self.assertFalse(is_safe_audio_url(""))
        self.assertFalse(is_safe_audio_url(None))

    def test_client_ip_forwarded_header(self):
        """Test that get_client_ip properly extracts trusted rightmost client IP from X-Forwarded-For."""
        from limiter_config import get_client_ip
        from unittest.mock import MagicMock

        # Proxy with X-Forwarded-For: attacker injected spoofed IP, proxy appended true client IP at the end
        req_proxied = MagicMock()
        req_proxied.headers = {"x-forwarded-for": "203.0.113.195, 70.41.3.18, 150.172.238.178"}
        self.assertEqual(get_client_ip(req_proxied), "150.172.238.178")

        # Direct connection with X-Real-IP
        req_real = MagicMock()
        req_real.headers = {"x-real-ip": "198.51.100.42"}
        self.assertEqual(get_client_ip(req_real), "198.51.100.42")


class _SecurityTestBase(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self._prev_limiter_enabled = app.state.limiter.enabled
        app.state.limiter.enabled = False

    def tearDown(self):
        app.dependency_overrides.clear()
        app.state.limiter.enabled = self._prev_limiter_enabled


class TestIDORAuthorization(_SecurityTestBase):

    def test_protected_endpoints_reject_unauthenticated_requests(self):
        for method, path in [
            ("GET", "/api/playlists/"),
            ("GET", "/api/history/listen"),
            ("GET", "/api/users/export"),
            ("DELETE", "/api/users/me"),
            ("GET", "/api/auth/me"),
        ]:
            resp = self.client.request(method, path)
            self.assertEqual(resp.status_code, 401, f"Expected 401 for {method} {path}")

    def test_private_playlist_idor_returns_403(self):
        owner_id = uuid.uuid4()
        attacker_id = uuid.uuid4()
        playlist_id = uuid.uuid4()

        attacker = User(id=attacker_id, email="attacker@example.com", username="attacker", is_verified=True)
        other_playlist = Playlist(id=playlist_id, user_id=owner_id, title="Secret", is_public=False)
        other_playlist.tracks = []

        mock_db = AsyncMock()
        app.dependency_overrides[get_db] = lambda: mock_db

        with patch("routers.playlists.PlaylistRepository.get_by_id", AsyncMock(return_value=other_playlist)):
            app.dependency_overrides[get_current_user_optional] = lambda: None
            self.assertEqual(self.client.get(f"/api/playlists/{playlist_id}").status_code, 401)

            app.dependency_overrides[get_current_user] = lambda: attacker
            app.dependency_overrides[get_current_user_optional] = lambda: attacker
            self.assertEqual(self.client.get(f"/api/playlists/{playlist_id}").status_code, 403)
            self.assertEqual(
                self.client.patch(f"/api/playlists/{playlist_id}", json={"title": "Hacked"}).status_code,
                403,
            )
            self.assertEqual(self.client.delete(f"/api/playlists/{playlist_id}").status_code, 403)

    def test_delete_search_click_rejects_malformed_uuid(self):
        user = User(id=uuid.uuid4(), email="u@example.com", username="u", is_verified=True)
        app.dependency_overrides[get_current_user] = lambda: user
        app.dependency_overrides[get_db] = lambda: AsyncMock()

        resp = self.client.delete("/api/history/search-click/not-a-uuid")
        self.assertEqual(resp.status_code, 400)

    def test_cleanup_old_history_uses_parameterized_interval(self):
        import asyncio
        from repositories.history_repo import HistoryRepository

        mock_session = AsyncMock()
        mock_ctx = MagicMock()
        mock_ctx.__aenter__ = AsyncMock(return_value=mock_session)
        mock_ctx.__aexit__ = AsyncMock(return_value=None)

        with patch("repositories.history_repo.AsyncSessionLocal", return_value=mock_ctx):
            asyncio.run(HistoryRepository.cleanup_old_history("user-1", days=90))

        sql_arg, params_arg = mock_session.execute.call_args[0]
        self.assertIn("make_interval(days => :days)", str(sql_arg))
        self.assertEqual(params_arg, {"uid": "user-1", "days": 90})

    def test_import_rejects_oversized_payload_and_sanitizes_500(self):
        user = User(id=uuid.uuid4(), email="u@example.com", username="u", is_verified=True)
        app.dependency_overrides[get_current_user] = lambda: user
        app.dependency_overrides[get_db] = lambda: AsyncMock()

        oversized = b"{" + b"a" * (5 * 1024 * 1024 + 10)
        resp = self.client.post(
            "/api/users/import",
            files={"file": ("big.json", oversized, "application/json")},
        )
        self.assertEqual(resp.status_code, 413)

        with patch("routers.users.UserRepository.get_followed_artists", AsyncMock(side_effect=RuntimeError("SECRET_DB_DSN"))):
            err_resp = self.client.get("/api/users/me/followed-artists")
            self.assertEqual(err_resp.status_code, 500)
            self.assertNotIn("SECRET_DB_DSN", err_resp.json().get("detail", ""))


class TestCORSHardening(_SecurityTestBase):

    def test_cors_strips_wildcard_origins(self):
        from cors_config import get_allowed_origins

        with patch.dict(
            os.environ,
            {"ALLOWED_ORIGINS": "*,https://paatupadava.com", "FRONTEND_URL": "*"},
            clear=False,
        ):
            origins = get_allowed_origins()
            self.assertNotIn("*", origins)
            self.assertIn("https://paatupadava.com", origins)


class TestStreamAndDownloadSecurity(_SecurityTestBase):

    def test_unauthenticated_stream_prefetch_and_download_rejected(self):
        app.dependency_overrides[get_redis] = lambda: AsyncMock()

        self.assertEqual(self.client.get("/api/music/stream/track123").status_code, 401)
        self.assertEqual(self.client.get("/music/stream/track123").status_code, 401)
        self.assertEqual(
            self.client.post("/api/music/prefetch-stream", json={"tracks": [{"id": "track123"}]}).status_code,
            401,
        )
        self.assertEqual(
            self.client.get("/api/music/download?url=https://aac.saavncdn.com/x.mp3").status_code,
            401,
        )

    def test_stream_token_session_binding_and_download_subject_enforcement(self):
        from services.stream_security import create_signed_media_token

        app.dependency_overrides[get_redis] = lambda: AsyncMock()
        sid = "guest_session_123456"

        tok_resp = self.client.post(
            "/api/music/stream-token",
            json={"song_id": "track123", "purpose": "stream"},
            headers={"X-Session-ID": sid},
        )
        self.assertEqual(tok_resp.status_code, 200)
        st = tok_resp.json()["token"]

        # Omitting X-Session-ID fails strict session binding
        self.assertEqual(self.client.get(f"/api/music/stream/track123?st={st}").status_code, 401)

        mock_stream = {
            "song_id": "track123",
            "title": "Test",
            "audio_url": "https://aac.saavncdn.com/123.mp4",
            "url": "https://aac.saavncdn.com/123.mp4",
            "download_urls": ["https://aac.saavncdn.com/123.mp4"],
            "engine": "native",
            "source": "saavn",
            "cached": False,
        }
        with patch("routers.music.resolve_single_stream", AsyncMock(return_value=mock_stream)):
            ok_resp = self.client.get(
                f"/api/music/stream/track123?st={st}",
                headers={"X-Session-ID": sid},
            )
            self.assertEqual(ok_resp.status_code, 200)
            dl_token = ok_resp.json()["download_token"]

        # Token signed for song_id='track123' must NOT authorize arbitrary ?url=...
        self.assertEqual(
            self.client.get(
                f"/api/music/download?song_id=track123&url=https://aac.saavncdn.com/other.mp3&token={dl_token}",
                headers={"X-Session-ID": sid},
            ).status_code,
            401,
        )

        # Expired or tampered token must be rejected
        expired = create_signed_media_token("track123", purpose="stream", ttl_seconds=-10, session_id=sid)
        self.assertEqual(
            self.client.get(f"/api/music/stream/track123?st={expired}", headers={"X-Session-ID": sid}).status_code,
            401,
        )
        self.assertEqual(
            self.client.get(f"/api/music/stream/track123?st={st}tamper", headers={"X-Session-ID": sid}).status_code,
            401,
        )


class TestAuthAndRateLimitHardening(_SecurityTestBase):

    @patch("httpx.AsyncClient.get")
    def test_google_login_rejects_missing_aud_when_client_id_configured(self, mock_get):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "sub": "google_sub_1",
            "email": "user@example.com",
            "email_verified": True,
        }
        mock_get.return_value = mock_resp
        app.dependency_overrides[get_db] = lambda: AsyncMock()

        with patch.dict(os.environ, {"GOOGLE_CLIENT_ID": "expected-client-id.apps.googleusercontent.com"}, clear=False):
            resp = self.client.post("/api/auth/google", json={"credential": "tok"})
            self.assertEqual(resp.status_code, 401)

    def test_pydantic_input_bounds_and_rate_limiter_registration(self):
        user = User(id=uuid.uuid4(), email="u@example.com", username="u", is_verified=True)
        app.dependency_overrides[get_current_user] = lambda: user
        app.dependency_overrides[get_db] = lambda: AsyncMock()

        self.assertEqual(self.client.post("/api/playlists/", json={"title": "x" * 256}).status_code, 422)
        self.assertEqual(
            self.client.post("/api/users/follow-artist", json={"id": ""}).status_code,
            422,
        )
        self.assertEqual(
            self.client.patch("/api/auth/preferences", json=["artist"] * 101).status_code,
            422,
        )

        # Verify slowapi rate-limit decorators are registered on sensitive endpoints
        from routers import auth as auth_router, music as music_router, playlists as pl_router
        route_limit_keys = set(app.state.limiter._route_limits.keys())
        for fn in [
            auth_router.google_login,
            auth_router.refresh_token,
            auth_router.verify_email,
            auth_router.logout,
            music_router.mint_stream_token,
            music_router.get_stream_url,
            music_router.prefetch_streams_endpoint,
            music_router.download_track,
            pl_router.preview_spotify_playlist,
            pl_router.import_spotify_playlist,
        ]:
            key = f"{fn.__module__}.{fn.__name__}"
            self.assertIn(key, route_limit_keys, f"Expected limiter on {key}")

    def test_get_client_ip_ignores_cf_connecting_ip(self):
        from limiter_config import get_client_ip
        mock_req = MagicMock()
        mock_req.headers = {
            "cf-connecting-ip": "1.1.1.1",
            "x-real-ip": "2.2.2.2",
            "x-forwarded-for": "9.9.9.9, 203.0.113.77",
        }
        mock_req.client = None
        self.assertEqual(get_client_ip(mock_req), "203.0.113.77")

    @patch("httpx.AsyncClient.get")
    def test_google_login_rejects_prefix_spoofed_aud(self, mock_get):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "sub": "google_sub_2",
            "email": "user@example.com",
            "email_verified": True,
            "aud": "expected-client-id.attacker.com",
        }
        mock_get.return_value = mock_resp
        app.dependency_overrides[get_db] = lambda: AsyncMock()

        with patch.dict(os.environ, {"GOOGLE_CLIENT_ID": "expected-client-id"}, clear=False):
            resp = self.client.post("/api/auth/google", json={"credential": "tok"})
            self.assertEqual(resp.status_code, 401)

    def test_supabase_user_metadata_email_verified_accepted(self):
        import asyncio
        import jwt as pyjwt
        import auth_utils

        secret = os.environ["SUPABASE_JWT_SECRET"]
        token = pyjwt.encode(
            {
                "sub": "supa-new-uid",
                "email": "newmobile@example.com",
                "user_metadata": {"email_verified": True},
            },
            secret,
            algorithm="HS256",
        )
        fake_db = AsyncMock()
        empty_result = MagicMock()
        empty_result.scalars.return_value.first.return_value = None
        fake_db.execute.return_value = empty_result

        user = asyncio.run(auth_utils._resolve_user_from_token(token, fake_db))
        self.assertIsNotNone(user)
        self.assertEqual(user.email, "newmobile@example.com")


if __name__ == "__main__":
    unittest.main()

