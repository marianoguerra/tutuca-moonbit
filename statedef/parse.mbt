// The state language's parser. Implements `parse_state`.
//
// Three declaration forms — `state`, `struct`, `enum` — plus the three message
// buckets, and that is the whole grammar.
//
// Two passes, because a field may name a type declared below it: collect every
// declaration, then resolve every type against the collection. That is the
// same shape any forward-referencing declaration language needs.

///|
/// The parser's cursor.
priv struct P {
  toks : Array[Token]
  mut at : Int
}

///|
fn P::peek(self : P) -> Tok {
  self.toks[self.at].tok
}

///|
fn P::span(self : P) -> Span {
  self.toks[self.at].span
}

///|
/// The token `n` places ahead, for the one decision that needs a second look:
/// `provide` opens a wiring section only when a brace follows it, and is an
/// ordinary field name otherwise.
fn P::peek_at(self : P, n : Int) -> Tok {
  let i = self.at + n
  if i < self.toks.length() {
    self.toks[i].tok
  } else {
    TEof
  }
}

///|
fn P::bump(self : P) -> Token {
  let t = self.toks[self.at]
  if self.at + 1 < self.toks.length() {
    self.at = self.at + 1
  }
  t
}

///|
fn[T] P::fail(self : P, want : String) -> T raise DefError {
  raise Syntax(
    msg="expected \{want}, found \{self.peek().describe()}",
    span=self.span(),
  )
}

///|
fn P::expect(self : P, t : Tok, want : String) -> Unit raise DefError {
  if self.peek() == t {
    self.bump() |> ignore
  } else {
    self.fail(want)
  }
}

///|
fn P::ident(self : P, want : String) -> (String, Span) raise DefError {
  match self.peek() {
    TIdent(n) => {
      let t = self.bump()
      (n, t.span)
    }
    _ => self.fail(want)
  }
}

///|
/// A trailing separator is optional everywhere, so a field list reads the same
/// whether an author writes MoonBit's commas or leaves them out.
fn P::skip_comma(self : P) -> Unit {
  if self.peek() is TComma {
    self.bump() |> ignore
  }
}

///|
/// Consecutive `///` lines are one comment.
fn P::docs(self : P) -> String? {
  let lines : Array[String] = []
  while self.peek() is TDoc(text) {
    lines.push(text)
    self.bump() |> ignore
  }
  if lines.is_empty() {
    None
  } else {
    Some(lines.join("\n"))
  }
}

///|
/// `#[a = 1, b = "x", c]`, or nothing.
fn P::attrs(self : P) -> Array[(String, AttrValue)] raise DefError {
  let out : Array[(String, AttrValue)] = []
  while self.peek() is THashBracket {
    self.bump() |> ignore
    if !(self.peek() is TRBracket) {
      for ;; {
        let (key, _) = self.ident("an attribute name")
        let value : AttrValue = if self.peek() is TEquals {
          self.bump() |> ignore
          match self.peek() {
            TNum(v) => {
              self.bump() |> ignore
              ANum(v)
            }
            TStr(v) => {
              self.bump() |> ignore
              AStr(v)
            }
            // A bare identifier reads as its own text: `#[format = email]`
            // and `#[format = "email"]` are the same, which is what an author
            // writes without thinking about it.
            TIdent(v) => {
              self.bump() |> ignore
              AStr(v)
            }
            _ => self.fail("an attribute value")
          }
        } else {
          AFlag
        }
        out.push((key, value))
        if self.peek() is TComma {
          self.bump() |> ignore
          continue
        }
        break
      }
    }
    self.expect(TRBracket, "`]` closing the attribute list")
  }
  out
}

// ---------------------------------------------------------------------------
// Declarations, collected before anything is resolved

///|
priv enum RawKind {
  RState
  RStruct
  REnum
  RProtocol(String)
  RProtocolImport(String)
  RSurface(String)
}

///|
priv struct RawDecl {
  kind : RawKind
  /// The component a `state` names, or the type name. "" for a bare `state`
  /// and for a bucket.
  name : String
  name_span : Span
  doc : String?
  /// Fields, for `state` and `struct`.
  fields : Array[RawField]
  /// Cases, for `enum` and the buckets.
  cases : Array[RawCase]
  handle_message : Array[RawCase]
  handle_intent : Array[RawCase]
  express_message : Array[RawCase]
  express_intent : Array[RawCase]
  properties : Array[RawField]
  views : Array[RawCase]
  implements : Array[(String, Span)]
  bindings : Array[RawBinding]
  /// The wiring sections, for `state`.
  provide : Array[ProvideDecl]
  lookup : Array[LookupDecl]
  /// The rule layer, for `state`.
  rules : Array[RuleDecl]
  /// The domain layer, for `state`.
  wheres : Array[WhereDecl]
}

///|
priv struct RawBinding {
  section : String
  protocol_name : String
  member_name : String
  source : String
  span : Span
}

///|
priv struct RawField {
  name : String
  span : Span
  doc : String?
  attrs : Array[(String, AttrValue)]
  ty : RawTy
}

///|
priv struct RawCase {
  name : String
  span : Span
  doc : String?
  payload : Array[RawTy]
}

///|
/// A type as written, before any name is resolved.
priv enum RawTy {
  /// `Name`, `Name[A, B]`
  RNamed(name~ : String, args~ : Array[RawTy], span~ : Span)
  /// `T?`
  ROpt(RawTy, Span)
  /// `(A, B)`
  RTuple(Array[RawTy], Span)
  /// `protocol P & Q` inside `Component[…]`.
  RProtocolSet(Array[(String, Span)], Span)
}

///|
fn RawTy::span(self : RawTy) -> Span {
  match self {
    RNamed(span~, ..) => span
    ROpt(_, s) => s
    RTuple(_, s) => s
    RProtocolSet(_, s) => s
  }
}

// ---------------------------------------------------------------------------
// Pass 1 — read the declarations

