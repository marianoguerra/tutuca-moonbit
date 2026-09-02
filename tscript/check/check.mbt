// The checker. Implements the declares in spec.mbt.
//
// One walk per declaration, carrying an environment of what a name means here:
// the schema for `.field`, the parameters for a bare name, the block's own
// declarations for an application. Types are `@statedef.StateTy?` throughout,
// where `None` is OPAQUE and never "wrong" — the rule `check_state.mbt` states
// and this file inherits without amendment.
//
// The shape of nearly every rule is therefore the same: infer both sides, and
// report only when both are known and they disagree. A checker over a language
// with `$method`, `*dyn` and binds it cannot see has to be built that way or it
// reports mostly noise.

///|
priv struct C {
  def : @statedef.StateDef
  surface : Surface
  out : Array[Finding]
  /// The parameters of the declaration being checked.
  mut params : Map[String, @statedef.StateTy?]
  /// The declaration being checked, for a message about one of its arguments.
  mut decl_name : String
  /// Which declarations the block itself makes, by name: predicates and
  /// computes are callable, and everything else is not.
  callable : Map[String, Int]
  /// The callables a `requires` / `ensures` may name, by name and arity.
  predicate : Map[String, Int]
  /// True inside `enrich` / `enrich_scope`, the only kinds that may assign a
  /// binding.
  mut binds_assignable : Bool
  /// The kind of the declaration being checked. `reply`, `fail` and `forward`
  /// are the first statements in the language whose legality depends on which
  /// body they are in, so this is the first thing the walk has to carry.
  mut decl_kind : @tscript.DeclKind
  /// What `new` last put in `@cur`, on this path through the body.
  mut target : Target
}

///|
/// The active target's type, as the walk knows it.
///
/// Two states rather than one optional, because "no `new` has run" and "a
/// `new` ran and its type is opaque" are different answers: the first is a
/// mistake to report, and the second is the usual opacity to stay quiet about.
priv enum Target {
  TUnset
  TySet(@statedef.StateTy?)
}

///|
fn C::say(
  self : C,
  code : String,
  message : String,
  span : @tutuca.Span,
) -> Unit {
  self.out.push({ code, message, span, severity: SError, })
}

///|
/// A finding a build does not have to stop for. One rule uses it; see
/// `Severity`.
fn C::warn(
  self : C,
  code : String,
  message : String,
  span : @tutuca.Span,
) -> Unit {
  self.out.push({ code, message, span, severity: SWarning, })
}

///|
pub fn Surface::empty() -> Surface {
  { inputs: Map([]), knows_views: false, open_senders: false, comps: [], }
}

///|
/// Check the SPEC block's rules against the schema they are about.
///
/// A second entry point rather than a branch inside `check`, because the two
/// answer about different texts. A `Finding` carries a span in the block it
/// came from, and a caller rebases it with that block's offset — so a finding
/// about a `pred` in the spec block and a finding about a `receive` in the
/// script block cannot ride in one list without one of them landing in the
/// wrong file position.
///
/// Every span here is relative to the SPEC block; rebase with
/// `@viewfile.ViewFile::state_block`.
pub fn check_rules(def : @statedef.StateDef) -> Array[Finding] {
  let callable : Map[String, Int] = Map([])
  let predicate : Map[String, Int] = Map([])
  for r in def.rules {
    callable[r.name] = 0
    predicate[r.name] = 0
  }
  let c = C::{
    def,
    surface: Surface::empty(),
    out: [],
    params: Map([]),
    decl_name: "",
    callable,
    predicate,
    binds_assignable: false,
    decl_kind: DPred,
    target: TUnset,
  }
  for r in def.rules {
    c.decl_name = r.name
    c.decl_kind = if r.kind is RInvariant { DInvariant } else { DPred }
    // The body. A rule answers yes or no, so it is judged as a CONDITION by
    // the same rule every other condition is — not a stricter one, since a
    // string and a number are boolish in tutuca and a `pred` that invented a
    // narrower truthiness would be a second one to learn.
    if c.parse_rule(r.source, r.source_span) is Some(e) {
      c.condition(e)
    }
    // The sentence. Walked like any other expression, so a field that is not
    // there is reported where it is written rather than turning into an empty
    // sentence at the moment somebody most wants to read one.
    if r.format != "" {
      if c.parse_rule(r.format, r.format_span) is Some(e) {
        match definite(c.expr(e)) {
          Some(TyText) | None => ()
          Some(t) =>
            c.say(
              "FORMAT_TYPE",
              "a `format` is the sentence a reader is shown, and this one answers \{t.show_source()} — write a string, or a `$'…'` template that puts it in one",
              r.format_span |> rebase,
            )
        }
      }
    }
  }
  c.out
}

///|
/// A `@statedef.Span` as a `@tutuca.Span`. The two are the same half-open
/// character range and differ only in which package declares them.
fn rebase(s : @statedef.Span) -> @tutuca.Span {
  { start: s.start, end_: s.end_, }
}

///|
/// Parse one rule's source, answering a finding rather than raising.
///
/// The span comes from the SPEC block and the parse error's span from inside
/// the rule, so the two are added: `parse_expr_source` is handed a slice and
/// counts from its start.
fn C::parse_rule(
  self : C,
  source : String,
  at : @statedef.Span,
) -> @tutuca.Expr? {
  Some(@tscript.parse_expr_source(source)) catch {
    err => {
      let inner = err.span()
      self.out.push({
        code: "RULE_SYNTAX",
        message: err.message(),
        severity: SError,
        span: { start: at.start + inner.start, end_: at.start + inner.end_, },
      })
      None
    }
  }
}

