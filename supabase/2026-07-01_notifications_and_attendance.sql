-- Notifications + attendance status expansion for muscle_club
-- Run this in the Supabase SQL editor before testing the new notification flow.

create table if not exists public.notifications (
    id uuid primary key,
    recipient_member_id uuid not null references public.members(id) on delete cascade,
    actor_member_id uuid references public.members(id) on delete set null,
    type text not null check (
        type in (
            'going',
            'notGoing',
            'checkedIn',
            'checkedOut',
            'checkInCancelled',
            'chatMessage'
        )
    ),
    title text not null,
    message text not null,
    created_at timestamptz not null default timezone('utc', now()),
    read_at timestamptz
);

alter table public.notifications
    drop column if exists group_id;

-- old 'joinRequest'/'memberJoined' rows predate the group feature removal and are no
-- longer a valid notification type, so drop them before tightening the constraint.
delete from public.notifications
where type not in ('going', 'notGoing', 'checkedIn', 'checkedOut', 'checkInCancelled', 'chatMessage');

do $$
declare
    target_constraint text;
begin
    select conname
    into target_constraint
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'notifications'
      and pg_get_constraintdef(c.oid) ilike '%type%'
    limit 1;

    if target_constraint is not null then
        execute format('alter table public.notifications drop constraint %I', target_constraint);
    end if;
end $$;

alter table public.notifications
add constraint notifications_type_check
check (type in ('going', 'notGoing', 'checkedIn', 'checkedOut', 'checkInCancelled', 'chatMessage'));

drop index if exists notifications_group_created_idx;

create index if not exists notifications_recipient_created_idx
    on public.notifications (recipient_member_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications
for select
to authenticated
using (recipient_member_id = auth.uid());

drop policy if exists "notifications_insert_actor" on public.notifications;
create policy "notifications_insert_actor"
on public.notifications
for insert
to authenticated
with check (actor_member_id = auth.uid());

drop policy if exists "notifications_update_own_read_state" on public.notifications;
create policy "notifications_update_own_read_state"
on public.notifications
for update
to authenticated
using (recipient_member_id = auth.uid())
with check (recipient_member_id = auth.uid());

-- attendance_records.type constraint is now owned by schema.sql (going/notGoing only);
-- run schema.sql after this file, or re-run it, to ensure the final constraint applies.
