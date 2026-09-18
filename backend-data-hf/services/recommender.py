import asyncio
import logging
import math
import random
import re
from collections import defaultdict, Counter
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional, Set, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

import models
from graph import recommendation_graph

logger = logging.getLogger(__name__)

# ==============================================================================
# CONFIGURABLE PARAMETERS & WEIGHTS (Easy to tune without touching logic)
# ==============================================================================
SESSION_WINDOW_MINUTES = 45          # Plays within 45m considered in the same session
SESSION_CO_OCCURRENCE_WEIGHT = 1.5   # Moderate positive signal for co-session plays
LIKED_CO_OCCURRENCE_WEIGHT = 3.0     # Strong explicit positive feedback between liked songs

LISTEN_AFFINITY_WEIGHT = 1.0         # Base weight for a listen event in taste profile
LIKE_AFFINITY_WEIGHT = 3.0          # Base weight for a like in taste profile

MAX_HISTORY_DAYS = 90               # Window listening events to last 90 days
MAX_EVENTS_PER_USER = 1000          # Window events per user to keep computation lightweight
REBUILD_INTERVAL_SECONDS = 1200     # Periodic background rebuild every 20 minutes


KNOWN_REGIONAL_LANGS = {
    "tamil", "telugu", "hindi", "malayalam", "kannada",
    "punjabi", "bengali", "marathi", "gujarati", "english"
}


def extract_language_from_title(title: str) -> Optional[str]:
    """
    Detects explicit language tags in track titles, e.g.:
      'Singari (From "Dude (Telugu)")' -> 'telugu'
      'Vaama Vaama (Telugu Version)' -> 'telugu'
      'Arabic Kuthu (Hindi)' -> 'hindi'
      'Hukum (Tamil)' -> 'tamil'
    """
    if not title:
        return None
    lower = title.lower()
    for lang in KNOWN_REGIONAL_LANGS:
        pattern = r'[\(\[\{\-\s]' + lang + r'[\)\]\}\s]|\b' + lang + r'\s*(version|song|audio|track|refix)?\b'
        if re.search(pattern, lower):
            return lang
    return None


def canonical_title(title: str, artist: str = "") -> str:
    """
    Normalizes song titles to a canonical key to deduplicate covers, remixes, refixes, and video editions.
    Example:
      'Vaa Vaathi (Cover Version)' -> 'vaa vaathi'
      'Vaa Vaathi Refix' -> 'vaa vaathi'
      'Vaa Vaathi - Official Video' -> 'vaa vaathi'
    """
    if not title:
        return ""
    t = str(title).lower()
    if artist:
        art_clean = re.sub(r'[^a-z0-9\s]', ' ', str(artist).lower()).strip()
        if art_clean and len(art_clean) > 2:
            t = t.replace(art_clean, ' ')
    # Strip parenthetical or bracketed text like (cover), (refix), (from "movie")
    t = re.sub(r'[\(\[\{].*?[\)\]\}]', ' ', t)
    # Strip common noise keywords
    t = re.sub(r'\b(feat\.|ft\.|official|video|audio|lyric|lyrical|cover|remix|refix|reprise|version|full video|song|hd|4k)\b', ' ', t, flags=re.IGNORECASE)
    t = re.sub(r'[^a-z0-9\s]', ' ', t)
    return ' '.join(t.split())


def _parse_lang_set(languages: Any) -> Set[str]:
    """Safely extracts a lowercase set of language codes from list, string, or json string."""
    if not languages:
        return set()
    if isinstance(languages, (list, set, tuple)):
        return {str(l).strip().lower() for l in languages if str(l).strip()}
    if isinstance(languages, str):
        s = languages.strip()
        if s.startswith("["):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, list):
                    return {str(l).strip().lower() for l in parsed if str(l).strip()}
            except Exception:
                pass
        return {l.strip().lower() for l in s.split(",") if l.strip()}
    return set()


