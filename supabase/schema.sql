-- ════════════════════════════════════════════════════════════════════
--  مكتب الزاحم للمحاماة والاستشارات القانونية — مخطط قاعدة البيانات
--  يُنفَّذ في: Supabase Dashboard → SQL Editor → New query → Run
--
--  الملف آمن لإعادة التنفيذ أكثر من مرة: لا يحذف بيانات ولا يفقد سجلاً،
--  وإنما يُعيد بناء الجداول الناقصة وسياسات الحماية فقط.
-- ════════════════════════════════════════════════════════════════════

-- Supabase يضع الإضافات في مخطط extensions لا في public
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ════════════════════════════════════════════════════════════════════
--  الجداول
-- ════════════════════════════════════════════════════════════════════

-- حسابات المكتب (مدير / محامي / مستشار / محاسب / سكرتير)
-- id مرتبط بمعرّف المستخدم في نظام المصادقة
create table if not exists staff (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  username    text not null unique,
  email       text,
  role        text not null default 'محامي',
  perms       jsonb not null default '{}'::jsonb,
  avatar_path text,
  created_at  timestamptz not null default now()
);
-- لقواعد البيانات المُنشأة قبل إضافة البريد
alter table staff add column if not exists email text;

-- الموكلون. auth_user_id يُملأ عند أول دخول للموكل من بوابة العميل
create table if not exists clients (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  name         text not null,
  id_num       text,
  phone        text,
  email        text,
  nationality  text,
  username     text unique,
  notes        text,
  avatar_path  text,
  created_at   timestamptz not null default now()
);

-- القضايا. lawyer_id يربط القضية بالمحامي المسؤول (بدل مطابقة الاسم نصياً)
create table if not exists cases (
  id           uuid primary key default gen_random_uuid(),
  num          text,
  title        text not null,
  type         text not null default 'تجارية',
  client_id    uuid references clients(id) on delete set null,
  court        text,
  dept         text,
  lawyer_id    uuid references staff(id) on delete set null,
  opponent     text,
  next_hearing date,
  status       text not null default 'active'
                 check (status in ('active','pending','closed')),
  progress     int  not null default 10 check (progress between 0 and 100),
  notes        text,
  created_at   timestamptz not null default now()
);

-- المستجد إما جلسة أو مهمة. الجلسة تُنشئ صفاً في جدول الجلسات والمهمة في
-- جدول المهام، فتظهر في قوائمها تلقائياً بلا إضافة يدوية.
-- ولا تُضاف جلسة جديدة قبل كتابة تقرير عن سابقتها.
create table if not exists case_updates (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references cases(id) on delete cascade,
  date       date not null default current_date,
  text       text not null,
  status     text,
  kind       text not null default 'note' check (kind in ('hearing','task','note')),
  hearing_id uuid references hearings(id) on delete set null,
  task_id    uuid references tasks(id) on delete set null,
  created_by text,
  report     text,
  report_by  text,
  report_at  timestamptz,
  created_at timestamptz not null default now()
);
alter table case_updates add column if not exists kind       text not null default 'note';
alter table case_updates add column if not exists hearing_id uuid references hearings(id) on delete set null;
alter table case_updates add column if not exists task_id    uuid references tasks(id) on delete set null;
alter table case_updates add column if not exists created_by text;
alter table case_updates add column if not exists report     text;
alter table case_updates add column if not exists report_by  text;
alter table case_updates add column if not exists report_at  timestamptz;

-- الوكالة وأوراق القضية — الملف نفسه في Supabase Storage، وهنا بياناته فقط
create table if not exists case_documents (
  id           uuid primary key default gen_random_uuid(),
  case_id      uuid not null references cases(id) on delete cascade,
  kind         text not null check (kind in ('agency','papers')),
  name         text not null,
  size         bigint,
  storage_path text not null,
  uploaded_by  text,
  uploaded_at  date not null default current_date
);

create table if not exists hearings (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references cases(id) on delete cascade,
  date       date not null,
  time       text,
  court      text,
  purpose    text,
  notes      text,
  created_at timestamptz not null default now()
);

