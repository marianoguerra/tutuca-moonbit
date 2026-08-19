// `tutuca migrate` — rewrite v1 sources to v2.
//
// Worth building rather than doing by hand because the work is large,
// mechanical and repeated: this repository, the examples, the site, and every
// downstream project runs the same edits.
//
// THE RULE THIS IS ORGANIZED AROUND. A codemod that is 95% right on 500 sites
// leaves 25 broken ones in a diff nobody reads. So a file this cannot handle
// COMPLETELY is refused whole, with the reason, and left exactly as it was —
// never half-edited. `refused` is not a failure list, it is the work list.
//
// Three kinds of answer, and the difference matters:
//
//   `files`    rewritten, and the rewrite is deterministic and complete.
//   `reports`  rewritten, AND something a human should look at — a behaviour
//              that v2 changes, which the tool cannot decide for anyone.
//   `refused`  not rewritten. The file needs a decision the tool cannot make.
//
// Pure, like the rest of `cli/`: source text in, rewritten text out. The shell
// reads and writes.

///|
let migrate_help : String =
  #|tutuca migrate <path...> [--dry-run]
  #|
  #|  Rewrite v1 sources to v2. `.html` files move the block language, the
  #|  state block and the `@on` argument slots; `.mbt` files move the dispatch
  #|  arms and the ctx calls.
  #|
  #|  A file this cannot handle COMPLETELY is refused whole and left exactly as
  #|  it was — never half-edited. A codemod that is 95% right on 500 sites
  #|  leaves 25 broken ones in a diff nobody reads, so the refusals are the
  #|  point: they are the work list, not a failure list.
  #|
  #|  Three answers, and the difference matters:
  #|    rewritten   deterministic and complete; nothing to read.
  #|    reported    rewritten, AND something v2 changes that only a human can
  #|                decide — a `ctx.send` naming a generated mutator did
  #|                nothing in v1 and mutates in v2.
  #|    refused     not rewritten. A `response` arm becomes two `receive` arms
  #|                and the body has to be split between them.
  #|
  #|  --dry-run  print what would change instead of writing it.
  #|

///|
/// `tutuca migrate <path>…` — the flags, and nothing else.
///
/// No default root. `gen-views` and the CSS commands default to `.` because
/// running them over a whole project is the ordinary case; running a CODEMOD
/// over a whole project without saying so is not, and a person who meant one
/// file should not get all of them for a missing argument.
fn run_migrate(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("migrate")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: migrate_help, err: "", exit_code: 0 })
  }
  if parsed.positionals.length() == 0 {
    return Done(
      error_emit(opts, {
        code: "missing-path",
        message: "migrate needs at least one path",
        suggestion: None,
        hint: Some(
          "a codemod over a whole project is not something to get from a missing argument — name the files or the directory",
        ),
        where_: Some("tutuca migrate"),
        exit_code: 2,
      }),
    )
  }
  Migrate(opts, roots=parsed.positionals, dry_run=parsed.bool("dry-run"))
}

///|
/// What `tutuca migrate` decided about one run.
pub(all) struct MigratePlan {
  /// (path, new contents) for every file that was rewritten completely.
  files : Array[(String, String)]
  /// Rewritten, but a human should read the result.
  reports : Array[String]
  /// Not rewritten, and why.
  refused : Array[String]
} derive(Debug, Eq)

///|
/// Migrate one file. `path` decides which half runs; the contents decide
/// everything else.
pub fn migrate_source(path : String, source : String) -> MigratePlan {
  // A GENERATED file is never edited, here or anywhere: `AGENTS.md` is
  // explicit about it, and the reason applies exactly to a codemod — an edit
  // here survives until the next `gen-views` and then silently does not. The
  // SOURCE moves and the generator re-runs.
  if path.has_suffix("_gen.mbt") {
    return { files: [], reports: [], refused: [] }
  }
  if path.has_suffix(".mbt") {
    migrate_mbt(path, source)
  } else if path.has_suffix(".html") {
    migrate_html(path, source)
  } else {
    { files: [], reports: [], refused: [] }
  }
}

// ---------------------------------------------------------------------------
// .html — the block language, the state block, and the views

