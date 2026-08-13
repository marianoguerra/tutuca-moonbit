///|
/// Project the conformance corpus into a view file the MoonBit backend
/// compiles.
///
/// One component holds every case, because they all share one schema and the
/// only thing that varies is the body. The `@on` declarations are RENAMED to
/// `case<i>` — the corpus reuses `go` for most of them, and one component
/// answers one name once. A `receive` case keeps its name, because the schema
/// is what declares those and there is exactly one.
///
/// Two files come out: the `.html` (which `gen-views` then compiles) and a
/// table pairing each case index with the NAME it was emitted under, which is
/// the one thing a test cannot work out for itself once the rename has
/// happened.
extern "C" fn exit(code : Int) = "exit"

///|
/// The generated component's name.
const COMP : String = "Corpus"

///|
fn main raise {
  let args = @env.args()
  let mut out_dir = "tscript/conformance/mbt"
  let mut index = 1
  while index < args.length() {
    match args[index] {
      "-o" | "--out" => {
        index = index + 1
        if index >= args.length() {
          println("error: --out requires a value")
          exit(2)
        }
        out_dir = args[index]
      }
      "-h" | "--help" => {
        println("usage: conformance [--out <dir>]")
        return
      }
      other => {
        println("error: unknown argument '\{other}'")
        exit(2)
      }
    }
    index = index + 1
  }
  let cases = @corpus.cases()
  let (html, table) = project(cases, @corpus.value_cases())
  @fs.write_string_to_file(out_dir + "/corpus.html", html)
  @fs.write_string_to_file(out_dir + "/table_gen.mbt", table)
  println("conformance: \{cases.length()} case(s) -> \{out_dir}/corpus.html")
}

///|
/// The declaration name a case is emitted under.
fn fn_name_of(c : @corpus.Case, i : Int) -> String {
  match c.bucket {
    BInput => "case\{i}"
    // Not renamed: a receive/bubble/response name has to be one the SCHEMA
    // declares, and the schema is the corpus's own.
    _ => c.handler
  }
}

