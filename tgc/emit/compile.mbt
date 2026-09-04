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
  // ERRORS only. A warning is a thing worth telling an author about a card that
  // RUNS, and refusing to build one would make the two indistinguishable from
  // the outside — which is the whole reason the checker separates them.
  let fatal = issues.filter(i => i.severity == "error")
  guard fatal.length() == 0 else {
    raise BadScript(fatal.map(i => "line \{i.line} [\{i.code}]: \{i.message}"))
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
  let siblings = states.map(d => d.component)
  for def in states {
    let decls = scripts.get(def.component).unwrap_or([])
    comps.push(comp_of(def, decls, siblings~))
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
  authored? : Array[@tscript.Decl] = [],
  views? : Array[@viewfile.RawView] = [],
  common_style? : String = "",
  inits? : Array[@statedef.InitState] = [],
  siblings? : Array[String] = [],
) -> Comp {
  {
    def,
    name: def.component,
    id: mangle(def.component),
    fields: def.fields,
    decls,
    authored: if authored.is_empty() {
      decls
    } else {
      authored
    },
    views,
    common_style,
    inits,
    siblings,
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
  let siblings = file.state.map(d => d.component)
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
    // The SPEC block's rules, as declarations, ahead of the block's own.
    //
    // The same synthesis `gen` runs, from the same function, because the two
    // backends have to keep the same rules: a card that enforced a different
    // `invariant` from the generated component of the same file would be two
    // answers to one question.
    //
    // A rule whose body this backend cannot read is dropped rather than
    // raised: `check_card` has already reported it with a position in the
    // file, and a card that renders is what this function exists to produce.
    let (spec_rules, _) = @check.rule_decls(def, decls)
    let authored = decls
    let decls = spec_rules + decls
    // Through `component_name`, and with the FILE's root as the fallback.
    //
    // A view set is named by the prefix on its template ids —
    // `<template id="Todo:main">` — and a card with a BARE `<template>` names
    // none, so the set takes the fallback. Passing the caller's `name` made
    // that fallback depend on what the caller happened to call the card:
    // `tgc card nested-state.html` said "nested-state" where the component is
    // `Nested`, and the card mounted with no view at all.
    //
    // A file with one component and unnamed views has an empty `root` too, so
    // the last resort is the component being matched — which is right, because
    // an unnamed view set in a one-component file is that component's.
    let fallback = if file.root == "" { def.component } else { file.root }
    let set = file.components.filter(v => {
      v.component_name(fallback) == def.component
    })
    let views = if set.length() > 0 { set[0].views } else { [] }
    let style = if set.length() > 0 { set[0].common_style } else { "" }
    let inits = []
    for entry in file.init {
      let (comp, state) = entry
      if comp == def.component {
        inits.push(state)
      }
    }
    comps.push(
      comp_of(
        def,
        decls,
        authored~,
        views~,
        common_style=style,
        inits~,
        siblings~,
      ),
    )
  }
  // The root is the first declared component unless a template says otherwise.
  comps.sort_by_key(c => if c.name == file.root { 0 } else { 1 })
  // THE VIEWS, before the script — a view is most of a card, and a template
  // that names a field the spec does not declare used to compile clean and draw
  // blank. `check_card` is the loop somebody runs before paying for a compile,
  // so a fault it cannot see is a fault they converge past.
  let prog = @viewgen.ProgramIndex::of(file, name)
  let names = comps.map(c => c.name)
  check_protocols(comps, prog, issues)
  for c in comps {
    // The script block's own names: a card's handlers are all in it, so what
    // this cannot see is nothing.
    let claimed = c.authored.map(d => d.name)
    for f in @check.check_stale_mutators(c.def, claimed) {
      issues.push({
        comp: c.name,
        code: f.code,
        message: f.message,
        severity: if f.severity is SError {
          "error"
        } else {
          "warning"
        },
        line: 0,
        span: f.span,
      })
    }
  }
  for c in comps {
    let surface = view_surface(c, names, prog, file.macros, issues)
    for f in @check.check(c.authored, c.def, surface~) {
      // WARNINGS travel too, and only here: `compile` below gates on errors
      // alone, so a warning is something to show an author rather than a build
      // to stop. `check_card` is what an editor calls between keystrokes, and
      // the findings it drops are findings nobody ever sees.
      issues.push({
        comp: c.name,
        code: f.code,
        message: f.message,
        severity: if f.severity is SError {
          "error"
        } else {
          "warning"
        },
        line: 0,
        span: f.span,
      })
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
/// `knows_views` stays FALSE: this is the surface for a caller that has not
/// checked the templates, and claiming otherwise would let three rules fire
/// against a view set nobody read. `view_surface` below is the one that has.
fn surface_of(comps : Array[Comp]) -> @check.Surface {
  {
    inputs: Map([]),
    knows_views: false,
    open_senders: true,
    comps: comps.map(c => c.name),
  }
}

///|
/// The validator's code, as the string an editor puts in a gutter.
///
/// Spelled out rather than derived: these are the names a card author reads and
/// searches for, and a `Show` that happened to answer the constructor is a
/// coupling between a diagnostic code and a MoonBit identifier.
fn protocol_code(c : @tutuca.ProtocolIssueCode) -> String {
  match c {
    ProtocolUnresolved => "PROTOCOL_UNRESOLVED"
    ProtocolDefinitionConflict => "PROTOCOL_DEFINITION_CONFLICT"
    ProtocolNotImplemented => "PROTOCOL_NOT_IMPLEMENTED"
    ProtocolMemberMissing => "PROTOCOL_MEMBER_MISSING"
    ProtocolMemberType => "PROTOCOL_MEMBER_TYPE"
    ProtocolTargetMismatch => "PROTOCOL_TARGET_MISMATCH"
    ProtocolPropertyMissing => "PROTOCOL_PROPERTY_MISSING"
    ProtocolPropertyType => "PROTOCOL_PROPERTY_TYPE"
    ProtocolViewMissing => "PROTOCOL_VIEW_MISSING"
    ProtocolProvideMissing => "PROTOCOL_PROVIDE_MISSING"
    ProtocolLookupMissing => "PROTOCOL_LOOKUP_MISSING"
    ProtocolResultType => "PROTOCOL_RESULT_TYPE"
    ProtocolExpressionUndeclared => "PROTOCOL_EXPRESSION_UNDECLARED"
  }
}

///|
/// What a component PROMISES by implementing a protocol, held to what it does.
///
/// Two questions, and a card could fail either while compiling clean:
///
/// The SCHEMA's — does the spec block declare the protocol's operations at all?
/// `statedef.validate_protocols` answers it, and `gen` has run it since
/// protocols landed. This backend never did.
///
/// The SCRIPT's — is there a handler that ANSWERS each declared operation,
/// under the name the module will be dispatched at? A card can declare
/// `handle Hole { message { Holder::hold(Any) } }` and write `receive hold`,
/// and then it answers `hold` while its manifest claims a protocol whose
/// operation is `x/Holder@1::hold`. `SchemaInfo::conforms` refuses such a
/// component when a host fills a slot with it, so the card is already broken —
/// it just says nothing until something tries to use it. That is the shape this
/// exists for, and it is what a real card carried unnoticed for its whole life.
///
/// An ERROR, not a warning: a component the host will refuse is not a component
/// that runs. The express side is the schema's question alone — nothing in a
/// script declares an outbound name — so it is left to the validator above.
fn check_protocols(
  comps : Array[Comp],
  prog : @viewgen.ProgramIndex,
  issues : Array[Issue],
) -> Unit {
  for d in prog.protocol_validation().diagnostics {
    // A protocol this batch cannot see is checked at runtime and says so; the
    // validator marks it non-fatal and this keeps that.
    issues.push({
      comp: d.component,
      code: protocol_code(d.code),
      message: d.message,
      severity: if d.error {
        "error"
      } else {
        "warning"
      },
      line: 0,
      span: d.span,
    })
  }
  for c in comps {
    for p in c.def.protocols {
      if !c.def.implements.contains(p.id) {
        continue
      }
      let answered = c.decls
        .filter(d => d.kind is (DReceive | DAnswer))
        .map(d => wire_name(c, d))
      for pair in [(p.handle_message, "message"), (p.handle_intent, "intent")] {
        let (members, what) = pair
        for m in members {
          let wire = p.id + "::" + m.name
          if !answered.contains(wire) {
            issues.push({
              comp: c.name,
              code: "PROTOCOL_MEMBER_UNANSWERED",
              message: "`\{c.name}` implements `\{p.id}` and nothing answers its \{what} `\{m.name}` — the handler has to be declared under the protocol's own name (`\{if what == "message" { "receive" } else { "answer" }} \{p.local_name}::\{m.name}`), because that is the name a host dispatches",
              severity: "error",
              line: 0,
              span: p.span,
            })
          }
        }
      }
    }
  }
}

///|
/// One component's surface, built by CHECKING its own templates — which is also
/// how those templates get checked at all.
///
/// `check_component_views` does both jobs at once, and that is the reason to
/// call it rather than to check views separately: the surface it answers KNOWS
/// what the views reach, which is what turns on `NO_VIEW_HANDLER`, the handler
/// arity cross-check and the call-site parameter types. A surface built without
/// reading the views cannot have those rules, because every name would look
/// unreached.
///
/// PER COMPONENT, and that is not an optimization: a card declares several, and
/// `NO_VIEW_HANDLER` asks "does THIS block answer what ITS OWN views send". One
/// surface merged across the file makes every component answer for every
/// other's views, which reports six faults in a card that has none.
///
/// A fatal finding RAISES there and is collected here instead: a card that does
/// not check is a card to REPORT on, not a build to abandon — `check_card` is
/// an editor's call, and an editor that answers nothing when one template is
/// wrong is worse than one that lists what is wrong with it.
///
/// `open_senders` because a card is mounted by a host that dispatches a name
/// into it and driven by scenes that send it one, and neither is in the file.
fn view_surface(
  c : Comp,
  names : Array[String],
  prog : @viewgen.ProgramIndex,
  macros : Array[@viewfile.MacroDef],
  issues : Array[Issue],
) -> @check.Surface {
  @viewgen.check_component_views(
    c.views,
    c.def,
    prog,
    macros~,
    comps=names,
    open_senders=true,
  ) catch {
    e => {
      issues.push({
        comp: c.name,
        code: e.code(),
        message: e.message(),
        severity: "error",
        line: 0,
        span: { start: 0, end_: 0, },
      })
      // Its views did not read, so nothing here knows what they reach — and a
      // rule that fires on "no view mentions this" would report the failure
      // above a second time, in worse words.
      { ..surface_of([c]), comps: names, }
    }
  }
}

///|
fn build(
  comps : Array[Comp],
  name : String,
  macros? : Array[@viewfile.MacroDef] = [],
) -> Compiled raise GenError {
  // The BODY first, then the imports it turned out to need. A module's import
  // section is meant to be a true statement about what it does, and one written
  // before the body is a statement about what it COULD do.
  let body = Src::new()
  for c in comps {
    emit_state(body, c)
    emit_decls(body, c)
  }
  // The manifest is built ONCE, here, and then written into the module. The
  // JSON a caller gets back is `to_json()` of the same value — a projection
  // rather than a second description that could disagree with the first.
  let refusals_so_far = []
  for c in comps {
    for r in c.refusals {
      refusals_so_far.push(r)
    }
  }
  let manifest = manifest_value(comps, name, refusals_so_far, macros)
  emit_shell(body, comps, manifest)
  let text = body.text()
  let src = Src::new()
  src.line("// Generated by `tgc/emit` from a card. Do not edit.")
  src.line("//")
  src.line(
    "// The canonical preamble is prepended by the compiler, so the types",
  )
  src.line("// below are the frozen ones and nothing here spells them.")
  src.blank()
  emit_imports(src, text)
  src.buf.write_string(text)
  let wax = src.text()
  let refusals = refusals_so_far
  let wasm = compile_wax(wax)
  {
    component: comps[0].name,
    components: comps.map(c => c.name),
    wasm,
    wax,
    refusals,
    fields: comps[0].fields.map(f => f.name),
    manifest: manifest.to_json(),
  }
}

///|
/// What the generated module imports.
///
/// Everything, unconditionally, and that is a gap rather than a decision: the
/// import section is meant to be a TRUE statement about what a card does, and
/// this one over-claims. Narrowing it means walking the lowered bodies for the
/// names they actually reached, which is the same analysis
/// a `lower_scalar` / `lower_values` split would. Until then a
/// host reading this section learns what a card COULD do rather than what it
/// does, and `tgc/SPEC.md` says so.
fn emit_imports(src : Src, body : String) -> Unit {
  src.open("import \{wax_str(@abi.import_namespace)} {")
  for entry in runtime_imports {
    let (fname, exported, sig) = entry
    if calls(body, fname) {
      src.line("#[import = \{wax_str(exported)}]")
      src.line("fn \{fname}\{sig};")
    }
  }
  src.close("}")
  src.blank()
}

///|
/// Whether the generated body calls a runtime function.
///
/// By SCANNING the text this generator just wrote, which is sound because it
/// wrote it: the only way a name reaches the body is an emitter putting it
/// there, and every emitter writes a call. The alternative — threading a set of
/// used names through every emission site — buys the same answer and costs a
/// parameter on functions that are otherwise about the language.
///
/// `name(` rather than `name`, so `member` does not match `with_member`, and a
/// preceding identifier character rules out the reverse.
fn calls(body : String, name : String) -> Bool {
  let needle = name + "("
  let chars = body.to_array()
  let n = needle.to_array()
  let mut i = 0
  while i + n.length() <= chars.length() {
    let mut hit = true
    for k in 0..<n.length() {
      if chars[i + k] != n[k] {
        hit = false
        break
      }
    }
    // A match preceded by an identifier character is the tail of a longer name.
    if hit && (i == 0 || !is_ident_char(chars[i - 1])) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
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
  // Which arm a value is, for the one place a compiled body has to ask: `cur`
  // is materialized at its first READ, and "has it been already" is that
  // question.
  ("kind_of", "kind_of", "(v: &tg_val) -> i32"),
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
  (
    "eff_send_at", "eff_send_at", "(path: &?tg_val, name: &tg_bytes, args: &tg_vals)",
  ),
  ("mk_step_field", "mk_step_field", "(name: &tg_bytes) -> &?tg_val"),
  (
    "mk_step_key", "mk_step_key", "(field: &tg_bytes, key: &?tg_val) -> &?tg_val",
  ),
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
/// The manifest, as an ordinary VALUE.
///
/// One manifest, and the module carries it. There used to be two — the module's
/// own `tgc.describe` and a second in `tgc/host`'s shape emitted beside it —
/// because `describe` did not name the views and a host needs them. Two
/// descriptions of one component is two things that can disagree, and the one
/// on disk was the one that could arrive without the other.
///
/// So this builds `core.Value` and the emitter writes it into the module with
/// `value_expr`. The JSON a host parses is `to_json()` of the same value, read
/// back out of `tgc.describe` at load — a projection rather than a second copy.
///
/// The KEYS are `tgc/host`'s, because that is the host that reads them and
/// a shape is worth more than a preference.
fn manifest_value(
  comps : Array[Comp],
  name : String,
  refusals : Array[Refusal],
  macros : Array[@viewfile.MacroDef],
) -> @tutuca.Value {
  let out : Map[String, @tutuca.Value] = Map([])
  out["manifestVersion"] = Num(3)
  out["apiVersion"] = Num(10)
  out["moduleName"] = Str(name)
  out["doc"] = Str("")
  out["version"] = Str("0.1.0")
  out["homepage"] = Str("")
  out["authors"] = List([])
  out["stringEncoding"] = Str("utf8")
  out["config"] = List([])
  // A macro is markup the HOST expands when it parses a view, so a manifest
  // that dropped them is a view reaching for a name nothing declares.
  out["macros"] = List(
    macros.map(m => {
      let defaults : Map[String, @tutuca.Value] = Map([])
      for k, v in m.defaults {
        defaults[k] = Str(v)
      }
      Map({
        "name": Str(m.name),
        "defaults": Map(defaults),
        "html": Str(m.source),
      })
    }),
  )
  out["components"] = List(comps.map(c => component_value(c, refusals)))
  // Not part of the host's shape; carried so a playground can show them beside
  // what did compile. A host ignores what it does not read.
  out["refusals"] = List(
    refusals.map(r => {
      Map({
        "component": Str(r.comp),
        "kind": Str(r.kind),
        "name": Str(r.name),
        "reason": Str(r.reason),
      })
    }),
  )
  Map(out)
}

///|
/// One protocol, in the shape `tgc/host`'s `parse_protocols` reads.
///
/// A member list is NAMES for the four message surfaces and typed defs for the
/// properties, because that is the asymmetry the host has: a message is matched
/// by name, and a property is READ, so a host needs its type to say what came
/// back.
fn protocol_value(p : @statedef.ProtocolDef) -> @tutuca.Value {
  let names = (ms : Array[@statedef.MsgDef]) => {
    @tutuca.Value::List(ms.map(m => Str(m.name)))
  }
  Map({
    "id": Str(p.id),
    "handleMessages": names(p.handle_message),
    "handleIntents": names(p.handle_intent),
    "expressMessages": names(p.express_message),
    "expressIntents": names(p.express_intent),
    "properties": List(p.properties.map(property_value)),
    "views": List(p.views.map(v => Str(v))),
    "provides": List(p.provides.map(d => Str(d.name))),
    "lookups": List(p.lookups.map(d => Str(d.name))),
  })
}

///|
/// One declared member, typed. The same shape a component's own `properties`
/// take, so a host reads a protocol's member and a component's the one way.
fn property_value(d : @statedef.PropertyDef) -> @tutuca.Value {
  Map({
    "name": Str(d.name),
    "ty": @tutuca.Value::from_json(d.ty.to_json()),
    "public": Bool(d.public_),
    "writable": Bool(d.writable),
    "doc": Str(d.doc.unwrap_or("")),
  })
}

///|
/// Which of this component's own members answers for a protocol's.
fn bindings_value(bs : Array[@statedef.ProtocolBinding]) -> @tutuca.Value {
  List(
    bs.map(b => {
      Map({
        "protocolId": Str(b.protocol_id),
        "member": Str(b.member_name),
        "source": Str(b.source),
      })
    }),
  )
}

///|
/// One component's half of it — and the whole of what an INSTANCE says about
/// itself, which is why `<C>_desc()` is this same value.
fn component_value(c : Comp, refusals : Array[Refusal]) -> @tutuca.Value {
  // The names the module ANSWERS TO, which for a message or an intent is the
  // schema's runtime name and not the declaration's own spelling — the same
  // resolution the dispatch does, because a manifest that advertised a name
  // the module does not answer would be worse than one that advertised none.
  let names_of = (kinds : Array[@tscript.DeclKind]) => {
    c.decls
    .filter(d => {
      kinds.contains(d.kind) && !refusals.iter().any(r => r.name == d.name)
    })
    .map(d => @tutuca.Value::Str(wire_name(c, d)))
  }
  let lowered = (kind : @tscript.DeclKind) => {
    @tutuca.Value::List(names_of([kind]))
  }
  let strs = (xs : Array[String]) => @tutuca.Value::List(xs.map(x => Str(x)))
  let out : Map[String, @tutuca.Value] = Map([])
  out["name"] = Str(c.name)
  out["doc"] = Str(c.def.doc.unwrap_or(""))
  out["keywords"] = List([])
  out["category"] = Str("")
  out["messageDocs"] = List([])
  out["views"] = List(
    c.views.map(v => Map({ "name": Str(v.name), "html": Str(v.source) })),
  )
  out["fields"] = List(
    c.fields.map(f => {
      Map({
        "name": Str(f.name),
        "ty": @tutuca.Value::from_json(f.ty.to_json()),
        "doc": Str(f.doc.unwrap_or("")),
        "required": Bool(f.attr_required()),
      })
    }),
  )
  out["properties"] = List(
    c.def.properties.map(p => {
      Map({
        "name": Str(p.name),
        "ty": @tutuca.Value::from_json(p.ty.to_json()),
        "public": Bool(p.public_),
        "writable": Bool(p.writable),
        "doc": Str(p.doc.unwrap_or("")),
      })
    }),
  )
  out["domains"] = @tutuca.Value::from_json(
    @tutuca.domains_to_json(c.def.field_domains()),
  )
  out["receives"] = lowered(DReceive)
  out["intents"] = lowered(DAnswer)
  out["expressMessages"] = strs(c.def.express_message.map(m => m.name))
  out["expressIntents"] = strs(c.def.express_intent.map(m => m.name))
  out["implements"] = strs(c.def.implements)
  // The PROTOCOLS this component implements, as definitions and not just as
  // ids. `implements` above says which ones; this says what each one requires,
  // which is what a host resolving a slot THROUGH a protocol reads. Both, or a
  // host that matched by id would then find nothing to match against.
  out["protocols"] = List(c.def.protocols.map(protocol_value))
  out["propertyBindings"] = bindings_value(c.def.property_bindings)
  out["viewBindings"] = bindings_value(c.def.view_bindings)
  out["provideBindings"] = bindings_value(c.def.provide_bindings)
  out["lookupBindings"] = bindings_value(c.def.lookup_bindings)
  // A `pred` is BOTH: read as `$name` it answers its own expression, and
  // reached through `@when` it answers that value's truthiness. One
  // declaration, two lists — a host that found it in only one of them would
  // draw `@show="$positive"` as an unread name.
  out["methods"] = List(names_of([DCompute, DPred, DInvariant]))
  out["whens"] = List(names_of([DPred, DInvariant]))
  out["enriches"] = lowered(DEnrich)
  out["bindWiths"] = lowered(DBindWith)
  out["serves"] = List([])
  // What a component publishes to its subtree and what it reads from above.
  // The host resolves both when it renders, so a manifest that dropped them is
  // a `*name` in a view answering nothing.
  out["provide"] = List(
    c.def.provide.map(d => Map({ "name": Str(d.name), "source": Str(d.source) })),
  )
  out["lookup"] = List(
    c.def.lookup.map(d => {
      Map({ "name": Str(d.name), "default": Str(d.default.unwrap_or("")) })
    }),
  )
  // The DEFAULT fixture is what a host mounts when told no other name, so a
  // card whose fixtures are dropped mounts at its declared zero and every
  // string field renders empty.
  out["inits"] = List(
    c.inits.map(i => {
      let args : Map[String, @tutuca.Value] = Map([])
      for k, v in i.args {
        args[k] = v
      }
      Map({
        "name": Str(i.name),
        // The host parses this back out of a STRING, which is what
        // `parse_inits` reads: `argsJson`, not `args`.
        "argsJson": Str(@tutuca.Value::Map(args).to_json().stringify()),
        "doc": Str(i.doc),
        "view": Str(i.view),
        "tags": strs(i.tags),
        "default": Bool(i.default_),
        "driveJson": Str(i.drive.stringify()),
        "intentsJson": Str(i.intents.stringify()),
      })
    }),
  )
  out["style"] = Str(c.common_style)
  Map(out)
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
