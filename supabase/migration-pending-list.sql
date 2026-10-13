-- ════════════════════════════════════════════════════════════════════
--  إظهار الحسابات المعلَّقة لمدير المكتب — نفّذه مرة واحدة
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- جدول الحسابات المعلَّقة محجوب عن المتصفح لأنه يحوي كلمات المرور معمّاة.
-- هذه الدالة تُعيد ما يحتاجه المدير فقط — بلا كلمة المرور إطلاقاً
drop function if exists list_pending_accounts();
create or replace function list_pending_accounts()
returns table (username text, name text, role text, kind text, email text, created_at timestamptz)
  language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_owner() then
    raise exception 'غير مصرَّح';
  end if;
  return query
    select p.username, p.name, p.role, p.kind, p.email, p.created_at
    from pending_accounts p
    order by p.created_at desc;
end;
$$;
revoke all on function list_pending_accounts() from public, anon;
grant execute on function list_pending_accounts() to authenticated;

-- إلغاء دعوة لم تُستخدم بعد
drop function if exists cancel_pending_account(text);
create or replace function cancel_pending_account(p_username text)
returns void
  language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_owner() then
    raise exception 'غير مصرَّح';
  end if;
  delete from pending_accounts where username = p_username;
end;
$$;
revoke all on function cancel_pending_account(text) from public, anon;
grant execute on function cancel_pending_account(text) to authenticated;
