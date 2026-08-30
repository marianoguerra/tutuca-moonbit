import assert from "node:assert/strict";
import { gzipSync } from "node:zlib";
import test from "node:test";

import {
  createTcompImports,
  gunzip,
  readCompressedResponse,
  registerArchive,
  requireDescriptor,
  untar,
} from "../host/wasm/loader.mjs";
import { registerDroppedFiles } from "../../app/wasm/loader.mjs";

const encoder = new TextEncoder();

function writeAscii(into, start, width, value) {
  into.set(encoder.encode(value).subarray(0, width), start);
}

function header(name, size, type = "0") {
  const out = new Uint8Array(512);
  writeAscii(out, 0, 100, name);
  writeAscii(out, 100, 8, "0000644\0");
  writeAscii(out, 108, 8, "0000000\0");
  writeAscii(out, 116, 8, "0000000\0");
  writeAscii(out, 124, 12, `${size.toString(8).padStart(11, "0")}\0`);
  writeAscii(out, 136, 12, "00000000000\0");
  out.fill(0x20, 148, 156);
  out[156] = type.charCodeAt(0);
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

test("untar extracts a descriptor archive", () => {
  const files = untar(archive([
    ["bundle/tutuca.json", '{"manifestVersion":2}'],
    ["bundle/main.wasm", new Uint8Array([0, 97, 115, 109])],
  ]));
  assert.equal(new TextDecoder().decode(requireDescriptor(files)), '{"manifestVersion":2}');
  assert.deepEqual([...files["main.wasm"]], [0, 97, 115, 109]);
});

test("legacy JavaScript-only archives are rejected", () => {
  const files = untar(archive([["old.component.js", "export const instantiate = () => {}"]]));
  assert.throws(
    () => requireDescriptor(files),
    /legacy JavaScript bundles are not supported/,
  );
});

test("the signed-size wraparound that used to stall the parser is rejected", () => {
  const bad = new Uint8Array(512);
  bad.set(header("huge", 4_294_966_784));
  assert.throws(() => untar(bad), /truncated or non-advancing tar entry/);
});

test("untar rejects truncated entries and colliding basenames", () => {
  const truncated = header("short", 1);
  assert.throws(() => untar(truncated), /truncated or non-advancing tar entry/);
  assert.throws(
    () => untar(archive([["a/same", "a"], ["b/same", "b"]])),
    /duplicate or ambiguous tar basename/,
  );
});

test("gunzip enforces compressed and expanded byte limits", async () => {
  const compressed = gzipSync(new Uint8Array(4096));
  await assert.rejects(
    gunzip(compressed, { compressedBytes: 1, expandedBytes: 8192 }),
    /compressed bytes/,
  );
  await assert.rejects(
    gunzip(compressed, { compressedBytes: 8192, expandedBytes: 1024 }),
    /expands past 1024 bytes/,
  );
});

test("fetched archives are bounded while the response is read", async () => {
  const body = new Uint8Array(2048);
  await assert.rejects(
    readCompressedResponse(new Response(body), { compressedBytes: 1024 }),
    /exceeds 1024 compressed bytes/,
  );
  await assert.rejects(
    readCompressedResponse(new Response(body, {
      headers: { "content-length": "2048" },
    }), { compressedBytes: 1024 }),
    /too large: 2048 compressed bytes/,
  );
});

// Unpack one in-memory archive through the dropped-file path and answer with
// what the host was told. The stub core module is four bytes of magic and no
// world, so `instantiate` always refuses it — which is the point: the refusal
// comes from `finishLoad`, and `hydrateManifest` has already run by then. An
// archive that reaches the world check is an archive whose manifest hydrated.
async function loadOutcome(manifest, extraFiles = []) {
  const descriptor = { core: "main.wasm", world: "card", manifest };
  const gz = gzipSync(archive([
    ["bundle/tutuca.json", JSON.stringify(descriptor)],
    ["bundle/main.wasm", new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])],
    ...extraFiles,
  ]));
  const told = [];
  const imports = createTcompImports(() => ({
    dyncomp_on_loaded: (_loadId, _id, json) => told.push(json),
    dyncomp_on_load_error: (_loadId, message) => told.push(message),
    refresh_margaui: () => {},
  }));
  const dropped = JSON.parse(registerDroppedFiles({
    dataTransfer: { files: [new File([gz], "bundle.tutuca.tar.gz")] },
  }));
  // The loader reports a failed load by console.error as well as by calling
  // the host back; the callback is what is under test, so keep the stack out
  // of the suite's output rather than let a deliberate failure look like one.
  const noise = console.error;
  console.error = () => {};
  try {
    imports.load_dropped(dropped[0].id, 1);
    for (let i = 0; i < 200 && told.length === 0; i++) {
      await new Promise((resume) => setTimeout(resume, 10));
    }
  } finally {
    console.error = noise;
  }
  return told[0] ?? "the load never reported back";
}

