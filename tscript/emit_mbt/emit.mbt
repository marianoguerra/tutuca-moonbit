// The MoonBit backend. Implements the declares in spec.mbt.
//
// Every expression is emitted with the LANGUAGE type it has, and conversion
// happens where a value meets a declared type — `to_double()` on the way out
// of an integer field, `to_int()` on the way in. Doing it that way rather than
// tracking MoonBit types directly is what makes this backend agree with the
// interpreter without either consulting the other: the interpreter's `Value`
// has one number, so a language that rounds at the boundary and one that has
// only Doubles round the same expression the same way.
//
// Failure is `return None`, everywhere, for the same reason it is `no change`
// in the interpreter: it is the contract `update` already has.

///|
/// One declaration's compilation, or the reason it did not compile.
priv suberror NoWay {
  Cannot(String)
}

///|
priv struct E {
  def : @statedef.StateDef
  /// The generated state struct's name. Needed by `spread`, for the one
  /// literal that carries no `..s` to infer from.
  state_ty : String
  /// Parameter name -> its language type, or None for a raw `@tutuca.Value`.
  mut params : Map[String, @statedef.StateTy?]
  /// Statements the current one needs FIRST — a bounds check, a divisor
  /// test. They answer `Unchanged`, which is what "the arm claimed the name
  /// and there was nothing to do" means, and it is the answer the interpreter
  /// gives for the same input.
  ///
  /// Collected on the way down and flushed by `stmt`, because a guard is a
  /// statement and the thing that needs it is an expression.
  mut prelude : Array[String]
  /// Whether any arm that SURVIVED reached for `ctx`. A block of pure state
  /// transitions names the parameter `_ctx`, because a generated file must not
  /// be the thing that warns.
  mut uses_ctx : Bool
  /// Whether THIS body reached for the render stack — a `*name`, or a sibling
  /// call that may contain one.
  ///
  /// Per BODY, unlike `uses_ctx`, which names one parameter of the ONE
  /// transition function every arm shares. Treating the two as one flag is
  /// half of why a `*name` in a value body used to emit a free `ctx`.
  mut uses_stack : Bool
  /// Whether any arm of the transition function READS the state parameter.
  ///
  /// A one-field state rebinds with a whole record literal rather than
  /// `{ ..s, … }`, so a handler that only assigns can leave the parameter
  /// untouched — and a generated file must not be the thing that warns. Set
  /// wherever the emitter writes an expression over `s`, and read once, at the
  /// signature.
  mut uses_state : Bool
  /// Which function is being written: a transition, which is handed a
  /// `&@tutuca.Ctx`, or one of the four value bodies, which are handed the
  /// state and the row and a `&@tutuca.Stack`.
  ///
  /// Not derivable from `fail` or `leave`: `fail` is "" for the enrich roles
  /// AND for a transition, so it says something else.
  mut in_value_body : Bool
  /// `@name` -> the MoonBit expression that reads it, for the bodies that have
  /// bindings at all. A `@when` gets the loop's three; an `enrich` gets those
  /// plus whatever it has written into the binds map.
  mut binds : Map[String, String]
  /// The binds map's parameter name inside an `enrich`, or "" — the one body
  /// shape that may WRITE a binding, and read one it wrote.
  mut binds_map : String
  /// What a value body returns when a guard does not hold — `false` for a
  /// `@when`, `Null` for a method — or "" inside a transition, where the
  /// existing `Unchanged` idiom already covers it and a guard on an opaque
  /// value is still refused.
  mut fail : String
  /// What a runtime guard returns to LEAVE this body early: `Unchanged` in a
  /// transition, `Null` for a method, `false` for a `@when` — the same three
  /// answers `fail` spells, plus the one `fail` cannot say, because a
  /// transition leaves through `Unchanged` while `fail` stays empty there so
  /// opaque coercions keep being refused rather than guarded.
  ///
  /// "" means leaving early is not EXPRESSIBLE: an enricher writes into a map
  /// it was handed as it goes, so a return keeps the writes already made and
  /// drops the rest. A construct whose guard needs the door (`/`, `mod`,
  /// the bounds-checked collection methods) is refused there instead of
  /// miscompiled — see `leave_token`.
  mut leave : String
  /// Every name this component has an arm for, so an `intent` can be told
  /// which of the three outcomes its sender is waiting for.
  ///
  /// A sender expects an answer if and only if its schema declares
  /// `<name>Ok`, `<name>Error` or `<name>Unhandled` — three separately named
  /// outcomes, each with its own payload, and each an ordinary addressed
  /// message when it lands. This set is the schema's `receive` variant PLUS
  /// the block's own message
  /// declarations, because both are arms and the rule is about having one —
  /// and because a block may answer a name the schema does not carry, now that
  /// a `receive` can take its types from the views.
  answer_arms : Set[String]
  /// A counter for the temporaries those guards bind, and what is already
  /// bound: reading `q` twice is one guard, not two.
  mut tmp : Int
  mut guards : Map[String, String]
  /// The block's own callables, name -> the emitted function that answers it.
  /// This is what lets one body call another: `compute status { if over { … } }`
  /// is a call, and a bare name is where the reader expects one.
  callables : Map[String, String]
  /// The block's rules, name -> the one expression a `pred` or an `invariant`
  /// is. What a `requires` / `ensures` clause resolves to, and what an arm
  /// inlines at the two moments a contract is kept.
  rules : Map[String, @tutuca.Expr]
  /// The rules that declare a `format`, name -> the sentence expression.
  /// Compiled INTO the refusal, beside the rule and at the same moment, so the
  /// values it names are the ones that made the rule false.
  formats : Map[String, @tutuca.Expr]
  /// The `invariant` names, every one of them checked after every transition.
  /// Sorted, because WHICH rule broke is part of the answer and the
  /// interpreter — which reads them off a map and has no declaration order to
  /// read — sorts too. Two backends reporting different names for the same
  /// broken state are two backends that disagree.
  invariants : Array[String]
  /// The temporary the active `new` bound, and its type — what `@cur` reads
  /// and writes here. None until a `new` runs, and again after a branch whose
  /// arm bound one, because a `let` inside the branch expression does not
  /// outlive it.
  mut target : (String, @statedef.StateTy)?
  /// A counter for those temporaries, so two `new`s in one body do not shadow.
  mut target_n : Int
}

///|
pub fn emit(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  state_ty~ : String,
  fn_name~ : String,
  prefix? : String = "",
  roles? : Roles = Roles::none(),
  surface? : @check.Surface = @check.Surface::empty(),
) -> Emitted {
  // The SPEC block's rules, as declarations, ahead of the block's own.
  //
  // Synthesised rather than handled separately, because a rule is a `Decl` in
  // every way that matters here — a name, no parameters, one expression, an
  // optional sentence — and giving it a second path through this file would
  // mean `callables`, `rules`, `formats`, `invariants` and `value_bodies` each
  // learning about two kinds of rule that behave identically.
  let refusals : Array[Refusal] = []
  let (spec_rules, unreadable) = @check.rule_decls(def, decls)
  for name in unreadable {
    refusals.push({
      name,
      why: "its body is not an expression this backend can read",
      span: @tscript.no_span,
    })
  }
  let decls = spec_rules + decls
  // Every name this component has an arm for, gathered before the walk for the
  // same reason `callables` is: a body above a declaration still needs it.
  let answer_arms : Set[String] = Set([])
  for m in def.receive {
    answer_arms.add(m.name)
  }
  for d in decls {
    if d.kind is DReceive {
      answer_arms.add(d.name)
    }
  }
  let e = E::{
    def,
    answer_arms,
    state_ty,
    params: Map([]),
    prelude: [],
    uses_ctx: false,
    uses_stack: false,
    uses_state: false,
    in_value_body: false,
    binds: Map([]),
    binds_map: "",
    fail: "",
    leave: "Unchanged",
    tmp: 0,
    guards: Map([]),
    rules: Map([]),
    formats: Map([]),
    invariants: [],
    callables: Map([]),
    target: None,
    target_n: 0,
  }
  let arms : Array[String] = []
  // Two buckets, and THREE lists: the `Receive` bucket has two enums over it,
  // because a name a VIEW writes is typed from its call sites and a name the
  // SCHEMA declares is typed from the declaration. One dispatch bucket, two
  // sources of truth about the payload, so the generator needs to know which
  // half each answered name came from in order to trim the right enum.
  let answers : Map[String, Array[String]] = {
    "Input": [],
    "Receive": [],
    "Intent": [],
  }
  // Every callable the block declares, so a body can call its siblings. Filled
  // before the walk because declaration order is not call order: `compute
  // status { if over { … } }` may sit above the `pred` it asks.
  for d in decls {
    if d.kind is (DPred | DCompute | DInvariant) && prefix != "" {
      e.callables[d.name] = value_fn_name(prefix, RMethod, d.name)
    }
    // The rules, by name, as EXPRESSIONS rather than as calls. A contract is
    // compiled INTO the arm that carries it: the same `pred` asked before a
    // body reads the state it arrived with and asked after it reads the
    // successor, and `s` is already both of those at the two points where the
    // check goes. Routing through the generated method instead would mean
    // emitting a function the views never asked for, and refusing the arm when
    // that function turned out not to compile.
    if @tscript.is_predicate(d.kind) && d.body is Value(rule) {
      e.rules[d.name] = rule
      if d.format is Some(sentence) {
        e.formats[d.name] = sentence
      }
      if d.kind is DInvariant {
        e.invariants.push(d.name)
      }
    }
  }
  e.invariants.sort()
  for d in decls {
    let bucket = match d.kind {
      DReceive => "Receive"
      DIntent => "Intent"
      // A `compute`, a `pred`, an `enrich`: not a transition, so not this
      // function's business. They are compiled below, into one function each,
      // because what answers them is a different bucket rather than nothing.
      _ => continue
    }
    e.params = Map([])
    let before = e.uses_ctx
    let arm = e.arm(d, bucket, surface) catch {
      Cannot(why) => {
        // A refused arm is not emitted, so whatever it reached for does not
        // count towards what the function's parameters are used for.
        e.uses_ctx = before
        refusals.push({ name: d.name, why, span: d.span, })
        continue
      }
    }
    arms.push(arm)
    // A `receive` the schema declares trims `<T>Receive`; one only the views
    // write trims `<T>Msg`. `"Input"` is the key that half still goes under —
    // the bucket is gone, the DISTINCTION is not.
    let key = if bucket == "Receive" && e.declared_msg(d) is None {
      "Input"
    } else {
      bucket
    }
    answers.get(key).unwrap().push(d.name)
  }
  let source = if arms.is_empty() {
    ""
  } else {
    let b = StringBuilder()
    b.write_string("///|\n")
    b.write_string(
      "/// The dispatches the `<script type=\"tutuca/script\">` block answers.\n",
    )
    b.write_string("///\n")
    b.write_string(
      "/// Composed AHEAD of the author's `update~`, which stays optional and is\n",
    )
    b.write_string(
      "/// consulted only for a name this does not answer. GENERATED — edit the\n",
    )
    b.write_string("/// block, not this.\n")
    b.write_string(
      "fn \{fn_name}(\n  \{if e.uses_state { "s" } else { "_s" }} : \{state_ty},\n  msg : @component.Dispatch,\n  \{if e.uses_ctx { "ctx" } else { "_ctx" }} : &@tutuca.Ctx,\n) -> @component.Update[\{state_ty}] {\n",
    )
    b.write_string("  match msg {\n")
    for a in arms {
      b.write_string(a)
    }
    // Every other name falls through, which is the documented precedence: the
    // author's `update`, then the generated mutators.
    b.write_string("    _ => Unhandled\n")
    b.write_string("  }\n}\n")
    b.to_string()
  }
  // The value bodies: `compute` and `pred` as methods, a `pred` again as a
  // `@when` when the views use it that way, and the two enrichers. One
  // function each, so a body that calls a sibling calls a function.
  let values = e.value_bodies(decls, prefix, roles, refusals)
  let setters = e.property_setters(decls, prefix, surface, refusals)
  {
    source: source + values.source + setters.source,
    answers_input: answers.get("Input").unwrap(),
    answers_receive: answers.get("Receive").unwrap(),
    answers_intent: answers.get("Intent").unwrap(),
    answers_methods: values.methods,
    answers_whens: values.whens,
    answers_enriches: values.enriches,
    answers_enrich_scopes: values.enrich_scopes,
    answers_property_get: values.property_get,
    answers_property_set: setters.names,
    refusals,
  }
}

