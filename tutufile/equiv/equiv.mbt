// Comparing a converted `.tutu` file with the `.html` file it replaces.

///|
/// One thing the two files do not agree about.
///
/// It carries both sides rather than a rendered diff, because the caller
/// decides how much to show: a corpus sweep wants one line per file, and a
/// person converting one file wants the whole of both.
pub(all) struct Difference {
  section : String
  what : String
  html : String
  tutu : String
} derive(@debug.Debug)

///|
/// A one-line rendering, for a sweep.
pub fn Difference::line(self : Difference) -> String {
  "\{self.section}: \{self.what}"
}

///|
/// Everything the two files disagree about. Empty means the conversion is
/// sound.
///
/// `name` is what the CLI's `--name` would supply: a `.html` file that declares
/// one unnamed component has no name of its own, and a `.tutu` file always
/// names its components, so the comparison needs to be told which name the
/// nameless side was going to get. This is the one asymmetry the notation
/// change actually introduces (see `docs/tutu-migration.md`, "Naming an
/// anonymous component changes its fingerprint").
pub fn compare(
  html : String,
  tutu : String,
  name~ : String,
) -> Array[Difference] {
  let out : Array[Difference] = []
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", tutu)
  let lowered = @lower.lower(tutu, id)
  for r in lowered.reports {
    out.push({
      section: "tutu",
      what: "the file did not lower: \{r.message}",
      html: "",
      tutu: "",
    })
  }
  if !out.is_empty() {
    return out
  }
  let a = @viewfile.split_file(html, name~) catch {
    e => {
      out.push({
        section: "html",
        what: "the file did not split: \{e.message()}",
        html: "",
        tutu: "",
      })
      return out
    }
  }
  let b = @viewfile.split_file(lowered.text, name~) catch {
    e => {
      out.push({
        section: "tutu",
        what: "what it lowered to did not split: \{e.message()}",
        html: "",
        tutu: "",
      })
      return out
    }
  }
  compare_spec(a, b, out)
  compare_logic(a, b, out)
  compare_data(a, b, out)
  compare_views(a, tutu, name, out)
  out
}

///|
/// The schema, as the splitter parsed it on both sides.
fn compare_spec(
  a : @viewfile.ViewFile,
  b : @viewfile.ViewFile,
  out : Array[Difference],
) -> Unit {
  if a.state.length() != b.state.length() {
    out.push({
      section: "spec",
      what: "a different number of components is declared",
      html: a.state.length().to_string(),
      tutu: b.state.length().to_string(),
    })
    return
  }
  for i, sa in a.state {
    let sb = b.state[i]
    // `source_name` is the ONE field allowed to differ: an anonymous `state {}`
    // has none and a `.tutu` component always does. Everything the runtime
    // reads is compared.
    if sa.component != sb.component {
      out.push({
        section: "spec",
        what: "component name",
        html: sa.component,
        tutu: sb.component,
      })
    }
    diff_debug(out, "spec", "\{sa.component} fields", sa.fields, sb.fields)
    diff_debug(
      out,
      "spec",
      "\{sa.component} properties",
      sa.properties,
      sb.properties,
    )
    compare_rules(out, sa, sb)
    diff_debug(out, "spec", "\{sa.component} wheres", sa.wheres, sb.wheres)
    diff_debug(out, "spec", "\{sa.component} receive", sa.receive, sb.receive)
    diff_debug(out, "spec", "\{sa.component} intent", sa.intent, sb.intent)
    diff_debug(
      out,
      "spec",
      "\{sa.component} express_message",
      sa.express_message,
      sb.express_message,
    )
    diff_debug(
      out,
      "spec",
      "\{sa.component} express_intent",
      sa.express_intent,
      sb.express_intent,
    )
    diff_debug(
      out,
      "spec",
      "\{sa.component} implements",
      sa.implements,
      sb.implements,
    )
    diff_debug(
      out,
      "spec",
      "\{sa.component} protocols",
      sa.protocols,
      sb.protocols,
    )
    diff_debug(out, "spec", "\{sa.component} types", sa.types, sb.types)
    diff_debug(out, "spec", "\{sa.component} provide", sa.provide, sb.provide)
    diff_debug(out, "spec", "\{sa.component} lookup", sa.lookup, sb.lookup)
  }
}