///|
fn parse_decls(p : P) -> Array[RawDecl] raise DefError {
  let out : Array[RawDecl] = []
  for ;; {
    let doc = p.docs()
    if p.peek() is TEof {
      break
    }
    let (word, word_span) = p.ident(
      "a declaration: state, struct, enum, protocol or import",
    )
    // `import protocol "id" as Alias` has no body. The declaration is still
    // collected beside protocols so the second pass resolves only ids.
    if word == "import" {
      let (protocol_word, ps) = p.ident("`protocol`")
      if protocol_word != "protocol" {
        raise Syntax(msg="only protocols are imported here", span=ps)
      }
      let id = match p.peek() {
        TStr(s) => {
          p.bump() |> ignore
          s
        }
        _ => p.fail("a canonical protocol string id")
      }
      let (as_word, as_span) = p.ident("`as` and a local protocol name")
      if as_word != "as" {
        raise Syntax(msg="expected `as`", span=as_span)
      }
      let (local_name, name_span) = p.ident("a local protocol name")
      out.push(empty_raw(RProtocolImport(id), local_name, name_span, doc))
      continue
    }
    let mut protocol_id = ""
    let kind : RawKind = match word {
      "state" => RState
      "struct" => RStruct
      "enum" => REnum
      "protocol" => RProtocol("")
      "handle" | "express" => RSurface(word)
      _ => raise UnknownDecl(got=word, span=word_span)
    }
    let (name, name_span) = match kind {
      RState | RSurface(_) =>
        if p.peek() is TIdent(_) {
          p.ident("the component's name")
        } else {
          ("", word_span)
        }
      _ =>
        p.ident(
          if kind is RProtocol(_) {
            "the protocol's local name"
          } else {
            "the type's name"
          },
        )
    }
    if kind is RProtocol(_) {
      p.expect(TEquals, "`=` before the canonical protocol id")
      protocol_id = match p.peek() {
        TStr(s) => {
          p.bump() |> ignore
          s
        }
        _ => p.fail("a canonical protocol string id")
      }
    }
    let actual_kind = if kind is RProtocol(_) {
      RProtocol(protocol_id)
    } else {
      kind
    }
    let implements : Array[(String, Span)] = []
    if actual_kind is RState && p.peek() is TIdent("implements") {
      p.bump() |> ignore
      for ;; {
        implements.push(p.ident("a protocol name"))
        if p.peek() is TComma {
          p.bump() |> ignore
          continue
        }
        break
      }
    }
    p.expect(TLBrace, "`{` opening the body")
    let fields : Array[RawField] = []
    let cases : Array[RawCase] = []
    let handle_message : Array[RawCase] = []
    let handle_intent : Array[RawCase] = []
    let express_message : Array[RawCase] = []
    let express_intent : Array[RawCase] = []
    let properties : Array[RawField] = []
    let views : Array[RawCase] = []
    let bindings : Array[RawBinding] = []
    let provide : Array[ProvideDecl] = []
    let lookup : Array[LookupDecl] = []
    let rules : Array[RuleDecl] = []
    let wheres : Array[WhereDecl] = []
    let takes_fields = actual_kind is (RState | RStruct)
    if actual_kind is RSurface(outer) {
      parse_channel_body(
        p,
        outer,
        if outer == "handle" {
          handle_message
        } else {
          express_message
        },
        if outer == "handle" {
          handle_intent
        } else {
          express_intent
        },
      )
      p.expect(TRBrace, "`}` closing the \{outer} declaration")
      out.push({
        kind: actual_kind,
        name,
        name_span,
        doc,
        fields,
        cases,
        handle_message,
        handle_intent,
        express_message,
        express_intent,
        properties,
        views,
        implements,
        bindings,
        provide,
        lookup,
        rules,
        wheres,
      })
      continue
    }
    while !(p.peek() is (TRBrace | TEof)) {
      // Docs first, because a section is documented the way a field is and the
      // comment sits between the brace and the word.
      let member_doc = p.docs()
      // A capability section, which only a `state` or a `protocol` may carry:
      // a `struct` describes a value, and a value answers no message.
      //
      // Guarded on the BRACE, the same way every other section here is. The
      // trigger is the word followed by `{`, which is what keeps `handle` and
      // `express` from being reserved field names: `handle : String` is still
      // a field, exactly as `view : String` and `provide : String` are. Adding
      // a section should never take a name away from an author, and this arm
      // was the one place that did.
      if p.peek() is TIdent(w) &&
        (w == "handle" || w == "express") &&
        p.peek_at(1) is TLBrace {
        p.bump() |> ignore
        if !(actual_kind is (RState | RProtocol(_))) {
          raise Syntax(
            msg="`\{w}` is a component or protocol capability section",
            span=p.span(),
          )
        }
        parse_channels(
          p,
          w,
          if w == "handle" {
            handle_message
          } else {
            express_message
          },
          if w == "handle" {
            handle_intent
          } else {
            express_intent
          },
        )
        continue
      }
      if p.peek() is TIdent(w) &&
        (w == "provide" || w == "lookup" || w == "property" || w == "view") &&
        p.peek_at(1) is TLBrace {
        let word_at = p.span()
        p.bump() |> ignore
        if actual_kind is RProtocol(_) {
          parse_protocol_members(p, w, properties, views)
        } else if actual_kind is RState {
          if w == "provide" || w == "lookup" {
            parse_state_wiring(p, w, provide, lookup, bindings)
          } else {
            parse_bindings(p, w, bindings)
          }
        } else {
          raise Syntax(
            msg="`\{w}` is only valid in a state or protocol",
            span=word_at,
          )
        }
        continue
      }
      // A `where`: `where FIELD <relation>`. Armed on THREE tokens, the way a
      // rule is, and for the same reason — the word must not be taken away
      // from an author. `where : String` is still a field (the second token is
      // `:`), and a case named `where` is still a case (a `where` is only read
      // in a `state`, and two bare identifiers side by side never occur in a
      // state body).
      //
      // The third token is what the relation opens with, so a state that
      // happens to declare fields called `where` and `is` still parses: the
      // arm needs `is`/`len`/`between` or an ordering, and a field is followed
      // by `:`.
      if actual_kind is RState &&
        p.peek() is TIdent("where") &&
        p.peek_at(1) is TIdent(_) &&
        p.peek_at(2)
        is (TIdent("is" | "len" | "between") | TGte | TGt | TLte | TLt) {
        let kw_at = p.span()
        p.bump() |> ignore
        let (subject, subject_span) = p.ident("the field the `where` is about")
        let ref_spans : Array[(String, Span)] = []
        let relation = parse_relation(p, subject, ref_spans)
        wheres.push({
          subject,
          subject_span,
          relation,
          ref_spans,
          doc: member_doc,
          span: { start: kw_at.start, end_: p.span().start, },
        })
        p.skip_comma()
        continue
      }
      // The same shape outside a `state`. Caught HERE rather than falling
      // through to the field parser, which would ask for a `:` after `where`
      // and tell an author about a colon when the problem is the block.
      if p.peek() is TIdent("where") &&
        p.peek_at(1) is TIdent(_) &&
        p.peek_at(2)
        is (TIdent("is" | "len" | "between") | TGte | TGt | TLte | TLt) {
        raise WhereOutsideState(span=p.span())
      }
      // A rule: `pred NAME [format <sentence>] { <expression> }`. The lexer
      // has already found where the sentence and the body END — both are the
      // block language and neither means anything here — so what is left is
      // the shape.
      //
      // Recognised on the WORD plus a NAME, which is why `pred : Bool` is
      // still a field and a case called `pred` is still a case: the lexer arms
      // on a shape rather than reserving a word.
      // A rule with PARAMETERS, which the spec block cannot express and should
      // not: a rule here is a fact about the component's state, and one that
      // needs an argument is about the particular call that supplied it. That
      // is the same line `CONTRACT_ARGS` already draws for a contract clause,
      // and the same reason a `@when` filter over `@value` stays where the
      // render-time things are.
      //
      // Caught by SHAPE, before the field parser sees `containsText` and asks
      // for a `:`, which is a puzzling thing to be told about a `pred`.
      if p.peek() is TIdent(w) &&
        (w == "pred" || w == "invariant") &&
        p.peek_at(1) is TIdent(_) &&
        p.peek_at(2) is TLParen {
        p.bump() |> ignore
        let (rname, rname_span) = p.ident("the rule's name")
        raise Syntax(
          msg="`\{rname}` takes parameters, and a rule in the spec block takes none — it is a fact about this component's state, so declare it as a `pred` in the script block, beside the other render-time callables",
          span=rname_span,
        )
      }
      // The same three-token shape the lexer armed on, and not a looser one:
      // in an `enum` body two bare identifiers sit side by side, so `pred` plus
      // a name is a CASE LIST as often as it is a rule. The third token is what
      // tells them apart, and it is the lexer that produced it — a `TBody` only
      // exists where the lexer decided a brace opened a rule.
      if p.peek() is TIdent(w) &&
        (w == "pred" || w == "invariant") &&
        p.peek_at(1) is TIdent(_) &&
        p.peek_at(2) is (TBody(_) | TIdent("format")) {
        let kw_at = p.span()
        p.bump() |> ignore
        let (rname, rname_span) = p.ident("the rule's name")
        guard actual_kind is RState else {
          raise RuleOutsideState(name=rname, span=rname_span)
        }
        let mut format = ""
        let mut format_span = no_span
        if p.peek() is TIdent("format") {
          p.bump() |> ignore
          match p.peek() {
            TExpr(e) => {
              format = e
              format_span = p.span()
              p.bump() |> ignore
            }
            other =>
              raise Syntax(
                msg="`format` takes the sentence to say when `\{rname}` does not hold, and got \{other.describe()}",
                span=p.span(),
              )
          }
        }
        let (source, source_span) = match p.peek() {
          TBody(b) => {
            let at = p.span()
            p.bump() |> ignore
            (b, at)
          }
          other =>
            raise Syntax(
              msg="`\{rname}` needs a body — one expression in `{ … }` — and got \{other.describe()}",
              span=p.span(),
            )
        }
        // One namespace for both kinds: `$conserved` reads an invariant from a
        // view exactly as `$canPush` reads a pred, so two rules with one name
        // would be one `$name` with two answers.
        if rules.iter().any(r => r.name == rname) {
          raise DuplicateRule(name=rname, span=rname_span)
        }
        rules.push({
          kind: if w == "invariant" {
            RInvariant
          } else {
            RPred
          },
          name: rname,
          source,
          source_span,
          format,
          format_span,
          doc: member_doc,
          span: { start: kw_at.start, end_: source_span.end_ + 1, },
          name_span: rname_span,
        })
        p.skip_comma()
        continue
      }
      let attrs = p.attrs()
      let (mname, mspan) = p.ident(
        if takes_fields {
          "a field name"
        } else {
          "a case name"
        },
      )
      if takes_fields {
        p.expect(TColon, "`:` before the field's type")
        fields.push({
          name: mname,
          span: mspan,
          doc: member_doc,
          attrs,
          ty: parse_ty(p),
        })
      } else {
        let payload : Array[RawTy] = []
        if p.peek() is TLParen {
          p.bump() |> ignore
          if !(p.peek() is TRParen) {
            for ;; {
              payload.push(parse_ty(p))
              if p.peek() is TComma {
                p.bump() |> ignore
                continue
              }
              break
            }
          }
          p.expect(TRParen, "`)` closing the payload")
        }
        cases.push({ name: mname, span: mspan, doc: member_doc, payload, })
      }
      p.skip_comma()
    }
    p.expect(TRBrace, "`}` closing the body")
    out.push({
      kind: actual_kind,
      name,
      name_span,
      doc,
      fields,
      cases,
      handle_message,
      handle_intent,
      express_message,
      express_intent,
      properties,
      views,
      implements,
      bindings,
      provide,
      lookup,
      rules,
      wheres,
    })
  }
  out
}

