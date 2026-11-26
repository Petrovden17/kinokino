/**
 * KinoKino TMDB proxy for Cloudflare Workers.
 * Configure the secret TMDB_API_KEY in Worker Settings > Variables and Secrets.
 */
const TMDB_ORIGIN = "https://api.themoviedb.org";
const WATCHMODE_ORIGIN = "https://api.watchmode.com";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method !== "GET") {
      return json({ error: "Method not allowed" }, 405);
    }

    if (url.pathname.startsWith("/watchmode/v1/")) {
      if (!env.WATCHMODE_API_KEY) return json({ error: "Watchmode service is not configured" }, 503);
      const path = url.pathname.substring("/watchmode".length);
      const allowed = path === "/v1/search/" || path === "/v1/sources/" || path === "/v1/status/" || /^\/v1\/title\/[A-Za-z0-9_-]+\/sources\/?$/.test(path);
      if (!allowed) return json({ error: "Watchmode endpoint is not allowed" }, 404);
      const upstreamUrl = new URL(WATCHMODE_ORIGIN + path);
      for (const [key, value] of url.searchParams) upstreamUrl.searchParams.append(key, value);
      try {
        const upstream = await fetch(upstreamUrl.toString(), {
          method: "GET",
          headers: { Accept: "application/json", "X-API-Key": env.WATCHMODE_API_KEY },
        });
        const headers = new Headers(upstream.headers);
        for (const [key, value] of Object.entries(corsHeaders())) headers.set(key, value);
        headers.set("Cache-Control", "public, max-age=900");
        return new Response(upstream.body, { status: upstream.status, headers });
      } catch {
        return json({ error: "Watchmode is temporarily unavailable" }, 502);
      }
    }

    if (!url.pathname.startsWith("/3/")) {
      return json({ service: "KinoKino TMDB proxy", status: "ok" });
    }

    if (!env.TMDB_API_KEY) {
      return json({ error: "TMDB service is not configured" }, 503);
    }

    // Only proxy TMDB API v3 paths; never accept an arbitrary upstream URL.
    const upstreamUrl = new URL(TMDB_ORIGIN + url.pathname);
    for (const [key, value] of url.searchParams) {
      if (key !== "api_key") upstreamUrl.searchParams.append(key, value);
    }
    upstreamUrl.searchParams.set("api_key", env.TMDB_API_KEY);

    try {
      const upstream = await fetch(upstreamUrl.toString(), {
        method: "GET",
        headers: { Accept: "application/json" },
      });
      const headers = new Headers(upstream.headers);
      for (const [key, value] of Object.entries(corsHeaders())) {
        headers.set(key, value);
      }
      headers.set("Cache-Control", "public, max-age=120");
      return new Response(upstream.body, {
        status: upstream.status,
        headers,
      });
    } catch {
      return json({ error: "TMDB is temporarily unavailable" }, 502);
    }
  },
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(),
    },
  });
}
