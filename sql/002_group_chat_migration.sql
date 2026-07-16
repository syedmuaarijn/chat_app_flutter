-- =============================================================================
-- GROUP CHAT MIGRATION (v3)
-- Run this in the Supabase SQL Editor.
-- =============================================================================

-- ── 1. ENUMS ─────────────────────────────────────────────────────────────────

DO $$ BEGIN
  CREATE TYPE public.participant_role AS ENUM ('creator', 'admin', 'member');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2. CONVERSATIONS TABLE ───────────────────────────────────────────────────

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS is_group boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS description text DEFAULT '',
  ADD COLUMN IF NOT EXISTS avatar_url text DEFAULT '',
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS only_admins_can_message boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS only_admins_can_edit_info boolean DEFAULT false;

-- ── 3. CONVERSATION PARTICIPANTS TABLE ───────────────────────────────────────

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS role participant_role DEFAULT 'member',
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'active' CHECK (status IN ('active', 'left'));

-- Use ctid (physical row pointer) to deduplicate; MIN/MAX work on ctid
DELETE FROM public.conversation_participants
WHERE ctid NOT IN (
  SELECT MIN(ctid)
  FROM public.conversation_participants
  GROUP BY conversation_id, user_id
);

DO $$ BEGIN
  ALTER TABLE public.conversation_participants
    ADD CONSTRAINT unique_conversation_user UNIQUE (conversation_id, user_id);
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- ── 4. MESSAGES TABLE ────────────────────────────────────────────────────────

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_system_message boolean DEFAULT false;

DO $$ BEGIN
  ALTER TABLE public.messages ALTER COLUMN sender_id DROP NOT NULL;
EXCEPTION WHEN others THEN NULL;
END $$;

-- ── 5. INDEXES ───────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conv ON public.conversation_participants(conversation_id);

