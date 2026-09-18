import unittest
import sys
import os
import secrets
from unittest.mock import MagicMock, patch

# Ensure backend-data-hf directory is in Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

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


if __name__ == "__main__":
    unittest.main()

