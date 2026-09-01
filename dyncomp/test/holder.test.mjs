// A hole holds an INSTANCE, across the bridge and back.
//
// The case: a card declares `child: Component` — a hole naming no component —
// and a host puts an instance in it. Everything about that is host-side
// bookkeeping the card never sees, and all of it happens in `loader.mjs`:
// what a value looks like on the way IN (a handle, not a copy of the fields
// under a name that no longer refers to them), and what a read hands BACK (a
// `$dyn` marker the host resolves to the instance it stands for).
//
// Driven at the bridge rather than through MoonBit because that is where the
// two encodings meet. The card is compiled by `cmd/cardwasm` the way
// `tutucard/wasm/test/gen.test.mjs` does it: slow once, cached after, and
// nothing checked in that nobody can regenerate.
//
//   node --test "dyncomp/test/*.test.mjs"

import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

import { createTcompImports, registerArchive } from "../host/wasm/loader.mjs";

const MODULE = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const encoder = new TextEncoder();

function writeAscii(into, start, width, value) {
  into.set(encoder.encode(value).subarray(0, width), start);
}

function header(name, size) {
  const out = new Uint8Array(512);
  writeAscii(out, 0, 100, name);
  writeAscii(out, 100, 8, "0000644\0");
  writeAscii(out, 108, 8, "0000000\0");
  writeAscii(out, 116, 8, "0000000\0");
  writeAscii(out, 124, 12, `${size.toString(8).padStart(11, "0")}\0`);
  writeAscii(out, 136, 12, "00000000000\0");
  out.fill(0x20, 148, 156);
  out[156] = "0".charCodeAt(0);
  writeAscii(out, 257, 6, "ustar\0");
  writeAscii(out, 263, 2, "00");
  const sum = out.reduce((n, byte) => n + byte, 0);
  writeAscii(out, 148, 8, `${sum.toString(8).padStart(6, "0")}\0 `);
  return out;
}

function archive(entries) {
  const chunks = [];
  let length = 1024;
  for (const [name, source] of entries) {
    const body = typeof source === "string" ? encoder.encode(source) : source;
    const padded = Math.ceil(body.byteLength / 512) * 512;
    chunks.push(header(name, body.byteLength), body, new Uint8Array(padded - body.byteLength));
    length += 512 + padded;
  }
  chunks.push(new Uint8Array(1024));
  const out = new Uint8Array(length);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.byteLength;
  }
  return out;
}

let compiled = null;

/** Compile `tutucard/wasm/examples/Holder.html` once, into an archive. */
function bundleBytes() {
  if (!compiled) {
    const out = mkdtempSync(join(tmpdir(), "holder-"));
    execFileSync(
      "moon",
      ["run", "cmd/cardwasm", "--target", "native", "--", "tutucard/wasm/examples/Holder.html", out],
      { cwd: MODULE, encoding: "utf8" },
    );
    const descriptor = JSON.parse(readFileSync(join(out, "Holder.descriptor.json"), "utf8"));
    const manifest = JSON.parse(readFileSync(join(out, "Holder.manifest.json"), "utf8"));
    const wasm = readFileSync(join(out, "Holder.wasm"));
    // `cmd/cardwasm` writes the descriptor and the manifest side by side; an
    // archive carries the manifest INSIDE the descriptor, which is the shape
    // `hydrateManifest` reads.
    compiled = gzipSync(archive([
      ["bundle/tutuca.json", JSON.stringify({ ...descriptor, manifest, core: "Holder.wasm" })],
      ["bundle/Holder.wasm", wasm],
    ]));
  }
  return compiled;
}

/** One bridge, which may hold several bundles — as a page with two cards does. */
function bridge() {
  const loaded = [];
  let failed = null;
  const imports = createTcompImports(() => ({
    dyncomp_on_loaded: (_loadId, id) => loaded.push(id),
    dyncomp_on_load_error: (_loadId, message) => { failed = message; },
    dyncomp_load_error: () => "",
    set_bundle_config: () => {},
    refresh_margaui: () => {},
  }));
  return {
    imports,
    /** Load the card as another bundle, and answer its id. */
    async load() {
      const before = loaded.length;
      imports.load_bytes(registerArchive(bundleBytes()), before + 1);
      for (let i = 0; i < 400 && loaded.length === before && failed === null; i++) {
        await new Promise((resume) => setTimeout(resume, 10));
      }
      assert.equal(failed, null, "the bundle should load");
      return loaded[before];
    },
  };
}

test("an instance handed to a hole comes back as an instance", async () => {
  const host = bridge();
  const bundle = await host.load();
  const { imports } = host;

  const text = imports.create(bundle, "Text", JSON.stringify({ body: "hi" }));
  // What `child_json` writes on the way in: the HANDLE. `Value::to_json` would
  // write `{"body":"hi"}` here, and the guest would store a map — which is a
  // copy of an instance's state under a name that no longer refers to it, and
  // the bug this test exists for.
  const hole = imports.create(bundle, "Hole", JSON.stringify({
    child: { $dyn: { handle: text } },
    kept: "beside it",
  }));

  // Read back: a marker naming the instance AND its component, which is what
  // the host needs to wrap it as the thing it is. Losing either half draws an
  // empty cell with no error anywhere.
  assert.deepEqual(
    JSON.parse(imports.get_field(bundle, hole, "child")),
    { $dyn: { handle: text, comp: "Text" } },
  );
  // The field beside it is ordinary, so a lost hole cannot be mistaken for an
  // instance that was never stored.
  assert.deepEqual(JSON.parse(imports.get_field(bundle, hole, "kept")), "beside it");
});

