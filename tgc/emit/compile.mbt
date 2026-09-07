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
  let got = split(source, name)
  let (comps, checked) = prepare(got.file, name)
  let issues = got.issues + checked
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
  let got = split(source, name)
  let (comps, checked) = prepare(got.file, name)
  let issues = got.issues + checked
  let file = got.file
  // ERRORS only. A warning is a thing worth telling an author about a card that
  // RUNS, and refusing to build one would make the two indistinguishable from
  // the outside — which is the whole reason the checker separates them.
  let fatal = issues.filter(i => i.severity == "error")
  guard fatal.length() == 0 else {
    raise BadScript(fatal.map(i => "line \{i.line} [\{i.code}]: \{i.message}"))
  }
  guard comps.length() > 0 else { raise BadCard("no component is declared") }
  build(comps, name, macros=file.macros, source~)
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
/// The blocks, and whatever the lowering had to say to get to them.
///
/// The issues travel WITH the file rather than being raised here, because a
/// lowering that failed still answers the blocks it managed and an author
/// fixing one report should see the next. `compile` refuses on an error the
/// same way it refuses on a checker error, and `check_card` prints them.
fn split(source : String, name : String) -> Split raise GenError {
  let (file, reports) = @viewgen.read_card(source, name~) catch {
    e => raise BadCard(@viewgen.GenError::message(e))
  }
  let src = @report.Source::new("card.tutu", source)
  { file, issues: reports.map(r => issue_of(r, src)), }
}

///|
/// What reading a card's source produced, before anything is checked.
///
/// A struct rather than a tuple because it has grown twice — once for the
/// lowering's reports, once for what a component says about itself — and each
/// time every caller had to be edited to widen a shape nobody had named.
priv struct Split {
  file : @viewfile.ViewFile
  issues : Array[Issue]
}