///|
fn empty_raw(
  kind : RawKind,
  name : String,
  span : Span,
  doc : String?,
) -> RawDecl {
  {
    kind,
    name,
    name_span: span,
    doc,
    fields: [],
    cases: [],
    handle_message: [],
    handle_intent: [],
    express_message: [],
    express_intent: [],
    properties: [],
    views: [],
    implements: [],
    bindings: [],
    provide: [],
    lookup: [],
    rules: [],
    wheres: [],
  }
}

///|
/// The relation half of a `where` clause, after its subject.
///
/// A hand-written descent over a CLOSED vocabulary rather than a table, so
/// each arm can say what it expected in its own words. `subject` is carried
/// only to name it in those messages — nothing here looks at the field.
fn parse_relation(
  p : P,
  subject : String,
  refs : Array[(String, Span)],
) -> Relation raise DefError {
  match p.peek() {
    TIdent("is") => {
      p.bump() |> ignore
      parse_is_relation(p, subject, refs)
    }
    // `len <= 100`, `len between 1 and 10`. The one prefix, because a length
    // is the only projection of a subject this vocabulary admits — anything
    // else about a collection is a fact about its ELEMENTS, and a domain is
    // about the field.
    TIdent("len") => {
      p.bump() |> ignore
      RLen(parse_ordering(p, subject, "`len`", refs))
    }
    _ => parse_ordering(p, subject, "`\{subject}`", refs)
  }
}

