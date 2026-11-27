const WORKER_ORIGIN = "https://kinokino-tmdb.get46-get47.workers.dev";
const FUNCTION_PREFIX = "/functions/v1/tmdb-catalog-proxy";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);

  const incoming = new URL(request.url);
  const marker = incoming.pathname.indexOf(FUNCTION_PREFIX);
  if (marker < 0) return json({ error: "Invalid function path" }, 404);

  const path = incoming.pathname.slice(marker + FUNCTION_PREFIX.length);
  // Only fixed API namespaces are forwarded. This is not an open proxy.
  if (!(path.startsWith("/3/") || path.startsWith("/watchmode/v1/"))) {
    return json({ error: "Endpoint is not allowed" }, 404);
  }

  try {
    const upstreamUrl = new URL(path + incoming.search, WORKER_ORIGIN);
    const upstream = await fetch(upstreamUrl, {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(25000),
    });
    const headers = new Headers(upstream.headers);
    for (const [key, value] of Object.entries(corsHeaders)) headers.set(key, value);
    headers.set("Cache-Control", upstream.headers.get("Cache-Control") ?? "public, max-age=120");
    return new Response(upstream.body, {
      status: upstream.status,
      headers,
    });
  } catch (error) {
    console.error("[tmdb-catalog-proxy] upstream request failed", error);
    return json({ error: "Catalogue provider is temporarily unavailable" }, 502);
  }
});