create table if not exists tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  done         boolean not null default false,
  due          date,
  case_id      uuid references cases(id) on delete set null,
  assignee_id  uuid references staff(id) on delete set null,
  creator_id   uuid references staff(id) on delete set null,
  completed_at date,
  created_at   timestamptz not null default now()
);

-- مهمة واحدة قد تُوكَّل لأكثر من محامٍ
create table if not exists task_assignees (
  task_id  uuid not null references tasks(id) on delete cascade,
  staff_id uuid not null references staff(id) on delete cascade,
  primary key (task_id, staff_id)
);
-- فترة عمل المهمة تُحدَّد يدوياً بدل أن تبدأ من لحظة الإنشاء
alter table tasks add column if not exists start_date date;

create table if not exists task_comments (
  id              uuid primary key default gen_random_uuid(),
  task_id         uuid not null references tasks(id) on delete cascade,
  author_id       uuid references staff(id) on delete set null,
  author_name     text not null,
  text            text,
  attachment_name text,
  attachment_size bigint,
  attachment_path text,
  created_at      timestamptz not null default now()
);

-- عقود الأتعاب. المبلغ نصي لأن المكتب قد يكتب نسبة أو وصفاً بدل رقم
create table if not exists invoices (
  id         uuid primary key default gen_random_uuid(),
  ref        text not null,
  client_id  uuid not null references clients(id) on delete cascade,
  date       date not null default current_date,
  city       text not null default 'المدينة المنورة',
  notes      text,
  created_at timestamptz not null default now()
);

-- نوع المستند وحقوله الإضافية (عرض سعر / فاتورة / عقد استشارات)
alter table invoices add column if not exists kind text not null default 'fee';
alter table invoices drop constraint if exists invoices_kind_chk;
alter table invoices add constraint invoices_kind_chk
  check (kind in ('fee','consulting','quote','invoice'));
alter table invoices add column if not exists subject text;
alter table invoices add column if not exists vat_rate numeric not null default 0;
alter table invoices add column if not exists vat_number text;
alter table invoices add column if not exists valid_days int;
alter table invoices add column if not exists due_date date;
alter table invoices add column if not exists bank_info text;

create table if not exists invoice_cases (
  invoice_id uuid not null references invoices(id) on delete cascade,
  case_id    uuid not null references cases(id) on delete cascade,
  primary key (invoice_id, case_id)
);

create table if not exists installments (
  id         uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  label      text not null,
  amount     text not null default '',
  paid       boolean not null default false,
  sort       int not null default 0
);
-- إيصال السداد ملف في مساحة receipts، والعمود يحفظ مساره واسمه الأصلي
alter table installments add column if not exists receipt_path text;
alter table installments add column if not exists receipt_name text;
alter table installments add column if not exists receipt_size bigint;
alter table installments add column if not exists paid_at date;
alter table installments add column if not exists qty numeric;

-- تذاكر التواصل بين الموكل والمكتب
create table if not exists tickets (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references clients(id) on delete cascade,
  subject    text,
  status     text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);

create table if not exists ticket_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references tickets(id) on delete cascade,
  from_side   text not null check (from_side in ('client','office')),
  author_name text not null,
  text        text not null,
  created_at  timestamptz not null default now()
);

-- الإشعارات. for_staff_id فارغ = تظهر لكل حسابات المكتب
create table if not exists notifications (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  for_staff_id  uuid references staff(id) on delete cascade,
  read          boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists office_settings (
  id      int primary key default 1 check (id = 1),
  name    text not null default 'مكتب الزاحم للمحاماة والاستشارات القانونية',
  license text not null default '38/321',
  phone   text not null default '0148482131',
  mobile  text not null default '+966537475000',
  email   text not null default 'Abdullah@alzahimlaw.com',
  address text not null default 'طريق الملك عبدالله | الدائري الثاني | مقابل سوق بن داود'
);
insert into office_settings (id) values (1) on conflict (id) do nothing;

-- حسابات يُنشئها المدير ويستكملها صاحبها عند أول دخول.
-- كلمة المرور مُعمّاة، ولا يُقرأ هذا الجدول من المتصفح مطلقاً — فقط عبر claim_account
create table if not exists pending_accounts (
  username      text primary key,
  password_hash text not null,
  kind          text not null check (kind in ('staff','client')),
  name          text not null,
  email         text,
  role          text,
  perms         jsonb default '{}'::jsonb,
  client_id     uuid references clients(id) on delete cascade,
  created_at    timestamptz not null default now()
);
alter table pending_accounts add column if not exists email text;

-- ════════════════════════════════════════════════════════════════════
--  دوال مساعدة للحماية
--  SECURITY DEFINER ضروري: بدونه تستدعي السياسة الجدول الذي تحميه فتدخل
--  في استدعاء لا نهائي (infinite recursion)
-- ════════════════════════════════════════════════════════════════════

create or replace function is_staff() returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from staff where id = auth.uid());
$$;

