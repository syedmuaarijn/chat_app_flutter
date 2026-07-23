-- Media messages store their metadata in public.messages and their bytes in
-- Supabase Storage. Run this migration in the Supabase SQL editor (or through
-- your normal migration workflow) before releasing media sharing.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS media_url text,
  ADD COLUMN IF NOT EXISTS file_name text,
  ADD COLUMN IF NOT EXISTS file_size bigint,
  ADD COLUMN IF NOT EXISTS audio_duration integer;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_type_check
  CHECK (type IN ('text', 'image', 'video', 'audio', 'voice', 'document'));

-- The Flutter app uses getPublicUrl(), so this bucket must be public. Uploads
-- remain restricted to active participants of the conversation in the first
-- path segment: <conversation-id>/<unique-file-name>.
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "Active participants can upload chat attachments" ON storage.objects;
CREATE POLICY "Active participants can upload chat attachments"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND public.is_active_participant_of((storage.foldername(name))[1]::uuid)
  );

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

DROP POLICY IF EXISTS "Uploaders can delete chat attachments" ON storage.objects;
CREATE POLICY "Uploaders can delete chat attachments"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'chat-attachments'
    AND owner_id = auth.uid()::text
  );
