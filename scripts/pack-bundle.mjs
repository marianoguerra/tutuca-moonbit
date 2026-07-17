#!/usr/bin/env node
// Pack a guest's jco-transpiled bundle (the runtime files under
// guests/<name>/dist/js) into a SINGLE self-contained `.tutuca.tar.gz`: a
// gzipped ustar tar the universal demo drops onto the page and unpacks
// in-browser (native DecompressionStream + the tiny tar reader in
// demo/universal_wasm/loader.mjs).
//
// Only runtime files are included — the ESM entry (*.component.js) and its
// core modules (*.wasm). Type files (*.d.ts, interfaces/) are dropped.
//
// No dependency: Node's built-in zlib gzips a tar we build by hand (Node has
// no built-in tar writer). Regular files only, stored by basename.
//
// Usage: node scripts/pack-bundle.mjs [srcDir] [outFile]
//   defaults: guests/counter/dist/js  ->  dist/universal/examples/counter.tutuca.tar.gz
import { gzipSync } from "node:zlib";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const srcDir = join(repoRoot, process.argv[2] ?? "guests/counter/dist/js");
const outFile = join(
  repoRoot,
  process.argv[3] ?? "dist/universal/examples/counter.tutuca.tar.gz",
);

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

const names = readdirSync(srcDir).filter(
  (n) => n.endsWith(".component.js") || n.endsWith(".wasm"),
);
if (!names.some((n) => n.endsWith(".component.js"))) {
  console.error(`pack-bundle: no *.component.js in ${srcDir}`);
  process.exit(1);
}
const files = names.map((n) => ({
  name: basename(n),
  data: readFileSync(join(srcDir, n)),
}));

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, gzipSync(buildTar(files), { level: 9 }));
console.log(`packed ${files.length} files -> ${outFile}`);