///|
pub fn check(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  surface? : Surface = Surface::empty(),
) -> Array[Finding] {
  // Collected first, because a body may apply a predicate declared BELOW it.
  // Declaration order is only a termination proof for predicates calling
  // predicates, which is a rule for a later pass; nothing here needs order.
  let callable : Map[String, Int] = Map([])
  // The subset a contract may name. Separate rather than a flag on the map
  // above, because the two questions are different: "can a body apply this" is
  // answered by every value body, and "is this a rule" only by the two kinds
  // that declare their answer to be a yes or a no.
  let predicate : Map[String, Int] = Map([])
  // The spec block's rules FIRST, because that is where a `pred` and an
  // `invariant` now live: a rule is not behaviour — no statements, no effects,
  // no parameters — and an invariant in particular has nowhere per-handler to
  // be written. A rule declared there takes no arguments, which is why the
  // arity is 0 and not read from anywhere.
  for r in def.rules {
    callable[r.name] = 0
    predicate[r.name] = 0
  }
  let out : Array[Finding] = []
  for p in def.properties {
    if p.getter is None &&
      !decls.iter().any(d => d.kind is DGet && d.name == p.name) {
      out.push({
        code: "MISSING_PROPERTY_GETTER",
        message: "property `\{p.name}` uses a complex `get` but the script block declares no `get \{p.name}` body",
        severity: SError,
        span: @tscript.no_span,
      })
    }
    if p.writable &&
      p.setter is None &&
      !decls.iter().any(d => d.kind is DSet && d.name == p.name) {
      out.push({
        code: "MISSING_PROPERTY_SETTER",
        message: "property `\{p.name}` opts into a complex `set` but the script block declares no `set \{p.name}` body",
        severity: SError,
        span: @tscript.no_span,
      })
    }
  }
  for d in decls {
    if d.kind is (DPred | DCompute | DInvariant) {
      // A rule written in BOTH blocks is not a silent win for either. It is
      // reported here rather than left to whichever backend reads one of them,
      // because the two answers can differ and the author is the only one who
      // knows which was meant.
      if @tscript.is_predicate(d.kind) && def.rule(d.name) is Some(_) {
        out.push({
          code: "RULE_IN_BOTH",
          message: "`\{d.name}` is declared here and in the spec block — a rule has one body, and these two can disagree; delete this one",
          severity: SWarning,
          span: d.name_span,
        })
      }
      callable[d.name] = d.params.length()
    }
    if @tscript.is_predicate(d.kind) {
      predicate[d.name] = d.params.length()
    }
  }
  let c = C::{
    def,
    surface,
    out,
    params: Map([]),
    decl_name: "",
    callable,
    predicate,
    binds_assignable: false,
    decl_kind: DReceive,
    target: TUnset,
  }
  for d in decls {
    c.decl(d)
  }
  c.view_names(decls)
  c.out
}

///|
/// `NO_VIEW_HANDLER`: a view name the block neither answers nor forwards
///.
///
/// A view name that nothing answers does nothing, which is safe and is also
/// the shape of a misspelling — the two are indistinguishable at runtime, so
/// they are separated here instead. The whole rule is that a component states
/// its own vocabulary, so reading the block tells you every name it answers
/// and every name it lets out.
///
/// Answering and forwarding are the same thing here, deliberately: a
/// `receive save(text) { forward }` IS a declaration, so the rule is about the
/// name being DECLARED and not about what the body does with it. An `intent`
/// declaration does not count — an intent is not a message, and a view raises
/// messages.
fn C::view_names(self : C, decls : Array[@tscript.Decl]) -> Unit {
  let declared : Set[String] = Set([])
  for d in decls {
    if d.kind is DReceive {
      declared.add(d.name)
    }
  }
  for name, _ in self.surface.inputs {
    if declared.contains(name) || self.addresses_a_field(name) {
      continue
    }
    self.warn(
      "NO_VIEW_HANDLER",
      "the view sends `\{name}`, and this block neither answers it nor forwards it — write `receive \{name}(…) { forward }` to dispatch it as an intent, or `receive \{name}(…) { … }` to answer it here",
      // The block has no span for a name it does not mention, so the finding
      // points at the block's start. Where the name IS written is the view,
      // and this package cannot see one.
      { start: 0, end_: 0, },
    )
  }
}

