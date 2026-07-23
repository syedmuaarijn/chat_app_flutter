-- Create storage buckets for avatars and chat attachments
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/nfjlgqylmggppsxabtbd/sql/new

-- ============================================
-- Create avatars bucket (for user profile pictures)
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- Policy: Authenticated users can upload their own avatar
-- Storage path format: user_avatars/{userId}_{timestamp}.{ext}
DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
CREATE POLICY "Users can upload their own avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND storage.foldername(name) = ARRAY['user_avatars']
    AND split_part(name, '/', 2) LIKE (auth.uid()::text || '%')
  );

-- Policy: Users can update their own avatar
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND storage.foldername(name) = ARRAY['user_avatars']
    AND split_part(name, '/', 2) LIKE (auth.uid()::text || '%')
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND storage.foldername(name) = ARRAY['user_avatars']
    AND split_part(name, '/', 2) LIKE (auth.uid()::text || '%')
  );

-- Policy: Public can view avatars (bucket is public)
DROP POLICY IF EXISTS "Public can view avatars" ON storage.objects;
CREATE POLICY "Public can view avatars"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

-- ============================================
-- Create chat-attachments bucket (for group avatars and media)
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- Policy: Active participants can upload chat attachments
DROP POLICY IF EXISTS "Active participants can upload chat attachments" ON storage.objects;
CREATE POLICY "Active participants can upload chat attachments"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND public.is_active_participant_of((storage.foldername(name))[1]::uuid)
  );

-- Policy: Uploaders can update chat attachments
DROP POLICY IF EXISTS "Uploaders can update chat attachments" ON storage.objects;
CREATE POLICY "Uploaders can update chat attachments"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'chat-attachments'
    AND owner_id = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND owner_id = auth.uid()::text
  );

-- Policy: Uploaders can delete chat attachments
DROP POLICY IF EXISTS "Uploaders can delete chat attachments" ON storage.objects;
CREATE POLICY "Uploaders can delete chat attachments"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'chat-attachments'
    AND owner_id = auth.uid()::text
  );

-- Policy: Public can view chat attachments (bucket is public)
DROP POLICY IF EXISTS "Public can view chat attachments" ON storage.objects;
CREATE POLICY "Public can view chat attachments"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'chat-attachments');
