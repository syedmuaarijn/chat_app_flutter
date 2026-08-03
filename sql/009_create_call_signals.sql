-- Create call_signals table for Agora call signaling
CREATE TABLE IF NOT EXISTS public.call_signals (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id TEXT        NOT NULL,
  caller_id      UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id    UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  signal_type    TEXT         NOT NULL CHECK (signal_type IN ('invite', 'accept', 'decline', 'end')),
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Index for fast receiver lookups (realtime subscriptions filter by this)
CREATE INDEX IF NOT EXISTS idx_call_signals_receiver ON public.call_signals(receiver_id);
-- Index for fast conversation lookups
CREATE INDEX IF NOT EXISTS idx_call_signals_conversation ON public.call_signals(conversation_id);

-- Auto-delete old signals after 60 seconds (keep DB clean)
-- (Run a Supabase cron job or just handle in app; signals are ephemeral)

-- Enable Row Level Security
ALTER TABLE public.call_signals ENABLE ROW LEVEL SECURITY;

-- Callers can insert signals
CREATE POLICY "Users can insert call signals" ON public.call_signals
  FOR INSERT WITH CHECK (auth.uid() = caller_id);

-- Users can read signals where they are the receiver OR caller
CREATE POLICY "Users can read their own call signals" ON public.call_signals
  FOR SELECT USING (auth.uid() = caller_id OR auth.uid() = receiver_id);

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE public.call_signals;
