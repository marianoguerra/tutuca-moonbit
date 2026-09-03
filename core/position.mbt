// Which forms are legal WHERE.
//
// The policy used to be in two halves that never met. A `kind_of` / `in_group`
// table said which of ten flat shapes each parsing context admitted; a
// `lower_expr` in the same file said, with a sentence each, which of the
// expression grammar's forms a slot cannot hold at all. The first answered
// single tokens, the second answered everything longer, and the two disagreed
// about the same input often enough that "which path did this take" was a
// question a reader had to ask.
//
// One question now, asked of the expression itself: may this form stand HERE.
// It lives beside the AST rather than in the parser because it is a fact about
// the language and not about reading it — the generator asks it, a checker
// could, and a second front end would otherwise invent its own answer.
//
// The sentences are the contract. `tscript/parse_test.mbt` snapshots them, and
// a diff there is a bug rather than a rewording: the refusal is what an author
// reads, and it names what to write instead.

///|
/// A position an expression can be written in.
///
/// One case per slot the view language has, plus the block body. They are not
/// a hierarchy and they are not orderable: `@each` admits a dynamic and a
/// field and nothing else, an `@on` argument admits an event read that no
/// other position may hold, and `provide` admits exactly the two shapes that
/// can be ADDRESSED because a provide doubles as a resume target.
pub(all) enum Position {
  /// A condition: `@show`, `@hide`, `@when`, `@if.<attr>`, a `pred` body.
  PosCondition
  /// Text: `@text`, an interpolated attribute value.
  PosText
  /// A render target: `<x render="…">`.
  PosComponent
  /// An iteration source: `@each`, `<x render-each>`.
  PosSequence
  /// A `provide` expression. Read as `*name` AND resumed at, so it must be
  /// addressable — a field or a seq access, nothing else.
  PosProvide
  /// A field-shaped slot: a `lookup` default, a bind target.
  PosField
  /// An argument of an `@on` handler. The one position an `e.<path>` may
  /// stand in.
  PosEventArg
  /// The HANDLER of an `@on`: the name of the thing a raised event runs.
  PosEvent
  /// The handler of a render-time directive — `@when`, `@enrich-with`,
  /// `@loop-with`. A name here is answered by the render stack rather than
  /// dispatched, which is the whole of what the retired `HandlerNamespace`
  /// said.
  PosTrigger
  /// A macro attribute: whatever a slot can hold, because the callee's own
  /// position decides what it means.
  PosMacroAttr
  /// A declaration body. The whole grammar — this is the position the
  /// expression language was written for.
  PosBody
} derive(Debug, Eq)

///|
/// What a position answers about a form.
///
/// Three answers rather than two, because "no" comes in two kinds and they are
/// reported differently. A form that is simply not in this position's set is
/// `NotHere`: the caller says its own bad-value sentence, naming the slot. A
/// form the slot LANGUAGE cannot hold at any depth — a nested place, an `if`,
/// a `&position` — is `Refused`, and carries the sentence that names what to
/// write instead, because that one is about the expression rather than about
/// where it was put.
pub(all) enum Admission {
  Admitted
  NotHere
  Refused(String)
} derive(Debug, Eq)

///|
/// The ten flat shapes a slot's admission table is written over.
priv enum Kind {
  KConst
  KStrTpl
  KField
  KBind
  KDyn
  KName
  /// A bare Uppercase name: a component TYPE.
  ///
  /// In NO group, which is the point. A type is not a value — it has no path,
  /// nothing can be read off it, and it cannot be rendered — so it belongs to
  /// no value position and a `@on.click="addItem JsonSelector"` is a parse
  /// error rather than an argument that silently arrives as null. A handler
  /// that needs one asks for it by name (`ctx.make`), with the name declared
  /// in `lookup` where a checker can still see it and the scope it resolves
  /// against.
  ///
  /// The kind stays so that such a token still PARSES far enough to be
  /// reported as what it is.
  KType
  KSeq
  KMethod
  /// A name applied to arguments. Admitted in the CONDITION group only: a
  /// condition slot asks a yes/no question, which is what an application
  /// answers, and a value slot spells a call with `$`. Widening it further is
  /// what the expression language does, not this table.
  KApp
  /// `e.<path>` — a read of the event being handled.
  ///
  /// Admitted in the EVENT ARGUMENT group and nowhere else, which is the whole
  /// of what makes it safe to have. A `@text="e.value"` would be a render-time
  /// read of an event that is not happening, and this table is where that is
  /// refused rather than in a special case somewhere.
  KEvent
}

///|
/// The flat shape of an expression, for the admission table. `None` for a form
/// the table has no row for, which is a form no slot admits.
fn kind_of(val : Expr) -> Kind? {
  match val {
    ELit(..) => Some(KConst)
    // A placeholderless, non-macro template is a literal written the long
    // way and takes the single literal kind; a real placeholder makes it a
    // dynamic template confined to text/all contexts.
    ETpl(..) => if val.is_literal() { Some(KConst) } else { Some(KStrTpl) }
    ERead(place~, ..) =>
      match (place.root, place.steps) {
        (PState(_), []) => Some(KField)
        (PBind(_), []) | (PBind(_), [PField(_)]) => Some(KBind)
        (PState(_), [PIndex(_)]) =>
          if val.as_seq_access() is Some(_) {
            Some(KSeq)
          } else {
            None
          }
        _ => None
      }
    EMethod(..) => Some(KMethod)
    EDyn(..) => Some(KDyn)
    ETypeName(..) => Some(KType)
    EName(..) => Some(KName)
    EApp(..) | EChain(..) | EUnary(..) => Some(KApp)
    EEventPath(..) => Some(KEvent)
    EIf(..) | ERef(..) | EMacroVar(..) | EConfigVar(..) => None
  }
}

