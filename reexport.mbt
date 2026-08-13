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
