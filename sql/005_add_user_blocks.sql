-- =============================================================================
-- USER BLOCKING
-- Run this script in the Supabase SQL Editor after the existing migrations.
-- It is idempotent and enforces blocking on the database, not just the app UI.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_user_id),
  CONSTRAINT user_blocks_no_self_block CHECK (blocker_id <> blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked_user
  ON public.user_blocks (blocked_user_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own blocks" ON public.user_blocks;
CREATE POLICY "Users can view their own blocks"
  ON public.user_blocks FOR SELECT
  USING (auth.uid() = blocker_id);

DROP POLICY IF EXISTS "Users can create their own blocks" ON public.user_blocks;
CREATE POLICY "Users can create their own blocks"
  ON public.user_blocks FOR INSERT
  WITH CHECK (auth.uid() = blocker_id AND blocker_id <> blocked_user_id);

DROP POLICY IF EXISTS "Users can remove their own blocks" ON public.user_blocks;
CREATE POLICY "Users can remove their own blocks"
  ON public.user_blocks FOR DELETE
  USING (auth.uid() = blocker_id);

-- A blocked user cannot obtain the blocker through the app's user search.
CREATE OR REPLACE FUNCTION public.search_visible_profiles(search_term text DEFAULT '')
RETURNS SETOF public.profiles
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.*
  FROM public.profiles p
  WHERE auth.uid() IS NOT NULL
    AND p.id <> auth.uid()
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_blocks b
      WHERE b.blocker_id = p.id
        AND b.blocked_user_id = auth.uid()
    )
    AND (
      coalesce(search_term, '') = ''
      OR p.username ILIKE '%' || search_term || '%'
    )
  ORDER BY p.username
  LIMIT 20;
$$;

REVOKE ALL ON FUNCTION public.search_visible_profiles(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_visible_profiles(text) TO authenticated;

-- A direct-message recipient can neither receive a new message from somebody
-- they blocked nor see that user's historic messages after the block.
CREATE OR REPLACE FUNCTION public.can_view_message(message_conversation_id uuid, message_sender_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_active_participant_of(message_conversation_id)
    AND (
      message_sender_id IS NULL
      OR message_sender_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = message_conversation_id AND c.is_group = true
      )
      OR NOT EXISTS (
        SELECT 1 FROM public.user_blocks b
        WHERE b.blocker_id = auth.uid()
          AND b.blocked_user_id = message_sender_id
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_send_message(message_conversation_id uuid, message_sender_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT message_sender_id = auth.uid()
    AND public.is_active_participant_of(message_conversation_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = message_conversation_id AND c.is_group = true
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.conversation_participants recipient
        JOIN public.user_blocks b
          ON b.blocker_id = recipient.user_id
         AND b.blocked_user_id = message_sender_id
        WHERE recipient.conversation_id = message_conversation_id
          AND recipient.status = 'active'
          AND recipient.user_id <> message_sender_id
      )
    );
$$;

DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
DROP POLICY IF EXISTS "Active participants can view permitted messages" ON public.messages;
CREATE POLICY "Active participants can view permitted messages"
  ON public.messages FOR SELECT
  USING (public.can_view_message(conversation_id, sender_id));

DROP POLICY IF EXISTS "Participants can insert messages" ON public.messages;
DROP POLICY IF EXISTS "Active participants can insert permitted messages" ON public.messages;
CREATE POLICY "Active participants can insert permitted messages"
  ON public.messages FOR INSERT
  WITH CHECK (public.can_send_message(conversation_id, sender_id));

-- This trigger is deliberately separate from RLS. It is the final server-side
-- safeguard for installations that still have an older permissive INSERT
-- policy on messages: a blocked user's direct-message INSERT is rejected.
CREATE OR REPLACE FUNCTION public.reject_messages_from_blocked_users()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_group_chat boolean;
BEGIN
  -- System messages have no sender and group messages are unaffected by a
  -- one-to-one block.
  IF NEW.sender_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT is_group INTO is_group_chat
  FROM public.conversations
  WHERE id = NEW.conversation_id;

  IF NOT coalesce(is_group_chat, false)
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants recipient
      JOIN public.user_blocks b
        ON b.blocker_id = recipient.user_id
       AND b.blocked_user_id = NEW.sender_id
      WHERE recipient.conversation_id = NEW.conversation_id
        AND recipient.status = 'active'
        AND recipient.user_id <> NEW.sender_id
    ) THEN
    RAISE EXCEPTION 'This user has blocked you and cannot receive your messages';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reject_messages_from_blocked_users ON public.messages;
CREATE TRIGGER reject_messages_from_blocked_users
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.reject_messages_from_blocked_users();

-- Reject creating a new 1-to-1 conversation with a user who has blocked the
-- caller. Existing conversations remain visible, but the message policy above
-- still prevents delivery to the blocker.
CREATE OR REPLACE FUNCTION public.prevent_blocked_direct_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_group_chat boolean;
BEGIN
  SELECT is_group INTO is_group_chat
  FROM public.conversations WHERE id = NEW.conversation_id;

  IF NOT coalesce(is_group_chat, false)
    AND NEW.status = 'active'
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants other_participant
      JOIN public.user_blocks b
        ON b.blocker_id = other_participant.user_id
       AND b.blocked_user_id = NEW.user_id
      WHERE other_participant.conversation_id = NEW.conversation_id
        AND other_participant.status = 'active'
        AND other_participant.user_id <> NEW.user_id
    ) THEN
    RAISE EXCEPTION 'You cannot start a conversation with this user';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_blocked_direct_participant ON public.conversation_participants;
CREATE TRIGGER prevent_blocked_direct_participant
  BEFORE INSERT OR UPDATE OF user_id, status ON public.conversation_participants
  FOR EACH ROW EXECUTE FUNCTION public.prevent_blocked_direct_participant();
