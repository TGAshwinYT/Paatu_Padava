# Regional Weighting Matrix for JioSaavn Search (Normalized)
REGION_LANGUAGE_PRIORITY = {
    "tamilnadu": "tamil,english,hindi",
    "tn": "tamil,english,hindi",
    "kerala": "malayalam,tamil,english,hindi",
    "karnataka": "kannada,telugu,tamil,english,hindi",
    "andhrapradesh": "telugu,tamil,english,hindi",
    "telangana": "telugu,tamil,english,hindi",
    "maharashtra": "marathi,hindi,english"
}

def get_search_languages(region: str) -> str:
    """
    Returns a prioritized, comma-separated string of languages for JioSaavn searches.
    Normalizes region strings (e.g. 'Tamil Nadu' -> 'tamilnadu') to avoid dictionary misses.
    """
    if not region:
        return "hindi,english,tamil,telugu"
    
    # 🚨 STRICT BULLETPROOF NORMALIZATION 🚨
    clean_region = str(region).lower().replace(" ", "").strip()
    
    # Check for direct match in normalized dictionary
    if clean_region in REGION_LANGUAGE_PRIORITY:
        return REGION_LANGUAGE_PRIORITY[clean_region]
            
    # Default Indian priority if mapping fails
    return "hindi,english,tamil,telugu"

# Keeping get_preferred_language for backward compatibility if needed elsewhere
def get_preferred_language(region: str) -> str:
    """
    Alias for new search language logic (returns primary language only).
    """
    langs = get_search_languages(region)
    return langs.split(',')[0]