///|
/// One replacement in the original text, as an absolute byte range.
///
/// Applied back-to-front so an earlier splice cannot move a later one's
/// offsets — which is the whole reason this is a list of ranges rather than a
/// string being rebuilt as it goes.
priv struct Splice {
  start : Int
  end_ : Int
  text : String
}

///|
fn apply_splices(source : String, splices : Array[Splice]) -> String {
  let ordered = splices.copy()
  ordered.sort_by((a, b) => b.start - a.start)
  let mut out = source
  for s in ordered {
    out = out[0:s.start].to_owned() + s.text + out[s.end_:].to_owned()
  }
  out
}

///|
fn migrate_html(path : String, source : String) -> MigratePlan {
  let reports : Array[String] = []
  let refused : Array[String] = []
  let splices : Array[Splice] = []
  let file = @viewfile.split_file(source) catch {
    e =>
      return {
        files: [],
        reports: [],
        refused: [path + ": does not split — " + e.message()],
      }
  }

  // -- the block language ---------------------------------------------------
  //
  // Through the PARSER and the PRINTER rather than through the text. The
  // grammar is pinned by parse-print-parse (`tscript/script_test.mbt`), which
  // is exactly the property a rewrite needs: what comes out is what the parser
  // accepts, not what a substitution happened to produce.
  for sb in file.scripts {
    let decls = @tscript.parse_script(sb.block.text) catch {
      e =>
        return {
          files: [],
          reports: [],
          refused: [path + ": a script block does not parse — " + e.message()],
        }
    }
    // A `response` arm becomes TWO `receive` arms and the body has to be split
    // between them — which value belongs to the ok arm and which to the error
    // arm is a reading of the code, not a transformation of it.
    for d in decls {
      if d.kind is DResponse {
        refused.push(
          path +
          ": `response " +
          d.name +
          "` becomes two `receive` arms (" +
          d.name +
          "Ok, " +
          d.name +
          "Error) and the body has to be split between them — a human decides which half is which",
        )
      }
    }
    if !refused.is_empty() {
      return { files: [], reports: [], refused }
    }
    let moved = decls.map(d => migrate_decl(d))
    // The printer emits at column 0, and the block was indented. Re-applying
    // the ORIGINAL indent is not cosmetics: a codemod that reindents every
    // script block turns a two-word change into a diff nobody reads, which is
    // the same failure the refusals exist to avoid, one line at a time.
    let indent = block_indent(sb.block.text)
    let body = moved.map(d => reindent(d.to_source(), indent)).join("\n\n")
    // ...and the block's own TAIL, which is whatever sat between its last
    // newline and the `</script>`. Usually nothing; appending the declaration
    // indent instead would move the closing tag, which is a diff about the
    // tool rather than about the code.
    splices.push({
      start: sb.block.offset,
      end_: sb.block.offset + sb.block.text.length(),
      text: "\n" + body + "\n" + block_tail(sb.block.text),
    })
  }

  // -- the state block ------------------------------------------------------
  //
  // Textually, on the DECLARATION KEYWORD only, because `statedef` has a
  // parser and no printer — and inventing one to rewrite two words would be a
  // second spelling of the schema that has to be kept in step forever.
  //
  // Bounded by where a keyword can appear: the first word of a declaration, at
  // the start of a line modulo indentation. A `bubble` inside a doc comment or
  // a type name is not at that position.
  for st in state_block_ranges(source) {
    let body = source[st.0:st.1].to_owned()
    let (text, bad) = migrate_state_text(body)
    for b in bad {
      refused.push(path + ": " + b)
    }
    if text != body {
      splices.push({ start: st.0, end_: st.1, text })
    }
  }
  if !refused.is_empty() {
    return { files: [], reports: [], refused }
  }

  // -- the views ------------------------------------------------------------
  //
  // Every event accessor in an `@on` argument slot gains `e.`. Bounded to the
  // attribute VALUE, and within it to the argument tokens — the handler name
  // is the first token and stays bare, which is the one unprefixed name v2
  // keeps.
  let (view_splices, view_reports) = migrate_on_attrs(source, path)
  for s in view_splices {
    splices.push(s)
  }
  for r in view_reports {
    reports.push(r)
  }
  let out = apply_splices(source, splices)
  if out == source {
    { files: [], reports, refused }
  } else {
    { files: [(path, out)], reports, refused }
  }
}

