# What a `tgc` module can and cannot do

The premise is the same one `dyncomp/SECURITY.md` set out: a component can be
fetched from anywhere and mounted into a running app, and that is only worth
building if it is possible to say precisely what such a component may do.

This document says it for `tgc/1`. It is not a port of the older one. Most of
the argument is unchanged, because most of it was never about the wasm contract
— views, CSS, event paths and intents are the host's policy and that policy is
the same object. What changed is the substrate, and it changed in both
directions: some claims are stronger now, and **two are weaker**. Both are
named below rather than left for somebody to find.

Everything here was checked against the code.

## Summary

| Channel | Reaches | State |
|---|---|---|
| the import section | everything a module can reach | **closed, and legible** — a module declares no memory and no table, so `tut` is the whole of it, and the section names only what the body calls (§1) |
| a module's own state | itself | **closed by the engine** — `state` is `&?eq` and each module casts it back to a type only it can name; anyone else traps (§2) |
| an instance a host handed over | that instance's own surface | **bounded, and DURABLE** — bounded by the instance's two-slot vtable, which is the same authority the host has; durable because a reference is not a handle that expires (§3, **weaker than before**) |
| a mutable array a host handed in | that module's state, later | **the host's own foot** — a module stores the array it was given, so a host that keeps one keeps a way in (§3a) |
| re-entering a module mid-call | the module's own consistency | **open, and narrower than it looks** — core wasm has no re-entrance rule and neither does this, but copy on write makes a reference cycle unreachable by ordinary means (§4, **weaker than before**) |
| effects | the host's tree and services | **asked, not performed** — buffered by the host and discarded whole if the transition abandons (§5) |
| ambient facts (clock, entropy, network) | nothing | **absent** — `tut` has none, so a module asks the host over an intent (§6) |
| guest views, guest CSS, event paths, host intents | the host's DOM, stylesheet and services | **unchanged** — the same `policy/` decisions, enforced at registration (§7) |

## 1. The import section is the authority list, and it is legible

A `tgc` module declares **no memory and no table**. There is nothing to smuggle
through, no linear address space to corrupt, and no indirect-call table to
confuse. Everything a module can reach arrives through the namespace `tut`.

That was already the shape of the argument the older contract made about its
WIT world. What is new is that the section **discriminates**. `tgc/emit` writes
the body first and imports what the body turned out to call, so:

- a card that computes and renders imports arithmetic and constructors, and
  **none of the machinery for an effect**;
- a card that sends imports `eff_send` and not `eff_ask`;
- a card that declares a contract imports `eff_log`, because a declined rule
  says so.

A host can therefore read a module and know what it does before running a line
of it. Under the older contract every guest imported the whole world and the
section said only that it was a guest. `tgc/emit/compile_test.mbt` pins this,
and `tgc/test/compose.test.mjs` asserts that every prototype module's imports
are `tut` and nothing else.

**What this does not say.** The section is what the module *may call*, not what
it *will*. A card that imports `eff_send` may never send. The claim is an upper
bound, and a tight one; it is not a behaviour.

## 2. State opacity is the engine's, not a convention's

`tg_inst.state` is `&?eq` — an opaque reference. Each module casts it back to
its own concrete type with `ref.cast`, and a module that tries to read another
module's state **traps**.

This is strictly stronger than the handle table it replaces. A handle is an
integer, and an integer can be guessed, incremented or forged; the old bridge
was safe because nothing let a guest mint one, which is a property of the bridge
rather than of the type. Here it is the type: there is no way to write down a
`tg_inst` whose state you did not create, and no way to read one you did not.

`tgc/test/compose.test.mjs` proves it by pointing one module's vtable at
another's state and catching the trap.

## 3. An instance a host hands over is DURABLE — weaker than before

Under the older contract, a compound value crossed as a `u64` handle into a
host-side arena, **valid only for the duration of one call**. Nothing a guest
captured stayed reachable after it returned.

Here a value is a reference, and a reference lives as long as somebody holds it.
A module handed a child instance can keep it — in a field, in a list, across
transitions — and call it later.

That is the format's whole point, and it is a real reduction in what the host
controls. What bounds it:

- **What a held instance can do is what its vtable does**: `get` and an op-coded
  `call`. That is the same surface the host itself uses, so holding one confers
  no authority the holder did not already have by being able to ask the host.
- **A module cannot fabricate one.** `tg_inst` is a GC struct; there is no
  integer, no address and no cast that produces one from nothing.
