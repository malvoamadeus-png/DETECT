import { Client } from "pg";

export function databaseUrl() {
  return process.env.SUPABASE_DB_URL || process.env.DATABASE_URL || "";
}

export function createDatabaseClient() {
  const dsn = databaseUrl();
  if (!dsn) {
    throw new Error("Missing SUPABASE_DB_URL or DATABASE_URL");
  }
  return new Client({
    connectionString: dsn,
    ssl: { rejectUnauthorized: false }
  });
}
