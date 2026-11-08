const json = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  },
  body: JSON.stringify(body)
});

function jwtRole(key) {
  try {
    const payload = key.split(".")[1];
    return JSON.parse(Buffer.from(payload, "base64url").toString("utf8")).role;
  } catch {
    return null;
  }
}

export const handler = async (event) => {
  if (event.httpMethod !== "GET") {
    return json(405, { error: "Method not allowed." });
  }

  // .trim() supprime automatiquement les espaces en trop copiés par erreur
  const supabaseUrl = (process.env.SUPABASE_URL || "").trim();
  const key = (process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || "").trim();
  
  let validUrl = false;
  try {
    const parsed = new URL(supabaseUrl);
    validUrl = parsed.protocol === "https:";
  } catch {
    validUrl = false;
  }

  const validPublicKey = key.startsWith("sb_publishable_") || jwtRole(key) === "anon";
  if (!validUrl || !validPublicKey || key.startsWith("sb_secret_")) {
    console.error("Supabase public configuration is missing or invalid.");
    return json(503, { error: "Supabase public configuration is unavailable." });
  }

  return json(200, { supabaseUrl, supabasePublishableKey: key });
};