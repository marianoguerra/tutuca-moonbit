// `tutuca gen` — ahead-of-time view compilation. An .html file holding
// one or more views becomes a companion MoonBit module of typed view
// surfaces, so handler names, argument shapes, view names and element ids
// stop being strings the compiler cannot see.
//
// Pure like the rest of cli/: this half parses the flags and turns SOURCE
// TEXT into GENERATED TEXT. The shell (cmd/tutuca) reads the input file and
// writes the plan, the same split `install-skill` uses.

///|
/// What the shell should write: (path, contents) pairs, already resolved
/// against `--out`.
pub(all) struct GenPlan {
  files : Array[(String, String)]
  /// View problems worth reporting that do not stop generation: structural
  /// HTML mistakes and the deprecation nudges. Anything that makes the
  /// emitted types wrong already fails generation instead (@viewgen), so a
  /// diagnostic here never means "the output is untrustworthy".
  diagnostics : Array[String]
} derive(Debug, Eq)

///|
/// View diagnostics, reported at generation time.
///
/// This is where view checking happens, and the only place it happens: these
/// rules need nothing but the view text, and the generator is already parsing
/// every view. Which names are fields, which are methods, what is registered
/// in the scope — the generated types answer them at compile time, and what
/// the types cannot express is not worth a second, weaker check.
fn view_diagnostics(
  file : @viewfile.ViewFile,
  fallback : String,
) -> Array[String] {
  let out : Array[String] = []
  // A schema interface with no template declares state for a component whose
  // views are built in MoonBit. Legitimate, and also what a mistyped
  // interface name looks like — so it is reported, not generated in silence.
  let declared = @viewgen.declared_components(file, fallback)
  for def in file.state {
    if !declared.contains(def.component_name(fallback)) {
      out.push(
        "state-without-views (hint) \{def.component_name(fallback)}: the schema declares it but no <template> here gives it views" +
        (if declared.is_empty() {
          ""
        } else {
          " (this file declares \{declared.join(", ")})"
        }),
      )
    }
    for line in message_case_diagnostics(def, fallback) {
      out.push(line)
    }
    // NOT `check_stale_mutators` here, and the reason is the whole shape of
    // what `gen` can know.
    //
    // It ran here in 0.49.5, gated on the component having a script block —
    // "a card's handlers are all in it, so what this cannot see is nothing".
    // That is true of a CARD and false of a compiled component: a block is not
    // a promise that it is the only handler surface. `SkillEditor` in the
    // tutuca-components port has a block answering `save` and `cancel`, and
    // answers `setName` in MoonBit (`Receive("setName", args) => …`) because
    // it must also recompute a verdict, which a script arm cannot express.
    // `gen` reads .html, the arm is in .mbt, and the warning fired on correct
    // code — naming `.name = v` as the repair, which is precisely the bug that
    // component's author avoided on purpose.
    //
    // The sharpest statement of the bug, from the consumer who found it: the
    // per-component test was doing DOUBLE DUTY as "has no handlers here" and
    // "has all handlers here", and only the first is what a missing block
    // implies. The old comment argued the first and the code relied on the
    // second, which is why it read as justified.
    //
    // The property is per-NAME, not per-component: "is this name's handler
    // somewhere `gen` can see". For a compiled component the answer is no, and
    // there is nothing in the view file that changes it. So the check lives
    // where it is decidable — `tgc`'s card backend, where there is no MoonBit
    // for an arm to hide in — and `gen` does not guess.

    // The rule layer, checked against the schema it is about. A `pred` reading
    // a field the state does not declare is the same mistake as a view reading
    // one, and it is worth the same report — a rule that cannot be evaluated
    // is a rule that silently never holds.
    //
    // The spans are the spec BLOCK's, and it is the block's own line that puts
    // them on the file. That is the whole reason `check_rules` is a second
    // entry point: a finding about a rule and a finding about a handler come
    // out of different texts and cannot share one rebasing.
    for f in @check.check_rules(def) {
      let where_ = def.component_name(fallback)
      let line = match file.state_block {
        Some(b) =>
          "line \{b.line + @viewfile.line_of(b.text, f.span.start) - 1}: "
        None => ""
      }
      let level = if f.severity is SWarning { "warning" } else { "error" }
      out.push("\{f.code} (\{level}) \{where_}: \{line}\{f.message}")
    }
  }
  for comp in file.components {
    let cname = comp.component_name(fallback)
    for view in comp.views {
      let where_ = "\{cname}/\{view.name}"
      // Structural HTML (mismatched tags, bad nesting): the WHATWG-tokenizer
      // linter, which needs only the source text.
      for f in @lint.lint_html(view.source) {
        out.push(f.to_line(where_))
      }
      // Parse-issue rules, deprecation nudges and host bare directives. A
      // fresh shadow parse, never the live tree.
      let collector = @lint.LintCollector::new()
      let px = @anode.ParseContext::new(handler=collector)
      let _ = @anode.ANode::parse(view.source, px)
      for f in @lint.check_collected(collector) {
        out.push(f.to_line(where_))
      }
      // Event paths: an off-list step resolves under the open profile these
      // views run under, so it advises rather than refuses — see
      // `@lint.check_event_paths`.
      for f in @lint.check_event_paths(px.events) {
        out.push(f.to_line(where_))
      }
    }
  }
  out
}