///|
/// Everything spelled `is …`.
fn parse_is_relation(
  p : P,
  subject : String,
  refs : Array[(String, Span)],
) -> Relation raise DefError {
  let (word, span) = p.ident(
    "what `\{subject}` is — `index of`, `key of`, `member of`, `subset of`, `one of`, or `nonempty`",
  )
  match word {
    "nonempty" => RNonEmpty
    "index" => {
      expect_of(p, "index")
      let field = parse_field_ref(p, "the list `\{subject}` indexes", refs)
      // `or none` — the sentinel half. Written out rather than inferred from
      // the field being an option, because a selection field is as often a
      // plain `Int` holding -1 or 0 as it is an `Int?`, and the clause has to
      // be able to say so either way.
      let allow_none = if p.peek() is TIdent("or") {
        p.bump() |> ignore
        let (n, nspan) = p.ident("`none`")
        if n != "none" {
          raise Syntax(
            msg="`or` in a `where` is followed by `none` and nothing else",
            span=nspan,
          )
        }
        true
      } else {
        false
      }
      RIndexOf(field~, allow_none~)
    }
    "key" => {
      expect_of(p, "key")
      RKeyOf(field=parse_field_ref(p, "the map `\{subject}` keys", refs))
    }
    "member" => {
      expect_of(p, "member")
      RMemberOf(
        field=parse_field_ref(p, "the set `\{subject}` is a member of", refs),
      )
    }
    "subset" => {
      expect_of(p, "subset")
      RSubsetOf(
        field=parse_field_ref(p, "the set `\{subject}` is a subset of", refs),
      )
    }
    "one" => {
      expect_of(p, "one")
      parse_one_of(p, subject)
    }
    _ =>
      raise Syntax(
        msg="`\{word}` is not something a `where` can say; it says `index of`, `key of`, `member of`, `subset of`, `one of`, or `nonempty`",
        span~,
      )
  }
}

///|
/// The `of` that every relational spelling carries.
fn expect_of(p : P, word : String) -> Unit raise DefError {
  if p.peek() is TIdent("of") {
    p.bump() |> ignore
  } else {
    raise Syntax(
      msg="`\{word}` in a `where` is followed by `of`",
      span=p.span(),
    )
  }
}

///|
/// `is one of ["a", "b"]`, or `is one of Priority` for an enum's cases.
///
/// The enum spelling resolves in pass two, where the declarations are in
/// hand; here it is recorded as the single name it was written as, and the
/// resolver tells the two apart by whether the state declares that enum.
fn parse_one_of(p : P, subject : String) -> Relation raise DefError {
  match p.peek() {
    TLBracket => {
      p.bump() |> ignore
      let out : Array[String] = []
      while !(p.peek() is TRBracket) {
        match p.peek() {
          TStr(v) => {
            p.bump() |> ignore
            out.push(v)
          }
          _ => p.fail("a quoted member of the set")
        }
        if p.peek() is TComma {
          p.bump() |> ignore
        } else {
          break
        }
      }
      p.expect(TRBracket, "`]` closing the `one of` list")
      if out.is_empty() {
        raise Syntax(
          msg="`where \{subject} is one of []` admits nothing, so the field could never hold a value",
          span=p.span(),
        )
      }
      ROneOf(out)
    }
    // A bare name: an enum whose cases are the members. Kept as a one-element
    // list and resolved in pass two — see `resolve_wheres`.
    TIdent(_) => {
      let (n, _) = p.ident("an enum name")
      ROneOf([ENUM_MEMBERS_OF + n])
    }
    _ => p.fail("a `[…]` list or an enum name after `one of`")
  }
}

///|
/// The marker that says a `ROneOf` still holds an ENUM NAME rather than its
/// members.
///
/// A prefix and not a second constructor, because the distinction lives for
/// exactly one pass: `resolve_wheres` replaces it with the enum's cases, and
/// nothing downstream can ever see one. A constructor would make every
/// consumer match an arm that is unreachable by then.
///
/// `:` cannot begin an identifier, so no author-written member can collide.
const ENUM_MEMBERS_OF : String = ":enum:"

///|
/// `>= 0`, `< .max`, `between 0 and 100`.
fn parse_ordering(
  p : P,
  subject : String,
  what : String,
  refs : Array[(String, Span)],
) -> Relation raise DefError {
  match p.peek() {
    TIdent("between") => {
      p.bump() |> ignore
      let lo = parse_operand(p, "the low bound", refs)
      if p.peek() is TIdent("and") {
        p.bump() |> ignore
      } else {
        raise Syntax(
          msg="`between` takes two bounds joined by `and`",
          span=p.span(),
        )
      }
      let hi = parse_operand(p, "the high bound", refs)
      RBetween(lo~, hi~)
    }
    TGte | TGt | TLte | TLt => {
      let op : CmpOp = match p.bump().tok {
        TGte => CGe
        TGt => CGt
        TLte => CLe
        _ => CLt
      }
      RCompare(
        op~,
        rhs=parse_operand(p, "what \{what} is compared against", refs),
      )
    }
    _ =>
      p.fail(
        "`>=`, `>`, `<=`, `<` or `between` after \{what} — the orderings a `where` states about \{subject}",
      )
  }
}

///|
/// A number, or another field.
fn parse_operand(
  p : P,
  want : String,
  refs : Array[(String, Span)],
) -> Operand raise DefError {
  match p.peek() {
    TNum(v) => {
      p.bump() |> ignore
      OLit(v)
    }
    TDot => OField(parse_field_ref(p, want, refs))
    _ => p.fail("\{want} — a number, or `.field`")
  }
}

///|
/// `.items` — the dot is what says it is a field rather than a bare word.
fn parse_field_ref(
  p : P,
  want : String,
  refs : Array[(String, Span)],
) -> String raise DefError {
  p.expect(TDot, "`.` before \{want}")
  let (name, span) = p.ident(want)
  refs.push((name, span))
  name
}

