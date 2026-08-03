-- Adds video-call metadata without changing existing audio call rows.
ALTER TABLE public.call_signals
  ADD COLUMN IF NOT EXISTS call_type text NOT NULL DEFAULT 'audio'
  CHECK (call_type IN ('audio', 'video'));

CREATE INDEX IF NOT EXISTS idx_call_signals_receiver_created_at
  ON public.call_signals (receiver_id, created_at DESC);

-- An authenticated caller must be an active participant of the direct
-- conversation and may not signal a user either party has blocked.
DROP POLICY IF EXISTS "Users can insert call signals" ON public.call_signals;
DROP POLICY IF EXISTS "Active direct-chat participants can signal calls" ON public.call_signals;

CREATE POLICY "Active direct-chat participants can signal calls"
  ON public.call_signals FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = caller_id
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants sender
      JOIN public.conversation_participants receiver
        ON receiver.conversation_id = sender.conversation_id
      JOIN public.conversations conversation
        ON conversation.id = sender.conversation_id
      WHERE sender.conversation_id = split_part(call_signals.conversation_id, ':', 1)::uuid
        AND sender.user_id = auth.uid()
        AND receiver.user_id = call_signals.receiver_id
        AND sender.status = 'active'
        AND receiver.status = 'active'
        AND conversation.is_group = false
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks block
      WHERE (block.blocker_id = auth.uid() AND block.blocked_user_id = call_signals.receiver_id)
         OR (block.blocker_id = call_signals.receiver_id AND block.blocked_user_id = auth.uid())
    )
  );