///|
/// A message case declared in a spelling nothing else uses.
///
/// `MsgDef` keeps three spellings of one name — as written, the runtime name,
/// and the MoonBit variant — and the parser derives the last two from the
/// first, so `Init`, `init` and `INIT` all declare the same message. That
/// tolerance is deliberate and stays; what it costs is a schema that reads
/// `Init` sitting above a handler that reads `receive init` and a view that
/// writes `'init'`, which is one mental transform per message for every
/// reader.
///
/// So: declared the way it is used. `source_name != name` is the whole rule,
/// which catches `set_label` along with the capital — a separator spelling
/// diverges from the used name for exactly the same reason a capital does.
///
/// A hint would be the wrong level — the declaration is not a mistake and
/// nothing downstream is wrong — but a warning is what gets a house convention
/// followed, and the fix is always the name the message already prints.
fn message_case_diagnostics(
  def : @statedef.StateDef,
  fallback : String,
) -> Array[String] {
  let out : Array[String] = []
  let where_ = def.component_name(fallback)
  for pair in [("receive", def.receive), ("intent", def.intent)] {
    for m in pair.1 {
      // A protocol member's declared name and its runtime name differ BY
      // DESIGN: `Openable::setOpen` is what the file imported the protocol as,
      // and `tutuca.dev/std/Openable@1::setOpen` is the identity it travels
      // under. Comparing the whole strings warned on every declared member of
      // every protocol whose id is not its alias, and asked for a spelling the
      // declaration grammar cannot parse — the qualifier is an identifier
      // there, not a URL. So the qualifier is dropped on both sides and only
      // the member is compared, which is the casing question this rule is for.
      let (declared, used) = (member_of(m.source_name), member_of(m.name))
      if declared != used {
        let fix = qualifier_of(m.source_name) + used
        out.push(
          "message-case (warning) \{where_}: `\{pair.0}` declares `\{m.source_name}`, but every use of it is `\{fix}` — a handler writes `\{pair.0} \{fix}` and a view writes `'\{fix}'`. Declare it `\{fix}`.",
        )
      }
    }
  }
  out
}

///|
/// The member half of a possibly-qualified message name.
fn member_of(name : String) -> String {
  match name.rev_find("::") {
    Some(i) => name[i + 2:].to_owned()
    None => name
  }
}

///|
/// The qualifier half, `::` included, or empty for a bare name. Taken from the
/// name as WRITTEN, so a suggestion is spelled the way the file spells it.
fn qualifier_of(name : String) -> String {
  match name.rev_find("::") {
    Some(i) => name[:i + 2].to_owned()
    None => ""
  }
}