///|
fn parse_channels(
  p : P,
  outer : String,
  messages : Array[RawCase],
  intents : Array[RawCase],
) -> Unit raise DefError {
  p.expect(TLBrace, "`{` opening the \{outer} section")
  parse_channel_body(p, outer, messages, intents)
  p.expect(TRBrace, "`}` closing the \{outer} section")
}

///|
fn parse_channel_body(
  p : P,
  outer : String,
  messages : Array[RawCase],
  intents : Array[RawCase],
) -> Unit raise DefError {
  while !(p.peek() is (TRBrace | TEof)) {
    let (kind, span) = p.ident("`message` or `intent`")
    let target = match kind {
      "message" => messages
      "intent" => intents
      _ =>
        raise Syntax(
          msg="`\{outer}` contains `message` and `intent` sections",
          span~,
        )
    }
    p.expect(TLBrace, "`{` opening the \{kind} section")
    parse_cases(p, target)
    p.expect(TRBrace, "`}` closing the \{kind} section")
  }
}

///|
fn parse_cases(p : P, out : Array[RawCase]) -> Unit raise DefError {
  while !(p.peek() is (TRBrace | TEof)) {
    let doc = p.docs()
    let (first_name, span) = p.ident("a message or intent name")
    let name = if p.peek() is TDoubleColon {
      p.bump() |> ignore
      let (member_name, _) = p.ident("a protocol member name")
      first_name + "::" + member_name
    } else {
      first_name
    }
    let payload : Array[RawTy] = []
    if p.peek() is TLParen {
      p.bump() |> ignore
      if !(p.peek() is TRParen) {
        for ;; {
          payload.push(parse_ty(p))
          if p.peek() is TComma {
            p.bump() |> ignore
            continue
          }
          break
        }
      }
      p.expect(TRParen, "`)` closing the payload")
    }
    out.push({ name, span, doc, payload, })
    p.skip_comma()
  }
}

///|
fn qualified(p : P) -> (String, String, Span) raise DefError {
  let (protocol_name, span) = p.ident("a protocol-qualified name")
  p.expect(TDoubleColon, "`::` between a protocol and member")
  let (member_name, _) = p.ident("a protocol member name")
  (protocol_name, member_name, span)
}

///|
fn parse_bindings(
  p : P,
  section : String,
  out : Array[RawBinding],
) -> Unit raise DefError {
  p.expect(TLBrace, "`{` opening the \{section} section")
  while !(p.peek() is (TRBrace | TEof)) {
    let (protocol_name, member_name, span) = qualified(p)
    p.expect(TEquals, "`=` before the implementation")
    let source = match p.peek() {
      TExpr(s) => {
        p.bump() |> ignore
        s
      }
      _ => p.fail("a field, computation, or view name")
    }
    out.push({ section, protocol_name, member_name, source, span, })
    p.skip_comma()
  }
  p.expect(TRBrace, "`}` closing the \{section} section")
}

///|
fn parse_protocol_members(
  p : P,
  section : String,
  properties : Array[RawField],
  views : Array[RawCase],
) -> Unit raise DefError {
  p.expect(TLBrace, "`{` opening the \{section} section")
  while !(p.peek() is (TRBrace | TEof)) {
    let doc = p.docs()
    let attrs = p.attrs()
    let (name, span) = p.ident("a \{section} name")
    if section == "view" {
      views.push({ name, span, doc, payload: [], })
    } else {
      p.expect(TColon, "`:` before the \{section} type")
      properties.push({
        name: section + "::" + name,
        span,
        doc,
        attrs,
        ty: parse_ty(p),
      })
    }
    p.skip_comma()
  }
  p.expect(TRBrace, "`}` closing the \{section} section")
}

///|
/// One `provide { … }` or `lookup { … }` section, already past its word.
///
/// The entries differ by exactly one thing: a provide must say what produces
/// the value, and a lookup names what it wants and MAY say what to fall back
/// on. The expression itself arrives as one `TExpr` — the lexer found where it
/// ended and read none of it.
fn parse_state_wiring(
  p : P,
  word : String,
  provide : Array[ProvideDecl],
  lookup : Array[LookupDecl],
  bindings : Array[RawBinding],
) -> Unit raise DefError {
  let is_provide = word == "provide"
  p.expect(TLBrace, "`{` opening the \{word} section")
  while !(p.peek() is (TRBrace | TEof)) {
    let (first, span) = p.ident(
      if is_provide {
        "the name this component publishes under"
      } else {
        "the name this component is asking for"
      },
    )
    // A qualified binding belongs to a protocol namespace and never enters
    // the raw lookup table, avoiding collisions with an unrelated raw name.
    if p.peek() is TDoubleColon {
      p.bump() |> ignore
      let (member_name, _) = p.ident("a protocol member name")
      p.expect(TEquals, "`=` before the implementation")
      let source = match p.peek() {
        TExpr(s) => {
          p.bump() |> ignore
          s
        }
        _ => p.fail("an expression after `=`")
      }
      bindings.push({
        section: word,
        protocol_name: first,
        member_name,
        source,
        span,
      })
      p.skip_comma()
      continue
    }
    let name = first
    let seen = if is_provide {
      provide.iter().any(e => e.name == name)
    } else {
      lookup.iter().any(e => e.name == name)
    }
    if seen {
      raise Syntax(
        msg="`\{name}` is \{word}d twice, and the second says nothing the first did not",
        span~,
      )
    }
    let mut expr : String? = None
    if p.peek() is TEquals {
      p.bump() |> ignore
      match p.peek() {
        TExpr(e) => {
          p.bump() |> ignore
          expr = Some(e)
        }
        _ => p.fail("an expression after `=`")
      }
    }
    if is_provide {
      match expr {
        // Every provide states what produces it. There is no shorthand for
        // "the field of the same name": a provide is read as a PATH, and one
        // that has to be inferred is one an author cannot see.
        None =>
          raise Syntax(
            msg="`\{name}` is provided with nothing — write `\{name} = .\{name}`, or `self` to publish this component as a type",
            span~,
          )
        Some(source) => provide.push({ name, source, span, })
      }
    } else {
      lookup.push({ name, default: expr, span, })
    }
    p.skip_comma()
  }
  p.expect(TRBrace, "`}` closing the \{word} section")
}