///|
/// The indent the block's own declarations were written at.
///
/// The first non-blank line's leading spaces. A block whose lines disagree has
/// no single answer, and the first one is the one an author sees.
fn block_indent(text : String) -> String {
  for raw in text.split("\n") {
    let line = raw.to_owned()
    let trimmed = line.trim_start(chars=" ").to_owned()
    if !trimmed.is_empty() {
      return line[0:line.length() - trimmed.length()].to_owned()
    }
  }
  ""
}

///|
/// Whatever the block's text held after its last newline.
fn block_tail(text : String) -> String {
  match text.rev_find("\n") {
    Some(i) => text[i + 1:].to_owned()
    None => ""
  }
}

///|
/// Every line of `src` shifted right by `indent`, leaving blank lines blank.
fn reindent(src : String, indent : String) -> String {
  if indent == "" {
    return src
  }
  let out : Array[String] = []
  for raw in src.split("\n") {
    let line = raw.to_owned()
    out.push(if line.is_empty() { line } else { indent + line })
  }
  out.join("\n")
}

///|
/// One declaration, moved to v2.
///
/// `on` and `receive` merge; `bubble` becomes `intent`. The BODY moves too: a
/// `bubble` effect becomes `intent dyn` and a `request` becomes `intent lex`,
/// which is the same statement the design makes — the route says which scope
/// answers, where v1's verb said it.
fn migrate_decl(d : @tscript.Decl) -> @tscript.Decl {
  let kind : @tscript.DeclKind = match d.kind {
    DOn => DReceive
    DBubble => DIntent
    other => other
  }
  { ..d, kind, body: migrate_body(d.body) }
}

///|
fn migrate_body(b : @tscript.Body) -> @tscript.Body {
  match b {
    Value(_) => b
    Stmts(ss) => Stmts(ss.map(s => migrate_stmt(s)))
  }
}

///|
fn migrate_stmt(s : @tscript.Stmt) -> @tscript.Stmt {
  match s {
    SEffect(name~, args~, route=_, span~) =>
      match name {
        // v1's two routed verbs, each becoming the one channel plus the leg it
        // always walked.
        "bubble" => SEffect(name="intent", args~, route=[Dyn], span~)
        "request" => SEffect(name="intent", args~, route=[Lex], span~)
        _ => s
      }
    // A branch's arms are statements too, and a `bubble` inside an `if` is as
    // much a bubble as one at the top.
    SIf(cond~, then_~, else_~, span~) =>
      SIf(
        cond~,
        then_=then_.map(x => migrate_stmt(x)),
        else_=else_.map(x => migrate_stmt(x)),
        span~,
      )
    _ => s
  }
}

///|
/// The byte range of each `<script type="tutuca/state">` body.
///
/// Found by scanning rather than taken from `ViewFile`, which parses the block
/// into a `StateDef` and keeps no raw text for it. A rewrite needs the text:
/// `statedef` has a parser and no printer, and inventing one to move two words
/// would be a second spelling of the schema to keep in step forever.
fn state_block_ranges(source : String) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let open_ = "<script type=\"tutuca/state\">"
  let close = "</script>"
  let mut from = 0
  for ;; {
    guard source[from:].to_owned().find(open_) is Some(rel) else { break }
    let body = from + rel + open_.length()
    guard source[body:].to_owned().find(close) is Some(endrel) else { break }
    out.push((body, body + endrel))
    from = body + endrel + close.length()
  }
  out
}