///|
fn in_position(kind : Kind, pos : Position) -> Bool {
  match pos {
    PosCondition => kind is (KField | KMethod | KBind | KDyn | KConst | KApp)
    PosText => kind is (KField | KMethod | KBind | KDyn | KConst | KStrTpl)
    // `$m` is in every value-read group but never in a path-bearing one: a
    // method result has no addressable path.
    PosComponent => kind is (KField | KSeq | KDyn)
    PosSequence => kind is (KField | KDyn)
    PosProvide => kind is (KField | KSeq)
    PosField => kind is (KField | KMethod | KConst | KSeq)
    PosEventArg =>
      kind is (KField | KMethod | KBind | KDyn | KName | KConst | KEvent)
    // A handler position holds a NAME. `$name` is admitted by the grammar
    // and refused separately in an `@on` — the sigil claims a distinction the
    // dispatch does not have (`@anode.NodeEvent::method_in_event`) — while a
    // trigger genuinely may be either.
    PosEvent | PosTrigger => kind is (KName | KMethod)
    PosMacroAttr =>
      kind
      is (KField | KMethod | KBind | KDyn | KName | KConst | KStrTpl | KSeq)
    // The body is the position the grammar was written for.
    PosBody => true
  }
}

///|
/// Why the slot language cannot hold this place, when it cannot.
///
/// A slot reads ONE level. `.a.b` and `.a[k].b` are the two things it cannot
/// spell — nested reads and nested writes — because a slot's name lookup is
/// unchecked, while a body is checked code where the generator knows every
/// type along the path.
fn place_refusal(place : Place) -> String? {
  match (place.root, place.steps) {
    (PState(_), []) | (PBind(_), []) | (PBind(_), [PField(_)]) => None
    (PBind(_), [PIndex(_)]) =>
      Some("a slot reads a binding's member by name, not by index")
    (PBind(b), _) => Some("a slot reads one member of `@\{b}`, not a path")
    // A slot never has one: `new` is a statement, and a slot holds one
    // expression with no statement to have opened a target.
    (PTarget, _) =>
      Some("`cur` is what a `new` builds into, and a slot has no `new`")
    // `.seq[.key]` is the one indexed read a slot has, and only with a plain
    // field for the key.
    (PState(seq), [PIndex(idx)]) =>
      if idx.as_field() is Some(_) {
        None
      } else {
        Some("a slot indexes by a plain field — write `.\{seq}[.key]`")
      }
    (PState(seq), [PField(m), ..]) =>
      Some(
        "a slot reads one level, so `.\{seq}.\{m}` has nothing to look in — render the child as a component, or name the read with a `compute`",
      )
    (PState(f), _) =>
      Some(
        "a slot reads one level, so `.\{f}` cannot be walked into — render the child as a component, or name the read with a `compute`",
      )
    (PParam(n), _) => Some("`\{n}` is a parameter, and a slot has none")
  }
}

///|
/// May this form stand in this position?
///
/// Total over the AST, and the same answer whether the caller reached the
/// expression through a single token or through the whole grammar — which is
/// the property the two-table version did not have.
pub fn Expr::admitted_in(self : Expr, pos : Position) -> Admission {
  // The body admits the grammar. Everything below is about SLOTS.
  if pos is PosBody {
    return Admitted
  }
  match self {
    ERead(place~, ..) | ERef(place~, ..) =>
      if place_refusal(place) is Some(why) {
        return Refused(why)
      }
    _ => ()
  }
  match self {
    ERef(..) => return Refused("`&` names a position, and a slot reads values")
    EIf(..) =>
      return Refused(
        "a slot has no `if` — `@show` / `@hide` ARE the choice, and a value that picks between two needs `@if.<attr>` with `@then` / `@else`",
      )
    EUnary(op=UNeg, ..) =>
      return Refused(
        "a slot has no arithmetic — name the value with a `compute`",
      )
    // The operator words ARE the builtin names, so a family the slot
    // vocabulary has no row for is named rather than silently evaluated to
    // nothing.
    EChain(ops~, ..) =>
      for op in ops {
        if builtin(op) is None {
          return Refused("`\{op}` is not a slot operator")
        }
      }
    // A placeholderless template is a literal written the long way, and takes
    // the literal's kind — so `@show="$'flex'"` is the constant it looks like.
    // One with a real placeholder is TEXT, and a condition is not text.
    ETpl(..) =>
      if pos is PosCondition && !self.is_literal() {
        return Refused("a template is text, and a condition is not text")
      }
    _ => ()
  }
  match kind_of(self) {
    Some(k) => if in_position(k, pos) { Admitted } else { NotHere }
    None => NotHere
  }
}
