#!/usr/bin/env node
// Pack this guest's core wasm plus static declaration into a SINGLE
// self-contained `.tutuca.tar.gz` — a gzipped ustar tar a universal host
// unpacks in the browser with the native DecompressionStream and a tiny tar
// reader. That is the whole distribution format: one file, dropped on a page.
//
// It contains no executable JavaScript: `tutuca.json`, one core wasm, and the
// HTML views are enough because the host owns the canonical ABI.
//
// No dependency: Node's zlib gzips a tar built by hand here, because Node has
// no tar writer. Regular files only, stored by basename.
//
//   node pack.mjs                     # dist/js -> <name>.tutuca.tar.gz
//   node pack.mjs <srcDir> <outFile>
import { gzipSync } from "node:zlib";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const name = JSON.parse(readFileSync(join(here, "package.json"), "utf8")).name;
const srcDir = resolve(here, process.argv[2] ?? "dist/js");
const outFile = resolve(here, process.argv[3] ?? `${name}.tutuca.tar.gz`);

// A 512-byte ustar header for a regular file. Octal numeric fields, checksum
// computed with the checksum field spaced out (POSIX rule). mtime pinned to 0
// so the archive is byte-for-byte reproducible.
function tarHeader(name, size) {
  const h = Buffer.alloc(512);
  h.write(name, 0, 100, "utf8");
  const octal = (n, len) => n.toString(8).padStart(len - 1, "0") + "\0";
  h.write(octal(0o644, 8), 100); // mode
  h.write(octal(0, 8), 108); // uid
  h.write(octal(0, 8), 116); // gid
  h.write(size.toString(8).padStart(11, "0") + "\0", 124); // size
  h.write(octal(0, 12), 136); // mtime
  h.write("        ", 148); // checksum placeholder = 8 spaces
  h.write("0", 156); // typeflag: regular file
  h.write("ustar\0", 257);
  h.write("00", 263); // version
  let sum = 0;
  for (const b of h) sum += b;
  h.write(sum.toString(8).padStart(6, "0") + "\0 ", 148); // real checksum
  return h;
}

function buildTar(files) {
  const chunks = [];
  for (const { name, data } of files) {
    chunks.push(tarHeader(name, data.length));
    chunks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad) chunks.push(Buffer.alloc(pad));
  }
  chunks.push(Buffer.alloc(1024)); // two zero blocks = end of archive
  return Buffer.concat(chunks);
}

const names = readdirSync(srcDir);
const core = names.find((n) => n.endsWith(".component.core.wasm"));
if (!core) {
  console.error(`pack: no *.component.core.wasm in ${srcDir} — run \`node build.mjs\` first`);
  process.exit(1);
}
const manifestPath = join(here, "manifest.json");
if (!existsSync(manifestPath)) {
  console.error("pack: manifest.json is missing");
  process.exit(1);
}
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const descriptor = {
  world: "tutuca:component@0.11.0",
  encoding: manifest.stringEncoding ?? "utf16",
  core,
  manifest,
};
const files = [
  { name: "tutuca.json", data: Buffer.from(JSON.stringify(descriptor)) },
  { name: core, data: readFileSync(join(srcDir, core)) },
];
for (const component of manifest.components ?? []) {
  for (const view of component.views ?? []) {
    const name = basename(view.src ?? "");
    const path = join(here, "views", name);
    if (!name || !existsSync(path)) {
      console.error(`pack: missing view ${view.src ?? "<unnamed>"}`);
      process.exit(1);
    }
    if (!files.some((f) => f.name === name)) {
      files.push({ name, data: readFileSync(path) });
    }
  }
}

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, gzipSync(buildTar(files), { level: 9 }));
console.log(`packed ${files.length} files -> ${outFile}`);
console.log("Drop it on a universal host page to load it.");