///|
let gen_views_help : String =
  #|tutuca gen [path...] [--name <Name>] [--out <dir-or-file>] [--dry-run]
  #|
  #|  Compiles the views in each path into a MoonBit module of typed view
  #|  surfaces, written next to the component that uses them.
  #|
  #|  Paths are .html files or directories, following watch's rule: a directory
  #|  contributes the .html files that ALREADY have a generated sibling, so
  #|  pointing this at a project root does not try to compile index.html.
  #|
  #|  Passing more than one path is not just a convenience. The checks that span
  #|  components — whether the component a view renders exists, and whether it
  #|  has the view `as=` names — can only see what one invocation was given. The
  #|  program is the set of paths you passed; a component outside it is unknown,
  #|  and unknown is never reported as wrong.
  #|
  #|  Template ids say what each one is:
  #|    (none)         the single unnamed component's `main` view
  #|    row            ...its `row` view
  #|    Counter:main   the `Counter` component's `main` view
  #|    Counter        shorthand for `Counter:main`
  #|    macro:icon     a macro shared by every component in the file; its
  #|                   data-* attributes are the defaults for the body's ^vars
  #|
  #|  One file per MoonBit module, not per component: a file names as many
  #|  components as the module defines. A <style> inside a template is that
  #|  view's style; one at file level is the first component's common style,
  #|  or its global style with data-global.
  #|
  #|  The generated module declares, for a component named Counter:
  #|    counter_main_view / counter_views()  the view sources, for component()
  #|    CounterInput / CounterMsg            @on handler names, with the argument
  #|                                         shapes inferred from the call sites,
  #|                                         plus CounterMsg::from_dispatch
  #|    CounterCompute                        $-callable names, answered as an
  #|                                         exhaustive match
  #|
  #|  With a <script type="tutuca/spec"> block it also declares CounterState,
  #|  its zero, its codec, and one SchemaInfo carrying the whole declaration:
  #|  the fields with their declared kinds, the handler channels, the view
  #|  names, the element ids and the fixture names. That descriptor is what an
  #|  instance answers schema() with, so an inspector holding a bare Value
  #|  can read it with no component registry.
  #|
  #|  --name  the component name, for a file whose templates do not name one
  #|          (default: the file's basename, capitalized). A file that names
  #|          its components with `id="Comp:view"` ignores it. Names ONE
  #|          component, so it is refused with more than one path.
  #|  --out   directory (default: each input's) or an explicit .mbt file path.
  #|          The .mbt form names one file, so it too is refused for a batch.
  #|  --dry-run prints the generated modules to stdout instead of writing.
  #|  --no-ir skips the companion <stem>_view_ir_gen.mbt (the compiled tree,
  #|          which `views~` takes so the parser never runs at
  #|          startup). It is skipped automatically for a view using a macro,
  #|          which only MoonBit can expand.
  #|
  #|  The generated file is checked in and regenerated, never hand-edited; its
  #|  package must import "marianoguerra/tutuca/core" @tutuca,
  #|  "marianoguerra/tutuca/component" and "moonbitlang/core/debug".
  #|

///|
/// "a/b/counter.html" -> ("a/b", "counter")
fn split_path(path : String) -> (String, String) {
  let chars = path.to_array()
  let mut slash = -1
  let mut dot = -1
  for i, c in chars {
    if c == '/' {
      slash = i
      dot = -1 // a dot in a directory name is not an extension
    } else if c == '.' {
      dot = i
    }
  }
  let dir = if slash < 0 { "" } else { path[:slash].to_owned() }
  let stem_start = slash + 1
  let stem_end = if dot > slash { dot } else { chars.length() }
  (dir, path[stem_start:stem_end].to_owned())
}

///|
/// Join a directory and a file name, tolerating an empty or trailing-slash
/// directory.
fn join_path(dir : String, file : String) -> String {
  if dir == "" {
    file
  } else if dir.has_suffix("/") {
    dir + file
  } else {
    dir + "/" + file
  }
}

