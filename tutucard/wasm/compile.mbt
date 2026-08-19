// Card in, `tutuca:component@0.8.0` core module out.
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
  pool : @abi.Pool
  comp : String
  /// The state fields, in declaration order. A field's INDEX is its cell's
  /// position, and nothing else addresses one.
  fields : Array[@statedef.FieldDef]
  index : Map[String, Int]
  def : @statedef.StateDef
  /// The value-returning declarations a body may call bare: `compute`,
  /// `pred`, `invariant`.
  callables : Map[String, @tscript.Decl]
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
  /// Whether any of v2's four effects compiled — `intent`, `forward`, `reply`
  /// or `fail`. One flag rather than four, because a card that says one of
  /// them is a v2 card and the host that hosts it provides all four; a v1 card
  /// says none and imports none, which is the property worth keeping.
  mut uses_v2_effects : Bool
  /// Set when a transition has a `requires`, an `ensures` or an invariant to
  /// check — which is when there is something that can decline, and so
  /// something to say. Unlike the two above this one reaches the import
  /// section: saying it needs `control.log`.
  mut uses_contract_log : Bool
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
  guard file.components.length() <= 1 else {
    raise BadCard(
      "a card is one component, but this file declares " +
      file.components.map(c => "`" + c.component_name(name) + "`").join(", "),
    )
  }
  guard file.components.get(0) is Some(views) else {
    raise BadCard(
      "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible",
    )
  }
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
  let def = match file.state.get(0) {
    Some(d) => d
    None =>
      {
        source_name: comp,
        component: comp,
        fields: [],
        receive: [],
        intent: [],
        bubble: [],
        response: [],
        types: [],
        doc: None,
      }
  }
  let block = file.script_for(comp)
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
  // saying `.count = nope` reached `expr.mbt` and was refused there — by name,
  // with a worse reason than the checker's, and with the rest of the card
  // still compiling around it.
  //
  // A name that resolves to nothing is not a feature this backend has yet to
  // implement; it is a card that does not typecheck, and the honest answer is
  // to reject it rather than to emit a module with a hole where a handler
  // should be. So the findings are errors here, spelled in the checker's own
  // words and pointing at the card's own columns.
  match block {
    Some(b) => {
      let bad : Array[String] = []
      for f in @check.check(decls, def) {
        // A warning is not a card that does not typecheck. The paragraph above
        // argues that a name resolving to nothing should be rejected rather
        // than compiled around, and that argument is about ERRORS; the one
        // warning the checker has (`NO_VIEW_HANDLER`) reports code that
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
    pool: @abi.Pool::new(),
    comp,
    fields: def.fields,
    index: Map([]),
    def,
    callables: Map([]),
    refusals: [],
    uses_control: false,
    uses_values: false,
    uses_num: false,
    uses_send_at: false,
    uses_v2_effects: false,
    uses_contract_log: false,
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
  // An enricher's name is NOT callable from an expression, and does not become
  // so by being in here: `tscript/check` answers `NO_NAME` for a bare one — "a
  // bare name is a parameter, a builtin, or a `pred` or `compute` this block
  // declares" — so a card that tried would be rejected before a single
  // instruction was built.
  for d in decls {
    if d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) {
      g.callables[d.name] = d
    }
  }
  // The escape block, parsed and screened BEFORE anything is emitted — so that
  // the fixpoint over the callables and the dispatch chains already know which
  // names a hand-written function answers.
  let escape_fields : Array[@abi.Field] = match file.wax_for(comp) {
    Some(b) if allow_wax => {
      let (fields, defined) = parse_escape(b.text, "<" + comp + ".wax>")
      for e in defined {
        // A helper carries no kind and answers no declaration; it is there for
        // the functions that do.
        if e.kind != "" {
          g.escapes[e.kind + " " + e.name] = e
        }
      }
      // AN ESCAPE MAY DO ANYTHING, and the generator cannot know what.
      //
      // Every other one of these flags is inferred from what a compiled body
      // actually said — a card that performs no effect imports no `control`,
      // one that never writes `num` carries no parser. A hand-written function
      // is opaque to all of that: it may call `tcx_send`, it may build a map,
      // it may reach for `tc_int`. So the whole vocabulary the documentation
      // promises is made available, and the import section widens to match.
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
        kind: "wax",
        name: comp,
        reason: "this host compiles cards without their `<script type=\"tutuca/wax\">` block — whether a card may carry hand-written code is the host's decision, and this one did not grant it",
        line: b.line,
        span: { start: b.offset, end_: b.offset + b.text.length() },
      })
      []
    }
    None => []
  }
  let module_ = emit_module(g, decls, escape_fields)
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
    wasm,
    wat,
    wax,
    refusals: g.refusals,
    escapes: escape_list(g, decls),
    fields: def.fields.map(f => f.name),
    manifest: manifest_json(g, decls, views, file),
    descriptor: Json::object({
      "world": Json::string("tutuca:component@0.8.0"),
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
fn emit_module(
  g : Gen,
  decls : Array[@tscript.Decl],
  escape_fields : Array[@abi.Field],
) -> @ast.LocModule raise GenError {
  // Bodies first: every one of them interns constants, and neither the data
  // segment nor the `#[start]` that builds them can be laid down until the pool
  // has stopped growing.
  let card = card_fields(g, decls, escape_fields)
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
      @build.import_func(@abi.control_iface, "emit", as_=Some("ctl_emit"), params=[
        (Some("np"), i32_),
        (Some("nl"), i32_),
        (Some("ap"), i32_),
        (Some("al"), i32_),
      ]),
    )
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
    // Fourteen i32s, which is what `(string, list<value>, request-opts)`
    // flattens to: two for the name, two for the arguments, three per
    // `option<string>` (a discriminant and the joined string payload) and one
    // for `live-path`. Under the canonical ABI's sixteen, so it stays flat
    // rather than going indirect through a pointer — `dyncomp/host/wasm/abi.mjs`
    // is where that limit lives and where these params were read off.
    fs.push(
      @build.import_func(
        @abi.control_iface,
        "request",
        as_=Some("ctl_request"),
        params=[
          (Some("np"), i32_),
          (Some("nl"), i32_),
          (Some("ap"), i32_),
          (Some("al"), i32_),
          (Some("ok_d"), i32_),
          (Some("ok_p"), i32_),
          (Some("ok_l"), i32_),
          (Some("er_d"), i32_),
          (Some("er_p"), i32_),
          (Some("er_l"), i32_),
          (Some("rs_d"), i32_),
          (Some("rs_p"), i32_),
          (Some("rs_l"), i32_),
          (Some("live"), i32_),
        ],
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
  // v2's four. Emitted only when a card performs one, so a v1 card's import
  // section is exactly what it was — which is what keeps an old bundle
  // loadable by a host that has not been rebuilt.
  if g.uses_v2_effects {
    fs.push(
      @build.import_func(@abi.control_iface, "intent", as_=Some("ctl_intent"), params=[
        (Some("np"), i32_),
        (Some("nl"), i32_),
        (Some("ap"), i32_),
        (Some("al"), i32_),
        // The route, as `@abi.route_*`. One i32 because the set is closed.
        (Some("rt"), i32_),
      ]),
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
          (Some("rt"), i32_),
        ],
      ),
    )
    fs.push(
      @build.import_func(@abi.control_iface, "reply", as_=Some("ctl_reply"), params=[
        (Some("ap"), i32_),
        (Some("al"), i32_),
      ]),
    )
    fs.push(
      @build.import_func(@abi.control_iface, "fail", as_=Some("ctl_fail"), params=[
        (Some("ap"), i32_),
        (Some("al"), i32_),
      ]),
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
    uses_escape=g.escapes.length() > 0 || !escape_fields.is_empty(),
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
fn card_fields(
  g : Gen,
  decls : Array[@tscript.Decl],
  escape_fields : Array[@abi.Field],
) -> Array[@abi.Field] {
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
  for f in g.fields {
    if compound_ty(f.ty) {
      g.uses_values = true
    }
  }
  let schema : Array[@abi.I] = [let_("sch", call("jv_record_schema_empty", []))]
  for f in g.fields {
    match jv_type_of(g, f) {
      Some(ty) =>
        schema.push(
          set(
            "sch",
            call("jv_record_schema_add", [
              get("sch"),
              text_const_str(g.pool, f.name),
              ty,
              zero_value(g, f),
            ]),
          ),
        )
      None => ()
    }
  }
  schema.push(
    set(
      "tc_state_type",
      call("jv_record_type_create", [text_const_str(g.pool, g.comp), get("sch")]),
    ),
  )

  // -- the exports ---------------------------------------------------------
  fs.push(
    func(
      "ctor",
      params=[("np", i32_), ("nl", i32_), ("ap", i32_), ("al", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#[constructor]instance",
      body=[
        call("resource_new", [
          call("tc_intern", [
            call("tc_apply_args", [call("tc_zero", []), get("ap"), get("al")]),
          ]),
        ]),
      ],
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
      "handle_request",
      params=[("np", i32_), ("nl", i32_), ("ap", i32_), ("al", i32_)],
      results=[i32_],
      export_as=@abi.guest_iface + "#handle-request",
      body=[
        mem("fill", [i32c(@abi.ret_handle_request), i32c(0), i32c(24)]),
        mem("store32", [i32c(@abi.ret_handle_request), i32c(1)]),
        i32c(@abi.ret_handle_request),
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
  // The callables first: a handler's `requires`, and a body that calls one
  // bare, both need to know which of them survived.
  for f in callable_fields(g, decls) {
    fs.push(f)
  }
  // THEN the escape, and the order is the whole of what it can reach. Wax
  // resolves in one pass, so a function may call anything defined ahead of it
  // and nothing defined after: an escape sits behind the stdlib, the runtime,
  // the per-field accessors and the compiled `cm_*` callables — so it can call
  // every one of those — and ahead of the dispatch chains, so those can call
  // it. That is exactly the reach an escape should have and no more.
  if !escape_fields.is_empty() {
    for f in escape_prelude(g) {
      fs.push(f)
    }
    for f in escape_fields {
      fs.push(f)
    }
    // …and the `cm_<name>` forwarders last, so every call site that reaches a
    // callable reaches an escaped one the same way.
    for f in escape_wrappers(g) {
      fs.push(f)
    }
  }
  fs.push(handle_event_fn(g, decls))
  fs.push(call_method_fn(g, decls))
  if g.uses_control {
    fs.push(flush_fn(g.uses_send_at, g.uses_v2_effects))
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
      @abi.guest_iface + "#handle-request",
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
    if_(
      eq(get("k"), i32c(2)),
      [call("ctl_emit", [get("np"), get("nl"), get("ap"), get("al")])],
      [],
    ),
    // `request-opts` as the interpreter builds it: `RequestOpts::new()` names
    // no `on-ok`, no `on-error` and no `on-res`, and does not ask for a live
    // path. Three `none` discriminants with dead pointer/length slots, and a
    // false. The response arrives at the request's own name, in the `response`
    // bucket, which this card already dispatches.
    if_(
      eq(get("k"), i32c(4)),
      [
        call("ctl_request", [
          get("np"),
          get("nl"),
          get("ap"),
          get("al"),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
          i32c(0),
        ]),
      ],
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
    arms.push(
      if_(
        eq(get("k"), i32c(6)),
        [
          call("ctl_intent", [
            get("np"),
            get("nl"),
            get("ap"),
            get("al"),
            call("tc_effect_route", [get("i")]),
          ]),
        ],
        [],
      ),
    )
    arms.push(
      if_(
        eq(get("k"), i32c(7)),
        [
          call("ctl_forward", [
            get("ap"),
            get("al"),
            call("tc_effect_route", [get("i")]),
          ]),
        ],
        [],
      ),
    )
    arms.push(
      if_(eq(get("k"), i32c(8)), [call("ctl_reply", [get("ap"), get("al")])], []),
    )
    arms.push(
      if_(eq(get("k"), i32c(9)), [call("ctl_fail", [get("ap"), get("al")])], []),
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
