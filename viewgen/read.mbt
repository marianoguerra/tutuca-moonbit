// A `.tutu` file, read into the shapes the generator works over.
//
// The one reader there is. The splitter it replaced recovered blocks of TEXT
// from an `.html` file and every consumer parsed them again; this reads each
// section into the shape it means, once, with the four readers `tutufile/`
// provides. Nothing is printed on the way, so there is no notation between the
// file and the generator and no printer to keep in step with a parser.
//
// It answers a `@viewfile.ViewFile` rather than a shape of its own, because
// everything downstream already takes one — the difference is that a view
// arrives with its TREE and a `logic:` section with its DECLARATIONS, and the
// text fields they replace are left empty.

///|
/// Read a `.tutu` into the file shape the generator consumes.
///
/// `name` is the fallback for a file that declares one component and never
/// names it. A `.tutu` always names its components, so it is only what the
/// shared half of `statedef` asks for.
pub fn read_file(
  source : String,
  name? : String = "",
) -> @viewfile.ViewFile raise GenError {
  let reports = []
  let file = read_into(source, name, reports)
  if reports is [r, ..] {
    raise ReadIssue(r.message)
  }
  file
}

///|
/// The same read, with every report handed back instead of the first one
/// raised.
///
/// For a caller that CHECKS rather than builds. A card compiler answers a list
/// of issues over a card an author is still writing, so a `view:` that will
/// not read has to leave the `logic:` beside it readable — otherwise fixing
/// the first thing is the only way to see the second, and the count a check
/// prints is a count of one.
///
/// This is the lesson the lowering learned the expensive way: it dropped its
/// reports for a while, and a card whose whole `logic:` section was garbage
/// compiled to 5158 bytes with "0 issues" — which reads as a dispatch bug
/// rather than a compile error, and was chased as one.
pub fn read_card(
  source : String,
  name? : String = "",
) -> (@viewfile.ViewFile, Array[@report.Report]) raise GenError {
  let reports = []
  let file = read_into(source, name, reports)
  (file, reports)
}

