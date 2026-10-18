-- ════════════════════════════════════════════════════════════════════
--  اشتراكات الإشعارات: جهاز واحد = سطر واحد
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

create table if not exists push_subscriptions (
  endpoint   text primary key,
  staff_id   uuid not null references staff(id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  device     text,
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);

create index if not exists idx_push_staff on push_subscriptions(staff_id);

alter table push_subscriptions enable row level security;

-- لا يرى أحد اشتراكات غيره ولا يعبث بها
drop policy if exists push_own_read on push_subscriptions;
create policy push_own_read on push_subscriptions for select using (staff_id = auth.uid());
drop policy if exists push_own_write on push_subscriptions;
create policy push_own_write on push_subscriptions for insert with check (staff_id = auth.uid());
drop policy if exists push_own_update on push_subscriptions;
create policy push_own_update on push_subscriptions for update using (staff_id = auth.uid());
drop policy if exists push_own_delete on push_subscriptions;
create policy push_own_delete on push_subscriptions for delete using (staff_id = auth.uid());