///|
pub fn Roles::none() -> Roles {
  { methods: [], whens: [], enriches: [], enrich_scopes: [], }
}

///|
pub fn value_fn_name(prefix : String, role : Role, name : String) -> String {
  let infix = match role {
    RMethod => "compute"
    RWhen => "when"
    REnrich => "enrich"
    REnrichScope => "enrich_scope"
  }
  "\{prefix}_\{infix}_\{name}"
}

///|
pub fn property_set_fn_name(prefix : String, name : String) -> String {
  "\{prefix}_property_set_\{name}"
}

///|
/// What one pass over the value bodies produced.
priv struct Values {
  source : String
  methods : Array[String]
  whens : Array[String]
  enriches : Array[String]
  enrich_scopes : Array[String]
  property_get : Array[String]
}

///|
/// Compile every value body the caller asked for, in the roles it asked for.
///
/// A refusal is per NAME AND ROLE, because the same `pred` can compile as a
/// `@when` — where `@value` is a parameter — and be refused as a method, where
/// it is nothing at all. Both are true statements about the same declaration.
fn E::value_bodies(
  self : E,
  decls : Array[@tscript.Decl],
  prefix : String,
  roles : Roles,
  refusals : Array[Refusal],
) -> Values {
  let out = Values::{
    source: "",
    methods: [],
    whens: [],
    enriches: [],
    enrich_scopes: [],
    property_get: [],
  }
  if prefix == "" {
    return out
  }
  let b = StringBuilder()
  fn take(
    d : @tscript.Decl,
    role : Role,
    wanted : Array[String],
    into : Array[String],
  ) -> Unit {
    if !wanted.contains(d.name) {
      return
    }
    let src = self.value_body(d, role, prefix) catch {
      Cannot(why) => {
        refusals.push({ name: d.name, why, span: d.span, })
        return
      }
    }
    b.write_string(src)
    into.push(d.name)
  }

  for d in decls {
    match d.kind {
      // An `invariant` is a `pred` with a role, and every USE a `pred` has it
      // has too: a badge reading `$conserved` and a `@when="conserved"` are
      // asking the rule the same question the transitions ask it.
      // An `invariant` gets its method body whether or not a view asks for
      // one. Every other value body waits to be NAMED — a `compute` no view
      // reads is a function nobody could call — but an invariant is the
      // COMPONENT's rather than a view's: the runtime asks it after every
      // dispatch, including the ones no view raised, so its existence cannot
      // depend on a template mentioning it.
      DInvariant => {
        take(d, RMethod, roles.methods + [d.name], out.methods)
        take(d, RWhen, roles.whens, out.whens)
      }
      DCompute | DPred => {
        take(d, RMethod, roles.methods, out.methods)
        if @tscript.is_predicate(d.kind) {
          take(d, RWhen, roles.whens, out.whens)
        }
      }
      DGet => take(d, RMethod, [d.name], out.property_get)
      DEnrich => take(d, REnrich, roles.enriches, out.enriches)
      DEnrichScope =>
        take(d, REnrichScope, roles.enrich_scopes, out.enrich_scopes)
      _ => ()
    }
  }
  { ..out, source: b.to_string(), }
}

///|
priv struct PropertySetters {
  source : String
  names : Array[String]
}

///|
fn E::property_setters(
  self : E,
  decls : Array[@tscript.Decl],
  prefix : String,
  surface : @check.Surface,
  refusals : Array[Refusal],
) -> PropertySetters {
  let source = StringBuilder()
  let names : Array[String] = []
  if prefix == "" {
    return { source: "", names, }
  }
  for d in decls {
    guard d.kind is DSet else { continue }
    self.params = Map([])
    self.prelude = []
    self.tmp = 0
    self.guards = Map([])
    self.target = None
    let before_ctx = self.uses_ctx
    let arm = self.arm(d, "Receive", surface) catch {
      Cannot(why) => {
        self.uses_ctx = before_ctx
        refusals.push({ name: d.name, why, span: d.span, })
        continue
      }
    }
    if self.uses_ctx != before_ctx {
      self.uses_ctx = before_ctx
      refusals.push({
        name: d.name,
        why: "a property setter is synchronous and pure, so it cannot use component effects or context",
        span: d.span,
      })
      continue
    }
    let fn_name = property_set_fn_name(prefix, d.name)
    source.write_string(
      "///|\nfn \{fn_name}(s : \{self.state_ty}, value : @tutuca.Value) -> @component.Update[\{self.state_ty}] {\n" +
      "  match (@component.Receive(\{quote(d.name)}, [value]) : @component.Dispatch) {\n" +
      arm +
      "    _ => Unhandled\n" +
      "  }\n" +
      "}\n\n",
    )
    names.push(d.name)
  }
  { source: source.to_string(), names, }
}

///|
/// One value body, as a whole function.
///
/// The four roles differ in exactly two ways — what is in scope, and what
/// comes back — so they share everything else, including the expression
/// compiler that also writes the transitions. That sharing is the point: a
/// `pred` used in a `@show` and the same `pred` used in an `@when` must answer
/// the same question, and here they cannot drift because they are one body
/// compiled twice.
fn E::value_body(
  self : E,
  d : @tscript.Decl,
  role : Role,
  prefix : String,
) -> String raise NoWay {
  self.params = Map([])
  self.binds = Map([])
  self.binds_map = ""
  self.prelude = []
  self.tmp = 0
  self.guards = Map([])
  // A target belongs to the body that built it, here as everywhere else.
  self.target = None
  // Which function this is, and what it has asked of it so far. Both per
  // BODY: the four signatures below carry a `&@tutuca.Stack` and no `ctx`.
  self.in_value_body = true
  self.uses_stack = false
  // What "this value is not that shape" answers, per role. The interpreter
  // answers None and the caller reads it as nothing happened; these are the
  // same statement in each signature.
  self.fail = match role {
    RMethod => "Null"
    RWhen => "false"
    // An enricher writes into a map it was handed, and the interpreter drops
    // every write when a body cannot finish. Leaving early would keep the ones
    // already made, so nothing here guards: an opaque value used at a type is
    // refused instead, and the refusal names the enricher.
    REnrich | REnrichScope => ""
  }
  // The same three answers, read as the door a runtime guard walks out
  // through — including the transition's `Unchanged`, which `fail` leaves
  // empty for. An enricher gets "" too: there is no door, so anything that
  // needs one is refused (see `leave_token`).
  self.leave = match role {
    RMethod => "Null"
    RWhen => "false"
    REnrich | REnrichScope => ""
  }
  let name = value_fn_name(prefix, role, d.name)
  // A body that calls a sibling passes `s` to it, so it reads the state even
  // when no `.field` appears in it.
  let s_used = decl_reads_state(d) || self.decl_calls_sibling(d)
  let sp = if s_used { "s" } else { "_s" }
  // The BODY first, the header after. Whether this function needs its `stack`
  // parameter is only known once the body has been compiled — a `*name` sets
  // it, and so does a sibling call that may contain one — and a generated file
  // must not be the thing that warns about an unused parameter.
  let body = StringBuilder()
  let params : Array[String] = [sp + " : " + self.state_ty]
  match role {
    RMethod => {
      // The arguments a `$name` call site passes. Their types are not known
      // here — nothing declares what a slot hands a method — so they bind raw,
      // and a typed use of one is refused exactly as it is in an `on` handler
      // the views call inconsistently.
      let args_used = d.params.length() > 0 && decl_reads_params(d)
      params.push(
        "\{if args_used { "args" } else { "_args" }} : Array[@tutuca.Value]",
      )
      for i, prm in d.params {
        self.params[prm.name] = None
        if decl_reads_name(d, prm.name) {
          body.write_string(
            "  let \{local_of(prm.name)} = args.get(\{i}).unwrap_or(Null)\n",
          )
        }
      }
      let (src, ty) = self.value_of_body(d)
      body.write_string(self.flush("  "))
      body.write_string("  \{self.value_of(src, ty)}\n")
    }
    RWhen => {
      // The loop's own three, as the renderer passes them. `iterData` is the
      // one a body reads least, and every one of them is named with the
      // underscore when it is not read at all.
      let (kp, vp, ip) = self.bind_params(d)
      params.push("\{kp} : @tutuca.Value")
      params.push("\{vp} : @tutuca.Value")
      params.push("\{ip} : @tutuca.Value")
      guard d.body is Value(e) else {
        raise Cannot("a `@when` is one expression, not statements")
      }
      let cond = self.at_bool(e)
      body.write_string(self.flush("  "))
      body.write_string("  \{cond}\n")
    }
    REnrich => {
      let (kp, vp, ip) = self.bind_params(d)
      self.binds_map = "binds"
      params.push("binds : Map[String, @tutuca.Value]")
      params.push("\{kp} : @tutuca.Value")
      params.push("\{vp} : @tutuca.Value")
      params.push("\{ip} : @tutuca.Value")
      body.write_string(self.enrich_stmts(d, "  "))
    }
    REnrichScope => {
      self.binds_map = "binds"
      body.write_string("  let binds : Map[String, @tutuca.Value] = Map([])\n")
      body.write_string(self.enrich_stmts(d, "  "))
      body.write_string("  binds\n")
    }
  }
  // The environment, last in every role. A value body is called BY the render
  // stack, and `*name` is the one question it has for it — so the parameter is
  // there whether or not this body asks, and named `_stack` when it does not.
  params.push(
    "\{if self.uses_stack { "stack" } else { "_stack" }} : &@tutuca.Stack",
  )
  let ret = match role {
    RMethod => "@tutuca.Value"
    RWhen => "Bool"
    REnrich => "Unit"
    REnrichScope => "Map[String, @tutuca.Value]"
  }
  let b = StringBuilder()
  b.write_string("///|\n")
  b.write_string("/// `\{@tscript.kind_word(d.kind)} \{d.name}` from the ")
  // Which block it came from. A rule lives in the spec block and everything
  // else in the script block, and a generated comment that pointed at the
  // wrong one would send a reader to edit a file that does not hold it.
  let block = if self.def.rule(d.name) is Some(_) { "spec" } else { "script" }
  b.write_string(
    "`<script type=\"tutuca/\{block}\">` block. GENERATED — edit\n",
  )
  b.write_string("/// the block, not this.\n")
  b.write_string("fn \{name}(\{params.join(", ")}) -> \{ret} {\n")
  b.write_string(body.to_string())
  b.write_string("}\n\n")
  b.to_string()
}

///|
/// The guards an expression needed, as lines, and then forgotten.
fn E::flush(self : E, pad : String) -> String {
  let out = self.prelude.map(g => "\{pad}\{g}\n").join("")
  self.prelude = []
  out
}

