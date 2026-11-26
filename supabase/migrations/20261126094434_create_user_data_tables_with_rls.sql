create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_id bigint not null,
  media_type text not null check (media_type in ('movie','tv')),
  media jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(user_id, media_id, media_type)
);
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_id bigint not null,
  media_type text not null check (media_type in ('movie','tv')),
  rating numeric(3,1) not null check (rating >= 0 and rating <= 10),
  updated_at timestamptz not null default now(),
  unique(user_id, media_id, media_type)
);
create table if not exists public.watch_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_id bigint not null,
  media_type text not null check (media_type in ('movie','tv')),
  media jsonb not null default '{}'::jsonb,
  watched_at timestamptz not null default now(),
  progress_seconds integer not null default 0 check (progress_seconds >= 0)
);
alter table public.profiles enable row level security;
alter table public.favorites enable row level security;
alter table public.ratings enable row level security;
alter table public.watch_history enable row level security;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.favorites to authenticated;
grant select, insert, update, delete on public.ratings to authenticated;
grant select, insert, update, delete on public.watch_history to authenticated;
create policy "profiles_select_own" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "profiles_delete_own" on public.profiles for delete to authenticated using ((select auth.uid()) = id);
create policy "favorites_select_own" on public.favorites for select to authenticated using ((select auth.uid()) = user_id);
create policy "favorites_insert_own" on public.favorites for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "favorites_update_own" on public.favorites for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "favorites_delete_own" on public.favorites for delete to authenticated using ((select auth.uid()) = user_id);
create policy "ratings_select_own" on public.ratings for select to authenticated using ((select auth.uid()) = user_id);
create policy "ratings_insert_own" on public.ratings for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "ratings_update_own" on public.ratings for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "ratings_delete_own" on public.ratings for delete to authenticated using ((select auth.uid()) = user_id);
create policy "history_select_own" on public.watch_history for select to authenticated using ((select auth.uid()) = user_id);
create policy "history_insert_own" on public.watch_history for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "history_update_own" on public.watch_history for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "history_delete_own" on public.watch_history for delete to authenticated using ((select auth.uid()) = user_id);
create index if not exists favorites_user_idx on public.favorites(user_id);
create index if not exists ratings_user_idx on public.ratings(user_id);
create index if not exists watch_history_user_watched_idx on public.watch_history(user_id, watched_at desc);
