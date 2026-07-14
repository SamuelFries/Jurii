type JsonBody = Record<string, unknown>;

type StorageBucket = "verification-documents" | "profile-avatars";

type StorageSummary = Record<
  StorageBucket,
  {
    databasePaths: number;
    folderPaths: number;
    deletedPaths: number;
    errors: string[];
  }
>;

type SupabaseEnv = {
  url: string;
  serviceRoleKey: string;
  anonKey: string;
};

type SupabaseUser = {
  id: string;
  user_metadata?: JsonBody;
};

type StorageListItem = {
  id: string | null;
  name: string;
  metadata: JsonBody | null;
};

type AccountStoragePathRow = {
  bucket_id: unknown;
  storage_path: unknown;
};

type FetchOptions = {
  method?: string;
  key: string;
  bearer: string;
  body?: unknown;
  headers?: Record<string, string>;
  context: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sensitiveBuckets = [
  "verification-documents",
  "profile-avatars",
] as const;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return json({ ok: true }, 200);
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = request.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ error: "Missing bearer token" }, 401);
  }

  let env: SupabaseEnv;
  try {
    env = readEnv();
  } catch (error) {
    console.error("delete-account env error", error);
    return json({ error: "Function is not configured" }, 500);
  }

  const user = await validateUser(env, jwt);
  if (!user) {
    return json({ error: "Invalid bearer token" }, 401);
  }

  let auditId: string | null = null;
  try {
    auditId = await startAudit(env, user.id);

    const storageSummary = await deleteSensitiveStorage(env, user.id);

    await callSoftDelete(env, jwt);
    await banUser(env, user);
    const signOutWarning = await signOutAllSessions(env, jwt);

    await finishAudit(env, auditId, {
      status: "completed",
      storageSummary,
      authBannedAt: new Date().toISOString(),
      errorMessage: signOutWarning,
    });

    return json({
      ok: true,
      storage: storageSummary,
      warning: signOutWarning,
    });
  } catch (error) {
    const message = errorMessage(error);
    console.error("delete-account failed", message);
    await finishAudit(env, auditId, {
      status: "failed",
      storageSummary: {},
      errorMessage: message,
    });
    return json({ error: "Account deletion failed" }, 500);
  }
});

