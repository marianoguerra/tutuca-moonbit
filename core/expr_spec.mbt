// THE expression AST.
//
// One tree, where there were two. `core` held a span-free `Val` — what a view
// slot parses to, what a render frame replays, what the generated IR modules
// spell out — and `tscript` held an `Expr` with spans, positions and operators,
// which its parser lowered INTO a `Val` for anything a slot could hold. The
// lowering was the problem: two enums for one language means every question
// ("is this addressable", "may this go here") is answered twice and the answers
// drift, and it means the block language could never grow a form a slot might
// legitimately want without the slot half having somewhere to put it.
//
// So the tree is one, it lives here — `core` never parses anything, but it is
// what a parse produces and what `Step` embeds, and that embedding is why the
// value and path layers already share this package — and the question of which
// forms are legal WHERE is a separate answer, `Position` (`position.mbt`).
//
// SPANS RIDE ALONG AND DO NOT COUNT. Every node carries where it was read
// from, which is what lets a diagnostic point at the operand that was wrong
// rather than at the whole attribute. But a span is not part of what an
// expression IS: `Step::ScopeBindStep` embeds one of these and `Step` derives
// `Eq`, so a path rebuilt from a serialized frame has to compare equal to the
// one the renderer built, and it will not have the same offsets. `Eq` is
// therefore written by hand below, one arm per case, ignoring `span`
// throughout — and so is `Debug`, for the second half of the same reason: a
// snapshot of a tree is a comparison too, and one that moved because an
// attribute grew a character would be a test about nothing. `Expr::span()` is
// how you read a position when you want one.

///|
/// The four operator families. **Mixing families in one unparenthesized chain
/// is a parse error**, and the message names the parentheses to add — so
/// `a and b and c` and `a + b - c` chain freely, `a + b * c` is refused, and
/// there is no precedence to get wrong.
pub(all) enum OpFamily {
  /// `and` `or` — associative, chains freely.
  FLogic
  /// `is` `is not` `<` `<=` `>` `>=` — exactly TWO operands, so `a < b < c`
  /// is refused too.
  FCompare
  /// `implies` — `a implies b` is `(not a) or b`. Non-associative like
  /// comparison, so the right-associativity trap never arises. It is the shape
  /// most cross-field rules take.
  FImplies
  /// `+` `-`. `+` concatenates two strings and adds two numbers; the operands'
  /// static types decide and a mixed pair is a type error, not a coercion.
  FAdd
  /// `*` `/` `mod`
  FMul
} derive(Debug, Eq)

///|
pub(all) enum UnOp {
  UNot
  UNeg
} derive(Debug, Eq)

///|
/// One piece of a `$'…'` template: literal text, or an interpolated
/// expression.
///
/// There is no third case for a placeholder that failed to parse. The slot
/// parser used to keep one as a hole, which meant every reader of a template
/// had to decide what a hole means; a placeholder that does not parse is a
/// PARSE ISSUE, reported where issues are reported, and the part is dropped.
///
/// `from_macro` rides on the TEXT case and not only on `ELit`, because a
/// `^name` that resolved to a string is text in the template that contains it —
/// it prints as text and reads as text — and the one bit that still has to
/// survive is whose source it was. That bit is what decides whether the
/// enclosing template counts as a hand-written literal, and therefore whether
/// it may pin a URL origin (`dyncomp/policy/external_url.mbt`).
pub(all) enum TplPart {
  TText(text~ : String, from_macro~ : Bool)
  TExpr(Expr)
}

///|
/// What a place is rooted at.
pub(all) enum PlaceRoot {
  /// `.field` — a place in this component's state.
  PState(String)
  /// `@name` — a binding. Assignable in `enrich` / `enrich-scope` only;
  /// readable anywhere the slot provides it.
  PBind(String)
  /// `cur` — what a `new` in this body is building.
  ///
  /// Not a binding, which is what `@cur` used to call it: a binding is
  /// something an `enrich` produces and a view reads, and this is neither. It
  /// is the one position a body owns that is not state, alive from the `new`
  /// that opened it to the statement that hands it over.
  PTarget
  /// `name.field` — a path into a PARAMETER. Never assignable: an argument is
  /// a value the caller handed over, not a position this component owns.
  ///
  /// The root is a bare name and the steps are the same ones every other place
  /// takes, so the only thing that tells `f.name` from `f .name` is
  /// ATTACHMENT — which is the rule already in force for `min .a .b` versus
  /// `min .a.b` (`pre_space` in script_lex.mbt). No new ambiguity: a bare name
  /// followed by an attached `.` or `[` could not mean anything else, since a
  /// parameter is the one kind of name that can never be applied.
  PParam(String)
} derive(Debug, Eq)

