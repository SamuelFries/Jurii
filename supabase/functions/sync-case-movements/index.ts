// Sincronizacao do andamento processual (DataJud/CNJ).
//
// Chamada de hora em hora pelo pg_cron (via pg_net, funcao
// dispatch_case_movement_sync): pega um lote pequeno de casos com numero CNJ
// preenchido (RPC fetch_cases_for_movement_sync), consulta os indices
// relevantes da API publica do DataJud e entrega os movimentos ao banco (RPC
// ingest_case_movements, que deduplica, traduz e notifica o cliente).
//
// Auth: verify_jwt=false (server-to-server); o dispatch passa um segredo
// dedicado no Authorization, comparado com CASE_SYNC_HOOK_SECRET do ambiente.
//
// Leitura/escrita de tabela SEMPRE via RPC SECURITY DEFINER com grant
// service_role (pos-hardening o service_role nao tem SELECT direto; ler tabela
// via PostgREST devolveria vazio com HTTP 200 - armadilha ja documentada no
// calendar-feed).
//
// A chave do DataJud e PUBLICA (publicada pelo CNJ na wiki da API para todos
// os usuarios); pode ser sobrescrita pelo secret DATAJUD_API_KEY se o CNJ a
// rotacionar.
//
// Latencia do DataJud e alta e variavel (4-47s por consulta, medido em
// 29/07/2026): lote pequeno, consultas sequenciais e timeout generoso.

interface SyncCaseRow {
  case_id: string;
  cnj_number: string;
}