create or replace function is_owner() returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from staff where id = auth.uid() and (perms->>'users')::boolean is true);
$$;

create or replace function has_perm(k text) returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from staff where id = auth.uid() and (perms->>k)::boolean is true);
$$;

create or replace function my_client_id() returns uuid
  language sql stable security definer set search_path = public, extensions as $$
  select id from clients where auth_user_id = auth.uid();
$$;

-- القضايا التي يحق للحساب الحالي رؤيتها
create or replace function can_see_case(c_id uuid) returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from cases c
    where c.id = c_id
      and (
        is_owner()
        or (is_staff() and c.lawyer_id = auth.uid())
        or c.client_id = my_client_id()
      )
  );
$$;

-- من يرى المهمة: صاحب المكتب، أو منشئها، أو أحد المُوكَّلين بها
create or replace function can_see_task(t_id uuid) returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from tasks t
    where t.id = t_id
      and (
        is_owner()
        or (is_staff() and (
             t.assignee_id = auth.uid() or t.creator_id = auth.uid()
             or exists (select 1 from task_assignees ta
                         where ta.task_id = t.id and ta.staff_id = auth.uid())
           ))
      )
  );
$$;

-- ════════════════════════════════════════════════════════════════════
--  تشغيل الحماية على كل الجداول
--  القاعدة: لا يُقرأ أي سطر إلا بسياسة صريحة تسمح به
-- ════════════════════════════════════════════════════════════════════

alter table staff            enable row level security;
alter table clients          enable row level security;
alter table cases            enable row level security;
alter table case_updates     enable row level security;
alter table case_documents   enable row level security;
alter table hearings         enable row level security;
alter table tasks            enable row level security;
alter table task_assignees   enable row level security;
alter table task_comments    enable row level security;
alter table invoices         enable row level security;
alter table invoice_cases    enable row level security;
alter table installments     enable row level security;
alter table tickets          enable row level security;
alter table ticket_messages  enable row level security;
alter table notifications    enable row level security;
alter table office_settings  enable row level security;
alter table pending_accounts enable row level security;
-- pending_accounts: بلا أي سياسة = لا يستطيع المتصفح قراءته أو تعديله إطلاقاً

-- ───────── حسابات المكتب ─────────
drop policy if exists staff_read on staff;
create policy staff_read on staff for select
  using (is_staff() or id = auth.uid());
drop policy if exists staff_self_update on staff;
create policy staff_self_update on staff for update
  using (id = auth.uid() or is_owner());
drop policy if exists staff_owner_write on staff;
create policy staff_owner_write on staff for insert
  with check (id = auth.uid() or is_owner());
drop policy if exists staff_owner_delete on staff;
create policy staff_owner_delete on staff for delete
  using (is_owner());

-- ───────── الموكلون ─────────
-- المحامي لا يرى إلا موكلي قضاياه، والموكل لا يرى إلا نفسه
drop policy if exists clients_read on clients;
create policy clients_read on clients for select using (
  is_owner()
  or id = my_client_id()
  or (is_staff() and exists (select 1 from cases c where c.client_id = clients.id and c.lawyer_id = auth.uid()))
);
drop policy if exists clients_staff_write on clients;
create policy clients_staff_write on clients for insert with check (is_staff());
drop policy if exists clients_staff_update on clients;
create policy clients_staff_update on clients for update using (is_staff() or id = my_client_id());
drop policy if exists clients_owner_delete on clients;
create policy clients_owner_delete on clients for delete using (is_owner());

