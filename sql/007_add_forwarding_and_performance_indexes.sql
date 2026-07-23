-- Forwarded-message marker and indexes used by the chat list and user search.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_forwarded boolean NOT NULL DEFAULT false;

-- The chat list reads newest messages and unread messages per conversation.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_desc
  ON public.messages (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_unread_by_conversation
  ON public.messages (conversation_id, created_at DESC)
  WHERE is_read = false;

-- Makes the existing ILIKE '%query%' profile search fast as the user types.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_profiles_username_trgm
  ON public.profiles USING gin (username gin_trgm_ops);