- **Revocation is gone, though.** A host that hands over a child cannot take it
  back — the older arena took everything back at the call boundary, whether the
  host meant to or not. A host that needs revocation must hand over something it
  can invalidate (an instance of its own that forwards, and stops), and nothing
  in the format does that for it.

## 4. Re-entrancy is possible — weaker than before

The Component Model forbids re-entering a component while a call into it is
active. Core wasm has no such rule, and this format does not add one: a parent
can read a field of a child that is, at that moment, reading a field of the
parent.

That is a capability the format was built for — it is what lets a component hold
and traverse another one — and it is also a hazard the older contract did not
have.

**Copy on write narrows it further than the design intended.** Writing into A
answers a NEW A; B still holds the old one. So A-holds-B and B-holds-A cannot
both be true, because the write that would close the ring is the write that
leaves it open. A chain of instances built the ordinary way is finite however
it is assembled, and `tgc/test/compose.test.mjs` walks one to the end to say so.

What is left:

- **A module that mutates in place has no such protection.** Every module
  `tgc/emit` generates answers a successor, so a re-entrant read sees an intact
  predecessor. Nothing in the format requires that shape, and a hand-written
  module holding mutable state can be re-entered mid-update. The identity
  counter every generated module carries is the benign case.
- **A mutable array handed IN is a channel that stays open** — see §3a. It is
  the one ordinary way to build a real cycle, and `compose.test.mjs` builds one:
  the recursion is unbounded and the engine's stack ends it with a **trap**.
  That is an answer where the older contract's "runaway guest call" row was a
  hang, and it is still not a budget: a module that loops without recursing
  hangs exactly as before.

### 3a. A mutable array handed in is a channel that stays open

`tg_vals` and `tg_entries` are arrays of MUTABLE fields, because a growable list
needs them. A module stores the array it was given rather than a copy — that is
what makes copy on write cheap — so **a host that keeps the array it constructed
with keeps a way to change that module's state afterwards**, with no call and no
successor.

This is the host's own foot, not a hole a module can reach through: a module has
no way to obtain an array a host did not hand it. But a host that builds a
component's arguments and then retains the arrays has not finished handing them
over. Build them, pass them, drop them.

## 5. Effects are asked for, not performed

Every effect a card can write — `send`, `sendAt`, `ask`, `notify`, `forward`,
`reply`, `fail`, `drop`, and the `log` a declined rule emits — is a `tut`
import, and the **host** buffers them. They are applied through the dispatching
handler's context after the call returns, and a transition that abandons
discards what it buffered.

The buffer is host-side rather than guest-side deliberately: the host is what
brackets the call and therefore what knows when it ended. A guest-side buffer
would be a guest deciding when its own effects become real.

`sendAt` addresses a place **relative to the dispatching instance**. There is no
absolute form, so a component addresses its own subtree and never the tree it
happens to be mounted in — the same property the older contract had, kept for
the same reason.

## 6. No ambient facts

`tut` has no clock, no entropy, no filesystem, no network and no timer. A module
cannot read the time, which removes the primitive most timing side channels are
built from, and cannot generate a random number.

A fact a module cannot compute it asks the host for over an intent, and the host
decides per call. That is unchanged, and it is why `Instant` is a value the
format carries rather than a call it offers.

## 7. Views, CSS, event paths and host intents are unchanged

None of these were ever about the wasm contract. A module's views are **data** —
HTML the host compiles with its own parser — so a module never touches the DOM,
and `dyncomp/policy` decides what a view may reach: unsafe names, direct network
sinks, raw markup, guest-authored utility CSS and URL-bearing macro arguments
are refused for an untrusted module; `<img src>` and `<a href>` reopen only for
an origin settled before render.

Two rows the older document left **open** are still open, for the same reasons:

- **`control.intent` → host handlers** needs caller-aware authorization. The
  plumbing exists (`IntentCall.from`) and no host uses it.
- **A hung or runaway call** needs worker isolation. §4 narrows this — a
  re-entrant cycle traps on stack exhaustion rather than hanging — but a module
  that loops does not.

## What to check when changing this

- **The frozen rec group.** Changing it changes the identity of every type in
  it, in every module ever built. §2's guarantee is that group's subtyping.
- **`runtime_imports` in `tgc/emit`.** Adding a row adds something a card can
  reach. If it is an effect, §5's buffering has to cover it; if it reads an
  ambient fact, §6 stops being true.
- **The `tut` object a host passes.** A host that adds an import the format does
  not define has widened the authority list without widening the document.
