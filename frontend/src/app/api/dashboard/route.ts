import { NextResponse } from "next/server";

import { dashboardLimit } from "@/lib/limits";
import { createDatabaseClient, databaseUrl } from "@/lib/server-db";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: Request) {
  if (!databaseUrl()) {
    return new NextResponse("Missing SUPABASE_DB_URL or DATABASE_URL", { status: 503 });
  }

  const url = new URL(request.url);
  const limit = dashboardLimit(url.searchParams.get("limit"));
  const client = createDatabaseClient();

  try {
    await client.connect();
    const result = await client.query("SELECT * FROM detect_dashboard ORDER BY discovered_at DESC LIMIT $1", [limit]);
    return NextResponse.json(result.rows, {
      headers: {
        "Cache-Control": "no-store"
      }
    });
  } catch (error) {
    console.error("dashboard query failed", error);
    return new NextResponse("Dashboard query failed", { status: 500 });
  } finally {
    await client.end().catch(() => undefined);
  }
}
