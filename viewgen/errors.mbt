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
    NoMainView =>
      "no main view: give one <template> no id attribute, or id=\"main\""
    UnclosedTemplate(what) => "unclosed <template\{what}>"
    ViewParseIssue(view~, issue~) => "view \"\{view}\": \{issue}"
    EmptyView(name) => "view \"\{name}\" is empty"
    NameCollision(variant~, first~, second~) =>
      "\"\{first}\" and \"\{second}\" both become the variant \{variant} — rename one"
    BadComponentName(name) =>
      "\"\{name}\" is not usable as a component name: expected a name starting with a letter and made of letters, digits and underscores"
  }
}