///|
/// The state block's keywords, and what cannot be moved.
///
/// Answers the rewritten text and the refusals. `bubble Comp {` becomes
/// `intent Comp {`; a `response` variant is refused, because its cases become
/// `receive` cases with DERIVED names (`<name>Ok`, `<name>Error`) and deciding
/// which of the two a payload belongs to is a reading of the code.
fn migrate_state_text(text : String) -> (String, Array[String]) {
  let bad : Array[String] = []
  let out : Array[String] = []
  for raw in text.split("\n") {
    let line = raw.to_owned()
    let trimmed = line.trim_start(chars=" ").to_owned()
    if trimmed.has_prefix("response ") || trimmed.has_prefix("response\t") {
      bad.push(
        "the state block declares a `response` variant. Its cases become `receive` cases named `<name>Ok` and `<name>Error`, and which payload belongs to which is a reading of the code",
      )
      out.push(line)
    } else if trimmed.has_prefix("bubble ") || trimmed.has_prefix("bubble\t") {
      let indent = line[0:line.length() - trimmed.length()].to_owned()
      out.push(indent + "intent" + trimmed["bubble".length():].to_owned())
    } else {
      out.push(line)
    }
  }
  (out.join("\n"), bad)
}

///|
/// Every `@on.<event>="…"` attribute value, with its argument accessors
/// prefixed.
///
/// A hand scan rather than the view parser, and the reason is what a rewrite
/// needs: `@anode` gives a compiled TREE, and printing one back is a different
/// document — attribute order, whitespace and comments are all the author's.
/// The scan touches the argument tokens of one attribute value and nothing
/// else, so everything it does not understand it leaves alone.
fn migrate_on_attrs(
  source : String,
  path : String,
) -> (Array[Splice], Array[String]) {
  let splices : Array[Splice] = []
  let reports : Array[String] = []
  let chars = source.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    // `@on.` — the only attribute whose arguments are event reads.
    if i + 4 <= n &&
      chars[i] == '@' &&
      chars[i + 1] == 'o' &&
      chars[i + 2] == 'n' &&
      chars[i + 3] == '.' {
      // Find the `="` that opens the value, and the `"` that closes it. A
      // value containing a quote is not something this rewrites.
      let mut j = i + 4
      while j < n && chars[j] != '=' && chars[j] != '>' && chars[j] != ' ' {
        j = j + 1
      }
      if j < n && chars[j] == '=' && j + 1 < n && chars[j + 1] == '"' {
        let vstart = j + 2
        let mut k = vstart
        while k < n && chars[k] != '"' {
          k = k + 1
        }
        if k < n {
          let value = source[vstart:k].to_owned()
          let (rewritten, note) = migrate_on_value(value)
          if rewritten != value {
            splices.push({ start: vstart, end_: k, text: rewritten })
          }
          match note {
            Some(msg) =>
              reports.push(path + ": `@on…=\"" + value + "\"` — " + msg)
            None => ()
          }
          i = k + 1
          continue
        }
      }
    }
    i = i + 1
  }
  (splices, reports)
}

///|
/// One `@on` attribute value: the handler name, then its arguments.
///
/// The first token is the message name and stays bare — that is the one
/// unprefixed name v2 keeps. Every argument that is a known accessor gains
/// `e.`. An argument that is a bare name and NOT an accessor is left alone and
/// REPORTED: in v1 it read as `Null` at run time, so it is a latent bug this
/// rewrite surfaces rather than a spelling it can fix.
fn migrate_on_value(value : String) -> (String, String?) {
  let tokens = @tscript.tokenize(value)
  if tokens.length() <= 1 {
    return (value, None)
  }
  let out : Array[Splice] = []
  let mut note : String? = None
  for idx in 1..<tokens.length() {
    let t = tokens[idx]
    if t.text.is_empty() {
      continue
    }
    guard t.text.get_char(0) is Some(c0) else { continue }
    // Already prefixed, a literal, or a bind / field / dyn / method read.
    if !(c0 is ('a'..='z')) {
      continue
    }
    if t.text == "true" || t.text == "false" {
      continue
    }
    if t.text.has_prefix("e.") {
      continue
    }
    if @eventpath.event_accessors.contains(t.text) {
      out.push({ start: t.span.start, end_: t.span.end_, text: "e." + t.text })
    } else {
      note = Some(
        "`" +
        t.text +
        "` is a bare name in an argument slot and is not an event accessor. In v1 it read as Null at run time; write `.field`, `@bind` or `e.<path>` for what it meant",
      )
    }
  }
  (apply_splices(value, out), note)
}

// ---------------------------------------------------------------------------
// .mbt — the update arms and the ctx calls

