# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed — typed-state components (breaking)

The dynamic component API was replaced by a typed-state model (inspired by
[rabbita](https://github.com/moonbit-community/rabbita)'s TEA shape):

- State is a plain struct with `derive(ToJson, FromJson)`; `component(...)`
  takes `init~` instead of `fields=` and every handler is compiler-checked
  against the struct. `Instance`, `InstanceHandler` and `MethodFn` are gone;
  `Component::make` returns the instance as a `@tutuca.Value`.
- The four effectful buckets (`input`/`receive`/`bubble`/`response`) fold
  into ONE `update : (S, Dispatch, &Ctx) -> S?` pattern match over the new
  `Dispatch` enum. `methods` splits into `mutate` (pure state changes,
  `$name`) and `compute` (value reads, `$label`).
- `alter` splits into four typed render-time buckets matching the directive
  call conventions: `when : (S, key, value, iter) -> Bool`,
  `enrich : (S, binds, key, value, iter) -> Unit`,
  `enrich_scope : (S) -> Map[String, Value]`, and
  `loop_with : (S, seq, LoopCtx) -> LoopWith`.
- Child-component slots and Set/OMap kinds are declared via `specs=`
  (`FieldSpec::comp` / `::set` / `::omap`); fields of type `@tutuca.Value`
  (or collections of it) carry instances/functions losslessly through state
  updates via a core value stash (`with_value_stash` + `ToJson`/`FromJson`
  impls for `Value`).
- Core gains coercing accessors on `Value`: `int` / `num` / `str` / `bool` /
  `list` / `entries` / `field`.
- The inspector's component summary now reports the typed buckets (fields /
  methods / update flag / alter / views).

## [0.1.0]

Initial public release: a MoonBit port of the
[tutuca](https://github.com/marianoguerra/tutuca) UI framework.

- Value language (parse / tokenize / eval) and reactive path/dispatch system.
- `anode` template parser, `render` layer, `component`/`app`/`transactor`
  runtime.
- Virtual DOM (`vdom`) with in-memory, js (real DOM), and wasm-gc backends.
- `lint` (parse-issue rules + structural HTML linter) and `inspector`.
- Native `tutuca` CLI (`get` / `list` / `examples` / `show` / `lint` /
  `render` / `storybook` / `install-skill`).
- 32 ported examples, browser/CLI/wasm demos, an in-browser playground, and a
  compiled storybook gallery.

[Unreleased]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/marianoguerra/tutuca-moonbit/releases/tag/v0.1.0
