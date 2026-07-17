// Feed iCalendar (.ics) da agenda do advogado.
//
// Servido sem JWT (verify_jwt = false): calendarios nao mandam Authorization.
// A autenticacao e o token secreto na URL (?token=...), resolvido para o
// advogado por uma RPC service_role. Quem tem o link ve a agenda daquele
// advogado — e uma "capability URL", por isso o token e aleatorio e revogavel.
//
// Unidirecional: Jurii -> calendario. O advogado assina uma vez no
// Google/Apple/Outlook e todo compromisso aparece la, atualizando no refresh.

type AppointmentRow = {
  id: string;
  title: string;
  counterpart_name: string | null;
  area: string | null;
  location: string | null;
  starts_at: string;
  ends_at: string | null;
  status: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env ${name}`);
  return value;
}

// RFC 5545: escapa \ ; , e quebras de linha em valores de texto.
function escapeText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

// Dobra linhas com mais de 75 octetos (CRLF + espaco), como manda o RFC — sem
// isso, titulos longos podem ser truncados por alguns clientes.
function foldLine(line: string): string {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;

  const parts: string[] = [];
  let current = "";
  let currentBytes = 0;
  for (const char of line) {
    const charBytes = new TextEncoder().encode(char).length;
    // 74 para deixar espaco ao octeto do prefixo (espaco) nas continuacoes.
    if (currentBytes + charBytes > 74) {
      parts.push(current);
      current = "";
      currentBytes = 0;
    }
    current += char;
    currentBytes += charBytes;
  }
  if (current) parts.push(current);
  return parts.join("\r\n ");
}

function formatUtc(iso: string): string {
  // 2026-07-20T14:00:00Z -> 20260720T140000Z
  const d = new Date(iso);
  const p = (n: number) => n.toString().padStart(2, "0");
  return (
    `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `T${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`
  );
}

function buildEvent(row: AppointmentRow, stamp: string): string[] {
  const start = formatUtc(row.starts_at);
  // Sem fim, assume 1h — um VEVENT precisa de DTEND (ou duracao).
  const endIso = row.ends_at ??
    new Date(new Date(row.starts_at).getTime() + 3600000).toISOString();
  const end = formatUtc(endIso);

  const descriptionParts: string[] = [];
  if (row.counterpart_name && row.counterpart_name.trim()) {
    descriptionParts.push(`Com: ${row.counterpart_name.trim()}`);
  }
  if (row.area && row.area.trim()) {
    descriptionParts.push(row.area.trim());
  }
  descriptionParts.push("Agendado pela Jurii");

  const status = row.status === "cancelled" ? "CANCELLED" : "CONFIRMED";

  const lines = [
    "BEGIN:VEVENT",
    `UID:${row.id}@jurii.app`,
    `DTSTAMP:${stamp}`,
    `DTSTART:${start}`,
    `DTEND:${end}`,
    `SUMMARY:${escapeText(row.title)}`,
    `STATUS:${status}`,
    `DESCRIPTION:${escapeText(descriptionParts.join("\n"))}`,
  ];
  if (row.location && row.location.trim()) {
    lines.push(`LOCATION:${escapeText(row.location.trim())}`);
  }
  lines.push("END:VEVENT");
  return lines.map(foldLine);
}

function buildCalendar(rows: AppointmentRow[]): string {
  const stamp = formatUtc(new Date().toISOString());
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Jurii//Agenda//PT-BR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Jurii",
    "X-WR-TIMEZONE:UTC",
  ];
  for (const row of rows) {
    lines.push(...buildEvent(row, stamp));
  }
  lines.push("END:VCALENDAR");
  // RFC 5545 exige CRLF entre as linhas dobradas tambem.
  return lines.join("\r\n") + "\r\n";
}

async function resolveLawyerId(
  supabaseUrl: string,
  serviceKey: string,
  token: string,
): Promise<string | null> {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/lawyer_id_for_calendar_feed`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ token_value: token }),
    },
  );
  if (!response.ok) return null;
  const data = await response.json();
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function fetchAppointments(
  supabaseUrl: string,
  serviceKey: string,
  lawyerId: string,
): Promise<AppointmentRow[]> {
  // Leitura por RPC SECURITY DEFINER (a tabela appointments esta trancada pelo
  // hardening; service_role nao tem SELECT direto). A RPC ja limita a janela.
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/fetch_appointments_for_feed`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ lawyer_id_value: lawyerId }),
    },
  );
  if (!response.ok) return [];
  return await response.json() as AppointmentRow[];
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "GET") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const token = new URL(request.url).searchParams.get("token");
  if (!token) {
    return new Response("Missing token", { status: 400, headers: corsHeaders });
  }

  try {
    const supabaseUrl = env("SUPABASE_URL");
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");

    const lawyerId = await resolveLawyerId(supabaseUrl, serviceKey, token);
    if (!lawyerId) {
      // Token invalido/revogado: 404 generico, sem revelar se ja existiu.
      return new Response("Not found", { status: 404, headers: corsHeaders });
    }

    const rows = await fetchAppointments(supabaseUrl, serviceKey, lawyerId);
    const ics = buildCalendar(rows);

    return new Response(ics, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/calendar; charset=utf-8",
        "Content-Disposition": 'inline; filename="jurii.ics"',
        "Cache-Control": "no-cache",
      },
    });
  } catch (error) {
    console.error("calendar-feed failed:", error);
    return new Response("Internal error", { status: 500, headers: corsHeaders });
  }
});
