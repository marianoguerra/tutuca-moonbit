import assert from "node:assert/strict";
import { gzipSync } from "node:zlib";
import test from "node:test";

import {
  gunzip,
  readCompressedResponse,
  requireDescriptor,
  untar,
} from "../host/wasm/loader.mjs";

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
    ["bundle/tutuca.json", '{"manifestVersion":1}'],
    ["bundle/main.wasm", new Uint8Array([0, 97, 115, 109])],
  ]));
  assert.equal(new TextDecoder().decode(requireDescriptor(files)), '{"manifestVersion":1}');
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
