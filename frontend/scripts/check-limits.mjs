import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../src/lib/limits.ts", import.meta.url), "utf8");
const executable = source
  .replace(": string | null", "")
  .replace("export function dashboardLimit", "function dashboardLimit")
  .concat("\n({ dashboardLimit });");
const { dashboardLimit } = vm.runInNewContext(executable);

const cases = [
  [null, 80],
  ["", 1],
  ["abc", 80],
  ["0", 1],
  ["-10", 1],
  ["12.8", 12],
  ["500", 500],
  ["9999", 500],
  ["Infinity", 80]
];

for (const [input, expected] of cases) {
  const actual = dashboardLimit(input);
  if (actual !== expected) {
    throw new Error(`dashboardLimit(${JSON.stringify(input)}) returned ${actual}, expected ${expected}`);
  }
}

console.log("dashboard_limit=ok");
