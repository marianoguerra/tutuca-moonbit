// File-failure messages. Kept out of the error type itself (rather than an
// `impl Show`) so the wording is one readable table — the CLI prints these
// verbatim, so they are user-facing text, not debug output.

///|
/// The user-facing one-line message for a file failure.
pub fn FileError::message(self : FileError) -> String {
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
    DuplicateStateBlock =>
      "two <script type=\"tutuca/state\"> blocks — one file declares one schema, with one `state` per component"
    DuplicateScriptBlock("") =>
      "two unqualified <script type=\"tutuca/script\"> blocks — a block is written about ONE component, so name each one with `for=\"Comp\"`"
    DuplicateScriptBlock(comp) =>
      "two <script type=\"tutuca/script\" for=\"\{comp}\"> blocks — one component answers one set of handlers"
    DuplicateWaxBlock("") =>
      "two unqualified <script type=\"tutuca/wax\"> blocks — a block is written about ONE component, so name each one with `for=\"Comp\"`"
    DuplicateWaxBlock(comp) =>
      "two <script type=\"tutuca/wax\" for=\"\{comp}\"> blocks — one component's escapes are one body of source"
    BadStateBlock(line~, message~) | BadInitBlock(line~, message~) =>
      "line \{line}: \{message}"
  }
}