// A card compiled straight to a bundle has no view files beside its manifest:
// `tutucard/wasm/manifest.mbt` projects each `<template>` into `html`, and
// `packBundle` tars that manifest as it stands. Hydration used to read
// `view.src` off every view unconditionally, so every such card — which is to
// say every card with a view at all — died before it could be instantiated.
test("a manifest whose views are already html hydrates untouched", async () => {
  const outcome = await loadOutcome({
    manifestVersion: 2,
    components: [{ name: "card", views: [{ name: "main", html: "<div>hi</div>" }] }],
  });
  assert.doesNotMatch(outcome, /static manifest view is missing/);
  assert.match(outcome, /unsupported world/);
});

// ...and the archive shape still gets the check it always had: a view that
// names a file is a view whose file has to be there.
test("a manifest view naming an absent file is still refused", async () => {
  const outcome = await loadOutcome({
    manifestVersion: 2,
    components: [{ name: "card", views: [{ name: "main", src: "views/gone.html" }] }],
  });
  assert.match(outcome, /static manifest view is missing from archive: views\/gone.html/);
});

// Both shapes in one component, which is what a bundle that grew an inline
// view alongside its files looks like: each view takes its own path.
test("html and src views hydrate side by side", async () => {
  const outcome = await loadOutcome(
    {
      manifestVersion: 2,
      components: [{
        name: "card",
        views: [
          { name: "main", html: "<div>inline</div>" },
          { name: "row", src: "views/row.html" },
        ],
      }],
    },
    [["bundle/row.html", "<div>from file</div>"]],
  );
  assert.doesNotMatch(outcome, /static manifest view is missing/);
  assert.match(outcome, /unsupported world/);
});

// --- bundles the page already holds ---

// The same unpack as `loadOutcome`, reached the third way: bytes this process
// built rather than a file somebody dropped or a URL to fetch. A page that
// GENERATES bundles has them in hand, and staging them behind an object URL to
// fetch back is a round trip whose only other outcome is a revoke race.
async function loadBytesOutcome(bytes, { registered = true } = {}) {
  const told = [];
  const imports = createTcompImports(() => ({
    dyncomp_on_loaded: (_loadId, _id, json) => told.push(json),
    dyncomp_on_load_error: (_loadId, message) => told.push(message),
    refresh_margaui: () => {},
  }));
  const id = registered ? registerArchive(bytes) : 987654;
  const noise = console.error;
  console.error = () => {};
  try {
    imports.load_bytes(id, 1);
    for (let i = 0; i < 200 && told.length === 0; i++) {
      await new Promise((resume) => setTimeout(resume, 10));
    }
  } finally {
    console.error = noise;
  }
  return { outcome: told[0] ?? "the load never reported back", id, imports, told };
}

function heldArchive(manifest) {
  return gzipSync(archive([
    ["bundle/tutuca.json", JSON.stringify({ core: "main.wasm", world: "card", manifest })],
    ["bundle/main.wasm", new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])],
  ]));
}

const HELD = {
  manifestVersion: 2,
  components: [{ name: "card", views: [{ name: "main", html: "<div>held</div>" }] }],
};

test("held bytes unpack the same as a dropped file", async () => {
  const { outcome } = await loadBytesOutcome(heldArchive(HELD));
  // Reaching the world check is reaching `finishLoad`, which means the archive
  // untarred and its manifest hydrated — the whole path, minus a real guest.
  assert.match(outcome, /unsupported world/);
  assert.doesNotMatch(outcome, /no held archive/);
});

// An id names ONE load. Holding the bytes after it would be a page-lifetime
// leak of every bundle it ever built, and there is no second load to serve:
// a host that wants the same archive twice registers it twice.
test("a held archive id is consumed by its load", async () => {
  const { id, imports, told } = await loadBytesOutcome(heldArchive(HELD));
  told.length = 0;
  const noise = console.error;
  console.error = () => {};
  try {
    imports.load_bytes(id, 2);
    for (let i = 0; i < 50 && told.length === 0; i++) {
      await new Promise((resume) => setTimeout(resume, 10));
    }
  } finally {
    console.error = noise;
  }
  assert.match(told[0] ?? "", new RegExp(`no held archive #${id}`));
});

// The failure answers rather than going quiet: every way into the loader has
// to complete its load, or a host that waits for one waits forever.
test("an unregistered id fails the load instead of hanging", async () => {
  const { outcome } = await loadBytesOutcome(heldArchive(HELD), { registered: false });
  assert.match(outcome, /no held archive #987654/);
});

// `gunzip` already bounds the compressed size, so the bytes path needs no
// check of its own — but it does have to REPORT rather than throw past the
// host, which is the part a caller depends on.
test("held bytes over the compressed limit are refused, not thrown", async () => {
  const { outcome } = await loadBytesOutcome(new Uint8Array(17 * 1024 * 1024));
  assert.match(outcome, /too large/);
});