///|
fn parse_ty(p : P) -> RawTy raise DefError {
  let from = p.span()
  let base : RawTy = match p.peek() {
    TLParen => {
      p.bump() |> ignore
      let parts : Array[RawTy] = []
      if !(p.peek() is TRParen) {
        for ;; {
          parts.push(parse_ty(p))
          if p.peek() is TComma {
            p.bump() |> ignore
            continue
          }
          break
        }
      }
      p.expect(TRParen, "`)` closing the tuple")
      RTuple(parts, { start: from.start, end_: p.toks[p.at - 1].span.end_, })
    }
    TIdent(_) => {
      let (name, nspan) = p.ident("a type")
      let args : Array[RawTy] = []
      if p.peek() is TLBracket {
        p.bump() |> ignore
        if name == "Component" && p.peek() is TIdent("protocol") {
          p.bump() |> ignore
          let refs : Array[(String, Span)] = []
          for ;; {
            refs.push(p.ident("a protocol name"))
            if p.peek() is TAmp {
              p.bump() |> ignore
              continue
            }
            break
          }
          args.push(RProtocolSet(refs, nspan))
        } else if !(p.peek() is TRBracket) {
          for ;; {
            args.push(parse_ty(p))
            if p.peek() is TComma {
              p.bump() |> ignore
              continue
            }
            break
          }
        }
        p.expect(TRBracket, "`]` closing the type arguments")
      }
      RNamed(name~, args~, span={
        start: nspan.start,
        end_: p.toks[p.at - 1].span.end_,
      })
    }
    // `Component["Legend"]` is the only place a string is a type argument, and
    // it arrives through the branch above.
    _ => p.fail("a type")
  }
  if p.peek() is TQuestion {
    let q = p.bump()
    return ROpt(base, { start: from.start, end_: q.span.end_, })
  }
  base
}

// ---------------------------------------------------------------------------
// Pass 2 — resolve

///|
/// What a name resolves against while types are being built.
priv struct Env {
  /// Type name -> the declaration, for this component.
  decls : Map[String, RawDecl]
  /// Component name -> itself, so a field can name a sibling.
  comps : Map[String, String]
  protocols : Map[String, String]
}

///|
pub fn parse_state(
  source : String,
  name? : String = "",
) -> Array[StateDef] raise DefError {
  let p : P = { toks: tokenize(source), at: 0, }
  let raw = parse_decls(p)
  // Which components this file declares, so a field can name a sibling
  // before its `state` appears.
  let comps : Map[String, String] = Map([])
  let mut saw_named = false
  let mut saw_bare = false
  let mut bare_span = no_span
  for d in raw {
    if d.kind is RState {
      if d.name == "" {
        saw_bare = true
        bare_span = d.name_span
      } else {
        saw_named = true
        if comps.contains(d.name) {
          raise DuplicateComponent(name=d.name, span=d.name_span)
        }
        // Validated here rather than at emission: the name heads every
        // generated type, so one that is not an identifier would emit code
        // that does not compile.
        comps[d.name] = component_of(d.name, d.name_span)
      }
    }
  }
  if saw_named && saw_bare {
    raise MixedStateNames(span=bare_span)
  }
  guard saw_named || saw_bare else {
    raise NoState(span=if raw.is_empty() { no_span } else { raw[0].name_span })
  }
  // A bare `state` belongs to the file's single unnamed component, exactly as
  // a bare `<template>` id does — and the caller is who knows what that
  // component is called. It matters beyond a label: the name prefixes every
  // generated type, so a bare state with no fallback would emit `Sample`
  // beside `LoaderBarState`.
  if saw_bare {
    comps[""] = upper_name(name)
  }
  // Everything that is not a `state` belongs to every component in the file.
  // One block, one set of shared types — which is what an author writing two
  // components over one `Label` expects.
  let decls : Map[String, RawDecl] = Map([])
  for d in raw {
    match d.kind {
      RStruct | REnum => {
        if is_builtin_ty(d.name) {
          raise ReservedName(name=d.name, span=d.name_span)
        }
        decls[d.name] = d
      }
      _ => ()
    }
  }
  let protocols : Map[String, String] = Map([])
  for d in raw {
    match d.kind {
      RProtocol(id) | RProtocolImport(id) => {
        if protocols.contains(d.name) {
          raise ProtocolConflict(id~, span=d.name_span)
        }
        protocols[d.name] = id
      }
      _ => ()
    }
  }
  let env : Env = { decls, comps, protocols, }
  let out : Array[StateDef] = []
  for d in raw {
    guard d.kind is RState else { continue }
    out.push(build(d, raw, env, name))
  }
  out
}

///|
/// One component's whole contract.
fn build(
  d : RawDecl,
  raw : Array[RawDecl],
  env : Env,
  fallback : String,
) -> StateDef raise DefError {
  let _ = fallback
  let comp = env.comps.get(d.name).unwrap()
  let fields = fields_of(d.fields, env)
  let handle_message = d.handle_message.copy()
  let handle_intent = d.handle_intent.copy()
  let express_message = d.express_message.copy()
  let express_intent = d.express_intent.copy()
  for r in raw {
    if r.name == d.name {
      match r.kind {
        RSurface("handle") => {
          for c in r.handle_message {
            handle_message.push(c)
          }
          for c in r.handle_intent {
            handle_intent.push(c)
          }
        }
        RSurface("express") => {
          for c in r.express_message {
            express_message.push(c)
          }
          for c in r.express_intent {
            express_intent.push(c)
          }
        }
        _ => ()
      }
    }
  }
  let types : Array[UserTy] = []
  for _name, decl in env.decls {
    types.push(user_ty_of(decl, comp, env))
  }
  types.sort_by((a, b) => str_cmp(a.source_name, b.source_name))
  check_acyclic(types, fields, d.name_span)
  let protocol_defs : Array[ProtocolDef] = []
  let protocol_imports : Array[ProtocolRef] = []
  for r in raw {
    match r.kind {
      RProtocol(id) => protocol_defs.push(protocol_of(r, id, env))
      RProtocolImport(id) =>
        protocol_imports.push({ local_name: r.name, id, span: r.name_span, })
      _ => ()
    }
  }
  let implements : Array[String] = []
  for pair in d.implements {
    guard env.protocols.get(pair.0) is Some(id) else {
      raise UnknownProtocol(local_name=pair.0, span=pair.1)
    }
    implements.push(id)
  }
  let bindings : Array[ProtocolBinding] = []
  for b in d.bindings {
    guard env.protocols.get(b.protocol_name) is Some(id) else {
      raise UnknownProtocol(local_name=b.protocol_name, span=b.span)
    }
    bindings.push({
      protocol_id: id,
      member_name: b.member_name,
      source: b.source,
      span: b.span,
    })
  }
  let binding_section = (section : String) => {
    let out : Array[ProtocolBinding] = []
    for i, b in bindings {
      if d.bindings[i].section == section {
        out.push(b)
      }
    }
    out
  }
  {
    source_name: d.name,
    component: comp,
    fields,
    receive: msgs_of(handle_message, env),
    intent: msgs_of(handle_intent, env),
    express_message: msgs_of(express_message, env),
    express_intent: msgs_of(express_intent, env),
    implements,
    protocols: protocol_defs,
    protocol_imports,
    property_bindings: binding_section("property"),
    view_bindings: binding_section("view"),
    provide_bindings: binding_section("provide"),
    lookup_bindings: binding_section("lookup"),
    // `func` is gone: a callable is declared in the script block, where every
    // other callable already lives.
    types,
    provide: d.provide,
    lookup: d.lookup,
    rules: d.rules,
    wheres: resolve_wheres(d.wheres, fields, types, d.name_span),
    doc: d.doc,
  }
}