///|
/// The loop's binding parameters, each named with a leading underscore when
/// the body does not read it — a generated file must not be the thing that
/// warns.
fn E::bind_params(self : E, d : @tscript.Decl) -> (String, String, String) {
  let out : Array[String] = []
  for pair in [("key", "key"), ("value", "value"), ("iter", "iter_data")] {
    let read = decl_reads_bind(d, pair.0)
    let param = if read { pair.1 } else { "_" + pair.1 }
    if read {
      self.binds[pair.0] = param
    }
    out.push(param)
  }
  (out[0], out[1], out[2])
}

///|
/// The one expression a `compute` or a `pred` is, with its type.
fn E::value_of_body(
  self : E,
  d : @tscript.Decl,
) -> (String, @statedef.StateTy) raise NoWay {
  guard d.body is Value(e) else {
    raise Cannot("a `compute` and a `pred` are one expression, not statements")
  }
  // NOT coerced to a Bool, even for a `pred`. The interpreter answers a
  // `pred`'s own expression — `pred named { .name }` reads back "ada" — and
  // the truthiness is applied by whatever ASKED: a condition slot, or the
  // `@when` role below, which is the one place the bucket's signature makes it
  // a Bool. Boxing it here made `<x text="$named">` print "true" in a compiled
  // component and "ada" in a card, which the corpus caught on the first run.
  self.expr(e)
}

///|
/// An enricher's statements, which write bindings rather than state.
fn E::enrich_stmts(
  self : E,
  d : @tscript.Decl,
  pad : String,
) -> String raise NoWay {
  guard d.body is Stmts(body) else {
    raise Cannot("an enricher is statements, not one expression")
  }
  let b = StringBuilder()
  for st in body {
    guard st is SAssign(place~, op~, value~, ..) else {
      raise Cannot(
        "an enricher may only assign bindings — `@name = …` — and this is not one",
      )
    }
    guard place.root is PBind(bind) else {
      raise Cannot("an enricher writes `@name`, not state")
    }
    guard place.steps.is_empty() else {
      raise Cannot(
        "`@\{bind}` is written whole; a path into one is not compiled",
      )
    }
    guard op is ASet else {
      raise Cannot(
        "a binding is assigned with `=`; `+=` needs one to already be there",
      )
    }
    let src = self.as_value(value)
    b.write_string("\{pad}\{self.binds_map}[\{quote(bind)}] = \{src}\n")
    // Written, so readable below it — the interpreter threads the same map.
    self.binds[bind] = "\{self.binds_map}.get(\{quote(bind)}).unwrap_or(Null)"
  }
  b.to_string()
}

///|
/// One match arm.
fn E::arm(
  self : E,
  d : @tscript.Decl,
  bucket : String,
  surface : @check.Surface,
) -> String raise NoWay {
  guard d.body is Stmts(body) else {
    raise Cannot("a value body is not a transition")
  }
  // A target belongs to the body that built it: an arm never starts holding
  // one the arm above it left behind.
  self.target = None
  // An arm is written into the shared transition function, which is handed a
  // `&@tutuca.Ctx`. Stated rather than inherited: leaving it implicit is what
  // let a value body emit `ctx.lookup` into a signature that had no `ctx`.
  self.in_value_body = false
  let b = StringBuilder()
  // `_args` when the declaration takes none: a generated file must not be the
  // thing that warns.
  let args_binder = if d.params.is_empty() { "_args" } else { "args" }
  b.write_string(
    "    \{bucket}(\{quote(self.wire_name(d))}, \{args_binder}) => {\n",
  )
  // Parameters, decoded from the dispatch arguments by their declared or
  // inferred type. A shape that does not match is `None` — the same answer
  // every generated mutator gives when handed something it cannot use.
  // The effect queue, when the body has any. Effects go out ONLY when the
  // body FINISHED: half a transition — nothing moved but a message went out —
  // is the one outcome nobody can reason about afterwards, and it is what the
  // interpreter's `Outcome` already says by dropping them with the state. A
  // `guard … else { return Unchanged }` anywhere below leaves the queue
  // unflushed, which is the whole point of it being a queue.
  let types = self.param_types(d, surface)
  for i, p in d.params {
    let declared = types.get(i).unwrap_or(None)
    // Bound only when the body reads it. The SHAPE is still checked either
    // way — a `setLabel 3` must refuse whether or not the body looks at the
    // argument — but a binding nobody uses is a warning, and a generated file
    // must not be the thing that warns.
    let binder = if uses_name(body, p.name) { local_of(p.name) } else { "_" }
    // The pattern that takes a payload APART, and the type the body may then
    // use it at. The two answers are one decision: a parameter is usable at
    // its declared type exactly when the pattern below hands the body that
    // type's MoonBit value.
    //
    // `Array[Any]` and `Map[String, Any]` are the shapes a channel actually
    // carries — an intent's answer above all — and their patterns hand over
    // `Array[Value]` / `Map[String, Value]`, which IS what the field holds.
    // Anything else non-scalar (a list of a DECLARED element type, a record, a
    // set) would need a decode loop this backend does not write, so the
    // parameter binds raw and its type becomes unknown: a typed use is then
    // refused with a script-refusal and the arm stays in MoonBit, which is the
    // honest answer. Keeping the declared type there instead emitted an
    // assignment of a `Value` into a typed field — a generated module that did
    // not compile.
    let (pat, ty) = match declared {
      Some(TInt(..)) | Some(TFloat) => ("Num(\{binder})", declared)
      Some(TText) => ("Str(\{binder})", declared)
      Some(TBool) => ("Bool(\{binder})", declared)
      Some(TList(TAny)) => ("List(\{binder})", declared)
      Some(TOMap(TAny)) => ("Map(\{binder})", declared)
      // A list of COMPONENTS is `Array[@tutuca.Value]` at runtime, exactly as
      // `Array[Any]` is — a component instance travels as a `Value` and there
      // is nothing to decode. So the element type costs nothing here, which is
      // the point of declaring one: `Array[ChatModelGroup]` buys the `@each`
      // body check and the generator drawing instances instead of junk, and it
      // used to cost the whole handler, because the payload bound raw and its
      // assignment into the typed field was refused into MoonBit.
      //
      // A list of a declared RECORD is not this case: that field holds decoded
      // structs, and the decode loop is what this backend does not write.
      Some(TList(TComp(_))) | Some(TList(TCompProtocols(_))) =>
        ("List(\{binder})", declared)
      // `Any` is already a `Value`, so the raw binding is the right one.
      Some(TAny) | None => (binder, declared)
      _ => (binder, None)
    }
    self.params[p.name] = ty
    // An argument of the wrong shape is `Unchanged`, not `Unhandled`: this
    // arm DID claim the name, and letting `add 'x'` fall through to a
    // generated mutator would apply a write the block refused.
    b.write_string(
      "      guard args.get(\{i}) is Some(\{pat}) else { return Unchanged }\n",
    )
  }
  // THE PRECONDITION, over the state as the arm received it. After the
  // argument guards, so a `setLabel 3` is refused for its shape rather than
  // reported as a rule that did not hold.
  if d.requires_ is Some(c) {
    b.write_string(
      self.contract_guard(c.name, "      ", "precondition_failed", d.name),
    )
  }
  let stmts = self.stmts(body, "      ")
  // THE POSTCONDITION and THE INVARIANTS, over the successor — which is what
  // `s` names by the time the statements are done, since each write rebinds
  // it. Before the flush, so a rule that does not hold leaves the queue
  // unflushed: half a transition is what the queue exists to prevent, and a
  // contract failing is no different from a body not finishing.
  let after = StringBuilder()
  if d.ensures_ is Some(c) {
    after.write_string(
      self.contract_guard(c.name, "      ", "postcondition_failed", d.name),
    )
  }
  for inv in self.invariants {
    after.write_string(
      self.contract_guard(inv, "      ", "invariant_failed", d.name),
    )
  }
  // THE DOMAINS, beside the invariants and for the same reason.
  //
  // A `where` is a rule about the successor exactly as an `invariant` is, and
  // the runtime already asks it after every dispatch. What it did not have
  // until now was a place in the ARM — so an arm that raised effects and then
  // put a field outside its domain flushed the queue first and was refused
  // afterwards, leaving the state rolled back and the effects gone. That is the
  // half a queue exists to prevent, and an invariant already got it.
  after.write_string(self.domain_guard("      ", d.name))
  if stmts.contains("effects.push(") {
    b.write_string("      let effects : Array[() -> Unit] = []\n")
    b.write_string(stmts)
    b.write_string(after.to_string())
    b.write_string("      for f in effects {\n        f()\n      }\n")
  } else {
    b.write_string(stmts)
    b.write_string(after.to_string())
  }
  // `Next(s)` at the end of an arm that never rebound is the parameter going
  // straight back out — the one use that is not an expression the emitter
  // wrote.
  if !stmts.contains("let s ") && !stmts.contains("let s :") {
    self.uses_state = true
  }
  b.write_string("      Next(s)\n")
  b.write_string("    }\n")
  b.to_string()
}

///|
/// Every declared domain, as one check that reports and leaves.
///
/// ONE check for all of them, and CALLED rather than compiled — the opposite
/// of what `contract_guard` does with a rule, on purpose. A rule is an
/// arbitrary expression this backend has to be able to spell; a domain is a
/// closed relation the runtime already evaluates, at the very door this guard
/// stands in front of. Compiling a second reading of `index of` into the arm
/// would buy nothing and could disagree with the first — and a component that
/// abandons a transition its own compiled code passed is the worst shape that
/// disagreement can take.
///
/// So the literal is emitted and `@tutuca.first_broken_domain` is asked. The
/// sentence is composed rather than authored, which is why a `where` needs no
/// `format` and why nothing here looks one up.
fn E::domain_guard(self : E, pad : String, handler : String) -> String {
  let domains = self.def.domains_src()
  if domains == "[]" {
    return ""
  }
  // `s` is the successor at this point, the same state the invariants above
  // were just asked about. Encoded ONCE: the check reads it, the sentence
  // reads it, and the record carries it.
  let lines = [
    "let domain_fields = @component.Fields::encode(s)",
    "match @tutuca.first_broken_domain(" + domains + ", domain_fields) {",
    "  Some(domain_broke) => {",
    "    @tutuca.domain_failed(",
    "      handler=" + quote(handler) + ",",
    "      field=domain_broke.field,",
    "      sentence=@tutuca.broken_domain_sentence(domain_broke, domain_fields),",
    "      state=(Map(domain_fields) : @tutuca.Value),",
    "    )",
    "    return Unchanged",
    "  }",
    "  None => ()",
    "}",
  ]
  let b = StringBuilder()
  for line in lines {
    b.write_string(pad)
    b.write_string(line)
    b.write_char('\n')
  }
  b.to_string()
}

