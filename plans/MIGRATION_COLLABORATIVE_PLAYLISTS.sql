-- =========================================================================
-- PAATU PAADAVA: COLLABORATIVE PLAYLISTS & REALTIME RLS MIGRATION (SECURED)
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

-- 4. Create playlist_members table for granular collaborator authorization
CREATE TABLE IF NOT EXISTS public.playlist_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID NOT NULL REFERENCES public.playlists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL DEFAULT 'editor', -- 'owner', 'editor', 'viewer'
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE(playlist_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_playlist_members_user_id ON public.playlist_members(user_id);
CREATE INDEX IF NOT EXISTS idx_playlist_members_playlist_id ON public.playlist_members(playlist_id);

-- 5. Enable Row Level Security (RLS) on all relevant tables
ALTER TABLE public.playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlist_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlist_members ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- PLAYLIST MEMBERS POLICIES
-- =========================================================================
DROP POLICY IF EXISTS "Users view own playlist memberships" ON public.playlist_members;
DROP POLICY IF EXISTS "Owners manage playlist memberships" ON public.playlist_members;

CREATE POLICY "Users view own playlist memberships" ON public.playlist_members
    FOR SELECT USING (
        auth.uid() = user_id
        OR playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
    );

CREATE POLICY "Owners manage playlist memberships" ON public.playlist_members
    FOR ALL USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
    );

-- =========================================================================
-- SECURE INVITE CODE JOIN FUNCTION (SECURITY DEFINER)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.join_collaborative_playlist(p_invite_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_playlist RECORD;
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Authentication required');
    END IF;

    SELECT id, title, user_id INTO target_playlist
    FROM public.playlists
    WHERE invite_code = p_invite_code AND is_collaborative = TRUE;

    IF target_playlist.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or inactive invite code');
    END IF;

    -- Add membership if not already present
    INSERT INTO public.playlist_members (playlist_id, user_id, role)
    VALUES (target_playlist.id, current_uid, 'editor')
    ON CONFLICT (playlist_id, user_id) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true, 
        'playlist_id', target_playlist.id,
        'title', target_playlist.title
    );
END;
$$;

-- =========================================================================
-- PLAYLISTS POLICIES
-- =========================================================================
DROP POLICY IF EXISTS "Users view accessible playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users insert own playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users update own playlists" ON public.playlists;
DROP POLICY IF EXISTS "Users delete own playlists" ON public.playlists;

-- SELECT: Users can view their own playlists, public playlists, or playlists where they are an authorized member
CREATE POLICY "Users view accessible playlists" ON public.playlists
    FOR SELECT USING (
        auth.uid() = user_id 
        OR is_public = TRUE 
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlists.id AND pm.user_id = auth.uid()
        )
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
-- PLAYLIST TRACKS POLICIES (Collaborator Membership Access)
-- =========================================================================
DROP POLICY IF EXISTS "Users view playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users insert playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users update playlist tracks" ON public.playlist_tracks;
DROP POLICY IF EXISTS "Users delete playlist tracks" ON public.playlist_tracks;

-- SELECT: Tracks are viewable if the parent playlist is accessible
CREATE POLICY "Users view playlist tracks" ON public.playlist_tracks
    FOR SELECT USING (
        playlist_id IN (
            SELECT id FROM public.playlists 
            WHERE user_id = auth.uid() OR is_public = TRUE
        )
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlist_tracks.playlist_id AND pm.user_id = auth.uid()
        )
    );

-- INSERT: Only verified members or playlist owners can add tracks
CREATE POLICY "Users insert playlist tracks" ON public.playlist_tracks
    FOR INSERT WITH CHECK (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlist_tracks.playlist_id 
              AND pm.user_id = auth.uid() 
              AND pm.role IN ('owner', 'editor')
        )
    );

-- UPDATE: Only verified members or playlist owners can update tracks
CREATE POLICY "Users update playlist tracks" ON public.playlist_tracks
    FOR UPDATE USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlist_tracks.playlist_id 
              AND pm.user_id = auth.uid() 
              AND pm.role IN ('owner', 'editor')
        )
    ) WITH CHECK (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlist_tracks.playlist_id 
              AND pm.user_id = auth.uid() 
              AND pm.role IN ('owner', 'editor')
        )
    );

-- DELETE: Only verified members or playlist owners can remove tracks
CREATE POLICY "Users delete playlist tracks" ON public.playlist_tracks
    FOR DELETE USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.playlist_members pm
            WHERE pm.playlist_id = playlist_tracks.playlist_id 
              AND pm.user_id = auth.uid() 
              AND pm.role IN ('owner', 'editor')
        )
    );

-- =========================================================================
-- REALTIME REPLICATION CONFIGURATION
-- =========================================================================
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

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'playlist_members'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.playlist_members;
    END IF;
END $$;
