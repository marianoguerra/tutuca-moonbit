// Card in, `tutuca:component@0.9.0` core module out.
//
// The pipeline is the card runtime's, with one stage swapped:
//
//   viewfile.split_file    the blocks              (tutucard does this too)
//   statedef               the schema              (already done by split_file)
//   tscript.parse_script   the behaviour           (tutucard does this too)
//   ---- and then, instead of an interpreter ----
//   emit_module            a Wax module
//   wax/compile            a core wasm module
//
// So a compiled card and an interpreted one are the SAME card read the same
// way, and the only thing that differs is what runs the handlers. That is the
// property worth protecting: two front ends would be two languages.

///|
/// Bailing out of ONE declaration. Caught per declaration, turned into a
/// `Refusal`, and the rest of the card carries on.
priv suberror Bail {
  Bail(String)
}

///|
/// Everything the emitters share while building one card's module.
priv struct Gen {
  /// SHARED across every component of one card. Interning is content-addressed,
  /// so two components' `"toggle"` is one constant, and the data segment and
  /// the `#[start]` that builds it are laid down once for the module.
  pool : @abi.Pool
  comp : String
  /// This component's position in the module: which arm of the constructor
  /// builds it, which arm of the dispatch answers for it, and which slot of
  /// `tc_types` holds its record type.
  idx : Int
  /// Every component the FILE declares, so `new TodoItem` resolves to the
  /// sibling rather than to a type this component's schema does not have.
  siblings : Array[String]
  /// Whether the FILE declares more than one component.
  ///
  /// The only thing that decides whether a generated name is qualified — see
  /// `Gen::sym`. False for every card that has ever compiled, and then every
  /// name is what it was.
  many : Bool
  /// The state fields, in declaration order. A field's INDEX is its cell's
  /// position, and nothing else addresses one.
  fields : Array[@statedef.FieldDef]
  index : Map[String, Int]
  def : @statedef.StateDef
  /// The value-returning declarations a body may call bare: `compute`,
  /// `pred`, `invariant`.
  callables : Map[String, @tscript.Decl]
  /// SHARED, like the pool: `Compiled.refusals` is one list for the card, and
  /// components are compiled one after another into it. Each entry names its
  /// own component, which is what keeps two `toggle`s apart.
  refusals : Array[Refusal]
  /// Set when a body compiles an effect, so the module imports `control` only
  /// if it uses it. A guest chooses what it imports, and an import it does not
  /// need is one more thing the host has to be willing to grant.
  mut uses_control : Bool
  /// Set when the card can hold or build a collection, so the module imports
  /// the `values` arena only if a compound value can actually reach the
  /// boundary. Same argument as `uses_control`, and the same consequence: it
  /// decides which of the two lowering halves the runtime is built from.
  mut uses_values : Bool
  /// Set when a body compiles `num` or `int`, so the module carries the decimal
  /// parser only if something can call it. Not an import decision like the two
  /// above — it is a size one, and Wax emits every function it is handed.
  mut uses_num : Bool
  /// Set when a body compiles `sendAt`, which is the only effect that carries a
  /// path — and the only one that needs the reifying half of the runtime.
  mut uses_send_at : Bool
  /// Whether any of the four ROUTED effects compiled — `intent`, `forward`,
  /// `reply` or `fail`. One flag rather than four, because a host that
  /// provides one provides all four, and a card that reaches for none should
  /// not import them.
  mut uses_routed_effects : Bool
  /// Set when a transition has a `requires`, an `ensures` or an invariant to
  /// check — which is when there is something that can decline, and so
  /// something to say. Unlike the two above this one reaches the import
  /// section: saying it needs `control.log`.
  mut uses_contract_log : Bool
  /// Set when a body builds a child — `new <Component>` — so the module
  /// imports `control.make-instance` and carries `make_child.wax` only then.
  mut uses_children : Bool
  /// The declarations this card's `<script type="tutuca/wax">` block answers,
  /// by kind word and name. A name in here takes the dispatch arm the block
  /// language would have had, and its `Refusal` becomes an `Escape`.
  escapes : Map[String, EscapeFn]
  /// Fresh names for temporaries, per emitted function.
  mut temp : Int
  /// The script block's position in the FILE, for rebasing a refusal's span.
  block_line : Int
  block_offset : Int
  block_text : String
}

///|
/// A generated module-level name, qualified by component when the file needs it.
///
/// `many` is false for a card that declares one component, and then this is the
/// IDENTITY — which is the whole compatibility story. `get_count` / `set_count`
/// / `num_count` are documented as what an escape author writes with, and
/// `card_<role>_<name>` is a name somebody typed; a card that has not changed
/// must not lose its escape block to a feature it does not use.
///
/// A card that declares several is new surface, so the qualified branch owes
/// nothing to anybody. It stays under the same reserved prefix, so the screen
/// that stops an escape defining into `get_` still stops it defining into
/// `get_TodoItem_`.
fn Gen::sym(self : Gen, stem : String, name : String) -> String {
  if self.many {
    stem + self.comp + "_" + name
  } else {
    stem + name
  }
}

///|
fn Gen::fresh(self : Gen, stem : String) -> String {
  self.temp = self.temp + 1
  stem + "_" + self.temp.to_string()
}

///|
/// Record a refusal against a declaration, in the card's own coordinates.
fn Gen::refuse(
  self : Gen,
  kind : String,
  name : String,
  reason : String,
  span : @tscript.Span,
) -> Unit {
  self.refusals.push({
    comp: self.comp,
    kind,
    name,
    reason,
    line: self.block_line + line_of(self.block_text, span.start) - 1,
    span: {
      start: span.start + self.block_offset,
      end_: span.end_ + self.block_offset,
    },
  })
}

