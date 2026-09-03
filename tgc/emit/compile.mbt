// The driver: card in, module out.
//
// Two answers, and the difference is the whole of what a host does next.
// REJECTED is the card turned away whole because it does not check — a name
// that resolves to nothing does not typecheck against any backend, and emitting
// a module with a hole where the handler should be would turn a mistake into
// behaviour. REFUSED is per-declaration: this backend did not lower THAT, the
// rest of the card still runs, and the manifest leaves the name out.

///|
pub fn check_card(source : String, name~ : String) -> Checked raise GenError {
  let file = split(source, name)
  let (comps, issues) = prepare(file, name)
  {
    component: if comps.length() > 0 {
      comps[0].name
    } else {
      ""
    },
    components: comps.map(c => c.name),
    issues,
  }
}

///|
pub fn compile(source : String, name~ : String) -> Compiled raise GenError {
  let file = split(source, name)
  let (comps, issues) = prepare(file, name)
  guard issues.length() == 0 else {
    raise BadScript(issues.map(i => "line \{i.line} [\{i.code}]: \{i.message}"))
  }
  guard comps.length() > 0 else { raise BadCard("no component is declared") }
  build(comps, name, macros=file.macros)
}

///|
pub fn compile_decls(
  states : Array[@statedef.StateDef],
  scripts : Map[String, Array[@tscript.Decl]],
  name~ : String,
  root~ : String,
) -> Compiled raise GenError {
  let comps = []
  for def in states {
    let decls = scripts.get(def.component).unwrap_or([])
    comps.push(comp_of(def, decls))
  }
  // The root goes first: every mount site takes the head of `components`.
  comps.sort_by_key(c => if c.name == root { 0 } else { 1 })
  guard comps.length() > 0 else { raise BadCard("no component is declared") }
  check_all(comps)
  build(comps, name)
}

///|
fn split(source : String, name : String) -> @viewfile.ViewFile raise GenError {
  @viewfile.split_file(source, name~) catch {
    e => raise BadCard(e.message())
  }
}

///|
fn comp_of(
  def : @statedef.StateDef,
  decls : Array[@tscript.Decl],
  views? : Array[@viewfile.RawView] = [],
  common_style? : String = "",
  inits? : Array[@statedef.InitState] = [],
) -> Comp {
  {
    def,
    name: def.component,
    id: mangle(def.component),
    fields: def.fields,
    decls,
    views,
    common_style,
    inits,
    refusals: [],
  }
}

///|
/// Parse every script block and check it against its state.
fn prepare(
  file : @viewfile.ViewFile,
  name : String,
) -> (Array[Comp], Array[Issue]) raise GenError {
  let comps = []
  let issues = []
  for def in file.state {
    let block = file.script_for(def.component)
    let decls = match block {
      None => []
      Some(b) =>
        @tscript.parse_script(b.text) catch {
          e =>
            raise BadScript(["\{def.component}: line \{b.line}: \{e.message()}"])
        }
    }
    let set = file.components.filter(v => v.name == def.component)
    let views = if set.length() > 0 { set[0].views } else { [] }
    let style = if set.length() > 0 { set[0].common_style } else { "" }
    let inits = []
    for entry in file.init {
      let (comp, state) = entry
      if comp == def.component {
        inits.push(state)
      }
    }
    comps.push(comp_of(def, decls, views~, common_style=style, inits~))
  }
  // The root is the first declared component unless a template says otherwise.
  comps.sort_by_key(c => if c.name == file.root { 0 } else { 1 })
  let surface = surface_of(comps)
  for c in comps {
    for f in @check.check(c.decls, c.def, surface~) {
      if f.severity is SError {
        issues.push({
          comp: c.name,
          code: f.code,
          message: f.message,
          line: 0,
          span: f.span,
        })
      }
    }
  }
  ignore(name)
  (comps, issues)
}

///|
fn check_all(comps : Array[Comp]) -> Unit raise GenError {
  let issues = []
  let surface = surface_of(comps)
  for c in comps {
    for f in @check.check(c.decls, c.def, surface~) {
      if f.severity is SError {
        issues.push("\{c.name} [\{f.code}]: \{f.message}")
      }
    }
  }
  guard issues.length() == 0 else { raise BadScript(issues) }
}