///|
/// The `.html` and the index table.
fn project(
  cases : Array[@corpus.Case],
  values : Array[@corpus.ValueCase],
) -> (String, String) {
  let decls = StringBuilder::new()
  let arms = StringBuilder::new()
  let calls = StringBuilder::new()
  /// Auxiliary declarations already written, by name, so two cases can share
  /// one and a third that redefines it is caught rather than emitted twice.
  let shared : Map[String, String] = Map([])
  let mut skipped = 0
  for i, c in cases {
    let name = fn_name_of(c, i)
    // Reparsed and reprinted rather than string-spliced, so the rename goes
    // through the same grammar the checker and both backends read. A case
    // whose script does not parse is the parser's problem and is reported by
    // the interpreter's own run; here it is simply left out, with a count.
    let parsed = @tscript.parse_script(c.script) catch {
      _ => {
        skipped = skipped + 1
        continue
      }
    }
    // The DISPATCHED declaration is the one the case is about; a script may
    // carry others it calls — a `pred`, a `compute`. Those keep their names,
    // since a body referring to one names it, and one component answers a name
    // once: a second case declaring the same name differently cannot share the
    // file and is left out with a count.
    guard parsed.get(parsed.length() - 1) is Some(d) else {
      skipped = skipped + 1
      continue
    }
    let aux : Array[String] = []
    let mut clash = false
    for k in 0..<(parsed.length() - 1) {
      let a = parsed[k]
      let src = a.to_source()
      match shared.get(a.name) {
        Some(prev) => if prev != src { clash = true }
        None => {
          shared[a.name] = src
          aux.push(src)
        }
      }
    }
    if clash {
      skipped = skipped + 1
      continue
    }
    for a in aux {
      decls.write_string(
        "  " +
        a.split("\n").map(l => l.to_owned()).collect().join("\n  ") +
        "\n\n",
      )
    }
    decls.write_string(
      "  " +
      { ..d, name, doc: "case \{i}: \{c.name}" }
      .to_source()
      .split("\n")
      .map(l => l.to_owned())
      .collect()
      .join("\n  ") +
      "\n\n",
    )
    arms.write_string("    \{i} => Some(\{quote(name)})\n")
    // A CALL SITE per case, carrying literals of the shapes the case
    // dispatches. Without one the surface infers nothing and every parameter
    // arrives as a raw value, which the backend refuses to use at a type —
    // so the projection would be testing its own omission rather than the
    // emitter.
    if c.bucket is BInput {
      calls.write_string(
        "  <button @on.click=\{quote(name + args_src(c.args))}>\{name}</button>\n",
      )
    }
  }
  // The value bodies. Renamed the same way and for the same reason, and each
  // given the VIEW SLOT that puts it in its bucket: a `compute` is a method
  // because the block declares it, but a `@when` and an `@enrich-with` are
  // roles the views assign, and a projection with no slots would compile the
  // methods and nothing else — testing its own omission again.
  let value_arms = StringBuilder::new()
  for i, c in values {
    let name = "v\{i}_\{c.callable}"
    let parsed = @tscript.parse_script(c.script) catch {
      _ => {
        skipped = skipped + 1
        continue
      }
    }
    // Every declaration in the case, renamed together: a body that calls a
    // sibling names it, so the pair has to travel and be renamed as one.
    let renamed : Map[String, String] = Map([])
    for d in parsed {
      renamed[d.name] = "v\{i}_\{d.name}"
    }
    let mut clash = false
    for d in parsed {
      let src = rename_calls(d, renamed)
      match shared.get(renamed.get(d.name).unwrap()) {
        Some(prev) => if prev != src { clash = true }
        None => shared[renamed.get(d.name).unwrap()] = src
      }
    }
    if clash {
      skipped = skipped + 1
      continue
    }
    for d in parsed {
      let key = renamed.get(d.name).unwrap()
      decls.write_string(
        "  " +
        shared
        .get(key)
        .unwrap()
        .split("\n")
        .map(l => l.to_owned())
        .collect()
        .join("\n  ") +
        "\n\n",
      )
    }
    match c.role {
      VMethod => ()
      VWhen =>
        calls.write_string(
          "  <ul><li @each=\".items\" @when=\{quote(name)}></li></ul>\n",
        )
      VEnrich =>
        calls.write_string(
          "  <ul><li @each=\".items\" @enrich-with=\{quote(name)}></li></ul>\n",
        )
      VEnrichScope =>
        calls.write_string("  <div @enrich-with=\{quote(name)}></div>\n")
    }
    value_arms.write_string("    \{i} => Some(\{quote(name)})\n")
  }
  if skipped > 0 {
    println("conformance: \{skipped} case(s) could not be projected")
  }
  let html = "<!--\n" +
    "  GENERATED by `cmd/dev -- gen-conformance` from tscript/conformance.\n" +
    "  DO NOT EDIT: add a case to the corpus and regenerate.\n" +
    "\n" +
    "  Every case in one component, because they share one schema and only the\n" +
    "  body varies. The `@on` names are `case<i>` rather than what the corpus\n" +
    "  wrote, since most cases spell theirs `go` and one component answers one\n" +
    "  name once.\n" +
    "-->\n" +
    "<script type=\"tutuca/state\">\n" +
    indent(schema_of(cases)) +
    "\n</script>\n\n" +
    "<script type=\"tutuca/script\">\n" +
    decls.to_string() +
    "</script>\n\n" +
    "<template id=\"\{COMP}\">\n<div>\n  <x text=\".name\"></x>\n" +
    calls.to_string() +
    "</div>\n</template>\n"
  let table = "// GENERATED by `cmd/dev -- gen-conformance` — DO NOT EDIT.\n" +
    "//\n" +
    "// The corpus is a list and the emitted arms are named, and the two only\n" +
    "// line up because this says so: most cases spell their handler `go`, and\n" +
    "// the projection renames each to `case<i>` so one component can answer\n" +
    "// them all.\n" +
    "\n" +
    "///|\n" +
    "/// The name case `i` was emitted under, or None when it was not projected.\n" +
    "pub fn case_name(i : Int) -> String? {\n" +
    "  match i {\n" +
    arms.to_string() +
    "    _ => None\n" +
    "  }\n" +
    "}\n" +
    "\n" +
    "///|\n" +
    "/// The same, for the value cases — which are renamed per case rather than\n" +
    "/// per bucket, since two of them declare the same `matches` differently.\n" +
    "pub fn value_case_name(i : Int) -> String? {\n" +
    "  match i {\n" +
    value_arms.to_string() +
    "    _ => None\n" +
    "  }\n" +
    "}\n"
  (html, table)
}