///|
/// The 1-based line of a character offset in `text`.
fn line_of(text : String, offset : Int) -> Int {
  let chars = text.to_array()
  let mut line = 1
  let n = if offset < chars.length() { offset } else { chars.length() }
  for i in 0..<n {
    if chars[i] == '\n' {
      line = line + 1
    }
  }
  line
}

// ---------------------------------------------------------------------------
// the entry point

///|
/// Compile one card's `.html` source into a core wasm module.
///
/// `name` names the component when the file's blocks do not, exactly as
/// `tutucard.load`'s does.
///
/// `allow_wax` decides whether the card's `<script type="tutuca/wax">` block —
/// the escape hatch — is compiled or refused. It is OFF by default, and that is
/// a trust decision rather than a feature flag: a card is untrusted content in
/// the `<mb-card>` story, so whether one may carry hand-written code at all
/// belongs to the host that mounts it. With it off, a block is a `Refusal`
/// naming the block rather than something quietly ignored.
///
/// It is not the only thing keeping an escape honest, and not the important
/// one: `escape.mbt`'s screen takes functions and refuses everything a guest's
/// authority is made of, so an escape cannot widen the import section whatever
/// this is set to.
pub fn compile(
  source : String,
  name~ : String,
  allow_wax? : Bool = false,
) -> Compiled raise GenError {
  let file = @viewfile.split_file(source, name~) catch {
    e => raise BadCard(e.message())
  }
  guard file.components.get(0) is Some(root_views) else {
    raise BadCard(
      "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible",
    )
  }
  // The root: what a `data-root` marker names, or the first component in the
  // file. `components[0]` stays what it always was — a file-level `<style>`
  // belongs to it — so the marker moves which component a HOST mounts and
  // nothing else.
  let components = file.components.map(v => v.component_name(name))
  let root = if file.root != "" && components.contains(file.root) {
    file.root
  } else {
    root_views.component_name(name)
  }
  let many = file.components.length() > 1
  // SHARED across every component: one data segment, one `#[start]` interning
  // it, and one list of refusals — which is what `Compiled` carries. Interning
  // is content-addressed, so two components saying `"toggle"` is one constant.
  let pool = @abi.Pool::new()
  let refusals : Array[Refusal] = []
  let comps : Array[Comp] = []
  for idx, views in file.components {
    let comp = views.component_name(name)
    // A card with no `<script type="tutuca/state">` block is a card with no
    // fields, and it used to be turned away whole. That was wrong twice over:
    // `tutucard.load` mounts one happily, so the two backends disagreed about
    // what a card IS; and `viewfile` has a name for the shape — a SCHEMA-LESS
    // file, whose views are built at runtime — so it is a thing people write.
    //
    // What comes out is a guest with an empty `jv_record` type: `get-field`
    // answers `none` for everything, `with-field` refuses everything, and any
    // handler the script declares is refused for naming a field that does not
    // exist. All of which is the truth about a card with no state, and all of
    // which the host can act on.
    let def = match state_for(file, comp, name) {
      Some(d) => d
      None =>
        {
          source_name: comp,
          component: comp,
          fields: [],
          receive: [],
          intent: [],
          types: [],
          doc: None,
        }
    }
    let block = script_for(file, comp)
    let decls : Array[@tscript.Decl] = match block {
      Some(b) =>
        @tscript.parse_script(b.text) catch {
          e =>
            raise BadCard(
              "line " +
              (b.line + line_of(b.text, e.span().start) - 1).to_string() +
              ": " +
              e.message(),
            )
        }
      None => []
    }
    // The CHECKER, before a single instruction is built.
    //
    // `tutucard.load` runs this and reports the findings beside the card; the
    // generator used to skip it and go straight to codegen, which meant a card
    // saying `.count = nope` reached `expr.mbt` and was refused there — by
    // name, with a worse reason than the checker's, and with the rest of the
    // card still compiling around it.
    //
    // A name that resolves to nothing is not a feature this backend has yet to
    // implement; it is a card that does not typecheck, and the honest answer is
    // to reject it rather than to emit a module with a hole where a handler
    // should be. So the findings are errors here, spelled in the checker's own
    // words and pointing at the card's own columns.
    match block {
      Some(b) => {
        let bad : Array[String] = []
        for
          f in @check.check(
            decls,
            def,
            // The siblings, so `new TodoItem` is the child and not a type this
            // component's schema is missing.
            surface={ inputs: Map([]), knows_views: false, comps: components },
          ) {
          // A warning is not a card that does not typecheck. The paragraph
          // above argues that a name resolving to nothing should be rejected
          // rather than compiled around, and that argument is about ERRORS; the
          // one warning the checker has (`NO_VIEW_HANDLER`) reports code that
          // behaves exactly as it did before, so stopping a build for it would
          // break every card that upgrades.
          if f.severity is SWarning {
            continue
          }
          bad.push(
            "line " +
            (b.line + line_of(b.text, f.span.start) - 1).to_string() +
            " [" +
            f.code +
            "]: " +
            f.message,
          )
        }
        guard bad.is_empty() else { raise BadScript(bad) }
      }
      None => ()
    }
    let g : Gen = {
      pool,
      comp,
      idx,
      many,
      siblings: components,
      fields: def.fields,
      index: Map([]),
      def,
      callables: Map([]),
      refusals,
      uses_control: false,
      uses_values: false,
      uses_num: false,
      uses_send_at: false,
      uses_routed_effects: false,
      uses_contract_log: false,
      uses_children: false,
      escapes: Map([]),
      temp: 0,
      block_line: match block {
        Some(b) => b.line
        None => 1
      },
      block_offset: match block {
        Some(b) => b.offset
        None => 0
      },
      block_text: match block {
        Some(b) => b.text
        None => ""
      },
    }
    for i, f in def.fields {
      g.index[f.name] = i
    }
    // Every declaration that answers through `call-method`, which is now five
    // kinds rather than three: the two enrichers reach a view through the Alter
    // namespace and used to reach nothing at all.
    //
    // An enricher's name is NOT callable from an expression, and does not
    // become so by being in here: `tscript/check` answers `NO_NAME` for a bare
    // one — "a bare name is a parameter, a builtin, or a `pred` or `compute`
    // this block declares" — so a card that tried would be rejected before a
    // single instruction was built.
    for d in decls {
      if d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) {
        g.callables[d.name] = d
      }
    }
    // The escape block, parsed and screened BEFORE anything is emitted — so
    // that the fixpoint over the callables and the dispatch chains already know
    // which names a hand-written function answers.
    let escape_fields : Array[@abi.Field] = match wax_for(file, comp) {
      Some(b) if allow_wax => {
        let (fields, defined) = parse_escape(
          b.text,
          "<" + comp + ".wax>",
          comp~,
        )
        for e in defined {
          // A helper carries no kind and answers no declaration; it is there
          // for the functions that do.
          if e.kind != "" {
            g.escapes[e.kind + " " + e.name] = e
          }
        }
        // AN ESCAPE MAY DO ANYTHING, and the generator cannot know what.
        //
        // Every other one of these flags is inferred from what a compiled body
        // actually said — a card that performs no effect imports no `control`,
        // one that never writes `num` carries no parser. A hand-written
        // function is opaque to all of that: it may call `tcx_send`, it may
        // build a map, it may reach for `tc_int`. So the whole vocabulary the
        // documentation promises is made available, and the import section
        // widens to match.
        //
        // That widening is the real cost of the escape hatch and the reason
        // `allow_wax` is a host's decision rather than a card's: a card with a
        // block like this asks for `control` whether or not it uses it, and a
        // host reads the import section to know what a guest can do.
        g.uses_control = true
        g.uses_values = true
        g.uses_num = true
        g.uses_send_at = true
        fields
      }
      // A block the host did not allow is REFUSED rather than ignored. A card
      // whose escape silently did nothing would be a card whose author cannot
      // tell "the host said no" from "I spelled the function wrong".
      Some(b) => {
        g.refusals.push({
          comp,
          kind: "wax",
          name: comp,
          reason: "this host compiles cards without their `<script type=\"tutuca/wax\"> block — whether a card may carry hand-written code is the host's decision, and this one did not grant it",
          line: b.line,
          span: { start: b.offset, end_: b.offset + b.text.length() },
        })
        []
      }
      None => []
    }
    comps.push({ g, decls, escape_fields })
  }
  // Two escape blocks defining the same function.
  //
  // Every block's fields are spliced into ONE module, so two components each
  // writing `fn round_half_up(...)` is a duplicate definition — which Wax
  // rejects, and which this backend would report as `BadModule`, the error
  // whose message says "this is a cardwasm bug". It is not: the card's author
  // typed both. So it is caught here, named, and reported as what it is.
  let seen : Map[String, String] = Map([])
  let clashes : Array[String] = []
  for c in comps {
    for f in c.escape_fields {
      match f.desc {
        Func(name~, ..) =>
          match seen.get(name.name) {
            Some(first) =>
              clashes.push(
                "`" +
                name.name +
                "` is defined by both `" +
                first +
                "` and `" +
                c.g.comp +
                "` — every escape block is spliced into one module, so a helper two components both want needs one name each",
              )
            None => seen[name.name] = c.g.comp
          }
        _ => ()
      }
    }
  }
  guard clashes.is_empty() else { raise BadEscape(clashes) }
  // The root's own `Gen` and views, which is not `comps[0]` when a `data-root`
  // marker moved it. `emit_module` still leads with `comps[0]` — the module's
  // shared pool and flags live on whichever it holds — but everything a host
  // READS about this card is named after the root.
  let mut root_g = comps[0].g
  for c in comps {
    if c.g.comp == root {
      root_g = c.g
    }
  }
  let g = root_g
  let comp = root
  let module_ = emit_module(comps)
  let session = @compile.Session::new()
  let checked = session.check(module_)
  let reports = session.reports()
  if @compile.rejected(reports) {
    raise BadModule(reports.map(d => @message.to_plain_string(d.message)))
  }
  let wasm = checked.to_bytes() catch { e => raise BadModule([e.to_string()]) }
  let wat = checked.to_wat() catch { _ => "" }
  // The tree back as Wax. A fresh trivia context because there is none to
  // carry: nothing here was parsed from text a reader wrote, so there are no
  // comments and no blank lines to put back.
  let wax = @waxfacade.render(module_, @trivia.Context::new())
  {
    component: comp,
    components,
    wasm,
    wat,
    wax,
    refusals: g.refusals,
    // Every component's escapes, not just the root's: `Compiled.escapes` is a
    // report about the CARD, the same way `refusals` is.
    escapes: comps
    .map(c => escape_list(c.g, c.decls))
    .fold(init=[], (a, b) => a + b),
    // The ROOT's fields. A host reading this is asking about the component it
    // is going to mount; the rest are in the manifest, per component, where a
    // host that wants them can ask by name.
    fields: g.def.fields.map(f => f.name),
    manifest: manifest_json(comps, file, g),
    descriptor: Json::object({
      "world": Json::string("tutuca:component@0.9.0"),
      // utf8 rather than the shipped guests' utf16: a constant pool laid down
      // as a data segment is bytes, and `abi.mjs` implements both.
      "encoding": Json::string("utf8"),
      "core": Json::string(comp.to_lower() + ".component.core.wasm"),
    }),
  }
}