-- ───────── القضايا ─────────
drop policy if exists cases_read on cases;
create policy cases_read on cases for select using (
  is_owner() or (is_staff() and lawyer_id = auth.uid()) or client_id = my_client_id()
);
drop policy if exists cases_staff_write on cases;
create policy cases_staff_write on cases for insert with check (is_staff());
drop policy if exists cases_staff_update on cases;
create policy cases_staff_update on cases for update using (is_owner() or (is_staff() and lawyer_id = auth.uid()));
drop policy if exists cases_owner_delete on cases;
create policy cases_owner_delete on cases for delete using (is_owner());

-- ───────── مستجدات ومستندات وجلسات القضية: تتبع صلاحية القضية نفسها ─────────
drop policy if exists case_updates_read on case_updates;
create policy case_updates_read on case_updates for select using (can_see_case(case_id));
drop policy if exists case_updates_write on case_updates;
create policy case_updates_write on case_updates for insert with check (is_staff() and can_see_case(case_id));
drop policy if exists case_updates_update on case_updates;
create policy case_updates_update on case_updates for update using (is_staff() and can_see_case(case_id));
drop policy if exists case_updates_delete on case_updates;
create policy case_updates_delete on case_updates for delete using (is_staff() and can_see_case(case_id));

drop policy if exists case_documents_read on case_documents;
create policy case_documents_read on case_documents for select using (can_see_case(case_id));
drop policy if exists case_documents_write on case_documents;
create policy case_documents_write on case_documents for insert with check (is_staff() and can_see_case(case_id));
drop policy if exists case_documents_delete on case_documents;
create policy case_documents_delete on case_documents for delete using (is_staff() and can_see_case(case_id));

drop policy if exists hearings_read on hearings;
create policy hearings_read on hearings for select using (can_see_case(case_id));
drop policy if exists hearings_write on hearings;
create policy hearings_write on hearings for insert with check (is_staff() and can_see_case(case_id));
drop policy if exists hearings_update on hearings;
create policy hearings_update on hearings for update using (is_staff() and can_see_case(case_id));
drop policy if exists hearings_delete on hearings;
create policy hearings_delete on hearings for delete using (is_staff() and can_see_case(case_id));

-- ───────── المهام: للمكتب فقط، والمحامي يرى ما وُكِّل به ─────────
drop policy if exists tasks_read on tasks;
create policy tasks_read on tasks for select using (
  is_owner() or (is_staff() and (
    assignee_id = auth.uid() or creator_id = auth.uid()
    or exists (select 1 from task_assignees ta where ta.task_id = tasks.id and ta.staff_id = auth.uid())
  ))
);
drop policy if exists tasks_write on tasks;
create policy tasks_write on tasks for insert with check (is_staff());
drop policy if exists tasks_update on tasks;
create policy tasks_update on tasks for update using (
  is_owner() or (is_staff() and (
    assignee_id = auth.uid() or creator_id = auth.uid()
    or exists (select 1 from task_assignees ta where ta.task_id = tasks.id and ta.staff_id = auth.uid())
  ))
);
drop policy if exists tasks_delete on tasks;
create policy tasks_delete on tasks for delete using (
  is_owner() or (is_staff() and creator_id = auth.uid())
);

drop policy if exists task_assignees_read on task_assignees;
create policy task_assignees_read on task_assignees for select using (can_see_task(task_id));
drop policy if exists task_assignees_write on task_assignees;
create policy task_assignees_write on task_assignees for insert with check (is_staff() and can_see_task(task_id));
drop policy if exists task_assignees_delete on task_assignees;
create policy task_assignees_delete on task_assignees for delete using (is_staff() and can_see_task(task_id));

drop policy if exists task_comments_read on task_comments;
create policy task_comments_read on task_comments for select using (can_see_task(task_id));
drop policy if exists task_comments_write on task_comments;
create policy task_comments_write on task_comments for insert with check (
  is_staff() and exists (select 1 from tasks t where t.id = task_id
    and (is_owner() or t.assignee_id = auth.uid() or t.creator_id = auth.uid()))
);

