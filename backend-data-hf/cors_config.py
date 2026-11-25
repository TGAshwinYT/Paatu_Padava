import os
from typing import List


def get_allowed_origins() -> List[str]:
    """
    Loads allowed CORS origins dynamically from environment variables
    (ALLOWED_ORIGINS / FRONTEND_URL) while explicitly stripping wildcard '*'
    because allow_credentials=True forbids wildcard origins.
    """
    origins: List[str] = [
        "http://localhost:5173",
        "http://localhost:5174",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:5174",
    ]
    env_origins = os.getenv("ALLOWED_ORIGINS", "")
    if env_origins:
        for o in env_origins.split(","):
            clean_o = o.strip().rstrip("/")
            if clean_o and clean_o != "*" and clean_o not in origins:
                origins.append(clean_o)

    frontend_url = os.getenv("FRONTEND_URL", "").strip().rstrip("/")
    if frontend_url and frontend_url != "*" and frontend_url not in origins:
        origins.append(frontend_url)

    return origins