///|
/// One contract check, as a guard that reports and leaves.
///
/// The rule is compiled HERE rather than called, so the same `pred` written
/// before a body and after it reads the two states `s` names at those two
/// points. Nothing else in an arm's scope is visible to it: a rule is about
/// state, so the arm's parameters, its bindings and whatever a `new` left in
/// `@cur` are all put away first and handed back after.
fn E::contract_guard(
  self : E,
  rule : String,
  pad : String,
  reporter : String,
  handler : String,
) -> String raise NoWay {
  guard self.rules.get(rule) is Some(e) else {
    raise Cannot(
      "`\{rule}` is not a `pred` this block declares, so there is no rule to check",
    )
  }
  let params = self.params
  let binds = self.binds
  let target = self.target
  self.params = Map([])
  self.binds = Map([])
  self.target = None
  // Nothing is put back on the way out of a refusal, and nothing needs to be:
  // a refused arm is not emitted, and the next declaration is handed fresh
  // parameters and no target before it starts.
  let cond = self.at_bool(e)
  let sentence = self.compiled_sentence(rule)
  let prelude = self.flush(pad)
  self.params = params
  self.binds = binds
  self.target = target
  // `s` is the state at THIS moment, which is the whole reason the rule is
  // compiled in rather than called: before the body it names what arrived, and
  // after it the successor the framework is about to throw away. Encoding it is
  // paid for only here, inside the refusal.
  let state = "state=(Map(@component.Fields::encode(s)) : @tutuca.Value)"
  let says = match sentence {
    Some(src) => "sentence=\{src}, "
    None => ""
  }
  let report = "@tutuca.\{reporter}(handler=\{quote(handler)}, pred=\{quote(rule)}, \{says}\{state})"
  "\{prelude}\{pad}guard \{cond} else {\n\{pad}  \{report}\n\{pad}  return Unchanged\n\{pad}}\n"
}

///|
/// A rule's `format`, compiled as a String expression — or None, which is a
/// record with no sentence rather than an arm that does not compile.
///
/// Compiled into a SCRATCH prelude, and dropped if it needed a guard. A guard
/// stands in front of the condition and leaves the arm when it does not hold,
/// so a sentence that needed one would decide whether the transition happens —
/// and a message about a failure that can cause one is worse than no message.
/// The same reasoning refuses to let it refuse the arm: the interpreter answers
/// `""` for a sentence it cannot evaluate and keeps the record, and two backends
/// that disagree about that would disagree about whether a rule fires at all.
fn E::compiled_sentence(self : E, rule : String) -> String? {
  guard self.formats.get(rule) is Some(f) else { return None }
  let kept_prelude = self.prelude
  let kept_guards = self.guards
  self.prelude = []
  self.guards = Map([])
  let src = self.at_text(f) catch {
    // A sentence this backend cannot spell — `null`, an enum where a string is
    // wanted — is one the interpreter would still print. Neither backend loses
    // the RECORD over it, which is the half that has to agree.
    _ => ""
  }
  let needed_guard = !self.prelude.is_empty()
  self.prelude = kept_prelude
  self.guards = kept_guards
  if src == "" || needed_guard {
    None
  } else {
    Some(src)
  }
}

///|
/// Whether `name` is read anywhere in a body.
///
/// A parameter the body ignores is bound to `_`, so the arity and the shape
/// are still checked and nothing is named that nobody reads.
fn uses_name(body : Array[@tscript.Stmt], name : String) -> Bool {
  for st in body {
    if stmt_uses(st, name) {
      return true
    }
  }
  false
}

///|
fn stmt_uses(s : @tscript.Stmt, name : String) -> Bool {
  match s {
    SAssign(place~, value~, ..) =>
      place_uses(place, name) || expr_uses(value, name)
    SMethod(place~, args~, ..) =>
      place_uses(place, name) || args.iter().any(a => expr_uses(a, name))
    SEffect(args~, ..) => args.iter().any(a => expr_uses(a, name))
    SIf(cond~, then_~, else_~, ..) =>
      expr_uses(cond, name) || uses_name(then_, name) || uses_name(else_, name)
    // `new Label` names a TYPE. It reads no name, so it uses none.
    SNew(..) => false
  }
}

///|
fn place_uses(p : @tutuca.Place, name : String) -> Bool {
  // A path ROOTED at a parameter reads it, which is what decides whether the
  // generated arm binds the argument or underscores it.
  if p.root is PParam(n) && n == name {
    return true
  }
  for st in p.steps {
    if st is PIndex(e) && expr_uses(e, name) {
      return true
    }
  }
  false
}

///|
fn expr_uses(e : @tutuca.Expr, name : String) -> Bool {
  match e {
    EName(name=n, ..) => n == name
    ERead(place~, ..) | ERef(place~, ..) => place_uses(place, name)
    ELit(..) | EMethod(..) | EDyn(..) | EMacroVar(..) | EConfigVar(..) => false
    ETpl(parts~, ..) =>
      parts.iter().any(p => p is TExpr(inner) && expr_uses(inner, name))
    EUnary(operand~, ..) => expr_uses(operand, name)
    EChain(operands~, ..) => operands.iter().any(o => expr_uses(o, name))
    EApp(args~, ..) => args.iter().any(a => expr_uses(a, name))
    EIf(cond~, then_~, else_~, ..) =>
      expr_uses(cond, name) || expr_uses(then_, name) || expr_uses(else_, name)
    // Three forms a SLOT produces and a block body never writes. They name
    // nothing a body has a binder for, so they use no parameter.
    ETypeName(..) | EHandlerName(..) | EEventPath(..) => false
  }
}

///|
/// Whether a declaration's body reads the state at all.
///
/// A `compute two { 2 }` names its parameter `_s`, for the reason every other
/// unread binder here is underscored: a generated file must not be the thing
/// that warns.
fn decl_reads_state(d : @tscript.Decl) -> Bool {
  decl_any(d, e => e is ERead(place=p, ..) && p.root is PState(_))
}

///|
/// Whether a body calls another callable this block declares.
fn E::decl_calls_sibling(self : E, d : @tscript.Decl) -> Bool {
  decl_any(d, e => {
    match e {
      EName(name~, ..) =>
        !self.params.contains(name) && self.callables.contains(name)
      EApp(name~, ..) => self.callables.contains(name)
      _ => false
    }
  })
}

///|
/// Whether it reads one of the loop's bindings.
fn decl_reads_bind(d : @tscript.Decl, bind : String) -> Bool {
  decl_any(d, e => e is ERead(place=p, ..) && p.root is PBind(b) && b == bind)
}

///|
/// Whether it reads any of its own parameters.
fn decl_reads_params(d : @tscript.Decl) -> Bool {
  for prm in d.params {
    if decl_reads_name(d, prm.name) {
      return true
    }
  }
  false
}

///|
/// Whether it reads one name.
fn decl_reads_name(d : @tscript.Decl, name : String) -> Bool {
  match d.body {
    Value(e) => expr_uses(e, name)
    Stmts(body) => uses_name(body, name)
  }
}

///|
/// Every expression in a declaration, against a question.
fn decl_any(d : @tscript.Decl, ask : (@tutuca.Expr) -> Bool) -> Bool {
  fn walk(e : @tutuca.Expr) -> Bool {
    if ask(e) {
      return true
    }
    match e {
      ETpl(parts~, ..) =>
        parts.iter().any(p => p is TExpr(inner) && walk(inner))
      EUnary(operand~, ..) => walk(operand)
      EChain(operands~, ..) => operands.iter().any(o => walk(o))
      EApp(args~, ..) => args.iter().any(a => walk(a))
      EIf(cond~, then_~, else_~, ..) => walk(cond) || walk(then_) || walk(else_)
      ERead(place~, ..) | ERef(place~, ..) =>
        place.steps.iter().any(st => st is PIndex(i) && walk(i))
      _ => false
    }
  }

  fn walk_stmts(body : Array[@tscript.Stmt]) -> Bool {
    for st in body {
      let hit = match st {
        SAssign(place~, value~, ..) =>
          walk(ERead(place~, span=place.span)) || walk(value)
        SMethod(place~, args~, ..) =>
          walk(ERead(place~, span=place.span)) || args.iter().any(a => walk(a))
        SEffect(args~, ..) => args.iter().any(a => walk(a))
        SIf(cond~, then_~, else_~, ..) =>
          walk(cond) || walk_stmts(then_) || walk_stmts(else_)
        SNew(..) => false
      }
      if hit {
        return true
      }
    }
    false
  }

  match d.body {
    Value(e) => walk(e)
    Stmts(body) => walk_stmts(body)
  }
}

///|
/// Where a handler's parameter types come from — the schema for a message it
/// declares, the views' call sites for a name only they write.

///|
/// The declared message a handler answers, by either spelling.
///
/// A protocol member is DECLARED as `Alias::member` and travels as
/// `id::member`; a case declared `Nudge` travels as `nudge`. A script body
/// writes the declaration spelling, because that is the only one the grammar
/// takes — so this is the one place that turns what the author wrote into what
/// the schema says it IS, and every reader downstream asks here rather than
/// comparing strings of its own.
fn E::declared_msg(self : E, d : @tscript.Decl) -> @statedef.MsgDef? {
  let cases = match d.kind {
    DIntent => self.def.intent
    _ => self.def.receive
  }
  for m in cases {
    if m.name == d.name || m.source_name == d.name {
      return Some(m)
    }
  }
  None
}

///|
/// The name a handler's arm must MATCH — the runtime name, always.
///
/// The arm used to be written with `d.name`, the declaration spelling, while
/// `send` and `intent` and the generated codec all emit the runtime name. For
/// a bare lowercase message those are the same string and nothing showed; for
/// `receive Openable::setOpen` they are not, so the arm listened for
/// `"Openable::setOpen"`, every sender emitted
/// `"…/Openable@1::setOpen"`, and the handler never ran. Silently, in a
/// component with no `update~` to report the miss.
fn E::wire_name(self : E, d : @tscript.Decl) -> String {
  match self.declared_msg(d) {
    Some(m) => m.name
    None => d.name
  }
}

