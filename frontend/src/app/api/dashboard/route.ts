import { NextResponse } from "next/server";
import { Client } from "pg";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

function safeLimit(value: string | null) {
  const parsed = Number(value ?? 80);
  if (!Number.isFinite(parsed)) return 80;
  return Math.max(1, Math.min(500, Math.floor(parsed)));
}

function databaseUrl() {
  return process.env.SUPABASE_DB_URL || process.env.DATABASE_URL || "";
}

export async function GET(request: Request) {
  const dsn = databaseUrl();
  if (!dsn) {
    return new NextResponse("Missing SUPABASE_DB_URL or DATABASE_URL", { status: 503 });
  }

  const url = new URL(request.url);
  const limit = safeLimit(url.searchParams.get("limit"));
  const client = new Client({
    connectionString: dsn,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    const result = await client.query("SELECT * FROM detect_dashboard ORDER BY discovered_at DESC LIMIT $1", [limit]);
    return NextResponse.json(result.rows, {
      headers: {
        "Cache-Control": "no-store"
      }
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Dashboard query failed";
    return new NextResponse(message, { status: 500 });
  } finally {
    await client.end().catch(() => undefined);
  }
}