///|
/// One lowering report, as the issue the card path already carries.
///
/// `comp` is empty because a section that did not lower has no component to
/// blame — the file may not have named one yet, and guessing would put the
/// wrong name in front of an author.
fn issue_of(r : @report.Report, src : @report.Source) -> Issue {
  let span = match r.anchor() {
    Some(label) => label.span
    None => @report.Span::of_range(0, 0)
  }
  {
    comp: "",
    code: r.code.unwrap_or("TUTU_LOWER"),
    message: r.message,
    severity: match r.severity {
      Error => "error"
      Warning | Advice => "warning"
    },
    line: src.line_of(span.start) + 1,
    span: { start: span.start, end_: span.end(), },
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
    // `declarations()` and not `parse_script(block.text)`: a `logic:` section
    // read from a `.tutu` arrives as DECLARATIONS and its text is empty, so
    // parsing the text again answered nothing — every handler in the card,
    // silently absent, which compiles and renders and does nothing.
    let block = file.script_block_for(def.component)
    let decls = match block {
      None => []
      Some(b) =>
        b.declarations() catch {
          e =>
            raise BadScript([
              "\{def.component}: line \{b.block.line}: \{e.message()}",
            ])
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
/// The card's wap module name.
///
/// Every declaration wap emits is prefixed with it — `card__Counter_receive_inc`
/// — which is how a generated module's names cannot collide with the runtime's
/// or the preamble's however a component is spelled.
let card_module : String = "card"

///|
fn build(
  comps : Array[Comp],
  name : String,
  macros? : Array[@viewfile.MacroDef] = [],
  source? : String = "",
) -> Compiled raise GenError {
  let b = B::new(@report.Sources::new().add("card", ""))
  // The BODY first, then the imports it turned out to need. A module's import
  // section is meant to be a true statement about what it does, and one written
  // before the body is a statement about what it COULD do.
  let decls : Array[@wast.Decl] = []
  for d in own_array_types(b) {
    decls.push(d)
  }
  for c in comps {
    for d in emit_state(b, c) {
      decls.push(d)
    }
    for d in emit_decls(b, c) {
      decls.push(d)
    }
  }
  // The manifest is built ONCE, here, and then written into the module. The
  // JSON a caller gets back is `to_json()` of the same value — a projection
  // rather than a second description that could disagree with the first.
  let refusals = []
  for c in comps {
    for r in c.refusals {
      refusals.push(r)
    }
  }
  let manifest = manifest_value(comps, name, refusals, macros, source)
  for d in emit_shell(b, comps, manifest) {
    decls.push(d)
  }
  // Now the head: the module name, the preamble it imports, and exactly the
  // runtime functions the emitters asked for.
  let head : Array[@wast.Decl] = [
    ModuleName(card_module),
    Import([@abi.preamble_module]),
    import_decl(b),
  ]
  for d in decls {
    head.push(d)
  }
  let module_ : @wast.Module = { name: card_module, decls: head, }
  let wasm = compile_wap(b, module_)
  {
    component: comps[0].name,
    components: comps.map(c => c.name),
    wasm,
    wap: print_module(module_),
    refusals,
    fields: comps[0].fields.map(f => f.name),
    manifest: manifest.to_json(),
  }
}

///|
/// What the generated module imports.
///
/// Exactly what the emitters reached for, and no more. `tgc/1` decided this by
/// SCANNING the generated text for each of eighty names, which was sound
/// because it wrote the text — but it answered a question about a string rather
/// than about the module, and it had to be careful that `member` did not match
/// `with_member`. Now every call to a runtime function goes through `B::rt`,
/// which records the name, so the import section is a list of what happened
/// rather than a search for evidence of it.
///
/// This matters beyond tidiness: `tgc/SECURITY.md` rests on a module's import
/// section being its COMPLETE authority list, so a card that performs no effect
/// must not import one.
fn import_decl(b : B) -> @wast.Decl {
  let funcs : Array[@wast.FnDecl] = []
  for f in @abi.vocab() {
    if !b.used.contains(f.name) {
      continue
    }
    let params : Array[@wast.Param] = []
    for p in f.params {
      let (pname, typ) = p
      params.push(b.param(pname, typ))
    }
    funcs.push({
      name: f.name,
      receiver: None,
      params,
      results: f.results,
      body: None,
      export_name: None,
      import_name: Some(f.import_name),
      is_start: false,
      is_pub: false,
      span: b.at(@tutuca.no_span),
    })
  }
  ImportHost(module_=@abi.import_namespace, funcs~, consts=[])
}

///|
/// Lower the card beside the preamble, and compile the pair.
///
/// The preamble is IMPORTED rather than prepended. `tgc/1` concatenated it as
/// text and then subtracted its line count from every diagnostic, with a branch
/// for when the arithmetic went negative that said "in the preamble — which is
/// a tgc bug, not yours". A module that imports its types has no such
/// arithmetic and no such branch.
fn compile_wap(b : B, module_ : @wast.Module) -> Bytes raise GenError {
  ignore(b)
  let parsed = @parse.parse_module(
    @abi.preamble_wap(),
    fname="\{@abi.preamble_module}.wap",
  ) catch {
    _ =>
      raise BadModule([
        "the frozen preamble did not parse — this is a tgc bug",
      ])
  }
  let lowered = @waplower.lower_program([
    {
      module_: parsed.module_(),
      source: {
        fname: "\{@abi.preamble_module}.wap",
        text: @abi.preamble_wap(),
        src: parsed.source(),
      },
    },
    { module_, source: { fname: "card.wap", text: "", src: parsed.source(), }, },
  ])
  if lowered.diagnostics().length() > 0 {
    let lines = []
    for r in lowered.diagnostics() {
      lines.push(r.message)
    }
    raise BadModule(lines)
  }
  // The vtable functions, given the format's frozen function type after the
  // fact — wap cannot annotate a definition with a named function type and a
  // vtable slot needs one. Which functions those are is read out of the module
  // rather than guessed from their names. See `@abi.retype_vtables`.
  let fields = @abi.retype_vtables(module_, lowered.fields()) catch {
    e => raise BadModule([e.to_string()])
  }
  let session = @compile.Session::new()
  let checked = session.check(fields)
  let reports = session.reports()
  if @compile.rejected(reports) {
    let lines = []
    for d in reports {
      lines.push("\{d.loc}: \{@message.to_plain_string(d.message)}")
    }
    raise BadModule(lines)
  }
  checked.to_bytes() catch {
    _ => raise BadModule(["the wasm encoder stopped"])
  }
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
  refusals : Array[@check.Refusal],
  macros : Array[@viewfile.MacroDef],
  source : String,
) -> @tutuca.Value {
  let out : Map[String, @tutuca.Value] = Map([])
  out["manifestVersion"] = Num(4)
  // The FORMAT's version, beside the manifest's own. `tgc.abi` exports it too
  // and that export is the ABI's own declaration — but reading it needs the
  // instantiated module, and a host wants to refuse a `tgc/1` module before it
  // instantiates anything. A `tgc/1` manifest has no such field, which reads as
  // 1 and is refused, which is right.
  out["abiVersion"] = Num(@abi.ABI_VERSION.to_double())
  out["apiVersion"] = Num(10)
  out["moduleName"] = Str(name)
  out["doc"] = Str("")
  out["version"] = Str("0.1.0")
  out["homepage"] = Str("")
  out["authors"] = List([])
  out["stringEncoding"] = Str("utf8")
  out["config"] = List([])
  // THE CARD ITSELF, once, and the views and macros below name what to read
  // out of it.
  //
  // The manifest used to carry each view and each macro as HTML — the notation
  // the front end read before `.tutu`, printed back out for the host to parse
  // again. Which meant a printer: the card arrives at the compiler as a TREE
  // now, so producing that field would have meant an `ANode` -> HTML writer,
  // byte-exact against a conformance suite, for a notation nothing else in the
  // tree is written in any more.
  //
  // Carrying the source instead costs a host the shrubbery reader and saves it
  // the HTML one, and the two sides read the SAME text with the SAME reader —
  // which is what a differential test can be written about. A host reads it
  // with `tutufile/toanode`, macros in hand, exactly as `viewgen` does.
  out["tutu"] = List(chunks_of(source).map(c => Str(c)))
  // A macro is markup the HOST expands when it parses a view, so a manifest
  // that dropped them is a view reaching for a name nothing declares. Its
  // defaults are named here because a caller may override them and the reader
  // needs the fallbacks; the body comes out of `tutu` above.
  out["macros"] = List(
    macros.map(m => {
      let defaults : Map[String, @tutuca.Value] = Map([])
      for k, v in m.defaults {
        defaults[k] = Str(v)
      }
      Map({ "name": Str(m.name), "defaults": Map(defaults) })
    }),
  )
  out["components"] = List(comps.map(c => component_value(c, name, refusals)))
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
/// The card source, in pieces a wasm module can hold.
///
/// A string literal lowers to `array.new_fixed`, and v8 refuses one with more
/// than 10000 elements — so a card of any size at all cannot cross as one
/// literal. The pieces are joined by whoever reads them, which is the host and
/// nothing else.
///
/// Cut on CHARACTER boundaries, not on the string's own indices: a cut through
/// a surrogate pair would make two pieces that are each invalid and a join that
/// is not the source.
fn chunks_of(source : String) -> Array[String] {
  let chars = source.to_array()
  let out = []
  let mut at = 0
  while at < chars.length() {
    let end = if at + 4096 < chars.length() {
      at + 4096
    } else {
      chars.length()
    }
    let piece = StringBuilder()
    for i in at..<end {
      piece.write_char(chars[i])
    }
    out.push(piece.to_string())
    at = end
  }
  if out.is_empty() {
    out.push("")
  }
  out
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
fn component_value(
  c : Comp,
  module_name : String,
  refusals : Array[@check.Refusal],
) -> @tutuca.Value {
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
  // WHO MADE IT, and the reason it is on the component rather than only on the
  // manifest around it: `<C>_desc()` is this same value, so this is the only
  // place an INSTANCE can say which module it came from. A host holding
  // instances from two modules has nothing else to tell them apart — a handle
  // is per-module, and `tg_inst.id` is a per-module counter starting at zero —
  // so without this the host wraps a foreign instance with the wrong module's
  // schema and renders one component's view over another's fields.
  out["module"] = Str(module_name)
  out["doc"] = Str(c.def.doc.unwrap_or(""))
  // WHAT THE COMPONENT SAYS, not what a host was told about it. A shipper's
  // annotation table fills the silence when these are empty and does not
  // shadow them when they are not — the person who knows a component's
  // keywords is the person who wrote it, and a host-side row is not versioned
  // with the card that outgrew it.
  //
  // Both are SEARCH TEXT and neither is an identifier: `compose/catalog`
  // lowercases the category and matches it against what a person typed into a
  // palette. So they survive spelled as they were written, spaces and capitals
  // included, the way a protocol id does.
  out["keywords"] = List(c.def.keywords.map(k => Str(k)))
  out["category"] = Str(c.def.category)
  out["messageDocs"] = List([])
  // NAMES, in the order the file declares them, `main` first. The bodies are
  // in the manifest's `tutu`, under `<Component>.<name>` — a host reads them
  // there rather than being handed each one twice.
  out["views"] = List(
    c.views.map(v => {
      Map({
        "name": Str(v.name),
        "bytes": Num(
          (match v.tree {
            Some(t) => t.bytes
            None => v.source.length()
          }).to_double(),
        ),
      })
    }),
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
  let src = @rt.source()
  let loader = @resolve.MapLoader::new(entries=[
    (@abi.preamble_module, @abi.preamble_wap()),
  ])
  let m = match @wap.program_to_wax("tutuca-rt.wap", src, loader) {
    Ok(m) => m
    Err(_) =>
      raise BadModule([
        "the embedded runtime does not resolve — `rt_src_gen.mbt` is stale " +
        "against `rt.wap`. Rerun the `rt-embed` task.",
      ])
  }
  if m.diagnostics.length() > 0 {
    raise BadModule([
      "the embedded runtime does not lower — `rt_src_gen.mbt` is stale against " +
      "`rt.wap`, or `rt.wap` itself is broken. Rerun the `rt-embed` task, then " +
      "compile `rt.wap` with `tgc build` for the diagnostics this deliberately " +
      "does not carry",
    ])
  }
  // The runtime is the one module that declares an `import was`, because it is
  // the one module that needs a cell that changes: instance identity. wap
  // records the signature and emits nothing, so the definition arrives here.
  let fields = m.fields
  for f in @abi.runtime_sys_fields() {
    fields.push(f)
  }
  let session = @compile.Session::new()
  let checked = session.check(fields)
  if @compile.rejected(session.reports()) {
    raise BadModule([
      "the embedded runtime does not check — `rt_src_gen.mbt` is stale against " +
      "`rt.wap`, or `rt.wap` itself is broken. Rerun the `rt-embed` task, then " +
      "compile `rt.wap` with `tgc build` for the diagnostics this deliberately " +
      "does not carry",
    ])
  }
  checked.to_bytes() catch {
    _ => raise BadModule(["the wasm encoder stopped on the runtime"])
  }
}