///|
fn E::param_types(
  self : E,
  d : @tscript.Decl,
  surface : @check.Surface,
) -> Array[@statedef.StateTy?] {
  match d.kind {
    DReceive | DIntent => {
      if self.declared_msg(d) is Some(m) {
        return m.payload.map(t => Some(t))
      }
      // A `receive` whose name the VIEWS send is declared by the call sites
      // rather than by the schema — the merge, and the same fallback
      // `tscript/check` makes for the same reason. `intent` is schema-only, and
      // an undeclared one is opaque.
      if d.kind is DReceive && surface.inputs.get(d.name) is Some(ts) {
        return d.params.mapi((i, _p) => ts.get(i).unwrap_or(None))
      }
      d.params.map(_p => None)
    }
    DSet =>
      match self.def.properties.iter().find_first(p => p.name == d.name) {
        Some(p) => [Some(p.ty)]
        None => [None]
      }
    _ =>
      match surface.inputs.get(d.name) {
        Some(ts) => d.params.mapi((i, _p) => ts.get(i).unwrap_or(None))
        None => d.params.map(_p => None)
      }
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn E::stmts(
  self : E,
  body : Array[@tscript.Stmt],
  pad : String,
) -> String raise NoWay {
  let b = StringBuilder()
  for s in body {
    b.write_string(self.stmt(s, pad))
  }
  b.to_string()
}

///|
fn E::stmt(self : E, s : @tscript.Stmt, pad : String) -> String raise NoWay {
  self.prelude = []
  let body = self.stmt_body(s, pad)
  let head = self.prelude.map(g => "\{pad}\{g}\n").join("")
  self.prelude = []
  head + body
}

///|
/// One copy-on-write rebind of `s`, with one field replaced.
///
/// `{ ..s, count: … }` on a ONE-field struct is `unused_struct_update` — the
/// spread covers nothing — and a generated file must not be the thing that
/// warns. Dropping it takes the inference the spread was supplying with it, so
/// the annotation goes back on: several examples in one package declare a
/// one-field state and MoonBit cannot pick between their record types.
///
/// A single-field state is not an edge case; it is what a counter looks like.
fn E::rebind(self : E, field : String, rhs : String, pad : String) -> String {
  if self.def.fields.length() == 1 {
    "\{pad}let s : \{self.state_ty} = { \{binding_of(field)}: \{rhs} }\n"
  } else {
    // `..s` reads the state the arm was handed, whether or not anything else
    // in the body does.
    self.uses_state = true
    "\{pad}let s = { ..s, \{binding_of(field)}: \{rhs} }\n"
  }
}

///|
fn E::stmt_body(
  self : E,
  s : @tscript.Stmt,
  pad : String,
) -> String raise NoWay {
  match s {
    // The target, which is a LOCAL of known type rather than a field of the
    // state — so writing through a path into one is a record update the
    // generator can spell, not the spine rebuild it refuses on `s`.
    SAssign(place~, op=ASet, value~, ..) if is_target(place) => {
      let (name, ty) = self.target_root()
      let rhs = self.target_update(name, ty, place.steps, 0, (t, _) => {
        self.at(value, t)
      })
      "\{pad}let \{name} = \{rhs}\n"
    }
    SMethod(place~, call~, args~, ..) if is_target(place) => {
      let (name, ty) = self.target_root()
      let rhs = self.target_update(name, ty, place.steps, 0, (t, recv) => {
        self.collection_call_at(call, recv, "@" + @tscript.target_bind, t, args)
      })
      "\{pad}let \{name} = \{rhs}\n"
    }
    SAssign(place~, op~, value~, ..) => {
      let (field, ty) = self.root_field(place)
      let rhs = match op {
        ASet => self.at(value, ty)
        // Arithmetic, so both sides go through Double and the result comes
        // back at the field's type.
        AAdd | ASub => {
          let sign = if op is AAdd { "+" } else { "-" }
          let cur = self.read_field(place)
          let inc = self.at_num(value)
          self.to_ty("(\{cur} \{sign} \{inc})", TFloat, ty)
        }
      }
      // Copy-on-write, exactly as a hand-written arm spells it. Rebinding `s`
      // rather than accumulating one literal is what lets a later statement
      // read what an earlier one wrote.
      self.rebind(field, rhs, pad)
    }
    SMethod(place~, call~, args~, ..) => {
      let (field, ty) = self.root_field(place)
      let next = self.collection_call(call, field, ty, args)
      self.rebind(field, next, pad)
    }
    SEffect(name~, args~, route~, ..) => self.effect(name, args, route, pad)
    // `new Label` is a `let` at the type's zero. The annotation is what makes
    // it resolve: `zero_expr` writes `{ text: "", done: false }` unqualified,
    // because every other position it lands in already has a type wanted.
    SNew(ty~, ..) => {
      guard @check.resolve_ty_ref(self.def, ty) is Some(t) else {
        raise Cannot(
          "`\{ty.to_source()}` is not a type the state declares, so there is nothing to build",
        )
      }
      let name = "cur\{self.target_n}"
      self.target_n = self.target_n + 1
      self.target = Some((name, t))
      "\{pad}let \{name} : \{self.def.moonbit_ty(t)} = \{self.def.zero_expr(t)}\n"
    }
    SIf(cond~, then_~, else_~, ..) => {
      let c = self.at_bool(cond)
      let b = StringBuilder()
      // A branch rebinds `s`, so the shadowing has to happen in an EXPRESSION
      // that answers the state — `if … { … } else { s }` — rather than in two
      // statement blocks whose bindings would not escape.
      b.write_string("\{pad}let s = if \{c} {\n")
      // A `new` inside an arm binds a `let` inside that expression, so the
      // target it made does not outlive the branch — and the one that was
      // there before still does. Restoring it is what keeps a later `@cur`
      // from naming a temporary that is out of scope: it is refused instead,
      // which is a message rather than a generated file that will not compile.
      let outer = self.target
      b.write_string(self.stmts(then_, pad + "  "))
      b.write_string("\{pad}  s\n")
      b.write_string("\{pad}} else {\n")
      self.target = outer
      b.write_string(self.stmts(else_, pad + "  "))
      b.write_string("\{pad}  s\n")
      b.write_string("\{pad}}\n")
      self.target = outer
      b.to_string()
    }
  }
}

///|
/// Whether a place is rooted at the target `new` builds into.
fn is_target(p : @tutuca.Place) -> Bool {
  p.root is PBind(n) && n == @tscript.target_bind
}

///|
/// The temporary the active `new` bound, refused when there is none.
fn E::target_root(self : E) -> (String, @statedef.StateTy) raise NoWay {
  guard self.target is Some(t) else {
    raise Cannot(
      "`@\{@tscript.target_bind}` holds what a `new` built, and no `new` is in scope here — one inside a branch does not outlive it",
    )
  }
  t
}

///|
/// A write through a path into the target, as a value: `{ ..cur0, text: … }`,
/// nested for a deeper path.
///
/// Expressible where the same write into `s` is not, and for one reason: the
/// target is a local whose type is known at every step, so no bounds check and
/// no runtime lookup stand between the path and a record literal.
fn E::target_update(
  self : E,
  src : String,
  ty : @statedef.StateTy,
  steps : Array[@tutuca.PathStep],
  i : Int,
  leaf : (@statedef.StateTy, String) -> String raise NoWay,
) -> String raise NoWay {
  guard steps.get(i) is Some(st) else { return leaf(ty, src) }
  guard st is PField(name) else {
    raise Cannot(
      "writing through an index into `@\{@tscript.target_bind}` needs a bounds check this backend does not emit yet — write the handler in MoonBit",
    )
  }
  guard ty is TRecord(_) else {
    raise Cannot(
      "`\{ty.show_source()}` is not a record, so `\{name}` is not a field to write",
    )
  }
  guard self.def.field_of(ty, name) is Some(inner) else {
    raise Cannot("`\{ty.show_source()}` has no field `\{name}`")
  }
  let bind = binding_of(name)
  let next = self.target_update("\{src}.\{bind}", inner, steps, i + 1, leaf)
  "{ ..\{src}, \{bind}: \{next} }"
}

///|
/// The state field a place is rooted at, refusing everything this backend
/// cannot rebuild.
fn E::root_field(
  self : E,
  p : @tutuca.Place,
) -> (String, @statedef.StateTy) raise NoWay {
  guard p.root is PState(name) else {
    raise Cannot(
      "a binding is written by `enrich` / `enrichScope`, which this backend does not compile yet — write the handler in MoonBit",
    )
  }
  guard self.def.field(name) is Some(f) else {
    raise Cannot("`.\{name}` is not a field of the state")
  }
  guard p.steps.is_empty() else {
    // The spine rebuild is expressible — the generator knows every type on the
    // path — and is not written yet. Saying so beats emitting something that
    // silently drops the write.
    raise Cannot(
      "writing through `.\{name}.…` needs a spine rebuild this backend does not emit yet — write the handler in MoonBit, or assign the whole field",
    )
  }
  (name, f.ty)
}

///|
/// Read the current value of a place, at its own type.
fn E::read_field(self : E, p : @tutuca.Place) -> String raise NoWay {
  let (name, ty) = self.root_field(p)
  self.uses_state = true
  self.to_ty("s.\{binding_of(name)}", ty, TFloat)
}

///|
/// A collection method, as the new value of the field.
///
/// Every one answers an EXPRESSION, never a mutation of the receiver. A
/// MoonBit `Array` and `Map` are both mutable and a state struct is shared —
/// the previous state is still on the transactor's stack — so writing through
/// the receiver would edit a value someone else is holding. `Array` gets a
/// fresh one from a slice concatenation; `Map` gets `.copy()`.
fn E::collection_call(
  self : E,
  call : String,
  field : String,
  ty : @statedef.StateTy,
  args : Array[@tutuca.Expr],
) -> String raise NoWay {
  self.uses_state = true
  self.collection_call_at(call, "s.\{binding_of(field)}", ".\{field}", ty, args)
}

///|
/// The same, on a receiver that is not a state field: the target `new` built,
/// or a path into one. `label` is how the receiver is written in a refusal,
/// since a temporary's generated name means nothing to an author.
fn E::collection_call_at(
  self : E,
  call : String,
  recv : String,
  label : String,
  ty : @statedef.StateTy,
  args : Array[@tutuca.Expr],
) -> String raise NoWay {
  fn arity(n : Int) -> Unit raise NoWay {
    if args.length() != n {
      raise Cannot("`\{call}` takes \{n} argument(s), not \{args.length()}")
    }
  }

  // A set is Map-backed and keyed by the member's display string — the same
  // key the generated `addIn<X>` mutator writes, so a card and a compiled
  // component put a member in the same place.
  fn set_write(value : String) -> String raise NoWay {
    let k = self.at(args[0], TText)
    "{ let m = \{recv}.copy(); m[\{k}] = \{value}; m }"
  }

  match (call, ty) {
    // -- lists --------------------------------------------------------------
    ("push", TList(elem)) => {
      arity(1)
      "(\{recv} + [\{self.at(args[0], elem)}])"
    }
    ("insertAt", TList(elem)) => {
      arity(2)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let v = self.at(args[1], elem)
      // `<=` because inserting AT the length appends, which is a real answer.
      let at = self.hoist("at", i)
      let out = self.leave_token("`insertAt`")
      self.prelude.push(
        "guard \{at} >= 0 && \{at} <= \{recv}.length() else { return \{out} }",
      )
      "(\{recv}[0:\{at}].to_owned() + [\{v}] + \{recv}[\{at}:].to_owned())"
    }
    ("removeAt", TList(_)) | ("deleteAt", TList(_)) => {
      arity(1)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let at = self.hoist("at", i)
      let out = self.leave_token("`removeAt`")
      self.prelude.push(
        "guard \{at} >= 0 && \{at} < \{recv}.length() else { return \{out} }",
      )
      "(\{recv}[0:\{at}].to_owned() + \{recv}[\{at} + 1:].to_owned())"
    }
    ("setAt", TList(elem)) => {
      arity(2)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let v = self.at(args[1], elem)
      let at = self.hoist("at", i)
      let out = self.leave_token("`setAt`")
      self.prelude.push(
        "guard \{at} >= 0 && \{at} < \{recv}.length() else { return \{out} }",
      )
      "{ let a = \{recv}.copy(); a[\{at}] = \{v}; a }"
    }
    ("clear", TList(elem)) => {
      arity(0)
      "([] : Array[\{elem_ty_name(elem)}])"
    }
    // -- sets ---------------------------------------------------------------
    ("add", TSet) | ("add", TFlags(_)) => {
      arity(1)
      set_write("true")
    }
    ("remove", TSet)
    | ("remove", TFlags(_))
    | ("delete", TSet)
    | ("delete", TFlags(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); m.remove(\{k}); m }"
    }
    ("toggle", TSet) | ("toggle", TFlags(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); let k = \{k}; if m.get(k) is Some(true) { m.remove(k) } else { m[k] = true }; m }"
    }
    // -- ordered maps -------------------------------------------------------
    // `setAt` / `deleteAt` are the KEYED half of the sequence operations, and
    // an ordered map takes them for the same reason a list does — they are the
    // generated `setIn<X>At` / `deleteIn<X>At` mutators with the infix
    // dropped. The checker (`method_fits`) and the card interpreter both spell
    // a map that way, so emitting only `set` / `remove` here made one backend
    // refuse what the other ran.
    ("set", TOMap(v)) | ("setAt", TOMap(v)) => {
      arity(2)
      let k = self.at(args[0], TText)
      let value = self.at(args[1], v)
      "{ let m = \{recv}.copy(); m[\{k}] = \{value}; m }"
    }
    ("remove", TOMap(_))
    | ("delete", TOMap(_))
    | ("deleteAt", TOMap(_))
    | ("removeAt", TOMap(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); m.remove(\{k}); m }"
    }
    _ =>
      raise Cannot(
        "`\{call}` does not apply to `\{label}`, which is \{ty.show_source()} — write the handler in MoonBit",
      )
  }
}

