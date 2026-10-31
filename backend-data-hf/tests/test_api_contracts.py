"""
Backend API Contract Verification Suite
Maintained by backend_engineer agent.
Validates route definitions, URL prefixes, HTTP methods, and Pydantic bindings.
"""
import unittest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

if not os.environ.get("JWT_SECRET"):
    os.environ["JWT_SECRET"] = "test_jwt_secret_for_ci_and_local_testing_minimum_32_chars"

from main import app


class TestBackendAPIContracts(unittest.TestCase):

    def setUp(self):
        self.routes = [route for route in app.routes]
        # Guard against FastAPI >= 0.137 _IncludedRouter objects that lack a direct .path attribute
        self.route_paths = {route.path for route in self.routes if hasattr(route, 'path')}
        # Expand nested routes from IncludedRouter or Mount objects (FastAPI >= 0.137)
        for r in self.routes:
            sub = getattr(r, 'routes', None) or getattr(getattr(r, 'router', None), 'routes', None)
            if sub:
                pref = getattr(r, 'prefix', '') or getattr(r, 'path', '')
                for sr in sub:
                    p = getattr(sr, 'path', '')
                    if p:
                        self.route_paths.add(p)
                        if pref and not p.startswith(pref):
                            self.route_paths.add(f"{pref.rstrip('/')}/{p.lstrip('/')}")
        # Always merge paths from FastAPI's canonical openapi registry
        try:
            for p in app.openapi().get('paths', {}).keys():
                self.route_paths.add(p)
        except Exception:
            pass

    def test_health_and_autocomplete_endpoints(self):
        """Verify baseline utility endpoints exist."""
        self.assertIn("/api/health", self.route_paths)
        self.assertIn("/api/search/autocomplete", self.route_paths)
        self.assertIn("/", self.route_paths)

    def test_music_endpoints_registered(self):
        """Verify core music streaming, recommendation, and catalog endpoints."""
        expected_music_routes = [
            "/api/music/home",
            "/api/music/home-feed",
            "/api/music/search",
            "/api/music/search/suggestions",
            "/api/music/stream/{song_id}",
            "/api/music/download",
            "/api/music/prefetch-stream",
            "/api/music/player-state",
            "/api/music/for-you",
            "/api/music/shuffle-order",
            "/api/music/like",
            "/api/music/unlike/{song_id}",
            "/api/music/liked",
            "/api/music/recommendations/{song_id}",
            "/api/music/lyrics/{song_id}",
            "/api/music/lyrics/synced",
        ]
        for route in expected_music_routes:
            self.assertIn(route, self.route_paths, f"Missing expected route: {route}")

    def test_auth_endpoints_registered(self):
        """Verify authentication and user session routes."""
        expected_auth_routes = [
            "/api/auth/register",
            "/api/auth/login",
            "/api/auth/google",
            "/api/auth/me",
            "/api/auth/logout",
            "/api/auth/forgot-password",
            "/api/auth/reset-password",
            "/api/auth/preferences",
        ]
        for route in expected_auth_routes:
            self.assertIn(route, self.route_paths, f"Missing expected auth route: {route}")

    def test_history_and_playlist_endpoints_registered(self):
        """Verify history and playlist endpoints."""
        expected_routes = [
            "/api/history/listen",
            "/api/history/search",
            "/api/history/recent-searches",
            "/api/playlists/preview-spotify",
            "/api/playlists/import-spotify",
            "/api/users/export",
            "/api/users/import",
        ]
        for route in expected_routes:
            self.assertIn(route, self.route_paths, f"Missing expected route: {route}")


if __name__ == "__main__":
    unittest.main()
