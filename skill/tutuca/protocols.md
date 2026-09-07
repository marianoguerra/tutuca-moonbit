# Protocols

Use a protocol when components need a shared capability without sharing a
concrete component or filesystem module. `protocol` and not "interface": an
interface usually means an inbound callable surface, while a protocol here is
bidirectional and also covers observations, views and dynamic bindings.

Protocol identity is a string, and the local name is only a source alias —
manifests and runtime checks carry the id:

```tutu
spec:
  protocol Lifecycle = "tutuca.dev/std/Lifecycle@1":
    message init
    message deinit
    intent resume
    intent suspend
    express message resumed
    express intent wantsAttention(String)
    property active :: Bool
    view display
    provide lifecycleState :: String
    lookup clock :: Int

  Screen:
    field status :: String
    property active :: Bool

    message Lifecycle::init
    message Lifecycle::deinit
    intent Lifecycle::resume
    intent Lifecycle::suspend
    express message Lifecycle::resumed
    express intent Lifecycle::wantsAttention(String)

    implements Lifecycle
    property Lifecycle::active = active
    view Lifecycle::display = main
    provide Lifecycle::lifecycleState = it.status
    lookup Lifecycle::clock = 0

logic:
  Screen:
    property active :: Bool:
      get: true

view:
  Screen:
    p():
      @(it.status)
```

Import by id, never by a path:

```text
import protocol Lifecycle = "tutuca.dev/std/Lifecycle@1"
```

`property` means a typed read operation. A component declares its own
`property name :: Type` and gives it a body in `logic:`; the `property
Lifecycle::active = active` line then binds that local property to the
protocol's member. It does not require a same-named stored field. A local
property is private unless marked `~public`, while binding it to a protocol
exposes it under the protocol's member name. Protocol views are semantic roles
mapped to local view names — `view Lifecycle::display = main`. A qualified
`provide` or `lookup` takes a value the same way an unqualified one does, and
lives in the canonical-id namespace rather than the raw one.

Effects distinguish three cases:

```text
send 'refresh'                  // raw/dynamic
send refreshed                  // implicit component protocol
send Lifecycle::resumed         // imported protocol
ask Lifecycle::wantsAttention 'editor'
```

Use protocols as component constraints with
`Instance[protocol ListItem & Selectable]`. The constraint survives in the
declared `Ty`, so installing a dynamic component checks its runtime schema and
its explicit protocol claims; a mismatch rejects that value, keeps the previous
one, and reports `PROTOCOL_TARGET_MISMATCH`.

Whole-batch validation reports **strict** when every referenced definition is
present and every checkable claim validates, and **gradual** when a fact can
only be known after dynamic loading. A known contradiction is an error either
way; an absent dynamic fact is a warning.

Runtime mismatches do not crash the UI. Each chooses a documented fallback and
emits through `on_runtime_notice`, in the same `ProtocolIssueCode` vocabulary
the static checker uses:

- `Refused(Refusal)` — an ordinary dispatch or contract refusal;
- `ProtocolMismatch(RuntimeProtocolNotice)` — a protocol failure, carrying the
  component, path, state, operation and the resolution chosen (`ReturnedNull`,
  `UsedMainView`, `RejectedComponentValue`, …);
- `RuntimeWarning(String)` — uncategorized.

The fallbacks favour a partly usable UI: a missing property or lookup answers
`Null` or its declared default, a missing semantic view falls through to `main`,
an invalid slot value is rejected and the previous value kept, an unhandled
intent continues to its ordinary unhandled outcome, and an invalid transition
keeps the last good state. A notice fires when a deferred assumption is
exercised and fails, not because a module is gradual.

Protocols cover boundary-visible behavior: handled/expressed operations,
semantic views, typed properties, dynamic bindings, and component constraints.
Fields, helper types, fixtures, private properties, `pred` / `invariant` rules,
the `requires` / `ensures` clauses that attach them, and parameterized `compute`
declarations stay private — declared in `spec:` does not mean visible at
the boundary, and a protocol says nothing about what an implementor promises
itself. Promote a stable observation to a protocol `property`, and model an
argument-taking or asynchronous operation as a message or intent.
