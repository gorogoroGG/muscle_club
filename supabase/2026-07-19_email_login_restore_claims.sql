-- Email login for the PWA.
-- Run this after 2026-07-16_member_picker_mode.sql.
--
-- Flow:
--   1. User signs in with a magic link sent to their email address.
--   2. On first login, they pick their member row once.
--   3. That member row is then permanently linked through claimed_by = auth.uid().
--
-- This restores the claimed-member access model after the temporary
-- per-launch member picker mode.

alter table public.members
  add column if not exists claimed_by uuid references auth.users(id) on delete set null;

create unique index if not exists idx_members_claimed_by
  on public.members(claimed_by)
  where claimed_by is not null;

create or replace function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members where claimed_by = auth.uid()
$$;

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members
  for update
  to authenticated
  using (claimed_by is null or claimed_by = auth.uid())
  with check (claimed_by = auth.uid());

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
