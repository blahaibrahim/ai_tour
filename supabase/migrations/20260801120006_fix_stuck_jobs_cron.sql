-- Fix reconcile-stuck-jobs cron: distinguish jobs that never started from jobs that started but ran too long.
-- Previous version: timed out ALL processing jobs after 20 min from queued_at (missed jobs that started late).
-- New version:
--   - Never-started jobs (started_at IS NULL): timeout after 15 min of queuing (cold start window)
--   - Running jobs (started_at IS NOT NULL): timeout after 12 min of running (L4 GPU shape+paint ~5-7 min)

SELECT cron.unschedule('reconcile-stuck-jobs');

SELECT cron.schedule(
  'reconcile-stuck-jobs',
  '*/5 * * * *',
  $$
  UPDATE public.model_jobs
  SET status = 'failed', error_code = 'timeout', finished_at = now()
  WHERE status IN ('queued', 'processing')
    AND (
      -- Never started (cold-start timeout window): queued > 15 min ago but started_at is still null
      (started_at IS NULL AND queued_at < now() - interval '15 minutes')
      OR
      -- Started but exceeded GPU time budget: started > 12 min ago
      (started_at IS NOT NULL AND started_at < now() - interval '12 minutes')
    );
  $$
);
