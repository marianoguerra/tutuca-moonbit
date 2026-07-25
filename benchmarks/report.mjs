// Run `moon bench` and print one aligned line per benchmark, optionally against
// a saved baseline.
//
//   node benchmarks/report.mjs [--target native] [--file <bench_test.mbt>]
//                              [--save <path>] [--baseline <path>]
//
// `moon bench` spends three lines per benchmark (header, column titles, the
// numbers) which is unreadable across 30 of them; this collapses each to
//
//   render todo 1000                    23.51 ms  ± 0.7%
//
// and with --baseline adds the delta, which is the only number that matters when
// judging a change:
//
//   render todo 1000                    21.02 ms  ± 0.8%   -10.6%  (was 23.51 ms)
//
// Saved baselines are JSON, so `--save before.json` then `--baseline
// before.json` is the whole A/B loop.

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const argv = process.argv.slice(2);
function flag(name, fallback = null) {
  const i = argv.indexOf(`--${name}`);
  return i < 0 ? fallback : argv[i + 1];
}

const target = flag("target");
const file = flag("file");
const save = flag("save");
const baselinePath = flag("baseline");

const args = ["bench", "--release"];
if (target) args.push("--target", target);
if (file) args.push("-p", "marianoguerra/tutuca/benchmarks", "-f", file);
else args.push("benchmarks");

const run = spawnSync("moon", args, { encoding: "utf8" });
const out = (run.stdout ?? "") + (run.stderr ?? "");
if (run.status !== 0) {
  process.stdout.write(out);
  process.exit(run.status ?? 1);
}

// `... ("<name>") ok` on one line; `  12.34 ms ±  1.00 ms  ...` a couple below.
const UNITS = { ns: 1e-6, "µs": 1e-3, us: 1e-3, ms: 1, s: 1000 };
const results = [];
let pending = null;
for (const line of out.split("\n")) {
  const name = line.match(/\("([^"]+)"\)/);
  if (name) {
    pending = name[1].replace(/^bench /, "");
    continue;
  }
  const num = line.match(
    /^\s*([\d.]+)\s*(ns|µs|us|ms|s)\s*±\s*([\d.]+)\s*(ns|µs|us|ms|s)/,
  );
  if (num && pending) {
    results.push({
      name: pending,
      ms: parseFloat(num[1]) * UNITS[num[2]],
      sigmaMs: parseFloat(num[3]) * UNITS[num[4]],
    });
    pending = null;
  }
}

if (results.length === 0) {
  process.stdout.write(out);
  console.error("\nreport.mjs: no benchmark results parsed");
  process.exit(1);
}

function time(ms) {
  if (ms < 1) return `${(ms * 1000).toFixed(2)} µs`;
  return `${ms.toFixed(2)} ms`;
}

const baseline = baselinePath
  ? new Map(
      JSON.parse(readFileSync(baselinePath, "utf8")).map(r => [r.name, r.ms]),
    )
  : null;

const width = Math.max(...results.map(r => r.name.length));
console.log(`${target ?? "wasm-gc"} · release · ${results.length} benchmarks`);
for (const r of results) {
  const spread = `± ${((r.sigmaMs / r.ms) * 100).toFixed(1)}%`;
  let delta = "";
  const was = baseline?.get(r.name);
  if (was !== undefined) {
    const pct = ((r.ms - was) / was) * 100;
    const sign = pct > 0 ? "+" : "";
    delta = `   ${sign}${pct.toFixed(1)}%  (was ${time(was)})`;
  }
  console.log(
    `  ${r.name.padEnd(width)}  ${time(r.ms).padStart(9)}  ${spread.padStart(7)}${delta}`,
  );
}

if (save) {
  writeFileSync(save, JSON.stringify(results, null, 2) + "\n");
  console.log(`\nsaved to ${save}`);
}
