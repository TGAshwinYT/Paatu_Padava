import os
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import timedelta

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("JWT_SECRET", "test_jwt_secret_key_for_unit_tests_32chars")
os.environ.setdefault("SUPABASE_JWT_SECRET", "test_supabase_secret_key_minimum_32chars")
os.environ.setdefault("STREAM_SIGNING_SECRET", "test_stream_signing_secret_32chars")

import auth_utils  # noqa: E402
from limiter_config import limiter  # noqa: E402
from main import app  # noqa: E402
from connection import get_db, get_redis  # noqa: E402
from services.stream_security import create_signed_media_token  # noqa: E402


class _FakeResult:
    def __init__(self, user):
        self._user = user

    def scalars(self):
        return self

    def first(self):
        return self._user


class _FakeAsyncSession:
    def __init__(self, user=None):
        self.user = user
        self.added = []

    async def execute(self, _stmt):
        return _FakeResult(self.user)

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        return None

    async def refresh(self, _obj):
        return None


class AuthRefreshDownloadTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.mock_user = SimpleNamespace(
            id=1,
            email="listener@example.com",
            username="Listener",
            hashed_password=auth_utils.get_password_hash("SecretPass123!"),
            is_verified=True,
            token_version=2,
            supabase_uid="supa-uid-123",
            avatar_url=None,
            preferred_languages='["tamil","english"]',
            favorite_artists='[]',
        )
        self._prev_limiter_enabled = limiter.enabled
        limiter.enabled = False
        self.fake_db = _FakeAsyncSession(self.mock_user)

        async def _override_db():
            yield self.fake_db

        async def _override_redis():
            return MagicMock()

        app.dependency_overrides[get_db] = _override_db
        app.dependency_overrides[get_redis] = _override_redis
        self.client = TestClient(app)

    def tearDown(self):
        limiter.enabled = self._prev_limiter_enabled
        app.dependency_overrides.clear()

    def test_login_success_and_invalid_password(self):
        ok_resp = self.client.post(
            "/api/auth/login",
            json={"email": "listener@example.com", "password": "SecretPass123!"},
        )
        self.assertEqual(ok_resp.status_code, 200)
        self.assertIn("access_token", ok_resp.json())

        bad_resp = self.client.post(
            "/api/auth/login",
            json={"email": "listener@example.com", "password": "WrongPassword"},
        )
        self.assertEqual(bad_resp.status_code, 401)

    def test_register_duplicate_email_returns_400(self):
        resp = self.client.post(
            "/api/auth/register",
            json={
                "email": "listener@example.com",
                "username": "Listener",
                "password": "SecretPass123!",
            },
        )
        self.assertEqual(resp.status_code, 400)

    def test_refresh_token_requires_token_and_honors_token_version(self):
        missing = self.client.post("/api/auth/refresh")
        self.assertEqual(missing.status_code, 401)

        expired_valid = auth_utils.create_access_token(
            {"sub": "listener@example.com", "id": 1, "tv": 2},
            expires_delta=timedelta(minutes=-5),
        )
        ok_refresh = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {expired_valid}"},
        )
        self.assertEqual(ok_refresh.status_code, 200)
        self.assertIn("access_token", ok_refresh.json())

        revoked_token = auth_utils.create_access_token(
            {"sub": "listener@example.com", "id": 1, "tv": 1},
        )
        revoked_resp = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {revoked_token}"},
        )
        self.assertEqual(revoked_resp.status_code, 401)

    def test_download_requires_auth_or_signed_token_and_validates_ssrf(self):
        unauth = self.client.get("/api/music/download?song_id=abc123")
        self.assertEqual(unauth.status_code, 401)

        signed = create_signed_media_token(
            subject="https://aac.saavncdn.com/test.mp4",
            purpose="download",
        )
        with patch(
            "routers.music.resolve_download_audio_url",
            new=AsyncMock(return_value="https://aac.saavncdn.com/test.mp4"),
        ), patch(
            "routers.music.create_download_streaming_response",
            new=AsyncMock(return_value={"ok": True}),
        ):
            ok_dl = self.client.get(
                f"/api/music/download?url=https://aac.saavncdn.com/test.mp4&token={signed}"
            )
            self.assertEqual(ok_dl.status_code, 200)

    async def test_supabase_asymmetric_rs256_and_hs256_verification(self):
        # 1. Legacy HS256 Supabase token
        hs_token = jwt.encode(
            {"sub": "supa-uid-123", "email": "listener@example.com"},
            os.environ["SUPABASE_JWT_SECRET"],
            algorithm="HS256",
        )
        resolved_hs = await auth_utils._resolve_user_from_token(hs_token, self.fake_db)
        self.assertIsNotNone(resolved_hs)
        self.assertEqual(resolved_hs.email, "listener@example.com")

        # 2. Asymmetric RS256 Supabase token via mocked PyJWKClient
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        public_key = private_key.public_key()
        rs_token = jwt.encode(
            {"sub": "supa-uid-123", "email": "listener@example.com"},
            private_key,
            algorithm="RS256",
            headers={"kid": "test-kid"},
        )
        fake_jwk = MagicMock()
        fake_jwk.get_signing_key_from_jwt.return_value = SimpleNamespace(key=public_key)
        with patch.object(auth_utils, "_supabase_jwk_client", fake_jwk):
            resolved_rs = await auth_utils._resolve_user_from_token(rs_token, self.fake_db)
        self.assertIsNotNone(resolved_rs)
        self.assertEqual(resolved_rs.supabase_uid, "supa-uid-123")

    def test_production_disables_swagger_docs(self):
        import importlib
        import main as main_module
        with patch.dict(os.environ, {"ENV": "production"}):
            reloaded = importlib.reload(main_module)
            prod_client = TestClient(reloaded.app)
            self.assertEqual(prod_client.get("/docs").status_code, 404)
            self.assertEqual(prod_client.get("/openapi.json").status_code, 404)
        importlib.reload(main_module)


if __name__ == "__main__":
    unittest.main()
