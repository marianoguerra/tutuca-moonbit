// Generation-failure messages. Kept out of the error type itself (rather
// than an `impl Show`) so the wording is one readable table — the CLI prints
// these verbatim, so they are user-facing text, not debug output.

///|
/// The user-facing one-line message for a generation failure.
pub fn GenError::message(self : GenError) -> String {
  match self {
    StrayText(msg) => msg
    DuplicateView(name) => "two views are both named \"\{name}\""
    DuplicateMacro(name) => "two macros are both named \"\{name}\""
    BadMacroName(id) => "\"\{id}\" needs a name after `macro:`"
    MixedViewIds =>
      "this file mixes `Component:view` ids with bare ones — name every component, or none of them"
    NoMainViewFor(what) =>
      "\{what} declares no main view: add a `main` view (id=\"Comp\" or id=\"Comp:main\")"
    UnclosedTemplate(what) => "unclosed <template\{what}>"
    ViewParseIssue(view~, issue~) => "view \"\{view}\": \{issue}"
    EmptyView(name) => "view \"\{name}\" is empty"
    NameCollision(variant~, first~, second~) =>
      "\"\{first}\" and \"\{second}\" both become the variant \{variant} — rename one"
    BadComponentName(name) =>
      "\"\{name}\" is not usable as a component name: expected a name starting with a letter and made of letters, digits and underscores"
    BadStateBlock(line~, message~) | BadInitBlock(line~, message~) =>
      "line \{line}: \{message}"
    MethodInEventPosition(view~, name~, site~) =>
      "view \"\{view}\": `\{site}=\"$\{name}\"` — drop the `$`. In an event position a `$name` and a bare name are the SAME dispatch, so the sigil claims a distinction that is not there; `$` belongs in value positions (@text, @show, an attribute)"
    NoViewsToCompile =>
      "this file declares a schema and no <template>, so it has no views to compile"
    DuplicateStateBlock =>
      "two <script type=\"tutuca/state\"> blocks — one file declares one schema, with one interface per component"
    UnknownStateField(view~, name~, scope~, suggestion~) =>
      "view \"\{view}\": `.\{name}` is not a field of \{scope}" +
      (match suggestion {
        Some(s) => " — did you mean `.\{s}`?"
        None => "; declare it in the <script type=\"tutuca/state\"> block"
      })
    NotIterable(view~, expr~, ty~) =>
      "view \"\{view}\": `@each` needs a collection, but `\{expr}` is \{ty}"
    NotRenderable(view~, expr~, ty~) =>
      "view \"\{view}\": `<x render>` needs a component, but `\{expr}` is \{ty}"
  }
}