function readEnv(): SupabaseEnv {
  return {
    url: requiredEnv("SUPABASE_URL").replace(/\/+$/, ""),
    serviceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    anonKey:
      Deno.env.get("SUPABASE_ANON_KEY") ??
      requiredEnv("SUPABASE_PUBLISHABLE_KEY"),
  };
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

function json(body: JsonBody, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function validateUser(
  env: SupabaseEnv,
  jwt: string,
): Promise<SupabaseUser | null> {
  try {
    return await supabaseFetch<SupabaseUser>(env, "/auth/v1/user", {
      key: env.anonKey,
      bearer: jwt,
      context: "auth user lookup",
    });
  } catch (error) {
    console.error("delete-account auth error", error);
    return null;
  }
}

async function startAudit(
  env: SupabaseEnv,
  profileId: string,
): Promise<string> {
  const rows = await supabaseFetch<Array<{ id: string }>>(
    env,
    "/rest/v1/account_deletion_audit?select=id",
    {
      method: "POST",
      key: env.serviceRoleKey,
      bearer: env.serviceRoleKey,
      body: { profile_id: profileId, status: "started" },
      headers: { Prefer: "return=representation" },
      context: "account deletion audit insert",
    },
  );

  const auditId = rows[0]?.id;
  if (!auditId) {
    throw new Error("account deletion audit insert returned no id");
  }
  return auditId;
}

async function finishAudit(
  env: SupabaseEnv,
  auditId: string | null,
  values: {
    status: "completed" | "failed";
    storageSummary: StorageSummary | Record<string, never>;
    authBannedAt?: string;
    errorMessage?: string | null;
  },
): Promise<void> {
  if (!auditId) return;

  try {
    await supabaseFetch<unknown>(
      env,
      `/rest/v1/account_deletion_audit?id=eq.${encodeURIComponent(auditId)}`,
      {
        method: "PATCH",
        key: env.serviceRoleKey,
        bearer: env.serviceRoleKey,
        body: {
          status: values.status,
          completed_at: new Date().toISOString(),
          storage_summary: values.storageSummary,
          auth_banned_at: values.authBannedAt ?? null,
          error_message: values.errorMessage ?? null,
        },
        context: "account deletion audit update",
      },
    );
  } catch (error) {
    console.error("account deletion audit update failed", error);
  }
}

async function deleteSensitiveStorage(
  env: SupabaseEnv,
  userId: string,
): Promise<StorageSummary> {
  const dbPaths = await collectDatabaseStoragePaths(env, userId);
  const summary = {} as StorageSummary;

  for (const bucket of sensitiveBuckets) {
    const folderPaths = (await listBucketPaths(env, bucket, userId))
      .filter((path) => isOwnedStoragePath(userId, path));
    const paths = new Set<string>([
      ...(dbPaths[bucket] ?? []),
      ...folderPaths,
    ]);

    const errors: string[] = [];
    let deletedPaths = 0;

    for (const chunk of chunks([...paths], 100)) {
      if (chunk.length === 0) continue;
      try {
        deletedPaths += await removeStoragePaths(env, bucket, chunk);
      } catch (error) {
        errors.push(errorMessage(error));
      }
    }

    summary[bucket] = {
      databasePaths: dbPaths[bucket]?.length ?? 0,
      folderPaths: folderPaths.length,
      deletedPaths,
      errors,
    };

    if (errors.length > 0) {
      throw new Error(`storage delete failed for ${bucket}: ${errors[0]}`);
    }
  }

  return summary;
}

async function collectDatabaseStoragePaths(
  env: SupabaseEnv,
  userId: string,
): Promise<Record<StorageBucket, string[]>> {
  const paths: Record<StorageBucket, Set<string>> = {
    "verification-documents": new Set<string>(),
    "profile-avatars": new Set<string>(),
  };

  const rows = await supabaseFetch<AccountStoragePathRow[]>(
    env,
    "/rest/v1/rpc/get_account_deletion_storage_paths",
    {
      method: "POST",
      key: env.serviceRoleKey,
      bearer: env.serviceRoleKey,
      body: { profile_id_value: userId },
      context: "account storage paths lookup",
    },
  );

  for (const row of rows) {
    if (!isStorageBucket(row.bucket_id)) {
      throw new Error("account storage paths returned an unsupported bucket");
    }

    const path = row.bucket_id === "profile-avatars"
      ? decodeStoragePath(row.storage_path)
      : row.storage_path;
    addOwnedPath(paths[row.bucket_id], userId, path);
  }

  return {
    "verification-documents": [...paths["verification-documents"]],
    "profile-avatars": [...paths["profile-avatars"]],
  };
}

function isStorageBucket(value: unknown): value is StorageBucket {
  return value === "verification-documents" || value === "profile-avatars";
}

function decodeStoragePath(value: unknown): unknown {
  if (typeof value !== "string") return value;

  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function addPath(paths: Set<string>, value: unknown): void {
  if (typeof value !== "string") return;
  const cleaned = value.trim();
  if (cleaned.length > 0) {
    paths.add(cleaned);
  }
}

function addOwnedPath(
  paths: Set<string>,
  userId: string,
  value: unknown,
): void {
  if (typeof value !== "string") return;
  const cleaned = value.trim();
  if (!isOwnedStoragePath(userId, cleaned)) return;
  addPath(paths, cleaned);
}

function isOwnedStoragePath(userId: string, path: string): boolean {
  return path.startsWith(`${userId}/`);
}

async function listBucketPaths(
  env: SupabaseEnv,
  bucket: StorageBucket,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];

  async function visit(currentPrefix: string): Promise<void> {
    const items = await supabaseFetch<StorageListItem[]>(
      env,
      `/storage/v1/object/list/${bucket}`,
      {
        method: "POST",
        key: env.serviceRoleKey,
        bearer: env.serviceRoleKey,
        body: { limit: 1000, prefix: currentPrefix },
        context: `storage list ${bucket}/${currentPrefix}`,
      },
    );

    for (const item of items) {
      const path = currentPrefix ? `${currentPrefix}/${item.name}` : item.name;
      if (item.id === null || item.metadata === null) {
        await visit(path);
      } else {
        paths.push(path);
      }
    }
  }

  await visit(prefix);
  return paths;
}

async function removeStoragePaths(
  env: SupabaseEnv,
  bucket: StorageBucket,
  paths: string[],
): Promise<number> {
  const removed = await supabaseFetch<unknown[] | null>(
    env,
    `/storage/v1/object/${bucket}`,
    {
      method: "DELETE",
      key: env.serviceRoleKey,
      bearer: env.serviceRoleKey,
      body: { prefixes: paths },
      context: `storage remove ${bucket}`,
    },
  );

  return Array.isArray(removed) ? removed.length : paths.length;
}

async function callSoftDelete(env: SupabaseEnv, jwt: string): Promise<void> {
  await supabaseFetch<unknown>(env, "/rest/v1/rpc/delete_current_account", {
    method: "POST",
    key: env.anonKey,
    bearer: jwt,
    body: {},
    context: "soft delete rpc",
  });
}

async function banUser(env: SupabaseEnv, user: SupabaseUser): Promise<void> {
  await supabaseFetch<unknown>(
    env,
    `/auth/v1/admin/users/${encodeURIComponent(user.id)}`,
    {
      method: "PUT",
      key: env.serviceRoleKey,
      bearer: env.serviceRoleKey,
      body: {
        ban_duration: "876000h",
        user_metadata: {
          ...(user.user_metadata ?? {}),
          deleted_account: true,
          deleted_account_at: new Date().toISOString(),
        },
      },
      context: "auth ban user",
    },
  );
}

async function signOutAllSessions(
  env: SupabaseEnv,
  jwt: string,
): Promise<string | null> {
  try {
    await supabaseFetch<unknown>(env, "/auth/v1/logout?scope=global", {
      method: "POST",
      key: env.anonKey,
      bearer: jwt,
      context: "auth global sign out",
    });
    return null;
  } catch (error) {
    return `Session sign-out failed: ${errorMessage(error)}`;
  }
}

async function supabaseFetch<T>(
  env: SupabaseEnv,
  path: string,
  options: FetchOptions,
): Promise<T> {
  const response = await fetch(`${env.url}${path}`, {
    method: options.method ?? "GET",
    headers: {
      apikey: options.key,
      Authorization: `Bearer ${options.bearer}`,
      ...(options.body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(options.headers ?? {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  const payload = await readResponseBody(response);
  if (!response.ok) {
    throw new Error(`${options.context}: ${response.status} ${bodyMessage(payload)}`);
  }
  return payload as T;
}

async function readResponseBody(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return null;

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function bodyMessage(body: unknown): string {
  if (typeof body === "string") return body;
  if (!body || typeof body !== "object") return "";

  const record = body as Record<string, unknown>;
  const message = record.message ?? record.error ?? record.msg ?? record.code;
  return typeof message === "string" ? message : JSON.stringify(body);
}

function chunks<T>(items: T[], size: number): T[][] {
  const output: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    output.push(items.slice(index, index + size));
  }
  return output;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