///|
/// Bind an expression once when it is not already a simple name.
///
/// A guard tests it and the code after reads it again; evaluating a call twice
/// would be wrong the moment it stopped being pure, and unreadable either way.
fn E::hoist(self : E, name : String, expr : String) -> String {
  if is_simple(expr) {
    return expr
  }
  self.prelude.push("let \{name} = \{expr}")
  name
}

///|
/// Whether an expression is a bare name or an integer literal.
fn is_simple(e : String) -> Bool {
  let cs = e.to_array()
  if cs.is_empty() {
    return false
  }
  for c in cs {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_') {
      return false
    }
  }
  true
}

///|
/// The MoonBit spelling of a list's element type, for the one place an empty
/// literal has to be annotated.
fn elem_ty_name(t : @statedef.StateTy) -> String raise NoWay {
  match t {
    TBool => "Bool"
    TInt(width=32, signed=true) => "Int"
    TFloat => "Double"
    TText => "String"
    TAny => "@tutuca.Value"
    _ =>
      raise Cannot(
        "clearing a list of \{t.show_source()} needs a type annotation this backend does not spell yet — assign `[]` to the whole field instead",
      )
  }
}

///|
/// An effect, straight through to the `ctx` the function already holds.
/// The three outcome names a sender declared an arm for, as
/// `IntentOpts::new`'s keyword arguments — or "" when it declared none.
///
/// This is where "a sender expects an answer if and only if it declares an
/// answer arm" becomes code. Nobody writes these;
/// the generator computes them, which is exactly the design's claim that the
/// notification/request split needs no declaration.
fn E::outcomes(self : E, msg : String) -> String {
  let parts : Array[String] = []
  for
    pair in [
      ("Ok", "on_ok_name"),
      ("Error", "on_error_name"),
      ("Unhandled", "on_unhandled_name"),
    ] {
    let arm = msg + pair.0
    if self.answer_arms.contains(arm) {
      parts.push("\{pair.1}=\{quote(arm)}")
    }
  }
  parts.join(", ")
}

///|
/// `@tutuca.IntentOpts::new(...)`, with only what was written.
///
/// An EMPTY route emits no `route=`, so the default `dyn lex` stays where it is
/// written — `IntentOpts::new` — rather than being spelled a second time into
/// every generated module.
fn intent_opts(route : Array[@tutuca.Leg], outcomes : String?) -> String {
  let parts : Array[String] = []
  if !route.is_empty() {
    parts.push(
      "route=[" +
      route
      .map(l => "@tutuca.Leg::" + (if l is Dyn { "Dyn" } else { "Lex" }))
      .join(", ") +
      "]",
    )
  }
  match outcomes {
    Some(o) if o != "" => parts.push(o)
    _ => ()
  }
  "@tutuca.IntentOpts::new(" + parts.join(", ") + ")"
}

///|
/// The stack a sibling call is handed: this body's own parameter, or the
/// handler-side twin built from `ctx`.
///
/// One `lookup_dynamic` seam, two producers — the render chain a view is being
/// built on, and the dispatch route a handler is already standing on. A
/// `NullStack` here instead would make `$dark` answer one thing in a `@show`
/// and another in the `receive` beside it, silently.
fn E::stack_arg(self : E) -> String {
  if self.in_value_body {
    self.uses_stack = true
    "stack"
  } else {
    self.uses_ctx = true
    // The call this belongs to passes `s` alongside it, and in a transition
    // that is the parameter — a `requires`/`invariant` guard runs before the
    // arm has rebound anything.
    self.uses_state = true
    "@tutuca.CtxStack(ctx)"
  }
}

///|
/// The `ctx` a dispatch-time construct needs, or a refusal naming the body
/// that is not handed one.
///
/// The twin of `leave_token`: a construct that needs something the SIGNATURE
/// does not carry is refused at generation time, by name, rather than emitted
/// as source that does not build.
fn E::needs_ctx(self : E, what : String) -> Unit raise NoWay {
  guard !self.in_value_body else {
    raise Cannot(
      "`\{what}` is a dispatch-time effect, and a `compute`, a `pred`, a `@when` and an `enrich` all run while the view is being BUILT — there is no message in flight for one to answer. Raise it from the transition instead",
    )
  }
  self.uses_ctx = true
}

///|
fn E::effect(
  self : E,
  name : String,
  args : Array[@tutuca.Expr],
  route : Array[@tutuca.Leg],
  pad : String,
) -> String raise NoWay {
  self.needs_ctx(name)
  if name == "stop" {
    return "\{pad}effects.push(() => ctx.stop_propagation())\n"
  }
  // The three effects that name no message. `forward` re-dispatches the one
  // that arrived, and `reply` / `fail` are addressed by the walk, so the
  // literal-name guard below is not theirs to satisfy.
  match name {
    "reply" | "fail" => {
      let v = self.as_value(args[0])
      let verb = if name == "reply" { "reply" } else { "fail" }
      return "\{pad}effects.push(() => ctx.\{verb}(\{v}))\n"
    }
    "forward" => {
      // Amended arguments, or the ones that arrived. A route the forwarder
      // wrote, or the one the walk is already on.
      let amended = if args.is_empty() {
        "None"
      } else {
        "Some([" + args.map(a => self.as_value(a)).join(", ") + "])"
      }
      let opts = if route.is_empty() {
        "None"
      } else {
        "Some(\{intent_opts(route, None)})"
      }
      return "\{pad}effects.push(() => ctx.forward(\{amended}, \{opts}))\n"
    }
    _ => ()
  }
  let msg = match args.get(0) {
    Some(ELit(lit=LStr(raw), ..)) => raw
    Some(EName(name=source_name, ..)) =>
      match self.def.operation_name(source_name) {
        Some(wire_name) => wire_name
        None => raise Cannot("unknown protocol operation `\{source_name}`")
      }
    _ =>
      raise Cannot(
        "`\{name}` needs a raw quoted name or a declared protocol operation",
      )
  }
  // Every payload crosses as a `@tutuca.Value`, which is what the channel
  // carries — so this is the one place a typed expression goes back to the
  // dynamic representation.
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(self.as_value(args[i]))
  }
  let payload = "[" + rest.join(", ") + "]"
  match name {
    "send" => "\{pad}effects.push(() => ctx.send(\{quote(msg)}, \{payload}))\n"
    // The replier names the reply, which is the whole difference from `reply`:
    // an intent's raiser declared arms for an answer and a message's sender
    // did not, so the name has to come from here.
    "sendReply" =>
      "\{pad}effects.push(() => ctx.send_reply(\{quote(msg)}, \{payload}))\n"
    "intent" =>
      "\{pad}effects.push(() => ctx.intent(\{quote(msg)}, \{payload}, \{intent_opts(route, Some(self.outcomes(msg)))}))\n"
    _ =>
      raise Cannot(
        "`\{name}` addresses a position, which this backend does not emit yet — write the handler in MoonBit",
      )
  }
}

// ---------------------------------------------------------------------------
// Expressions

///|
/// Emit an expression at a wanted type.
///
/// A WHOLE numeric literal is spelled at the wanted type directly rather than
/// converted into it. `.count = 1` reads `1`, not `1.0.to_int()`, and the two
/// are the same number — the conversion exists for values whose type is only
/// known at run time, and a literal's is known here.
///
/// A FRACTIONAL one is not refused. It goes through the ordinary `.to_int()`,
/// which truncates, because that is what the interpreter does with the same
/// expression — `Value` has one number and the generated codec's decode
/// truncates too. Refusing it here would make `.count = 2.7` an error while
/// `.count = .ratio` quietly truncated, which is two rules for one idea.
/// Whether a fractional literal in an integer place deserves a DIAGNOSTIC is
/// the checker's question, not the emitter's.
fn E::at(
  self : E,
  e : @tutuca.Expr,
  want : @statedef.StateTy,
) -> String raise NoWay {
  if e is ELit(lit=LNum(n), ..) &&
    want is TInt(..) &&
    n == n.to_int().to_double() {
    return n.to_int().to_string()
  }
  // A nullable place is peeled HERE and nowhere else, because the two things
  // that fill one are both decided by the place rather than by the value.
  // `null` is the literal with no type of its own — `Value::Null` and `None`
  // are the same absence, and only the wanted type says which spelling it
  // gets. And a present value goes through the SAME `at` one level in, so
  // `.n = 3` writes `Some(3)` and not `Some(3.0.to_int())`: the literal
  // shortcut above is asked about `Int`, which is what it can answer.
  //
  // The recursion is also what keeps the widening honest — `Some(...)` is
  // written only around a conversion that was already legal, so `Any` into a
  // `String?` stays refused rather than becoming a `Some` around a guess.
  if want is TOption(inner) {
    if e is ELit(lit=LNull, ..) {
      return "None"
    }
    return "Some(\{self.at(e, inner)})"
  }
  let (src, got) = self.expr(e)
  // An opaque value — a binding, a raw argument, another callable's answer —
  // where a type is wanted. Inside a value body this GUARDS, and the guard is
  // a port of the interpreter's own: `lower` there is
  // `guard args[0] is Str(s) else { return None }`, so a `@value` that is not
  // text makes the body answer nothing in both backends rather than being
  // coerced in one of them. In a transition `fail` is empty and it is still
  // refused, because there the answer to "not that shape" is already written.
  if got is TAny && self.fail != "" {
    match want {
      TText | TFloat | TInt(..) => return self.guarded(src, want)
      _ => ()
    }
  }
  self.to_ty(src, got, want)
}

///|
/// The token a runtime guard returns to leave this body, or a refusal when
/// this body has no door.
///
/// A transition answers `Unchanged`, a `compute` `Null`, a `@when` `false` —
/// each the same answer its signature gives a body that cannot finish. An
/// enricher is the one shape where leaving early is WRONG rather than
/// impossible: its writes have already landed in the map it was handed, and a
/// return would keep the ones made while dropping the rest. So the constructs
/// that need the door — a division by zero, an out-of-bounds collection index
/// — are refused there at generation time, on the same rule that refuses an
/// opaque coercion in an enricher.
fn E::leave_token(self : E, what : String) -> String raise NoWay {
  guard self.leave != "" else {
    raise Cannot(
      "`\{what}` can fail at run time, and surviving that means leaving the body mid-way — which an `enrich` cannot do (the writes before it would be half kept). Do the arithmetic in a transition or a `compute` instead",
    )
  }
  self.leave
}

///|
/// Bind an opaque value at the wanted type, or leave the body.
fn E::guarded(self : E, src : String, want : @statedef.StateTy) -> String {
  let key = "\{src}|\{want.show_source()}"
  if self.guards.get(key) is Some(bound) {
    return bound
  }
  self.tmp = self.tmp + 1
  let v = "v\{self.tmp}"
  let pat = match want {
    TText => "Str(\{v})"
    _ => "Num(\{v})"
  }
  self.prelude.push("guard \{src} is \{pat} else { return \{self.fail} }")
  let bound = match want {
    TInt(..) => "\{v}.to_int()"
    _ => v
  }
  self.guards[key] = bound
  bound
}

///|
fn E::at_num(self : E, e : @tutuca.Expr) -> String raise NoWay {
  self.at(e, TFloat)
}

