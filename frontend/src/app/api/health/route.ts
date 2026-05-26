import { NextResponse } from "next/server";

import { createDatabaseClient, databaseUrl } from "@/lib/server-db";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET() {
  if (!databaseUrl()) {
    return NextResponse.json({ ok: false, error: "Missing SUPABASE_DB_URL or DATABASE_URL" }, { status: 503 });
  }

  const client = createDatabaseClient();
  try {
    await client.connect();
    const result = await client.query("SELECT count(*)::int AS rows FROM detect_dashboard");
    return NextResponse.json(
      {
        ok: true,
        dashboard_rows: result.rows[0]?.rows ?? 0
      },
      {
        headers: {
          "Cache-Control": "no-store"
        }
      }
    );
  } catch (error) {
    console.error("health check failed", error);
    return NextResponse.json({ ok: false, error: "Health check failed" }, { status: 500 });
  } finally {
    await client.end().catch(() => undefined);
  }
}