///|
/// Whether `name` looks like a generated mutator over a declared field.
///
/// Deliberately CONSERVATIVE, and deliberately not a copy of
/// `component/gen_mutators`' verb table. This package imports `tscript` and
/// `statedef` and nothing else, so it cannot see that table, and a second copy
/// of a list is exactly how two lists drift apart. What it can see is that
/// every generated name is built from a field's name capitalized
/// (`@tutuca.mutator_name`) — `setTitle`, `titleLen`, `removeInItemsAt` — so a
/// name that does not contain one is certainly not a mutator, and one that
/// does might be.
///
/// Erring toward silence is this package's governing rule: unknown is not
/// wrong. A missed mutator here is a warning nobody wanted; a false one is a
/// warning that teaches people to ignore the rule.
fn C::addresses_a_field(self : C, name : String) -> Bool {
  for f in self.def.fields {
    if f.name.is_empty() {
      continue
    }
    let capped = f.name[0:1].to_owned().to_upper() + f.name[1:].to_owned()
    // `<field>Len` is the one generated name that does NOT capitalize, so it
    // is the one that has to be spelled out here.
    if name.contains(capped) || name == f.name + "Len" {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Declarations

///|
fn C::decl(self : C, d : @tscript.Decl) -> Unit {
  self.params = Map([])
  self.decl_name = d.name
  self.binds_assignable = d.kind is (DEnrich | DEnrichScope)
  self.decl_kind = d.kind
  // A target belongs to the body that built it and to nothing else — the same
  // rule the interpreter enforces by refusing to hand `@cur` back.
  self.target = TUnset
  // Where a handler's parameter types come from. A schema case is DECLARED, so
  // its payload is exact; a name only the views write is not declared
  // anywhere, so its arguments are what the views wrote — and two call sites
  // that disagreed joined to opaque long before this saw them. `msg_params`
  // answers both, because one bucket now holds both.
  match d.kind {
    DReceive | DIntent => self.msg_params(d)
    DSet =>
      match self.def.properties.iter().find_first(p => p.name == d.name) {
        Some(p) => self.params["value"] = Some(p.ty)
        None => self.params["value"] = None
      }
    // A `compute` or a `pred` is called from a slot or from another body, and
    // nothing declares what it is passed. Opaque, which is the honest answer.
    _ =>
      for p in d.params {
        self.params[p.name] = None
      }
  }
  self.contract(d, d.requires_, "requires")
  self.contract(d, d.ensures_, "ensures")
  self.format(d)
  // An invariant is asked after every transition, and no two transitions carry
  // the same arguments. There is nothing that could be passed.
  if d.kind is DInvariant && !d.params.is_empty() {
    self.say(
      "INVARIANT_ARGS",
      "an `invariant` is asked after every transition, so there is nothing to pass it — drop the parameter(s), or make it a `pred` a slot calls",
      d.name_span,
    )
  }
  match d.kind {
    DGet =>
      match self.def.properties.iter().find_first(p => p.name == d.name) {
        None =>
          self.say(
            "NO_PROPERTY",
            "`get {d.name}` names no property in the spec block",
            d.name_span,
          )
        Some(p) if p.getter is Some(_) =>
          self.say(
            "PROPERTY_ALREADY_BACKED",
            "property `{d.name}` already names a backing field for `get`, so it cannot also have a complex getter",
            d.name_span,
          )
        _ => ()
      }
    DSet =>
      match self.def.properties.iter().find_first(p => p.name == d.name) {
        None =>
          self.say(
            "NO_PROPERTY",
            "`set {d.name}` names no property in the spec block",
            d.name_span,
          )
        Some(p) if !p.writable =>
          self.say(
            "READ_ONLY_PROPERTY",
            "property `{d.name}` did not opt into `set`",
            d.name_span,
          )
        Some(p) if p.setter is Some(_) =>
          self.say(
            "PROPERTY_ALREADY_BACKED",
            "property `{d.name}` already names a backing field for `set`, so it cannot also have a complex setter",
            d.name_span,
          )
        _ => ()
      }
    _ => ()
  }
  match d.body {
    Stmts(ss) => self.stmts(ss)
    // A `pred` answers yes or no, so its body is a CONDITION and is judged by
    // the same rule every other condition is. Not a stricter one: a string and
    // a number are boolish in tutuca — `@show=".role"` beside `@text=".role"`
    // is idiomatic — and a `pred` that invented a narrower rule than `@show`
    // follows would be a second truthiness to learn.
    Value(e) =>
      if @tscript.is_predicate(d.kind) {
        self.condition(e)
      } else if d.kind is DGet {
        let got = self.expr(e)
        let want = self.def.properties
          .iter()
          .find_first(p => p.name == d.name)
          .map(p => p.ty)
        self.assignable(want, got, e.span())
      } else {
        self.expr(e) |> ignore
      }
  }
}

///|
/// One contract clause: the `pred` it names has to exist, be a predicate, and
/// take nothing.
///
/// Nothing to pass is the rule, not an omission. A contract is a statement
/// about the component's STATE — what has to be true for a transition to
/// happen, and what has to be true where it landed — and the arguments a
/// handler was called with are already checked by the schema and by the arm's
/// own guards. A rule that needed one of them is a rule about this dispatch
/// rather than about the component, and `if` is where that is written.
fn C::contract(
  self : C,
  d : @tscript.Decl,
  clause : @tscript.Attach?,
  word : String,
) -> Unit {
  guard clause is Some(c) else { return }
  guard self.predicate.get(c.name) is Some(arity) else {
    self.say(
      "NO_PRED",
      "`\{word} \{c.name}` names no `pred` the spec block declares" +
      (match @statedef.nearest(c.name, self.predicate.keys().collect()) {
        Some(s) => " — did you mean `\{s}`?"
        None =>
          if self.callable.contains(c.name) {
            "; `\{c.name}` is a `compute`, and a contract names a `pred`, whose answer is declared to be a yes or a no"
          } else {
            "; `\{d.name}` asks for it, so declare `pred \{c.name} { … }` inside `state \{self.def.source_name}` in the spec block"
          }
      }),
      c.span,
    )
    return
  }
  if arity != 0 {
    self.say(
      "CONTRACT_ARGS",
      "`\{c.name}` takes \{arity} parameter(s), and a contract is asked with none — a rule that needs an argument is about this dispatch rather than about the component, so guard it with `if` instead",
      c.span,
    )
  }
}

///|
/// A rule's `format`: the sentence a reader sees when the rule does not hold.
///
/// Walked like any other expression, so a field that is not there is reported
/// where it is written rather than turning into an empty sentence at the moment
/// somebody most wants to read one. Its TYPE is judged by the same rule the
/// rest of this file follows — report only when the answer is known and it
/// disagrees — and what it has to be is a string: a bare number is provenance,
/// not a sentence, and the sigil that makes one out of the other (`$'…'`) is
/// already in the language.
fn C::format(self : C, d : @tscript.Decl) -> Unit {
  guard d.format is Some(e) else { return }
  match definite(self.expr(e)) {
    Some(TyText) | None => ()
    Some(t) =>
      self.say(
        "FORMAT_TYPE",
        "a `format` is the sentence a reader is shown, and this one answers \{t.show_source()} — write a string, or a `$'…'` template that puts it in one",
        e.span(),
      )
  }
}

///|
/// Bind a message handler's parameters from the schema's declared payload.
fn C::msg_params(self : C, d : @tscript.Decl) -> Unit {
  let (cases, bucket) = match d.kind {
    DIntent => (self.def.intent, "intent")
    _ => (self.def.receive, "receive")
  }
  let found = cases.filter(m => m.name == d.name)
  // A `receive` name the VIEWS send needs no schema case. One bucket holds a
  // view's name and a parent's, and the schema declares every message the
  // component accepts BEYOND the ones its own views send. So a `receive` that
  // answers a view name takes its parameter types from the call sites, which
  // are right there in the same component.
  // A `receive` the surface cannot speak for. Either the views send this name
  // and its parameters take their types from the call sites, or the caller has
  // no views at all and is in no position to call the name undeclared.
  if found.is_empty() && d.kind is DReceive && !self.surface.knows_views {
    for p in d.params {
      self.params[p.name] = None
    }
    return
  }
  if found.is_empty() &&
    d.kind is DReceive &&
    self.surface.inputs.get(d.name) is Some(types) {
    for i, p in d.params {
      self.params[p.name] = types.get(i).unwrap_or(None)
    }
    if types.length() != d.params.length() {
      self.say(
        "ARITY",
        "`\{d.name}` takes \{d.params.length()} parameter(s) here, but the views call it with \{types.length()}",
        d.name_span,
      )
    }
    return
  }
  // A name no view sends, in a file whose senders are not all in it. See
  // `Surface::open_senders`: a card is dispatched into by its host and by its
  // own scenes, so "the schema declares no case for this" is a thing to
  // prefer, not a thing to assert. The parameters bind raw, exactly as they do
  // for a caller with no views at all.
  if found.is_empty() && d.kind is DReceive && self.surface.open_senders {
    for p in d.params {
      self.params[p.name] = None
    }
    return
  }
  guard found.get(0) is Some(msg) else {
    // The schema is the only place these names can be declared — the views
    // never write them — so a handler for one the block does not declare is
    // answering a message nothing can send.
    self.say(
      "NO_SUCH_MESSAGE",
      "the schema declares no `\{bucket}` case `\{d.name}`" +
      (match @statedef.nearest(d.name, cases.map(m => m.name)) {
        Some(s) => " — did you mean `\{s}`?"
        None =>
          "; add it to `variant \{bucket}` in the <script type=\"tutuca/spec\"> block"
      }),
      d.name_span,
    )
    for p in d.params {
      self.params[p.name] = None
    }
    return
  }
  if msg.payload.length() != d.params.length() {
    self.say(
      "ARITY",
      "`\{bucket} \{d.name}` carries \{msg.payload.length()} value(s), but this takes \{d.params.length()}",
      d.name_span,
    )
  }
  for i, p in d.params {
    self.params[p.name] = msg.payload.get(i)
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
/// Whether an effect's first argument is a message NAME.
///
/// The list is short and worth being explicit about, because the answer used
/// to be "everything except `stop`" and v2 makes that wrong three ways over.
fn names_a_message(effect : String) -> Bool {
  effect is ("send" | "sendAt" | "bubble" | "request" | "intent")
}

///|
/// `NOT_A_HANDLER`: the two effects that answer, and the one that continues,
/// are legal only in a body that has something to answer or continue.
///
/// `reply` and `fail` need a sender, and only an intent has one — a message is
/// addressed and its sender is not waiting. `forward` needs a message to pass
/// on, so it is legal wherever one arrives: a `receive`, where it starts a
/// walk, and an `intent`, where it amends the one already walking.
fn C::effect_placement(self : C, effect : String, span : @tutuca.Span) -> Unit {
  match effect {
    "reply" | "fail" =>
      if !(self.decl_kind is DIntent) {
        self.say(
          "NOT_A_HANDLER",
          "`\{effect}` answers the sender of an intent, and `\{@tscript.kind_word(self.decl_kind)} \{self.decl_name}` has none — a message is addressed, so nobody is waiting for an answer",
          span,
        )
      }
    "forward" =>
      if !(self.decl_kind is (DReceive | DIntent)) {
        self.say(
          "NOT_A_HANDLER",
          "`forward` passes on the message this body is handling, and `\{@tscript.kind_word(self.decl_kind)} \{self.decl_name}` is not handling one",
          span,
        )
      }
    _ => ()
  }
}

///|
fn C::stmts(self : C, ss : Array[@tscript.Stmt]) -> Unit {
  for s in ss {
    self.stmt(s)
  }
}

///|
fn C::stmt(self : C, s : @tscript.Stmt) -> Unit {
  match s {
    // `@cur = expr` names the WHOLE target, so it does not read one — it makes
    // one, out of a value that is already built. Taking a copy of a row to
    // edit and push back is what it is for.
    SAssign(place~, op=ASet, value~, span~) if place.root is PBind(n) &&
      n == @tscript.target_bind &&
      place.steps.is_empty() => {
      let got = self.expr(value)
      if self.binds_assignable {
        self.say(
          "RESERVED_BIND",
          "`@\{n}` is the target `new` builds into, not a binding this `enrich` can hand a view — bind another name",
          span,
        )
      }
      self.target = TySet(got)
    }
    SAssign(place~, op~, value~, span~) => {
      let target = self.place(place, assigning=true)
      let got = self.expr(value)
      // `+=` and `-=` are arithmetic, so both sides have to be numbers — and
      // a `+=` on a string is far likelier to be a mistake than an intended
      // concatenation, which `.s = .s + x` still spells.
      if op is (AAdd | ASub) {
        match definite(target) {
          Some(t) if !is_numeric(t) =>
            self.say(
              "TYPE",
              "`\{assign_word(op)}` is arithmetic, but this place is \{t.show_source()}",
              span,
            )
          _ => ()
        }
      }
      self.assignable(target, got, span)
    }
    SMethod(place~, call~, args~, span~) => {
      let recv = self.place(place, assigning=true)
      for a in args {
        self.expr(a) |> ignore
      }
      match recv {
        Some(t) => self.method_fits(call, t, span)
        None => ()
      }
    }
    SEffect(name~, args~, span~, ..) => {
      if self.decl_kind is DSet {
        self.say(
          "PROPERTY_EFFECT", "a property setter is synchronous and pure; move `{name}` to a message handler",
          span,
        )
      }
      let message_arg = if names_a_message(name) {
        Some(if name == "sendAt" { 1 } else { 0 })
      } else {
        None
      }
      for i, a in args {
        // A naming operand is syntax interpreted below, not a value
        // expression. In particular, an unquoted protocol member must not
        // also be diagnosed as an unknown local variable.
        if message_arg == Some(i) {
          continue
        }
        // A `&` place is a POSITION and has no value, so it is checked as a
        // place rather than inferred as one.
        match a {
          ERef(place~, ..) => self.place(place, assigning=false) |> ignore
          _ => self.expr(a) |> ignore
        }
      }
      self.effect_placement(name, span)
      // The first argument of a NAMING effect is a message, and a name that is
      // not a literal cannot be checked against anything — nor routed by the
      // generator, which needs it at generation time.
      //
      // Three effects carry no name at all and are therefore exempt:
      // `forward` re-dispatches the one that arrived, and `reply` and `fail`
      // are addressed by the walk. Asking them would report `reply 1` as a
      // dynamic message name.
      if names_a_message(name) {
        let name_at = message_arg.unwrap()
        if args.get(name_at) is Some(a0) {
          match a0 {
            ELit(lit=LStr(_), ..) => () // explicitly raw
            EName(name=source_name, ..) =>
              match self.def.operation_name(source_name) {
                None =>
                  self.say(
                    "PROTOCOL_UNRESOLVED",
                    "`\{source_name}` uses a protocol name this component did not import",
                    span,
                  )
                Some(wire_name) => {
                  let declared = if name == "intent" {
                    self.def.express_intent
                  } else {
                    self.def.express_message
                  }
                  if !declared.iter().any(m => m.name == wire_name) {
                    self.say(
                      "PROTOCOL_EXPRESSION_UNDECLARED",
                      "`\{source_name}` is not declared in this component's `express` surface",
                      span,
                    )
                  }
                }
              }
            _ =>
              self.say(
                "DYNAMIC_MESSAGE",
                "`\{name}` needs a raw quoted name or a declared protocol operation",
                span,
              )
          }
        }
      }
    }
    SNew(ty~, span~) => {
      if self.decl_kind is DSet {
        self.say(
          "PROPERTY_EFFECT", "a property setter cannot create a component; move `new` to a message handler",
          span,
        )
      }
      self.target = TySet(self.ty_ref(ty))
    }
    SIf(cond~, then_~, else_~, ..) => {
      self.condition(cond)
      let before = self.target
      self.stmts(then_)
      let after_then = self.target
      self.target = before
      self.stmts(else_)
      // What both arms agree on. Two arms that built different types leave a
      // target whose type nothing here knows, and an arm that built nothing
      // leaves no target at all — which is the answer that makes a `@cur`
      // after the branch report rather than pass.
      self.target = match (after_then, self.target) {
        (TySet(a), TySet(b)) => if a == b { TySet(a) } else { TySet(None) }
        (TUnset, _) | (_, TUnset) => TUnset
      }
    }
  }
}

///|
pub fn resolve_ty_ref(
  def : @statedef.StateDef,
  t : @tscript.TyRef,
) -> @statedef.StateTy? {
  let args : Array[@statedef.StateTy] = []
  for a in t.args {
    // An argument that does not resolve leaves the whole reference with
    // nothing to be: `Array[Frobnicator]` is not a list of anything.
    guard resolve_ty_ref(def, a) is Some(r) else { return None }
    args.push(r)
  }
  def.resolve_ty(t.name, args)
}

///|
/// Resolve the type a `new` names, reporting a name that resolves to nothing
/// so that nothing below it reports again.
fn C::ty_ref(self : C, t : @tscript.TyRef) -> @statedef.StateTy? {
  match resolve_ty_ref(self.def, t) {
    Some(r) => Some(r)
    // A SIBLING component: `new TodoItem` beside `state TodoItem`. Opaque
    // rather than unknown — `TySet(None)` is what the target already means for
    // "a target whose type nothing here knows", and every read through it is
    // already refused on that basis. What is lost is "TodoItem has no field
    // `txet`", and getting it back means handing this checker every sibling's
    // schema rather than only its name.
    None if t.args.is_empty() && self.surface.comps.contains(t.name) => None
    None => {
      self.say(
        "NO_TYPE",
        "`\{t.to_source()}` is not a type the \{self.def.component} state declares" +
        (match
          @statedef.nearest(t.name, self.def.types.map(u => u.source_name)) {
          Some(s) => " — did you mean `\{s}`?"
          None =>
            "; declare it in the <script type=\"tutuca/spec\"> block, or write a built-in type"
        }),
        t.span,
      )
      None
    }
  }
}

///|
/// A condition, checked for being answerable as a boolean at all.
fn C::condition(self : C, e : @tutuca.Expr) -> Unit {
  match definite(self.expr(e)) {
    Some(t) =>
      if !is_boolish(t) {
        // The same finding `AlwaysTruthy` makes about a `@show` over a
        // container: `Value::is_truthy` answers true for a List, a Map and an
        // Obj unconditionally, so the test cannot fail.
        self.say(
          "ALWAYS_TRUE",
          "\{t.show_source()} is always truthy, so this condition never decides anything — test `empty?` of it, or a field of it",
          e.span(),
        )
      }
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Places

///|
/// Resolve a place to the type it addresses, or None when opaque.
fn C::place(
  self : C,
  p : @tutuca.Place,
  assigning~ : Bool,
) -> @statedef.StateTy? {
  let mut ty : @statedef.StateTy? = match p.root {
    PState(name) =>
      match self.def.field(name) {
        Some(f) => Some(f.ty)
        None => {
          self.say(
            "NO_FIELD",
            "`.\{name}` is not a field of the \{self.def.component} state" +
            (match @statedef.nearest(name, self.def.fields.map(f => f.name)) {
              Some(s) => " — did you mean `.\{s}`?"
              None => "; declare it in the <script type=\"tutuca/spec\"> block"
            }),
            p.span,
          )
          return None
        }
      }
    // The target: the one binding this block makes for itself, so the one
    // binding whose type is known here.
    PBind(name) if name == @tscript.target_bind =>
      match self.target {
        TySet(t) => t
        TUnset => {
          self.say(
            "NO_TARGET",
            "`@\{name}` holds what a `new` built, and no `new` has run here — write `new <Type>` above this",
            p.span,
          )
          return None
        }
      }
    PBind(name) => {
      if assigning && !self.binds_assignable {
        self.say(
          "BIND_ASSIGN",
          "`@\{name}` is a binding, and only `enrich` and `enrichScope` produce bindings — a handler assigns state, and `new` builds a value in `@\{@tscript.target_bind}`",
          p.span,
        )
      }
      // A binding comes from the SLOT that uses this declaration, which the
      // block cannot see. Opaque, and everything below it too.
      None
    }
    // A path into an argument. The root has to BE a parameter — a bare name
    // followed by an attached `.` is a path and nothing else, so a name that
    // is not one is a mistake rather than a call.
    PParam(name) => {
      // Unreachable through the parser, which refuses a statement that starts
      // with a path into an argument and says why. Kept because `Place` is one
      // type for reads and writes, and answering "not a place" is the only
      // honest thing this can say if some other producer builds one.
      if assigning {
        self.say(
          "PARAM_ASSIGN",
          "`\{name}` is a parameter — an argument is a value the caller handed over, not a place this component owns; assign to a `.field` instead",
          p.span,
        )
        return None
      }
      if !self.params.contains(name) {
        self.say(
          "NO_PARAM",
          "`\{name}` is not a parameter of `\{self.decl_name}`" +
          (match @statedef.nearest(name, self.params.keys().collect()) {
            Some(s) => " — did you mean `\{s}`?"
            None =>
              "; a path is only written on an argument, and `.\{name}` is how a state field is read"
          }),
          p.span,
        )
        return None
      }
      self.params.get(name).unwrap_or(None)
    }
  }
  for st in p.steps {
    match st {
      PField(name) =>
        ty = match ty {
          Some(t) =>
            match self.def.field_of(t, name) {
              Some(inner) => Some(inner)
              None => {
                self.say(
                  "NO_FIELD",
                  "`\{t.show_source()}` has no field `\{name}`",
                  p.span,
                )
                return None
              }
            }
          None => None
        }
      PIndex(key) => {
        self.expr(key) |> ignore
        ty = match ty {
          Some(t) =>
            match t.iterable_elem() {
              Some(inner) => Some(inner)
              None => {
                self.say(
                  "NOT_INDEXABLE",
                  "`\{t.show_source()}` is not a collection, so it has nothing to index",
                  p.span,
                )
                return None
              }
            }
          None => None
        }
      }
    }
  }
  ty
}

// ---------------------------------------------------------------------------
// Expressions

///|
fn C::expr(self : C, e : @tutuca.Expr) -> @statedef.StateTy? {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LNull => None
        LBool(_) => Some(TyBool)
        LNum(_) => Some(TyFloat)
        LStr(_) => Some(TyText)
      }
    ETpl(parts~, ..) => {
      for part in parts {
        match part {
          TExpr(inner) => self.expr(inner) |> ignore
          TText(..) => ()
        }
      }
      Some(TyText)
    }
    ERead(place~, ..) => self.place(place, assigning=false)
    // Opaque, and REPORTED — the two are not the same thing.
    //
    // Their TYPE is unknown, which is never wrong; their value in a body is
    // Null, which almost always is. Both sigils are answered by the render
    // stack, and a body runs after one — so `if $over { … }` takes the else
    // arm every time and says nothing, which is the worst way for a rule to be
    // false. The ahead-of-time backend refuses both by name
    // (`tscript/emit_mbt/emit.mbt`); this is the same refusal for the path
    // that has no compiler to do it.
    EMethod(name~, span~) => {
      self.render_only(name, sigil="$", span)
      None
    }
    // `*name` in a BODY is the handler-side twin of the same read in a view:
    // one question — what does this name mean here — answered along the same
    // `dyn`/`lex` route. `$name` stays render-only, because a `compute` really
    // is the render stack's answer and a body calls one bare instead.
    //
    // What is checked is that the name was DECLARED. Whether a producer is
    // above this component when it renders is a runtime fact; whether this
    // component ever asked for the name is not.
    EDyn(name~, span~) => {
      if !self.declares_dyn(name) {
        let known = self.dyn_names()
        self.say(
          "DYN_NOT_DECLARED",
          "`*\{name}` is a dynamic binding this component does not declare — add it to the `state` block's `lookup { … }`, or `provide { … }` it here" +
          (match @statedef.nearest(name, known) {
            Some(s) => " — did you mean `*\{s}`?"
            None =>
              if known.is_empty() {
                "; this component declares neither"
              } else {
                "; it declares " + known.map(n => "`*" + n + "`").join(", ")
              }
          }),
          span,
        )
      }
      None
    }
    // The two SUBSTITUTED sigils. Both are legal in view markup and neither is
    // legal here, for one reason said two ways: a macro is expanded at a call
    // site and a host binds its table before any of this is parsed, while a
    // `<script type="tutuca/script">` block is parsed ONCE for the component,
    // with no call site and no host around it. `parse_script` takes no context
    // at all, which is that fact in the signature.
    //
    // Refused by name rather than resolved to nothing: reading Null is what
    // this would otherwise do, and silently.
    EMacroVar(name~, span~) => {
      self.say(
        "NO_MACRO_FRAME",
        "`^\{name}` is a macro argument, and a block has no macro slots — a `<script type=\"tutuca/script\">` block is parsed once for the component, not once per call site. Read it in the view, where a macro frame exists, and pass it in as a handler argument or a field",
        span,
      )
      None
    }
    EConfigVar(name~, span~) => {
      self.say(
        "NO_CONFIG_FRAME",
        "`$$\{name}` is a value the host bound, substituted into view markup as it is parsed — and a block is compiled ahead of any host, so there is nothing here to substitute. Read it in the view and pass it in",
        span,
      )
      None
    }
    EName(name~, span~) => self.name(name, [], span)
    EApp(name~, args~, span~) => self.name(name, args, span)
    EUnary(op~, operand~, span~) =>
      match op {
        UNot => {
          self.condition(operand)
          Some(TyBool)
        }
        UNeg => {
          let t = self.expr(operand)
          match definite(t) {
            Some(inner) if !is_numeric(inner) =>
              self.say(
                "TYPE",
                "`-` negates a number, but this is \{inner.show_source()}",
                span,
              )
            _ => ()
          }
          t
        }
      }
    EChain(family~, operands~, span~, ..) => self.chain(family, operands, span)
    EIf(cond~, then_~, else_~, ..) => {
      self.condition(cond)
      let a = self.expr(then_)
      let b = self.expr(else_)
      // Both arms known and different: the value has no one type, so nothing
      // reading it can be checked. Reported rather than joined to opaque,
      // because an author who wrote two shapes meant one of them.
      match (a, b) {
        (Some(x), Some(y)) =>
          if x == y {
            a
          } else {
            self.say(
              "TYPE",
              "the two branches are \{x.show_source()} and \{y.show_source()}",
              else_.span(),
            )
            None
          }
        _ => None
      }
    }
    // A place is not a value, and the parser has already confined it to
    // `sendAt`'s first argument. Reaching here means an AST built by hand.
    ERef(..) => None
    // The three forms a SLOT produces and a block body cannot write: a bare
    // Uppercase name is a component type, a handler name is answered by the
    // render stack, and an `e.<path>` reads the event a view is handling.
    // Opaque here rather than reported, by the rule at the head of this file —
    // a body that somehow holds one has a type nobody declared, and unknown is
    // not wrong.
    ETypeName(..) | EHandlerName(..) | EEventPath(..) => None
  }
}

///|
/// Whether this component asked for `name`, either way round: a `lookup` names
/// what it wants, and a producer reads its own `provide` by the same spelling.
fn C::declares_dyn(self : C, name : String) -> Bool {
  self.def.lookup.iter().any(l => l.name == name) ||
  self.def.provide.iter().any(p => p.name == name)
}

///|
/// Every name a `*` may spell here, for the "did you mean".
fn C::dyn_names(self : C) -> Array[String] {
  let out : Array[String] = self.def.lookup.map(l => l.name)
  for p in self.def.provide {
    out.push(p.name)
  }
  out
}

///|
/// A `$name` written inside a body.
///
/// A `compute` or a `pred` IS callable from a body — bare, the way a condition
/// slot spells one — so the finding names the spelling that works.
///
/// `*name` used to share this rule and no longer does: a dynamic binding is
/// the one question a body CAN ask, because the two environments it walks are
/// the same two an intent's route walks and the host can answer both from a
/// handler's position. What a body still cannot do is call a `compute`,
/// because that really is the render stack's answer and there is no route to
/// it.
fn C::render_only(
  self : C,
  name : String,
  sigil~ : String,
  span : @tutuca.Span,
) -> Unit {
  let head = "`\{sigil}\{name}` is answered by the render stack, and a body runs after one, so it reads Null here"
  self.say(
    "RENDER_ONLY",
    head +
    (if self.callable.contains(name) {
      " — this block declares `\{name}`, so call it bare: `\{name}`"
    } else {
      match @statedef.nearest(name, self.callable.keys().collect()) {
        Some(s) =>
          " — did you mean the `pred` or `compute` `\{s}`, called bare?"
        None =>
          "; a `pred` or a `compute` is called bare from a body, and nothing here declares one by that name"
      }
    }),
    span,
  )
}

///|
/// A bare name, or a name applied to arguments.
fn C::name(
  self : C,
  name : String,
  args : Array[@tutuca.Expr],
  span : @tutuca.Span,
) -> @statedef.StateTy? {
  for a in args {
    self.expr(a) |> ignore
  }
  // A parameter, and it takes no arguments — applying one is what a reader
  // would otherwise have to work out from the arity table.
  if self.params.contains(name) {
    if !args.is_empty() {
      self.say(
        "NOT_CALLABLE",
        "`\{name}` is a parameter, so it takes no arguments",
        span,
      )
      return None
    }
    return self.params.get(name).unwrap_or(None)
  }
  // A builtin: arity is checked, and the result type is what the vocabulary
  // says it is.
  if @tscript.script_builtin(name) is Some(arity) {
    if args.length() != arity {
      self.say(
        "ARITY",
        "`\{name}` takes \{arity} argument(s), not \{args.length()}",
        span,
      )
      return None
    }
    return builtin_result(name)
  }
  // A predicate or a compute this block declares.
  if self.callable.get(name) is Some(want) {
    if args.length() != want {
      self.say(
        "ARITY",
        "`\{name}` takes \{want} argument(s), not \{args.length()}",
        span,
      )
    }
    // A `pred` answers Bool; a `compute` answers whatever its body does, and
    // asking would mean ordering the declarations. Opaque is the honest
    // answer and costs nothing, since nothing downstream needs it yet.
    return None
  }
  let mut choices = self.params.keys().collect()
  choices = choices +
    @tscript.script_builtin_names() +
    self.callable.keys().collect()
  self.say(
    "NO_NAME",
    "nothing here is called `\{name}`" +
    (match @statedef.nearest(name, choices) {
      Some(s) => " — did you mean `\{s}`?"
      None =>
        "; a bare name is a parameter, a builtin, or a `pred` or `compute` this block declares"
    }),
    span,
  )
  None
}

///|
/// A chain of operands joined by one family's operators.
fn C::chain(
  self : C,
  family : @tutuca.OpFamily,
  operands : Array[@tutuca.Expr],
  span : @tutuca.Span,
) -> @statedef.StateTy? {
  let types = operands.map(o => self.expr(o))
  match family {
    FLogic | FImplies => {
      for i, t in types {
        match definite(t) {
          Some(ty) if !is_boolish(ty) =>
            self.say(
              "ALWAYS_TRUE",
              "\{ty.show_source()} is always truthy, so this operand never decides anything",
              operands[i].span(),
            )
          _ => ()
        }
      }
      Some(TyBool)
    }
    FCompare => {
      // Both sides known and different: comparing them can only ever answer
      // one way, which is not what the author wrote it for.
      match
        (
          definite(types.get(0).unwrap_or(None)),
          definite(types.get(1).unwrap_or(None)),
        ) {
        (Some(a), Some(b)) =>
          if !comparable(a, b) {
            self.say(
              "TYPE",
              "\{a.show_source()} and \{b.show_source()} are never equal, so this comparison has one answer",
              span,
            )
          }
        _ => ()
      }
      Some(TyBool)
    }
    FAdd | FMul => {
      // `+` concatenates two strings and adds two numbers; the operands'
      // static types decide, and a mixed pair is an error rather than a
      // coercion. Everything else is arithmetic only.
      let all_text = types.iter().all(t => t is Some(TyText))
      if family is FAdd && all_text && !types.is_empty() {
        return Some(TyText)
      }
      for i, t in types {
        match definite(t) {
          Some(ty) if !is_numeric(ty) =>
            self.say(
              "TYPE",
              "arithmetic needs a number, but this is \{ty.show_source()}",
              operands[i].span(),
            )
          _ => ()
        }
      }
      Some(TyFloat)
    }
  }
}

// ---------------------------------------------------------------------------
// The type rules

///|
/// The result of a reading builtin. `None` where the vocabulary genuinely
/// cannot say — `min`/`max`/`clamp` answer whatever they were given, and
/// pretending they answer `f64` would make `int .n` look like a widening.
fn builtin_result(name : String) -> @statedef.StateTy? {
  match name {
    "empty?" | "truthy?" | "falsy?" | "null?" | "has" | "contains" =>
      Some(TyBool)
    "len" | "int" => Some(TyInt(width=32, signed=true))
    "num" => Some(TyFloat)
    "str" | "lower" | "upper" | "trim" => Some(TyText)
    _ => None
  }
}

///|
/// Narrow a type to one worth checking against.
///
/// `any` is a DECLARED type and an opaque value at the same time — it is the
/// dynamic escape hatch inside a typed struct — so every rule below has to
/// treat it the way it treats a `$method` result. Doing that here rather than
/// in each rule is what stops one of them from forgetting.
fn definite(t : @statedef.StateTy?) -> @statedef.StateTy? {
  match t {
    Some(TyAny) => None
    other => other
  }
}

///|
fn is_numeric(t : @statedef.StateTy) -> Bool {
  t is (TyInt(..) | TyFloat)
}

///|
/// Whether a value of this type can answer a yes/no question usefully.
///
/// The same rule `StateTy::is_boolish` states, and reached through it so the
/// two cannot drift: a List, a Map and an Obj are truthy unconditionally, so a
/// condition over one never decides anything. Strings and numbers stay
/// boolish on purpose — `@show=".role"` beside `@text=".role"` is idiomatic.
fn is_boolish(t : @statedef.StateTy) -> Bool {
  t.is_boolish()
}

///|
/// Whether two types can hold equal values.
///
/// The integer/float pair is deliberately comparable: `Value` has one
/// `Num(Double)`, so an `s32` and an `f64` are the same runtime shape and
/// `.count is 2` must not be a type error.
fn comparable(a : @statedef.StateTy, b : @statedef.StateTy) -> Bool {
  if a == b {
    return true
  }
  if is_numeric(a) && is_numeric(b) {
    return true
  }
  // An `any` field holds whatever it was given, and an enum is a string at
  // runtime, so both compare against anything the author means them to.
  a is (TyAny | TyEnum(_)) || b is (TyAny | TyEnum(_))
}

///|
/// Whether a known value type fits a known assignment target.
fn assignment_types_fit(
  want : @statedef.StateTy,
  got : @statedef.StateTy,
) -> Bool {
  match (want, got) {
    // A present value fills an optional slot; `null` has no definite type and
    // is accepted by the caller before reaching this helper.
    (TyOption(inner), _) => assignment_types_fit(inner, got)
    // One numeric surface: assigning into an `s32` truncates and range-checks
    // against the same bounds the generated decode already applies, and fails
    // — no change — outside them. That is a runtime answer, not a type error.
    (TyInt(..) | TyFloat, TyInt(..) | TyFloat) => true
    // An enum is a string at runtime, so a computed string can name a case.
    (TyEnum(_), TyText) => true
    _ => want == got
  }
}

///|
/// Whether `got` may be written where `want` is expected.
fn C::assignable(
  self : C,
  want : @statedef.StateTy?,
  got : @statedef.StateTy?,
  span : @tutuca.Span,
) -> Unit {
  guard definite(want) is Some(w) && definite(got) is Some(g) else { return }
  if !assignment_types_fit(w, g) {
    self.say(
      "TYPE",
      "this place is \{w.show_source()}, but the value is \{g.show_source()}",
      span,
    )
  }
}

///|
/// Whether a collection method fits the field it is called on.
fn C::method_fits(
  self : C,
  call : String,
  t : @statedef.StateTy,
  span : @tutuca.Span,
) -> Unit {
  guard definite(Some(t)) is Some(t) else { return }
  let ok = match call {
    // The set operations, over open and closed membership alike.
    "add" | "remove" | "toggle" => t is (TySet | TyFlags(_, _))
    // The sequence operations. A map is keyed rather than ordered, so it takes
    // the keyed half and not `push`.
    "push" | "insertAt" => t is TyList(_)
    "setAt" | "deleteAt" => t is (TyList(_) | TyOMap(_))
    _ => true
  }
  if !ok {
    self.say(
      "NO_METHOD",
      "`\{call}` does not apply to \{t.show_source()}",
      span,
    )
  }
}

///|
fn assign_word(op : @tscript.AssignOp) -> String {
  op.word()
}

///|
/// The spec block's `pred`s and `invariant`s, as declarations a backend can
/// walk like any other.
///
/// Synthesised rather than handled separately, because a rule IS a `Decl` in
/// every way that matters downstream — a name, no parameters, one expression,
/// an optional sentence — and giving it a second path through a backend would
/// mean the rule table, the contract guards and the value bodies each learning
/// about two kinds of rule that behave identically.
///
/// Here rather than in either backend, because BOTH need it and they must not
/// drift: two backends reporting different names for the same broken state are
/// two backends that disagree. This package is where a declaration meets the
/// schema it is about, which is exactly the join a rule needs.
///
/// A rule whose name the SCRIPT block also declares is skipped, so the
/// deprecation window changes nothing about what a file already compiles to:
/// moving a rule is deleting the old copy, and until it is deleted the old copy
/// is what runs. `check` reports the pair as `RULE_IN_BOTH`, which is where the
/// author is told rather than here.
///
/// The second answer is the names whose body did not parse. The caller reports
/// them in its own vocabulary — `check` has already said so properly, with a
/// span in the spec block, and a second wording of one failure is worse than
/// none.
pub fn rule_decls(
  def : @statedef.StateDef,
  decls : Array[@tscript.Decl],
) -> (Array[@tscript.Decl], Array[String]) {
  let out : Array[@tscript.Decl] = []
  let unreadable : Array[String] = []
  for r in def.rules {
    if decls.iter().any(d => @tscript.is_predicate(d.kind) && d.name == r.name) {
      continue
    }
    // Spec-block spans, which are positions in a DIFFERENT block from the one
    // every other span on a `Decl` comes from. They reach only a backend's
    // refusal hint, which reports by name; nothing rebases them onto a file.
    let at : @tutuca.Span = {
      start: r.source_span.start,
      end_: r.source_span.end_,
    }
    let body = Some(@tscript.parse_expr_source(r.source)) catch { _ => None }
    guard body is Some(body) else {
      unreadable.push(r.name)
      continue
    }
    // A sentence that cannot be evaluated is DROPPED and the rule still holds:
    // a refusal that cannot describe itself is still a refusal.
    let format = if r.format == "" {
      None
    } else {
      Some(@tscript.parse_expr_source(r.format)) catch {
        _ => None
      }
    }
    out.push({
      kind: if r.kind is RInvariant {
        DInvariant
      } else {
        DPred
      },
      name: r.name,
      params: [],
      requires_: None,
      ensures_: None,
      format,
      body: Value(body),
      doc: r.doc.unwrap_or(""),
      span: at,
      name_span: { start: r.name_span.start, end_: r.name_span.end_, },
    })
  }
  (out, unreadable)
}