///|
fn E::at_bool(self : E, e : @tutuca.Expr) -> String raise NoWay {
  let (src, got) = self.expr(e)
  match got {
    TBool => src
    // Everything else answers a yes/no question by tutuca's own truthiness,
    // which is `Value::is_truthy` — so the conversion is through a Value
    // rather than a MoonBit `!= 0`, or the two backends would disagree about
    // `@show=".count"`.
    _ => "\{self.value_of(src, got)}.is_truthy()"
  }
}

///|
/// Emit an expression as a String — a sentence, which is what a `format` is.
///
/// Anything that is not already text goes through `to_display_string`, the same
/// conversion a `$'…'` template's interpolations take, so a number reads `3`
/// rather than `3.0` and a card and a compiled component say the same thing.
fn E::at_text(self : E, e : @tutuca.Expr) -> String raise NoWay {
  let (src, got) = self.expr(e)
  match got {
    TText => src
    _ => "\{self.value_of(src, got)}.to_display_string()"
  }
}

///|
/// Emit an expression as a `@tutuca.Value`, for a channel payload.
fn E::as_value(self : E, e : @tutuca.Expr) -> String raise NoWay {
  let (src, got) = self.expr(e)
  self.value_of(src, got)
}

///|
fn E::value_of(self : E, src : String, ty : @statedef.StateTy) -> String {
  // The schema's own projection, which the generated codec is written from
  // too. A set, a list of records and a tuple all need real conversion.
  let e = self.def.to_value_src(ty, src)
  // Annotated for the scalars, whose constructors are ambiguous in an
  // argument position; the compound forms carry their own annotation.
  match ty {
    TBool | TText | TInt(..) | TFloat => "(\{e} : @tutuca.Value)"
    _ => e
  }
}

///|
/// Insert whatever conversion `from` -> `to` needs, or refuse the pair.
fn E::to_ty(
  self : E,
  src : String,
  from : @statedef.StateTy,
  to : @statedef.StateTy,
) -> String raise NoWay {
  if from == to {
    return src
  }
  match (from, to) {
    // Widening into `Any`, which IS `@tutuca.Value` — the one direction that
    // needs no guess, because every language type has a Value spelling and the
    // codec already writes it. The other direction is refused where a raw
    // parameter is read: a Value could be anything, and picking one is the
    // guess this backend does not make.
    (_, TAny) => self.value_of(src, from)
    // The one numeric surface, made explicit. Truncating into an integer field
    // is what the generated codec's decode does with the same value.
    (TInt(..), TFloat) => "\{src}.to_double()"
    // A bare integer read that goes straight back into an integer place: the
    // normalization and its undoing cancel, and `s.count.to_double().to_int()`
    // is the same number spelled twice. Only the suffix WE wrote is peeled —
    // an arithmetic expression ends in `)`, so it never matches.
    (TFloat, TInt(..)) if src.has_suffix(".to_double()") =>
      src[0:src.length() - ".to_double()".length()].to_owned()
    (TFloat, TInt(..)) => "\{src}.to_int()"
    (TInt(..), TInt(..)) => src
    // An enum is a string at runtime, so a computed string can name a case —
    // but naming which case needs the generated enum's constructor, which this
    // does not build.
    (TText, TEnum(n)) =>
      raise Cannot(
        "assigning a computed string into the `\{n}` enum is not compiled yet",
      )
    _ =>
      raise Cannot(
        "a `\{from.show_source()}` does not fit where a `\{to.show_source()}` is wanted",
      )
  }
}

///|
/// Emit an expression, answering its source and its language type.
fn E::expr(
  self : E,
  e : @tutuca.Expr,
) -> (String, @statedef.StateTy) raise NoWay {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LBool(b) => (if b { "true" } else { "false" }, TBool)
        LStr(s) => (quote(s), TText)
        // Every literal number is a Double, because every arithmetic
        // expression is. The conversion happens where it meets a field.
        LNum(n) => (double_lit(n), TFloat)
        LNull => raise Cannot("`null` has no typed spelling here")
      }
    ETpl(parts~, ..) => {
      let b = StringBuilder()
      b.write_string("(")
      let mut first = true
      for part in parts {
        if !first {
          b.write_string(" + ")
        }
        first = false
        match part {
          TText(text=t, ..) => b.write_string(quote(t))
          // Through `to_display_string`, not MoonBit's `Show`: a template in a
          // slot renders JS-style (`3`, not `3.0`), and a card and a compiled
          // component have to agree about what the same template says.
          TExpr(inner) => {
            let (src, ty) = self.expr(inner)
            b.write_string("\{self.value_of(src, ty)}.to_display_string()")
          }
        }
      }
      b.write_string(")")
      (b.to_string(), TText)
    }
    ERead(place~, ..) => self.read(place)
    EName(name~, ..) => {
      // A `compute` or a `pred` the same block declares, called by name — the
      // spelling a body uses, since `$name` belongs to the render stack. The
      // answer is a `@tutuca.Value`, which is what a method returns.
      if !self.params.contains(name) && self.callables.get(name) is Some(f) {
        return ("\{f}(s, [], \{self.stack_arg()})", TAny)
      }
      guard self.params.get(name) is Some(ty) else {
        raise Cannot(
          if self.callables.is_empty() {
            "`\{name}` is not a parameter of this handler"
          } else {
            "`\{name}` is neither a parameter here nor a `pred` or `compute` this block declares"
          },
        )
      }
      guard ty is Some(t) else {
        // Inside a value body a raw argument is opaque rather than refused:
        // nothing declares what a `$name` call site passes, and the guard that
        // `at` emits where a type is wanted is a port of the interpreter's own
        // — so the two backends refuse the same argument at the same place.
        // A transition still refuses, because there the argument's shape is
        // what decides whether the transition happens at all.
        if self.fail != "" {
          return (local_of(name), TAny)
        }
        raise Cannot(
          "`\{name}`'s type is not known from the call sites, so it arrives as a raw value — annotate it by calling the handler consistently, or write the handler in MoonBit",
        )
      }
      // A parameter arrives as the type its pattern bound: a number is a
      // Double, which is the arithmetic surface.
      match t {
        TInt(..) => (local_of(name), TFloat)
        _ => (local_of(name), t)
      }
    }
    EUnary(op~, operand~, ..) =>
      match op {
        // `!expr`, not `not(expr)`: moonc deprecates the second, so a block
        // with a `not` in it made every generated module warn — and a strict
        // build (--deny-warn) reject a file whose author wrote nothing wrong.
        UNot => ("(!\{self.at_bool(operand)})", TBool)
        UNeg => ("(-\{self.at_num(operand)})", TFloat)
      }
    EChain(family~, ops~, operands~, ..) => self.chain(family, ops, operands)
    EIf(cond~, then_~, else_~, ..) => {
      let c = self.at_bool(cond)
      let (a, ta) = self.expr(then_)
      let bsrc = self.at(else_, ta)
      ("(if \{c} { \{a} } else { \{bsrc} })", ta)
    }
    EApp(name~, args~, ..) => self.app(name, args)
    EMethod(name~, ..) =>
      raise Cannot(
        "`$\{name}` is a `compute`, which a handler cannot call: it is answered by the render stack and a handler runs after one",
      )
    // The handler-side twin of a view's `*name`: the same question, walked
    // along the same default route, answered from this handler's position.
    // Opaque (`TAny`) because a dynamic binding is not in the schema and its
    // type is nobody's to state — which puts it on the same footing as an
    // event argument, and through the same guard when a type is wanted.
    EDyn(name~, ..) =>
      if self.in_value_body {
        // A value body is called BY the render stack, so the stack is what
        // answers — and `stack.lookup_dynamic` is literally the call the
        // interpreter makes for a `Val::Dyn` in a slot
        // (`core/value_eval.mbt`), so the two backends answer one question one
        // way rather than by a table kept in sync.
        self.uses_stack = true
        ("stack.lookup_dynamic(\{quote(name)})", TAny)
      } else {
        self.uses_ctx = true
        ("ctx.lookup(\{quote(name)}, @tutuca.LookupOpts::new())", TAny)
      }
    // Unreachable behind the checker, which refuses both by name — kept
    // because an emitter that would otherwise emit nothing is the wrong place
    // to learn that a pass upstream was skipped.
    EMacroVar(name~, ..) =>
      raise Cannot(
        "`^\{name}` is a macro argument, and a block has no macro slots: it is compiled once for the component rather than expanded at a call site",
      )
    EConfigVar(name~, ..) =>
      raise Cannot(
        "`$$\{name}` is a value the host bound, and a block is compiled ahead of any host",
      )
    ERef(..) => raise Cannot("a place is not a value")
    // The three forms only a SLOT produces. A block body cannot write one, so
    // reaching here means an AST assembled elsewhere — refused by name for the
    // reason the two above are, rather than emitted as something plausible.
    ETypeName(name~, ..) =>
      raise Cannot(
        "`\{name}` names a component type, and a handler asks for one with `ctx.make`",
      )
    EHandlerName(name~, ..) =>
      raise Cannot(
        "`\{name}` here is a handler name, which the render stack answers and a handler runs after",
      )
    EEventPath(segments~, ..) =>
      raise Cannot(
        "`e.\{segments.join(".")}` reads the DOM event a VIEW is handling, and a handler is called with its arguments already read",
      )
  }
}

///|
/// Read a place. Top-level fields and one level of record field; anything
/// indexed is a read this backend does not emit yet.
fn E::read(
  self : E,
  p : @tutuca.Place,
) -> (String, @statedef.StateTy) raise NoWay {
  // The target reads like a state path and for the same reason: it is a local
  // whose type is known at every step, so a field of one is a field access.
  if is_target(p) {
    let (name, ty) = self.target_root()
    let mut src = name
    let mut at = ty
    for st in p.steps {
      guard st is PField(sub) else {
        raise Cannot(
          "reading through an index into `@\{@tscript.target_bind}` needs a bounds check this backend does not emit yet — write the handler in MoonBit",
        )
      }
      guard self.def.field_of(at, sub) is Some(inner) else {
        raise Cannot("`\{at.show_source()}` has no field `\{sub}`")
      }
      src = "\{src}.\{binding_of(sub)}"
      at = inner
    }
    return (src, at)
  }
  // A path into an argument. `field_opt(…).unwrap_or(Null)` is exactly what
  // the interpreter does for the same steps, which is what lets a card and a
  // compiled component answer the same thing for `f.name`.
  //
  // It reads even when the call sites left the argument's type unstated, where
  // the argument ITSELF is refused: picking a field off a `Value` needs no
  // type, and the refusal below is about arithmetic and assignment.
  if p.root is PParam(param) {
    guard self.params.get(param) is Some(ty) else {
      raise Cannot("`\{param}` is not a parameter of this handler")
    }
    // A typed argument arrives UNWRAPPED — `Str(name)` binds a String — and
    // none of the types a call site can state has fields. The path is for the
    // arguments that stay values: a bind, a drag, a message payload.
    guard ty is None else {
      raise Cannot(
        "`\{param}` arrives as \{ty.unwrap().show_source()} from the call sites, and a \{ty.unwrap().show_source()} has no field `\{p.steps.map(s => if s is PField(n) { n } else { "?" }).join(".")}`",
      )
    }
    let mut src = local_of(param)
    for st in p.steps {
      guard st is PField(sub) else {
        raise Cannot(
          "reading through an index into `\{param}` needs a bounds check this backend does not emit yet — write the handler in MoonBit",
        )
      }
      src = "\{src}.field_opt(\{quote(sub)}).unwrap_or(Null)"
    }
    return (src, TAny)
  }
  guard p.root is PState(name) else {
    guard p.root is PBind(bind) else {
      raise Cannot("a binding is not readable from a handler")
    }
    // A body with bindings in scope: a `@when` has the loop's three, an
    // enricher has those plus whatever it has already written. `Any`, because
    // a binding is a `@tutuca.Value` and picking a type for one is the guess
    // this backend does not make — so it reads as a condition or travels as a
    // payload, and a typed use of it is refused below.
    guard self.binds.get(bind) is Some(src) else {
      raise Cannot(
        if self.binds_map == "" && self.binds.is_empty() {
          "`@\{bind}` is a binding, which a handler does not have — the renderer hands them to a `@when` or an `@enrich-with`"
        } else {
          "`@\{bind}` is not in scope here: a loop binds `@key`, `@value` and `@iter`, and an enricher may read one it wrote"
        },
      )
    }
    guard p.steps.is_empty() else {
      raise Cannot("reading a path into `@\{bind}` is not compiled yet")
    }
    return (src, TAny)
  }
  guard self.def.field(name) is Some(f) else {
    raise Cannot("`.\{name}` is not a field of the state")
  }
  self.uses_state = true
  let mut src = "s.\{binding_of(name)}"
  let mut ty = f.ty
  for st in p.steps {
    match st {
      PField(sub) => {
        guard self.def.field_of(ty, sub) is Some(inner) else {
          raise Cannot("`\{ty.show_source()}` has no field `\{sub}`")
        }
        src = "\{src}.\{binding_of(sub)}"
        ty = inner
      }
      PIndex(_) =>
        raise Cannot(
          "reading through an index needs a bounds check this backend does not emit yet — write the handler in MoonBit",
        )
    }
  }
  // An integer field is read at the arithmetic surface, like everything else.
  match ty {
    TInt(..) => (src + ".to_double()", TFloat)
    _ => (src, ty)
  }
}

