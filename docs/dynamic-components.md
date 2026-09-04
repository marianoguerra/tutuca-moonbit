# Dynamic components: hosting them, and writing them

Everything else in tutuca is decided before the program runs. This is the part
that is not: a WebAssembly module fetched at runtime, from someone you have no
reason to trust, mounted into a page that is already running and rendered by the
same machinery as the components you compiled in.

The format is **`tgc`** — core WebAssembly plus the GC proposal, and nothing
else. No component model, no WIT, no archive, no linear memory. A module is one
`.wasm` file that carries its own manifest.

The format is specified in [`../tgc/SPEC.md`](../tgc/SPEC.md); what a loaded
module can and cannot do is in [`../tgc/SECURITY.md`](../tgc/SECURITY.md),
checked against the code and against tests. This page is the practical route
into both.

## Why this is possible at all

Two things, and the second is the one that is new.

**A module declares its shape without revealing its state.** The manifest says
what components exist, what fields each holds and of what type, which messages
it accepts, and what its views are; the state itself never crosses. The host
reads one field at a time while rendering, and a handler takes the module's own
instance and answers its successor. That is the same copy-on-write model a
compiled-in tutuca component has, which is why nothing downstream can tell them
apart.

**Type identity is structural, so there is nothing to agree on.** Wasm GC
canonicalizes recursion groups: two modules that declare the *same* rec group
receive the same runtime types. Every `tgc` module carries a verbatim copy of
the frozen group `tgc/1` in its own type section, and that is the whole
interoperation mechanism — no shared registry, no linker, no negotiated ABI, no
version handshake. A module built by a toolchain that has never heard of this
repository holds, calls and is called by one built here.

The consequence is the thing the format was written for: **a component can hold
another component.** An instance is an ordinary GC struct, so a module can keep
one in its own state, put it in a list, pass it on, and read a field through it
with no host hop and no token table. `tgc/test/compose.test.mjs` builds a tree
out of modules from three different production routes and walks it.

And because a module's views are **data** — HTML templates the host compiles
with its own parser — the module never touches the DOM. The renderer, event
delegation, morphing, the modifiers and the linter all apply to it unchanged.

## Writing a component

The shortest route is a **card**: one HTML file holding a spec block, a script
block and templates, compiled to a module by `tgc/emit`. The card playground
(`cmd/dev -- tutucard-playground`, then `dist/tutucard/`) checks it, compiles
it, mounts it, and hands you the `.wasm`. No toolchain: the compiler is a
MoonBit library in the page.

```html
<script type="tutuca/spec">
  state Counter { count: Int }
</script>

<script type="tutuca/script">
  receive inc { .count += 1 }
  compute label { $'count: {.count}' }
</script>

<template id="Counter:main" data-root>
  <button @on.click="inc">+</button>
  <output @text="$label"></output>
</template>
```

The card language, its limits, and what the compiler refuses are in
[`../skill/tutuca/tutucard.md`](../skill/tutuca/tutucard.md) and
[`../skill/tutuca/schema.md`](../skill/tutuca/schema.md).

The other route is to write the module yourself, in any language that emits core
wasm with GC. Carry the preamble, export `tgc.abi`, `tgc.describe`, `tgc.make`
and `tgc.serve`, and import from `tut`. `cmd/dev -- tgc` prints the canonical
preamble in both WAT and Wax; `tgc/proto/` holds three hand-written modules —
one WAT, one Wax, one WAT whose preamble is spelled differently on purpose —
that compose with each other and with anything the card compiler emits.

Two things to know before writing one by hand:

**The core rec group is frozen.** A group's identity depends on the whole group,
so adding a type, reordering, or changing a field breaks identity for *every*
type in it and your module links against nothing. Extension goes through the
`tg_ext` arm and the `i32` op space, never by touching the group.

**`ref.null` is absence; `kind 0` is the null value.** A transition with no
answer does not happen; a callable with no answer answers Null. The distinction
is load-bearing and there is no option wrapper to hide it.

## Hosting them

The host is assembled from published packages:

