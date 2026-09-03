# Protocols

Use a protocol when components need a shared capability without sharing a
concrete component or filesystem module. Protocol identity is a string:

```html
<script type="tutuca/spec">
protocol Lifecycle = "tutuca.dev/std/Lifecycle@1" {
  handle { message { init, deinit } intent { resume, suspend } }
  express { message { resumed } intent { wantsAttention(String) } }
  property { active: Bool }
  view { display }
  provide { lifecycleState: String }
  lookup { clock: Int }
}

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
  message { Lifecycle::resumed }
  intent { Lifecycle::wantsAttention(String) }
}
</script>
```

Import by id, never by a path:

```text
import protocol "tutuca.dev/std/Lifecycle@1" as Lifecycle
```

`property` means a typed read operation. Bind it explicitly to `.field`, or use
a bare `get` plus a `get name { … }` script body; it does not require a
same-named stored field. A local property is private unless marked `pub`, while
binding it to a protocol exposes it under the protocol's member name.
Protocol views are semantic roles mapped to local view names. Qualified
provide/lookup values use the canonical-id namespace.

Effects distinguish three cases:

```text
send 'refresh'                  // raw/dynamic
send refreshed                  // implicit component protocol
send Lifecycle::resumed         // imported protocol
ask Lifecycle::wantsAttention 'editor'
```

Use protocols as component constraints with
`Component[protocol ListItem & Selectable]`.

Whole-batch validation reports **strict** when everything is proved and
**gradual** when dynamic loading leaves facts deferred. Runtime mismatches do
not crash the UI: they choose a documented fallback and emit a structured
`ProtocolMismatch` through `on_runtime_notice`, using the same issue codes as
the static checker.

Protocols cover boundary-visible behavior: handled/expressed operations,
semantic views, typed properties, dynamic bindings, and component constraints.
Fields, helper types, fixtures, private properties, `pred` / `invariant` rules,
the `requires` / `ensures` clauses that attach them, and parameterized `compute`
declarations stay private — declared in the spec block does not mean visible at
the boundary, and a protocol says nothing about what an implementor promises
itself. Promote a stable observation to a protocol `property`, and model an
argument-taking or asynchronous operation as a message or intent.
