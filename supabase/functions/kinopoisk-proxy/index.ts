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
  const apiToken = Deno.env.get("KINOPOISK_API_TOKEN");
  if (!apiToken) return json({
    error: "Kinopoisk API token is not configured on the server.",
    code: "KINOPOISK_TOKEN_MISSING",
  }, 503);

  try {
    const body = await req.json();
    const action = String(body?.action ?? "");
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