///|
/// Parse gen's own args. Finishes purely on help and usage errors;
/// otherwise hands the shell the input path to read and what to do with it.
fn run_gen_views(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("gen")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: gen_views_help, err: "", exit_code: 0, })
  }
  let roots = parsed.positionals
  let name = parsed.str("name")
  let out = parsed.str("out")
  let dry_run = parsed.bool("dry-run")
  let ir = !parsed.bool("no-ir")
  if roots.is_empty() {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "gen requires an input .html file or a directory",
          hint="`tutuca gen path/to/counter.html --name Counter`, or `tutuca gen src/`",
        ),
      ),
    )
  }
  // Both of these name ONE component or ONE output file, so neither survives a
  // batch. Rejected rather than silently applied to the first path: quietly
  // writing every module to the same `--out` file is worse than not starting.
  if roots.length() > 1 && name is Some(_) {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--name names one component, so it cannot be used with \{roots.length()} paths",
          hint="generate that file on its own, or let each file's basename name its component",
        ),
      ),
    )
  }
  if roots.length() > 1 && out is Some(o) && o.has_suffix(".mbt") {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--out '\{o}' is one file, so it cannot take \{roots.length()} paths",
          hint="pass a directory instead, and each file keeps its own module name",
        ),
      ),
    )
  }
  GenViews(opts, roots~, out~, name~, dry_run~, ir~)
}

///|
/// Generate the module from one file's contents — `gen_views_all` for a batch
/// of one, kept because most callers (the playground, the tests) have exactly
/// one file and no project around it.
pub fn gen_views(
  source : String,
  name~ : String,
  input~ : String,
  target~ : String,
  ir~ : Bool,
) -> Result[GenPlan, ErrShape] {
  gen_views_all([{ input, target, name, source, }], ir~)
}

///|
/// Resolve one view path's output module and component name.
pub fn gen_views_target(
  path : String,
  out? : String,
  name? : String,
) -> (String, String) {
  let (dir, stem) = split_path(path)
  let target = match out {
    Some(o) =>
      if o.has_suffix(".mbt") {
        o
      } else {
        join_path(o, "\{stem}_view_gen.mbt")
      }
    None => join_path(dir, "\{stem}_view_gen.mbt")
  }
  (target, name.unwrap_or(@statedef.upper_name(stem)))
}

///|
/// Compile a whole batch into one plan. The only impure parts are reading the
/// sources and writing the plan, both of which the shell does.
///
/// A batch that fails writes NOTHING — not even the files that compiled before
/// the bad one — because a half-generated tree is the one state nobody can
/// reason about. What it does not do is stop at the first failure: every file
/// that failed is named in one run, so fixing a directory takes one build per
/// round of fixes rather than one per broken file.
pub fn gen_views_all(
  files : Array[GenInput],
  ir~ : Bool,
) -> Result[GenPlan, ErrShape] {
  let out : Array[(String, String)] = []
  let diagnostics : Array[String] = []
  // Split everything BEFORE emitting anything: the component table has to be
  // complete or a cross-file reference reads as an absence.
  let split : Array[(GenInput, @viewfile.ViewFile)] = []
  let index = @viewgen.ProgramIndex::new()
  // What did not generate, in the order the files were given. Collected rather
  // than returned on sight: a directory run that stops at the first bad file
  // makes fixing three problems take three builds to even SEE the three.
  let failures : Array[(String, String)] = []
  for f in files {
    let views = @viewgen.split_file(f.source, name=f.name) catch {
      e => {
        failures.push((f.input, @viewgen.GenError::message(e)))
        continue
      }
    }
    index.add(views, f.name)
    split.push((f, views))
  }
  // A file that did not split leaves a HOLE in the component table, and the
  // emit pass below reads that table — so a cross-file reference in a file
  // that did split would read as an absence and report a second problem that
  // is an artefact of the first. Split failures are answered on their own.
  if !failures.is_empty() {
    return Err(batch_error(files.length(), failures))
  }
  let protocol_validation = index.protocol_validation()
  for d in protocol_validation.diagnostics {
    let line = "\{d.code.word()}: \{d.component}: \{d.message}"
    if d.error {
      failures.push((d.component, line))
    } else {
      diagnostics.push(line)
    }
  }
  if !failures.is_empty() {
    return Err(batch_error(files.length(), failures))
  }
  for pair in split {
    let (f, views) = pair
    let file = basename(f.input)
    try {
      for d in view_diagnostics(views, f.name) {
        diagnostics.push(where_prefixed(files, f, d))
      }
      // `hints` is the schema check's advisory half — the findings a `slots~`
      // entry naming a bare `component` slot could legitimately defeat, so they
      // are reported here rather than failing generation.
      let hints : Array[String] = []
      let generated = @viewgen.emit_modules(
        f.name,
        file,
        views,
        include_ir=ir,
        hints~,
        program=index,
      )
      for h in hints {
        diagnostics.push(where_prefixed(files, f, h))
      }
      out.push((f.target, generated.types_source))
      // The compiled tree goes in its own module: it is by far the biggest
      // part of the output and nothing in the types file depends on it, so a
      // component that opts out just never references it.
      if generated.ir_source is Some(ir_src) {
        out.push((gen_views_ir_target(f.target), ir_src))
      }
    } catch {
      e => failures.push((f.input, @viewgen.GenError::message(e)))
    }
  }
  // Atomic, and that half was always right: `out` is discarded whole rather
  // than written in part, because a half-generated tree is the one state
  // nobody can reason about.
  if !failures.is_empty() {
    return Err(batch_error(files.length(), failures))
  }
  Ok({ files: out, diagnostics, })
}

