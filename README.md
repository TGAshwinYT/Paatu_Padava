---
title: Paatu_Padava
emoji: 🎵
colorFrom: indigo
colorTo: purple
sdk: docker
pinned: false
---

# 🎵 Paatu Padava (பாட்டு பாடவா) — v2.5.0

[![CI Pipeline](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/ci.yml/badge.svg)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/ci.yml)
[![Build Release (Android & iOS)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml/badge.svg)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml)
[![Flutter](https://img.shields.io/badge/Flutter-v3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python_3.13-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![React](https://img.shields.io/badge/React-v19_TypeScript-61DAFB?logo=react&logoColor=black)](https://react.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Auth_%26_Cloud_DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)

**Paatu Padava** is a cross-platform, regional-first music streaming ecosystem (Tamil, Hindi, Telugu, Malayalam, Kannada, Punjabi, and English) featuring 320 kbps audio resolution, offline-first caching, LAN multi-speaker PartySync, and collaborative filtering recommendations.

---

## Architecture Overview

| Component | Stack | Purpose |
|---|---|---|
| **`mobile/`** | Flutter, `just_audio`, `audio_service`, Hive | Native Android/iOS player with gapless playback, LAN PartySync, Android Auto, and offline downloads |
| **`frontend-react/`** | React 19, TypeScript, Vite, Tailwind CSS, PWA | Responsive web player with 10-band Web Audio EQ, offline app-shell caching, and lazy-loaded routes |
| **`backend-data-hf/`** | FastAPI, Python 3.13, SQLAlchemy, Upstash Redis | Stream resolution & decryption, multi-provider search orchestration, JWT/JWKS auth, and recommendations |
| **`mcp_server.py`** | Model Context Protocol (MCP) | Local AI tooling bridge for search, smart shuffle, and recommendations |

> For deep-dive architecture diagrams, DSA internals (BK-Tree, SymSpell, MinHash, Trie), and API specifications, see **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Quick Start

### 1. Backend (`backend-data-hf/`)
```bash
cd backend-data-hf
python -m venv .venv
.venv/Scripts/activate   # or source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 7860
```
Run tests:
```bash
cd backend-data-hf
python -m unittest discover -s tests
```

### 2. Web App (`frontend-react/`)
```bash
cd frontend-react
npm ci
npm run dev
```
Run tests, lint, and production build:
```bash
cd frontend-react
npm test && npm run lint && npm run build
```

### 3. Mobile App (`mobile/`)
```bash
cd mobile
flutter pub get
flutter run
```
Run static analysis and tests:
```bash
cd mobile
flutter analyze --no-fatal-infos
flutter test --exclude-tags golden
```

---

## ⚖️ Legal Disclaimer & Fair Use Notice

* **Non-Commercial & Educational**: Paatu Padava is an open-source project created strictly for personal, educational, and research purposes. It is 100% free, non-monetized, carries zero advertisements, and charges no subscription fees.
* **No Content Hosting**: **This project does NOT host, store, or distribute any copyrighted media files, MP3s, or audio tracks on any server.** All media streams, metadata, and lyrics are fetched client-side in real time directly from publicly available third-party endpoints and decentralized networks (including JioSaavn public CDN, YouTube, Audius, and LRCLIB).
* **Intellectual Property**: All song titles, album art, audio recordings, and artist names are the property and copyright of their respective record labels, artists, and rights holders. Paatu Padava claims no ownership over any third-party content.
* **DMCA Inquiries**: If you are a copyright owner and have questions or concerns regarding client-side public indexing, please open an issue on the GitHub repository or contact the maintainer directly.

---

## 📄 License

This project is open-source and licensed under the [MIT License](LICENSE).

---

Made with ❤️ by [Ashwin (TGAshwinYT)](https://github.com/TGAshwinYT)