-- ───────── المالية: حسابات المكتب ذات صلاحية الفواتير + الموكل صاحب العقد ─────────
drop policy if exists invoices_read on invoices;
create policy invoices_read on invoices for select using (
  has_perm('invoices') or client_id = my_client_id()
);
drop policy if exists invoices_write on invoices;
create policy invoices_write on invoices for insert with check (has_perm('invoices'));
drop policy if exists invoices_update on invoices;
create policy invoices_update on invoices for update using (has_perm('invoices'));
drop policy if exists invoices_delete on invoices;
create policy invoices_delete on invoices for delete using (has_perm('invoices'));

drop policy if exists invoice_cases_read on invoice_cases;
create policy invoice_cases_read on invoice_cases for select using (
  exists (select 1 from invoices i where i.id = invoice_id
    and (has_perm('invoices') or i.client_id = my_client_id()))
);
drop policy if exists invoice_cases_write on invoice_cases;
create policy invoice_cases_write on invoice_cases for insert with check (has_perm('invoices'));
drop policy if exists invoice_cases_delete on invoice_cases;
create policy invoice_cases_delete on invoice_cases for delete using (has_perm('invoices'));

drop policy if exists installments_read on installments;
create policy installments_read on installments for select using (
  exists (select 1 from invoices i where i.id = invoice_id
    and (has_perm('invoices') or i.client_id = my_client_id()))
);
drop policy if exists installments_write on installments;
create policy installments_write on installments for insert with check (has_perm('invoices'));
drop policy if exists installments_update on installments;
create policy installments_update on installments for update using (has_perm('invoices'));
drop policy if exists installments_delete on installments;
create policy installments_delete on installments for delete using (has_perm('invoices'));

-- ───────── تذاكر التواصل ─────────
drop policy if exists tickets_read on tickets;
create policy tickets_read on tickets for select using (
  is_owner() or client_id = my_client_id()
  or (is_staff() and exists (select 1 from cases c where c.client_id = tickets.client_id and c.lawyer_id = auth.uid()))
);
drop policy if exists tickets_write on tickets;
create policy tickets_write on tickets for insert with check (is_staff() or client_id = my_client_id());
drop policy if exists tickets_update on tickets;
create policy tickets_update on tickets for update using (
  is_staff() or client_id = my_client_id()
);

drop policy if exists ticket_messages_read on ticket_messages;
create policy ticket_messages_read on ticket_messages for select using (
  exists (select 1 from tickets t where t.id = ticket_id
    and (is_owner() or t.client_id = my_client_id()
      or (is_staff() and exists (select 1 from cases c where c.client_id = t.client_id and c.lawyer_id = auth.uid()))))
);
drop policy if exists ticket_messages_write on ticket_messages;
create policy ticket_messages_write on ticket_messages for insert with check (
  exists (select 1 from tickets t where t.id = ticket_id
    and (is_staff() or t.client_id = my_client_id()))
);

-- ───────── الإشعارات ─────────
drop policy if exists notifications_read on notifications;
create policy notifications_read on notifications for select using (
  is_staff() and (for_staff_id is null or for_staff_id = auth.uid())
);
drop policy if exists notifications_write on notifications;
create policy notifications_write on notifications for insert with check (is_staff() or my_client_id() is not null);
drop policy if exists notifications_update on notifications;
create policy notifications_update on notifications for update using (
  is_staff() and (for_staff_id is null or for_staff_id = auth.uid())
);

-- ───────── بيانات المكتب ─────────
drop policy if exists office_read on office_settings;
create policy office_read on office_settings for select using (true);
drop policy if exists office_update on office_settings;
create policy office_update on office_settings for update using (has_perm('settings'));

-- ════════════════════════════════════════════════════════════════════
--  إنشاء الحسابات
--  المدير ينشئ الحساب هنا، ويستكمله صاحبه في متصفحه عند أول دخول.
--  بهذه الطريقة لا تُستخدم مفاتيح الإدارة في المتصفح ولا تُستبدل جلسة المدير.
-- ════════════════════════════════════════════════════════════════════