///|
/// The rules, compared by what their bodies MEAN.
///
/// A `RuleDecl` keeps its body and its format as SOURCE TEXT — the schema
/// parser hands them on unparsed, and whoever needs the expression parses it.
/// The two notations spell the same expression differently on purpose (the
/// lowering parenthesises what shrubbery did not need to), so comparing the
/// text would report every rule in the corpus as a difference. Parsing is the
/// comparison that says whether they mean the same thing.
fn compare_rules(
  out : Array[Difference],
  a : @statedef.StateDef,
  b : @statedef.StateDef,
) -> Unit {
  if a.rules.length() != b.rules.length() {
    diff_debug(
      out,
      "spec",
      "\{a.component} rule count",
      a.rules.length(),
      b.rules.length(),
    )
    return
  }
  for i, ra in a.rules {
    let rb = b.rules[i]
    diff_debug(out, "spec", "\{a.component} rule kind", ra.kind, rb.kind)
    diff_debug(out, "spec", "\{a.component} rule name", ra.name, rb.name)
    diff_debug(
      out,
      "spec",
      "\{a.component} rule `\{ra.name}` doc",
      ra.doc,
      rb.doc,
    )
    diff_debug(
      out,
      "spec",
      "\{a.component} rule `\{ra.name}` body",
      ra.body,
      rb.body,
    )
    diff_debug(
      out,
      "spec",
      "\{a.component} rule `\{ra.name}` format",
      ra.format,
      rb.format,
    )
  }
}

///|
/// The handlers, as the script parser parses them.
///
/// Parsed rather than compared as text, because the two notations spell the
/// same handler differently on purpose and only the parse says whether they
/// mean the same thing.
fn compare_logic(
  a : @viewfile.ViewFile,
  b : @viewfile.ViewFile,
  out : Array[Difference],
) -> Unit {
  // A file that declares ONE component names its script block `""` on the
  // `.html` side and names the component on the `.tutu` side, because a `.tutu`
  // file always names its components. That is the notation change, not a
  // difference in what the file says, so the two are one key here.
  let names = []
  for comp in script_names(a) {
    if !names.contains(comp) {
      names.push(comp)
    }
  }
  for comp in script_names(b) {
    if !names.contains(comp) {
      names.push(comp)
    }
  }
  for comp in names {
    // A block that does not PARSE is reported as itself. Read as an empty
    // handler list it compared unequal for the right reason and said the
    // wrong thing — "the converted file has no handlers" — about a converted
    // file whose handlers were all there and one of them misspelled.
    let da = match script_decls(a, comp) {
      Ok(d) => d
      Err(msg) => {
        out.push({
          section: "logic",
          what: "\{comp} handlers",
          html: "the script block does not parse: \{msg}",
          tutu: "",
        })
        continue
      }
    }
    let db = match script_decls(b, comp) {
      Ok(d) => d
      Err(msg) => {
        out.push({
          section: "logic",
          what: "\{comp} handlers",
          html: "",
          tutu: "the converted `logic:` section does not parse: \{msg}",
        })
        continue
      }
    }
    diff_debug(
      out,
      "logic",
      "\{comp} handlers",
      da.map(flat_decl),
      db.map(flat_decl),
    )
  }
}

///|
/// One declaration with its operator chains reduced.
///
/// The same normalisation the view half applies, for the same reason: a slot
/// parser reads `(a + b)` as an application and the block grammar reads it as a
/// chain, and an associative chain of six operands is one `EChain` on one side
/// and a nest of two-operand ones on the other. `eval_chain` reduces the first
/// to the second before evaluating it, so they are one expression written two
/// ways.
fn flat_decl(d : @tscript.Decl) -> @tscript.Decl {
  { ..d, body: flat_body(d.body), format: d.format.map(@toanode.flat_expr), }
}

