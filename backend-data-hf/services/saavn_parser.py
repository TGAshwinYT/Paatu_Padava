import html
import base64
from typing import Any, Dict

try:
    from cryptography.hazmat.decrepit.ciphers.algorithms import TripleDES
except ImportError:
    from cryptography.hazmat.primitives.ciphers.algorithms import TripleDES
from cryptography.hazmat.primitives.ciphers import Cipher, modes


def extract_artist_name(artist_data: Any) -> str:
    """
    Bulletproof extraction of artist name from various potential keys.
    Checks name, title, listname, subtitle in prioritized order.
    """
    if not artist_data:
        return "Unknown Artist"

    if isinstance(artist_data, str):
        return html.unescape(artist_data)

    keys = ["name", "title", "listname", "subtitle", "artist"]

    for key in keys:
        val = artist_data.get(key)
        if val and isinstance(val, str) and val.strip().lower() not in ["null", "none", "artist", "unknown"]:
            return html.unescape(val.strip())
        if val and isinstance(val, list) and len(val) > 0:
            item = val[0]
            if isinstance(item, str):
                return html.unescape(item)
            if isinstance(item, dict):
                inner_name = item.get("name") or item.get("title")
                if inner_name:
                    return html.unescape(inner_name)

    return "Unknown Artist"


def extract_high_res_image(image_data: Any) -> str:
    """
    Robust extraction of highest resolution image from various formats.
    Handles strings (including comma-separated lists), lists of URLs, or lists of dictionaries.
    Forces 500x500 for JioSaavn CDN links to ensure premium quality.
    """
    default_image = "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop"

    if not image_data:
        return default_image

    url = default_image

    if isinstance(image_data, str):
        if "," in image_data:
            urls = [u.strip() for u in image_data.split(",")]
            url = urls[-1] if urls and urls[-1].startswith("http") else default_image
        elif image_data.startswith("http"):
            url = image_data
    elif isinstance(image_data, list) and len(image_data) > 0:
        best_img = image_data[-1]
        if isinstance(best_img, dict):
            url = best_img.get("link") or best_img.get("url") or default_image
        elif isinstance(best_img, str) and best_img.startswith("http"):
            url = best_img
    elif isinstance(image_data, dict):
        url = image_data.get("image") or image_data.get("image_url") or image_data.get("images") or default_image
        if isinstance(url, list):
            return extract_high_res_image(url)

    if not isinstance(url, str) or not url.startswith("http"):
        return default_image

    if "jiosaavn.com" in url or "saavncdn.com" in url:
        url = url.replace("50x50", "500x500").replace("150x150", "500x500")

    return url


def extract_audio_url(item: Dict[str, Any]) -> str:
    """
    Robustly extracts the highest quality audio URL from JioSaavn song data.
    """
    if not item or not isinstance(item, dict):
        return ""

    downloads = item.get("downloadUrl", [])
    if isinstance(downloads, list) and len(downloads) > 0:
        if len(downloads) > 4:
            url = downloads[4].get("url")
            if url:
                return url

        url = downloads[-1].get("url")
        if url:
            return url

    direct_url = item.get("url") or item.get("link") or item.get("download_url")
    if direct_url and (".mp3" in direct_url or ".m4a" in direct_url or "http" in direct_url):
        return direct_url

    return ""


def decrypt_saavn_media_url(encrypted_url: str) -> str:
    """
    Directly decrypts JioSaavn's DES-encrypted media URL to pristine CDN audio streams.
    Replaces 96kbps / 160kbps with 320kbps for maximum fidelity.
    """
    if not encrypted_url:
        return ""
    try:
        key = b"38346591" * 3
        cipher = Cipher(TripleDES(key), modes.ECB())
        decryptor = cipher.decryptor()
        raw_data = base64.b64decode(encrypted_url)
        decrypted = decryptor.update(raw_data) + decryptor.finalize()
        pad = decrypted[-1]
        if pad < 8:
            decrypted = decrypted[:-pad]
        url = decrypted.decode("utf-8", errors="ignore").strip()
        if "_96.mp4" in url:
            return url.replace("_96.mp4", "_320.mp4")
        if "_160.mp4" in url:
            return url.replace("_160.mp4", "_320.mp4")
        return url
    except Exception:
        return ""
