---
name: db-guidelines
description: Database architecture rules, migration procedures, indexing standards, and connection pooling protocols for Paatu Padava.
---

# Database Guidelines (Paatu Padava Ecosystem)

## 1. Relational Schema Architecture (PostgreSQL & SQLAlchemy 2.0)
- All primary keys for transactional entities must use UUIDv4 (`UUID(as_uuid=True)` in SQLAlchemy, `gen_random_uuid()` in PostgreSQL) to prevent ID collision across offline client syncing.
- String keys (e.g. JioSaavn artist IDs or YouTube video IDs) must specify explicit lengths: `String(100)` for IDs, `String(255)` for names/titles.
- All timestamp columns must be timezone-aware (`DateTime(timezone=True)`) with server-side defaults (`server_default=func.now()`).

## 2. Supabase Cloud Setup & Row Level Security (RLS)
- Every table containing user-associated data (`profiles`, `user_favorite_artists`, `user_playlists`, `playlist_tracks`) MUST have RLS enabled:
  ```sql
  ALTER TABLE public.user_playlists ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Users can manage playlists" 
  ON public.user_playlists 
  FOR ALL 
  USING (auth.uid() = user_id);
  ```
- Sub-entity tables (`playlist_tracks`) must verify parent ownership:
  ```sql
  CREATE POLICY "Users can manage playlist tracks" 
  ON public.playlist_tracks 
  FOR ALL 
  USING (
    playlist_id IN (SELECT id FROM public.user_playlists WHERE user_id = auth.uid())
  );
  ```

## 3. Asynchronous Connection Pooling (asyncpg)
- In `backend-data-hf/connection.py`, ensure connection pool configuration enforces resilience:
  - `pool_size`: 5 base connections.
  - `max_overflow`: 10 burst connections.
  - `pool_pre_ping=True`: Verifies connection liveness before dispatching queries to avoid stale socket exceptions.
  - `pool_recycle=300`: Retires idle connections after 5 minutes to prevent remote proxy disconnects.
  - `pool_use_lifo=True`: Reuses hot connections to keep active keep-alives warm.
  - SSL Configuration: Use an unverified SSL context (`ssl.CERT_NONE`) specifically for local development and Windows/MSYS certificate stores.

## 4. Indexing & Query Optimization
- Index all foreign key columns (`user_id`, `playlist_id`, `artist_id`).
- For time-series queries (e.g. listening history), use composite indices:
  ```python
  Index('ix_user_played_at', 'user_id', 'played_at')
  ```
- Enforce business uniqueness at the database level:
  ```python
  UniqueConstraint("user_id", "yt_video_id", name="uq_user_song")
  ```

## 5. Non-Destructive Migrations
- Migration steps must be idempotent (`IF NOT EXISTS` / `IF EXISTS`):
  ```python
  await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id TEXT UNIQUE"))
  ```
- Never execute destructive `DROP TABLE` operations on production instances without automated backups and deprecation windows.
