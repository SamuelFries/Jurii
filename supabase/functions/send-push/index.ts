// Envio de push (FCM HTTP v1).
//
// Chamada pelo trigger em `notifications` (via pg_net) sempre que uma
// notificacao e criada — entao TODO tipo (lembrete, recomendacao, mensagem)
// ganha push sem codigo extra. Recebe os dados da notificacao, busca os device
// tokens do destinatario e envia para cada um.
//
// Auth: verify_jwt=false (chamada server-to-server); o trigger passa a
// service_role key no Authorization, comparada aqui com o secret do ambiente.
//
// Depende de FCM_SERVICE_ACCOUNT (JSON da service account do Firebase) — ate o
// Samuel configurar o Firebase, esta funcao existe mas responde 503.

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
  project_id: string;
}

interface PushTokenRow {
  token: string;
  platform: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env ${name}`);
  return value;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// Gera um OAuth2 access token para o escopo do FCM, assinando um JWT com a
// private key da service account (RS256). Sem libs externas — Web Crypto.
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: sa.token_uri,
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    throw new Error(`OAuth token failed: ${response.status} ${await response.text()}`);
  }
  const data = await response.json();
  return data.access_token as string;
}

async function fetchTokens(
  supabaseUrl: string,
  serviceKey: string,
  recipientId: string,
): Promise<PushTokenRow[]> {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/fetch_push_tokens_for_recipient`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ recipient_id: recipientId }),
    },
  );
  if (!response.ok) return [];
  return await response.json() as PushTokenRow[];
}

async function sendOne(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; status: number }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
        },
      }),
    },
  );
  return { ok: response.ok, status: response.status };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  // So o trigger (com a service_role key) chama esta funcao.
  const auth = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""}`;
  if (auth !== expected || expected === "Bearer ") {
    return new Response("Unauthorized", { status: 401, headers: corsHeaders });
  }

  let payload: {
    recipient_profile_id?: string;
    title?: string;
    body?: string;
    type?: string;
    notification_id?: string;
  };
  try {
    payload = await request.json();
  } catch {
    return new Response("Bad request", { status: 400, headers: corsHeaders });
  }

  const recipientId = payload.recipient_profile_id;
  if (!recipientId) {
    return new Response("Missing recipient", { status: 400, headers: corsHeaders });
  }

  const rawServiceAccount = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!rawServiceAccount) {
    // Esperado ate o Firebase ser configurado.
    console.error("send-push: FCM_SERVICE_ACCOUNT not set");
    return new Response("Push not configured", { status: 503, headers: corsHeaders });
  }

  try {
    const supabaseUrl = env("SUPABASE_URL");
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
    const sa = JSON.parse(rawServiceAccount) as ServiceAccount;

    const tokens = await fetchTokens(supabaseUrl, serviceKey, recipientId);
    if (tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no tokens" }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);
    const data: Record<string, string> = {
      type: payload.type ?? "",
      notification_id: payload.notification_id ?? "",
    };

    let sent = 0;
    let failed = 0;
    for (const row of tokens) {
      const result = await sendOne(
        accessToken,
        sa.project_id,
        row.token,
        payload.title ?? "Jurii",
        payload.body ?? "",
        data,
      );
      if (result.ok) sent++;
      else failed++;
    }

    return new Response(JSON.stringify({ sent, failed }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("send-push failed:", error);
    return new Response("Internal error", { status: 500, headers: corsHeaders });
  }
});