///|
/// The name `new` writes and the statements under it read: `cur`.
///
/// Reserved, and named once rather than spelled in five packages, because the
/// checker refuses to let an `enrich` bind it, the interpreter refuses to let
/// it escape into a view, and both are talking about the same name.
pub let target_bind : String = "cur"

///|
/// A step below the root.
pub(all) enum PathStep {
  /// `.field`
  PField(String)
  /// `[expr]`
  PIndex(Expr)
}

///|
/// A PLACE: a position, not a value.
///
/// `.a.b` and `.a[k].b` are the two things a view slot cannot spell — nested
/// reads and nested WRITES. A slot's name lookup stays one level because
/// nothing checks it; a body is checked code and the generator knows every
/// type along the path.
pub(all) struct Place {
  root : PlaceRoot
  steps : Array[PathStep]
  span : Span
}

///|
/// An expression.
///
/// `Val` is the same type under its older name — a slot's value and a block's
/// expression are one language, and the alias is what keeps the ~1500 places
/// that say `Val` reading as they did.
#alias(Val)
pub(all) enum Expr {
  /// A literal. `from_macro` is set when a `^name` macro var resolved to this
  /// constant, which makes an enclosing template non-literal — and is the one
  /// bit that decides whether a constant may pin a URL origin
  /// (`dyncomp/policy/external_url.mbt`).
  ELit(lit~ : Lit, from_macro~ : Bool, span~ : Span)
  /// `$'text {expr} more'` — alternating literal text and interpolations.
  ETpl(parts~ : Array[TplPart], span~ : Span)
  /// Reading what is AT a place. `.field`, `@bind.member`, `.rows[.key]`,
  /// `param.name` — every read of a position, at any depth.
  ERead(place~ : Place, span~ : Span)
  /// `$name` — a `compute` result. Its TYPE is opaque to the checker
  /// ("unknown is not wrong", so nothing under it is judged), and written
  /// inside a BODY it is additionally REPORTED: this sigil is answered by the
  /// render stack, a body runs after one, so it reads Null. A body calls a
  /// `compute` or a `pred` bare — `EName` with no arguments.
  EMethod(name~ : String, span~ : Span)
  /// `*name` — a dynamic binding. Opaque for the same reason, and reported in
  /// a body for the same reason, with no bare spelling to fall back on.
  EDyn(name~ : String, span~ : Span)
  /// `^name` — a macro argument, substituted from the frame the CALLER opened.
  ///
  /// The grammar carries it because a conditional slot and a block body are
  /// one language, and a slot DOES stand in a macro frame. A block does not:
  /// `parse_script(source)` takes no context at all, so `^title` there would
  /// resolve to nothing — `tscript/check` refuses it by name rather than
  /// letting it read Null.
  EMacroVar(name~ : String, span~ : Span)
  /// `$$name` — a value the HOST bound, substituted as a literal and not
  /// re-parsed. The mirror of `EMacroVar`, and the MARKING is the whole
  /// difference between them: a `^name` constant is the caller's source and
  /// carries `from_macro`, a `$$name` constant is the host's and does not.
  EConfigVar(name~ : String, span~ : Span)
  /// A bare name. In a declaration body it is a parameter; in a handler slot
  /// it is an event argument, resolved against the closed table in
  /// `render/dom_event.mbt`; in a HANDLER position it is the name of the
  /// thing to run. Never a value in a value slot.
  ///
  /// One case, where there were two. The second carried a NAMESPACE — the
  /// dispatch side or the render side — and the dispatch side never resolved
  /// anything: an `@on` name is dispatched BY NAME and never evaluated. What
  /// the namespace really said was which POSITION the name was written in,
  /// which is `Position`'s question and is asked where the name is read
  /// (`Val::eval_as_handler`) rather than carried on it.
  EName(name~ : String, span~ : Span)
  /// A bare Uppercase name — a component TYPE (`@tutuca.is_type_name`).
  ETypeName(name~ : String, span~ : Span)
  /// A name applied to arguments — `len .items`, `clamp .page 0 (.n - 1)`,
  /// `unfinished @value`. Juxtaposition is unambiguous because every callable
  /// has a known fixed arity and the vocabulary is closed.
  EApp(name~ : String, args~ : Array[Expr], span~ : Span)
  /// Two or more operands joined by operators of ONE family.
  EChain(
    family~ : OpFamily,
    ops~ : Array[String],
    operands~ : Array[Expr],
    span~ : Span
  )
  EUnary(op~ : UnOp, operand~ : Expr, span~ : Span)
  /// `if c { a } else { b }` in a value position. Both arms are required:
  /// an expression has to have a value.
  EIf(cond~ : Expr, then_~ : Expr, else_~ : Expr, span~ : Span)
  /// `&.rows[k]` — a reference to a POSITION, legal in exactly one place: the
  /// first argument of `sendAt`.
  ///
  /// `&.rows[k]` denotes the position; `.rows[k]` denotes what is there. That
  /// distinction is the point — a position survives the root being rebuilt,
  /// which is what makes an async response land on the row that asked for it.
  ERef(place~ : Place, span~ : Span)
  /// `e.value`, `e.target.dataset.rowId` — a rooted path into the DOM event
  /// that is being handled. The segments, without the `e`.
  ///
  /// The one form in this enum that names something OUTSIDE the value
  /// language: every other case reads state, a binding or a literal, and this
  /// one reads the event. That is why it is spelled with a root — `e` is a
  /// NAMESPACE and never a value, so there is no expression that means "the
  /// event" and nothing can accidentally pass one along.
  ///
  /// What a path may traverse under the SAFE profile is `@eventpath`'s
  /// question, and what its leaf converts to is the DOM property table's.
  /// Neither is asked here: this is the parsed FORM, and a form that carried
  /// its own permission check would be a second place for the rule to live.
  EEventPath(segments~ : Array[String], span~ : Span)
}

