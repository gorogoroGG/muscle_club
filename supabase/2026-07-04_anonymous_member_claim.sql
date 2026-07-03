-- Anonymous auth + member claiming for muscle_club (PWA)
-- Run this after 2026-07-03_pwa_migration.sql.
--
-- The PWA no longer uses email/Apple login. Instead:
--   1. The admin creates member rows directly in the SQL editor
--      (name / initials / avatar_color only, claimed_by left null).
--   2. Each friend opens the PWA, gets a silent anonymous Supabase Auth
--      session (no email sent, so there's no OTP rate limit), and taps
--      their name once to permanently link that anonymous identity to the
--      member row (claimed_by = auth.uid()).
--
-- Existing rows created by the native app (where members.id already equals
-- auth.users.id from Sign in with Apple / magic link) are backfilled so
-- claimed_by = id, keeping the native app working unchanged.
--
-- IMPORTANT: this also requires enabling "Anonymous Sign-Ins" in the
-- Supabase Dashboard under Authentication -> Sign In / Providers.

-- 1) members.id no longer has to equal an auth.users id.
do $$
declare
  target_constraint text;
begin
  select conname
  into target_constraint
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  where t.relname = 'members'
    and c.contype = 'f'
    and c.confrelid = 'auth.users'::regclass
  limit 1;

  if target_constraint is not null then
    execute format('alter table public.members drop constraint %I', target_constraint);
  end if;
end $$;

alter table public.members
  alter column id set default gen_random_uuid();

alter table public.members
  add column if not exists claimed_by uuid references auth.users(id) on delete set null;

-- Backfill: rows created by the native app already have id = auth.users.id,
-- so claiming them by themselves preserves access for existing sign-ins.
-- Rows whose id isn't a real auth.users row (e.g. old test/seed data) are
-- left unclaimed instead, so they become pickable in the web claim screen.
update public.members m
set claimed_by = m.id
where m.claimed_by is null
  and exists (select 1 from auth.users u where u.id = m.id);

create unique index if not exists idx_members_claimed_by
  on public.members(claimed_by)
  where claimed_by is not null;

-- 2) helper: resolves to the member row claimed by the current session
-- (works for anonymous, magic-link, and Apple sessions alike).
create or replace function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members where claimed_by = auth.uid()
$$;

-- 3) members: no client-side insert (admin uses the SQL editor). Update is
-- either claiming an unclaimed row or editing your own already-claimed row.
drop policy if exists "members_insert_own" on public.members;

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members
  for update
  to authenticated
  using (claimed_by is null or claimed_by = auth.uid())
  with check (claimed_by = auth.uid());

-- 4) re-point every other policy from auth.uid() to the claimed member id.
drop policy if exists "attendance_records_insert_own" on public.attendance_records;
create policy "attendance_records_insert_own"
  on public.attendance_records
  for insert
  with check (member_id = public.current_member_id());

drop policy if exists "attendance_records_update_own" on public.attendance_records;
create policy "attendance_records_update_own"
  on public.attendance_records
  for update
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "attendance_records_delete_own" on public.attendance_records;
create policy "attendance_records_delete_own"
  on public.attendance_records
  for delete
  using (member_id = public.current_member_id());

drop policy if exists "gym_visits_insert_own" on public.gym_visits;
create policy "gym_visits_insert_own"
  on public.gym_visits
  for insert
  with check (member_id = public.current_member_id());

drop policy if exists "gym_visits_update_own" on public.gym_visits;
create policy "gym_visits_update_own"
  on public.gym_visits
  for update
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "gym_visits_delete_own" on public.gym_visits;
create policy "gym_visits_delete_own"
  on public.gym_visits
  for delete
  using (member_id = public.current_member_id());

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications
  for select
  to authenticated
  using (recipient_member_id = public.current_member_id());

drop policy if exists "notifications_insert_actor" on public.notifications;
create policy "notifications_insert_actor"
  on public.notifications
  for insert
  to authenticated
  with check (actor_member_id = public.current_member_id());

drop policy if exists "notifications_update_own_read_state" on public.notifications;
create policy "notifications_update_own_read_state"
  on public.notifications
  for update
  to authenticated
  using (recipient_member_id = public.current_member_id())
  with check (recipient_member_id = public.current_member_id());

drop policy if exists "push_subscriptions_select_own" on public.push_subscriptions;
create policy "push_subscriptions_select_own"
  on public.push_subscriptions
  for select
  to authenticated
  using (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_insert_own" on public.push_subscriptions;
create policy "push_subscriptions_insert_own"
  on public.push_subscriptions
  for insert
  to authenticated
  with check (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_update_own" on public.push_subscriptions;
create policy "push_subscriptions_update_own"
  on public.push_subscriptions
  for update
  to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_delete_own" on public.push_subscriptions;
create policy "push_subscriptions_delete_own"
  on public.push_subscriptions
  for delete
  to authenticated
  using (member_id = public.current_member_id());

-- 5) example: how the admin adds a new friend (run manually, one row per
-- person). avatar_color must be one of: blue, indigo, pink, green, orange,
-- teal, purple, red, yellow.
--
-- insert into public.members (name, initials, avatar_color)
-- values ('たろう', 'TR', 'blue');
