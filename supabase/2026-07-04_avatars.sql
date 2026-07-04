-- Avatar image upload for muscle_club (PWA)
-- Run this after 2026-07-04_anonymous_member_claim.sql.
--
-- Members can upload a profile image. Files live in a public "avatars"
-- storage bucket, one file per member named "<member_id>.jpg". The public
-- URL (with a cache-busting query) is stored on members.avatar_url so
-- everyone sees everyone's latest icon.

alter table public.members
  add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
on storage.objects
for select
using (bucket_id = 'avatars');

-- Only the member who claimed the row may write "<member_id>.jpg".
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
)
with check (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);
