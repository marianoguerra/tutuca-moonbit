// The module-root package is a thin facade over the value+path runtime in
// core/ (marianoguerra/tutuca/core). Its purpose is the browser playground:
// examples import the runtime as @tutuca, but the in-browser moonc (unlike a
// moon.pkg) can't re-alias core to @tutuca, so it can only reach a package by
// its own name. This package IS named `tutuca` (module root), so re-exporting
// core's public value types here — transparently, via `using` — lets
// `@tutuca.Value` resolve in the browser AND stay identical to `@core.Value`.
// External users importing `marianoguerra/tutuca` get the same friendly facade.

///|
pub using @core {type Value, type RequestOpts}
