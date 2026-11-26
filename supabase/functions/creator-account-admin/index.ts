import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return json({ error: "Server configuration is incomplete" }, 500);
    }

    const token = authorization.slice("Bearer ".length);
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: creator, error: roleError } = await admin
      .from("kinokino_creator_roles")
      .select("user_id")
      .eq("user_id", authData.user.id)
      .eq("role", "creator")
      .maybeSingle();
    if (roleError || !creator) return json({ error: "Creator access required" }, 403);

    const body = await req.json();
    const action = body?.action;

    if (action === "list") {
      const page = Math.max(1, Math.min(1000, Number(body.page) || 1));
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
      if (error) return json({ error: error.message }, 400);

      const { data: roles, error: rolesError } = await admin
        .from("kinokino_creator_roles")
        .select("user_id")
        .in("user_id", data.users.map((user) => user.id));
      if (rolesError) return json({ error: rolesError.message }, 400);
      const creatorIds = new Set((roles ?? []).map((role) => role.user_id));
      const users = data.users.map((user) => ({
        id: user.id,
        email: user.email ?? "",
        display_name: user.user_metadata?.display_name ?? "",
        created_at: user.created_at,
        last_sign_in_at: user.last_sign_in_at,
        banned_until: user.banned_until,
        email_confirmed_at: user.email_confirmed_at,
        is_creator: creatorIds.has(user.id),
      }));
      return json({ users, page });
    }

    if (action === "watch_history") {
      const limit = Math.max(1, Math.min(500, Number(body.limit) || 200));
      const { data: rows, error: historyError } = await admin
        .from("watch_history")
        .select("id,user_id,media_id,media_type,media,watched_at,progress_seconds")
        .order("watched_at", { ascending: false })
        .limit(limit);
      if (historyError) return json({ error: historyError.message }, 400);

      const userIds = [...new Set((rows ?? []).map((row) => row.user_id))];
      const profilesResult = userIds.length
        ? await admin.from("profiles").select("id,display_name").in("id", userIds)
        : { data: [], error: null };
      if (profilesResult.error) return json({ error: profilesResult.error.message }, 400);
      const names = new Map((profilesResult.data ?? []).map((profile) => [profile.id, profile.display_name ?? ""]));
      const usersResult = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (usersResult.error) return json({ error: usersResult.error.message }, 400);
      const emails = new Map(usersResult.data.users.map((user) => [user.id, user.email ?? ""]));
      const history = (rows ?? []).map((row) => ({
        ...row,
        display_name: names.get(row.user_id) ?? "",
        email: emails.get(row.user_id) ?? "",
      }));
      return json({ history });
    }

    const targetId = String(body?.user_id ?? "");
    if (!targetId || targetId.length > 64) return json({ error: "Invalid user id" }, 400);
    if (targetId === authData.user.id) return json({ error: "You cannot change your own account here" }, 400);

    const { data: targetRole, error: targetRoleError } = await admin
      .from("kinokino_creator_roles")
      .select("role")
      .eq("user_id", targetId)
      .maybeSingle();
    if (targetRoleError) return json({ error: targetRoleError.message }, 400);
    if (targetRole?.role === "creator") {
      return json({ error: "Creator accounts are protected from account actions" }, 403);
    }

    if (action === "ban" || action === "unban") {
      const { error } = await admin.auth.admin.updateUserById(targetId, {
        ban_duration: action === "ban" ? "876000h" : "none",
      });
      if (error) return json({ error: error.message }, 400);
      return json({ success: true, action });
    }

    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});