///|
fn flat_body(b : @tscript.Body) -> @tscript.Body {
  match b {
    Value(e) => Value(@toanode.flat_expr(e))
    Stmts(ss) => Stmts(ss.map(flat_stmt))
  }
}

///|
fn flat_stmt(s : @tscript.Stmt) -> @tscript.Stmt {
  let f = @toanode.flat_expr
  match s {
    SAssign(place~, op~, value~, span~) =>
      SAssign(place~, op~, value=f(value), span~)
    SMethod(place~, call~, args~, span~) =>
      SMethod(place~, call~, args=args.map(f), span~)
    SEffect(name~, args~, route~, span~) =>
      SEffect(name~, args=args.map(f), route~, span~)
    SIf(cond~, then_~, else_~, span~) =>
      SIf(
        cond=f(cond),
        then_=then_.map(flat_stmt),
        else_=else_.map(flat_stmt),
        span~,
      )
    other => other
  }
}

///|
/// The component names a file's script blocks answer for, with the anonymous
/// one resolved to the single component it must have meant.
fn script_names(f : @viewfile.ViewFile) -> Array[String] {
  let out = []
  for s in f.scripts {
    if s.comp != "" {
      out.push(s.comp)
    } else if f.state.length() == 1 {
      out.push(f.state[0].component)
    } else if f.components.length() == 1 {
      out.push(f.components[0].name)
    } else {
      out.push("")
    }
  }
  out
}

///|
/// One component's parsed script declarations, or none.
///
/// A single-component file's block is looked up under the empty name too, since
/// that is what the `.html` side calls it.
fn script_decls(
  f : @viewfile.ViewFile,
  comp : String,
) -> Result[Array[@tscript.Decl], String] {
  let block = match f.script_for(comp) {
    Some(b) => Some(b)
    None =>
      if f.scripts.length() == 1 {
        Some(f.scripts[0].block)
      } else {
        None
      }
  }
  match block {
    Some(block) =>
      Ok(@tscript.parse_script(block.text)) catch {
        e => Err(e.message())
      }
    None => Ok([])
  }
}

///|
/// The fixtures and the scenes.
fn compare_data(
  a : @viewfile.ViewFile,
  b : @viewfile.ViewFile,
  out : Array[Difference],
) -> Unit {
  diff_debug(out, "fixtures", "fixtures", a.init, b.init)
  diff_debug(out, "tests", "scenes", a.tests, b.tests)
}

///|
/// The trees.
///
/// The `.html` side is parsed; the `.tutu` side is built by `tutufile/toanode`,
/// the direct reader. Comparing those two is what makes this check say
/// something about the reader as well as about the conversion.
fn compare_views(
  a : @viewfile.ViewFile,
  tutu : String,
  name : String,
  out : Array[Difference],
) -> Unit {
  let scope = FileMacros::of(a.macros)
  let decls = view_decls(tutu)
  let macros = @toanode.macros_of(decls) catch {
    @sh.ExError(message~, ..) => {
      out.push({
        section: "view",
        what: "macro: \{message}",
        html: "",
        tutu: "",
      })
      return
    }
  }
  // Every view the `.html` file has, looked up in the `.tutu` file by the pair
  // that names it: a component and one of its views.
  for set in a.components {
    for v in set.views {
      // Resolved exactly as the converter resolves it: the spec block first,
      // the caller's name only when the spec does not say.
      let comp = if set.name != "" {
        set.name
      } else if a.state.length() == 1 {
        a.state[0].component
      } else {
        name
      }
      let want = if v.name == "main" { comp } else { comp + "." + v.name }
      let decl = find_view(decls, comp, v.name)
      guard decl is Some(decl) else {
        out.push({
          section: "view",
          what: "`\{want}` is not declared",
          html: v.name,
          tutu: "",
        })
        continue
      }
      // The reader's own message, not a bare "did not read". A converter that
      // printed something the reader refuses is the commonest failure there is,
      // and the refusal already names the construct.
      let built = @toanode.ViewBuilder::new(macros~).view(decl) catch {
        @sh.ExError(message~, help~, ..) => {
          out.push({
            section: "view",
            what: "`\{want}` did not read: \{message} — \{help}",
            html: "",
            tutu: "",
          })
          continue
        }
      }
      guard built.anode is Some(tree) else {
        out.push({
          section: "view",
          what: "`\{want}` read as nothing",
          html: "",
          tutu: "",
        })
        continue
      }
      let (parsed, _) = parse_html(v, scope)
      guard parsed is Some(parsed) else {
        out.push({
          section: "view",
          what: "`\{want}` did not parse on the html side",
          html: "",
          tutu: "",
        })
        continue
      }
      diff_debug(
        out,
        "view",
        want,
        @toanode.strip_ws(
          @toanode.flatten_ops(@toanode.strip_macro_calls(parsed)),
        ),
        @toanode.strip_ws(
          @toanode.flatten_ops(@toanode.strip_macro_calls(tree)),
        ),
      )
      if @toanode.collapse_ws(v.style) != @toanode.collapse_ws(built.style) {
        out.push({
          section: "view",
          what: "`\{want}` style",
          html: v.style,
          tutu: built.style,
        })
      }
    }
  }
}

