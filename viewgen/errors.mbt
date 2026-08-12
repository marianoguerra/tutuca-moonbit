// Generation-failure messages. Kept out of the error type itself (rather
// than an `impl Show`) so the wording is one readable table — the CLI prints
// these verbatim, so they are user-facing text, not debug output.

///|
/// The user-facing one-line message for a generation failure.
pub fn GenError::message(self : GenError) -> String {
  match self {
    File(e) => e.message()
    ViewParseIssue(view~, issue~) => "view \"\{view}\": \{issue}"
    EmptyView(name) => "view \"\{name}\" is empty"
    NameCollision(variant~, first~, second~) =>
      "\"\{first}\" and \"\{second}\" both become the variant \{variant} — rename one"
    BadComponentName(name) =>
      "\"\{name}\" is not usable as a component name: expected a name starting with a letter and made of letters, digits and underscores"
    MethodInEventPosition(view~, name~, site~) =>
      "view \"\{view}\": `\{site}=\"$\{name}\"` — drop the `$`. In an event position a `$name` and a bare name are the SAME dispatch, so the sigil claims a distinction that is not there; `$` belongs in value positions (@text, @show, an attribute)"
    NoViewsToCompile =>
      "this file declares a schema and no <template>, so it has no views to compile"
    UnknownStateField(view~, name~, scope~, suggestion~) =>
      "view \"\{view}\": `.\{name}` is not a field of \{scope}" +
      (match suggestion {
        Some(s) => " — did you mean `.\{s}`?"
        None => "; declare it in the <script type=\"tutuca/state\"> block"
      })
    IdInLoop(view~, id~) =>
      "view \"\{view}\": `id=\"\{id}\"` sits inside an `@each`, so the loop stamps it on every item — use a class, or build the id per item with `:id=\"$'\{id}-{@key}'\"`"
    AlwaysTruthy(view~, directive~, expr~, ty~) =>
      "view \"\{view}\": `\{directive}=\"\{expr}\"` — \{ty} is always truthy, so this never hides anything; test `empty? \{expr}` or a field of it instead"
    NotIterable(view~, expr~, ty~) =>
      "view \"\{view}\": `@each` needs a collection, but `\{expr}` is \{ty}"
    NotRenderable(view~, expr~, ty~) =>
      "view \"\{view}\": `<x render>` needs a component, but `\{expr}` is \{ty}"
  }
}
