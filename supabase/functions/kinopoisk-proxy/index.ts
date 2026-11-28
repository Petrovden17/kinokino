const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
const apiBase = "https://kinopoiskapiunofficial.tech/api";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!req.headers.get("Authorization")?.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json();
    const action = String(body?.action ?? "");

    // Cache writes use the server-side service key; it is never exposed to the app.
    if (action === "cache") {
      const tmdbId = Number(body?.tmdb_id);
      const mediaType = String(body?.media_type ?? "");
      const kinopoiskId = Number(body?.kinopoisk_id);
      const title = String(body?.title ?? "").trim().slice(0, 300);
      const matchMethod = String(body?.match_method ?? "");
      const confidence = Number(body?.confidence ?? 0);
      if (!Number.isSafeInteger(tmdbId) || tmdbId <= 0 ||
          !Number.isSafeInteger(kinopoiskId) || kinopoiskId <= 0 ||
          !["movie", "tv"].includes(mediaType) || title.length < 1 ||
          !["imdb", "wikidata", "title_year", "title"].includes(matchMethod) ||
          !Number.isFinite(confidence) || confidence < 0 || confidence > 100) {
        return json({ error: "Invalid mapping payload" }, 400);
      }
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!supabaseUrl || !serviceKey) {
        return json({ error: "Server database credentials are not configured" }, 503);
      }
      const record = {
        tmdb_id: tmdbId,
        media_type: mediaType,
        kinopoisk_id: kinopoiskId,
        title,
        release_year: Number.isInteger(Number(body?.release_year)) && Number(body?.release_year) > 0
          ? Number(body.release_year) : null,
        imdb_id: /^tt[0-9]{5,12}$/.test(String(body?.imdb_id ?? "")) ? String(body.imdb_id) : null,
        wikidata_id: /^Q[0-9]+$/.test(String(body?.wikidata_id ?? "")) ? String(body.wikidata_id) : null,
        match_method: matchMethod,
        confidence,
        status: confidence >= 85 ? "matched" : "needs_review",
        verified_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
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
          body: JSON.stringify(record),
        },
      );
      if (!stored.ok) {
        const detail = await stored.text();
        console.error("[kinokino-id-cache] database write failed", stored.status, detail);
        return json({ error: "Could not store mapping" }, 502);
      }
      return json({ cached: true });
    }

    const apiToken = Deno.env.get("KINOPOISK_API_TOKEN");
    if (!apiToken) return json({
      error: "Kinopoisk API token is not configured on the server.",
      code: "KINOPOISK_TOKEN_MISSING",
    }, 503);

    const filmId = Number(body?.film_id);
    let path: string;
    if (action === "search") {
      const query = String(body?.query ?? "").trim();
      if (query.length < 2 || query.length > 120) return json({ error: "Invalid search query" }, 400);
      path = "/v2.1/films/search-by-keyword?keyword=" + encodeURIComponent(query) + "&page=1";
    } else if (action === "imdb") {
      const imdbId = String(body?.imdb_id ?? "").trim();
      if (!/^tt[0-9]{5,12}$/.test(imdbId)) return json({ error: "Invalid IMDb id" }, 400);
      path = "/v2.2/films?imdbId=" + encodeURIComponent(imdbId);
    } else {
      if (!Number.isSafeInteger(filmId) || filmId <= 0) return json({ error: "Invalid film id" }, 400);
      switch (action) {
        case "film": path = `/v2.2/films/${filmId}`; break;
        case "seasons": path = `/v2.2/films/${filmId}/seasons`; break;
        case "videos": path = `/v2.2/films/${filmId}/videos`; break;
        case "similars": path = `/v2.2/films/${filmId}/similars`; break;
        default: return json({ error: "Unsupported action" }, 400);
      }
    }
    const upstream = await fetch(apiBase + path, {
      headers: { "Accept": "application/json", "X-API-KEY": apiToken },
      signal: AbortSignal.timeout(12000),
    });
    const text = await upstream.text();
    let payload: unknown;
    try { payload = text ? JSON.parse(text) : {}; }
    catch { return json({ error: "Kinopoisk API returned invalid JSON" }, 502); }
    if (!upstream.ok) return json({
      error: "Kinopoisk API request failed",
      upstream_status: upstream.status,
    }, upstream.status === 429 ? 429 : 502);
    return json(payload);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 502);
  }
});
