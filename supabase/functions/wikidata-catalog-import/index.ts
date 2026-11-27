const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!req.headers.get("Authorization")?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Server database credentials are not configured" }, 503);

  try {
    const body = await req.json();
    const startOffset = Number.isSafeInteger(body?.start_offset) && body.start_offset >= 0 ? body.start_offset : 0;
    const pages = Math.min(5, Math.max(1, Number.isSafeInteger(body?.pages) ? body.pages : 1));
    const pageSize = 1000;
    let imported = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (let page = 0; page < pages; page++) {
      const offset = startOffset + page * pageSize;
      const query = `
        SELECT ?item ?itemLabel ?tmdbMovie ?tmdbTV ?kp ?imdb ?date WHERE {
          ?item wdt:P2603 ?kp.
          {
            ?item wdt:P4947 ?tmdbMovie.
            BIND("movie" AS ?kind)
          } UNION {
            ?item wdt:P4983 ?tmdbTV.
            BIND("tv" AS ?kind)
          }
          OPTIONAL { ?item wdt:P345 ?imdb. }
          OPTIONAL { ?item wdt:P577 ?date. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
        }
        ORDER BY STR(?item)
        LIMIT ${pageSize}
        OFFSET ${offset}
      `;
      const upstream = await fetch("https://query.wikidata.org/sparql", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "application/sparql-results+json",
          "User-Agent": "KinoKinoCatalogImporter/1.0 (metadata reconciliation)",
        },
        body: new URLSearchParams({ query, format: "json" }),
        signal: AbortSignal.timeout(45000),
      });
      if (!upstream.ok) {
        errors.push(`Wikidata page at offset ${offset} returned HTTP ${upstream.status}`);
        break;
      }
      const payload = await upstream.json();
      const bindings = payload?.results?.bindings ?? [];
      if (!bindings.length) break;

      const records = new Map<string, Record<string, unknown>>();
      const seenKinopoisk = new Set<string>();
      for (const row of bindings) {
        const tmdbMovie = row.tmdbMovie?.value;
        const tmdbTV = row.tmdbTV?.value;
        const mediaType = tmdbTV ? "tv" : "movie";
        const tmdbId = Number(tmdbTV ?? tmdbMovie);
        const kinopoiskId = Number(row.kp?.value);
        const itemLabel = String(row.itemLabel?.value ?? "").trim().slice(0, 300);
        if (!Number.isSafeInteger(tmdbId) || tmdbId <= 0 ||
            !Number.isSafeInteger(kinopoiskId) || kinopoiskId <= 0 || !itemLabel) {
          skipped++;
          continue;
        }
        const uniqueKp = `${mediaType}:${kinopoiskId}`;
        if (seenKinopoisk.has(uniqueKp)) { skipped++; continue; }
        seenKinopoisk.add(uniqueKp);
        const key = `${mediaType}:${tmdbId}`;
        const date = String(row.date?.value ?? "");
        const year = Number(date.slice(0, 4));
        records.set(key, {
          tmdb_id: tmdbId,
          media_type: mediaType,
          kinopoisk_id: kinopoiskId,
          imdb_id: /^tt[0-9]{5,12}$/.test(String(row.imdb?.value ?? "")) ? row.imdb.value : null,
          wikidata_id: String(row.item?.value ?? "").split("/").pop() ?? null,
          title: itemLabel,
          release_year: Number.isInteger(year) && year >= 1888 && year <= 2200 ? year : null,
          match_method: "wikidata",
          confidence: 100,
          status: "matched",
          verified_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });
      }

      const rows = [...records.values()];
      for (let index = 0; index < rows.length; index += 250) {
        const chunk = rows.slice(index, index + 250);
        const stored = await fetch(
          `${supabaseUrl}/rest/v1/kinokino_id_map?on_conflict=tmdb_id,media_type`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "apikey": serviceKey,
              "Authorization": `Bearer ${serviceKey}`,
              "Prefer": "resolution=merge-duplicates,return=minimal",
            },
            body: JSON.stringify(chunk),
          },
        );
        if (!stored.ok) {
          errors.push(`Database rejected page ${offset}, chunk ${index}: HTTP ${stored.status} ${(await stored.text()).slice(0, 300)}`);
          break;
        }
        imported += chunk.length;
      }
      if (errors.length || bindings.length < pageSize) break;
    }

    return json({
      imported,
      skipped,
      start_offset: startOffset,
      pages_requested: pages,
      next_offset: startOffset + pages * pageSize,
      errors,
      source: "Wikidata properties P4947/P4983 + P2603",
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected importer error" }, 502);
  }
});
