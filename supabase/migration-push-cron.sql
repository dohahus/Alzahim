-- ════════════════════════════════════════════════════════════════════
--  جدولة التذكير اليومي — بعد نشر الوظيفة send-reminders
--  يُنفَّذ مرة واحدة. استبدل <CRON_SECRET> بالقيمة نفسها المحفوظة في أسرار الوظيفة.
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('alzahim-daily-reminders')
where exists (select 1 from cron.job where jobname = 'alzahim-daily-reminders');

-- ٤:٠٠ بتوقيت غرينتش = ٧:٠٠ صباحاً بتوقيت الرياض
select cron.schedule(
  'alzahim-daily-reminders',
  '0 4 * * *',
  $$
  select net.http_post(
    url     := 'https://javmazwxrdkylewhjahu.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', '<CRON_SECRET>'),
    body    := '{}'::jsonb
  );
  $$
);

-- للتحقّق
select jobname as "المهمة", schedule as "التوقيت", active as "مفعّلة" from cron.job;
