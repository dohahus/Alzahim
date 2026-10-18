// ═══════════════════════════════════════════════════════════════════
//  تذكير يومي: جلسات الغد، والمهام التي تستحقّ خلال يومين
//  يُستدعى من مهمة مجدولة في قاعدة البيانات، ويرسل إشعاراً إلى
//  أجهزة أصحاب الشأن ويضع التنبيه في جرس البوابة أيضاً.
// ═══════════════════════════════════════════════════════════════════
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC')!;
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE')!;
const CRON_SECRET   = Deno.env.get('CRON_SECRET')!;
const CONTACT       = Deno.env.get('VAPID_CONTACT') ?? 'mailto:abdullah@alzahimlaw.com';

webpush.setVapidDetails(CONTACT, VAPID_PUBLIC, VAPID_PRIVATE);

// التواريخ بتوقيت الرياض لا بتوقيت الخادم
const riyadh = (plusDays = 0) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Riyadh' })
    .format(new Date(Date.now() + plusDays * 86400000));

const ar = (n: number) => String(n).replace(/\d/g, d => '٠١٢٣٤٥٦٧٨٩'[+d]);

Deno.serve(async (req) => {
  if (req.headers.get('x-cron-secret') !== CRON_SECRET) {
    return new Response('unauthorized', { status: 401 });
  }
  const sb = createClient(SUPABASE_URL, SERVICE_KEY);
  const tomorrow = riyadh(1);
  const soon     = riyadh(2);
  const today    = riyadh(0);

  // رسالة واحدة لكل موظف تجمع ما يخصّه
  const lines = new Map<string, string[]>();
  const add = (staffId: string | null, line: string) => {
    if (!staffId) return;
    if (!lines.has(staffId)) lines.set(staffId, []);
    lines.get(staffId)!.push(line);
  };

  // ───── جلسات الغد ─────
  const { data: hearings } = await sb
    .from('hearings')
    .select('time, court, cases(title, num, lawyer_id)')
    .eq('date', tomorrow);
  for (const h of hearings ?? []) {
    const c: any = h.cases;
    if (!c) continue;
    const when = h.time ? ` الساعة ${h.time}` : '';
    const where = h.court ? ` — ${h.court}` : '';
    add(c.lawyer_id, `جلسة غداً${when}: ${c.title}${where}`);
  }

  // ───── المهام المستحقّة خلال يومين ─────
  const { data: tasks } = await sb
    .from('tasks')
    .select('id, title, due, creator_id, assignee_id, task_assignees(staff_id)')
    .eq('done', false)
    .gte('due', today)
    .lte('due', soon);
  for (const t of tasks ?? []) {
    const days = Math.round(
      (Date.parse(t.due + 'T00:00:00Z') - Date.parse(today + 'T00:00:00Z')) / 86400000);
    const when = days <= 0 ? 'تستحقّ اليوم' : days === 1 ? 'تستحقّ غداً' : `تستحقّ بعد ${ar(days)} أيام`;
    const who = new Set<string>();
    if (t.creator_id) who.add(t.creator_id);
    if (t.assignee_id) who.add(t.assignee_id);
    for (const a of (t.task_assignees as any[] ?? [])) who.add(a.staff_id);
    for (const id of who) add(id, `مهمة ${when}: ${t.title}`);
  }

  if (lines.size === 0) return Response.json({ ok: true, sent: 0, note: 'لا شيء يستحق التذكير' });

  // ───── الإرسال ─────
  const { data: subs } = await sb
    .from('push_subscriptions')
    .select('endpoint, p256dh, auth, staff_id')
    .in('staff_id', [...lines.keys()]);

  const notifRows: any[] = [];
  let sent = 0, dropped = 0;

  for (const [staffId, items] of lines) {
    const title = items.length === 1 ? 'تذكير من بوابة المكتب' : `لديك ${ar(items.length)} تذكيرات`;
    const body  = items.slice(0, 4).join('\n');
    notifRows.push({ title, description: body, for_staff_id: staffId });

    for (const s of (subs ?? []).filter(x => x.staff_id === staffId)) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          JSON.stringify({ title, body, tag: 'daily-' + today, url: '/app/' }),
        );
        sent++;
      } catch (e: any) {
        // اشتراك منتهٍ أو جهاز أُزيل التطبيق منه: يُحذف كي لا يتكرر الفشل
        if (e?.statusCode === 404 || e?.statusCode === 410) {
          await sb.from('push_subscriptions').delete().eq('endpoint', s.endpoint);
          dropped++;
        } else {
          console.error('push failed', e?.statusCode, e?.body ?? e?.message);
        }
      }
    }
  }

  if (notifRows.length) await sb.from('notifications').insert(notifRows);
  return Response.json({ ok: true, staff: lines.size, sent, dropped });
});