// ---------------------------------------------------------------------------
// the module

///|
fn emit_module(comps : Array[Comp]) -> @ast.LocModule raise GenError {
  let g = comps[0].g
  // Bodies first: every one of them interns constants, and neither the data
  // segment nor the `#[start]` that builds them can be laid down until the pool
  // has stopped growing.
  // Every component's bodies, and the union of what they used. A flag is set
  // while a body compiles, so `uses_control` for the MODULE is true when any
  // component's body performed an effect — and the import section is a
  // statement about the module.
  let card = card_fields(comps)
  for c in comps {
    if c.g.uses_control {
      g.uses_control = true
    }
    if c.g.uses_values {
      g.uses_values = true
    }
    if c.g.uses_num {
      g.uses_num = true
    }
    if c.g.uses_send_at {
      g.uses_send_at = true
    }
    if c.g.uses_routed_effects {
      g.uses_routed_effects = true
    }
    if c.g.uses_children {
      g.uses_children = true
    }
    if c.g.uses_contract_log {
      g.uses_contract_log = true
    }
  }
  let alloc = runtime_fields()
  let fs : @ast.LocModule = []
  // The stdlib first: Wax resolves in one pass, so a name must be defined
  // before it is used, and everything below may call into it.
  // `waxsrc` raises its own error, because the dependency runs the other way:
  // it knows nothing about cards. A failure there is never a card's fault, so
  // it lands as `BadModule` — the error that already means "this is a compiler
  // bug".
  let stdlib = @waxsrc.stdlib_fields() catch {
    e => raise BadModule(e.reasons())
  }
  for f in stdlib {
    fs.push(f)
  }
  fs.push(
    @build.import_func(
      @abi.resource_iface,
      "[resource-new]instance",
      as_=Some("resource_new"),
      params=[(Some("rep"), i32_)],
      results=[i32_],
    ),
  )
  if g.uses_control {
    fs.push(
      @build.import_func(@abi.control_iface, "send", as_=Some("ctl_send"), params=[
        (Some("np"), i32_),
        (Some("nl"), i32_),
        (Some("ap"), i32_),
        (Some("al"), i32_),
      ]),
    )
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "stop-propagation",
        as_=Some("ctl_stop"),
      ),
    )
  }
  // Only a card that says `sendAt` asks for this one. `control` is already
  // imported by then — an effect is what set `uses_control` — so this is a
  // sixth function on an interface the module already names, rather than a new
  // thing to be granted.
  // Outside the `uses_control` block on purpose: a card can declare an
  // `invariant` and perform no effect at all, and it still has something to say
  // when the rule turns a transition away.
  if g.uses_contract_log {
    fs.push(
      @build.import_func(@abi.control_iface, "log", as_=Some("ctl_log"), params=[
        (Some("level"), i32_),
        (Some("p"), i32_),
        (Some("l"), i32_),
      ]),
    )
  }
  // Only a card that BUILDS a child asks for this one, and asking for it is the
  // whole claim: a card that composes children something else made imports
  // nothing here, and a host reads the import section to know which it has.
  //
  // No capability gates it (`abi.mjs` binds it with no `cap`), because a child
  // of the same bundle is not a reach outside it — the component it names has
  // to be one this manifest declares.
  if g.uses_children {
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "make-instance",
        as_=Some("tc_make_instance"),
        params=[
          (Some("np"), i32_),
          (Some("nl"), i32_),
          (Some("ap"), i32_),
          (Some("al"), i32_),
        ],
        results=[i64_],
      ),
    )
  }
  // The routed effects. Emitted only when a card performs one, so a card that
  // only sends imports only `send` — the import section is what the card
  // actually reaches for, and no more.
  if g.uses_routed_effects {
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "intent",
        as_=Some("ctl_intent"),
        params=[
          (Some("np"), i32_),
          (Some("nl"), i32_),
          (Some("ap"), i32_),
          (Some("al"), i32_),
          ..intent_opts_params(),
        ],
      ),
    )
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "forward",
        as_=Some("ctl_forward"),
        params=[
          // An empty argument list is "no amendment", which is the same thing
          // `forward` with no arguments means — so there is no third state to
          // encode and no discriminant to carry.
          (Some("ap"), i32_),
          (Some("al"), i32_),
          ..intent_opts_params(),
        ],
      ),
    )
    // `reply` and `fail` each take ONE `value`, not a list of them, and a
    // `value` flattens to three core values rather than to a pointer: the
    // discriminant, the joined payload (a f64, a handle or a string's pointer
    // all fit an i64), and the string case's length.
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "reply",
        as_=Some("ctl_reply"),
        params=[..value_params()],
      ),
    )
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "fail",
        as_=Some("ctl_fail"),
        params=[..value_params()],
      ),
    )
  }
  if g.uses_send_at {
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "send-at",
        as_=Some("ctl_send_at"),
        params=[
          (Some("sp"), i32_),
          (Some("sl"), i32_),
          (Some("np"), i32_),
          (Some("nl"), i32_),
          (Some("ap"), i32_),
          (Some("al"), i32_),
        ],
      ),
    )
  }
  fs.push(memory_field(2))
  fs.push(data_field("pool", @abi.pool_base, g.pool.to_bytes()))
  fs.push(global_i32("heap", g.pool.heap_base()))
  // The allocator has to precede the runtime source, which calls it to put a
  // string's bytes where the host can read them.
  for f in alloc {
    fs.push(f)
  }
  let runtime = @waxsrc.runtime_wax_fields(
    g.uses_values,
    uses_num=g.uses_num,
    uses_send_at=g.uses_send_at,
    uses_contract_log=g.uses_contract_log,
    uses_children=g.uses_children,
    uses_escape=comps
      .iter()
      .any(c => c.g.escapes.length() > 0 || !c.escape_fields.is_empty()),
  ) catch {
    e => raise BadModule(e.reasons())
  }
  for f in runtime {
    fs.push(f)
  }
  for f in card {
    fs.push(f)
  }
  fs
}

