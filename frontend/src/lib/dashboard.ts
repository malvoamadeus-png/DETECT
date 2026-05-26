import { getSupabaseClient } from "@/lib/supabase";
import type { DashboardRow } from "@/types/dashboard";

export async function loadDashboardRows(limit = 80): Promise<DashboardRow[]> {
  const response = await fetch(`/api/dashboard?limit=${limit}`, {
    cache: "no-store"
  });
  if (response.ok) {
    return (await response.json()) as DashboardRow[];
  }

  // Local fallback keeps the UI usable when only public Supabase env is configured.
  if (process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    const supabase = getSupabaseClient();
    const { data, error } = await supabase
      .from("detect_dashboard")
      .select("*")
      .order("discovered_at", { ascending: false })
      .limit(limit);
    if (error) {
      throw new Error(error.message);
    }
    return (data ?? []) as DashboardRow[];
  }

  const message = await response.text();
  throw new Error(message || "Dashboard API is not configured");
}
