import unittest
import sys
import os
from jose import jwt
from unittest.mock import MagicMock, AsyncMock, patch

# Ensure backend-data-hf directory is in Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from routers.music import (
    detect_script_language,
    TANGLISH_TRANSLITERATION_MAP,
    score_track_relevance,
    search_canonical_title,
)
from auth_utils import _resolve_user_from_token, SECRET_KEY, SUPABASE_JWT_SECRET


class TestSearchPipelineAndTrust(unittest.IsolatedAsyncioTestCase):

    def test_detect_script_language(self):
        """Test script detection across South Asian and Devanagari scripts."""
        self.assertEqual(detect_script_language("மீசைய முறுக்கு"), "tamil")
        self.assertEqual(detect_script_language("రాములో రాములా"), "telugu")
        self.assertEqual(detect_script_language("പുതുமഴ"), "malayalam")
        self.assertEqual(detect_script_language("ಬಾ ಬೆಳಕೆ"), "kannada")
        self.assertEqual(detect_script_language("केसरिया तेरा"), "hindi")
        self.assertIsNone(detect_script_language("Meesaya Murukku"))

    def test_tanglish_transliteration_dictionary(self):
        """Test real-world Tanglish typo transliterations."""
        self.assertEqual(TANGLISH_TRANSLITERATION_MAP.get("mesaya muruku"), "meesaya murukku")
        self.assertEqual(TANGLISH_TRANSLITERATION_MAP.get("mesaya murukku"), "meesaya murukku")
        self.assertEqual(TANGLISH_TRANSLITERATION_MAP.get("oorum blood"), "aarambam")
        self.assertEqual(TANGLISH_TRANSLITERATION_MAP.get("puthu mazha"), "puthumazha")

    def test_score_track_relevance_confidence_threshold(self):
        """Test exact studio release clears confidence bar (>= 70) and derivative noise is penalized."""
        clean_track = {
            "title": "Meesaya Murukku",
            "artist": "Hiphop Tamizha",
            "duration": 210,
            "is_studio": True,
            "language": "tamil",
        }
        score = score_track_relevance(clean_track, "meesaya murukku", ["tamil"])
        self.assertGreaterEqual(score, 70.0)

        # Derivative noise (slowed + reverb ringtone) receives strong penalties
        noisy_track = {
            "title": "Meesaya Murukku (Slowed + Reverb Whatsapp Status Ringtone)",
            "artist": "Unknown DJ",
            "duration": 40,
            "is_studio": False,
            "language": "tamil",
        }
        noisy_score = score_track_relevance(noisy_track, "meesaya murukku", ["tamil"])
        self.assertLess(noisy_score, 70.0)

    def test_canonical_title_version_preservation(self):
        """Test canonical grouping normalizes noise while preserving semantic version tags."""
        c1 = search_canonical_title("Meesaya Murukku Official Video Song HD 4K", "Hiphop Tamizha")
        c2 = search_canonical_title("Meesaya Murukku (From \"Meesaya Murukku\")", "Hiphop Tamizha")
        self.assertEqual(c1, c2)

        remix = search_canonical_title("Meesaya Murukku Remix", "Hiphop Tamizha")
        self.assertNotEqual(c1, remix)
        self.assertIn("remix", remix)

    async def test_cryptographic_token_verification_success(self):
        """Test cryptographic JWT token verification with valid signature."""
        user_id = 999
        payload = {"sub": str(user_id), "email": "artist@paatupaadava.com"}
        valid_token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")

        mock_db = AsyncMock()
        mock_user = MagicMock(id=user_id, email="artist@paatupaadava.com")
        mock_result = MagicMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = mock_user
        mock_result.scalars.return_value = mock_scalars
        mock_db.execute.return_value = mock_result

        user = await _resolve_user_from_token(valid_token, mock_db)
        self.assertIsNotNone(user)
        self.assertEqual(user.id, user_id)

    async def test_cryptographic_token_verification_rejects_forgery(self):
        """Test that tokens with forged or wrong signatures are cryptographically rejected."""
        user_id = 999
        payload = {"sub": str(user_id), "email": "hacker@evil.com"}
        forged_token = jwt.encode(payload, "wrong-secret-key-123", algorithm="HS256")

        mock_db = AsyncMock()
        user = await _resolve_user_from_token(forged_token, mock_db)
        self.assertIsNone(user)

    async def test_untrusted_client_headers_dropped(self):
        """Verify that _resolve_user_from_token requires Bearer token and rejects empty/None tokens."""
        mock_db = AsyncMock()
        user = await _resolve_user_from_token(None, mock_db)
        self.assertIsNone(user)


if __name__ == "__main__":
    unittest.main()
