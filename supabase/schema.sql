create extension if not exists pgcrypto;

create table if not exists public.members (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  initials text not null,
  avatar_color text not null
);

alter table public.members
  drop column if exists weekly_goal;

create table if not exists public.attendance_records (
  id uuid primary key,
  member_id uuid not null references public.members(id) on delete cascade,
  date timestamptz not null,
  type text not null check (type in ('going', 'notGoing'))
);

drop policy if exists "attendance_records_select_visible" on public.attendance_records;
drop policy if exists "attendance_records_insert_own" on public.attendance_records;
drop policy if exists "attendance_records_update_own" on public.attendance_records;
drop policy if exists "attendance_records_delete_own" on public.attendance_records;

alter table public.attendance_records
  drop column if exists group_id;

-- old 'planned'/'checkedIn' rows predate the gym_visits-based check-in model and can't
-- be migrated (no check-out time to backfill), so drop them before tightening the constraint.
delete from public.attendance_records
where type not in ('going', 'notGoing');

do $$
declare
  target_constraint text;
begin
  select conname
  into target_constraint
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  where t.relname = 'attendance_records'
    and pg_get_constraintdef(c.oid) ilike '%type%'
  limit 1;

  if target_constraint is not null then
    execute format('alter table public.attendance_records drop constraint %I', target_constraint);
  end if;
end $$;

alter table public.attendance_records
add constraint attendance_records_type_check
check (type in ('going', 'notGoing'));

create table if not exists public.gym_visits (
  id uuid primary key,
  member_id uuid not null references public.members(id) on delete cascade,
  check_in_at timestamptz not null,
  check_out_at timestamptz
);

create table if not exists public.chat_messages (
  id uuid primary key,
  sender_member_id uuid not null references public.members(id) on delete cascade,
  body text not null,
  mentioned_member_ids uuid[] not null default '{}'::uuid[],
  created_at timestamptz not null default timezone('utc', now())
);

-- legacy self-recorded training feature removal
drop table if exists public.machine_records cascade;
drop table if exists public.member_monthly_checkin_counts cascade;
drop trigger if exists sync_member_monthly_checkin_counts_trigger on public.attendance_records;
drop function if exists public.sync_member_monthly_checkin_counts();
drop function if exists public.adjust_member_monthly_checkin_count(uuid, date, integer);

-- legacy group feature removal: everyone belongs to a single implicit club now
drop table if exists public.group_memberships cascade;
drop table if exists public.groups cascade;
drop function if exists public.is_group_owner(uuid, uuid);
drop function if exists public.is_group_member(uuid, uuid);
drop function if exists public.find_group_by_invite_code(text);
drop function if exists public.generate_group_invite_code();

create index if not exists idx_attendance_records_member_id on public.attendance_records(member_id);
create index if not exists idx_gym_visits_member_id on public.gym_visits(member_id);
create index if not exists idx_chat_messages_created_at on public.chat_messages(created_at desc);

alter table public.members enable row level security;
alter table public.attendance_records enable row level security;
alter table public.gym_visits enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "members_select_visible" on public.members;
create policy "members_select_visible"
  on public.members
  for select
  using (true);

drop policy if exists "members_insert_own" on public.members;
create policy "members_insert_own"
  on public.members
  for insert
  with check (id = auth.uid());

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "attendance_records_select_visible"
  on public.attendance_records
  for select
  using (true);

create policy "attendance_records_insert_own"
  on public.attendance_records
  for insert
  with check (member_id = auth.uid());

create policy "attendance_records_update_own"
  on public.attendance_records
  for update
  using (member_id = auth.uid())
  with check (member_id = auth.uid());

create policy "attendance_records_delete_own"
  on public.attendance_records
  for delete
  using (member_id = auth.uid());

drop policy if exists "gym_visits_select_visible" on public.gym_visits;
create policy "gym_visits_select_visible"
  on public.gym_visits
  for select
  using (true);

drop policy if exists "gym_visits_insert_own" on public.gym_visits;
create policy "gym_visits_insert_own"
  on public.gym_visits
  for insert
  with check (member_id = auth.uid());

drop policy if exists "gym_visits_update_own" on public.gym_visits;
create policy "gym_visits_update_own"
  on public.gym_visits
  for update
  using (member_id = auth.uid())
  with check (member_id = auth.uid());

drop policy if exists "gym_visits_delete_own" on public.gym_visits;
create policy "gym_visits_delete_own"
  on public.gym_visits
  for delete
  using (member_id = auth.uid());

drop policy if exists "chat_messages_select_visible" on public.chat_messages;
create policy "chat_messages_select_visible"
  on public.chat_messages
  for select
  using (true);

drop policy if exists "chat_messages_insert_own" on public.chat_messages;
create policy "chat_messages_insert_own"
  on public.chat_messages
  for insert
  with check (sender_member_id = auth.uid());