///|
fn protocol_of(
  d : RawDecl,
  id : String,
  env : Env,
) -> ProtocolDef raise DefError {
  let props = (section : String) => {
    let out : Array[PropertyDef] = []
    let prefix = section + "::"
    for f in d.properties {
      if f.name.has_prefix(prefix) {
        out.push({
          name: f.name[prefix.length():].to_owned(),
          ty: resolve(f.ty, env),
          doc: f.doc,
        })
      }
    }
    out
  }
  {
    local_name: d.name,
    id,
    handle_message: msgs_of(d.handle_message, env),
    handle_intent: msgs_of(d.handle_intent, env),
    express_message: msgs_of(d.express_message, env),
    express_intent: msgs_of(d.express_intent, env),
    properties: props("property"),
    views: d.views.map(v => v.name),
    provides: props("provide"),
    lookups: props("lookup"),
    doc: d.doc,
    span: d.name_span,
  }
}

///|
fn fields_of(
  raw : Array[RawField],
  env : Env,
) -> Array[FieldDef] raise DefError {
  let names = raw.map(f => f.name)
  // The binding is the only mapped spelling. A field is written the way a
  // view reads it, so its source, runtime, and JSON name are one string.
  let bound = mapped(names, "field", binding_name, span_of(raw))
  let out : Array[FieldDef] = []
  for i, f in raw {
    out.push({
      name: f.name,
      binding: bound[i].1,
      ty: resolve(f.ty, env),
      doc: f.doc,
      attrs: f.attrs,
    })
  }
  out
}

///|
fn span_of(raw : Array[RawField]) -> Span {
  match raw.get(0) {
    Some(f) => f.span
    None => no_span
  }
}

///|
fn msgs_of(raw : Array[RawCase], env : Env) -> Array[MsgDef] raise DefError {
  let first = match raw.get(0) {
    Some(c) => c.span
    None => no_span
  }
  let runtime_names : Array[String] = []
  let variant_names : Array[String] = []
  for c in raw {
    let parts : Array[String] = c.name
      .split("::")
      .map(x => x.to_owned())
      .collect()
    if parts.length() == 2 {
      guard env.protocols.get(parts[0]) is Some(id) else {
        raise UnknownProtocol(local_name=parts[0], span=c.span)
      }
      runtime_names.push(id + "::" + camel_name(parts[1]))
      variant_names.push(upper_name(parts[0]) + upper_name(parts[1]))
    } else {
      runtime_names.push(camel_name(c.name))
      variant_names.push(upper_name(c.name))
    }
  }
  let runtime = mapped(runtime_names, "message", x => x, first)
  let variants = mapped(variant_names, "message", x => x, first)
  let out : Array[MsgDef] = []
  for i, c in raw {
    let payload : Array[StateTy] = []
    for t in c.payload {
      payload.push(resolve(t, env))
    }
    out.push({
      source_name: c.name,
      name: runtime[i].1,
      variant: variants[i].1,
      payload,
      doc: c.doc,
    })
  }
  out
}

///|
/// A named type, prefixed with the component so two components' `Label`s do
/// not collide in one generated module.
fn user_ty_of(d : RawDecl, comp : String, env : Env) -> UserTy raise DefError {
  let name = comp + upper_name(d.name)
  let kind : UserTyKind = match d.kind {
    RStruct => URecord(fields_of(d.fields, env))
    _ => {
      // One construct, two encodings. Every case payload-free means the value
      // IS its case name, which is what an enum has always encoded as; one
      // payload anywhere makes it a tagged sum. The author writes `enum`
      // either way.
      let mut has_payload = false
      for c in d.cases {
        if !c.payload.is_empty() {
          has_payload = true
        }
      }
      if has_payload {
        UVariant(msgs_of(d.cases, env))
      } else {
        let names = d.cases.map(c => c.name)
        let first = match d.cases.get(0) {
          Some(c) => c.span
          None => no_span
        }
        UEnum(mapped(names, "enum case", upper_name, first))
      }
    }
  }
  { source_name: d.name, name, kind, doc: d.doc, }
}

// ---------------------------------------------------------------------------
// Types

///|
/// The builtin type names, which are reserved.
///
/// Reserved because a user type called `Any` would silently change what every
/// `Any` in the file means.
fn is_builtin_ty(name : String) -> Bool {
  name
  is ("Bool"
  | "Int"
  | "Int8"
  | "Int16"
  | "UInt"
  | "UInt8"
  | "UInt16"
  | "Double"
  | "String"
  | "Array"
  | "Set"
  | "Map"
  | "Any"
  | "Component")
}

///|
fn resolve(t : RawTy, env : Env) -> StateTy raise DefError {
  match t {
    ROpt(inner, _) => TOption(resolve(inner, env))
    RTuple(parts, _) => {
      let out : Array[StateTy] = []
      for x in parts {
        out.push(resolve(x, env))
      }
      TTuple(out)
    }
    RNamed(name~, args~, span~) => named(name, args, span, env)
    RProtocolSet(refs, _) => {
      let ids : Array[String] = []
      for pair in refs {
        guard env.protocols.get(pair.0) is Some(id) else {
          raise UnknownProtocol(local_name=pair.0, span=pair.1)
        }
        ids.push(id)
      }
      TCompProtocols(ids)
    }
  }
}