///|
/// The half of the module the card decides.
/// One component on its way into the module: its `Gen`, what its block
/// declared, and what its escape block answered.
///
/// Three parallel arrays would say the same thing and let two of them get out
/// of step. They are indexed together everywhere they are read.
priv struct Comp {
  g : Gen
  decls : Array[@tscript.Decl]
  escape_fields : Array[@abi.Field]
}

///|
/// Every function the module carries, in the order Wax resolves them.
///
/// A card used to be one component, so this took one `Gen` and read like it.
/// It takes the list now, and the shape of the list is what the file says:
/// what is emitted PER COMPONENT — its schema, its accessors, its callables,
/// its escapes, its dispatch arms — sits inside a loop, and what the module has
/// exactly one of — the exports, the flush, `#[start]`, the post-returns —
/// sits outside it.
///
/// The ordering constraint that shaped this is unchanged and now applies across
/// components: `#[start]` interns the constant pool AND builds the schemas, so
/// it cannot be assembled until every body of every component has stopped
/// interning. Which is why it is still last.
fn card_fields(comps : Array[Comp]) -> Array[@abi.Field] {
  // The first component's `Gen` answers for the module wherever a
  // module-level decision needs one: they share a pool, a refusal list and —
  // after the union below — the same view of what the card uses.
  let g = comps[0].g
  let fs : Array[@abi.Field] = []

  // -- the schema ----------------------------------------------------------
  //
  // A card's state IS a `jv_record`: field name -> declared type, with the
  // default the type gives it. That replaces the whole of the old field table
  // — `field_index`'s memcmp chain, `clone_state`'s `memory.copy`, and the
  // offsets four places computed as `i * @abi.cell_size` — with one schema the
  // record layer reads.
  //
  // The instructions are built here and the FUNCTION is assembled at the very
  // end, because both halves of `#[start]` depend on a pool that is still
  // growing: building the schema interns the field names, and compiling the
  // handlers interns everything a card says. Snapshotting the pool before
  // either leaves `tc_const` reading past what `#[start]` interned, which traps
  // on the first name it looks up.
  //
  // A card that can hold a compound value is a card whose `get-field` can be
  // asked for one, so it needs the arena — and one that cannot must not import
  // it. Asked of the DECLARED types rather than of what the handlers do,
  // because the host reads a field the handlers never touch.
  // One schema per component, PUSHED IN ORDER: a component's index is its slot
  // in `tc_types`, and that index is what the constructor's arm and the
  // dispatch's arm are numbered by. `sch` is bound once and reset per
  // component, because `#[start]` is one function and a second `let` of the
  // same name is a binding Wax will not resolve.
  let schema : Array[@abi.I] = [let_("sch", call("jv_record_schema_empty", []))]
  for c in comps {
    let cg = c.g
    for f in cg.fields {
      if compound_ty(f.ty) {
        cg.uses_values = true
      }
    }
    schema.push(set("sch", call("jv_record_schema_empty", [])))
    for f in cg.fields {
      match jv_type_of(cg, f) {
        Some(ty) =>
          schema.push(
            set(
              "sch",
              call("jv_record_schema_add", [
                get("sch"),
                text_const_str(cg.pool, f.name),
                ty,
                zero_value(cg, f),
              ]),
            ),
          )
        None => ()
      }
    }
    schema.push(
      call("tc_type_add", [
        call("jv_record_type_create", [
          text_const_str(cg.pool, cg.comp),
          get("sch"),
        ]),
      ]),
    )
  }

  // -- the exports ---------------------------------------------------------
  //
  // The constructor is handed the COMPONENT NAME and used to throw it away,
  // which was honest while a card was one component and a lie the moment it
  // stopped being. It reads it now, with the same pair every dispatch arm
  // already uses: `tc_str_in` lifts the (pointer, length), `tc_is` compares it
  // against a pool index. Each component's name is already interned — it is
  // the name its record type was created with.
  //
  // A name the bundle does not declare builds the ROOT. That is what a
  // one-component card did for every name it was ever handed, and it keeps a
  // host that guesses wrong from getting nothing at all.
  let ctor_body : Array[@abi.I] = if comps.length() == 1 {
    [
      call("resource_new", [
        call("tc_intern", [
          call("tc_apply_args", [
            call("tc_zero_of", [i32c(0)]),
            get("ap"),
            get("al"),
          ]),
        ]),
      ]),
    ]
  } else {
    let arms : Array[@abi.I] = [
      let_("name", call("tc_str_in", [get("np"), get("nl")])),
    ]
    for c in comps {
      arms.push(
        if_(
          call("tc_is", [get("name"), i32c(c.g.pool.string_index(c.g.comp))]),
          [
            ret(
              Some(
                call("resource_new", [
                  call("tc_intern", [
                    call("tc_apply_args", [
                      call("tc_zero_of", [i32c(c.g.idx)]),
                      get("ap"),
                      get("al"),
                    ]),
                  ]),
                ]),
              ),
            ),
          ],
          [],
        ),
      )
    }
    arms.push(
      call("resource_new", [
        call("tc_intern", [
          call("tc_apply_args", [
            call("tc_zero_of", [i32c(0)]),
            get("ap"),
            get("al"),
          ]),
        ]),
      ]),
    )
    arms
  }
  fs.push(
    func(
      "ctor",
      params=[("np", i32_), ("nl", i32_), ("ap", i32_), ("al", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#[constructor]instance",
      body=ctor_body,
    ),
  )

  // A guest that does not persist says so by answering nothing, and the host
  // then rebuilds from the declared fields — which it can do without asking.
  // A card's whole state IS its declared fields, so there is nothing here that
  // the host cannot already do better.
  fs.push(
    func(
      "restore",
      params=[("np", i32_), ("nl", i32_), ("bp", i32_), ("bl", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#[static]instance.restore",
      body=[
        mem("store32", [i32c(@abi.ret_restore), i32c(0)]),
        i32c(@abi.ret_restore),
      ],
    ),
  )
  fs.push(
    func(
      "persist",
      params=[("h", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#[method]instance.persist",
      body=[
        mem("store32", [i32c(@abi.ret_persist), i32c(0)]),
        mem("store32", [i32c(@abi.ret_persist + 4), i32c(0)]),
        i32c(@abi.ret_persist),
      ],
    ),
  )
  fs.push(
    func(
      "get_field",
      params=[("h", i32_), ("np", i32_), ("nl", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#[method]instance.get-field",
      body=[
        call("tc_get_field", [
          call("tc_deref", [get("h")]),
          get("np"),
          get("nl"),
          i32c(@abi.ret_get_field),
        ]),
        i32c(@abi.ret_get_field),
      ],
    ),
  )
  fs.push(
    func(
      "with_field",
      params=[
        ("h", i32_),
        ("np", i32_),
        ("nl", i32_),
        ("vkind", i32_),
        ("p64", i64_),
        ("p32", i32_),
      ],
      results=[i32_],
      export_as=@abi.guest_iface + "#[method]instance.with-field",
      body=[
        // The payload arrives JOINED: every case of `value` is widened to the
        // one (i64, i32) pair that holds any of them, and `tc_lift_flat` reads
        // the halves each case actually uses.
        //
        // The SCHEMA decides now. A name it does not carry and a value of the
        // wrong type both answer `none`, where this used to check the name and
        // then write whatever eight bytes it was handed into the cell.
        let_(
          "n",
          call("tc_with_field", [
            call("tc_deref", [get("h")]),
            get("np"),
            get("nl"),
            get("vkind"),
            get("p64"),
            get("p32"),
          ]),
        ),
        if_(
          lts(get("n"), i32c(0)),
          [
            mem("store32", [i32c(@abi.ret_with_field), i32c(0)]),
            ret(Some(i32c(@abi.ret_with_field))),
          ],
          [],
        ),
        mem("store32", [i32c(@abi.ret_with_field), i32c(1)]),
        mem("store32", [
          i32c(@abi.ret_with_field + 4),
          call("resource_new", [get("n")]),
        ]),
        i32c(@abi.ret_with_field),
      ],
    ),
  )

  // A card serves no requests: `request` in a block reaches the HOST, and a
  // bundle-served request is a second thing the manifest would have to declare.
  fs.push(
    func(
      "serve_intent",
      params=[("np", i32_), ("nl", i32_), ("ap", i32_), ("al", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#serve-intent",
      body=[
        mem("fill", [i32c(@abi.ret_serve_intent), i32c(0), i32c(24)]),
        mem("store32", [i32c(@abi.ret_serve_intent), i32c(1)]),
        i32c(@abi.ret_serve_intent),
      ],
    ),
  )
  // The flush, which is the only code that reaches `control`. Emitted here
  // rather than in `runtime/runtime.wax` because the imports it calls are
  // themselves conditional: a card that performs no effect has no `ctl_send`
  // to name, and Wax resolves names in one pass over one module.
  //
  // `uses_control` is set while compiling the bodies, so this reads it after
  // the callables and the dispatch chains are built — which is why the
  // function is pushed here and the decision made below.
  // Per component, in order, and the order WITHIN a component is the whole of
  // what its escape can reach.
  //
  // The callables first: a handler's `requires`, and a body that calls one
  // bare, both need to know which of them survived. THEN the escape — Wax
  // resolves in one pass, so a function may call anything defined ahead of it
  // and nothing defined after: an escape sits behind the stdlib, the runtime,
  // the per-field accessors and the compiled `cm_*` callables — so it can call
  // every one of those — and ahead of the dispatch chains, so those can call
  // it. That is exactly the reach an escape should have and no more.
  for c in comps {
    for f in callable_fields(c.g, c.decls) {
      fs.push(f)
    }
    if !c.escape_fields.is_empty() {
      for f in escape_prelude(c.g) {
        fs.push(f)
      }
      for f in c.escape_fields {
        fs.push(f)
      }
      // …and the `cm_<name>` forwarders last, so every call site that reaches
      // a callable reaches an escaped one the same way.
      for f in escape_wrappers(c.g) {
        fs.push(f)
      }
    }
  }
  fs.push(handle_event_fn(comps))
  fs.push(call_method_fn(comps))
  if g.uses_control {
    // Before `tc_flush`, which calls it: Wax resolves in one pass.
    if g.uses_routed_effects {
      fs.push(route_out_fn())
    }
    fs.push(flush_fn(g.uses_send_at, g.uses_routed_effects))
  }

  // `#[start]`, assembled now that NOTHING else will intern a constant: one
  // `tc_intern_const` per pool string in pool order, then the schema. A start
  // function may be declared after what it calls — it runs at instantiation,
  // not where it sits — so being last costs nothing.
  let boot : Array[@abi.I] = [call("tc_init", [])]
  for sc in g.pool.string_list {
    let (at, len) = sc
    boot.push(call("tc_intern_const", [i32c(at), i32c(len)]))
  }
  for i in schema {
    boot.push(i)
  }
  fs.push(func("tc_boot", body=boot, start=true))

  // The post-returns. A bump allocator with no free has nothing to do here,
  // and the ABI still requires the export to exist for every lift that owns
  // memory — so these are four honest no-ops rather than four absences.
  for
    name in [
      @abi.guest_iface + "#[method]instance.get-field",
      @abi.guest_iface + "#[method]instance.call-method",
      @abi.guest_iface + "#[method]instance.persist",
      @abi.guest_iface + "#serve-intent",
    ] {
    fs.push(
      func(
        g.fresh("post"),
        params=[("p", i32_)],
        export_as="cabi_post_" + name,
        body=[],
      ),
    )
  }
  fs
}

///|
/// WIT `intent-opts`, flattened: `route` as a (pointer, length) pair, then
/// three `option<string>` answer names — each a discriminant and the string's
/// two slots — and then `live-path`.
///
/// Twelve core values, which is why `intent` takes exactly sixteen: the
/// canonical ABI spills at seventeen, and a card that also passed a path would
/// be over. `intent-at` is the one this generator cannot emit, and that is the
/// arithmetic behind it rather than an oversight.
fn intent_opts_params() -> Array[(String?, @abi.VT)] {
  [
    (Some("rp"), i32_),
    (Some("rl"), i32_),
    (Some("ok_d"), i32_),
    (Some("ok_p"), i32_),
    (Some("ok_l"), i32_),
    (Some("er_d"), i32_),
    (Some("er_p"), i32_),
    (Some("er_l"), i32_),
    (Some("un_d"), i32_),
    (Some("un_p"), i32_),
    (Some("un_l"), i32_),
    (Some("live"), i32_),
  ]
}

///|
/// The ten of those a CARD always passes as zero.
///
/// A card names no answer arm and asks for no live path: `on-ok`, `on-error`
/// and `on-unhandled` are `none` — discriminant 0, and the two payload slots
/// of a case that has no payload are dead — and `live-path` is false. The
/// answer names come from the schema, which is where a card says them.
fn none_opts() -> Array[@abi.I] {
  Array::makei(10, _ => i32c(0))
}

///|
/// One `value`, flattened: the discriminant, the joined payload, and the one
/// slot only the `text` case uses.
fn value_params() -> Array[(String?, @abi.VT)] {
  [(Some("tag"), i32_), (Some("p64"), i64_), (Some("p32"), i32_)]
}

///|
/// The same three, read out of a 16-byte cell at `p`.
///
/// The cell is what `tc_lower` writes and what a `list<value>` is made of, and
/// its layout is the flat one rearranged: the discriminant at +0, the payload
/// at +8. `text` puts its pointer at +8 and its length at +12, so the i64 load
/// picks the pointer up in its low half — which is where the host reads it
/// from, since the joined slot is truncated to i32 for that case.
fn value_args(p : @abi.I) -> Array[@abi.I] {
  [
    mem("load32", [p]),
    mem("load64", [add(p, i32c(8))]),
    mem("load32", [add(p, i32c(12))]),
  ]
}

///|
/// `tc_route_out` — lower a route CODE to the `list<leg>` the WIT asks for,
/// answering its length.
///
/// The bytes go to `@abi.route_buf`, which the caller passes as the pointer.
/// One `store32` rather than one `store8` per leg: a route is at most two
/// bytes, the buffer is four wide and only `rl` of them is ever read, so the
/// whole list is one little-endian word — `lex` is 0x01, `dyn lex` is 0x0100,
/// `lex dyn` is 0x0001 and `dyn` is 0x00.
fn route_out_fn() -> @abi.Field {
  func("tc_route_out", params=[("code", i32_)], results=[i32_], body=[
    let_("w", i32c(0)),
    if_(eq(get("code"), i32c(@abi.route_lex)), [set("w", i32c(0x01))], []),
    if_(eq(get("code"), i32c(@abi.route_lex_dyn)), [set("w", i32c(0x01))], []),
    if_(eq(get("code"), i32c(@abi.route_dyn_lex)), [set("w", i32c(0x0100))], []),
    mem("store32", [i32c(@abi.route_buf), get("w")]),
    // `route_none` is the EMPTY list — "the card wrote no leg" — and the
    // host is what turns that into the default. The two-leg codes are the
    // two above `route_lex`.
    let_("n", i32c(1)),
    if_(eq(get("code"), i32c(@abi.route_none)), [set("n", i32c(0))], []),
    if_(ges(get("code"), i32c(@abi.route_dyn_lex)), [set("n", i32c(2))], []),
    ret(Some(get("n"))),
  ])
}

///|
/// `tc_flush` — hand the host the effects the transition buffered, in order.
///
/// The buffer is the runtime's; the switch is here because only the generated
/// half knows which of `ctl_send`, `ctl_emit`, `ctl_stop`, `ctl_request` and
/// `ctl_send_at` this module imported.
fn flush_fn(uses_send_at : Bool, uses_v2 : Bool) -> @abi.Field {
  // A FLAT chain rather than a nest. It was nested while there were four
  // kinds and it read as one; nine kinds nested five deep reads as nothing,
  // and every arm here is the same shape — compare the kind, make one call.
  let arms : Array[@abi.I] = [
    if_(
      eq(get("k"), i32c(1)),
      [call("ctl_send", [get("np"), get("nl"), get("ap"), get("al")])],
      [],
    ),
  ]
  if uses_send_at {
    // The path is lowered HERE rather than when the effect was buffered,
    // because what it lowers to is linear memory the host reads during this
    // call and nothing owns afterwards.
    arms.push(
      if_(
        eq(get("k"), i32c(5)),
        [
          call("ctl_send_at", [
            call("tc_effect_steps_ptr", [get("i")]),
            call("tc_effect_steps_len", [get("i")]),
            get("np"),
            get("nl"),
            get("ap"),
            get("al"),
          ]),
        ],
        [],
      ),
    )
  }
  if uses_v2 {
    // The route is lowered HERE, for the same reason a `sendAt`'s path is:
    // what it lowers to is linear memory the host reads during this call and
    // nothing owns afterwards. `tc_route_out` writes the bytes and answers the
    // length; `@abi.route_buf` is where it wrote them.
    arms.push(
      if_(
        eq(get("k"), i32c(6)),
        [
          let_(
            "rl",
            call("tc_route_out", [call("tc_effect_route", [get("i")])]),
          ),
          call(
            "ctl_intent",
            [
              get("np"),
              get("nl"),
              get("ap"),
              get("al"),
              i32c(@abi.route_buf),
              get("rl"),
              ..none_opts(),
            ],
          ),
        ],
        [],
      ),
    )
    arms.push(
      if_(
        eq(get("k"), i32c(7)),
        [
          let_(
            "rl",
            call("tc_route_out", [call("tc_effect_route", [get("i")])]),
          ),
          call(
            "ctl_forward",
            [
              get("ap"),
              get("al"),
              i32c(@abi.route_buf),
              get("rl"),
              ..none_opts(),
            ],
          ),
        ],
        [],
      ),
    )
    // One `value` each, and the buffer holds it as a one-element `list<value>`
    // — `reply` and `fail` are compiled from an expression that has to be
    // there — so the cell to flatten is the one at `ap`.
    arms.push(
      if_(eq(get("k"), i32c(8)), [call("ctl_reply", value_args(get("ap")))], []),
    )
    arms.push(
      if_(eq(get("k"), i32c(9)), [call("ctl_fail", value_args(get("ap")))], []),
    )
  }
  func("tc_flush", body=[
    let_("i", i32c(0)),
    while_(
      lts(get("i"), call("tc_effect_count", [])),
      Some(setop("i", Add, i32c(1))),
      [
        let_("k", call("tc_effect_kind", [get("i")])),
        // `stop` carries neither a name nor arguments, so it is answered before
        // the lifts rather than beside them.
        if_(
          eq(get("k"), i32c(3)),
          [call("ctl_stop", [])],
          [
            let_("np", call("tc_effect_name_ptr", [get("i")])),
            let_("nl", call("tc_effect_name_len", [get("i")])),
            let_("ap", call("tc_effect_args_ptr", [get("i")])),
            let_("al", call("tc_effect_args_len", [get("i")])),
            ..arms,
          ],
        ),
      ],
    ),
  ])
}

///|
/// Can a value of this type be a vector or a map?
///
/// The question the `values` arena import turns on. `TAny` counts because it is
/// the type that promises nothing, and `TOption` counts when what it wraps
/// does.
fn compound_ty(ty : @statedef.StateTy) -> Bool {
  match ty {
    TBool | TInt(..) | TFloat | TText | TEnum(_) | TComp(_) => false
    TOption(inner) => compound_ty(inner)
    _ => true
  }
}

///|
/// A field's declared type, as the `jv_type` the schema validates against.
///
/// This is where the refusal list got short. The cell runtime had four types
/// with a representation — Bool, Int, Float, Str — and everything else was
/// refused for having "no cell representation". `jv_value` has a
/// representation for all of them, so the mapping is total and there is
/// nothing left here to refuse.
///
/// `TInt` and `TFloat` are BOTH `jv_type_f64`, and that is not a shortcut:
/// tutuca has exactly one number (`Value::Num(Double)`), so a schema that told
/// them apart would be inventing a distinction the language does not have.
/// What an Int field does get is a truncation at its assignment sites —
/// `Gen::coerce` in `stmt.mbt`, which is where the interpreter does it too.
fn jv_type_of(g : Gen, f : @statedef.FieldDef) -> @abi.I? {
  Some(jv_type_expr(g, f.ty))
}

///|
fn jv_type_expr(g : Gen, ty : @statedef.StateTy) -> @abi.I {
  match ty {
    TBool => call("jv_type_bool", [])
    TInt(..) | TFloat => call("jv_type_f64", [])
    TText | TEnum(_) => call("jv_type_string", [])
    TList(inner) => call("jv_type_vector", [jv_type_expr(g, inner)])
    TOMap(inner) => call("jv_type_ordered_map", [jv_type_expr(g, inner)])
    // A set is a Map keyed by the member's display string, and a record and a
    // tuple are Maps too — tutuca's own representations, not a widening chosen
    // here. The VALUE type is unconstrained because none of the three carries
    // one the schema could check.
    //
    // ORDERED, like every map this compiler builds: tutuca's `Value::Map` is
    // MoonBit's `Map`, which is insertion ordered, and `@each` over a map field
    // renders in that order.
    TSet | TFlags(_) | TRecord(_) | TTuple(_) =>
      call("jv_type_ordered_map", [call("jv_type_any", [])])
    TOption(inner) => call("jv_type_optional", [jv_type_expr(g, inner)])
    // A variant is a Map or a Null depending on the case, a component slot is
    // a host-side thing a guest never holds, and `TAny` is the whole point of
    // being unconstrained.
    TVariant(_) | TComp(_) | TAny => call("jv_type_any", [])
  }
}

///|
/// A field's zero, as the value the schema carries as its default.
///
/// `@info.zero_of` rather than a mapping written out here: it is the same
/// function the interpreter's `Env` is built with (`zero_value`), so a field's
/// default cannot differ between the two backends by being stated twice.
fn zero_value(g : Gen, f : @statedef.FieldDef) -> @abi.I {
  const_value(g, @info.zero_of(g.def, f.ty))
}

///|
/// Any constant `@tutuca.Value` as the instructions that build it.
///
/// Used for a field's zero and for what `new T` hands to `@cur`. Both are
/// known when the module is built — a zero is a property of a declared type —
/// so this runs at compile time and emits a tree of constructors rather than
/// anything that reads a description at run time.
fn const_value(g : Gen, v : @tutuca.Value) -> @abi.I {
  match v {
    Null => call("tc_null", [])
    Bool(b) => call("tc_bool", [i32c(if b { 1 } else { 0 })])
    Num(x) => call("tc_num", [fconst(g.pool, x)])
    Str(t) => text_const(g.pool, t)
    List(xs) => {
      let mut acc = call("jv_vector_empty", [])
      for x in xs {
        acc = call("jv_vector_push", [acc, const_value(g, x)])
      }
      acc
    }
    Map(m) => {
      let mut acc = call("jv_ordered_map_empty", [])
      for k, x in m {
        acc = call("jv_ordered_map_assoc", [
          acc,
          text_const_str(g.pool, k),
          const_value(g, x),
        ])
      }
      acc
    }
    // A function and a component instance are host-side, and a zero is never
    // either: `TyInfo::zero` answers Null for `TComp` and `TAny`.
    _ => call("tc_null", [])
  }
}