///|
fn E::chain(
  self : E,
  family : @tutuca.OpFamily,
  ops : Array[String],
  operands : Array[@tutuca.Expr],
) -> (String, @statedef.StateTy) raise NoWay {
  match family {
    FLogic => {
      let b = StringBuilder()
      b.write_string("(\{self.at_bool(operands[0])}")
      for i, op in ops {
        b.write_string(if op == "and" { " && " } else { " || " })
        b.write_string(self.at_bool(operands[i + 1]))
      }
      b.write_string(")")
      (b.to_string(), TBool)
    }
    FImplies => {
      let a = self.at_bool(operands[0])
      let c = self.at_bool(operands[1])
      ("((!\{a}) || \{c})", TBool)
    }
    FCompare => {
      let (a, ta) = self.expr(operands[0])
      match ops[0] {
        // Structural equality, through `Value` — the same `Eq for Value`
        // everything else compares with, so two lists with equal contents
        // compare equal here as they do in a card.
        "is" | "is not" => {
          let (bsrc, tb) = self.expr(operands[1])
          let cmp = "(\{self.value_of(a, ta)} == \{self.value_of(bsrc, tb)})"
          // `!(a == b)` rather than `not(a == b)`, for the reason above.
          (if ops[0] == "is" { cmp } else { "(!\{cmp})" }, TBool)
        }
        op => {
          let x = self.to_ty(a, ta, TFloat)
          let y = self.at_num(operands[1])
          ("(\{x} \{op} \{y})", TBool)
        }
      }
    }
    FAdd | FMul => {
      // Two strings concatenate; everything else is arithmetic. The operands'
      // static types decide, exactly as the checker says.
      let (first, tf) = self.expr(operands[0])
      if family is FAdd && tf is TText {
        let b = StringBuilder()
        b.write_string("(\{first}")
        for i, _op in ops {
          b.write_string(" + \{self.at(operands[i + 1], TText)}")
        }
        b.write_string(")")
        return (b.to_string(), TText)
      }
      // Folded rather than appended, because `mod` WRAPS what came before it
      // instead of extending it: `a mod b` is a round trip through Int, and
      // the accumulated left-hand side has to be inside that trip. Growing one
      // string left to right cannot express an operator that reaches backwards.
      let mut acc = self.to_ty(first, tf, TFloat)
      for i, op in ops {
        // A zero divisor is "no change", which is what the interpreter
        // answers. MoonBit's Double division answers Infinity instead, and
        // `.to_int()` then saturates to 2^31-1 — a number, silently, where
        // the other backend said the body did not finish. The token to leave
        // through is the ROLE's: `Unchanged` in a transition, `Null` for a
        // `compute`, `false` for a `@when`. Emitting the transition's answer
        // unconditionally compiled a module that did not build — an
        // `Update` constructor where a `Value` was wanted.
        let rhs = if op == "/" || op == "mod" {
          let d = self.hoist("d\{i}", self.at_num(operands[i + 1]))
          let out = self.leave_token("a `\{op}`")
          self.prelude.push("guard \{d} != 0.0 else { return \{out} }")
          d
        } else {
          self.at_num(operands[i + 1])
        }
        acc = match op {
          // MoonBit has no `%` on Double, and the language's `mod` is over
          // whole numbers anyway — the interpreter truncates both sides too.
          "mod" => "((\{acc}).to_int() % (\{rhs}).to_int()).to_double()"
          _ => "(\{acc} \{op} \{rhs})"
        }
      }
      (acc, TFloat)
    }
  }
}

///|
/// A builtin applied to arguments.
fn E::app(
  self : E,
  name : String,
  args : Array[@tutuca.Expr],
) -> (String, @statedef.StateTy) raise NoWay {
  match (name, args.length()) {
    ("len", 1) => {
      let (src, ty) = self.expr(args[0])
      guard ty is (TList(_) | TText | TSet | TFlags(_) | TOMap(_)) else {
        raise Cannot("`len` needs a sized value, not `\{ty.show_source()}`")
      }
      ("\{src}.length().to_double()", TFloat)
    }
    ("min", 2) | ("max", 2) => {
      let a = self.at_num(args[0])
      let b = self.at_num(args[1])
      let cmp = if name == "min" { "<" } else { ">" }
      ("(if \{a} \{cmp} \{b} { \{a} } else { \{b} })", TFloat)
    }
    ("clamp", 3) => {
      let v = self.at_num(args[0])
      let lo = self.at_num(args[1])
      let hi = self.at_num(args[2])
      // The empty-range answer is `lo`, matching the interpreter: an empty
      // list makes `hi` -1 and a negative index is not an honest result.
      (
        "(if \{hi} < \{lo} { \{lo} } else if \{v} < \{lo} { \{lo} } else if \{v} > \{hi} { \{hi} } else { \{v} })",
        TFloat,
      )
    }
    ("int", 1) => ("\{self.at_num(args[0])}.to_int().to_double()", TFloat)
    ("num", 1) => (self.at_num(args[0]), TFloat)
    ("str", 1) => {
      let (src, ty) = self.expr(args[0])
      ("\{self.value_of(src, ty)}.to_display_string()", TText)
    }
    ("lower", 1) => ("\{self.at(args[0], TText)}.to_lower()", TText)
    ("upper", 1) => ("\{self.at(args[0], TText)}.to_upper()", TText)
    ("trim", 1) =>
      (
        "\{self.at(args[0], TText)}.trim(chars=\" \\t\\n\\r\").to_owned()",
        TText,
      )
    ("contains", 2) => {
      let hay = self.at(args[0], TText)
      let needle = self.at(args[1], TText)
      ("\{hay}.contains(\{needle})", TBool)
    }
    // `has` — a key in a set or a map, or a value in a list. Both, because the
    // interpreter answers both, and the two are one question asked of the two
    // shapes a collection has.
    //
    // The keyed case keys on the DISPLAY string, which is not a detail: it is
    // the key the generated `hasIn<X>` mutator looks up
    // (`component/component.mbt`) and the one the card's `tc_has` reads. A set
    // is Map-backed, so membership is the key being PRESENT — a member whose
    // value is somehow not `true` is still a member, which is what both other
    // implementations already answer.
    ("has", 2) => {
      let (hay, hay_ty) = self.expr(args[0])
      match hay_ty {
        TSet | TFlags(_) | TOMap(_) => {
          let (needle, needle_ty) = self.expr(args[1])
          (
            "\{hay}.contains(\{self.value_of(needle, needle_ty)}.to_display_string())",
            TBool,
          )
        }
        // A list is searched by EQUALITY, at the element's own type. Every
        // type the state emitter writes derives `Eq` — the scalars, the
        // records, the enums, and `Value` itself — so there is no shape this
        // has to turn down.
        TList(elem) => ("\{hay}.contains(\{self.at(args[1], elem)})", TBool)
        _ =>
          raise Cannot(
            "`has` asks a set, a map or a list, not `\{hay_ty.show_source()}`",
          )
      }
    }
    ("empty?", 1) => {
      let (src, ty) = self.expr(args[0])
      (
        "(\{self.value_of(src, ty)} is Null || @tutuca.size_of(\{self.value_of(src, ty)}) is Some(0))",
        TBool,
      )
    }
    ("truthy?", 1) | ("falsy?", 1) | ("null?", 1) => {
      let (src, ty) = self.expr(args[0])
      let v = self.value_of(src, ty)
      // Through `core`'s own table, so the four mean in a compiled handler
      // exactly what they mean in a `@show`. One table, one meaning.
      let call = "(match @tutuca.builtin(\{quote(name)}) { Some(b) => (b.apply)([\{v}]).is_truthy(); None => false })"
      (call, TBool)
    }
    _ => {
      // A sibling callable, applied. Its parameters bind raw, so the arguments
      // travel as Values — the same list a `$name` call site passes.
      if self.callables.get(name) is Some(f) {
        let vals : Array[String] = []
        for a in args {
          vals.push(self.as_value(a))
        }
        return ("\{f}(s, [\{vals.join(", ")}], \{self.stack_arg()})", TAny)
      }
      raise Cannot(
        "`\{name}` applied to \{args.length()} argument(s) is not compiled yet — write the handler in MoonBit",
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Spelling

///|
/// The MoonBit local an author-chosen script name binds to.
///
/// Author names and generated names share ONE namespace inside the emitted
/// function, and a script identifier is `[A-Za-z_][A-Za-z0-9_]*` — the same
/// alphabet MoonBit locals use, so there is no character to escape into.
/// Appending `_` is injective, so two script names stay two, and it lands
/// every author name in a region this emitter never writes into: nothing it
/// generates ends in `_` — not `s`/`_s`, `args`, `ctx`, `stack`, `binds`,
/// `key`/`value`/`iter_data`, `at`, and not the COUNTED ones, `v1`, `cur0`,
/// `d0`.
///
/// Those counted names are why this is a rename rather than a reserved-name
/// list: the set of generated names has no bound, so a list could only ever
/// be a snapshot of it, and the next emitter local would reopen the hole
/// silently. `receive setStatus(s) { .status = s }` emitted
/// `let s = { ..s, status: s }` — the parameter shadowing the state it was
/// being written into, a module that does not compile out of a script nobody
/// would look at twice.
///
/// Applied at the BINDING sites and every reference site, never to the keys of
/// `params`/`binds`: a diagnostic quotes what the author wrote.
fn local_of(name : String) -> String {
  name + "_"
}

///|
/// The MoonBit binding for a runtime field name — the same escape
/// `statedef/names.mbt` applies, reached through it so the two cannot drift.
fn binding_of(name : String) -> String {
  @statedef.binding_name(name)
}

///|
/// Both reached through `@statedef` for the same reason `binding_of` is.
fn quote(s : String) -> String {
  @statedef.quote(s)
}

///|
fn double_lit(d : Double) -> String {
  @statedef.double_lit(d)
}
