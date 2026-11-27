create table if not exists public.kinokino_id_map (
  tmdb_id bigint not null,
  media_type text not null check (media_type in ('movie', 'tv')),
  kinopoisk_id bigint not null check (kinopoisk_id > 0),
  imdb_id text,
  wikidata_id text,
  title text not null,
  release_year integer,
  match_method text not null check (match_method in ('imdb', 'wikidata', 'title_year', 'title')),
  confidence numeric(5,2) not null default 0 check (confidence >= 0 and confidence <= 100),
  status text not null default 'matched' check (status in ('matched', 'needs_review')),
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tmdb_id, media_type),
  unique (kinopoisk_id, media_type)
);
create index if not exists kinokino_id_map_imdb_idx
  on public.kinokino_id_map (imdb_id) where imdb_id is not null;
create index if not exists kinokino_id_map_kinopoisk_idx
  on public.kinokino_id_map (kinopoisk_id);
alter table public.kinokino_id_map enable row level security;
grant select on public.kinokino_id_map to anon, authenticated;
drop policy if exists "kinokino_id_map_public_read" on public.kinokino_id_map;
create policy "kinokino_id_map_public_read"
  on public.kinokino_id_map for select to anon, authenticated using (true);