class PersonalRecommender:
    """
    In-process item-item collaborative filtering engine.
    Learns from real listening sessions, liked songs, and search clicks.
    Operates 100% in-memory without external AI/LLM infrastructure.
    """

    def __init__(self):
        # Song metadata catalog: song_id -> song_dict
        self.song_catalog: Dict[str, Dict[str, Any]] = {}

        # Co-occurrence matrix: song_a -> {song_b: cumulative_weight}
        self.co_occurrence: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))

        # Item interaction frequencies: song_id -> cumulative_weight
        self.item_frequencies: Dict[str, float] = defaultdict(float)

        # Pre-calculated normalized item-item similarity: song_a -> [(song_b, similarity_score)]
        self.similarities: Dict[str, List[Tuple[str, float]]] = {}

        # Per-user taste profiles: user_id_str -> {song_id: affinity_score}
        self.user_taste: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))

        # Per-user language distribution: user_id_str -> Counter(language -> count)
        self.user_languages: Dict[str, Counter] = defaultdict(Counter)

        # Recent plays per user (to prevent immediate repeat recommendations): user_id_str -> set(song_id)
        self.user_recent_plays: Dict[str, Set[str]] = defaultdict(set)

        self.last_built_at: Optional[datetime] = None
        self._lock = asyncio.Lock()

    def _normalize_song_dict(self, song_id: str, title: str, artist: str, cover_url: Optional[str] = None,
                             audio_url: Optional[str] = None, language: Optional[str] = None) -> Dict[str, Any]:
        lang_str = str(language).lower().strip() if language else ""
        if not lang_str and title:
            lang_str = extract_language_from_title(title) or ""
        return {
            "id": song_id,
            "title": title or "Unknown Title",
            "artist": artist or "Unknown Artist",
            "coverUrl": cover_url or "",
            "cover_url": cover_url or "",
            "audioUrl": audio_url or "",
            "audio_url": audio_url or "",
            "language": lang_str
        }

    async def rebuild(self, db: AsyncSession):
        """
        Rebuilds the entire collaborative filtering model from PostgreSQL in one go.
        Builds into temporary local state and swaps atomically.
        """
        logger.info("[RECOMMENDER] Starting in-memory recommendation model rebuild...")
        start_time = datetime.now()

        new_catalog: Dict[str, Dict[str, Any]] = {}
        new_co_occurrence: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
        new_item_frequencies: Dict[str, float] = defaultdict(float)
        new_user_taste: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
        new_user_languages: Dict[str, Counter] = defaultdict(Counter)
        new_user_recent_plays: Dict[str, Set[str]] = defaultdict(set)

        cutoff_date = datetime.now(timezone.utc) - timedelta(days=MAX_HISTORY_DAYS)

        try:
            # 1. Fetch Listening History
            history_stmt = (
                select(models.ListeningHistory)
                .where(models.ListeningHistory.played_at >= cutoff_date)
                .order_by(models.ListeningHistory.user_id, models.ListeningHistory.played_at.asc())
            )
            history_result = await db.execute(history_stmt)
            history_records = history_result.scalars().all()

            # Group by user
            user_histories: Dict[str, List[models.ListeningHistory]] = defaultdict(list)
            for record in history_records:
                uid = str(record.user_id)
                user_histories[uid].append(record)
                
                # Catalog registration
                sid = record.yt_video_id
                if sid not in new_catalog:
                    new_catalog[sid] = self._normalize_song_dict(
                        sid, record.title, record.artist, record.cover_url, record.audio_url, getattr(record, 'language', None)
                    )
                elif not new_catalog[sid].get("audio_url") and record.audio_url:
                    new_catalog[sid]["audio_url"] = record.audio_url
                    new_catalog[sid]["audioUrl"] = record.audio_url

            # Process Sessions per User
            for uid, records in user_histories.items():
                if len(records) > MAX_EVENTS_PER_USER:
                    records = records[-MAX_EVENTS_PER_USER:]

                # Track recent plays (last 30 tracks)
                for rec in records[-30:]:
                    new_user_recent_plays[uid].add(rec.yt_video_id)

                current_session: List[str] = []
                last_time: Optional[datetime] = None

                for rec in records:
                    sid = rec.yt_video_id
                    new_user_taste[uid][sid] += LISTEN_AFFINITY_WEIGHT
                    new_item_frequencies[sid] += LISTEN_AFFINITY_WEIGHT

                    lang = getattr(rec, 'language', None)
                    if lang:
                        new_user_languages[uid][str(lang).lower().strip()] += 1

                    ptime = rec.played_at
                    if last_time is None or (ptime - last_time).total_seconds() <= (SESSION_WINDOW_MINUTES * 60):
                        current_session.append(sid)
                    else:
                        # Close session and build co-occurrences
                        self._add_co_occurrences(current_session, new_co_occurrence, SESSION_CO_OCCURRENCE_WEIGHT)
                        current_session = [sid]
                    last_time = ptime

                if current_session:
                    self._add_co_occurrences(current_session, new_co_occurrence, SESSION_CO_OCCURRENCE_WEIGHT)

            # 2. Fetch Liked Songs
            liked_stmt = select(models.LikedSong)
            liked_result = await db.execute(liked_stmt)
            liked_records = liked_result.scalars().all()

            user_likes: Dict[str, List[str]] = defaultdict(list)
            for like in liked_records:
                uid = str(like.user_id)
                sid = like.yt_video_id
                user_likes[uid].append(sid)

                new_user_taste[uid][sid] += LIKE_AFFINITY_WEIGHT
                new_item_frequencies[sid] += LIKE_AFFINITY_WEIGHT

                lang = getattr(like, 'language', None)
                if lang:
                    new_user_languages[uid][str(lang).lower().strip()] += 2 # Likes carry double weight for language

                if sid not in new_catalog:
                    new_catalog[sid] = self._normalize_song_dict(
                        sid, like.title, like.artist, like.cover_url, like.audio_url, getattr(like, 'language', None)
                    )
                elif not new_catalog[sid].get("audio_url") and like.audio_url:
                    new_catalog[sid]["audio_url"] = like.audio_url
                    new_catalog[sid]["audioUrl"] = like.audio_url

            for uid, liked_sids in user_likes.items():
                self._add_co_occurrences(liked_sids, new_co_occurrence, LIKED_CO_OCCURRENCE_WEIGHT)

            # 3. Fetch Search Click History (Catalog Registration ONLY, no co-occurrence or taste pollution)
            clicks_stmt = select(models.SearchClickHistory)
            clicks_result = await db.execute(clicks_stmt)
            clicks_records = clicks_result.scalars().all()

            for click in clicks_records:
                sid = click.yt_video_id
                if sid not in new_catalog:
                    new_catalog[sid] = self._normalize_song_dict(
                        sid, click.title, click.artist, click.cover_url, click.audio_url, getattr(click, 'language', None)
                    )
                elif not new_catalog[sid].get("audio_url") and click.audio_url:
                    new_catalog[sid]["audio_url"] = click.audio_url
                    new_catalog[sid]["audioUrl"] = click.audio_url

            # 4. Integrate Metadata Graph Songs into Catalog as Fallback Knowledge
            if recommendation_graph and hasattr(recommendation_graph, 'nodes'):
                for gid, node in recommendation_graph.nodes.items():
                    if gid not in new_catalog:
                        new_catalog[gid] = self._normalize_song_dict(
                            gid,
                            node.get("title") or node.get("name") or "Unknown",
                            node.get("artist") or "Unknown",
                            node.get("cover_url") or node.get("coverUrl"),
                            node.get("audio_url") or node.get("audioUrl"),
                            node.get("language")
                        )

            # 5. Compute Normalized Cosine Similarities
            new_similarities = self._calculate_similarities(new_co_occurrence, new_item_frequencies)

            # Atomic swap under lock
            async with self._lock:
                self.song_catalog = new_catalog
                self.co_occurrence = new_co_occurrence
                self.item_frequencies = new_item_frequencies
                self.similarities = new_similarities
                self.user_taste = new_user_taste
                self.user_languages = new_user_languages
                self.user_recent_plays = new_user_recent_plays
                self.last_built_at = datetime.now()

            elapsed = (datetime.now() - start_time).total_seconds()
            logger.info(
                f"[RECOMMENDER] Rebuild complete in {elapsed:.2f}s: "
                f"{len(new_catalog)} songs, {len(new_user_taste)} user profiles, "
                f"{len(new_similarities)} similarity nodes."
            )

        except Exception as e:
            err_str = str(e)
            if "tenant" in err_str.lower() or "not found" in err_str.lower() or "connection" in err_str.lower():
                logger.warning(
                    f"[RECOMMENDER] Database unavailable ({err_str.strip()}). "
                    f"Check if your Supabase project is paused or DATABASE_URL in .env is correct. "
                    f"Using cold-start & regional fallbacks until database connects."
                )
            else:
                logger.error(f"[RECOMMENDER ERROR] Rebuild failed: {e}", exc_info=True)

    def _calculate_similarities(self, co_occurrence: Dict[str, Dict[str, float]],
                                item_frequencies: Dict[str, float]) -> Dict[str, List[Tuple[str, float]]]:
        """Calculates normalized cosine similarities between items from co-occurrences."""
        similarities: Dict[str, List[Tuple[str, float]]] = {}
        for item_a, neighbors in co_occurrence.items():
            freq_a = item_frequencies.get(item_a, 1.0)
            sim_list = []
            for item_b, co_score in neighbors.items():
                if item_a == item_b:
                    continue
                freq_b = item_frequencies.get(item_b, 1.0)
                # Cosine normalization
                cosine_sim = co_score / (math.sqrt(freq_a * freq_b) + 1e-6)
                sim_list.append((item_b, cosine_sim))

            sim_list.sort(key=lambda x: x[1], reverse=True)
            similarities[item_a] = sim_list[:50] # Retain top 50 neighbors per item
        return similarities

    def _add_co_occurrences(self, song_ids: List[str], matrix: Dict[str, Dict[str, float]], weight: float):
        """Adds symmetric co-occurrences between every distinct pair in song_ids."""
        unique_ids = list(dict.fromkeys(song_ids)) # Preserve order, remove duplicates
        n = len(unique_ids)
        if n < 2:
            return
        # Cap clique size to avoid combinatorial blowup if a session or liked list has 100s of songs
        capped_ids = unique_ids[:30]
        for i in range(len(capped_ids)):
            for j in range(i + 1, len(capped_ids)):
                id1, id2 = capped_ids[i], capped_ids[j]
                matrix[id1][id2] += weight
                matrix[id2][id1] += weight

    # ==========================================================================
    # CAPABILITY 1: Item-Item Similar Songs
    # ==========================================================================
    def get_similar_songs(self, song_id: str, preferred_languages: Optional[str] = None,
                          user_id: Optional[str] = None, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Given a song_id, returns other behaviorally similar songs with canonical title deduplication
        and language prioritization.
        """
        neighbors = self.similarities.get(song_id, [])
        if not neighbors:
            return []

        tier1_langs: Set[str] = _parse_lang_set(preferred_languages)

        tier2_langs: Set[str] = set()
        if user_id:
            tier2_langs = set(self.get_user_dominant_languages(str(user_id)))

        allowed_langs = tier1_langs.union(tier2_langs)

        seed_song = self.song_catalog.get(song_id, {})
        seed_c_title = canonical_title(seed_song.get("title", ""), seed_song.get("artist", ""))
        seen_canonical_titles: Set[str] = {seed_c_title} if seed_c_title else set()
        artist_counts: Counter = Counter()
        if seed_song.get("artist"):
            artist_counts[str(seed_song.get("artist")).lower().strip()] += 1

        results = []
        for neighbor_id, score in neighbors:
            song = self.song_catalog.get(neighbor_id)
            if not song:
                continue

            song_lang = str(song.get("language", "")).lower().strip()
            if not song_lang:
                song_lang = extract_language_from_title(song.get("title", "")) or ""

            title_lang_tag = extract_language_from_title(song.get("title", ""))
            if allowed_langs:
                if song_lang and song_lang not in allowed_langs:
                    continue
                if title_lang_tag and title_lang_tag not in allowed_langs:
                    continue

            c_title = canonical_title(song.get("title", ""), song.get("artist", ""))
            if c_title and c_title in seen_canonical_titles:
                continue

            artist_key = str(song.get("artist", "")).lower().strip()
            if artist_key and artist_counts[artist_key] >= 2:
                continue

            results.append(song)
            if c_title:
                seen_canonical_titles.add(c_title)
            if artist_key:
                artist_counts[artist_key] += 1

            if len(results) >= limit:
                break

        return results

    # ==========================================================================
    # CAPABILITY 2: Personalized Taste Queue for a User (Spotify Smart Shuffle Style)
    # ==========================================================================
    def get_personal_recommendations(self, user_id: str, preferred_languages: Optional[str] = None,
                                     limit: int = 20) -> List[Dict[str, Any]]:
        """
        Given a user_id, returns a ranked, deduplicated, diverse personal queue.
        Enforces:
        1. Canonical title deduplication (no duplicate covers/remixes of the same song).
        2. Artist capping (max 2 songs per artist for Spotify Smart Shuffle diversity).
        3. Two-tier language prioritization (Tier 1 = selected languages, Tier 2 = listening history languages).
        """
        user_profile = self.user_taste.get(str(user_id))
        if not user_profile:
            return []

        # Tier 1: User explicitly preferred languages
        tier1_langs: Set[str] = _parse_lang_set(preferred_languages)

        # Tier 2: Languages the user has actually listened to in history
        tier2_langs = set(self.get_user_dominant_languages(str(user_id)))

        allowed_langs = tier1_langs.union(tier2_langs)

        # Find top 15 highest affinity seed songs for this user
        top_seeds = sorted(user_profile.items(), key=lambda x: x[1], reverse=True)[:15]
        if not top_seeds:
            return []

        recent_plays = self.user_recent_plays.get(str(user_id), set())
        candidate_scores: Dict[str, float] = defaultdict(float)

        for seed_id, seed_affinity in top_seeds:
            neighbors = self.similarities.get(seed_id, [])
            for neighbor_id, sim_score in neighbors[:25]:
                # Exclude songs user just listened to recently
                if neighbor_id in recent_plays:
                    continue
                candidate_scores[neighbor_id] += seed_affinity * sim_score

        # Also include user's top-affinity songs if candidates are sparse (exclude recent plays)
        if len(candidate_scores) < limit:
            for seed_id, seed_affinity in top_seeds:
                if seed_id not in candidate_scores and seed_id not in recent_plays:
                    candidate_scores[seed_id] = seed_affinity * 0.1

        # Apply Language Weights & Exclusions
        scored_candidates = []
        for cid, base_score in candidate_scores.items():
            song = self.song_catalog.get(cid)
            if not song:
                continue

            song_lang = str(song.get("language", "")).lower().strip()
            if song_lang:
                if tier1_langs and song_lang in tier1_langs:
                    mult = 1.5 # Strong preference for user's chosen languages
                elif song_lang in tier2_langs:
                    mult = 1.0 # Supported because user has listened to it in history
                elif allowed_langs:
                    # Known language outside both user preference & history -> Exclude!
                    continue
                else:
                    mult = 1.0
            else:
                mult = 0.8

            scored_candidates.append((cid, base_score * mult))

        scored_candidates.sort(key=lambda x: x[1], reverse=True)

        # Build results with Smart Shuffle diversity constraints
        seen_canonical_titles: Set[str] = set()
        artist_counts: Counter = Counter()
        results = []

        for cid, _ in scored_candidates:
            song = self.song_catalog[cid]
            c_title = canonical_title(song.get("title", ""), song.get("artist", ""))
            if c_title and c_title in seen_canonical_titles:
                continue

            artist_key = str(song.get("artist", "")).lower().strip()
            if artist_key and artist_counts[artist_key] >= 2:
                continue

            results.append(song)
            if c_title:
                seen_canonical_titles.add(c_title)
            if artist_key:
                artist_counts[artist_key] += 1

            if len(results) >= limit:
                break

        return results

    # ==========================================================================
    # CAPABILITY 3: Smart Greedy Nearest-Neighbor Shuffle Ordering
    # ==========================================================================
    def get_shuffle_order(self, queue_ids: List[str], current_song_id: Optional[str] = None,
                          user_id: Optional[str] = None) -> List[str]:
        """
        Orders queue_ids by constructing a greedy nearest-neighbor chain starting
        from current_song_id. Uses direct behavioral similarity first, then user's
        overall taste affinity, then falls back to random placement.
        """
        if not queue_ids or len(queue_ids) <= 1:
            return list(queue_ids)

        remaining: Set[str] = set(queue_ids)
        ordered: List[str] = []

        user_profile = self.user_taste.get(str(user_id), {}) if user_id else {}

        # Starting anchor
        last_id = current_song_id if (current_song_id and current_song_id in remaining) else None
        if last_id:
            ordered.append(last_id)
            remaining.remove(last_id)
        elif current_song_id:
            last_id = current_song_id

        while remaining:
            best_candidate: Optional[str] = None
            best_score = -1.0

            # 1. Search for highest similarity to last placed song
            if last_id and last_id in self.similarities:
                for neighbor_id, score in self.similarities[last_id]:
                    if neighbor_id in remaining:
                        best_candidate = neighbor_id
                        best_score = score
                        break

            # 2. Fallback: User taste affinity
            if not best_candidate and user_profile:
                taste_candidates = [
                    (cid, user_profile.get(cid, 0.0))
                    for cid in remaining if cid in user_profile
                ]
                if taste_candidates:
                    taste_candidates.sort(key=lambda x: x[1], reverse=True)
                    best_candidate = taste_candidates[0][0]

            # 3. Fallback: Random selection from remaining (guarantees Fisher-Yates equivalent)
            if not best_candidate:
                best_candidate = random.choice(list(remaining))

            ordered.append(best_candidate)
            remaining.remove(best_candidate)
            last_id = best_candidate

        return ordered

    # ==========================================================================
    # CAPABILITY 4: User Dominant Languages
    # ==========================================================================
    def get_user_dominant_languages(self, user_id: str, limit: Optional[int] = None,
                                   top_n: Optional[int] = None) -> List[str]:
        """
        Returns languages user has shown affinity for in listening/liked history,
        ordered by playback/like frequency.
        """
        n = top_n if top_n is not None else limit
        counter = self.user_languages.get(str(user_id))
        if not counter:
            return []
        items = counter.most_common(n) if n is not None else counter.most_common()
        return [lang for lang, count in items if lang]

    # ==========================================================================
    # CAPABILITY 5: Cold-Start Fallback Cascade
    # ==========================================================================
    async def get_cold_start_recommendations(self, db: AsyncSession, user: Optional[models.User],
                                            preferred_languages: Optional[str] = None,
                                            limit: int = 20) -> List[Dict[str, Any]]:
        """
        Provides a sensible, rich queue for users with no/little behavioral data:
        1. Followed / Favorite artists
        2. Metadata recommendation graph (matching language preference)
        3. YouTube Trending (regionalized by preferred language)
        Enforces canonical title deduplication and diversity.
        """
        results: List[Dict[str, Any]] = []
        seen_ids: Set[str] = set()
        seen_canonical_titles: Set[str] = set()
        artist_counts: Counter = Counter()

        pref_langs: Set[str] = set()
        if preferred_languages:
            pref_langs = _parse_lang_set(preferred_languages)
        elif user and hasattr(user, 'preferred_languages') and user.preferred_languages:
            pref_langs = _parse_lang_set(user.preferred_languages)

        def can_add(song_id: str, title: str, artist: str, lang: Optional[str] = None) -> bool:
            if song_id in seen_ids:
                return False
            if lang and pref_langs and str(lang).lower().strip() not in pref_langs:
                return False
            c_title = canonical_title(title, artist)
            if c_title and c_title in seen_canonical_titles:
                return False
            art_key = str(artist).lower().strip()
            if art_key and artist_counts[art_key] >= 2:
                return False
            return True

        def record_added(song: Dict[str, Any]):
            results.append(song)
            seen_ids.add(song["id"])
            c_title = canonical_title(song.get("title", ""), song.get("artist", ""))
            if c_title:
                seen_canonical_titles.add(c_title)
            art_key = str(song.get("artist", "")).lower().strip()
            if art_key:
                artist_counts[art_key] += 1

        # Step 1: Followed or Favorite Artists
        if user:
            fav_artists: List[str] = []
            try:
                import json
                if user.favorite_artists and user.favorite_artists != "[]":
                    fav_artists.extend(json.loads(user.favorite_artists))
            except Exception:
                pass

            # Also check user_followed_artists
            try:
                res = await db.execute(
                    select(models.Artist.name)
                    .join(models.user_followed_artists, models.Artist.id == models.user_followed_artists.c.artist_id)
                    .where(models.user_followed_artists.c.user_id == user.id)
                )
                followed_names = res.scalars().all()
                fav_artists.extend(followed_names)
            except Exception as e:
                logger.warning(f"[COLD-START] Error fetching followed artists: {e}")

            if fav_artists:
                fav_artists_lower = [a.lower().strip() for a in fav_artists if a]
                for song in self.song_catalog.values():
                    song_artist = song.get("artist", "").lower()
                    if any(fa in song_artist for fa in fav_artists_lower):
                        if can_add(song["id"], song.get("title", ""), song.get("artist", ""), song.get("language")):
                            record_added(song)
                            if len(results) >= limit:
                                return results

        # Step 2: Metadata graph songs matching language
        if len(results) < limit and recommendation_graph and hasattr(recommendation_graph, 'nodes'):
            for gid, node in recommendation_graph.nodes.items():
                node_lang = node.get("language")
                node_title = node.get("title") or node.get("name") or "Unknown"
                node_artist = node.get("artist") or "Unknown"
                if can_add(gid, node_title, node_artist, node_lang):
                    norm_song = self._normalize_song_dict(
                        gid,
                        node_title,
                        node_artist,
                        node.get("cover_url") or node.get("coverUrl"),
                        node.get("audio_url") or node.get("audioUrl"),
                        node_lang
                    )
                    record_added(norm_song)
                    if len(results) >= limit:
                        return results

        # Step 3: Regional YouTube Trending
        if len(results) < limit:
            try:
                from services.youtube import get_trending_youtube
                trending = await get_trending_youtube('IN' if any(l in ('tamil', 'telugu', 'hindi', 'malayalam', 'kannada', 'punjabi') for l in pref_langs) else 'ZZ')
                for t in trending:
                    tid = t.get("id")
                    t_title = t.get("title") or "Unknown"
                    t_artist = t.get("artist") or "Unknown"
                    if tid and can_add(tid, t_title, t_artist, None):
                        norm_song = self._normalize_song_dict(
                            tid,
                            t_title,
                            t_artist,
                            t.get("coverUrl") or t.get("cover_url"),
                            "",
                            ""
                        )
                        record_added(norm_song)
                        if len(results) >= limit:
                            break
            except Exception as e:
                logger.warning(f"[COLD-START] Trending fallback error: {e}")

        return results


# Global in-process recommender instance
personal_recommender = PersonalRecommender()