-- البريد المستخدَم في نظام المصادقة: البريد الحقيقي إن وُجد (فتعمل استعادة
-- كلمة المرور)، وإلّا بريد اصطناعي من اسم المستخدم (فلا استعادة، ويعيد المدير ضبطها)
create or replace function auth_email_for(p_username text, p_email text)
returns text language sql immutable as $$
  select case
    when p_email is not null and btrim(p_email) <> '' then lower(btrim(p_email))
    else lower(btrim(p_username)) || '@alzahimlaw.app'
  end;
$$;

drop function if exists create_pending_account(text, text, text, text, text, jsonb, uuid);
create or replace function create_pending_account(
  p_username text, p_password text, p_kind text,
  p_name text, p_role text default null,
  p_perms jsonb default '{}'::jsonb, p_client_id uuid default null,
  p_email text default null
) returns void
  language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_owner() then
    raise exception 'غير مصرَّح: إنشاء الحسابات لمدير المكتب فقط';
  end if;
  if exists (select 1 from staff where username = p_username)
     or exists (select 1 from clients where username = p_username and id is distinct from p_client_id) then
    raise exception 'اسم المستخدم مستخدم مسبقاً';
  end if;
  if p_email is not null and btrim(p_email) <> '' then
    if exists (select 1 from staff where lower(email) = lower(btrim(p_email)))
       or exists (select 1 from clients where lower(email) = lower(btrim(p_email)) and id is distinct from p_client_id) then
      raise exception 'البريد الإلكتروني مستخدم لحساب آخر';
    end if;
  end if;
  insert into pending_accounts (username, password_hash, kind, name, email, role, perms, client_id)
  values (p_username, crypt(p_password, gen_salt('bf')), p_kind, p_name,
          nullif(btrim(coalesce(p_email,'')),''), p_role, p_perms, p_client_id)
  on conflict (username) do update
    set password_hash = excluded.password_hash, kind = excluded.kind, name = excluded.name,
        email = excluded.email, role = excluded.role, perms = excluded.perms,
        client_id = excluded.client_id;
end;
$$;

-- الحساب الأول للمكتب: يعمل مرة واحدة فقط ما دام جدول المكتب فارغاً،
-- لأن إنشاء الحسابات العادية يتطلب وجود مدير مسبقاً
drop function if exists bootstrap_owner(text, text, text);
create or replace function bootstrap_owner(
  p_username text, p_password text, p_name text, p_email text default null
) returns void
  language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from staff) then
    raise exception 'تم إنشاء حساب المكتب مسبقاً — تُنشأ بقية الحسابات من صفحة الإعدادات';
  end if;
  insert into pending_accounts (username, password_hash, kind, name, email, role, perms)
  values (p_username, crypt(p_password, gen_salt('bf')), 'staff', p_name,
    nullif(btrim(coalesce(p_email,'')),''), 'مدير المكتب',
    '{"cases":true,"hearings":true,"tasks":true,"clients":true,"invoices":true,"reports":true,"settings":true,"users":true}'::jsonb)
  on conflict (username) do update
    set password_hash = excluded.password_hash, perms = excluded.perms,
        role = excluded.role, name = excluded.name, email = excluded.email;
end;
$$;

-- يتحقق من المُعرِّف (اسم مستخدم أو بريد أو رقم هوية) وكلمة المرور،
-- ويعيد البريد المستخدَم في نظام المصادقة. لا يكشف كلمة المرور.
drop function if exists claim_account(text, text);
create or replace function claim_account(p_identifier text, p_password text)
returns table (auth_email text, kind text, already_registered boolean)
  language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id      text := lower(btrim(p_identifier));
  v_pending pending_accounts;
  v_staff   staff;
  v_client  clients;
begin
  select * into v_pending from pending_accounts
   where lower(username) = v_id or lower(email) = v_id;
  if v_pending.username is not null
     and v_pending.password_hash = crypt(p_password, v_pending.password_hash) then
    return query select auth_email_for(v_pending.username, v_pending.email), v_pending.kind, false;
    return;
  end if;

  -- حساب مُسجَّل مسبقاً: يُترك التحقق من كلمة المرور لنظام المصادقة
  select * into v_staff from staff where lower(username) = v_id or lower(email) = v_id;
  if v_staff.id is not null then
    return query select auth_email_for(v_staff.username, v_staff.email), 'staff'::text, true;
    return;
  end if;
  select * into v_client from clients
   where lower(username) = v_id or lower(email) = v_id or lower(id_num) = v_id;
  if v_client.id is not null then
    return query select auth_email_for(v_client.username, v_client.email), 'client'::text, true;
    return;
  end if;

  raise exception 'بيانات الدخول غير صحيحة';
