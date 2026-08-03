-- Run this if 012_add_call_history.sql was already applied.

-- Step 1: Drop the old constraint first so the UPDATE below is not blocked.
ALTER TABLE public.call_history
  DROP CONSTRAINT IF EXISTS call_history_status_check;

-- Step 2: Fix any stale rows stuck in 'ringing' or 'active' from calls that
-- ended abnormally (crash, network loss, etc.) before this migration.
UPDATE public.call_history
SET
  status = 'not_picked',
  ended_at = COALESCE(ended_at, now())
WHERE status NOT IN ('completed', 'declined', 'not_picked');

-- Step 3: Re-add the constraint with the full set of valid values.
ALTER TABLE public.call_history
  ADD CONSTRAINT call_history_status_check
  CHECK (status IN ('ringing', 'active', 'completed', 'declined', 'not_picked'));