///|
/// Where this expression was read from.
pub fn Expr::span(self : Expr) -> Span {
  match self {
    ELit(span~, ..)
    | ETpl(span~, ..)
    | ERead(span~, ..)
    | EMethod(span~, ..)
    | EDyn(span~, ..)
    | EMacroVar(span~, ..)
    | EConfigVar(span~, ..)
    | EName(span~, ..)
    | ETypeName(span~, ..)
    | EApp(span~, ..)
    | EChain(span~, ..)
    | EUnary(span~, ..)
    | EIf(span~, ..)
    | ERef(span~, ..)
    | EEventPath(span~, ..) => span
  }
}

///|
/// Structural equality, IGNORING spans.
///
/// Written out rather than derived because of what it is for: a `Step` embeds
/// an expression and a path is compared for equality all over the dispatch
/// layer, so a frame rebuilt from a serialized path has to equal the one the
/// renderer built. It will not carry the same offsets — it may carry no
/// offsets at all. See this file's header.
pub impl Eq for Expr with fn equal(self, other) {
  match (self, other) {
    (ELit(lit~, from_macro~, ..), ELit(lit=l2, from_macro=f2, ..)) =>
      lit == l2 && from_macro == f2
    (ETpl(parts~, ..), ETpl(parts=p2, ..)) => parts == p2
    (ERead(place~, ..), ERead(place=p2, ..)) => place == p2
    (EMethod(name~, ..), EMethod(name=n2, ..)) => name == n2
    (EDyn(name~, ..), EDyn(name=n2, ..)) => name == n2
    (EMacroVar(name~, ..), EMacroVar(name=n2, ..)) => name == n2
    (EConfigVar(name~, ..), EConfigVar(name=n2, ..)) => name == n2
    (EName(name~, ..), EName(name=n2, ..)) => name == n2
    (ETypeName(name~, ..), ETypeName(name=n2, ..)) => name == n2
    (EApp(name~, args~, ..), EApp(name=n2, args=a2, ..)) =>
      name == n2 && args == a2
    (
      EChain(family~, ops~, operands~, ..),
      EChain(family=f2, ops=o2, operands=d2, ..),
    ) => family == f2 && ops == o2 && operands == d2
    (EUnary(op~, operand~, ..), EUnary(op=o2, operand=d2, ..)) =>
      op == o2 && operand == d2
    (EIf(cond~, then_~, else_~, ..), EIf(cond=c2, then_=t2, else_=e2, ..)) =>
      cond == c2 && then_ == t2 && else_ == e2
    (ERef(place~, ..), ERef(place=p2, ..)) => place == p2
    (EEventPath(segments~, ..), EEventPath(segments=s2, ..)) => segments == s2
    _ => false
  }
}

