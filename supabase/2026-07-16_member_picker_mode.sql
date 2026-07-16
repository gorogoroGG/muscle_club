-- Member-picker mode for the PWA.
-- Run this after 2026-07-04_anonymous_member_claim.sql.
--
-- The web app no longer permanently binds a device to members.claimed_by.
-- Instead, an anonymous session picks a member at launch time and acts as
-- that member for the duration of the app session.
--
-- This intentionally favors simple shared-family usage over strong identity
-- guarantees: any authenticated PWA session may act as any member row.

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "attendance_records_insert_own" on public.attendance_records;
create policy "attendance_records_insert_own"
  on public.attendance_records
  for insert
  to authenticated
  with check (true);

drop policy if exists "attendance_records_update_own" on public.attendance_records;
create policy "attendance_records_update_own"
  on public.attendance_records
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "attendance_records_delete_own" on public.attendance_records;
create policy "attendance_records_delete_own"
  on public.attendance_records
  for delete
  to authenticated
  using (true);

drop policy if exists "gym_visits_insert_own" on public.gym_visits;
create policy "gym_visits_insert_own"
  on public.gym_visits
  for insert
  to authenticated
  with check (true);

drop policy if exists "gym_visits_update_own" on public.gym_visits;
create policy "gym_visits_update_own"
  on public.gym_visits
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "gym_visits_delete_own" on public.gym_visits;
create policy "gym_visits_delete_own"
  on public.gym_visits
  for delete
  to authenticated
  using (true);

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications
  for select
  to authenticated
  using (true);

drop policy if exists "notifications_insert_actor" on public.notifications;
create policy "notifications_insert_actor"
  on public.notifications
  for insert
  to authenticated
  with check (actor_member_id is not null);

drop policy if exists "notifications_update_own_read_state" on public.notifications;
create policy "notifications_update_own_read_state"
  on public.notifications
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "push_subscriptions_select_own" on public.push_subscriptions;
create policy "push_subscriptions_select_own"
  on public.push_subscriptions
  for select
  to authenticated
  using (true);

drop policy if exists "push_subscriptions_insert_own" on public.push_subscriptions;
create policy "push_subscriptions_insert_own"
  on public.push_subscriptions
  for insert
  to authenticated
  with check (true);

drop policy if exists "push_subscriptions_update_own" on public.push_subscriptions;
create policy "push_subscriptions_update_own"
  on public.push_subscriptions
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "push_subscriptions_delete_own" on public.push_subscriptions;
create policy "push_subscriptions_delete_own"
  on public.push_subscriptions
  for delete
  to authenticated
  using (true);
