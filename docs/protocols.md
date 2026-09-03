# Tutuca protocols

Protocols describe what components can do without coupling them to a module,
file, or concrete component name. `protocol` is the preferred term:
“interface” often means only an inbound callable surface, while a tutuca
protocol is bidirectional and also covers observations, views, and dynamic
bindings.

Every protocol has a canonical string id. The local name is only a source
alias; manifests and runtime checks carry the id.

```text
protocol Lifecycle = "tutuca.dev/std/Lifecycle@1" {
  handle {
    message { init, deinit }
    intent { resume, suspend }
  }
  express {
    message { resumed, suspended }
    intent { wantsAttention(String) }
  }
  property { active: Bool }
  view { display }
  provide { lifecycleState: String }
  lookup { clock: Int }
}
```

Another source unit refers to it without a filesystem import:

```text
import protocol "tutuca.dev/std/Lifecycle@1" as Lifecycle
```

## Implementing a protocol

The component’s unnamed, implicit protocol is its own `handle` and `express`
surface. A named protocol implementation qualifies members to avoid clashes:

```text
state Screen implements Lifecycle {
  active: Bool

  property { Lifecycle::active = .active }
  view { Lifecycle::display = main }
  provide { Lifecycle::lifecycleState = .status }
  lookup { Lifecycle::clock = 0 }
}

handle Screen {
  message { Lifecycle::init, Lifecycle::deinit }
  intent { Lifecycle::resume, Lifecycle::suspend }
}

express Screen {
  message { Lifecycle::resumed, Lifecycle::suspended }
  intent { Lifecycle::wantsAttention(String) }
}
```

A `property` is a typed read operation, not a promise that storage has a
particular field. `.active` binds it to a field; a bare `get` is implemented by
`get active { … }` in the script block. Local properties are private by
default; `pub` exposes one directly, while a protocol binding exposes it under
the protocol member regardless of the local name. Reads that cannot be
satisfied return `Null` and emit a structured runtime notice.

A protocol view is a semantic role. Its implementation maps that role to a
local view. Runtime selection tries the mapping, a same-named view, then
`main`; a missing mapping is reported without replacing the page with an
exception.

Qualified `provide` and `lookup` keys are stored as
`<canonical-id>::<member>`, in a namespace separate from raw binding names.

## Sending and expressing

An expressed message is an outbound capability, not a destination. `send`,
`sendAt`, and `reply` choose where an addressed message goes; `intent`
chooses a route. The `express` declaration says which operations this
component may initiate.

```text
send 'refresh'                 // deliberately raw name
send refreshed                 // this component's implicit protocol
send Lifecycle::resumed        // named protocol, canonicalized on the wire
ask Lifecycle::wantsAttention 'editor'
```

Quoted names remain the dynamic escape hatch. Unquoted names are checked
against `express`. Qualified names resolve through the imported string id, so
two protocols may both define `focus` without colliding.

## Component constraints

Protocols are component types:

```text
state List {
  rows: Array[Component[protocol ListItem & Selectable]]
}
```

The constraint survives in the declared `Ty`. Installing a dynamic component checks its
runtime schema and explicit protocol claims. A mismatch rejects that value,
keeps the previous/default slot value, and emits `PROTOCOL_TARGET_MISMATCH`.

## Strict and gradual behavior

A compilation batch is **strict** when every referenced protocol definition is
present and every checkable claim, handler, outbound operation, property,
view, provide, lookup, and type constraint validates. It is **gradual** when a
definition or implementation can only be known after dynamic loading. A known
contradiction is still an error; an absent dynamic fact is a warning.

At runtime, dynamic composition is always best effort. A failed assumption is
data on the centralized `RuntimeNotice` channel:

- `Refused(Refusal)` for ordinary dispatch/contract refusals;
- `ProtocolMismatch(RuntimeProtocolNotice)` for protocol failures;
- `RuntimeWarning(String)` for uncategorized warnings.

Static diagnostics and runtime mismatches use the same `ProtocolIssueCode`
vocabulary. Runtime records additionally carry the component, path, state,
operation, and chosen resolution (`ReturnedNull`, `UsedMainView`,
`RejectedComponentValue`, and so on). Notices are emitted when a deferred
assumption is exercised and fails, not merely because a module is gradual.

The fallback rules favor a partially usable UI: missing properties/lookups
return `Null` or a declared default, missing semantic views fall through to
`main`, an invalid slot value is rejected, unhandled intents continue or
produce their ordinary unhandled outcome, and invalid transitions retain the
last good state.

## Scope of a protocol

Protocols cover the component features that cross a component boundary:
handled and expressed messages/intents, semantic views, typed reads,
`provide`/`lookup` bindings, and component-valued fields. State fields, helper
types, fixtures, contracts, and script `pred`/`compute`
declarations remain implementation details. A stable zero-argument observation
should be a protocol `property`; an operation with arguments or an asynchronous
answer should be a message or intent. This keeps runtime conformance structural
and avoids exposing a component's internal handler vocabulary as an object API.
