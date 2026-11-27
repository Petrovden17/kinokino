create extension if not exists http with schema extensions;

create or replace function public.import_kinokino_wikidata_batch(p_offset integer default 0,p_limit integer default 20)
returns table(source_rows integer,inserted_rows integer,source_status integer)
language plpgsql security invoker set search_path=public,extensions
as $$
declare q text;r extensions.http_response;b jsonb;media text;tmdb bigint;kp bigint;imdb text;wd text;title_text text;n integer:=0;added integer:=0;
begin
 if p_offset<0 or p_limit<1 or p_limit>20 then raise exception 'invalid batch'; end if;
 perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','5000');
 q:='SELECT ?item ?tmdbMovie ?tmdbTV ?kp ?imdb WHERE { ?item wdt:P2603 ?kp. { ?item wdt:P4947 ?tmdbMovie. } UNION { ?item wdt:P4983 ?tmdbTV. } OPTIONAL { ?item wdt:P345 ?imdb. } } LIMIT '||p_limit||' OFFSET '||p_offset;
 select * into r from extensions.http_get('https://query.wikidata.org/sparql?query='||extensions.urlencode(q)||'&format=json');
 if r.status<>200 then raise exception 'Wikidata returned HTTP %',r.status; end if;
 for b in select value from jsonb_array_elements(r.content::jsonb #> '{results,bindings}') loop
  n:=n+1;media:=case when b?'tmdbTV' then 'tv' else 'movie' end;
  tmdb:=nullif(coalesce(b->'tmdbTV'->>'value',b->'tmdbMovie'->>'value'),'')::bigint;
  kp:=nullif(b->'kp'->>'value','')::bigint;
  imdb:=case when b->'imdb'->>'value' ~ '^tt[0-9]{5,12}$' then b->'imdb'->>'value' end;
  wd:=regexp_replace(coalesce(b->'item'->>'value',''),'^.*/','');title_text:='Wikidata '||wd;
  if tmdb is null or tmdb<=0 or kp is null or kp<=0 or wd='' then continue; end if;
  if exists(select 1 from public.kinokino_id_map old where old.media_type=media and old.kinopoisk_id=kp and old.tmdb_id<>tmdb) then continue; end if;
  insert into public.kinokino_id_map(tmdb_id,media_type,kinopoisk_id,imdb_id,wikidata_id,title,match_method,confidence,status,verified_at,updated_at)
  values(tmdb,media,kp,imdb,wd,title_text,'wikidata',100,'matched',now(),now())
  on conflict(tmdb_id,media_type) do update set kinopoisk_id=excluded.kinopoisk_id,imdb_id=coalesce(excluded.imdb_id,public.kinokino_id_map.imdb_id),wikidata_id=excluded.wikidata_id,title=excluded.title,match_method='wikidata',confidence=100,status='matched',verified_at=now(),updated_at=now();
  added:=added+1;
 end loop;
 return query select n,added,r.status;
end $$;
revoke all on function public.import_kinokino_wikidata_batch(integer,integer) from public,anon,authenticated;
grant execute on function public.import_kinokino_wikidata_batch(integer,integer) to service_role;

create or replace function public.import_kinokino_wikidata_tv_batch(p_offset integer default 0,p_limit integer default 20)
returns table(source_rows integer,inserted_rows integer,source_status integer)
language plpgsql security invoker set search_path=public,extensions
as $$
declare q text;r extensions.http_response;b jsonb;tmdb bigint;kp bigint;wd text;imdb text;n integer:=0;added integer:=0;
begin
 if p_offset<0 or p_limit<1 or p_limit>20 then raise exception 'invalid batch'; end if;
 perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','5000');
 q:='SELECT ?item ?tmdbTV ?kp ?imdb WHERE { ?item wdt:P2603 ?kp; wdt:P4983 ?tmdbTV. OPTIONAL { ?item wdt:P345 ?imdb. } } LIMIT '||p_limit||' OFFSET '||p_offset;
 select * into r from extensions.http_get('https://query.wikidata.org/sparql?query='||extensions.urlencode(q)||'&format=json');
 if r.status<>200 then raise exception 'Wikidata returned HTTP %',r.status; end if;
 for b in select value from jsonb_array_elements(r.content::jsonb #> '{results,bindings}') loop
  n:=n+1;tmdb:=nullif(b->'tmdbTV'->>'value','')::bigint;kp:=nullif(b->'kp'->>'value','')::bigint;wd:=regexp_replace(coalesce(b->'item'->>'value',''),'^.*/','');
  imdb:=case when b->'imdb'->>'value' ~ '^tt[0-9]{5,12}$' then b->'imdb'->>'value' end;
  if tmdb is null or tmdb<=0 or kp is null or kp<=0 or wd='' then continue; end if;
  if exists(select 1 from public.kinokino_id_map old where old.media_type='tv' and old.kinopoisk_id=kp and old.tmdb_id<>tmdb) then continue; end if;
  insert into public.kinokino_id_map(tmdb_id,media_type,kinopoisk_id,imdb_id,wikidata_id,title,match_method,confidence,status,verified_at,updated_at)
  values(tmdb,'tv',kp,imdb,wd,'Wikidata '||wd,'wikidata',100,'matched',now(),now())
  on conflict(tmdb_id,media_type) do update set kinopoisk_id=excluded.kinopoisk_id,imdb_id=coalesce(excluded.imdb_id,public.kinokino_id_map.imdb_id),wikidata_id=excluded.wikidata_id,title=excluded.title,match_method='wikidata',confidence=100,status='matched',verified_at=now(),updated_at=now();
  added:=added+1;
 end loop;
 return query select n,added,r.status;
end $$;
revoke all on function public.import_kinokino_wikidata_tv_batch(integer,integer) from public,anon,authenticated;
grant execute on function public.import_kinokino_wikidata_tv_batch(integer,integer) to service_role;

create or replace function public.update_kinokino_wikidata_titles(p_offset integer default 0,p_limit integer default 20)
returns table(source_rows integer,updated_rows integer,source_status integer)
language plpgsql security invoker set search_path=public,extensions
as $$
declare ids text;r extensions.http_response;updated integer:=0;fetched integer:=0;
begin
 if p_offset<0 or p_limit<1 or p_limit>20 then raise exception 'invalid batch'; end if;
 select string_agg(wikidata_id,'|') into ids from (select distinct wikidata_id from public.kinokino_id_map where title like 'Wikidata %' order by wikidata_id offset p_offset limit p_limit) s;
 if ids is null then return query select 0,0,200;return;end if;
 select * into r from extensions.http_get('https://www.wikidata.org/w/api.php?action=wbgetentities&ids='||extensions.urlencode(ids)||'&props=labels&languages=ru|en&format=json');
 if r.status<>200 then raise exception 'Wikidata labels returned HTTP %',r.status;end if;
 with labels as (select key as wikidata_id,coalesce(value #>> '{labels,ru,value}',value #>> '{labels,en,value}') title from jsonb_each(r.content::jsonb->'entities')),
 changed as (update public.kinokino_id_map m set title=l.title,updated_at=now() from labels l where m.wikidata_id=l.wikidata_id and l.title is not null and m.title like 'Wikidata %' returning 1)
 select (select count(*) from jsonb_each(r.content::jsonb->'entities')),(select count(*) from changed) into fetched,updated;
 return query select fetched,updated,r.status;
end $$;
revoke all on function public.update_kinokino_wikidata_titles(integer,integer) from public,anon,authenticated;
grant execute on function public.update_kinokino_wikidata_titles(integer,integer) to service_role;
