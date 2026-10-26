-- ════════════════════════════════════════════════════════════════════
--  الخطابات والتقارير على الورق الرسمي
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

create table if not exists letters (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null default 'خطاب',
  title       text not null,
  recipient   text,
  body        text not null default '',
  ref         text,
  date        date not null default current_date,
  with_stamp  boolean not null default false,
  with_date   boolean not null default true,
  sign_by     text,
  author_id   uuid references staff(id) on delete set null,
  author_name text,
  author_role text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- لمن أنشأ الجدول قبل إضافة خيار إظهار التاريخ
alter table letters add column if not exists with_date boolean not null default true;
alter table letters add column if not exists sign_by text;

create index if not exists idx_letters_author on letters(author_id);
create index if not exists idx_letters_date   on letters(date desc);

alter table letters enable row level security;

-- الخطاب لكاتبه، ويراه مدير المكتب لأنه يصدر باسم المكتب وعلى ورقه
drop policy if exists letters_read on letters;
create policy letters_read on letters for select using (
  is_owner() or author_id = auth.uid()
);
drop policy if exists letters_write on letters;
create policy letters_write on letters for insert with check (
  is_staff() and author_id = auth.uid() and (is_owner() or has_perm('letters'))
);
drop policy if exists letters_update on letters;
create policy letters_update on letters for update using (
  is_owner() or author_id = auth.uid()
);
drop policy if exists letters_delete on letters;
create policy letters_delete on letters for delete using (
  is_owner() or author_id = auth.uid()
);