///|
/// Places compare by root and steps; the span is not part of the position.
pub impl Eq for Place with fn equal(self, other) {
  self.root == other.root && self.steps == other.steps
}

///|
pub impl Eq for PathStep with fn equal(self, other) {
  match (self, other) {
    (PField(a), PField(b)) => a == b
    (PIndex(a), PIndex(b)) => a == b
    _ => false
  }
}

///|
pub impl Eq for TplPart with fn equal(self, other) {
  match (self, other) {
    (TText(text~, from_macro~), TText(text=t2, from_macro=f2)) =>
      text == t2 && from_macro == f2
    (TExpr(a), TExpr(b)) => a == b
    _ => false
  }
}

///|
/// Debug, SPAN-FREE. See this file's header: a debug dump of a tree is
/// compared, and a position is not part of what the tree is.
pub impl Debug for Expr with fn to_repr(self) {
  match self {
    ELit(lit~, from_macro~, ..) =>
      Repr::ctor("ELit", [
        (Some("lit"), Repr(lit)),
        (Some("from_macro"), Repr(from_macro)),
      ])
    ETpl(parts~, ..) => Repr::ctor("ETpl", [(Some("parts"), Repr(parts))])
    ERead(place~, ..) => Repr::ctor("ERead", [(Some("place"), Repr(place))])
    EMethod(name~, ..) => Repr::ctor("EMethod", [(Some("name"), Repr(name))])
    EDyn(name~, ..) => Repr::ctor("EDyn", [(Some("name"), Repr(name))])
    EMacroVar(name~, ..) =>
      Repr::ctor("EMacroVar", [(Some("name"), Repr(name))])
    EConfigVar(name~, ..) =>
      Repr::ctor("EConfigVar", [(Some("name"), Repr(name))])
    EName(name~, ..) => Repr::ctor("EName", [(Some("name"), Repr(name))])
    ETypeName(name~, ..) =>
      Repr::ctor("ETypeName", [(Some("name"), Repr(name))])
    EApp(name~, args~, ..) =>
      Repr::ctor("EApp", [
        (Some("name"), Repr(name)),
        (Some("args"), Repr(args)),
      ])
    EChain(family~, ops~, operands~, ..) =>
      Repr::ctor("EChain", [
        (Some("family"), Repr(family)),
        (Some("ops"), Repr(ops)),
        (Some("operands"), Repr(operands)),
      ])
    EUnary(op~, operand~, ..) =>
      Repr::ctor("EUnary", [
        (Some("op"), Repr(op)),
        (Some("operand"), Repr(operand)),
      ])
    EIf(cond~, then_~, else_~, ..) =>
      Repr::ctor("EIf", [
        (Some("cond"), Repr(cond)),
        (Some("then_"), Repr(then_)),
        (Some("else_"), Repr(else_)),
      ])
    ERef(place~, ..) => Repr::ctor("ERef", [(Some("place"), Repr(place))])
    EEventPath(segments~, ..) =>
      Repr::ctor("EEventPath", [(Some("segments"), Repr(segments))])
  }
}

///|
pub impl Debug for Place with fn to_repr(self) {
  Repr::record({ "root": Repr(self.root), "steps": Repr(self.steps) })
}

///|
pub impl Debug for PathStep with fn to_repr(self) {
  match self {
    PField(name) => Repr::ctor("PField", [(None, Repr(name))])
    PIndex(e) => Repr::ctor("PIndex", [(None, Repr(e))])
  }
}

///|
pub impl Debug for TplPart with fn to_repr(self) {
  match self {
    TText(text~, from_macro~) =>
      Repr::ctor("TyText", [
        (Some("text"), Repr(text)),
        (Some("from_macro"), Repr(from_macro)),
      ])
    TExpr(e) => Repr::ctor("TExpr", [(None, Repr(e))])
  }
}