///|
/// One coded error for a batch, however many files failed in it.
///
/// A SINGLE failure keeps the exact shape a single-file run has always had —
/// `[path] message` — because a one-file run already says which file it is on
/// the command line, and prefixing it there would change every existing
/// message.
///
/// Several name themselves in the body instead. `where_` has one slot and
/// `render_error` prints it as a claim about location, so picking one of three
/// failing files to put in it would be a claim about the other two.
fn batch_error(total : Int, failures : Array[(String, String)]) -> ErrShape {
  if failures.length() == 1 {
    let (input, why) = failures[0]
    return err(CODE_VIEW_GEN_FAILED, "\{input}: \{why}", where_=input)
  }
  err(
    CODE_VIEW_GEN_FAILED,
    "\{failures.length()} of \{total} view files failed to generate; nothing was written\n" +
    failures.map(f => "  \{f.0}: \{f.1}").join("\n"),
  )
}

///|
/// Name the file a diagnostic came from, but only when there is more than one
/// — a single-file run already says which file it is on the command line, and
/// prefixing it there would change every existing message.
fn where_prefixed(
  files : Array[GenInput],
  f : GenInput,
  line : String,
) -> String {
  if files.length() > 1 {
    "\{f.input}: \{line}"
  } else {
    line
  }
}

///|
/// "…/counter_view_gen.mbt" -> "…/counter_view_ir_gen.mbt"
///
/// Public because the shell reports which input each written file came from,
/// and a batch has more than one input to attribute them to.
pub fn gen_views_ir_target(target : String) -> String {
  if target.has_suffix("_gen.mbt") {
    target[:target.length() - 8].to_owned() + "_ir_gen.mbt"
  } else if target.has_suffix(".mbt") {
    target[:target.length() - 4].to_owned() + "_ir.mbt"
  } else {
    target + "_ir.mbt"
  }
}

///|
/// "a/b/counter.html" -> "counter.html" (what the generated header cites).
fn basename(path : String) -> String {
  let chars = path.to_array()
  let mut slash = -1
  for i, c in chars {
    if c == '/' {
      slash = i
    }
  }
  path[slash + 1:].to_owned()
}

///|
/// The line the shell prints after writing.
pub fn gen_views_success(target : String, input : String) -> String {
  "generated \{target} from \{input}\n"
}