///|
/// The read itself. Everything recoverable lands in `reports` and the section
/// it came from contributes what it could; only a `spec:` that will not read
/// raises, because nothing downstream of it has a component to belong to.
fn read_into(
  source : String,
  name : String,
  reports : Array[@report.Report],
) -> @viewfile.ViewFile raise GenError {
  let sources = @report.Sources::new()
  let id = sources.add(if name == "" { "view.tutu" } else { name }, source)
  let file = @tutufile.read(source, id)
  for r in file.reports {
    reports.push(r)
  }
  let spec = decls_in(file, Spec)
  let state = @statedef.state_of_tutu(spec, name~) catch {
    e => raise ReadIssue(@statedef.DefError::message(e))
  }
  let view_decls = decls_in(file, View)
  let macros = @toanode.macros_of(view_decls) catch {
    e => raise ReadIssue(ex_message(e))
  }
  let said = (span : @report.Span, msg : String) => {
    reports.push(
      @report.Report::error(msg).with_label(@report.Label::primary(id, span)),
    )
  }
  // A view arrives EXPANDED: `ViewBuilder` grafts a macro call where it
  // stands, so the trees below carry no macro nodes and the generator has
  // nothing left to expand. The declarations are still reported, because a
  // consumer that writes them out — the card manifest — needs their names.
  let macro_defs = []
  for d in view_decls {
    if d.kind is Macro {
      macro_defs.push(
        ({ name: d.name, defaults: Map([]), source: "", } : @viewfile.MacroDef),
      )
    }
  }
  // A `style()` at the top of `view:` is the file's, and `style(~global)`
  // is the page's. The two go to different places — one is scoped to the
  // component, the other is emitted verbatim — so they are collected apart.
  let file_style = StringBuilder()
  let global_style = StringBuilder()
  for d in view_decls {
    if d.kind is Style {
      let css = @toanode.style_of(d) catch {
        e => raise ReadIssue(ex_message(e))
      }
      if @toanode.style_is_global(d) {
        global_style.write_string(css)
      } else {
        file_style.write_string(css)
      }
    }
  }
  // One entry per component, in the order the `view:` section declares them —
  // the same order the splitter answered, because a file-level style belongs
  // to the component at index 0.
  let order = []
  let by_comp : Map[String, Array[@viewfile.RawView]] = Map([])
  for d in view_decls {
    guard d.kind is View else { continue }
    let (comp, vname) = split_view_name(d.name)
    if by_comp.get(comp) is None {
      by_comp[comp] = []
      order.push(comp)
    }
    let built = @toanode.ViewBuilder::new(macros~).view(d) catch {
      e => {
        said(d.span, "view \"\{d.name}\": \{ex_message(e)}")
        continue
      }
    }
    guard built.anode is Some(root) else {
      said(d.span, "view \"\{d.name}\" is empty")
      continue
    }
    let events = built.ctx.map(c => c.events).unwrap_or([])
    let raw : @viewfile.RawView = {
      name: vname,
      source: "",
      style: built.style,
      tree: Some({ root, events, bytes: d.span.end() - d.span.start, }),
    }
    // `main` first, which is what every consumer of a view set assumes.
    if vname == "main" {
      into_set(by_comp, comp, raw, first=true)
    } else {
      into_set(by_comp, comp, raw, first=false)
    }
  }
  let components = []
  for at, comp in order {
    components.push(
      (
        {
          name: comp,
          views: by_comp.get(comp).unwrap_or([]),
          common_style: if at == 0 {
            file_style.to_string()
          } else {
            ""
          },
          global_style: if at == 0 {
            global_style.to_string()
          } else {
            ""
          },
        } : @viewfile.ViewSet),
    )
  }
  // Which members a render-time option NAMES. A `pred` has two shapes and the
  // declaration cannot say which — `pred room: it.n < 10` is called from a
  // slot, `pred matches(row)` filters one — so the VIEW is what decides, and
  // only a reader holding both sections can ask.
  let rows = @sh.row_members(view_decls)
  let scripts = []
  for d in decls_in(file, Logic) {
    guard d.kind is Component else { continue }
    let decls = @tologic.read_logic(d, rows~) catch {
      e => {
        said(d.span, ex_message(e))
        continue
      }
    }
    scripts.push(
      (
        {
          comp: d.name,
          block: { text: "", offset: d.span.start, line: 0, },
          decls: Some(decls),
        } : @viewfile.ScriptBlock),
    )
  }
  // A property the LOGIC sets is writable, and only this function can see
  // both halves: `spec:` declares the property and `logic:` implements its
  // accessors, so a spec reader on its own has to answer "read-only" for
  // every property whose `set` is written next door. The lowering merged the
  // two before printing, which is why the block it printed said `{ get set }`
  // for a property whose `spec:` line says neither.
  let set_by_logic : Map[String, Array[String]] = Map([])
  for sb in scripts {
    let names = []
    for d in sb.decls.unwrap_or([]) {
      if d.kind is DSet {
        names.push(d.name)
      }
    }
    if !names.is_empty() {
      set_by_logic[sb.comp] = names
    }
  }
  let state = state.map(def => {
    match set_by_logic.get(def.component) {
      None => def
      Some(names) =>
        {
          ..def,
          properties: def.properties.map(p => {
            if p.writable || !names.contains(p.name) {
              p
            } else {
              { ..p, writable: true, }
            }
          }),
        }
    }
  })
  let init = read_fixtures(file, state) catch {
    e => {
      said(
        file.section(Fixtures).map(b => b.span).unwrap_or(@report.Span::at(0)),
        GenError::message(e),
      )
      []
    }
  }
  let tests = read_scenes(file) catch {
    e => {
      said(
        file.section(Tests).map(b => b.span).unwrap_or(@report.Span::at(0)),
        GenError::message(e),
      )
      []
    }
  }
  // The component a host mounts when told no other name. `~root` says so; with
  // no marker the first component is the root, which is what an empty name
  // means downstream.
  let mut root = ""
  for d in spec {
    if d.kind is Component && d.options.contains("root") {
      root = d.name
    }
  }
  // The `spec:` section's own text, which the generator writes into the module
  // as `<comp>_spec_source`. The schema beside it is a PROJECTION — a rule
  // reaches it as a name with no body — so a reader that wants the rule back
  // re-reads this. It is `.tutu` now, and `@statedef.state_of_tutu` is what
  // reads it.
  // A section's own span is its HEADING — `spec:` and nothing under it — so
  // the text runs from the heading to the end of the last declaration under
  // it. WITH the heading, and from the start of its line: what comes out is a
  // `.tutu` fragment that reads on its own, which is what a consumer
  // re-reading it needs.
  let state_block = if spec is [first, ..] {
    let mut start = match file.section(Spec) {
      Some(b) => line_start(source, b.span.start)
      None => line_start(source, first.span.start)
    }
    let mut end = first.span.end()
    for d in spec {
      if d.span.start < start {
        start = line_start(source, d.span.start)
      }
      if d.span.end() > end {
        end = d.span.end()
      }
    }
    Some(
      (
        { text: source[start:end].to_owned(), offset: start, line: 0, } :
        @viewfile.Block),
    )
  } else {
    None
  }
  {
    components,
    macros: macro_defs,
    state,
    state_block,
    init,
    scripts,
    tests,
    root,
  }
}

