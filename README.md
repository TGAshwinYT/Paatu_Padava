# 🎵 Paatu Padava

A full-stack, YouTube/Saavn-powered music streaming web app — search for songs, stream audio, follow artists, build playlists, view synced lyrics, and get AI-curated "DJ" recommendations. Built with a **React + TypeScript** frontend and a **FastAPI (Python)** backend, with a React Native mobile client in progress.

> Note: This file documents the actual web application. The auto-generated `README.md` in this repo is the default Vite template file and has been left untouched as requested — refer to this file for real project documentation.

---

## ✨ Features

- **Search & Discover** — Search tracks and artists with instant autocomplete suggestions (powered by an in-memory Trie), browse a personalized home feed, and explore popular albums/artists.
- **Streaming** — Stream audio sourced via YouTube Music (`ytmusicapi`, `yt-dlp`) with a custom audio player and mobile player overlay.
- **Lyrics** — Fetch plain and time-synced lyrics (via `syncedlyrics` / LRCLIB) that scroll in time with playback.
- **Playlists & Library** — Create, rename, and delete playlists, add/remove songs, like songs, and follow your favorite artists.
- **Listening History** — Automatic listen history, search history, and "recently clicked" search results, with the ability to clear history by song, by date, or entirely.
- **AI DJ** — An AI-powered recommendation endpoint (Google Gemini) that curates a queue based on mood/prompt.
- **Recommendation Graph** — A graph-based "related songs" engine that connects trending tracks so users get relevant recommendations.
- **Auth & Accounts** — Email/password registration with email verification, login/logout (JWT-based sessions), password reset, and profile preferences (favorite artists).
- **Data Portability** — Export and import your account data (playlists, history, likes) as a file.
- **Onboarding** — First-run onboarding flow to pick favorite artists/genres.
- **Responsive & Mobile-aware UI** — Dedicated mobile views (`Mobile Home`, `Mobile Search`, `Mobile Library`, mobile player overlay) alongside the desktop experience, plus an early-stage React Native mobile app.

---

## 🏗️ Tech Stack

### Frontend (`frontend-react/`)
- **React 19** + **TypeScript** + **Vite**
- **Tailwind CSS** for styling
- **React Router** for navigation
- **Axios** for API calls
- **Swiper**, **@hello-pangea/dnd** (drag & drop), **Heroicons** / **lucide-react** (icons)
- **react-youtube** for playback

### Backend (`backend-data-hf/`)
- **FastAPI** (async Python web framework)
- **SQLAlchemy** (async) + **PostgreSQL** (`asyncpg`) — via Supabase in production
- **Redis** (Upstash-compatible) for caching (`fastapi-cache2`) and rate limiting (`slowapi`)
- **JWT auth** (`python-jose`) with **Argon2** password hashing (`passlib`, `argon2-cffi`)
- **ytmusicapi** / **yt-dlp** / **curl-cffi** for fetching music metadata & audio streams
- **syncedlyrics** for time-synced lyrics
- **google-genai** (Gemini) for the AI DJ feature
- Deployed via **Docker** (see `Dockerfile`), configured for Hugging Face Spaces

### Mobile (`mobile/`)
- Early-stage **React Native** client (track player service + audio bridge utilities)

---

## 📁 Project Structure