| package | what it does |
| --- | --- |
| `tgc/abi` | the frozen preamble, the op codes, the tag numbers and the export names — the single source, emitting both WAT and a Wax AST so the two cannot disagree |
| `tgc/rt` | the runtime module `tut`: the value vocabulary and the host services, one per page rather than one per component |
| `tgc/emit` | the card compiler, and `compile_runtime()` for the module above |
| `tgc/host` | wraps a module's instance as an ordinary `&Obj`, and synthesizes real components from its manifest. `&Guest` is the seam — tests implement it with an in-process fake, so the whole host runs with no wasm at all |
| `tgc/policy` | what this host will *accept*. Three tiers, and a module that needs what the policy withholds — its own CSS, an external origin — is refused rather than degraded |
| `tgc/persist` | a component that has to outlive the page |

Loading is two steps and neither is a framework:

```js
// 1. instantiate — the module against the shared runtime
const { manifest } = await loadGuest(wasmBytes, "my-mount-point");

// 2. register — the manifest becomes components in a scope of its own
//    (MoonBit side: @host.register_module(scope, guest, manifest, policy~))
mountCompiled("my-mount-point", JSON.stringify(manifest), "");
```

`tutucard/web/card.js` plus `tutucard/playground/cardguest.mbt` are that pair
written out in full, and they are the reference host: `card.js` instantiates and
installs the guest calls on `globalThis.__cardguest`, `cardguest.mbt` implements
`&Guest` over them and calls `register_module`. Nothing in either is
card-specific once the module exists.

The manifest comes **out of the module** (`tgc.describe`), not out of a file
beside it. That is what makes one file the whole distribution: there is no way
for a component to arrive with half of itself.

## What a module can do to your page

Summarized from [`../tgc/SECURITY.md`](../tgc/SECURITY.md), which states each
claim's actual strength and names the two channels that are open by design:

| channel | reaches | state |
| --- | --- | --- |
| the import section | exactly what it lists | **the whole authority list, and legible.** A module declares no memory and no table, so there is nothing else. `tgc/emit` writes the body first and imports what the body turned out to call, so a card that performs no effect imports none of the effect vocabulary — readable before running a line |
| another module's state | nothing | **the engine's, not a convention's.** State is `ref null eq`; a module casts it back to its own type, and a module that tries to read someone else's traps |
| an instance a host handed over | that instance's own surface | **bounded, and durable.** Bounded by the instance's two-slot vtable, which is the same authority the host has; durable because a reference is not a handle that expires |
| a mutable array a host handed in | that module's state, later | **the host's own foot.** A module stores the array it was given; a host that keeps one keeps a way in. Build them, pass them, drop them |
| views | your DOM/network | `tgc/policy` refuses direct URL/CSS sinks, URL-bearing macro arguments and runtime markup for an untrusted module; `<img src>` / `<a href>` reopen only for an origin settled before render |
| module CSS | your stylesheet | refused outright for an untrusted module |
| `intent` → host handlers | your own services | **open** — needs caller-aware authorization |
| a hung or runaway call | the page's responsiveness | **open** — needs worker isolation |

`tut` has no clock, no entropy, no filesystem, no network and no timer. A fact a
module cannot compute it asks the host for over an intent, and the host decides
per call — which is why `Instant` is a value the format carries rather than a
call it offers.

A page that wants an untrusted module to show pictures allows external URLs and
names the origins in the same call:

```moonbit
@policy.Policy::untrusted().allowing_external_urls(["https://cdn.example"])
```

That reopens `src` on `<img>` and `href` on `<a>`, and only for a URL whose
ORIGIN is settled before anything renders — `<img :src="$'https://cdn.example/a/{.id}.png'">`
is allowed, `<img :src=".avatar">` is not. The path is still the module's to
write, so allow the origins you meant: an empty list means any `https://`
origin.

A module that should work at more than one server names no origin at all. It
declares a **config var** and its views spend it, and the host binds it:

```moonbit
@policy.Policy::untrusted().with_config([
  ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
])
```

```html
<img :src="$'{host.mediaOrigin}{.avatarPath}'">
```

`host.name` resolves at parse time to the string the host bound, so the same
rule checks it and the origin is still settled at registration — it is just
written by the host rather than by the module. Binding an origin IS allowing it,
which is one decision in one call.

The manifest declares nothing for any of this. The host's policy is the single
source of what a view may reach, and a view that names an origin the policy does
not allow is refused with "this host does not allow external URLs in views".

The two open rows above are open on purpose and are marked as such in the code.
If you host untrusted modules today, they are what to think about.