end;
$$;

-- يُستدعى بعد نجاح التسجيل ليُنشئ سطر المكتب/الموكل ويُفرِّغ الحساب المعلَّق
-- تُعاد كلمة المرور هنا ويُتحقَّق منها مرة أخرى.
-- بدون ذلك يستطيع أي حساب مسجَّل (موكل مثلاً) استدعاء الدالة باسم مستخدم مديرٍ
-- معلَّق فيُدرج نفسه في جدول المكتب بصلاحيات كاملة
drop function if exists finalize_account(text);
drop function if exists finalize_account(text, text);
create or replace function finalize_account(p_identifier text, p_password text)
returns void
  language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id      text := lower(btrim(p_identifier));
  v_pending pending_accounts;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;
  -- يُبحَث بنفس معايير claim_account (اسم مستخدم أو بريد)، وإلّا نجحت المصادقة
  -- بالبريد ثم لم يُربَط الحساب فيبقى معلَّقاً بلا سطر في جداول المكتب
  select * into v_pending from pending_accounts
   where lower(username) = v_id or lower(email) = v_id;

  if v_pending.username is null then
    -- الحساب مكتمل أصلاً: ليس خطأً
    if exists (select 1 from staff where id = auth.uid())
       or exists (select 1 from clients where auth_user_id = auth.uid()) then
      return;
    end if;
    -- لا حساب معلَّق ولا سطر مكتمل: يجب أن يظهر الخطأ بدل الخروج بصمت
    raise exception 'لا يوجد حساب معلَّق بهذا المعرّف';
  end if;

  if v_pending.password_hash <> crypt(p_password, v_pending.password_hash) then
    raise exception 'بيانات الدخول غير صحيحة';
  end if;

  if v_pending.kind = 'staff' then
    insert into staff (id, name, username, email, role, perms)
    values (auth.uid(), v_pending.name, v_pending.username, v_pending.email,
            coalesce(v_pending.role,'محامي'), coalesce(v_pending.perms,'{}'::jsonb))
    on conflict (id) do update set name = excluded.name, username = excluded.username,
            email = excluded.email, role = excluded.role, perms = excluded.perms;
  else
    update clients set auth_user_id = auth.uid(), username = v_pending.username,
           email = coalesce(v_pending.email, email)
    where id = v_pending.client_id;
  end if;

  delete from pending_accounts where username = v_pending.username;
end;
$$;

-- ════════════════════════════════════════════════════════════════════
--  تقييد الوصول للدوال الحسّاسة
--  الدوال في PostgreSQL متاحة للجميع افتراضياً، وواجهة Supabase تعرضها
--  للاستدعاء من المتصفح. فيجب سحب الصلاحية صراحةً عن الدوال التي لا
--  يُفترض استدعاؤها من المتصفح.
-- ════════════════════════════════════════════════════════════════════

-- ملاحظة جوهرية: PostgreSQL يمنح صلاحية تنفيذ الدالة لـ PUBLIC تلقائياً عند
-- إنشائها، وكل الأدوار ترث منه. فالسحب من anon و authenticated وحدهما لا يكفي —
-- تبقى الصلاحية موروثة عبر PUBLIC. لذا يُسحب من PUBLIC صراحةً.

-- أمر تهيئة لمرة واحدة يُنفَّذ من SQL Editor فقط.
-- بدونه يستطيع أي زائر مجهول استدعاءه — ما دام جدول المكتب فارغاً —
-- فيستبدل حساب المدير بكلمة مرور من عنده ويصبح مدير المكتب
revoke all on function bootstrap_owner(text, text, text, text) from public, anon, authenticated;

-- إنشاء الحسابات لمدير المكتب المسجَّل فقط (والدالة تتحقق أيضاً بنفسها)
revoke all on function create_pending_account(text, text, text, text, text, jsonb, uuid, text) from public, anon;
grant execute on function create_pending_account(text, text, text, text, text, jsonb, uuid, text) to authenticated;

