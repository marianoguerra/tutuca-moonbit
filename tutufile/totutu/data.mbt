// The `fixtures:` and `tests:` sections: two JSON blocks, printed as
// declarations in the same notation as everything else.

///|
/// One fixture.
pub fn print_fixture(
  f : @statedef.InitState,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let opts = []
  if f.default_ {
    opts.push(" ~default")
  }
  out.write_string("  \{quote(f.name)}\{opts.join("")}:\n")
  if f.doc != "" {
    out.write_string("    ~doc: \{quote(f.doc)}\n")
  }
  if f.view != "" {
    out.write_string("    ~view: \{quote(f.view)}\n")
  }
  if !f.tags.is_empty() {
    let parts = []
    for t in f.tags {
      parts.push(quote(t))
    }
    out.write_string("    ~tags: [\{parts.join(", ")}]\n")
  }
  // `args` is the seed as VALUES; `fields` is the same seed projected into
  // MoonBit source for the generator to write into a `make` call, which is not
  // this notation. The values are what get printed.
  for k, v in f.args {
    out.write_string("    it.\{@names.snake_of(k)} = \{print_value(v)}\n")
  }
  // A fixture arrived at by DOING: the same step language a scene writes, under
  // `~drive:`. It is kept as JSON by the splitter and validated as steps on the
  // way in, so parsing it here reads what was already checked.
  guard f.drive is (Null | Array([])) else {
    let steps = @scenedef.parse_steps(f.drive, "fixture `\{f.name}`") catch {
      _ =>
        raise NoSpelling(
          what="a fixture whose `drive` block does not read as steps (`\{f.name}`)",
          help="fix it in the `.html` file before converting",
        )
    }
    out.write_string("    ~drive:\n")
    for step in steps {
      out.write_string("      \{print_step(step)}\n")
    }
  }
  print_intents(answers_of(f.intents, "fixture `\{f.name}`"), out)
}

///|
/// A fixture's intent answers, which reach here as the JSON the splitter kept.
fn answers_of(
  j : Json,
  where_ : String,
) -> Map[String, @tutuca.IntentAnswer] raise NoSpelling {
  guard j is Object(_) else { return Map([]) }
  @scenedef.parse_answers(j, where_) catch {
    _ =>
      raise NoSpelling(
        what="an intent answer table that does not read as one (\{where_})",
        help="fix it in the `.html` file before converting",
      )
  }
}

///|
/// `~intents:` — one answer per intent the fixture or scene stands in for.
///
/// A statement each, in the same shape as a drive step, because that is what
/// they are: `ok`, `failed` and `pass` are the three answers an intent has,
/// and a name with no answer here is the `<name>_unhandled` path.
fn print_intents(
  answers : Map[String, @tutuca.IntentAnswer],
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !answers.is_empty() else { return }
  out.write_string("    ~intents:\n")
  let names = answers.keys().collect()
  names.sort()
  for name in names {
    match answers.get(name) {
      Some(Ok(v)) =>
        out.write_string("      ok(\{quote(name)}, \{print_value(v)})\n")
      Some(Failed(v)) =>
        out.write_string("      failed(\{quote(name)}, \{print_value(v)})\n")
      Some(Pass) => out.write_string("      pass(\{quote(name)})\n")
      None => ()
    }
  }
}

///|
/// One scene.
pub fn print_scene(
  s : @scenedef.Scene,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  out.write_string("  \{quote(s.name)}:\n")
  if s.component != "" {
    out.write_string("    ~component: \{s.component}\n")
  }
  if s.init != "" {
    out.write_string("    ~init: \{quote(s.init)}\n")
  }
  if !s.args.is_empty() {
    let parts = []
    for k, v in s.args {
      parts.push("\{@names.snake_of(k)}: \{print_value(v)}")
    }
    out.write_string("    ~args: {\{parts.join(", ")}}\n")
  }
  print_intents(s.intents, out)
  for step in s.steps {
    out.write_string("    \{print_step(step)}\n")
  }
}

