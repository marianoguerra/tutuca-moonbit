# CBOR ABI for Dynamic Components

Status: feasibility validated; proposed migration plan, not yet an accepted ABI.

## Decision summary

Replace the domain-level WIT interface used by dynamic components with a
versioned CBOR request/response protocol carried over a small raw Core Wasm
ABI. Keep JavaScript as the dynamic loader and byte transport between the
wasm-gc host and separately instantiated guest modules.

The proposal is feasible, including for MoonBit wasm-gc guests, but the ABI
must not require wasm-gc guests. A backend-neutral linear-memory byte ABI is
the path that preserves multi-language support:

- MoonBit guests may be compiled to wasm-gc and expose an auxiliary linear
  memory for the CBOR mailbox.
- Rust, C, C++, Zig, Go, and other guests may use ordinary linear-memory Wasm.
- Languages whose best Wasm story remains the component model may use a thin
  WIT adapter exposing the same CBOR exchange operation.
- The host remains wasm-gc. JavaScript remains responsible for loading a guest,
  copying bytes between memories, and invoking its exports.

Do not replace the current WIT ABI in one step. Add `core-cbor@1` beside the
existing `tutuca:component@0.9.0` ABI, prove it with MoonBit and Rust guests,
measure it, and make it the default only after the acceptance gates in this
document pass.

## Goals

- Remove WIT's recursive-value arena and express Tutuca values directly.
- Reduce the normal guest build from generated bindings plus component-model
  adaptation to a small SDK and ordinary Wasm build.
- Preserve the behavior defined in [dyncomp/DESIGN.md](dyncomp/DESIGN.md),
  including component lifecycle, persistence, dispatch, child components,
  tables, and buffered control effects.
- Keep dynamic components practical in more than one implementation language.
- Make the wire format versioned, testable byte-for-byte, and independent of a
  particular language's object or GC representation.
- Preserve or reduce the guest capability surface documented in
  [dyncomp/SECURITY.md](dyncomp/SECURITY.md).
- Improve guest authoring by replacing checked-in generated binding trees and
  copied SDK sources with published language packages.

## Non-goals

- Direct wasm-to-wasm dynamic linking. The browser cannot dynamically link an
  already running MoonBit wasm-gc host to an arbitrary downloaded module; the
  JavaScript loader remains necessary.
- A shared wasm-gc object ABI. GC struct and array layouts are compiler-specific
  and are not a viable cross-language contract.
- Replacing `tutuca.json` or component HTML views with CBOR. Those are
  author-facing bundle metadata and source assets. A build-produced CBOR
  descriptor may be considered later only if measurement justifies it.
- Making untrusted guest execution preemptible. A synchronous runaway guest
  can still freeze the page; worker isolation is a separate availability
  project.
- Removing WIT support immediately. A WIT compatibility adapter remains useful
  for existing bundles and languages with mature component-model tooling.

## Current system

The one WIT contract is
[dyncomp/wit/tutuca-component.wit](dyncomp/wit/tutuca-component.wit). It defines
recursive values through host-owned arena handles, table types, environment and
configuration imports, buffered control imports, and an exported `instance`
resource. The resource implements construction, restore, field access, event
handling, method calls, immutable field updates, persistence, and request
handling.

MoonBit guest bindings are generated with `wit-bindgen`, normalized, and
checked in by [guests/gen-bindings.mjs](guests/gen-bindings.mjs). Guest builds in
[guests/build-guest.mjs](guests/build-guest.mjs) currently pass through
`wasm-tools component embed`, `wasm-tools component new`, and `jco transpile`.
The resulting archive contains metadata, views, and an extracted Core Wasm
module. At runtime, the canonical component-model ABI implementation in
[dyncomp/host/wasm/abi.mjs](dyncomp/host/wasm/abi.mjs) instantiates that module
directly.

