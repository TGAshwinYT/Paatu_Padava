# Regional Weighting Matrix for JioSaavn Search
# Prioritizes local, neighboring, then national languages (Hindi/English)
REGION_LANGUAGE_PRIORITY = {
    "Tamil Nadu": "tamil,telugu,malayalam,english,hindi",
    "Kerala": "malayalam,tamil,english,hindi",
    "Karnataka": "kannada,telugu,tamil,english,hindi",
    "Andhra Pradesh": "telugu,tamil,english,hindi",
    "Telangana": "telugu,tamil,english,hindi",
    "Maharashtra": "marathi,hindi,english",
    "Gujarat": "gujarati,hindi,english",
    "Punjab": "punjabi,hindi,english",
    "West Bengal": "bengali,hindi,english"
}

def get_search_languages(region: str) -> str:
    """
    Returns a prioritized, comma-separated string of languages for JioSaavn searches.
    Defaults to a solid Indian base if region is not found.
    """
    if not region:
        return "hindi,english,tamil,telugu"
    
    # Check for direct match or substring (e.g. "Andhra Pradesh" matching "Andhra")
    for state, languages in REGION_LANGUAGE_PRIORITY.items():
        if region.lower() == state.lower():
            return languages
            
    # Default Indian priority if direct mapping fails
    return "hindi,english,tamil,telugu"

# Keeping get_preferred_language for backward compatibility if needed elsewhere
def get_preferred_language(region: str) -> str:
    """
    Alias for new search language logic (returns primary language only).
    """
    langs = get_search_languages(region)
    return langs.split(',')[0]