///|
/// What the checker is allowed to assume about the world outside one
/// declaration.
///
/// `comps` is the load-bearing field and the reason this exists at all: `new
/// TodoItem` names a SIBLING declared in the same spec block, and a checker
/// handed one component's `StateDef` alone answers `NO_TYPE` for it. Every
/// starter card that declares two components said so.
///
/// `open_senders` because a card is mounted by a host that dispatches a name
/// into it and driven by scenes that send it one, and neither is in the file.
///
/// `knows_views` stays FALSE, and that is a gap rather than a decision: the
/// old backend builds this through `viewgen.check_component_views`, which
/// checks the templates as well and answers a surface that knows what the
/// views reach. Until this does the same, a name only a view mentions is
/// unchecked here.
fn surface_of(comps : Array[Comp]) -> @check.Surface {
  {
    inputs: Map([]),
    knows_views: false,
    open_senders: true,
    comps: comps.map(c => c.name),
  }
}

///|
fn build(
  comps : Array[Comp],
  name : String,
  macros? : Array[@viewfile.MacroDef] = [],
) -> Compiled raise GenError {
  let src = Src::new()
  src.line("// Generated by `tgc/emit` from a card. Do not edit.")
  src.line("//")
  src.line(
    "// The canonical preamble is prepended by the compiler, so the types",
  )
  src.line("// below are the frozen ones and nothing here spells them.")
  src.blank()
  emit_imports(src, comps)
  for c in comps {
    emit_state(src, c)
    emit_decls(src, c)
  }
  emit_shell(src, comps, name)
  let wax = src.text()
  let refusals = []
  for c in comps {
    for r in c.refusals {
      refusals.push(r)
    }
  }
  let wasm = compile_wax(wax)
  {
    component: comps[0].name,
    components: comps.map(c => c.name),
    wasm,
    wax,
    refusals,
    fields: comps[0].fields.map(f => f.name),
    manifest: manifest_json(comps, name, refusals, macros),
  }
}

///|
/// What the generated module imports.
///
/// Everything, unconditionally, and that is a gap rather than a decision: the
/// import section is meant to be a TRUE statement about what a card does, and
/// this one over-claims. Narrowing it means walking the lowered bodies for the
/// names they actually reached, which is the same analysis
/// `tutucard/wasm`'s `lower_scalar` / `lower_values` split does. Until then a
/// host reading this section learns what a card COULD do rather than what it
/// does, and `tgc/SPEC.md` says so.
fn emit_imports(src : Src, comps : Array[Comp]) -> Unit {
  src.open("import \{wax_str(@abi.import_namespace)} {")
  for entry in runtime_imports {
    let (fname, exported, sig) = entry
    src.line("#[import = \{wax_str(exported)}]")
    src.line("fn \{fname}\{sig};")
  }
  src.close("}")
  src.blank()
  ignore(comps)
}