The wasm-gc host bridge in
[dyncomp/host/wasm/glue.mbt](dyncomp/host/wasm/glue.mbt) currently crosses the
JavaScript boundary using JSON strings. The loader is
[dyncomp/host/wasm/loader.mjs](dyncomp/host/wasm/loader.mjs). The guest SDK is
maintained once in [guests/sdk.mbt](guests/sdk.mbt), but is copied into every
generated binding tree because the generated declarations and their owning
types cannot currently be shared as a normal package.

This means the proposed change replaces substantial binding and adaptation
machinery, but not the fundamental runtime architecture: JavaScript already
loads a separately compiled guest Core Wasm module.

## Feasibility evidence

The following was validated locally with MoonBit `0.1.20260807`, wasm-tools
`1.244.0`, wit-bindgen `0.59.0`, and jco `1.26.1`:

- A MoonBit wasm-gc module can export and round-trip JavaScript strings through
  the Wasm JavaScript String Builtins integration.
- An external reference can carry a `Uint8Array` opaquely, but MoonBit cannot
  inspect it as `Bytes` without a JavaScript-facing API for every operation.
- Exported MoonBit `Bytes` use a wasm-gc array type. A JavaScript `Uint8Array`
  is not representation-compatible with it.
- A MoonBit wasm-gc package can also define and export an auxiliary linear
  memory. Small inline Wasm load/store functions successfully exchanged bytes
  with JavaScript through that memory.

Therefore a MoonBit wasm-gc guest can implement the same linear-memory CBOR ABI
as a conventional Wasm guest. No compiler-specific GC references need to cross
the guest boundary.

The current baselines also pass:

- `node --test dyncomp/test/abi.test.mjs`
- `moon test dyncomp/host -v` (45 tests)

The feasibility experiment lived outside the repository and made no source
changes.

## Target architecture

```text
Tutuca wasm-gc host
  encode request as CBOR
          |
          | host auxiliary linear-memory mailbox
          v
JavaScript loader and transport
  select ABI from bundle descriptor
  validate module imports/exports
  copy request into guest memory
  invoke tutuca_call
  copy response into host memory
          |
          v
Guest Core Wasm module
  MoonBit wasm-gc + auxiliary memory, or
  ordinary linear-memory Wasm from another language
  decode -> component SDK -> encode
```

CBOR is the domain protocol. Core Wasm imports, exports, memory, and integer
handles are the machine ABI. Neither compiler object layouts nor JavaScript
objects are part of the contract.

### Proposed raw guest exports

The first prototype should use only wasm32-friendly `i32` parameters and
results:

```text
memory
tutuca_abi_version() -> i32
tutuca_alloc(size: i32) -> i32
tutuca_call(request_ptr: i32, request_len: i32) -> i32
tutuca_result_ptr() -> i32
tutuca_result_len() -> i32
tutuca_free(ptr: i32, len: i32)
```

`tutuca_call` returns a small machine status, not a domain result. A successful
call makes one complete CBOR response available at `tutuca_result_ptr()` and
`tutuca_result_len()`. Domain errors are encoded in that response. A trap,
invalid pointer, allocation failure, or inability to produce a response uses a
non-zero machine status or traps according to the final ABI specification.

The ABI specification must settle these details before implementation:

- whether the caller or callee owns each request and response allocation;
- whether `tutuca_free` is required for request memory, response memory, or
  both;
- how zero-length buffers are represented;
- response validity duration;
- integer overflow and memory-bound checks;
- whether calls may be reentrant (the recommended answer for version 1 is no);
- behavior after a trap or malformed request;
- maximum memory growth and maximum request/response sizes.

A packed `i64` pointer/length result would save calls but complicate JavaScript
and some language bindings. Start with the explicit `i32` exports and change
only if benchmarks show the additional calls matter.

### Imports

The preferred guest profile has no imports. It receives context in requests and
returns control operations as ordered effects. A zero-import guest is simpler
to validate and has a smaller authority surface than the current set of WIT
imports.

