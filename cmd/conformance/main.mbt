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
/// Two files come out: the `.tutu` (which `gen` then compiles) and a
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
  let (tutu, table) = project(cases)
  @fs.write_string_to_file(out_dir + "/corpus.tutu", tutu)
  @fs.write_string_to_file(out_dir + "/table_gen.mbt", table)
  println("conformance: \{cases.length()} case(s) -> \{out_dir}/corpus.tutu")
}

///|
/// Project the cases into the view file the MoonBit backend is compiled from.
///
/// One decision here matters: **the schema is GENERATED from the cases**
/// rather than taken from any of them. Six cases declare `intent saveDraft`
/// with six different bodies, because that is the point of them, and one
/// component answers one name once. So every handler is renamed to `case<i>`
/// and the schema follows the rename — one variant case per projected handler,
/// typed from the values the case dispatches.
///
/// A consequence worth stating: the projection emits **no view call sites**.
/// A generated schema declares every argument type outright, so a template
/// here would answer a question the schema already answered — and for an
/// `intent` it would be wrong, since a view raises messages and never intents.
fn project(cases : Array[@corpus.Case]) -> (String, String) {
  let decls : Array[@tscript.Decl] = []
  let arms = StringBuilder()
  let recv_cases : Array[String] = []
  let intent_cases : Array[String] = []
  let shared : Map[String, String] = Map([])
  let mut skipped = 0
  for i, c in cases {
    let name = "case\{i}"
    let parsed = @tscript.parse_script(c.script) catch {
      _ => {
        skipped = skipped + 1
        continue
      }
    }
    guard parsed.get(parsed.length() - 1) is Some(d) else {
      skipped = skipped + 1
      continue
    }
    // The auxiliary declarations — a `pred` a contract names — travel with the
    // case and are shared, exactly as they are above.
    let aux : Array[@tscript.Decl] = []
    let mut clash = false
    for k in 0..<(parsed.length() - 1) {
      let a = parsed[k]
      let src = a.to_source()
      match shared.get(a.name) {
        Some(prev) => if prev != src { clash = true }
        None => {
          shared[a.name] = src
          aux.push(a)
        }
      }
    }
    if clash {
      skipped = skipped + 1
      continue
    }
    for a in aux {
      decls.push(a)
    }
    decls.push({ ..d, name, doc: "case \{i}: \{c.name}", })
    // The schema case, named after the rename and typed from the dispatch.
    let variant = name +
      (if c.args.is_empty() {
        ""
      } else {
        "(" + c.args.map(a => @corpus.payload_ty(a)).join(", ") + ")"
      })
    match c.bucket {
      BReceive => recv_cases.push(variant)
      BIntent => intent_cases.push(variant)
    }
    // The name the DRIVER dispatches, which is the renamed one only when the
    // case is about the declaration it renamed. A case whose whole point is a
    // name no arm answers dispatches its own, and renaming that would be the
    // projection quietly answering it.
    arms.write_string(
      "    \{i} => Some(\{@statedef.quote(if c.handler == d.name { name } else { c.handler })})\n",
    )
  }
  if skipped > 0 {
    println("conformance: \{skipped} v2 case(s) could not be projected")
  }
  // The state half is the corpus's own; the message halves are generated.
  let state = match cases.get(0) {
    Some(c) => {
      // Everything but the message variants, which are generated below.
      let keep : Array[String] = []
      let mut skipping_handle = false
      for line in c.schema.split("\n") {
        let l = line.to_owned()
        if l.has_prefix("handle C {") {
          skipping_handle = true
          continue
        }
        if skipping_handle {
          if l == "}" {
            skipping_handle = false
          }
          continue
        }
        keep.push(l)
      }
      keep.join("\n").replace(old="state C {", new="state \{COMP} {")
    }
    None => "state \{COMP} {}"
  }
  let schema = state +
    "\nhandle \{COMP} {\n" +
    "  message { " +
    recv_cases.join(", ") +
    " }" +
    (if intent_cases.is_empty() {
      ""
    } else {
      "\n  intent { " + intent_cases.join(", ") + " }"
    }) +
    "\n}"
  // The corpus SPECIFIES the block language — that is what a `@tscript.Decl`
  // is a parse of — and the file `gen` reads is a `.tutu` like every other
  // view file in the repo. So the schema is read once with the block parser
  // and both halves are written straight out as shrubbery: no `.html` in
  // between, and no converter to keep in step with two notations.
  let defs = @statedef.parse_state(schema, name=COMP) catch {
    e =>
      abort(
        "conformance: the projected schema does not parse: " +
        @statedef.DefError::message(e),
      )
  }
  let def = match defs {
    [d, ..] => d
    [] => abort("conformance: the projected schema declares no component")
  }
  let spec = StringBuilder()
  // The named types first: a `struct Label` the schema declares is a
  // declaration of the section, beside the component that names it.
  for t in def.types {
    @totutu.print_user_ty(t, spec) catch {
      @totutu.NoSpelling(what~, help~) =>
        abort(
          "conformance: a declared type does not spell: " +
          what +
          " — " +
          help,
        )
    }
    spec.write_string("\n")
  }
  @totutu.print_spec(def, root=true, names=Map([]), spec) catch {
    @totutu.NoSpelling(what~, help~) =>
      abort("conformance: the schema does not spell: " + what + " — " + help)
  }
  let logic = StringBuilder()
  @totutu.print_logic(COMP, decls, Some(def), logic) catch {
    @totutu.NoSpelling(what~, help~) =>
      abort("conformance: a case does not spell: " + what + " — " + help)
  }
  let tutu = "// GENERATED by `cmd/dev -- gen-conformance` from tscript/conformance.\n" +
    "// DO NOT EDIT: add a case to `cases()` and regenerate.\n" +
    "//\n" +
    "// The v2 half of the corpus, in its own component and its own file.\n" +
    "//\n" +
    "// The message variants are GENERATED from the cases rather than copied\n" +
    "// from the corpus's own schema: six cases declare `intent saveDraft` with\n" +
    "// six different bodies, and one component answers one name once.\n" +
    "\nspec:\n" +
    spec.to_string() +
    "\nlogic:\n" +
    logic.to_string() +
    "\nview:\n  \{COMP}:\n    @div{@(it.name)}\n"
  let table = "// GENERATED by `cmd/dev -- gen-conformance` — DO NOT EDIT.\n" +
    "//\n" +
    "// The v2 corpus is a list and the emitted arms are named; this is what\n" +
    "// lines the two up. Every handler is renamed to `case<i>` and the schema\n" +
    "// follows the rename — except where a case dispatches a name it did not\n" +
    "// declare, which is the whole point of one of them.\n" +
    "\n" +
    "///|\n" +
    "/// The name v2 case `i` was DISPATCHED under, or None when it was not\n" +
    "/// projected.\n" +
    "pub fn v2_case_name(i : Int) -> String? {\n" +
    "  match i {\n" +
    arms.to_string() +
    "    _ => None\n" +
    "  }\n" +
    "}\n"
  (tutu, table)
}