-- جدول الحسابات المعلَّقة: لا يُقرأ ولا يُكتب من المتصفح إطلاقاً.
-- الدوال أعلاه تصل إليه لأنها SECURITY DEFINER فتُنفَّذ بصلاحيات مالكها
revoke all on table pending_accounts from public, anon, authenticated;

-- الدوال المستخدَمة داخل سياسات الحماية (is_staff / is_owner / has_perm /
-- my_client_id / can_see_case) وكذلك claim_account و finalize_account
-- تبقى متاحة عن قصد: الأولى تُقيَّم بصلاحيات الدور السائل فتحتاجها السياسات،
-- والأخيرتان هما مسار تسجيل الدخول نفسه ومحميّتان بالتحقق من كلمة المرور.

-- ════════════════════════════════════════════════════════════════════
--  مساحة تخزين الملفات (المستندات ومرفقات المهام والصور الشخصية)
-- ════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('case-docs','case-docs',false), ('task-files','task-files',false),
       ('avatars','avatars',true), ('receipts','receipts',false)
on conflict (id) do nothing;

-- مستندات القضايا: يُقرأ الملف بحسب صلاحية القضية المذكورة في أول مقطع من المسار
drop policy if exists case_docs_read on storage.objects;
create policy case_docs_read on storage.objects for select using (
  bucket_id = 'case-docs' and can_see_case(((storage.foldername(name))[1])::uuid)
);
drop policy if exists case_docs_write on storage.objects;
create policy case_docs_write on storage.objects for insert with check (
  bucket_id = 'case-docs' and is_staff() and can_see_case(((storage.foldername(name))[1])::uuid)
);
drop policy if exists case_docs_delete on storage.objects;
create policy case_docs_delete on storage.objects for delete using (
  bucket_id = 'case-docs' and is_staff() and can_see_case(((storage.foldername(name))[1])::uuid)
);

drop policy if exists task_files_read on storage.objects;
create policy task_files_read on storage.objects for select using (
  bucket_id = 'task-files' and is_staff()
);
drop policy if exists task_files_write on storage.objects;
create policy task_files_write on storage.objects for insert with check (
  bucket_id = 'task-files' and is_staff()
);

-- إيصالات الدفعات بيانات مالية: لا يراها إلا من يملك صلاحية الفواتير.
-- الموكل لا يصل إليها ولو عرف المسار، لأن السياسة تُطبَّق على الملف نفسه
drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects for select using (
  bucket_id = 'receipts' and has_perm('invoices')
);
drop policy if exists receipts_write on storage.objects;
create policy receipts_write on storage.objects for insert with check (
  bucket_id = 'receipts' and has_perm('invoices')
);
drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects for delete using (
  bucket_id = 'receipts' and has_perm('invoices')
);

drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select using (bucket_id = 'avatars');
drop policy if exists avatars_write on storage.objects;
create policy avatars_write on storage.objects for insert with check (
  bucket_id = 'avatars' and auth.uid() is not null and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update using (
  bucket_id = 'avatars' and auth.uid() is not null and (storage.foldername(name))[1] = auth.uid()::text
);

-- ════════════════════════════════════════════════════════════════════
--  فهارس للأداء
-- ════════════════════════════════════════════════════════════════════
create index if not exists idx_cases_lawyer      on cases(lawyer_id);
create index if not exists idx_cases_client      on cases(client_id);
create index if not exists idx_case_updates_case on case_updates(case_id);
create index if not exists idx_case_docs_case    on case_documents(case_id);
create index if not exists idx_hearings_case     on hearings(case_id);
create index if not exists idx_hearings_date     on hearings(date);
create index if not exists idx_tasks_assignee    on tasks(assignee_id);
create index if not exists idx_task_comments     on task_comments(task_id);
create index if not exists idx_invoices_client   on invoices(client_id);
create index if not exists idx_installments_inv  on installments(invoice_id);
create index if not exists idx_tickets_client    on tickets(client_id);
create index if not exists idx_ticket_msgs       on ticket_messages(ticket_id);