interface MovementPayload {
  code: number;
  name: string;
  occurred_at: string;
  orgao: string | null;
  tribunal: string | null;
  grau: string | null;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DATAJUD_PUBLIC_KEY =
  "cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw==";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env ${name}`);
  return value;
}

// Segmentos do numero CNJ (20 digitos): NNNNNNN DD AAAA J TR OOOO.
// J (indice 13) e o ramo da Justica; TR (14-15) o tribunal. Consultamos o
// indice de origem e o do tribunal superior do ramo (o processo mantem o
// mesmo numero ao subir, e o indice superior tem documento proprio para ele).
const STATE_BY_TR: Record<string, string> = {
  "01": "ac", "02": "al", "03": "ap", "04": "am", "05": "ba", "06": "ce",
  "07": "df", "08": "es", "09": "go", "10": "ma", "11": "mt", "12": "ms",
  "13": "mg", "14": "pa", "15": "pb", "16": "pr", "17": "pe", "18": "pi",
  "19": "rj", "20": "rn", "21": "rs", "22": "ro", "23": "rr", "24": "sc",
  "25": "se", "26": "sp", "27": "to",
};

function aliasesFor(cnj: string): string[] {
  const branch = cnj[13];
  const tr = cnj.slice(14, 16);
  const trNumber = parseInt(tr, 10);

  if (branch === "8") {
    const uf = STATE_BY_TR[tr];
    if (!uf) return [];
    const court = uf === "df" ? "tjdft" : `tj${uf}`;
    return [`api_publica_${court}`, "api_publica_stj"];
  }
  if (branch === "5") {
    if (trNumber >= 1 && trNumber <= 24) {
      return [`api_publica_trt${trNumber}`, "api_publica_tst"];
    }
    return ["api_publica_tst"];
  }
  if (branch === "4") {
    if (trNumber >= 1 && trNumber <= 6) {
      return [`api_publica_trf${trNumber}`, "api_publica_stj"];
    }
    return ["api_publica_stj"];
  }
  if (branch === "3") return ["api_publica_stj"];

  // Demais ramos (STF, eleitoral, militar) ficam fora da v1.
  return [];
}

async function rpc<T>(
  supabaseUrl: string,
  serviceKey: string,
  name: string,
  body: Record<string, unknown>,
): Promise<T | null> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    console.error(`sync-case-movements: rpc ${name} -> ${response.status}`);
    return null;
  }
  return await response.json() as T;
}

// deno-lint-ignore no-explicit-any
async function queryIndex(alias: string, cnj: string, apiKey: string): Promise<any[]> {
  const response = await fetch(
    `https://api-publica.datajud.cnj.jus.br/${alias}/_search`,
    {
      method: "POST",
      headers: {
        Authorization: `APIKey ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        size: 10,
        query: { match: { numeroProcesso: cnj } },
      }),
      signal: AbortSignal.timeout(45_000),
    },
  );
  if (!response.ok) {
    throw new Error(`${alias} -> HTTP ${response.status}`);
  }
  const data = await response.json();
  return data?.hits?.hits ?? [];
}

function movementsFromDocs(
  // deno-lint-ignore no-explicit-any
  docs: any[],
  cnj: string,
): MovementPayload[] {
  const byKey = new Map<string, MovementPayload>();
  for (const doc of docs) {
    const source = doc?._source;
    // O match pode trazer vizinhos: fica so o documento do processo exato.
    if (!source || source.numeroProcesso !== cnj) continue;
    for (const movement of source.movimentos ?? []) {
      const code = Number(movement?.codigo);
      const occurredAt = movement?.dataHora;
      if (!Number.isInteger(code) || typeof occurredAt !== "string") continue;
      // dataHora podre no dado cru viraria exception de cast no RPC e
      // abortaria o lote inteiro; descarta o item como se faz com o code.
      if (Number.isNaN(Date.parse(occurredAt))) continue;
      const key = `${code}|${occurredAt}`;
      if (byKey.has(key)) continue;
      byKey.set(key, {
        code,
        name: String(movement?.nome ?? "").slice(0, 300),
        occurred_at: occurredAt,
        orgao: movement?.orgaoJulgador?.nome ?? null,
        tribunal: source.tribunal ?? null,
        grau: source.grau ?? null,
      });
    }
  }
  return [...byKey.values()];
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const auth = request.headers.get("Authorization") ?? "";
  const hookSecret = Deno.env.get("CASE_SYNC_HOOK_SECRET") ?? "";
  if (hookSecret === "" || auth !== `Bearer ${hookSecret}`) {
    return new Response("Unauthorized", { status: 401, headers: corsHeaders });
  }

  try {
    const supabaseUrl = env("SUPABASE_URL");
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = Deno.env.get("DATAJUD_API_KEY") ?? DATAJUD_PUBLIC_KEY;

    const batch = await rpc<SyncCaseRow[]>(
      supabaseUrl,
      serviceKey,
      "fetch_cases_for_movement_sync",
      { batch_size: 4 },
    ) ?? [];

    const results: Record<string, unknown>[] = [];
    // Orcamento de wall-clock: com a latencia do DataJud (4-47s por consulta)
    // o pior caso do lote estouraria o limite da plataforma. Caso que nao
    // couber fica na fila e sai na proxima passada, sem custo funcional.
    const startedAt = Date.now();
    const TIME_BUDGET_MS = 100_000;

    for (const row of batch) {
      if (Date.now() - startedAt > TIME_BUDGET_MS) {
        results.push({ case_id: row.case_id, skipped: "time_budget" });
        continue;
      }

      const cnj = row.cnj_number;
      const aliases = aliasesFor(cnj);

      // deno-lint-ignore no-explicit-any
      const docs: any[] = [];
      // O indice de ORIGEM (aliases[0]) e quem tem os dados do caso na
      // imensa maioria dos processos; sem ele, marcar como sincronizado
      // seria registrar "nada mudou" sem ter olhado. Ramo sem alias (fora
      // da v1) segue direto para o ingest vazio, so para a fila andar.
      let originOk = aliases.length === 0;
      for (let index = 0; index < aliases.length; index++) {
        try {
          docs.push(...await queryIndex(aliases[index], cnj, apiKey));
          if (index === 0) originOk = true;
        } catch (error) {
          console.error(`sync-case-movements: ${String(error)}`);
        }
      }

      if (!originOk) {
        // Origem inacessivel: nao marca como sincronizado; o caso volta no
        // topo da fila na proxima passada.
        results.push({ case_id: row.case_id, skipped: "origin_unreachable" });
        continue;
      }

      const movements = movementsFromDocs(docs, cnj);
      const outcome = await rpc<Record<string, unknown>>(
        supabaseUrl,
        serviceKey,
        "ingest_case_movements",
        {
          case_id_value: row.case_id,
          cnj_value: cnj,
          movements_value: movements,
        },
      );
      results.push({
        case_id: row.case_id,
        found: movements.length,
        ...(outcome ?? { ingest: "failed" }),
      });
    }

    return new Response(
      JSON.stringify({ processed: batch.length, results }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("sync-case-movements failed:", error);
    return new Response("Internal error", { status: 500, headers: corsHeaders });
  }
});