If an unavoidable import is found, it must be versioned, named in the ABI
specification, justified in [dyncomp/SECURITY.md](dyncomp/SECURITY.md), and
explicitly allowlisted before instantiation. An implementation must not silently
forward arbitrary host or WASI imports.

### Module validation

Before instantiation, the loader must:

1. Check the bundle descriptor's ABI identifier.
2. Inspect the module's imports and reject anything outside the ABI allowlist.
3. Check the required export names and export kinds.
4. Instantiate with only the permitted imports.
5. Call `tutuca_abi_version()` and require a supported version.
6. Enforce configured memory limits.

The raw WebAssembly JavaScript API exposes import/export names and kinds, but
does not provide complete function-signature reflection. Signature mismatches
must therefore produce a deliberate, well-explained load error when the version
probe or first invocation fails. A build-time verifier should perform stronger
signature checks with a Wasm parser.

## CBOR protocol

“CBOR” alone is not an interoperable contract. Version 1 needs a strict Tutuca
profile defined in CDDL and accompanied by valid and invalid byte fixtures.
Use [RFC 8949](https://datatracker.ietf.org/doc/html/rfc8949) for CBOR and
[RFC 8610](https://www.rfc-editor.org/info/rfc8610) for CDDL.

### Envelope

Every message should have an explicit envelope containing at least:

- protocol/version discriminator;
- operation or result discriminator;
- request identifier when useful for diagnostics and tracing;
- operation payload;
- success or structured error result;
- optional feature bits only if a concrete negotiated feature is introduced.

Use compact integer map keys on the wire only if the diagnostic and tooling
cost is justified. The CDDL and diagnostic renderer must always give them stable
names. Do not depend on map iteration order for semantics.

### Operations

Version 1 must cover the behavior of the current guest resource:

- `create`
- `restore`
- `get-field`
- `handle-event`
- `call-method`
- `with-field`
- `persist`
- `handle-request`
- `drop`

WIT resources become explicit guest-owned integer instance handles. The guest
SDK owns the handle table and validates generation/liveness. The host owns
lifecycle policy and must call `drop` for discarded and superseded instances.
The specification must preserve the current immutable-successor behavior: an
operation may return the same logical instance or a successor, and ownership of
both must be unambiguous.

Add a batch field-read operation only after measuring realistic rendering. It
may substantially reduce CBOR and boundary overhead, but should not be invented
before the current access pattern is benchmarked.

### Values

Tutuca values should be represented directly rather than through arena handles:

- null, booleans, text strings, arrays, and text-keyed maps map naturally to
  CBOR;
- `Value::Number` is always represented with the selected floating-point rule,
  while protocol handles, lengths, indices, and discriminants are integers;
- component-instance values require a collision-free representation, either a
  selected semantic tag or an explicit variant record;
- table values require a specified schema rather than relying on a language
  SDK's struct layout.

Before freezing fixtures, decide and test the behavior of NaN, infinities,
negative zero, invalid UTF-8, integer values outside the supported field range,
and floating-point width. The present JSON seam may normalize or reject some of
these, so compatibility must be an explicit decision rather than an accident.

### Effects and capabilities

Current `control` imports are already buffered. In the CBOR ABI, return them as
an ordered `effects` list in the operation response. It should cover the current
surface, including request/after/send/emit, relative and absolute dispatch,
stop, logging, and child-component operations.

Environment and configuration data should be passed in request context or
captured at `create`, as appropriate. Time, timezone, locale, configuration,
and random values must be frozen by the host when deterministic behavior
requires it. The guest must never gain ambient access merely because the data
moved from an import to a message.

Child creation and disposal need a protocol design before implementation. A
likely model is a bundle-scoped guest-generated token returned in an effect and
resolved by the host, but its ownership, uniqueness, failure, and persistence
semantics must be compared against the current `make`/`drop` behavior.

Operations documented as pure, especially field reads and pure method calls,
must reject effects or state changes. Moving effects into a response must not
quietly broaden what those operations may do.

### Required decoding profile

The decoder must treat guest data as untrusted. Version 1 should require:

- definite-length items only;
- canonical shortest integer encodings;
- valid UTF-8 text;
- text-only keys for Tutuca maps;
- rejection of duplicate map keys;
- explicit byte, item-count, nesting-depth, string-length, collection-length,
  and effect-count limits;
- checked conversions from CBOR integers to protocol field types;
- rejection of unsupported tags and simple values;
- clear handling of unknown optional fields and rejection of unknown required
  variants;
- no trailing top-level data;
- structured `malformed`, `unsupported-version`, `unsupported-operation`,
  `invalid-handle`, `limit-exceeded`, and guest-domain errors.

Deterministic encoding is required for golden fixtures, persisted values,
hashes, and snapshots. It is optional for transient request/response messages
unless deterministic traces or measured performance make it worthwhile. The
same semantic value must nevertheless decode identically in every SDK.

## Host-side byte transport

The host cannot directly treat a JavaScript `Uint8Array` as MoonBit `Bytes` on
wasm-gc. The full implementation therefore needs an auxiliary linear-memory
mailbox on the host as well as on a MoonBit wasm-gc guest.

Use a non-reentrant two-step import so JavaScript does not call back into the
active host Wasm instance:

1. Host MoonBit encodes the request into `Bytes` and copies it into host
   auxiliary memory.
2. Host calls an imported `tcomp_invoke(bundle, ptr, len) -> response_len`.
3. JavaScript copies the request into guest memory, calls `tutuca_call`, copies
   the response into a pending JavaScript `Uint8Array`, and returns its length.
4. Host reserves enough auxiliary memory for the response.
5. Host calls imported `tcomp_copy_response(ptr, len)`.
6. JavaScript copies the pending response into host memory.
7. Host copies it into MoonBit `Bytes`, decodes it, and clears the pending
   response through the defined success/error path.

The exact import names belong to the host's JavaScript FFI and are not guest ABI
surface. They must still define concurrency, pending-response ownership,
maximum sizes, behavior on guest traps, and cleanup on all error paths.

An early prototype may decode CBOR in JavaScript and retain the existing JSON
host seam to isolate guest-ABI work. That is not the finished architecture: it
adds conversion and duplicate validation, so the final path should encode and
decode the protocol in MoonBit.

## Bundle format and ABI selection

Keep the current archive structure and author-facing metadata. Add an explicit
descriptor field such as:

```json
{
  "abi": "core-cbor@1"
}
```

The exact spelling and fallback rules must be specified with the protocol.
Existing bundles without the field must continue to select the current WIT ABI.
The loader must never guess an ABI from exports or silently retry another ABI
after instantiation fails.

Bundle packing in [guests/template/pack.mjs](guests/template/pack.mjs) should
validate the declared ABI against the built module. The CLI should report the
ABI in bundle inspection output.

## Multi-language strategy

CBOR preserves multi-language potential only when each supported language has a
small, maintained SDK and all SDKs run the same conformance corpus.

### MoonBit

Publish a normal guest SDK package containing:

- the protocol value and operation types;
- strict CBOR encoding and decoding;
- the instance-handle table and lifecycle checks;
- effect buffering;
- adapters from the existing component authoring surface;
- helpers for the auxiliary memory mailbox.

The executable guest package will still contain a thin artifact-local export
wrapper because MoonBit link/export configuration is package-specific. It
should not contain a generated WIT tree or a copied SDK. The desired workflow is
roughly:

```text
implement component + manifest + views
depend on the published dyncomp guest SDK
moon build --target wasm-gc --release
tutuca pack-guest ...
```

The first implementation must validate whether an existing MoonBit CBOR package
meets the profile, especially maps, arrays, tags, canonical encoding, and hard
limits. `mizchi/cbor` is a candidate, not a decision. Extend it or implement a
focused codec if its public surface or validation behavior is insufficient.

### Rust

Provide a crate with:

- a component trait matching the semantic operations;
- generated or handwritten export wrappers;
- a handle table and effect collector;
- the same protocol types and fixture tests;
- a `wasm32-unknown-unknown` example build.

Rust is the second proof language because raw linear-memory exports are natural
on that target and it provides an independent implementation of the codec and
lifecycle rules.

### Other languages

C, C++, and Zig can implement the raw ABI with small wrappers. Go is possible
where its Wasm target permits the required exports and allocator integration.
Python, C#, and ecosystems whose strongest path is component-model tooling may
have worse developer experience with a bespoke raw ABI.

For those ecosystems, retain a minimal component-model adapter such as:

```wit
interface cbor-guest {
  exchange: func(request: list<u8>) -> result<list<u8>, string>;
}
```

The adapter carries exactly the same CBOR messages and semantics. It is a
transport option, not a second domain protocol. Its conformance tests must use
the same fixtures and lifecycle suite.

## Expected developer experience

### Improvements

- No per-guest WIT binding tree to regenerate, normalize, review, and check in.
- No copied SDK source in each guest.
- Normal language package dependency updates.
- Fewer build tools for the raw path: no component embedding, component
  wrapping, or jco transpilation in the normal guest build.
- One request/response call per operation instead of recursive arena traffic and
  multiple buffered-control calls.
- Byte-for-byte fixtures, replayable traces, and independent protocol tools.
- A zero-import module makes capabilities easier to explain and audit.

### New costs

- Errors formerly caught by WIT-generated types may become runtime protocol
  errors at an SDK boundary.
- Tutuca owns ABI versioning, allocation/lifetime rules, validation, and SDK
  compatibility.
- Every language needs a maintained ergonomic wrapper; “use a CBOR library” is
  not an SDK.
- Resource destructors become explicit handle lifecycle and leak checks.
- CBOR decoding expands the untrusted parser surface.
- Raw Wasm has less self-describing tooling and weaker runtime signature
  reflection than the component model.
- Boundary debugging is poor unless decoded traces and actionable errors ship
  with the ABI.
- Encoding and memory copies may regress small operations such as repeated
  scalar field access; batching might be needed.

### Required tooling

Before making the ABI the default, provide:

- `tutuca inspect-bundle` output showing ABI, Wasm imports/exports, declared
  components, and validation failures;
- a wire trace mode showing operation names and CBOR diagnostic notation with
  configurable value redaction;
- a standalone fixture/conformance runner for SDK authors;
- a build-time raw ABI verifier with signature checks;
- stable, contextual errors for malformed data, traps, unsupported versions,
  invalid handles, and size limits;
- golden request/response vectors in both hex and CBOR diagnostic notation.

## Security consequences

WIT is not itself the security boundary. A raw module with no imports can have a
smaller authority surface, but only if the loader validates the module before
instantiation and the decoder is strict.

The migration must preserve these properties:

- reject unknown imports rather than satisfying them from ambient JavaScript or
  WASI;
- keep all host authority represented by request context and validated effects;
- validate every pointer/length against memory bounds before copying;
- cap guest memory, request size, response size, collection sizes, nesting, and
  effects;
- catch guest traps and discard pending buffers and half-created handles;
- never execute code or scripts found in an archive outside the validated Wasm
  guest;
- retain view sanitization and every bundle-policy check unrelated to WIT;
- avoid exposing secrets in wire traces by default;
- define behavior for guest handle reuse and stale handles;
- test that pure operations cannot smuggle effects.

Every protocol or loader change must run the “What to check when changing this”
review in [dyncomp/SECURITY.md](dyncomp/SECURITY.md). Update that document with
file/line evidence when implementation moves or removes a channel.

The availability limitation remains: synchronous guest execution is not
preemptible. Record that explicitly in the security documentation and consider
worker isolation separately.

## Implementation plan

### Phase 0: freeze the proposal surface

Deliverables:

- an architecture decision recording `core-cbor@1`, dual-ABI migration, and
  the backend-neutral byte ABI;
- version 1 CDDL;
- written memory ownership, handle lifecycle, reentrancy, errors, effects,
  environment, child-component, and persistence rules;
- bundle descriptor versioning and fallback rules;
- decoder resource limits with rationale;
- initial valid and invalid golden vectors.

Exit criteria:

- Every operation in the existing WIT maps to a request/result shape.
- Every current import maps to request context, an effect, or a documented
  retained import.
- [dyncomp/DESIGN.md](dyncomp/DESIGN.md) and
  [dyncomp/SECURITY.md](dyncomp/SECURITY.md) reviews find no unspecified
  lifecycle or authority channel.
- No runtime implementation begins until the byte ABI and first fixture set can
  be independently reviewed.

### Phase 1: codec and conformance corpus

Implement a target-independent MoonBit protocol package, likely under
`dyncomp/wire`, without coupling it to DOM or loader code. Evaluate the existing
MoonBit CBOR package against the strict profile before deciding to depend on it.
Implement an independent JavaScript or Rust reference codec.

The shared corpus must include:

- one request and success/error response for every operation;
- every Tutuca value and table variant;
- deeply nested but valid values;
- malformed, truncated, overlong, duplicate-key, invalid-UTF-8, unsupported-tag,
  wrong-type, trailing-data, and over-limit inputs;
- numeric boundaries, NaN/infinity/negative-zero decisions;
- unknown optional fields and unknown required variants;
- deterministic persisted-value fixtures.

Exit criteria:

- MoonBit and the independent implementation accept and reject the same corpus.
- Re-encoding deterministic fixtures is byte-identical.
- Decoder limits are tested before allocation amplification can occur.
- Fuzz or property tests cover decoder termination and round trips where the
  available tooling permits it.

### Phase 2: dual-ABI host path

Add explicit ABI dispatch to the loader. Leave the current WIT path intact and
route `core-cbor@1` bundles to a new raw loader/transport module. Implement host
mailbox memory, import/export validation, version probing, byte copying, trap
cleanup, and decoded diagnostic errors.

Prefer a separate module over conditionals throughout
[dyncomp/host/wasm/abi.mjs](dyncomp/host/wasm/abi.mjs). Share only semantic host
operations after decoding. This keeps compatibility behavior reviewable and
makes eventual deletion measurable.

Exit criteria:

- Existing WIT bundles and tests are unchanged.
- The raw path rejects missing/wrong exports, all unapproved imports, bad ABI
  versions, bad pointers, oversized messages, malformed CBOR, and traps.
- No JavaScript re-entry into an active host Wasm call is required.
- Pending response buffers and guest handles are cleaned on every failure path.

### Phase 3: MoonBit counter proof

Build the published-style MoonBit guest SDK and port the smallest counter guest
to `core-cbor@1`. Keep the current counter as the behavior oracle during the
prototype; do not replace all checked-in generated guests yet.

Prove:

- construction and field rendering;
- events and successor instances;
- method calls and `with-field`;
- persistence and restore;
- effect ordering;
- explicit `drop` and absence of leaked live handles;
- packing and loading without wit-bindgen, wasm-tools component wrapping, or
  jco.

Exit criteria:

- The CBOR counter passes the same semantic host/harness tests as the WIT
  counter.
- The handwritten component code is not polluted by pointers, CBOR, or handle
  bookkeeping.
- Its build consumes a normal SDK package plus a thin artifact export wrapper,
  with no generated binding tree or copied SDK.

### Phase 4: independent Rust proof

Implement a Rust SDK crate and port a guest with meaningful state and
persistence, preferably temperature conversion or another example whose hidden
draft state catches lossy persistence.

Exit criteria:

- Rust consumes the same CDDL-derived fixtures and semantic harness.
- The Rust guest archive loads through the identical raw host path.
- Persistence, restore, errors, numeric behavior, effects, and handle lifecycle
  match the MoonBit implementation.
- The raw ABI is documented without requiring knowledge of MoonBit runtime
  representation.

This phase is the minimum evidence for a “multi-language” claim. Two SDKs that
share only a CBOR library but not the conformance corpus do not satisfy it.

### Phase 5: behavior coverage

Port representative guests rather than every guest at once:

- todo/TodoMVC for collections, nested values, events, and persistence;
- Slack or another nested-component example for make/drop and dispatch;
- table for the full table codec and larger payloads;
- a deliberately failing guest for traps, malformed responses, and effect
  rejection.

Extend [dyncomp/test](dyncomp/test) and
[dyncomp/host/host_test.mbt](dyncomp/host/host_test.mbt) so the same semantic
suite can run against both ABIs where behavior should be identical.

Exit criteria:

- All WIT operations and imports have behavioral parity tests.
- Nested instance values, relative paths, stopped dispatch, buffered effects,
  persistence refusal/fallback, and table payloads are covered.
- Repeated create/successor/drop cycles show no unbounded handle growth.

### Phase 6: benchmark and evaluate

Measure both ABIs on the same host, browser, release settings, and guest
behavior. Record at least:

- required tools and clean-build time;
- generated and handwritten source lines;
- raw module and packed archive sizes;
- cold bundle load and first instance creation;
- repeated scalar field reads;
- event dispatch and successor creation;
- nested-value encode/decode at several sizes;
- table encode/decode and rendering payloads;
- peak memory, allocations, copies, and live instance handles.

Agree on numerical acceptance thresholds before collecting final results.
Critical interactive paths should not regress materially without a measured,
documented simplicity or security benefit. If scalar field reads dominate and
regress, test a specified batch-read operation rather than weakening validation.

Publish the benchmark harness and raw results in the repository so the decision
is reproducible.

### Phase 7: default and compatibility policy

If the acceptance gates pass:

- make `tutuca new-guest` scaffold `core-cbor@1` by default;
- continue loading WIT `0.7` bundles for at least one announced compatibility
  window;
- keep a minimal CBOR-over-WIT adapter for ecosystems that need it;
- document how to opt into the legacy template during the window;
- add a migration guide focused on component code, bundle metadata, and test
  changes;
- deprecate generated WIT guest trees only after released consumers have an
  SDK replacement;
- remove old code only when usage, support policy, and rollback criteria permit
  it.

Never silently rewrite existing guest projects or reinterpret an unversioned
bundle as CBOR.

## Validation matrix

The implementation is not complete until the following areas have automated
coverage:

| Area | Required cases |
|---|---|
| Loading | supported ABI, unknown ABI, missing export, wrong export kind/signature, forbidden import, memory limit, version mismatch |
| CBOR | all values, truncation, duplicate keys, invalid UTF-8, unsupported tags, excessive depth/size/count, trailing bytes, numeric boundaries |
| Lifecycle | create, restore, same/successor instance, stale handle, double drop, trap cleanup, leak stress |
| Operations | field read, method call, event, update, request handling, persist success/refusal/failure |
| Effects | stable ordering, buffered execution, relative/absolute paths, stop, log, child make/drop, effects forbidden from pure operations |
| Security | zero/allowlisted imports, untrusted archive checks, pointer bounds, quotas, trace redaction, no authority from unknown fields |
| Compatibility | existing WIT bundles unchanged, equivalent semantic results across WIT and CBOR |
| Languages | identical golden corpus and host behavior for MoonBit and Rust |
| Performance | load, calls, nested values, tables, memory, copies, bundle size, build time |

Repository validation during implementation should include the focused dyncomp
tests, `guest-harness` when wasm-tools and jco are available, generated guest
and template drift checks while the WIT path exists, and the full
`moon run --target native cmd/dev -- ci` workflow before handoff.

## Acceptance gates

Adopt `core-cbor@1` as the default only if all of these are true:

- MoonBit and Rust guests pass the same protocol and semantic conformance suite.
- The default raw guest imports nothing, or every retained import has an
  accepted security justification.
- The memory and handle lifecycle survive stress and failure testing without
  leaks or stale-handle confusion.
- The strict codec rejects the full invalid corpus within bounded resources.
- Interactive performance has no unacceptable regression against WIT.
- Build/tooling complexity is measurably lower for a normal guest.
- Guest authors receive protocol-independent component APIs and useful decoded
  errors; pointer and CBOR details remain inside SDKs.
- Existing bundles retain a documented compatibility path.
- The CDDL and machine ABI can be versioned without inspecting compiler-specific
  layouts.

Retain WIT as the primary ABI if any of these occur:

- the design requires raw wasm-gc references and therefore loses credible
  multi-language support;
- every SDK reimplements large amounts of divergent lifecycle logic;
- host/guest memory ownership cannot be made stable and testable;
- runtime validation and diagnostic failures are materially worse than the
  current generated bindings;
- the measured encoding/copying cost cannot be repaired without making the
  protocol application-specific and fragile;
- component-model composition and tooling prove more valuable than the removed
  build machinery.

## Open decisions to resolve in Phase 0

1. The exact request/result envelope and integer key assignments.
2. Whether instance references use a CBOR tag or an explicit variant.
3. Floating-point rules for NaN, infinities, negative zero, and canonical width.
4. Request and response allocation ownership and response lifetime.
5. Handle generation/reuse rules and successor ownership.
6. The child make/drop token model.
7. Which environment values are captured at construction versus supplied per
   operation.
8. Exact decoder limits and whether hosts may advertise lower limits.
9. Whether deterministic encoding applies to all traffic or only fixtures and
   persistence.
10. The bundle ABI field spelling and compatibility-window duration.
11. Whether the initial prototype keeps a temporary JSON seam inside the host.
12. Benchmark thresholds and the criteria for adding batch field reads.

## Likely repository changes

Names are provisional; prefer packages that keep the wire protocol independent
from browser and DOM code.

```text
dyncomp/
  wire/                    CDDL-aligned types, codec, limits, fixtures
  host/wasm/
    cbor_abi.mjs           raw guest loader and byte transport
    cbor_glue.mbt          host mailbox and protocol bridge
  test/
    cbor-fixtures/         shared valid/invalid vectors
    cbor_abi.test.mjs      loader and machine-ABI failures
guests/
  sdk.mbt                  legacy WIT SDK during compatibility window
  counter-cbor/            first MoonBit proof guest
  rust-*/                  independent proof guest or external fixture
```

Do not hand-edit generated guest trees. The initial CBOR guest should be a
separate proof package until the new SDK and build are accepted. If the plan is
adopted, update the guest generator, embedded guest template, task runner,
security evidence, and documentation together; use their existing generation
tasks rather than editing generated outputs.

## References

- [CBOR, RFC 8949](https://datatracker.ietf.org/doc/html/rfc8949)
- [CDDL, RFC 8610](https://www.rfc-editor.org/info/rfc8610)
- [MoonBit foreign-function interface](https://docs.moonbitlang.com/en/stable/language/ffi.html)
- [MoonBit package configuration](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html)
- [WebAssembly JavaScript API](https://webassembly.github.io/spec/js-api/)
- [WebAssembly GC overview](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Overview.md)
- [Component-model GC discussion](https://github.com/WebAssembly/component-model/issues/525)
- [Component-model language support](https://component-model.bytecodealliance.org/language-support.html)
- [Rust `wasm32-unknown-unknown`](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html)
- [mizchi/cbor](https://github.com/mizchi/cbor.mbt)
