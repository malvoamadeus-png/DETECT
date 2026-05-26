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
    connectionTimeoutMillis: 5000,
    query_timeout: 10000,
    statement_timeout: 10000,
    ssl: { rejectUnauthorized: false }
  });
}
