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
    BareEventArg(view~, name~, site~) =>
      "view \"\{view}\": `\{site}=\"… \{name}\"` — an argument needs a sigil saying where it reads from. Write `e.\{name}` for the event, `.\{name}` for state, or `@\{name}` for a binding"
    NoViewsToCompile =>
      "this file declares a schema and no <template>, so it has no views to compile"
    UnknownStateField(view~, name~, scope~, suggestion~) =>
      "view \"\{view}\": `.\{name}` is not a field of \{scope}" +
      (match suggestion {
        Some(s) => " — did you mean `.\{s}`?"
        None => "; declare it in the <script type=\"tutuca/state\"> block"
      })
    InvalidBind(view~, reason~) => "view \"\{view}\": `@bind` \{reason}"
    PayloadDisagrees(name~, declared~, written~, sites~) =>
      "`\{name}` is declared in the state block as `\{declared}` and called from \{sites} as `\{written}` — the schema declares what a message carries, so the call sites have to match it"
    IdInLoop(view~, id~) =>
      "view \"\{view}\": `id=\"\{id}\"` sits inside an `@each`, so the loop stamps it on every item — use a class, or build the id per item with `:id=\"$'\{id}-{@key}'\"`"
    AlwaysTruthy(view~, directive~, expr~, ty~) =>
      "view \"\{view}\": `\{directive}=\"\{expr}\"` — \{ty} is always truthy, so this never hides anything; test `empty? \{expr}` or a field of it instead"
    NotIterable(view~, expr~, ty~) =>
      "view \"\{view}\": `@each` needs a collection, but `\{expr}` is \{ty}"
    NotRenderable(view~, expr~, ty~) =>
      "view \"\{view}\": `<x render>` needs a component, but `\{expr}` is \{ty}"
    BadScriptBlock(comp~, line~, message~) =>
      "line \{line}: script block for \{comp}: \{message}"
  }
}

///|
/// The stable machine-readable name for a generation failure.
///
/// `message` is what the CLI prints and the whole of what it needs. A CARD
/// reports its findings as a LIST an editor renders beside the source, and
/// every other entry in that list carries a code (`NO_VIEW_HANDLER`, `ARITY`,
/// …) — so a view finding needs one too, or the card's face would have a
/// column that is filled in for half its rows.
///
/// One table here rather than one per face, for the same reason `message` is
/// one table: two copies of a list is how two lists drift apart.
pub fn GenError::code(self : GenError) -> String {
  match self {
    File(_) => "FILE"
    ViewParseIssue(..) => "VIEW_PARSE"
    EmptyView(_) => "EMPTY_VIEW"
    NameCollision(..) => "NAME_COLLISION"
    BadComponentName(_) => "BAD_COMPONENT_NAME"
    NoViewsToCompile => "NO_VIEWS"
    MethodInEventPosition(..) => "METHOD_IN_EVENT"
    BareEventArg(..) => "BARE_EVENT_ARG"
    UnknownStateField(..) => "UNKNOWN_STATE_FIELD"
    InvalidBind(..) => "INVALID_BIND"
    IdInLoop(..) => "ID_IN_LOOP"
    PayloadDisagrees(..) => "PAYLOAD_DISAGREES"
    AlwaysTruthy(..) => "ALWAYS_TRUTHY"
    NotIterable(..) => "NOT_ITERABLE"
    NotRenderable(..) => "NOT_RENDERABLE"
    BadScriptBlock(..) => "BAD_SCRIPT_BLOCK"
  }
}

///|
/// The view a finding is about, for the callers that can point at one.
///
/// Every message below already NAMES its view, which is enough for a line in a
/// build log and not enough for an editor: a card's face has to turn a finding
/// into a position in the file the author has open, and the template is the
/// finest position there is — the checker walks a COMPILED tree, whose nodes
/// carry no offsets. `None` is for the failures that are about the file rather
/// than about one of its views.
pub fn GenError::view(self : GenError) -> String? {
  match self {
    ViewParseIssue(view~, ..)
    | MethodInEventPosition(view~, ..)
    | BareEventArg(view~, ..)
    | UnknownStateField(view~, ..)
    | InvalidBind(view~, ..)
    | IdInLoop(view~, ..)
    | AlwaysTruthy(view~, ..)
    | NotIterable(view~, ..)
    | NotRenderable(view~, ..) => Some(view)
    EmptyView(name) => Some(name)
    _ => None
  }
}
