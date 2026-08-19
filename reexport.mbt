// The module-root package is a thin facade over the value+path runtime in
// core/ (marianoguerra/tutuca/core). Its purpose is the browser playground:
// examples import the runtime as @tutuca, but the in-browser moonc (unlike a
// moon.pkg) can't re-alias core to @tutuca, so it can only reach a package by
// its own name. This package IS named `tutuca` (module root), so re-exporting
// core's public value types here — transparently, via `using` — lets
// `@tutuca.Value` resolve in the browser AND stay identical to `@core.Value`.
// External users importing `marianoguerra/tutuca` get the same friendly facade.

///|
pub using @core {type Value, type RequestOpts, trait Ctx, trait Obj}

// The intent types, for the same reason and with the same failure mode.
//
// A generated component with an `intent` bucket names `@tutuca.IntentOpts` in
// the signature of its `dispatch` — `emit_intent_sender` writes the default
// route as `@tutuca.IntentOpts::new()` rather than spelling the two legs. In a
// module `@tutuca` aliases core and that resolves; in the playground `@tutuca`
// IS this facade, so a card that raises an intent would not compile in the one
// place an author writes one in a browser. `Leg` comes with it because a route
// is written `route=[Dyn]`, and `IntentAnswer` / `IntentCall` because a card
// may register a handler for the `lex` leg.

///|
pub using @core {type IntentOpts, type IntentCall, type IntentAnswer, type Leg}

// The contract reporters and the channel they report through.
//
// Not a convenience: a GENERATED module names them. `gen-views` compiles a
// `requires` / `ensures` / `invariant` into a guard that calls
// `@tutuca.precondition_failed(…)`, and in the playground `@tutuca` IS this
// facade — so a card with a contract compiled everywhere except the one place
// an author writes one in a browser, with `Value precondition_failed not found
// in package tutuca`. It went unnoticed because no example in the corpus had a
// contract; `check-viewgen-tab.mjs` now carries one that does.
//
// The channel comes with them rather than after them: a page that can be told a
// rule refused something and cannot ask to hear it is half a feature.

///|
pub using @core {
  type Refusal,
  type RefusalCode,
  precondition_failed,
  postcondition_failed,
  invariant_failed,
  on_refusal,
  refuse,
  refusing,
}
