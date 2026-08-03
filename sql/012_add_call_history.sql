CREATE TABLE IF NOT EXISTS public.call_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL UNIQUE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  caller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  call_type text NOT NULL CHECK (call_type IN ('audio', 'video')),
  status text NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'active', 'completed', 'missed', 'cancelled')),
  started_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_call_history_participants_started ON public.call_history (caller_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_history_receiver_started ON public.call_history (receiver_id, started_at DESC);
ALTER TABLE public.call_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Participants can view call history" ON public.call_history;
CREATE POLICY "Participants can view call history" ON public.call_history FOR SELECT TO authenticated
USING (auth.uid() = caller_id OR auth.uid() = receiver_id);
DROP POLICY IF EXISTS "Caller can create call history" ON public.call_history;
CREATE POLICY "Caller can create call history" ON public.call_history FOR INSERT TO authenticated
WITH CHECK (auth.uid() = caller_id);
DROP POLICY IF EXISTS "Participants can update call history" ON public.call_history;
CREATE POLICY "Participants can update call history" ON public.call_history FOR UPDATE TO authenticated
USING (auth.uid() = caller_id OR auth.uid() = receiver_id)
WITH CHECK (auth.uid() = caller_id OR auth.uid() = receiver_id);
