-- =============================================================================
-- MESSAGE STATUS SYNC: CONSTRAINTS + TRIGGERS
-- Run this entire script in the Supabase SQL Editor.
-- It is fully idempotent — safe to run multiple times.
-- =============================================================================


-- ── 0. ENSURE TABLE EXISTS ───────────────────────────────────────────────────
-- Create message_receipts if it doesn't exist yet.
CREATE TABLE IF NOT EXISTS public.message_receipts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id    uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL,
  receipt_type  text NOT NULL CHECK (receipt_type IN ('delivered', 'read')),
  created_at    timestamptz NOT NULL DEFAULT now()
);


-- ── 1. UNIQUE CONSTRAINT ──────────────────────────────────────────────────────
-- Required for upsert(onConflict: 'message_id, user_id, receipt_type') to work.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'message_receipts_message_user_type_key'
  ) THEN
    ALTER TABLE public.message_receipts
      ADD CONSTRAINT message_receipts_message_user_type_key
      UNIQUE (message_id, user_id, receipt_type);
  END IF;
END;
$$;


-- ── 2. FOREIGN KEY: user_id → profiles ───────────────────────────────────────
-- Needed for PostgREST to auto-join profiles when querying message_receipts.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'message_receipts_user_id_fkey'
      AND conrelid = 'public.message_receipts'::regclass
  ) THEN
    ALTER TABLE public.message_receipts
      ADD CONSTRAINT message_receipts_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END;
$$;


-- ── 3. ROW-LEVEL SECURITY ─────────────────────────────────────────────────────
-- Allow authenticated users to insert/select their own receipts.
ALTER TABLE public.message_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert their own receipts" ON public.message_receipts;
CREATE POLICY "Users can insert their own receipts"
  ON public.message_receipts
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read receipts for messages they are part of" ON public.message_receipts;
CREATE POLICY "Users can read receipts for messages they are part of"
  ON public.message_receipts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      JOIN public.messages m ON m.conversation_id = cp.conversation_id
      WHERE m.id = message_receipts.message_id
        AND cp.user_id = auth.uid()
        AND cp.status = 'active'
    )
  );


-- ── 4. COMBINED READ + DELIVERED TRIGGER FUNCTION ────────────────────────────
-- A single SECURITY DEFINER function handles both receipt types in one pass.
-- This avoids double-firing and keeps the logic in one place.

CREATE OR REPLACE FUNCTION public.sync_message_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv_id       uuid;
  v_sender_id     uuid;
  v_is_group      boolean;
  v_total_others  integer;  -- active participants excluding sender
  v_receipt_count integer;  -- receipts of the given type for this message
BEGIN
  -- ── Fetch message metadata ────────────────────────────────────────────────
  SELECT conversation_id, sender_id
    INTO v_conv_id, v_sender_id
    FROM public.messages
   WHERE id = NEW.message_id;

  -- Safety: message not found (e.g. deleted)
  IF v_conv_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Do NOT record receipts from the sender themselves
  IF NEW.user_id = v_sender_id THEN
    RETURN NEW;
  END IF;

  -- ── Fetch conversation type ───────────────────────────────────────────────
  SELECT is_group INTO v_is_group
    FROM public.conversations
   WHERE id = v_conv_id;

  -- ── Handle READ receipt ───────────────────────────────────────────────────
  IF NEW.receipt_type = 'read' THEN
    IF v_is_group THEN
      SELECT COUNT(*) INTO v_total_others
        FROM public.conversation_participants
       WHERE conversation_id = v_conv_id
         AND status = 'active'
         AND user_id != v_sender_id;

      SELECT COUNT(*) INTO v_receipt_count
        FROM public.message_receipts
       WHERE message_id = NEW.message_id
         AND receipt_type = 'read'
         AND user_id != v_sender_id;

      IF v_receipt_count >= v_total_others THEN
        UPDATE public.messages
           SET is_read = true, updated_at = now()
         WHERE id = NEW.message_id AND is_read = false;
      END IF;
    ELSE
      -- 1-to-1: any read receipt from the other party → mark read immediately
      UPDATE public.messages
         SET is_read = true, updated_at = now()
       WHERE id = NEW.message_id AND is_read = false;
    END IF;

    -- A read receipt also implies delivery — ensure is_delivered is true too
    UPDATE public.messages
       SET is_delivered = true, updated_at = now()
     WHERE id = NEW.message_id AND is_delivered = false;
  END IF;

  -- ── Handle DELIVERED receipt ──────────────────────────────────────────────
  IF NEW.receipt_type = 'delivered' THEN
    IF v_is_group THEN
      SELECT COUNT(*) INTO v_total_others
        FROM public.conversation_participants
       WHERE conversation_id = v_conv_id
         AND status = 'active'
         AND user_id != v_sender_id;

      -- For group: count both 'delivered' AND 'read' receipts
      -- (a read implies delivery, so it counts toward delivered threshold)
      SELECT COUNT(*) INTO v_receipt_count
        FROM public.message_receipts
       WHERE message_id = NEW.message_id
         AND receipt_type IN ('delivered', 'read')
         AND user_id != v_sender_id;

      IF v_receipt_count >= v_total_others THEN
        UPDATE public.messages
           SET is_delivered = true, updated_at = now()
         WHERE id = NEW.message_id AND is_delivered = false;
      END IF;
    ELSE
      -- 1-to-1: any delivered receipt from the other party → mark delivered
      UPDATE public.messages
         SET is_delivered = true, updated_at = now()
       WHERE id = NEW.message_id AND is_delivered = false;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


-- ── 5. BIND TRIGGER ───────────────────────────────────────────────────────────
-- Drop old separate triggers first, then create one combined trigger.
DROP TRIGGER IF EXISTS on_receipt_read_inserted      ON public.message_receipts;
DROP TRIGGER IF EXISTS on_receipt_delivered_inserted ON public.message_receipts;
DROP TRIGGER IF EXISTS on_receipt_sync               ON public.message_receipts;

CREATE TRIGGER on_receipt_sync
  AFTER INSERT OR UPDATE ON public.message_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_message_status();


-- ── 6. ENABLE REALTIME FOR messages TABLE ────────────────────────────────────
-- The Flutter client subscribes to UPDATE events on messages to detect tick changes.
-- Supabase requires the table to be in the realtime publication.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END;
$$;

-- Also enable realtime for message_receipts (used by message info sheet refresh).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND tablename = 'message_receipts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_receipts;
  END IF;
END;
$$;
