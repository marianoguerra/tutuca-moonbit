// Canonical table of component-linter rule codes, ported verbatim from
// tools/core/lint-rules.js. `agent-context` emits it as JSON (lintCodes) and
// `tutuca help lint` prints it as a grouped table.
//
// GENERATED from `node tools/tutuca.js agent-context` output — regenerate
// with the script in the JS repo if the rule table changes.
//
// Enforcement lives in lint_component.mbt (check_component) plus the @lint
// package (parse-issue + structural HTML rules). A few codes are cataloged
// for JS parity but can never fire in the MoonBit port — the conditions
// they detect are statically impossible here (see the header comment in
// lint_component.mbt): ASYNC_HANDLER, FIELD_NAME_RESERVED_BY_RECORD,
// COMP_FIELD_BAD_SHAPE, UNKNOWN_COMPONENT_SPEC_KEY, LOOKUP_BAD_SHAPE,
// SUGGEST_BINDING_MEMBER.

///|
pub let lint_rules : Array[LintRule] = [
  {
    code: "FIELD_VAL_NOT_DEFINED",
    level: "error",
    group: "Field / method references",
    summary: "`.field` references a field not declared in `fields`.",
  },
  {
    code: "FIELD_VAL_IS_METHOD",
    level: "error",
    group: "Field / method references",
    summary: "`.name` reads a field, but `name` is a method — use `$name`.",
  },
  {
    code: "METHOD_VAL_NOT_DEFINED",
    level: "error",
    group: "Field / method references",
    summary: "`$method` references a method not declared in `methods`.",
  },
  {
    code: "METHOD_VAL_IS_FIELD",
    level: "error",
    group: "Field / method references",
    summary: "`$name` calls a method, but `name` is a field — use `.name`.",
  },
  {
    code: "INPUT_HANDLER_NOT_IMPLEMENTED",
    level: "error",
    group: "Input-handler / method confusion",
    summary: "Bare handler name has no entry in `input`.",
  },
  {
    code: "INPUT_HANDLER_METHOD_NOT_IMPLEMENTED",
    level: "error",
    group: "Input-handler / method confusion",
    summary: "`$handler` has no entry in `methods`.",
  },
  {
    code: "INPUT_HANDLER_FOR_INPUT_HANDLER_METHOD",
    level: "hint",
    group: "Input-handler / method confusion",
    summary: "`$name` is a method reference, but `name` is an input handler — drop the `$`.",
  },
  {
    code: "INPUT_HANDLER_METHOD_FOR_INPUT_HANDLER",
    level: "hint",
    group: "Input-handler / method confusion",
    summary: "Bare `name` is an input-handler reference, but `name` is a method — add `$`.",
  },
  {
    code: "INPUT_HANDLER_NOT_REFERENCED",
    level: "hint",
    group: "Input-handler / method confusion",
    summary: "`input` entry is defined but never wired to an `@on.*` event.",
  },
  {
    code: "ALT_HANDLER_NOT_DEFINED",
    level: "error",
    group: "Iteration helpers (`alter`)",
    summary: "`@when` / `@enrich-with` / `@loop-with` names a handler not in `alter`.",
  },
  {
    code: "ALT_HANDLER_NOT_REFERENCED",
    level: "hint",
    group: "Iteration helpers (`alter`)",
    summary: "`alter` entry is defined but never used.",
  },
  {
    code: "SUGGEST_BINDING_MEMBER",
    level: "hint",
    group: "Iteration helpers (`alter`)",
    summary: "`@enrich-with` handler only copies members of the loop value — read them directly as `@value.member` and drop the enrich.",
  },
  {
    code: "DYN_VAL_NOT_DEFINED",
    level: "error",
    group: "Dynamic bindings",
    summary: "`*name` references a binding not declared in `provide` or `lookup`.",
  },
  {
    code: "DYN_ALIAS_NOT_REFERENCED",
    level: "hint",
    group: "Dynamic bindings",
    summary: "`lookup` entry is defined but never read as `*name` in a view.",
  },
  {
    code: "PROVIDE_NOT_ADDRESSABLE",
    level: "error",
    group: "Dynamic bindings",
    summary: "`provide` value must be a field (`.f`) or seq-access (`.s[.k]`) path.",
  },
  {
    code: "LOOKUP_BAD_SHAPE",
    level: "error",
    group: "Dynamic bindings",
    summary: "`lookup` entry must be a string or `{ for, default }` (known keys, string values).",
  },
  {
    code: "LOOKUP_TARGET_MALFORMED",
    level: "error",
    group: "Dynamic bindings",
    summary: "`lookup` target must be `\"Producer.provideName\"` (string or `for`).",
  },
  {
    code: "RENDER_IT_OUTSIDE_OF_LOOP",
    level: "error",
    group: "Templates / events",
    summary: "`<x render-it>` used outside `@each` / `render-each`.",
  },
  {
    code: "UNKNOWN_EVENT_MODIFIER",
    level: "error",
    group: "Templates / events",
    summary: "`@on.<event>+<mod>` uses a modifier not in the recognized set.",
  },
  {
    code: "UNKNOWN_HANDLER_ARG_NAME",
    level: "error",
    group: "Templates / events",
    summary: "Handler argument name is not a built-in or a declared component.",
  },
  {
    code: "DUPLICATE_ATTR_DEFINITION",
    level: "error",
    group: "Templates / events",
    summary: "Same attribute set more than once (literal + `:attr` + `@if.attr`).",
  },
  {
    code: "IF_NO_BRANCH_SET",
    level: "error",
    group: "Templates / events",
    summary: "`@if.<attr>` has no `@then` or `@else` branch.",
  },
  {
    code: "UNKNOWN_DIRECTIVE",
    level: "error",
    group: "Templates / events",
    summary: "`@directive` name is not recognized (typo or unsupported).",
  },
  {
    code: "UNKNOWN_X_OP",
    level: "error",
    group: "Templates / events",
    summary: "First attribute on `<x>` (or pseudo-`@x`) is not a known op.",
  },
  {
    code: "UNKNOWN_X_ATTR",
    level: "error",
    group: "Templates / events",
    summary: "Extra attribute on `<x op>` not consumed by the op and not a known wrapper.",
  },
  {
    code: "X_OP_IGNORES_CHILDREN",
    level: "warn",
    group: "Templates / events",
    summary: "`<x text/render/render-it/render-each>` has child content the op silently drops.",
  },
  {
    code: "MAYBE_DROP_AT_PREFIX",
    level: "hint",
    group: "Templates / events",
    summary: "An `<x>` op/attr was written with a leading `@` like a directive.",
  },
  {
    code: "MAYBE_ADD_AT_PREFIX",
    level: "hint",
    group: "Templates / events",
    summary: "A directive name (`when`/`enrich-with`/`loop-with`/`show`/`hide`) was written as a plain attribute on a host element — add the `@` prefix.",
  },
  {
    code: "DEPRECATED_BARE_X_DIRECTIVE",
    level: "warn",
    group: "Templates / events",
    summary: "Bare `show`/`hide`/`when`/`loop-with` on an `<x>` op is deprecated — use the `@`-prefixed directive (`@show`/`@hide`/`@when`/`@loop-with`).",
  },
  {
    code: "BAD_VALUE",
    level: "error",
    group: "Value expressions",
    summary: "A value expression could not be parsed.",
  },
  {
    code: "UNSUPPORTED_EXPR_SYNTAX",
    level: "error",
    group: "Value expressions",
    summary: "Value uses JS-style syntax (ternary, comparison, logical, call-with-args, dotted field path) tutuca does not support — move the logic into a method.",
  },
  {
    code: "BINDING_MEMBER_TOO_DEEP",
    level: "error",
    group: "Value expressions",
    summary: "A binding member read goes more than one level deep (`@x.a.b`) — only one member is allowed.",
  },
  {
    code: "REDUNDANT_TEMPLATE_STRING",
    level: "warn",
    group: "Value expressions",
    summary: "`$'{expr}'` wraps a single expression — use the expression directly.",
  },
  {
    code: "PLACEHOLDERLESS_TEMPLATE_STRING",
    level: "hint",
    group: "Value expressions",
    summary: "`$'…'` template has no `{}` placeholder — use a plain string literal.",
  },
  {
    code: "CONSTANT_CONDITION",
    level: "warn",
    group: "Value expressions",
    summary: "A non-boolean literal in a boolean condition (`@show`, `@hide`, `@if`) never changes — reference a field or method instead.",
  },
  {
    code: "UNKNOWN_COMPONENT_NAME",
    level: "error",
    group: "Names registered with the app",
    summary: "A component type referenced in a template is not registered.",
  },
  {
    code: "UNKNOWN_MACRO_ARG",
    level: "error",
    group: "Names registered with the app",
    summary: "A macro call passes an attribute not declared in the macro's defaults.",
  },
  {
    code: "UNKNOWN_COMPONENT_SPEC_KEY",
    level: "warn",
    group: "Component spec",
    summary: "`component({...})` has an unrecognized key; its value is ignored at runtime.",
  },
  {
    code: "ASYNC_HANDLER",
    level: "error",
    group: "Handler effects",
    summary: "A handler in `input`/`receive`/`bubble`/`response`/`alter` is an async function — handlers must be synchronous; use a request handler, `ctx.send`, or `ctx.bubble` instead.",
  },
  {
    code: "TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE",
    level: "error",
    group: "Component styles",
    summary: "A top-level-only at-rule (`@import`, `@keyframes`, `@font-face`, …) appears in `style`/`commonStyle`, which is wrapped in a component-scoped selector where it is invalid and dropped — move it to `globalStyle`.",
  },
  {
    code: "GLOBAL_SELECTOR_IN_SCOPED_STYLE",
    level: "error",
    group: "Component styles",
    summary: "A rule whose leading selector is `html`/`body`/`:root` appears in `style`/`commonStyle`; once scoped it becomes a descendant selector that never matches — move it to `globalStyle`.",
  },
  {
    code: "COMP_FIELD_BAD_SHAPE",
    level: "error",
    group: "Component field declarations",
    summary: "`fields: { x: { component, args } }` shape is wrong: `component` must be a string and `args` must be a plain object.",
  },
  {
    code: "FIELD_NAME_RESERVED_BY_RECORD",
    level: "error",
    group: "Component field declarations",
    summary: "Field name matches an Immutable Record API member, so `.field` reads the API member instead of the value.",
  },
]