///|
/// One declaration's source, with every call to a renamed sibling renamed too.
///
/// Through the AST rather than the text. A word-boundary replace over the
/// printed source is nearly right and wrong exactly once: it renamed the
/// STRING `'over'` inside `if over { 'over' }`, because a string literal is
/// made of the same characters a name is.
fn rename_calls(d : @tscript.Decl, renamed : Map[String, String]) -> String {
  let body = match d.body {
    Value(e) => @tscript.Body::Value(rename_expr(e, renamed))
    Stmts(ss) => Stmts(ss.map(st => rename_stmt(st, renamed)))
  }
  { ..d, name: renamed.get(d.name).unwrap(), body }.to_source()
}

///|
fn rename_expr(e : @tscript.Expr, m : Map[String, String]) -> @tscript.Expr {
  fn go(x : @tscript.Expr) -> @tscript.Expr {
    rename_expr(x, m)
  }

  match e {
    EName(name~, span~) => EName(name=m.get(name).unwrap_or(name), span~)
    EApp(name~, args~, span~) =>
      EApp(name=m.get(name).unwrap_or(name), args=args.map(go), span~)
    ETpl(parts~, span~) =>
      ETpl(
        parts=parts.map(p => {
          match p {
            TExpr(inner) => TExpr(go(inner))
            TText(t) => TText(t)
          }
        }),
        span~,
      )
    EUnary(op~, operand~, span~) => EUnary(op~, operand=go(operand), span~)
    EChain(family~, ops~, operands~, span~) =>
      EChain(family~, ops~, operands=operands.map(go), span~)
    EIf(cond~, then_~, else_~, span~) =>
      EIf(cond=go(cond), then_=go(then_), else_=go(else_), span~)
    other => other
  }
}

///|
fn rename_stmt(s : @tscript.Stmt, m : Map[String, String]) -> @tscript.Stmt {
  match s {
    SAssign(place~, op~, value~, span~) =>
      SAssign(place~, op~, value=rename_expr(value, m), span~)
    SMethod(place~, call~, args~, span~) =>
      SMethod(place~, call~, args=args.map(a => rename_expr(a, m)), span~)
    SEffect(name~, args~, span~) =>
      SEffect(name~, args=args.map(a => rename_expr(a, m)), span~)
    // A `new` names a TYPE, and the renaming here is of handler PARAMETERS.
    SNew(..) => s
    SIf(cond~, then_~, else_~, span~) =>
      SIf(
        cond=rename_expr(cond, m),
        then_=then_.map(st => rename_stmt(st, m)),
        else_=else_.map(st => rename_stmt(st, m)),
        span~,
      )
  }
}

///|
/// The shared schema, with the component named so the generated types are.
fn schema_of(cases : Array[@corpus.Case]) -> String {
  guard cases.get(0) is Some(first) else { return "state \{COMP} {}" }
  // The corpus names its component `C`; the generated types read better as
  // `Corpus`, and the name is the only thing that has to change.
  first.schema
  .replace(old="state C {", new="state \{COMP} {")
  .replace(old="receive C {", new="receive \{COMP} {")
}

///|
/// The arguments a case dispatches, as slot-language literals.
///
/// Only the three shapes the value language spells; anything else is left off,
/// and the parameter then arrives raw exactly as it would in a real view.
fn args_src(args : Array[@tutuca.Value]) -> String {
  let out = StringBuilder::new()
  for a in args {
    match a {
      Num(n) =>
        out.write_string(
          if n == n.to_int().to_double() {
            " \{n.to_int()}"
          } else {
            " \{n}"
          },
        )
      Str(s) => out.write_string(" '\{s}'")
      Bool(b) => out.write_string(if b { " true" } else { " false" })
      _ => ()
    }
  }
  out.to_string()
}

///|
fn indent(s : String) -> String {
  s.split("\n").map(l => "  " + l.to_owned()).collect().join("\n")
}

///|
fn quote(s : String) -> String {
  "\"" + s + "\""
}
