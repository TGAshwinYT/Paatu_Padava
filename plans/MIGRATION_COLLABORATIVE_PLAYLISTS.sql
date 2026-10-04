-- =========================================================================
-- PAATU PAADAVA: COLLABORATIVE PLAYLISTS & REALTIME RLS MIGRATION
-- Run this migration in your Supabase SQL Editor.
-- =========================================================================

-- 1. Ensure 'added_by' column exists on playlist_tracks for track attribution
ALTER TABLE public.playlist_tracks 
ADD COLUMN IF NOT EXISTS added_by TEXT DEFAULT NULL;

-- 2. Ensure 'is_collaborative' and 'invite_code' columns exist on playlists
ALTER TABLE public.playlists 
ADD COLUMN IF NOT EXISTS is_collaborative BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS invite_code TEXT DEFAULT NULL;

-- 3. Create index for fast invite code lookup
CREATE INDEX IF NOT EXISTS idx_playlists_invite_code 
ON public.playlists(invite_code) 
WHERE invite_code IS NOT NULL;

-- 4. Enable Row Level Security (RLS) on both tables
ALTER TABLE public.playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlist_tracks ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- PLAYLISTS POLICIES
-- =========================================================================

-- Drop legacy/conflicting policies if they exist
DROP POLICY IF EXISTS "Users view accessible playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users insert own playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users update own playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users delete own playlists" ON public.playlists;

-- SELECT: Users can view their own playlists, public playlists, or collaborative playlists
CREATE POLICY "Users view accessible playlists" ON public.playlists
    FOR SELECT USING (
        auth.uid() = user_id 
        OR is_public = TRUE 
        OR is_collaborative = TRUE
    );

-- INSERT: Authenticated users can only create playlists with their own user_id
CREATE POLICY "Users insert own playlists" ON public.playlists
    FOR INSERT WITH CHECK (
        auth.uid() = user_id
    );

-- UPDATE: Only the playlist owner can update playlist metadata (title, cover, collab status)
CREATE POLICY "Users update own playlists" ON public.playlists
    FOR UPDATE USING (
        auth.uid() = user_id
    ) WITH CHECK (
        auth.uid() = user_id
    );

-- DELETE: Only the playlist owner can permanently delete the playlist
CREATE POLICY "Users delete own playlists" ON public.playlists
    FOR DELETE USING (
        auth.uid() = user_id
    );

-- =========================================================================
-- PLAYLIST TRACKS POLICIES (Collaborator Access)
-- =========================================================================

-- Drop legacy/conflicting policies if they exist
DROP POLICY IF EXISTS "Users view playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users insert playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users update playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users delete playlist tracks" ON public.playlist_tracks;

-- SELECT: Tracks are viewable if the parent playlist is accessible
CREATE POLICY "Users view playlist tracks" ON public.playlist_tracks
    FOR SELECT USING (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_public = TRUE OR is_collaborative = TRUE
        )
    );

-- INSERT: Collaborators or the owner can add tracks to a collaborative playlist
CREATE POLICY "Users insert playlist tracks" ON public.playlist_tracks
    FOR INSERT WITH CHECK (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_collaborative = TRUE
        )
    );

-- UPDATE: Collaborators or the owner can update tracks (e.g. reorder position) in a collaborative playlist
CREATE POLICY "Users update playlist tracks" ON public.playlist_tracks
    FOR UPDATE USING (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_collaborative = TRUE
        )
    ) WITH CHECK (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_collaborative = TRUE
        )
    );

-- DELETE: Collaborators or the owner can remove tracks from a collaborative playlist
CREATE POLICY "Users delete playlist tracks" ON public.playlist_tracks
    FOR DELETE USING (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_collaborative = TRUE
        )
    );

-- =========================================================================
-- REALTIME REPLICATION CONFIGURATION
-- =========================================================================

-- Ensure tables are published to supabase_realtime for live event notifications
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'playlists'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.playlists;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'playlist_tracks'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.playlist_tracks;
    END IF;
END $$;