-- ── 6. RLS POLICIES ──────────────────────────────────────────────────────────

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Helper functions to avoid infinite recursion in RLS
CREATE OR REPLACE FUNCTION public.is_participant_of(conv_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_active_participant_of(conv_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = auth.uid() AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin_of(conv_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id
      AND user_id = auth.uid()
      AND role IN ('creator', 'admin')
      AND status = 'active'
  );
$$;

DROP POLICY IF EXISTS "Users can view conversations they participate in" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "Participants can update conversations" ON public.conversations;
DROP POLICY IF EXISTS "Creator can delete conversations" ON public.conversations;

DROP POLICY IF EXISTS "Users can view participants of their conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Admins can add participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can join as participant" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can update own participation" ON public.conversation_participants;
DROP POLICY IF EXISTS "Admins can update participant roles" ON public.conversation_participants;

DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
DROP POLICY IF EXISTS "Participants can insert messages" ON public.messages;
DROP POLICY IF EXISTS "Senders can update own messages" ON public.messages;

-- Make sure RLS is off for tables we don't manage via RLS
ALTER TABLE public.deleted_conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.deleted_messages DISABLE ROW LEVEL SECURITY;

-- CONVERSATIONS

CREATE POLICY "Users can view conversations they participate in"
  ON public.conversations FOR SELECT
  USING (public.is_participant_of(id));

CREATE POLICY "Users can create conversations"
  ON public.conversations FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Participants can update conversations"
  ON public.conversations FOR UPDATE
  USING (public.is_participant_of(id));

CREATE POLICY "Creator can delete conversations"
  ON public.conversations FOR DELETE
  USING (auth.uid() = created_by);

-- CONVERSATION PARTICIPANTS

CREATE POLICY "Users can view participants of their conversations"
  ON public.conversation_participants FOR SELECT
  USING (public.is_participant_of(conversation_id));

CREATE POLICY "Users can join as participant"
  ON public.conversation_participants FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR public.is_admin_of(conversation_id)
  );

CREATE POLICY "Users can update own participation"
  ON public.conversation_participants FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can update participant roles"
  ON public.conversation_participants FOR UPDATE
  USING (public.is_admin_of(conversation_id));

-- MESSAGES

CREATE POLICY "Participants can view messages"
  ON public.messages FOR SELECT
  USING (public.is_active_participant_of(conversation_id));

CREATE POLICY "Participants can insert messages"
  ON public.messages FOR INSERT
  WITH CHECK (public.is_active_participant_of(conversation_id));

CREATE POLICY "Senders can update own messages"
  ON public.messages FOR UPDATE
  USING (sender_id = auth.uid());

-- ── 7. RPC FUNCTIONS ─────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_group_conversation(uuid, text, text, text, uuid[]);
DROP FUNCTION IF EXISTS public.add_group_participants(uuid, uuid, uuid[]);
DROP FUNCTION IF EXISTS public.remove_group_participant(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.leave_group(uuid, uuid);
DROP FUNCTION IF EXISTS public.promote_to_admin(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.demote_from_admin(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_group_settings(uuid, uuid, boolean, boolean);
DROP FUNCTION IF EXISTS public.update_group_info(uuid, uuid, text, text, text);
DROP FUNCTION IF EXISTS public.get_group_participants(uuid);
DROP FUNCTION IF EXISTS public.transfer_ownership(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_group(uuid, uuid);

CREATE OR REPLACE FUNCTION public.create_group_conversation(
  creator_id uuid,
  group_name text,
  group_description text DEFAULT '',
  group_avatar_url text DEFAULT '',
  member_ids uuid[] DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_conv_id uuid;
  member_id uuid;
  creator_name text;
BEGIN
  SELECT username INTO creator_name FROM public.profiles WHERE id = creator_id;

  INSERT INTO public.conversations (
    is_group, name, description, avatar_url, created_by, updated_at
  ) VALUES (
    true, group_name, group_description, group_avatar_url, creator_id, now()
  ) RETURNING id INTO new_conv_id;

  INSERT INTO public.conversation_participants (conversation_id, user_id, role, status)
  VALUES (new_conv_id, creator_id, 'creator', 'active');

  FOREACH member_id IN ARRAY member_ids
  LOOP
    INSERT INTO public.conversation_participants (conversation_id, user_id, role, status)
    VALUES (new_conv_id, member_id, 'member', 'active');
  END LOOP;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message, created_at)
  VALUES (new_conv_id, creator_id, 'You created this group', true, now());

  RETURN new_conv_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_group_participants(
  conv_id uuid,
  caller_id uuid,
  new_member_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  member_id uuid;
  caller_name text;
  member_name text;
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant of this group';
  END IF;
  IF caller_role NOT IN ('creator', 'admin') THEN
    RAISE EXCEPTION 'Only admins can add members';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;

  FOREACH member_id IN ARRAY new_member_ids
  LOOP
    SELECT username INTO member_name FROM public.profiles WHERE id = member_id;

    INSERT INTO public.conversation_participants (conversation_id, user_id, role, status)
    VALUES (conv_id, member_id, 'member', 'active')
    ON CONFLICT (conversation_id, user_id)
    DO UPDATE SET status = 'active', role = 'member';

    INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
    VALUES (conv_id, caller_id, caller_name || ' added ' || member_name, true);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_group_participant(
  conv_id uuid,
  caller_id uuid,
  target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  target_role text;
  caller_name text;
  target_name text;
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  SELECT role::text INTO target_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = target_id AND status = 'active';

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant of this group';
  END IF;
  IF target_role IS NULL THEN
    RAISE EXCEPTION 'Target user is not an active participant';
  END IF;

  IF caller_role = 'creator' THEN
    IF target_id = caller_id THEN
      RAISE EXCEPTION 'Use leave_group instead';
    END IF;
  ELSIF caller_role = 'admin' THEN
    IF target_role != 'member' THEN
      RAISE EXCEPTION 'Admins can only remove regular members';
    END IF;
  ELSE
    RAISE EXCEPTION 'Only admins can remove members';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;
  SELECT username INTO target_name FROM public.profiles WHERE id = target_id;

  UPDATE public.conversation_participants
  SET status = 'left'
  WHERE conversation_id = conv_id AND user_id = target_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
  VALUES (conv_id, caller_id, caller_name || ' removed ' || target_name, true);
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_group(
  conv_id uuid,
  leaving_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role text;
  leaving_name text;
BEGIN
  SELECT role::text, (SELECT username FROM public.profiles WHERE id = leaving_user_id)
  INTO user_role, leaving_name
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = leaving_user_id AND status = 'active';

  IF user_role IS NULL THEN
    RAISE EXCEPTION 'You are not an active participant';
  END IF;
  IF user_role = 'creator' THEN
    RAISE EXCEPTION 'Creator cannot leave. Transfer ownership first or delete the group.';
  END IF;

  UPDATE public.conversation_participants
  SET status = 'left'
  WHERE conversation_id = conv_id AND user_id = leaving_user_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
  VALUES (conv_id, leaving_user_id, leaving_name || ' left the group', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.promote_to_admin(
  conv_id uuid,
  caller_id uuid,
  target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  target_role text;
  caller_name text;
  target_name text;
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  SELECT role::text INTO target_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = target_id AND status = 'active';

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant';
  END IF;
  IF caller_role NOT IN ('creator', 'admin') THEN
    RAISE EXCEPTION 'Only admins can promote members';
  END IF;
  IF target_role IS NULL THEN
    RAISE EXCEPTION 'Target is not an active participant';
  END IF;
  IF target_role != 'member' THEN
    RAISE EXCEPTION 'Target is already an admin or creator';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;
  SELECT username INTO target_name FROM public.profiles WHERE id = target_id;

  UPDATE public.conversation_participants
  SET role = 'admin'
  WHERE conversation_id = conv_id AND user_id = target_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
  VALUES (conv_id, caller_id, caller_name || ' promoted ' || target_name || ' to admin', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.demote_from_admin(
  conv_id uuid,
  caller_id uuid,
  target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  target_role text;
  caller_name text;
  target_name text;
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  SELECT role::text INTO target_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = target_id AND status = 'active';

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant';
  END IF;
  IF caller_role != 'creator' THEN
    RAISE EXCEPTION 'Only the creator can demote admins';
  END IF;
  IF target_role != 'admin' THEN
    RAISE EXCEPTION 'Target is not an admin';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;
  SELECT username INTO target_name FROM public.profiles WHERE id = target_id;

  UPDATE public.conversation_participants
  SET role = 'member'
  WHERE conversation_id = conv_id AND user_id = target_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
  VALUES (conv_id, caller_id, caller_name || ' demoted ' || target_name || ' from admin', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_group_settings(
  conv_id uuid,
  caller_id uuid,
  new_only_admins_can_message boolean DEFAULT NULL,
  new_only_admins_can_edit_info boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  caller_name text;
  changes text[];
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant';
  END IF;
  IF caller_role NOT IN ('creator', 'admin') THEN
    RAISE EXCEPTION 'Only admins can change group settings';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;

  IF new_only_admins_can_message IS NOT NULL THEN
    UPDATE public.conversations SET only_admins_can_message = new_only_admins_can_message WHERE id = conv_id;
    changes := array_append(changes, CASE WHEN new_only_admins_can_message THEN 'messaging restricted to admins' ELSE 'messaging allowed for all' END);
  END IF;
  IF new_only_admins_can_edit_info IS NOT NULL THEN
    UPDATE public.conversations SET only_admins_can_edit_info = new_only_admins_can_edit_info WHERE id = conv_id;
    changes := array_append(changes, CASE WHEN new_only_admins_can_edit_info THEN 'editing restricted to admins' ELSE 'editing allowed for all' END);
  END IF;

  IF array_length(changes, 1) > 0 THEN
    INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
    VALUES (conv_id, caller_id, caller_name || ' changed settings: ' || array_to_string(changes, ', '), true);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_group_info(
  conv_id uuid,
  caller_id uuid,
  new_name text DEFAULT NULL,
  new_description text DEFAULT NULL,
  new_avatar_url text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  edit_restricted boolean;
  caller_name text;
BEGIN
  SELECT role::text INTO caller_role
  FROM public.conversation_participants
  WHERE conversation_id = conv_id AND user_id = caller_id AND status = 'active';

  SELECT only_admins_can_edit_info INTO edit_restricted
  FROM public.conversations WHERE id = conv_id;

  IF caller_role IS NULL THEN
    RAISE EXCEPTION 'You are not a participant';
  END IF;
  IF edit_restricted AND caller_role NOT IN ('creator', 'admin') THEN
    RAISE EXCEPTION 'Only admins can edit group info';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;

  IF new_name IS NOT NULL THEN
    UPDATE public.conversations SET name = new_name WHERE id = conv_id;
    INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
    VALUES (conv_id, caller_id, caller_name || ' changed the group name to ''' || new_name || '''', true);
  END IF;
  IF new_description IS NOT NULL THEN
    UPDATE public.conversations SET description = new_description WHERE id = conv_id;
  END IF;
  IF new_avatar_url IS NOT NULL THEN
    UPDATE public.conversations SET avatar_url = new_avatar_url WHERE id = conv_id;
  END IF;

  UPDATE public.conversations SET updated_at = now() WHERE id = conv_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_group_participants(conv_id uuid)
RETURNS TABLE (
  user_id uuid,
  role participant_role,
  status text,
  username text,
  full_name text,
  avatar_url text,
  joined_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    cp.user_id,
    cp.role,
    cp.status,
    p.username,
    p.full_name,
    p.avatar_url,
    cp.joined_at
  FROM public.conversation_participants cp
  JOIN public.profiles p ON p.id = cp.user_id
  WHERE cp.conversation_id = conv_id
  ORDER BY
    cp.role = 'creator' DESC,
    cp.role = 'admin' DESC,
    cp.joined_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_ownership(
  conv_id uuid,
  caller_id uuid,
  new_creator_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_name text;
  new_creator_name text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = caller_id AND role = 'creator'
  ) THEN
    RAISE EXCEPTION 'Only the creator can transfer ownership';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = new_creator_id AND role = 'admin' AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'New creator must be an active admin';
  END IF;

  SELECT username INTO caller_name FROM public.profiles WHERE id = caller_id;
  SELECT username INTO new_creator_name FROM public.profiles WHERE id = new_creator_id;

  UPDATE public.conversation_participants
  SET role = 'admin'
  WHERE conversation_id = conv_id AND user_id = caller_id;

  UPDATE public.conversation_participants
  SET role = 'creator'
  WHERE conversation_id = conv_id AND user_id = new_creator_id;

  UPDATE public.conversations SET created_by = new_creator_id WHERE id = conv_id;

  INSERT INTO public.messages (conversation_id, sender_id, content, is_system_message)
  VALUES (conv_id, caller_id, caller_name || ' transferred ownership to ' || new_creator_name, true);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_group(
  conv_id uuid,
  caller_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = caller_id AND role = 'creator'
  ) THEN
    RAISE EXCEPTION 'Only the creator can delete the group';
  END IF;

  DELETE FROM public.deleted_conversations WHERE conversation_id = conv_id;
  DELETE FROM public.deleted_messages
  WHERE message_id IN (SELECT id FROM public.messages WHERE conversation_id = conv_id);
  DELETE FROM public.messages WHERE conversation_id = conv_id;
  DELETE FROM public.conversation_participants WHERE conversation_id = conv_id;
  DELETE FROM public.conversations WHERE id = conv_id;
END;
$$;

-- ── 8. FIX EXISTING SYSTEM MESSAGES (if migration was previously run) ─────────
-- Update any generic system messages left by a prior migration run.
UPDATE public.messages
SET content = 'System message'
WHERE is_system_message = true AND content IN (
  'You created this group', 'New members added', 'A member was removed',
  'A user left the group', 'A user was promoted to admin',
  'A user was demoted from admin', 'Group name was changed',
  'Group ownership was transferred'
);
