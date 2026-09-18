import unittest
import sys
import os
from collections import defaultdict, Counter

# Ensure backend-data-hf directory is in Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from services.recommender import PersonalRecommender, canonical_title
from utils.location import resolve_user_languages, get_search_languages, get_user_search_languages, SUPPORTED_LANGUAGES, DEFAULT_APP_LANGUAGES


class MockUser:
    def __init__(self, id=1, preferred_languages=None):
        self.id = id
        self.preferred_languages = preferred_languages


class TestRecommenderEngine(unittest.TestCase):

    def setUp(self):
        self.recommender = PersonalRecommender()

        # Seed catalog
        for i in range(1, 6):
            sid = f"song_{i}"
            self.recommender.song_catalog[sid] = {
                "id": sid,
                "title": f"Test Song {i}",
                "artist": f"Artist {i}",
                "coverUrl": f"https://example.com/{i}.jpg",
                "cover_url": f"https://example.com/{i}.jpg",
                "audioUrl": f"https://example.com/{i}.mp3",
                "audio_url": f"https://example.com/{i}.mp3",
                "language": "tamil" if i <= 3 else "english"
            }

    def test_item_similarity_calculation(self):
        """Test co-occurrence scoring and normalized cosine similarity."""
        # Setup co-occurrence:
        # song_1 <-> song_2: co-occurred 10 times
        # song_1 <-> song_3: co-occurred 1 time
        self.recommender.co_occurrence["song_1"]["song_2"] = 10.0
        self.recommender.co_occurrence["song_2"]["song_1"] = 10.0
        self.recommender.co_occurrence["song_1"]["song_3"] = 1.0
        self.recommender.co_occurrence["song_3"]["song_1"] = 1.0

        self.recommender.item_frequencies["song_1"] = 12.0
        self.recommender.item_frequencies["song_2"] = 10.0
        self.recommender.item_frequencies["song_3"] = 5.0

        # Calculate similarities
        self.recommender.similarities = self.recommender._calculate_similarities(
            self.recommender.co_occurrence,
            self.recommender.item_frequencies
        )

        similar_to_1 = self.recommender.get_similar_songs("song_1", limit=5)
        self.assertTrue(len(similar_to_1) >= 2)
        # song_2 should be ranked higher than song_3
        self.assertEqual(similar_to_1[0]["id"], "song_2")
        self.assertEqual(similar_to_1[1]["id"], "song_3")

    def test_user_taste_recommendations(self):
        """Test that user taste profile drives personalized recommendations."""
        # Setup similarities: song_1 similar to song_2 (0.9), song_3 (0.3)
        self.recommender.similarities["song_1"] = [("song_2", 0.9), ("song_3", 0.3)]
        self.recommender.similarities["song_4"] = [("song_5", 0.8)]

        # User 10 has high affinity for song_1
        self.recommender.user_taste["10"]["song_1"] = 5.0
        # song_1 was already played recently
        self.recommender.user_recent_plays["10"].add("song_1")

        recs = self.recommender.get_personal_recommendations("10", limit=5)
        self.assertTrue(len(recs) > 0)
        # song_1 should NOT be recommended because it was played recently
        rec_ids = [r["id"] for r in recs]
        self.assertNotIn("song_1", rec_ids)
        # song_2 should be the top recommendation
        self.assertEqual(rec_ids[0], "song_2")

    def test_smart_shuffle_ordering(self):
        """Test greedy nearest-neighbor chain for smart shuffle."""
        # Define similarity graph: song_1 -> song_3 -> song_2 -> song_4
        self.recommender.similarities["song_1"] = [("song_3", 0.9), ("song_2", 0.4)]
        self.recommender.similarities["song_3"] = [("song_2", 0.85), ("song_4", 0.2)]
        self.recommender.similarities["song_2"] = [("song_4", 0.75), ("song_5", 0.1)]

        queue = ["song_1", "song_2", "song_3", "song_4", "song_5"]
        shuffled = self.recommender.get_shuffle_order(queue, current_song_id="song_1", user_id="10")

        # Must preserve exact set of songs without duplicates
        self.assertEqual(len(shuffled), len(queue))
        self.assertEqual(set(shuffled), set(queue))

        # First song must be current song
        self.assertEqual(shuffled[0], "song_1")
        # Next should follow highest similarity from song_1, which is song_3
        self.assertEqual(shuffled[1], "song_3")
        # Next should follow highest similarity from song_3, which is song_2
        self.assertEqual(shuffled[2], "song_2")
        # Next should follow highest similarity from song_2, which is song_4
        self.assertEqual(shuffled[3], "song_4")

    def test_smart_shuffle_fallback_empty_or_single(self):
        """Test shuffle behavior on edge case queue sizes."""
        self.assertEqual(self.recommender.get_shuffle_order([], None), [])
        self.assertEqual(self.recommender.get_shuffle_order(["song_1"], "song_1"), ["song_1"])

    def test_user_dominant_languages(self):
        """Test extraction of dominant languages from interaction history."""
        self.recommender.user_languages["42"] = Counter({
            "tamil": 15,
            "english": 8,
            "hindi": 2,
            "telugu": 1
        })
        dominant = self.recommender.get_user_dominant_languages("42", top_n=3)
        self.assertEqual(dominant, ["tamil", "english", "hindi"])

    def test_language_cascade_resolution(self):
        """Test explicit language preference resolution and neutral fallback."""
        # 1: User profile preference with comma string
        user1 = MockUser(id="user_1", preferred_languages="tamil,english")
        langs1 = get_user_search_languages(user1).split(",")
        self.assertEqual(langs1, ["tamil", "english"])

        # 2: User profile preference with JSON array
        user2 = MockUser(id="user_2", preferred_languages='["malayalam", "hindi"]')
        langs2 = get_user_search_languages(user2).split(",")
        self.assertEqual(langs2, ["malayalam", "hindi"])

        # 3: Logged out / guest user receives neutral multi-language mix
        langs_guest = get_user_search_languages(None).split(",")
        self.assertEqual(langs_guest, DEFAULT_APP_LANGUAGES.split(","))

        # 4: Backward-compat resolution check
        self.assertEqual(resolve_user_languages(user1), "tamil,english")
        self.assertEqual(get_search_languages(None), DEFAULT_APP_LANGUAGES)


    def test_add_co_occurrences(self):
        """Test symmetric co-occurrence accumulation and clique capping."""
        matrix = defaultdict(lambda: defaultdict(float))
        song_ids = [f"track_{i}" for i in range(50)]
        self.recommender._add_co_occurrences(song_ids, matrix, weight=2.0)

        # Should be symmetric
        self.assertEqual(matrix["track_0"]["track_1"], 2.0)
        self.assertEqual(matrix["track_1"]["track_0"], 2.0)

        # Because clique is capped at 30 items, track_35 should NOT have co-occurrences
        self.assertNotIn("track_35", matrix)

    def test_disconnected_shuffle_chain(self):
        """Test that shuffle visits all nodes across disconnected similarity clusters."""
        # Cluster 1: song_1 <-> song_2
        self.recommender.similarities["song_1"] = [("song_2", 0.9)]
        self.recommender.similarities["song_2"] = [("song_1", 0.9)]
        # Cluster 2: song_3 <-> song_4 (disconnected from Cluster 1)
        self.recommender.similarities["song_3"] = [("song_4", 0.8)]
        self.recommender.similarities["song_4"] = [("song_3", 0.8)]

        queue = ["song_1", "song_2", "song_3", "song_4"]
        shuffled = self.recommender.get_shuffle_order(queue, current_song_id="song_1")

        self.assertEqual(len(shuffled), 4)
        self.assertEqual(set(shuffled), set(queue))
        self.assertEqual(shuffled[0], "song_1")
        self.assertEqual(shuffled[1], "song_2")

    def test_model_columns(self):
        """Test that database models define required language and preference attributes."""
        import models
        user = models.User(username="test", email="test@example.com", hashed_password="hash", preferred_languages="tamil,english")
        self.assertEqual(user.preferred_languages, "tamil,english")

        lh = models.ListeningHistory(user_id=1, yt_video_id="abc", title="Title", artist="Artist", language="tamil")
        self.assertEqual(lh.language, "tamil")

        liked = models.LikedSong(user_id=1, yt_video_id="abc", title="Title", artist="Artist", language="tamil")
        self.assertEqual(liked.language, "tamil")

        click = models.SearchClickHistory(user_id=1, yt_video_id="abc", title="Title", artist="Artist", language="tamil")
        self.assertEqual(click.language, "tamil")

    def test_canonical_title_normalizer(self):
        """Test that canonical_title normalizes covers, remixes, and noise tokens."""
        t1 = canonical_title("Vaa Vaathi (Cover Song)", "RLE Soundcrew")
        t2 = canonical_title("Vaa Vaathi - Remix", "AJ Shangarjan")
        t3 = canonical_title("Vaa Vaathi (From 'Master') [Official Video]", "Anirudh Ravichander")
        self.assertEqual(t1, "vaa vaathi")
        self.assertEqual(t2, "vaa vaathi")
        self.assertEqual(t3, "vaa vaathi")

    def test_recommendations_deduplicate_canonical_titles(self):
        """Test that recommendations never return duplicate covers of the same canonical title."""
        # Add 3 versions of "Vaa Vaathi"
        self.recommender.song_catalog["seed"] = {
            "id": "seed", "title": "Master the Blaster", "artist": "Anirudh", "language": "tamil"
        }
        self.recommender.song_catalog["cov1"] = {
            "id": "cov1", "title": "Vaa Vaathi (Cover)", "artist": "Artist A", "language": "tamil"
        }
        self.recommender.song_catalog["cov2"] = {
            "id": "cov2", "title": "Vaa Vaathi Remix", "artist": "Artist B", "language": "tamil"
        }
        self.recommender.song_catalog["other"] = {
            "id": "other", "title": "Kutti Story", "artist": "Anirudh", "language": "tamil"
        }

        self.recommender.similarities["seed"] = [
            ("cov1", 0.95),
            ("cov2", 0.90),
            ("other", 0.85),
        ]

        results = self.recommender.get_similar_songs("seed", limit=5)
        # Should contain cov1 and other, but cov2 must be excluded as a duplicate canonical title!
        result_ids = [r["id"] for r in results]
        self.assertIn("cov1", result_ids)
        self.assertNotIn("cov2", result_ids)
        self.assertIn("other", result_ids)

    def test_two_tier_language_prioritization(self):
        """Test Tier 1 (selected) vs Tier 2 (listening history) vs excluded languages."""
        self.recommender.song_catalog["tamil_song"] = {
            "id": "tamil_song", "title": "Tamil Track", "artist": "Artist T", "language": "tamil"
        }
        self.recommender.song_catalog["telugu_song"] = {
            "id": "telugu_song", "title": "Telugu Track", "artist": "Artist Te", "language": "telugu"
        }
        self.recommender.song_catalog["hindi_song"] = {
            "id": "hindi_song", "title": "Hindi Track", "artist": "Artist H", "language": "hindi"
        }

        # User 99 has seed affinity
        self.recommender.user_taste["99"]["seed_song"] = 5.0
        self.recommender.similarities["seed_song"] = [
            ("tamil_song", 0.8),
            ("telugu_song", 0.8),
            ("hindi_song", 0.8),
        ]

        # Tier 1 selected = tamil
        # Tier 2 listening history = telugu (via user_languages)
        self.recommender.user_languages["99"] = Counter({"telugu": 10})

        # Hindi is neither selected nor in history -> must be excluded!
        recs = self.recommender.get_personal_recommendations("99", preferred_languages="tamil", limit=10)
        rec_ids = [r["id"] for r in recs]

        # Tamil (Tier 1) and Telugu (Tier 2) allowed
        self.assertIn("tamil_song", rec_ids)
        self.assertIn("telugu_song", rec_ids)
        # Hindi excluded
        self.assertNotIn("hindi_song", rec_ids)
        # Tamil should have higher weighted score than Telugu
        self.assertEqual(rec_ids[0], "tamil_song")

    def test_artist_diversity_capping(self):
        """Test that recommendations cap at max 2 songs per artist."""
        for i in range(1, 6):
            sid = f"ani_{i}"
            self.recommender.song_catalog[sid] = {
                "id": sid, "title": f"Song {i}", "artist": "Anirudh", "language": "tamil"
            }
        self.recommender.song_catalog["arr_1"] = {
            "id": "arr_1", "title": "Rahman Song 1", "artist": "A.R. Rahman", "language": "tamil"
        }

        self.recommender.user_taste["88"]["seed_ani"] = 10.0
        self.recommender.similarities["seed_ani"] = [
            ("ani_1", 0.9),
            ("ani_2", 0.85),
            ("ani_3", 0.8),
            ("ani_4", 0.75),
            ("arr_1", 0.7),
        ]

        recs = self.recommender.get_personal_recommendations("88", preferred_languages="tamil", limit=10)
        rec_ids = [r["id"] for r in recs]

        # Max 2 songs by Anirudh
        anirudh_count = sum(1 for r in recs if r.get("artist") == "Anirudh")
        self.assertLessEqual(anirudh_count, 2)
        # Rahman should be included thanks to diversity
        self.assertIn("arr_1", rec_ids)

    def test_stream_resolution_and_caching(self):
        """Test stream resolution logic and Redis caching behavior."""
        import asyncio
        from routers.music import resolve_single_stream
        
        class MockRedis:
            def __init__(self):
                self.store = {}
            async def get(self, key):
                return self.store.get(key)
            async def setex(self, key, ttl, value):
                self.store[key] = value

        mock_redis = MockRedis()
        
        # Test resolution with YouTube fallback when no saavn match
        res = asyncio.run(resolve_single_stream("yt_video_123", "NonExistentSongXYZ12345", "UnknownArtistXYZ", mock_redis))
        self.assertEqual(res["song_id"], "yt_video_123")
        self.assertEqual(res["engine"], "youtube")
        self.assertFalse(res["cached"])

        # Second call must hit mock Redis cache
        res_cached = asyncio.run(resolve_single_stream("yt_video_123", redis_client=mock_redis))
        self.assertEqual(res_cached["song_id"], "yt_video_123")
        self.assertTrue(res_cached.get("cached"))


if __name__ == "__main__":
    unittest.main()