///|
/// One step, which is a call.
fn print_step(step : @scenedef.Step) -> String raise NoSpelling {
  match step {
    Click(sel~, nth~) => "click(\{quote(sel)}\{step_nth(nth)})"
    Type(sel~, value~, nth~) =>
      "type(\{quote(sel)}, \{quote(value)}\{step_nth(nth)})"
    Key(sel~, key~, value~, nth~) => {
      let v = match value {
        Some(v) => ", \{print_value(v)}"
        None => ""
      }
      "key(\{quote(sel)}, \{quote(key)}\{v}\{step_nth(nth)})"
    }
    Check(sel~, checked~, nth~) =>
      "check(\{quote(sel)}, \{if checked { "true" } else { "false" }}\{step_nth(nth)})"
    Fire(sel~, event~, value~, key~, nth~) => {
      let v = match value {
        Some(v) => ", \{print_value(v)}"
        None => ""
      }
      let k = if key == "" { "" } else { ", ~key: \{quote(key)}" }
      "fire(\{quote(sel)}, \{quote(event)}\{v}\{k}\{step_nth(nth)})"
    }
    Drag(sel~, from~, to~) => "drag(\{quote(sel)}, \{from}, \{to})"
    Send(name~, args~) => {
      // A qualified message is a WIRE name on both halves — the protocol id
      // and its member, dispatched as those exact strings — so a scene that
      // renamed either would send something nothing answers.
      let parts = [quote(@names.rename_member(name))]
      for a in args {
        parts.push(print_value(a))
      }
      "send(\{parts.join(", ")})"
    }
    Read(e) => print_expect(e)
  }
}

///|
fn nth_opt(nth : Int) -> String {
  if nth == 0 {
    ""
  } else {
    " ~nth: \{nth}"
  }
}

///|
/// `~nth:` as a STEP takes, which is an argument of the call.
fn step_nth(nth : Int) -> String {
  if nth == 0 {
    ""
  } else {
    ", ~nth: \{nth}"
  }
}

///|
/// `expect <reader> <subject> == <value>`, or `contains`, or neither.
fn print_expect(e : @scenedef.Expect) -> String raise NoSpelling {
  let subject = match e.reader {
    // The two readers that take no selector at all.
    RState =>
      if e.place.is_empty() {
        "state it"
      } else {
        "state " + place_text(e.place)
      }
    RHtml | RRenders | RRefused | RLog => e.reader.word()
    RAttr | RProp => "\{e.reader.word()}(\{quote(e.sel)}, \{quote(e.name)})"
    _ => "\{e.reader.word()}(\{quote(e.sel)})"
  }
  // `~nth:` trails the whole EXPECTATION rather than sitting in the reader's
  // arguments: it says which of the matched elements to read, not what to read.
  let nth = nth_opt(e.nth)
  match e.want {
    Some(WIs(v)) => "expect \{subject} == \{print_value(v)}\{nth}"
    Some(WContains(s)) => "expect \{subject} contains \{quote(s)}\{nth}"
    // A read with nothing to compare against is a RECORDING: the runner reads
    // it and hands the answer back rather than judging it.
    None => "expect \{subject}\{nth}"
  }
}

///|
/// A dotted place in a `state` expectation.
fn place_text(steps : Array[@tutuca.Step]) -> String raise NoSpelling {
  let out = StringBuilder()
  out.write_string("it")
  for s in steps {
    match s {
      FieldStep(f) => out.write_string("." + @names.snake_of(f))
      SeqAccessStep(seq_field~, key_field~) =>
        out.write_string(
          ".\{@names.snake_of(seq_field)}[it.\{@names.snake_of(key_field)}]",
        )
      // A literal index or key, which is what a scene writes: the step the
      // parser builds for `.labels[1]` and `.by_id["a"]`.
      SeqStep(field~, key~) =>
        out.write_string(".\{@names.snake_of(field)}[\{key_text(key)}]")
      // An `@each`'s own render step: put there by the RENDERER, at the
      // position a loop was rendering. Nothing an author writes.
      EachRenderItStep(..) =>
        raise NoSpelling(
          what="a `state` expectation at a loop's own render step",
          help="a scene addresses a place the file writes; this one came from the renderer",
        )
    }
  }
  out.to_string()
}

///|
/// A literal path key, as a scene writes it.
fn key_text(k : @tutuca.PathKey) -> String {
  match k {
    KInt(i) => i.to_string()
    KStr(s) => quote(s)
  }
}

///|
/// One runtime value, as the literal a `.tutu` file writes.
pub fn print_value(v : @tutuca.Value) -> String raise NoSpelling {
  match v {
    Null => "none"
    Bool(b) => if b { "true" } else { "false" }
    Num(n) => print_num(n)
    Str(s) => quote(s)
    List(xs) => {
      let parts = []
      for x in xs {
        parts.push(print_value(x))
      }
      "[" + parts.join(", ") + "]"
    }
    Map(m) => {
      let parts = []
      for k, x in m {
        parts.push("\{@names.snake_of(k)}: \{print_value(x)}")
      }
      "{" + parts.join(", ") + "}"
    }
    // An `Int`, a `Bin`, an `Instant`, a function or a live instance. None of
    // them is something a fixture or a scene is written with, so none has a
    // literal to print.
    _ =>
      raise NoSpelling(
        what="a value with no literal in the notation",
        help="convert this fixture or scene by hand",
      )
  }
}
