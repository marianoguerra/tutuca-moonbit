// Building and reading the shapes a SLOT can hold.
//
// The tree is general — a place is a root plus any number of steps, at any
// depth — and a view slot uses a handful of its shapes over and over: `.field`,
// `@bind`, `@bind.member`, `.seq[.key]`. Before the two ASTs became one those
// were four CASES, so a slot's parser wrote `Field("x")` and its readers
// matched `Field(name)`. They are now four shapes of `ERead`, and writing one
// out longhand at each of a couple of hundred sites would trade one kind of
// duplication for another.
//
// So: one constructor and one reader per shape, here. A reader answers `None`
// for a place that is merely deeper than the shape asks about — `.a.b` is not a
// field read, and a caller that only understands fields must see that rather
// than the first segment of it.
//
// Spans default to `no_span`, because the callers that build these are the ones
// with no source to point at: a generated IR module, a test, a macro expansion.
// A parser passes the span it read.

///|
/// `.name` — a read of one of this component's own fields.
pub fn Expr::field(name : String, span? : Span = no_span) -> Expr {
  ERead(place={ root: PState(name), steps: [], span, }, span~)
}

///|
/// The field this expression reads, when it reads exactly one.
pub fn Expr::as_field(self : Expr) -> String? {
  match self {
    ERead(place={ root: PState(name), steps: [], .. }, ..) => Some(name)
    _ => None
  }
}

///|
/// `@name` — a read of a render binding.
pub fn Expr::bind(name : String, span? : Span = no_span) -> Expr {
  ERead(place={ root: PBind(name), steps: [], span, }, span~)
}

///|
/// The binding this expression reads whole, when it reads one.
pub fn Expr::as_bind(self : Expr) -> String? {
  match self {
    ERead(place={ root: PBind(name), steps: [], .. }, ..) => Some(name)
    _ => None
  }
}

///|
/// `@name.member` — one level into a render binding.
pub fn Expr::bind_member(
  name : String,
  prop : String,
  span? : Span = no_span,
) -> Expr {
  ERead(place={ root: PBind(name), steps: [PField(prop)], span, }, span~)
}

///|
/// The `(binding, member)` this expression reads, when it reads one level into
/// a binding.
pub fn Expr::as_bind_member(self : Expr) -> (String, String)? {
  match self {
    ERead(place={ root: PBind(name), steps: [PField(prop)], .. }, ..) =>
      Some((name, prop))
    _ => None
  }
}

///|
/// `.seq[.key]` — an entry of one of this component's sequences, indexed by
/// another of its fields.
///
/// The one indexed shape a slot can spell: both halves are plain fields, which
/// is what makes it addressable as a `SeqAccessStep` without evaluating
/// anything.
pub fn Expr::seq_access(
  seq : String,
  key : String,
  span? : Span = no_span,
) -> Expr {
  ERead(
    place={ root: PState(seq), steps: [PIndex(Expr::field(key, span~))], span, },
    span~,
  )
}

///|
/// The `(sequence, key)` fields this expression reads, when it is a
/// field-indexed-by-field read.
pub fn Expr::as_seq_access(self : Expr) -> (String, String)? {
  match self {
    ERead(place={ root: PState(seq), steps: [PIndex(idx)], .. }, ..) =>
      match idx.as_field() {
        Some(key) => Some((seq, key))
        None => None
      }
    _ => None
  }
}

///|
/// A literal.
pub fn Expr::lit(
  lit : Lit,
  from_macro? : Bool = false,
  span? : Span = no_span,
) -> Expr {
  ELit(lit~, from_macro~, span~)
}

///|
/// The literal this expression is, when it is one.
pub fn Expr::as_lit(self : Expr) -> Lit? {
  match self {
    ELit(lit~, ..) => Some(lit)
    _ => None
  }
}

///|
/// `$name` — a declared `compute` or `pred`, answered by the render stack.
pub fn Expr::method_(name : String, span? : Span = no_span) -> Expr {
  EMethod(name~, span~)
}

///|
/// `*name` — a dynamic binding.
pub fn Expr::dyn_(name : String, span? : Span = no_span) -> Expr {
  EDyn(name~, span~)
}

///|
/// A bare name, in the position where it is a value rather than a handler.
pub fn Expr::name(name : String, span? : Span = no_span) -> Expr {
  EName(name~, span~)
}

///|
/// A bare Uppercase name — a component type.
pub fn Expr::type_name(name : String, span? : Span = no_span) -> Expr {
  ETypeName(name~, span~)
}

///|
/// A name applied to arguments.
pub fn Expr::app(
  name : String,
  args : Array[Expr],
  span? : Span = no_span,
) -> Expr {
  EApp(name~, args~, span~)
}

///|
/// `$'…'` — a string template.
pub fn Expr::tpl(parts : Array[TplPart], span? : Span = no_span) -> Expr {
  ETpl(parts~, span~)
}

///|
/// `e.value` — a rooted path into the DOM event being handled.
pub fn Expr::event_path(
  segments : Array[String],
  span? : Span = no_span,
) -> Expr {
  EEventPath(segments~, span~)
}