///|
/// The vocabulary a generated module reaches for.
///
/// `get_field` and `call_op` are bound to the FROZEN function types, so the
/// link checks against the group rather than against a singleton that looks
/// like it. The rest take and answer `&?tg_val`, where null is "no answer" and
/// abandons the transition.
let runtime_imports : Array[(String, String, String)] = [
  ("str_eq", "str_eq", "(a: &tg_bytes, b: &tg_bytes) -> i32"),
  (
    "get_field", "get_field", ": tg_get(inst: &tg_inst, name: &tg_bytes) -> &?tg_val",
  ),
  (
    "call_op", "call_op", ": tg_call(inst: &tg_inst, op: i32, name: &tg_bytes, args: &tg_vals, v: &?tg_val) -> &?tg_val",
  ),
  ("tg_null", "mk_null", "() -> &tg_val"),
  ("tg_bool", "mk_bool", "(b: i32) -> &tg_val"),
  ("tg_num", "mk_num", "(n: f64) -> &tg_val"),
  ("tg_str", "mk_str", "(b: &tg_bytes) -> &tg_val"),
  ("tg_list", "mk_list", "(items: &tg_vals) -> &tg_val"),
  ("tg_map", "mk_map", "(entries: &tg_entries) -> &tg_val"),
  ("tg_comp", "mk_comp", "(inst: &tg_inst) -> &tg_val"),
  ("tg_entry_of", "entry_of", "(key: &tg_bytes, value: &?tg_val) -> &tg_entry"),
  ("tg_no_args", "no_args", "() -> &tg_vals"),
  (
    "tg_arg", "arg", "(args: &?tg_val, key: &tg_bytes, zero: &?tg_val) -> &?tg_val",
  ),
  ("tg_arg_at", "arg_at", "(args: &tg_vals, i: i32) -> &?tg_val"),
  ("tg_truthy", "truthy", "(v: &?tg_val) -> i32"),
  ("display", "display", "(v: &?tg_val) -> &tg_bytes"),
  ("concat", "concat", "(a: &tg_bytes, b: &tg_bytes) -> &tg_bytes"),
  ("trunc", "trunc", "(v: &?tg_val) -> &?tg_val"),
  ("op_add", "op_add", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_sub", "op_sub", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_mul", "op_mul", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_div", "op_div", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_mod", "op_mod", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_neg", "op_neg", "(a: &?tg_val) -> &?tg_val"),
  ("op_lt", "op_lt", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_le", "op_le", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_gt", "op_gt", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_ge", "op_ge", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_is", "op_is", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("op_is_not", "op_is_not", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("b_empty", "b_empty", "(v: &?tg_val) -> &?tg_val"),
  ("b_truthy", "b_truthy", "(v: &?tg_val) -> &?tg_val"),
  ("b_falsy", "b_falsy", "(v: &?tg_val) -> &?tg_val"),
  ("b_null", "b_null", "(v: &?tg_val) -> &?tg_val"),
  ("b_not", "b_not", "(v: &?tg_val) -> &?tg_val"),
  ("b_len", "b_len", "(v: &?tg_val) -> &?tg_val"),
  ("b_has", "b_has", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("b_contains", "b_contains", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("b_min", "b_min", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  ("b_max", "b_max", "(a: &?tg_val, b: &?tg_val) -> &?tg_val"),
  (
    "b_clamp", "b_clamp", "(v: &?tg_val, lo: &?tg_val, hi: &?tg_val) -> &?tg_val",
  ),
  ("b_int", "b_int", "(v: &?tg_val) -> &?tg_val"),
  ("b_num", "b_num", "(v: &?tg_val) -> &?tg_val"),
  ("b_str", "b_str", "(v: &?tg_val) -> &?tg_val"),
  ("b_lower", "b_lower", "(v: &?tg_val) -> &?tg_val"),
  ("b_upper", "b_upper", "(v: &?tg_val) -> &?tg_val"),
  ("b_trim", "b_trim", "(v: &?tg_val) -> &?tg_val"),
  ("item", "item", "(coll: &?tg_val, key: &?tg_val) -> &?tg_val"),
  ("member", "member", "(v: &?tg_val, name: &tg_bytes) -> &?tg_val"),
  (
    "with_item", "with_item", "(coll: &?tg_val, key: &?tg_val, x: &?tg_val) -> &?tg_val",
  ),
  (
    "with_member", "with_member", "(v: &?tg_val, name: &tg_bytes, x: &?tg_val) -> &?tg_val",
  ),
  ("coll_push", "coll_push", "(v: &?tg_val, x: &?tg_val) -> &?tg_val"),
  (
    "coll_insert_at", "coll_insert_at", "(v: &?tg_val, at: &?tg_val, x: &?tg_val) -> &?tg_val",
  ),
  (
    "coll_set_at", "coll_set_at", "(v: &?tg_val, at: &?tg_val, x: &?tg_val) -> &?tg_val",
  ),
  (
    "coll_delete_at", "coll_delete_at", "(v: &?tg_val, at: &?tg_val) -> &?tg_val",
  ),
  ("coll_add", "coll_add", "(v: &?tg_val, x: &?tg_val) -> &?tg_val"),
  ("coll_remove", "coll_remove", "(v: &?tg_val, x: &?tg_val) -> &?tg_val"),
  ("coll_toggle", "coll_toggle", "(v: &?tg_val, x: &?tg_val) -> &?tg_val"),
  // The effects. Buffered by the HOST, which brackets the call and therefore
  // knows when it ended: an effect performed before a statement that abandons
  // is discarded with the transition.
  ("eff_send", "eff_send", "(name: &tg_bytes, args: &tg_vals)"),
  ("eff_reply", "eff_reply", "(name: &tg_bytes, args: &tg_vals)"),
  ("eff_answer", "eff_answer", "(v: &?tg_val)"),
  ("eff_ask", "eff_ask", "(name: &tg_bytes, args: &tg_vals, route: i32)"),
  ("eff_notify", "eff_notify", "(name: &tg_bytes, args: &tg_vals, route: i32)"),
  ("eff_forward", "eff_forward", "(args: &tg_vals, route: i32)"),
  ("eff_fail", "eff_fail", "(v: &?tg_val)"),
  ("eff_drop", "eff_drop", "()"),
  // What a DECLINED rule says. A transition that stopped and said nothing is
  // indistinguishable from a click that missed.
  ("eff_log", "eff_log", "(msg: &tg_bytes)"),
]

///|
fn compile_wax(wax : String) -> Bytes raise GenError {
  let preamble = @abi.preamble_wax()
  let source = preamble + "\n" + wax
  // The stage NAME rather than the rendered error. `Show for CompileError`
  // renders the span, which walks the source — and a source carrying the
  // preamble's box-drawing comments walks it through a UTF-16 pair decoder
  // that a `#|`-embedded string trips. Naming the stage says the same useful
  // thing without reading the text back.
  let result = @wax.compile_string(source, fname="card.wax") catch {
    _ => raise BadModule(["the wax compiler stopped"])
  }
  match result {
    Ok(bytes) => bytes
    Err(ds) => {
      let lines = []
      let offset = line_count(preamble) + 1
      for d in ds {
        lines.push(
          "line \{d.loc.start.lnum - offset}: \{@message.to_plain_string(d.message)}",
        )
      }
      raise BadModule(lines)
    }
  }
}

///|
fn line_count(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c == '\n' {
      n = n + 1
    }
  }
  n
}

///|
/// The manifest a HOST reads, in `dyncomp/host`'s shape.
///
/// Two manifests, and the difference is worth naming rather than hiding. The
/// MODULE carries its own (`tgc.describe`, an ordinary value) and that one is
/// authoritative — it is what lets a `tgc` module be one file with no sidecar,
/// which is half the point of the format. This one is the same facts in the
/// shape `dyncomp/host` already parses, so a page can mount a `tgc` card
/// through the host it already has instead of waiting for a new one.
///
/// It carries the VIEWS, which `tgc.describe` does not yet. That is the gap
/// this exists across: a module that named its own views would need no
/// manifest at all.
fn manifest_json(
  comps : Array[Comp],
  name : String,
  refusals : Array[Refusal],
  macros : Array[@viewfile.MacroDef],
) -> Json {
  let lowered = (c : Comp, kind : @tscript.DeclKind) => {
    let out = []
    for d in c.decls {
      if d.kind == kind && !refusals.iter().any(r => r.name == d.name) {
        out.push(Json::string(d.name))
      }
    }
    Json::array(out)
  }
  let component_defs : Array[Json] = []
  for c in comps {
    let fields : Array[Json] = []
    for f in c.fields {
      fields.push({
        "name": Json::string(f.name),
        "ty": f.ty.to_json(),
        "doc": Json::string(f.doc.unwrap_or("")),
        "required": Json::boolean(f.attr_required()),
      })
    }
    let properties : Array[Json] = []
    for prop in c.def.properties {
      properties.push({
        "name": Json::string(prop.name),
        "ty": prop.ty.to_json(),
        "public": Json::boolean(prop.public_),
        "writable": Json::boolean(prop.writable),
        "doc": Json::string(prop.doc.unwrap_or("")),
      })
    }
    let views : Array[Json] = []
    for v in c.views {
      views.push({
        "name": Json::string(v.name),
        "html": Json::string(v.source),
      })
    }
    component_defs.push({
      "name": Json::string(c.name),
      "doc": Json::string(c.def.doc.unwrap_or("")),
      "keywords": Json::array([]),
      "category": Json::string(""),
      "messageDocs": Json::array([]),
      "views": Json::array(views),
      "fields": Json::array(fields),
      "properties": Json::array(properties),
      "types": Json::array([]),
      "domains": @tutuca.domains_to_json(c.def.field_domains()),
      "receives": lowered(c, DReceive),
      "intents": lowered(c, DAnswer),
      "expressMessages": Json::array(
        c.def.express_message.map(m => Json::string(m.name)),
      ),
      "expressIntents": Json::array(
        c.def.express_intent.map(m => Json::string(m.name)),
      ),
      "implements": Json::array(c.def.implements.map(Json::string)),
      "protocols": Json::array([]),
      "propertyBindings": Json::array([]),
      "viewBindings": Json::array([]),
      "provideBindings": Json::array([]),
      "lookupBindings": Json::array([]),
      "methods": lowered(c, DCompute),
      "whens": lowered(c, DPred),
      "enriches": lowered(c, DEnrich),
      "bindWiths": lowered(c, DBindWith),
      "serves": Json::array([]),
      "provide": Json::array([]),
      "lookup": Json::array([]),
      "inits": Json::array(
        c.inits.map(i => {
          let args : Map[String, Json] = Map([])
          for k, v in i.args {
            args[k] = v.to_json()
          }
          {
            "name": Json::string(i.name),
            // The host parses this back out of a STRING, which is what
            // `parse_inits` reads: `argsJson`, not `args`.
            "argsJson": Json::string(Json::object(args).stringify()),
            "doc": Json::string(i.doc),
            "view": Json::string(i.view),
            "tags": Json::array(i.tags.map(Json::string)),
            "default": Json::boolean(i.default_),
            "driveJson": Json::string(i.drive.stringify()),
            "intentsJson": Json::string(i.intents.stringify()),
          }
        }),
      ),
      "style": Json::string(c.common_style),
    })
  }
  {
    "manifestVersion": Json::number(3),
    "apiVersion": Json::number(10),
    "moduleName": Json::string(name),
    "doc": Json::string(""),
    "version": Json::string("0.1.0"),
    "homepage": Json::string(""),
    "authors": Json::array([]),
    "stringEncoding": Json::string("utf8"),
    "config": Json::array([]),
    // A macro is markup the HOST expands when it parses a view, so a manifest
    // that dropped them is a card whose views reach for a name nothing
    // declares — and the symptom is an element that is simply not there.
    "macros": Json::array(
      macros.map(m => {
        let defaults : Map[String, Json] = Map([])
        for k, v in m.defaults {
          defaults[k] = Json::string(v)
        }
        {
          "name": Json::string(m.name),
          "defaults": Json::object(defaults),
          "html": Json::string(m.source),
        }
      }),
    ),
    "components": Json::array(component_defs),
    // Not part of the host's shape; carried so a playground can show them
    // beside what did compile. A host ignores what it does not read.
    "refusals": Json::array(
      refusals.map(r => {
        "component": Json::string(r.comp),
        "kind": Json::string(r.kind),
        "name": Json::string(r.name),
        "reason": Json::string(r.reason),
      }),
    ),
  }
}

///|
/// The runtime module — `tut`, the shared function vocabulary.
///
/// Not through `compile_wax`, and the difference is worth naming rather than
/// leaving for somebody to trip over. `compile_wax` maps a diagnostic's line
/// back to the CARD's line, which means holding the preamble to count it and
/// rendering every message. The runtime is not a card: it is a fixed input that
/// either compiles or is a bug in this package, so there is no card line to map
/// to and nothing a card author could act on.
pub fn compile_runtime() -> Bytes raise GenError {
  let source = @abi.preamble_wax() + "\n" + @rt.source()
  let result = @wax.compile_string(source, fname="tutuca-rt.wax") catch {
    _ => raise BadModule(["the wax compiler stopped on the runtime"])
  }
  match result {
    Ok(bytes) => bytes
    Err(_) =>
      raise BadModule([
        "the embedded runtime does not compile — `rt_src_gen.mbt` is stale " +
        "against `rt.wax`, or `rt.wax` itself is broken. Rerun " +
        "`node tgc/rt/embed.mjs`, then compile `rt.wax` with `tgc build` for " +
        "the diagnostics this deliberately does not carry",
      ])
  }
}
