-- ════════════════════════════════════════════════════════════════════
--  إصلاح الدخول وحفظ بريد الحسابات — يُنفَّذ مرة واحدة
--  لا يمسّ القضايا ولا الموكّلين ولا الصلاحيات
-- ════════════════════════════════════════════════════════════════════

-- ١) ربط البريد الحقيقي بسطرَي المكتب، فيعود الدخول بالاسم أو بالبريد
alter table staff             add column if not exists email text;
alter table pending_accounts  add column if not exists email text;

update staff s set email = u.email
from auth.users u
where u.id = s.id
  and s.email is null
  and u.email not like '%@zahemlaw.app'
  and u.email not like '%@alzahimlaw.app';

-- ٢) إزالة كل النسخ القديمة من دالتَي إنشاء الحساب واستكماله
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('create_pending_account','finalize_account')
  loop
    execute 'drop function ' || r.sig;
  end loop;
end $$;

-- ٣) النسخة التي تحفظ البريد مع الحساب
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
  select * into v_pending from pending_accounts
   where lower(username) = v_id or lower(email) = v_id;

  if v_pending.username is null then
    if exists (select 1 from staff where id = auth.uid())
       or exists (select 1 from clients where auth_user_id = auth.uid()) then
      return;
    end if;
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

revoke all on function create_pending_account(text, text, text, text, text, jsonb, uuid, text) from public, anon;
grant execute on function create_pending_account(text, text, text, text, text, jsonb, uuid, text) to authenticated;
grant execute on function finalize_account(text, text) to authenticated;

-- ٤) التحقّق: يجب أن يظهر بريد لكل سطر، ويطابق بريد المصادقة
select s.username as "اسم المستخدم", s.email as "بريد الجدول",
       u.email as "بريد المصادقة",
       (lower(s.email) = lower(u.email)) as "متطابقان"
from staff s left join auth.users u on u.id = s.id order by s.username;
