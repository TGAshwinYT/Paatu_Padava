import os
from dotenv import load_dotenv
load_dotenv()

# ENV Dump
print(f"[*] DATABASE_URL: {repr(os.getenv('DATABASE_URL'))}")
print(f"[*] HTTP_PROXY: {repr(os.getenv('HTTP_PROXY'))}")
print(f"[*] HTTPS_PROXY: {repr(os.getenv('HTTPS_PROXY'))}")
print(f"[*] ALL_PROXY: {repr(os.getenv('ALL_PROXY'))}")

# Simulate connection.py logic
DB_URL_RAW = os.getenv("DATABASE_URL", "")
print(f"[*] RAW DATABASE_URL from .env: {repr(DB_URL_RAW)}")

DB_URL = DB_URL_RAW.replace("postgresql://", "postgresql+asyncpg://")
print(f"[*] Processed DB_URL for SQLAlchemy: {repr(DB_URL)}")

import socket
import urllib.parse

try:
    # Parse the URL to get the hostname
    parsed = urllib.parse.urlparse(DB_URL_RAW)
    host = parsed.hostname
    port = parsed.port or 5432
    print(f"[*] Extracted Host: {repr(host)}")
    print(f"[*] Extracted Port: {port}")
    
    print(f"[*] Testing socket resolution for {host}...")
    ip = socket.gethostbyname(host)
    print(f"[SUCCESS] Resolved to {ip}")
except Exception as e:
    print(f"[ERROR] Resolution failed: {e}")
