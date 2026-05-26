import { readFileSync } from "node:fs";

const routeFiles = [
  "../src/app/api/dashboard/route.ts",
  "../src/app/api/health/route.ts"
];

for (const routeFile of routeFiles) {
  const source = readFileSync(new URL(routeFile, import.meta.url), "utf8");
  if (source.includes("error instanceof Error ? error.message")) {
    throw new Error(`${routeFile} exposes internal error.message in public API responses`);
  }
  if (!source.includes("console.error(")) {
    throw new Error(`${routeFile} should log internal errors server-side`);
  }
}

console.log("api_error_responses=ok");
