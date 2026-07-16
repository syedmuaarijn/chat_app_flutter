-- Migration: Add message_receipts for granular tracking
CREATE TABLE public.message_receipts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- 'delivered' or 'read'
  receipt_type text NOT NULL CHECK (receipt_type IN ('delivered', 'read')),
  created_at timestamp with time zone DEFAULT now(),
  PRIMARY KEY (message_id, user_id, receipt_type)
);

-- Index for faster queries on receipt info
CREATE INDEX idx_message_receipts_message_id ON public.message_receipts(message_id);

-- Note: We will eventually remove is_read and is_delivered from public.messages
-- after migrating existing data. For now, we will maintain both.