///|
/// `old` -> `new`, but only where `old` starts a TOKEN.
///
/// The character before has to be one an identifier cannot continue with.
/// `Input(` is a substring of `OnInput(` — a generated `<T>Msg` variant for an
/// `@on.input` handler — and a plain substitution turned that into
/// `OnReceive(`, which is a name nothing declares.
fn replace_token(source : String, old : String, new : String) -> String {
  fn ident_char(c : Char) -> Bool {
    c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')
  }

  // Entirely over the CHAR array, never mixing it with string slicing. A
  // `String` is indexed by UTF-16 code unit and `to_array()` gives characters,
  // and the two agree only while the text is ASCII — which the comments in
  // this repository are not. Slicing by a char index panicked on the first
  // em-dash.
  let out = StringBuilder::new()
  let chars = source.to_array()
  let needle = old.to_array()
  let n = chars.length()
  let m = needle.length()
  let mut i = 0
  while i < n {
    let mut hit = i + m <= n && (i == 0 || !ident_char(chars[i - 1]))
    if hit {
      for k in 0..<m {
        if chars[i + k] != needle[k] {
          hit = false
          break
        }
      }
    }
    if hit {
      out.write_string(new)
      i = i + m
    } else {
      out.write_char(chars[i])
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// Every `ctx.bubble(…)` call, with the `dyn` route appended.
///
/// A bubble is an intent whose route is the dynamic scope, which is the design
/// read backwards: v1's verb said which scope, and v2's route does. So the
/// rewrite is the same call with the leg made explicit.
///
/// The closing paren is found by MATCHING, not by scanning to the next `)`: an
/// argument list holds calls of its own, and `ctx.bubble("x", [f(1)])` has two
/// of them. Unbalanced parens answer `Err`, and the caller refuses the file.
fn add_dyn_route(source : String) -> Result[String, String] {
  let marker = "ctx.bubble("
  let mut out = source
  let mut from = 0
  for ;; {
    guard out[from:].to_owned().find(marker) is Some(rel) else { break }
    let open_ = from + rel + marker.length()
    let chars = out.to_array()
    let mut depth = 1
    let mut i = open_
    while i < chars.length() && depth > 0 {
      if chars[i] == '(' {
        depth = depth + 1
      } else if chars[i] == ')' {
        depth = depth - 1
      }
      i = i + 1
    }
    if depth != 0 {
      return Err(
        "a `ctx.bubble(` call's parentheses do not balance, so the route cannot be placed — left as it was",
      )
    }
    let close = i - 1
    out = out[0:from + rel].to_owned() +
      "ctx.intent(" +
      out[open_:close].to_owned() +
      ", @tutuca.IntentOpts::new(route=[Dyn]))" +
      out[close + 1:].to_owned()
    from = from + rel + "ctx.intent(".length()
  }
  Ok(out)
}

///|
/// Migrate a MoonBit source file.
///
/// Textual, because there is no MoonBit parser here — which is exactly why the
/// refusals matter more on this side than on the other. Every rewrite below is
/// a whole token with a `(` or a boundary after it, so none of them can match
/// inside a longer name.
fn migrate_mbt(path : String, source : String) -> MigratePlan {
  let reports : Array[String] = []
  let refused : Array[String] = []

  // A `Response(name, [res, err])` arm becomes two arms and the body has to be
  // split. Refused whole rather than rewritten, per the rule at the top.
  if source.contains("Response(") {
    refused.push(
      path +
      ": a `Response(…)` arm becomes two `Receive` arms (`<name>Ok`, `<name>Error`) and the body has to be split between them — a human decides which half is which",
    )
  }
  // `RequestFn` is NOT renamed, and that is a correction rather than a gap.
  //
  // Renaming it compiles the annotation and breaks the body: an `IntentFn`
  // takes `(IntentCall, (IntentAnswer) -> Unit)` where a `RequestFn` takes
  // `(args, respond)`, so the rewrite would leave a type error — a half-edit,
  // which is the one thing this must not do. A signature change is not a
  // rename, and task 19 found that by running it.
  if source.contains("RequestFn") {
    refused.push(
      path +
      ": `RequestFn` becomes `IntentFn`, which is a SIGNATURE change and not a rename — it takes an `IntentCall` (carrying `from`, the sender's path) and answers `Ok` / `Failed` / `Pass` where a `RequestFn` had to answer. Rewrite each handler by hand",
    )
  }
  // `ctx.request` carries opts whose `on_res_name` has no v2 field, so a
  // mechanical rewrite could silently drop a routing decision.
  if source.contains("on_res_name") {
    refused.push(
      path +
      ": `on_res_name` names the combined `[res, err]` arm, which v2 removed. Split it into `on_ok_name` and `on_error_name` first",
    )
  }
  if !refused.is_empty() {
    return { files: [], reports: [], refused }
  }
  let mut out = source
  // The dispatch arms. `Input(` and `Bubble(` are constructor applications, so
  // the paren is part of the match and nothing longer can contain them.
  // `ctx.bubble(…)` FIRST, so the `.bubble(ctx)` rule below cannot see one.
  match add_dyn_route(out) {
    Ok(next) => out = next
    Err(why) => {
      refused.push(path + ": " + why)
      return { files: [], reports: [], refused }
    }
  }
  // The dispatch arms, as WHOLE tokens.
  //
  // `replace_all` and not `replace`, because `String::replace` moves ONE
  // occurrence and a codemod built on it renames the first arm in a file and
  // leaves the rest. And token-wise, because `Input(` is a substring of
  // `OnInput(` — a generated `<T>Msg` variant for an `@on.input` handler — and
  // a plain substitution turned it into `OnReceive(`. Task 19 found both on
  // its first two runs, which is what running a codemod on real code is for.
  out = replace_token(out, "Input(", "Receive(")
  out = replace_token(out, "Bubble(", "Intent(")
  // The GENERATED enums, which viewgen renamed with the schema: `<T>Bubble`
  // became `<T>Intent`, and `bubble(ctx)` became `dispatch(ctx)` — the raiser
  // that carries a route where the old one carried only a direction.
  //
  // `Bubble::` rather than the bare word, so a hand-written type that merely
  // ends in it is untouched: a generated name is always used qualified.
  out = out.replace_all(old="Bubble::", new="Intent::")
  // Every remaining `.bubble(` is a generated raiser, because `ctx.bubble(`
  // was rewritten above. Not `.bubble(ctx)` with the argument attached: `moon
  // fmt` wraps a long call across lines, and a rule that required the argument
  // on the same line missed exactly the sites a formatter had touched.
  //
  // The one shape that is NOT a raiser is `ctx.at()…bubble(…)`, the path
  // builder's own method — whose v2 spelling is `.intent(…)` and not
  // `.dispatch(…)`. A file holding both is refused rather than guessed at.
  if out.contains(".bubble(") {
    if out.contains(".at()") {
      refused.push(
        path +
        ": this file has both a generated raiser's `.bubble(` and a `ctx.at()` path builder, whose v2 spelling is `.intent(…)` rather than `.dispatch(…)`. Which is which needs a reader",
      )
      return { files: [], reports: [], refused }
    }
    out = out.replace_all(old=".bubble(", new=".dispatch(")
  }
  // The two routed calls, each becoming the one channel plus its leg. The
  // opts argument is appended rather than rewritten, because v1's call carries
  // none for `bubble` and a `RequestOpts` for `request` — and a `RequestOpts`
  // is not an `IntentOpts`, so that one is left for the human.
  if out.contains("ctx.request(") {
    reports.push(
      path +
      ": `ctx.request(name, args, RequestOpts::new(…))` becomes `ctx.intent(name, args, IntentOpts::new(route=[Lex], …))`. The opts do not map one for one — `on_res_name` is gone — so this one is left as it is",
    )
  }
  // A `ctx.send` whose name is a generated mutator changes behaviour: v1
  // dropped it and v2 mutates. The tool cannot tell which names are mutators
  // without the schema, so it reports every `ctx.send` in a file that has one
  // rather than guessing.
  if source.contains("ctx.send(") || source.contains("send_at_path(") {
    reports.push(
      path +
      ": this file sends addressed messages. A `ctx.send` naming a GENERATED MUTATOR did nothing in v1 and mutates in v2 — check each name against the component's fields",
    )
  }
  if out == source {
    { files: [], reports, refused }
  } else {
    { files: [(path, out)], reports, refused }
  }
}
