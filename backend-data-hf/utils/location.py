import logging
import json
from typing import Optional, List, Any

logger = logging.getLogger(__name__)

# Canonical Supported Languages for Paatu Padava
SUPPORTED_LANGUAGES = [
    "tamil",
    "english",
    "hindi",
    "telugu",
    "malayalam",
    "kannada",
    "punjabi",
    "marathi",
    "bengali",
]

# Neutral multi-language default for guests / unconfigured accounts
DEFAULT_APP_LANGUAGES = "tamil,english,hindi,telugu,malayalam"

def get_user_search_languages(user: Any = None) -> str:
    """
    Returns prioritized comma-separated string of search languages strictly from the user's
    explicit preferred_languages setting.
    No IP geolocation or browser locale sniffing is used.
    Falls back to neutral multi-language mix if guest or not configured.
    """
    if user and hasattr(user, 'preferred_languages') and user.preferred_languages:
        try:
            raw_pref = user.preferred_languages
            if isinstance(raw_pref, str):
                if raw_pref.strip().startswith("["):
                    pref_list = json.loads(raw_pref)
                else:
                    pref_list = [p.strip() for p in raw_pref.split(",") if p.strip()]
            elif isinstance(raw_pref, list):
                pref_list = raw_pref
            else:
                pref_list = []

            if isinstance(pref_list, list) and len(pref_list) > 0:
                clean_prefs = [
                    str(l).lower().strip() 
                    for l in pref_list 
                    if str(l).lower().strip() in SUPPORTED_LANGUAGES
                ]
                if clean_prefs:
                    resolved = ",".join(clean_prefs)
                    logger.info("[LANGUAGE] Resolved explicit preferred_languages for user %s: %s", getattr(user, 'id', 'unknown'), resolved)
                    return resolved
        except Exception as e:
            logger.warning("[LANGUAGE] Error parsing user preferred_languages: %s", e)

    # Neutral fallback for guest / unconfigured users
    return DEFAULT_APP_LANGUAGES

def resolve_user_languages(user: Any = None, region: Optional[str] = None, recommender: Any = None) -> str:
    """
    Resolves search and recommendation languages.
    Priority is strictly given to user's explicit preferred_languages.
    If listening history dominant languages are available from recommender, they can enrich missing preferences.
    Falls back to DEFAULT_APP_LANGUAGES without any IP geolocation or browser header sniffing.
    """
    # 1. Explicit profile setting (preferred_languages)
    if user and hasattr(user, 'preferred_languages') and user.preferred_languages:
        explicit = get_user_search_languages(user)
        if explicit != DEFAULT_APP_LANGUAGES:
            return explicit

    # 2. Behavioral signal from listening history if user has not set explicit preferences
    if user and hasattr(user, 'id') and recommender:
        try:
            dominant_langs = recommender.get_user_dominant_languages(str(user.id))
            if dominant_langs:
                clean = [l for l in dominant_langs if l in SUPPORTED_LANGUAGES]
                if clean:
                    return ",".join(clean[:5])
        except Exception as e:
            logger.warning("[LANGUAGE] Could not extract history languages: %s", e)

    # 3. Neutral App Default
    return DEFAULT_APP_LANGUAGES

def get_search_languages(region: Optional[str] = None) -> str:
    """
    Backward-compatible helper. Ignores region inference and returns app languages.
    """
    return DEFAULT_APP_LANGUAGES

def get_preferred_language(region: str = "") -> str:
    """
    Alias returning primary language.
    """
    return DEFAULT_APP_LANGUAGES.split(',')[0]

