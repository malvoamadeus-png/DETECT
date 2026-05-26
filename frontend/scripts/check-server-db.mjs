import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/lib/server-db.ts", import.meta.url), "utf8");

const requiredFragments = [
  "connectionTimeoutMillis: 5000",
  "query_timeout: 10000",
  "statement_timeout: 10000",
  "ssl: { rejectUnauthorized: false }"
];

for (const fragment of requiredFragments) {
  if (!source.includes(fragment)) {
    throw new Error(`server-db.ts is missing production DB config: ${fragment}`);
  }
}

console.log("server_db_config=ok");