```
Paatu_Padava/
├── backend-data-hf/          # FastAPI backend
│   ├── main.py                # App entrypoint, lifespan, middleware, table migrations
│   ├── routers/                # API route modules
│   │   ├── music.py            # Search, home feed, likes, recommendations, lyrics, artist/album details
│   │   ├── auth.py             # Register, login, logout, password reset, email verification
│   │   ├── playlists.py        # CRUD for playlists & playlist tracks
│   │   ├── history.py          # Listen/search history, search-click history
│   │   ├── users.py            # Data export/import, account deletion, followed artists
│   │   ├── utils.py             # Misc utility endpoints
│   │   └── ai.py                # AI DJ endpoint (Gemini-powered)
│   ├── services/               # External integrations (YouTube, Saavn, lyrics)
│   ├── graph.py                 # Song recommendation graph
│   ├── trie.py                  # Artist autocomplete Trie
│   ├── connection.py            # DB & Redis connection helpers
│   ├── models.py                # SQLAlchemy models
│   └── requirements.txt
├── frontend-react/            # React + TypeScript + Vite web app
│   ├── src/
│   │   ├── pages/               # Home, Search, Login, Signup, Profile, Playlists, Liked Songs, etc.
│   │   ├── pages/mobile/        # Mobile-specific pages
│   │   ├── components/          # Player bar, audio player, modals, home sections, etc.
│   │   ├── context/              # React context providers
│   │   ├── hooks/, services/, utils/, types/
│   └── package.json
├── mobile/                     # React Native mobile client (WIP)
├── scripts/                    # Icon generation & build scripts
├── Dockerfile                  # Backend container image (Hugging Face Spaces ready)
└── start_server.bat            # Windows helper script to start the backend
```

---

## 🚀 Getting Started

### Prerequisites
- **Node.js** (18+) and npm for the frontend
- **Python 3.11+** for the backend
- A **PostgreSQL** database (e.g. Supabase)
- A **Redis** instance (e.g. Upstash) — optional but recommended for caching/rate limiting
- A **Google Gemini API key** — optional, only required for the AI DJ feature

### 1. Backend setup

```bash
cd backend-data-hf
pip install -r requirements.txt
```

Create a `.env` file inside `backend-data-hf/` with the variables below, then start the server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

On Windows, you can alternatively run the included helper script from the repo root:

```bash
start_server.bat
```

The API will be available at `http://localhost:8000`, with a health check at `GET /api/health`.

### 2. Frontend setup

```bash
cd frontend-react
npm install
npm run dev
```

The app will be available at `http://localhost:5173` (Vite's default dev server, matching the backend's configured CORS origins).

### 3. Environment variables (backend)

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string (async, e.g. `postgresql+asyncpg://...`) |
| `REDIS_URL` | No | Redis connection string; defaults to `redis://localhost:6379` |
| `JWT_SECRET` | Recommended | Secret key used to sign JWT auth tokens |
| `GEMINI_API_KEY` | No | Google Gemini API key, required only for the `/ai/dj` endpoint |

> Tip: check `backend-data-hf/email_utils.py` and `auth_utils.py` if you plan to enable email verification/reset flows — you'll need SMTP-related configuration for outgoing email.

---

## 🐳 Docker (Backend)

The backend ships with a Dockerfile pre-configured for Hugging Face Spaces (exposes port `7860`):

```bash
docker build -t paatu-padava-backend .
docker run -p 7860:7860 --env-file backend-data-hf/.env paatu-padava-backend
```

---

## 📡 Key API Endpoints (Backend)

| Area | Examples |
|---|---|
| **Music** | `GET /home`, `GET /search`, `GET /search/suggestions`, `GET /lyrics/{song_id}`, `GET /recommendations/{song_id}`, `GET /artist/{artist_id}`, `GET /albums/{album_id}` |
| **Auth** | `POST /register`, `POST /login`, `GET /me`, `POST /forgot-password`, `POST /reset-password`, `GET /verify/{token}` |
| **Playlists** | `GET /`, `POST /`, `POST /{playlist_id}/songs`, `DELETE /{playlist_id}` |
| **History** | `POST /listen`, `GET /listen`, `POST /search`, `DELETE /all` |
| **Users** | `GET /export`, `POST /import`, `POST /follow-artist`, `GET /me/followed-artists` |
| **AI** | `POST /dj` (AI DJ recommendation queue) |

Full interactive API docs are available via FastAPI's auto-generated Swagger UI at `/docs` once the backend is running.

---

## 📱 Mobile App

The `mobile/` directory contains the beginnings of a React Native client, including a track player service and an audio bridge utility, intended to eventually mirror the web app's playback experience on iOS/Android.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome. Feel free to open a pull request or file an issue on the repository.

---

## 📄 License

This project is licensed under the [MIT License](./LICENSE).