///|
/// One view into its component's set, `main` first.
fn into_set(
  by_comp : Map[String, Array[@viewfile.RawView]],
  comp : String,
  raw : @viewfile.RawView,
  first~ : Bool,
) -> Unit {
  match by_comp.get(comp) {
    Some(vs) => if first { vs.insert(0, raw) } else { vs.push(raw) }
    None => by_comp[comp] = [raw]
  }
}

///|
/// The declarations of one section, or none when the file has no such section.
fn decls_in(
  file : @tutufile.TutuFile,
  s : @tutufile.Section,
) -> Array[@tutufile.Decl] {
  match file.section(s) {
    Some(block) => block.decls
    None => []
  }
}

///|
/// `Note.edit` is one component and one of its views; a bare name is `main`.
fn split_view_name(id : String) -> (String, String) {
  match id.rev_find(".") {
    Some(at) => (id[:at].to_owned(), id[at + 1:].to_owned())
    None => (id, "main")
  }
}

///|
/// The `fixtures:` section, checked against the schema the same way the block
/// front end checks it — the reader answers JSON and `statedef` reads it.
fn read_fixtures(
  file : @tutufile.TutuFile,
  state : Array[@statedef.StateDef],
) -> Array[(String, @statedef.InitState)] raise GenError {
  let decls = decls_in(file, Fixtures)
  guard decls.length() > 0 else { return [] }
  let json = @todata.fixtures_json(decls) catch {
    e => raise ReadIssue(ex_message(e))
  }
  guard state is [def, ..] else { return [] }
  let states = @statedef.parse_init(json.stringify(), def) catch {
    e => raise ReadIssue(@statedef.InitError::message(e))
  }
  let out = []
  for s in states {
    out.push((def.component, s))
  }
  out
}

///|
/// The `tests:` section, as scenes.
fn read_scenes(
  file : @tutufile.TutuFile,
) -> Array[@scenedef.Scene] raise GenError {
  let decls = decls_in(file, Tests)
  guard decls.length() > 0 else { return [] }
  let json = @todata.scenes_json(decls) catch {
    e => raise ReadIssue(ex_message(e))
  }
  @scenedef.parse_scenes(json.stringify()) catch {
    e => raise ReadIssue(@scenedef.SceneError::message(e))
  }
}

///|
/// The offset of the start of the line `at` is on.
fn line_start(source : String, at : Int) -> Int {
  let cs = source.to_array()
  let mut i = if at > cs.length() { cs.length() } else { at }
  while i > 0 && cs[i - 1] != '\n' {
    i = i - 1
  }
  i
}

///|
/// One reader failure, as its message.
fn ex_message(e : @sh.ExError) -> String {
  let ExError(message~, help~, ..) = e
  if help == "" {
    message
  } else {
    message + " — " + help
  }
}