///|
/// The declaration for a `Comp.view` pair.
///
/// A `.tutu` file names a component's `main` view by the component alone and
/// every other view `Comp.view`, which is how the converter writes them. Both
/// spellings are tried and NOTHING else is: a fallback that took the first view
/// it could see compared one component's markup against another's and reported
/// a difference about a view that was never looked at.
fn find_view(
  decls : Array[@tutufile.Decl],
  comp : String,
  view : String,
) -> @tutufile.Decl? {
  let want = if view == "main" { comp } else { comp + "." + view }
  for d in decls {
    if d.kind is View && d.name == want {
      return Some(d)
    }
  }
  None
}

///|
fn parse_html(
  v : @viewfile.RawView,
  scope : FileMacros,
) -> (@anode.ANode?, Array[@anode.NodeEvents]) {
  let view = @anode.View::new(v.name, raw_view=v.source)
  let px = @anode.ParseContext::new()
  view.compile(px, scope) catch {
    _ => return (None, [])
  }
  (view.anode, px.events)
}

///|
/// The `view:` section's declarations.
fn view_decls(tutu : String) -> Array[@tutufile.Decl] {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", tutu)
  let file = @tutufile.read(tutu, id)
  match file.section(View) {
    Some(s) => s.decls
    None => []
  }
}

///|
/// A macro scope over the `.html` file's own macro templates.
priv struct FileMacros {
  by_name : Map[String, @anode.Macro]
}

///|
fn FileMacros::of(defs : Array[@viewfile.MacroDef]) -> FileMacros {
  let by_name : Map[String, @anode.Macro] = Map([])
  for d in defs {
    by_name[d.name] = { defaults: d.defaults, raw_view: d.source, }
  }
  { by_name, }
}

///|
impl @anode.MacroScope for FileMacros with fn lookup_macro(self, name) {
  self.by_name.get(name)
}

///|
/// Compare two values by what `Debug` says about them.
///
/// A structural comparison would need `Eq` on a dozen types that do not derive
/// it, and the point here is to REPORT a difference rather than to decide one:
/// a reader has to see both sides to know which side is wrong.
fn[T : @debug.Debug] diff_debug(
  out : Array[Difference],
  section : String,
  what : String,
  a : T,
  b : T,
) -> Unit {
  // A DEPTH rather than `to_string`: `Debug` elides below its default depth,
  // and two trees that differ only in how deep they sit render one elided and
  // one not — a difference about the printer. Deep enough that nothing in the
  // corpus reaches it.
  let sa = scrub(@debug.render(Repr::Repr(a), max_depth=200))
  let sb = scrub(@debug.render(Repr::Repr(b), max_depth=200))
  if sa != sb {
    out.push({ section, what, html: sa, tutu: sb, })
  }
}
