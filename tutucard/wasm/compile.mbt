// Card in, `tutuca:component@0.7.0` core module out.
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
pub fn compile(source : String, name~ : String) -> Compiled raise GenError {
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
  guard file.state.get(0) is Some(def) else { raise NoState }
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
  for d in decls {
    if d.kind is (DCompute | DPred | DInvariant) {
      g.callables[d.name] = d
    }
  }
  let module_ = emit_module(g, decls)
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
    fields: def.fields.map(f => f.name),
    manifest: manifest_json(g, decls, views, file),
    descriptor: Json::object({
      "world": Json::string("tutuca:component@0.7.0"),
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
) -> @ast.LocModule raise GenError {
  // Bodies first: every one of them interns constants, and neither the data
  // segment nor the `#[start]` that builds them can be laid down until the pool
  // has stopped growing.
  let card = card_fields(g, decls)
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
  }
  fs.push(memory_field(2))
  fs.push(data_field("pool", @abi.pool_base, g.pool.to_bytes()))
  fs.push(global_i32("heap", g.pool.heap_base()))
  // The allocator has to precede the runtime source, which calls it to put a
  // string's bytes where the host can read them.
  for f in alloc {
    fs.push(f)
  }
  let runtime = @waxsrc.runtime_wax_fields(g.uses_values) catch {
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
fn card_fields(g : Gen, decls : Array[@tscript.Decl]) -> Array[@abi.Field] {
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
      body=[mem("store32", [i32c(@abi.ret_restore), i32c(0)]), i32c(@abi.ret_restore)],
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
  fs.push(handle_event_fn(g, decls))
  fs.push(call_method_fn(g, decls))
  if g.uses_control {
    fs.push(flush_fn())
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
/// half knows that `ctl_send`, `ctl_emit` and `ctl_stop` exist.
fn flush_fn() -> @abi.Field {
  func("tc_flush", body=[
    let_("i", i32c(0)),
    while_(
      lts(get("i"), call("tc_effect_count", [])),
      Some(setop("i", Add, i32c(1))),
      [
        let_("k", call("tc_effect_kind", [get("i")])),
        if_(eq(get("k"), i32c(3)), [call("ctl_stop", [])], [
          let_("np", call("tc_effect_name_ptr", [get("i")])),
          let_("nl", call("tc_effect_name_len", [get("i")])),
          let_("ap", call("tc_effect_args_ptr", [get("i")])),
          let_("al", call("tc_effect_args_len", [get("i")])),
          if_(
            eq(get("k"), i32c(2)),
            [call("ctl_emit", [get("np"), get("nl"), get("ap"), get("al")])],
            [call("ctl_send", [get("np"), get("nl"), get("ap"), get("al")])],
          ),
        ]),
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