///|
fn arity(
  name : String,
  args : Array[RawTy],
  want : Int,
  span : Span,
) -> Unit raise DefError {
  if args.length() != want {
    raise BadTypeArgs(name~, want~, got=args.length(), span~)
  }
}

///|
fn named(
  name : String,
  args : Array[RawTy],
  span : Span,
  env : Env,
) -> StateTy raise DefError {
  // The argument-free spellings, from the table `StateDef::resolve_ty` reads
  // too — one name, one meaning, in a schema and in a block's `new` alike.
  if scalar_ty(name) is Some(t) {
    arity(name, args, 0, span)
    return t
  }
  match name {
    "Array" => {
      arity(name, args, 1, span)
      TList(resolve(args[0], env))
    }
    "Set" => {
      arity(name, args, 1, span)
      // `Set[String]` is open membership; `Set[E]` over a declared enum is
      // closed, and the enum is where the membership is written. One spelling,
      // and the container decides the zero — which is empty either way.
      match args[0] {
        RNamed(name=inner, args=[], span=ispan) =>
          if inner == "String" {
            TSet
          } else if env.decls.get(inner) is Some(d) && d.kind is REnum {
            TFlags(inner)
          } else {
            raise UnsupportedType(
              ty="Set[\{inner}]",
              why="a set holds strings or the cases of an enum; `\{inner}` is neither",
              span=ispan,
            )
          }
        other =>
          raise UnsupportedType(
            ty="Set[…]",
            why="a set holds strings or the cases of an enum",
            span=other.span(),
          )
      }
    }
    "Map" => {
      arity(name, args, 2, span)
      // Ordered, which is the refinement the runtime actually keeps. The key
      // is String because a JSON object's key is.
      match args[0] {
        RNamed(name="String", args=[], ..) => TOMap(resolve(args[1], env))
        other =>
          raise UnsupportedType(
            ty="Map[…]",
            why="a map is keyed by String; state travels as JSON, where an object's key is a string",
            span=other.span(),
          )
      }
    }
    "Component" =>
      if args.is_empty() {
        TComp(None)
      } else {
        arity(name, args, 1, span)
        match args[0] {
          RProtocolSet(refs, _) => {
            let ids : Array[String] = []
            for pair in refs {
              guard env.protocols.get(pair.0) is Some(id) else {
                raise UnknownProtocol(local_name=pair.0, span=pair.1)
              }
              ids.push(id)
            }
            TCompProtocols(ids)
          }
          // `Component["Legend"]` names a component from another module. A
          // string rather than a bare name because it resolves through the
          // registration scope at make time and this file cannot see it.
          RNamed(name=n, args=[], ..) => TComp(Some(upper_name(n)))
          other =>
            raise UnsupportedType(
              ty="Component[…]",
              why="a component slot names one component",
              span=other.span(),
            )
        }
      }
    // Named rather than silently unknown, because "unknown type `Int64`" would
    // read as a spelling mistake when the answer is that state travels as JSON
    // and a JSON number is a Double.
    "Int64" | "UInt64" =>
      raise UnsupportedType(
        ty=name,
        why="state travels as JSON, where a number is a Double — whole values above 2^53 do not survive the trip; carry it as a String",
        span~,
      )
    _ => {
      arity(name, args, 0, span)
      // A sibling component, then a type this file declares. Siblings first
      // for the same reason builtins are reserved: a slot's type is the more
      // surprising thing to have shadowed.
      if env.comps.get(name) is Some(comp) {
        return TComp(Some(comp))
      }
      guard env.decls.get(name) is Some(d) else {
        raise UnknownTypeRef(name~, span~)
      }
      match d.kind {
        RStruct => TRecord(name)
        _ => {
          let mut has_payload = false
          for c in d.cases {
            if !c.payload.is_empty() {
              has_payload = true
            }
          }
          if has_payload {
            TVariant(name)
          } else {
            TEnum(name)
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Termination

///|
/// Refuse a named type that contains ITSELF with no indirection in between.
///
/// `Array[Node]` and `Node?` are fine, and that is the point of drawing the
/// line here: both become an `Array` and an `Option` in MoonBit, so the struct
/// and the type-directed `zero_expr` both terminate. `struct Node { next : Node }`
/// has no representation and no zero.
fn check_acyclic(
  types : Array[UserTy],
  state_fields : Array[FieldDef],
  span : Span,
) -> Unit raise DefError {
  let by_name : Map[String, Array[StateTy]] = Map([])
  for t in types {
    by_name[t.source_name] = match t.kind {
      URecord(fs) => fs.map(f => f.ty)
      // Every payload counts, not just the first case: a schema whose validity
      // turned on declaration order would be a trap.
      UVariant(cs) => cs.map(c => c.payload).fold(init=[], (a, b) => a + b)
      UEnum(_) => []
    }
  }
  by_name["state"] = state_fields.map(f => f.ty)
  let on_path : Map[String, Bool] = Map([])
  let done : Map[String, Bool] = Map([])
  walk_named("state", by_name, on_path, done, span)
}

///|
fn walk_named(
  name : String,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Bool],
  done : Map[String, Bool],
  span : Span,
) -> Unit raise DefError {
  if done.contains(name) {
    return
  }
  if on_path.contains(name) {
    raise CyclicType(name~, span~)
  }
  on_path[name] = true
  match by_name.get(name) {
    Some(tys) =>
      for t in tys {
        walk_inline(t, by_name, on_path, done, span)
      }
    None => ()
  }
  on_path.remove(name)
  done[name] = true
}

///|
fn walk_inline(
  ty : StateTy,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Bool],
  done : Map[String, Bool],
  span : Span,
) -> Unit raise DefError {
  match ty {
    // Heap indirection: the recursion is finite and the zero terminates.
    TList(_) | TOption(_) | TOMap(_) => ()
    TTuple(ts) =>
      for t in ts {
        walk_inline(t, by_name, on_path, done, span)
      }
    TRecord(n) | TVariant(n) | TEnum(n) | TFlags(n) =>
      walk_named(n, by_name, on_path, done, span)
    TBool
    | TInt(..)
    | TFloat
    | TText
    | TSet
    | TComp(_)
    | TCompProtocols(_)
    | TAny => ()
  }
}
