-- Tharaka University Housing Hub: run in Supabase SQL Editor
create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,full_name text,role text not null default 'student' check(role in ('student','landlord','admin')),created_at timestamptz not null default now());
create table if not exists public.listings(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id) on delete cascade,name text not null check(char_length(name) between 2 and 90),location text not null check(char_length(location) between 2 and 100),type text not null check(type in ('Single room','Shared room','Hostel','Self-contained','Bedsitter')),price integer not null check(price>0 and price<=1000000),phone text not null,features text[] not null default '{}',description text not null default '',photos text[] not null default '{}',status text not null default 'pending' check(status in ('pending','approved','rejected')),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index if not exists listings_status_created_idx on public.listings(status,created_at desc);
-- Exact map coordinates selected by the landlord when submitting a room.
alter table public.listings add column if not exists latitude double precision;
alter table public.listings add column if not exists longitude double precision;

-- Store a dedicated WhatsApp contact for each landlord listing. Existing listings reuse their phone number.
alter table public.listings add column if not exists whatsapp_phone text;
update public.listings set whatsapp_phone=phone where whatsapp_phone is null;
alter table public.listings alter column whatsapp_phone set not null;

-- Student profile photo and WhatsApp contact fields.
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists whatsapp_phone text;
alter table public.profiles add column if not exists landlord_approved boolean not null default false;
update public.profiles set landlord_approved=false where role='landlord' and landlord_approved is null;
grant select, update on public.profiles to authenticated;
grant select, update on public.profiles to authenticated;
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880;
drop policy if exists "Profile photos are publicly viewable" on storage.objects;
create policy "Profile photos are publicly viewable" on storage.objects for select to anon,authenticated using(bucket_id='profile-photos');
drop policy if exists "Users upload own profile photos" on storage.objects;
create policy "Users upload own profile photos" on storage.objects for insert to authenticated with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users update own profile photos" on storage.objects;
create policy "Users update own profile photos" on storage.objects for update to authenticated using(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  requested_role text;
begin
  requested_role := case
    when new.raw_user_meta_data->>'role' in ('student', 'landlord')
      then new.raw_user_meta_data->>'role'
    else 'student'
  end;

  insert into public.profiles (id, full_name, role, landlord_approved)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    requested_role,
    false
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        role = excluded.role;

  return new;
end;
$function$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$function$;
drop policy if exists "Admins update landlord approval" on public.profiles;
create policy "Admins update landlord approval" on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.profiles enable row level security;alter table public.listings enable row level security;
drop policy if exists "Profiles readable by owner or admin" on public.profiles;
create policy "Profiles readable by owner or admin" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists "Approved listings public" on public.listings;
create policy "Approved listings public" on public.listings for select to anon,authenticated using(status='approved' or owner_id=auth.uid() or public.is_admin());
drop policy if exists "Authenticated users create own pending listings" on public.listings;
drop policy if exists "Authenticated landlords create own pending listings" on public.listings;
create policy "Authenticated users create own pending listings" on public.listings for insert to authenticated with check(owner_id=auth.uid() and status='pending');
drop policy if exists "Owners update own pending or rejected listings" on public.listings;
create policy "Owners update own pending or rejected listings" on public.listings for update to authenticated using(owner_id=auth.uid() and status in ('pending','rejected')) with check(owner_id=auth.uid() and status in ('pending','rejected'));
drop policy if exists "Admins update any listing" on public.listings;
create policy "Admins update any listing" on public.listings for update to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "Owners or admins delete listings" on public.listings;
create policy "Owners or admins delete listings" on public.listings for delete to authenticated using(owner_id=auth.uid() or public.is_admin());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('listing-photos','listing-photos',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=true,file_size_limit=5242880;
drop policy if exists "Listing photos are publicly viewable" on storage.objects;
create policy "Listing photos are publicly viewable" on storage.objects for select to anon,authenticated using(bucket_id='listing-photos');
drop policy if exists "Users upload photos to own folder" on storage.objects;
create policy "Users upload photos to own folder" on storage.objects for insert to authenticated with check(bucket_id='listing-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users delete own photos" on storage.objects;
create policy "Users delete own photos" on storage.objects for delete to authenticated using(bucket_id='listing-photos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
-- After creating your own account, promote it from SQL Editor:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='YOUR_ADMIN_EMAIL');


-- Verified landlord badges and student landlord reviews.
-- Run this section in Supabase SQL Editor after the existing schema is installed.

create table if not exists public.landlord_reviews (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  student_name text not null default 'Student',
  rating integer not null check (rating between 1 and 5),
  review_text text not null check (char_length(review_text) between 10 and 1000),
  created_at timestamptz not null default now(),
  constraint one_review_per_student_per_landlord unique (landlord_id, student_id),
  constraint landlord_cannot_review_self check (landlord_id <> student_id)
);

create index if not exists landlord_reviews_landlord_created_idx
  on public.landlord_reviews (landlord_id, created_at desc);

alter table public.landlord_reviews enable row level security;

drop policy if exists "Public can read landlord reviews" on public.landlord_reviews;
create policy "Public can read landlord reviews"
  on public.landlord_reviews for select
  to anon, authenticated
  using (true);

grant select on public.landlord_reviews to anon, authenticated;
revoke insert, update, delete on public.landlord_reviews from anon, authenticated;

-- Only expose IDs of approved landlords; do not make private profile details public.
create or replace function public.get_verified_landlord_ids()
returns table (landlord_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  where p.role = 'landlord'
    and p.landlord_approved = true;
$$;

grant execute on function public.get_verified_landlord_ids() to anon, authenticated;

-- Students submit reviews through this function. The database checks their role,
-- verifies the landlord, prevents self-reviews, and allows one review per landlord.
create or replace function public.submit_landlord_review(
  p_landlord_id uuid,
  p_rating integer,
  p_review_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  student_display_name text;
begin
  if auth.uid() is null then
    raise exception 'Please sign in as a student before submitting a review.';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Choose a rating from 1 to 5 stars.';
  end if;

  if p_review_text is null or char_length(trim(p_review_text)) < 10
     or char_length(trim(p_review_text)) > 1000 then
    raise exception 'Your review must be between 10 and 1000 characters.';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'student'
  ) then
    raise exception 'Only student accounts can submit landlord reviews.';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_landlord_id
      and role = 'landlord'
      and landlord_approved = true
  ) then
    raise exception 'You can only review an approved landlord.';
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Student')
    into student_display_name
  from public.profiles
  where id = auth.uid();

  insert into public.landlord_reviews
    (landlord_id, student_id, student_name, rating, review_text)
  values
    (p_landlord_id, auth.uid(), student_display_name, p_rating, trim(p_review_text));
exception
  when unique_violation then
    raise exception 'You have already reviewed this landlord. Only one review per landlord is allowed.';
end;
$$;

grant execute on function public.submit_landlord_review(uuid, integer, text)
  to authenticated;
