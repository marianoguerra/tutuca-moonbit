// The `fixtures:` and `tests:` sections, read as the JSON their parsers take.
//
// One step language, printed twice: a fixture's `~drive` and a scene's steps
// are the same statements, which is the thing the two JSON blocks could never
// say about each other.

///|
/// A value expression as JSON.
pub fn json_of(ex : @sh.Ex) -> Json raise @sh.ExError {
  match ex {
    @sh.ENum(n) => Json::number(n)
    @sh.EStr(s) => Json::string(s)
    @sh.EBool(b) => Json::boolean(b)
    @sh.ENone => Json::null()
    @sh.EName("true") => Json::boolean(true)
    @sh.EName("false") => Json::boolean(false)
    @sh.EList(xs) => {
      let out = []
      for x in xs {
        out.push(json_of(x))
      }
      Json::array(out)
    }
    @sh.EMap(entries) => {
      let out = Map([])
      for e in entries {
        out[e.0] = json_of(e.1)
      }
      Json::object(out)
    }
    @sh.ECall(@sh.EName(name), args) => {
      // `ok [...]`, `failed "…"` and `pass` are an intent's three answers
      let pos = @sh.positional(args)
      match (name, pos.length()) {
        ("ok", 1) => Json::object({ "ok": json_of(pos[0]) })
        ("failed", 1) => Json::object({ "failed": json_of(pos[0]) })
        _ =>
          raise @sh.ExError(
            message="`\{name}` is not a value",
            help="a value is a number, a string, `true`, `false`, a list or a map",
            span=@report.Span::at(0),
          )
      }
    }
    _ =>
      raise @sh.ExError(
        message="this is not a value a fixture or a scene can carry",
        help="a value is a number, a string, `true`, `false`, a list or a map",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The `fixtures:` section as its JSON object.
pub fn fixtures_json(decls : Array[@tutufile.Decl]) -> Json raise @sh.ExError {
  let out = Map([])
  for d in decls {
    out[d.name] = fixture_json(d)
  }
  Json::object(out)
}

///|
fn fixture_json(decl : @tutufile.Decl) -> Json raise @sh.ExError {
  let env = Map([])
  let value = Map([])
  if decl.options.contains("default") {
    env["default"] = Json::boolean(true)
  }
  match @sh.decl_doc(decl) {
    Some(d) => env["doc"] = Json::string(d)
    None => ()
  }
  for group in @sh.body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    match parts[0].it {
      Kw(name) => {
        guard parts.length() >= 2 && parts[1].it is Block(bgs) else { continue }
        match name {
          "drive" => env["drive"] = steps_json(bgs)
          "intents" => env["intents"] = intents_json(bgs)
          _ => {
            guard bgs.length() == 1 else { continue }
            env[name] = json_of(@sh.read_group(bgs[0]))
          }
        }
      }
      // `it.field = value` — one entry of the state a fixture starts from
      Id("it") => {
        guard @sh.find_op(parts, ["="]) is Some(at) && parts.length() > 2 else {
          continue
        }
        guard parts[2].it is Id(field) else { continue }
        value[field] = json_of(@sh.read_ex(parts[at + 1:]))
      }
      _ => ()
    }
  }
  env["value"] = Json::object(value)
  Json::object(env)
}

///|
/// The `tests:` section as its JSON object.
pub fn scenes_json(decls : Array[@tutufile.Decl]) -> Json raise @sh.ExError {
  let out = Map([])
  for d in decls {
    out[d.name] = scene_json(d)
  }
  Json::object(out)
}

///|
fn scene_json(decl : @tutufile.Decl) -> Json raise @sh.ExError {
  let env = Map([])
  let steps = []
  for group in @sh.body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    match parts[0].it {
      Kw(name) => {
        guard parts.length() >= 2 && parts[1].it is Block(bgs) else {
          if name == "raw" {
            env["raw"] = Json::boolean(true)
          }
          continue
        }
        match name {
          "intents" => env["intents"] = intents_json(bgs)
          "component" => {
            guard bgs.length() == 1 else { continue }
            env["component"] = Json::string(group_name(bgs[0]))
          }
          _ => {
            guard bgs.length() == 1 else { continue }
            env[name] = json_of(@sh.read_group(bgs[0]))
          }
        }
      }
      _ => steps.push(step_json(group))
    }
  }
  env["steps"] = Json::array(steps)
  Json::object(env)
}

///|
/// A bare name written as a value, for the options that name a thing.
fn group_name(group : @ast.Node) -> String {
  match group.it {
    Group(parts) =>
      if parts.length() > 0 {
        @sh.node_text(parts[0])
      } else {
        ""
      }
    _ => @sh.node_text(group)
  }
}

///|
/// The steps of a `~drive` or a scene.
fn steps_json(groups : Array[@ast.Node]) -> Json raise @sh.ExError {
  let out = []
  for g in groups {
    out.push(step_json(g))
  }
  Json::array(out)
}

///|
/// One step: a driving verb, or a reading `expect`.
fn step_json(group : @ast.Node) -> Json raise @sh.ExError {
  guard group.it is Group(parts) && parts.length() > 0 else {
    raise @sh.ExError(
      message="a step is a verb",
      help="write `click(\"button\")`, or `expect text(\"o\") == \"3\"`",
      span=@sh.span_of(group),
    )
  }
  guard parts[0].it is Id(verb) else {
    raise @sh.ExError(
      message="a step is a verb",
      help="write `click(\"button\")`, or `expect text(\"o\") == \"3\"`",
      span=@sh.span_of(parts[0]),
    )
  }
  if verb == "expect" {
    return expect_json(parts, group)
  }
  guard parts.length() >= 2 && parts[1].it is Parens(gs) else {
    raise @sh.ExError(
      message="`\{verb}` is called with what it acts on",
      help="write `\{verb}(\"<selector>\")`",
      span=@sh.span_of(parts[0]),
    )
  }
  let args = @sh.read_args(gs)
  let pos = @sh.positional(args)
  let obj = Map([])
  let arg = fn(i : Int) -> Json raise @sh.ExError { json_of(pos[i]) }
  match verb {
    "click" => obj["click"] = arg(0)
    "type" => {
      obj["type"] = arg(0)
      obj["value"] = arg(1)
    }
    "key" => {
      obj["key"] = arg(0)
      obj["is"] = arg(1)
      // The value the box holds when the key goes down — optional, the way
      // `fire`'s is. Dropping it drove the key with an empty input.
      if pos.length() > 2 {
        obj["value"] = arg(2)
      }
    }
    "check" => {
      obj["check"] = arg(0)
      obj["is"] = arg(1)
    }
    "fire" => {
      obj["fire"] = arg(0)
      obj["event"] = arg(1)
      if pos.length() > 2 {
        obj["value"] = arg(2)
      }
    }
    "drag" => {
      obj["drag"] = arg(0)
      obj["from"] = arg(1)
      obj["to"] = arg(2)
    }
    "send" => {
      obj["send"] = arg(0)
      if pos.length() > 1 {
        let rest = []
        for i in 1..<pos.length() {
          rest.push(json_of(pos[i]))
        }
        obj["args"] = Json::array(rest)
      }
    }
    other =>
      raise @sh.ExError(
        message="`\{other}` is not a step",
        help="the verbs are `click`, `type`, `key`, `check`, `fire`, `drag` and `send`",
        span=@sh.span_of(parts[0]),
      )
  }
  match @sh.kw_arg(args, "nth") {
    Some(n) => obj["nth"] = json_of(n)
    None => ()
  }
  Json::object(obj)
}

///|
/// `expect <reader> <subject> == <value>`, or `contains`, or neither.
fn expect_json(
  parts : Array[@ast.Node],
  group : @ast.Node,
) -> Json raise @sh.ExError {
  guard parts.length() >= 2 && parts[1].it is Id(reader) else {
    raise @sh.ExError(
      message="`expect` names what to read",
      help="write `expect text(\"o\") == \"3\"`",
      span=@sh.span_of(group),
    )
  }
  let obj = Map([("expect", Json::string(reader))])
  let mut i = 2
  // a reader with a subject: `text("o")`, `attr("a", "href")`
  if i < parts.length() && parts[i].it is Parens(gs) {
    let pos = @sh.positional(@sh.read_args(gs))
    if pos.length() > 0 {
      obj["at"] = json_of(pos[0])
    }
    if pos.length() > 1 {
      obj["name"] = json_of(pos[1])
    }
    i = i + 1
  } else if reader == "state" && i < parts.length() && parts[i].it is Id("it") {
    // `expect state it.rows[0].label` — a place, printed as the dotted path
    let stop = comparison_at(parts, i)
    // `expect state it == {…}` names no place: the whole state IS what it
    // compares, and the old notation said that by leaving `at` out.
    let at = place_text(parts[i:stop])
    if at != "" {
      obj["at"] = Json::string(at)
    }
    i = stop
  }
  // A trailing `~nth:` is an option of the EXPECTATION — which of the matched
  // elements to read — rather than part of the value being compared against, so
  // the value stops where it starts.
  let mut stop = parts.length()
  for at, p in parts {
    if at > i && p.it is Kw(_) {
      stop = at
      break
    }
  }
  // the comparison, if there is one; without it the step records instead
  if i < stop {
    match parts[i].it {
      Op("==") => obj["is"] = json_of(@sh.read_ex(parts[i + 1:stop]))
      Id("contains") =>
        obj["contains"] = json_of(@sh.read_ex(parts[i + 1:stop]))
      _ =>
        raise @sh.ExError(
          message="an expectation compares with `==` or `contains`",
          help="leave the comparison out to record what it reads instead",
          span=@sh.span_of(parts[i]),
        )
    }
  }
  match kw_arg_of(parts) {
    Some((name, value)) => obj[name] = value
    None => ()
  }
  Json::object(obj)
}

///|
/// Where the comparison starts, so a state place can be read up to it.
fn comparison_at(parts : Array[@ast.Node], from : Int) -> Int {
  let mut i = from
  while i < parts.length() {
    match parts[i].it {
      Op("==") | Id("contains") | Kw(_) => return i
      _ => i = i + 1
    }
  }
  i
}

///|
/// A state place as the dotted text the scene reader takes.
fn place_text(terms : ArrayView[@ast.Node]) -> String {
  let out = StringBuilder()
  for t in terms {
    match t.it {
      Id("it") => ()
      Id(n) => out.write_string(n)
      Op(".") => out.write_string(".")
      // A key is a literal (`[0]`, `["a"]`) or a FIELD that holds one, and the
      // old notation spells the second `[.group]`. Rendering the group as its
      // raw text wrote `it.group`, which is not a key the parser has — and
      // dropping `it.` only at the top level wrote `group`, which it reads as
      // a bare name it refuses on purpose.
      // A key is a literal (`[0]`, `["a"]`) or a FIELD that holds one, and the
      // old notation spells the second `[.group]`.
      //
      // Rendered with `node_text` this wrote `[group]` — `node_text` falls
      // back to the NODE'S TAG, and a bracket holds a `Group`, so the word
      // "group" reached the parser as if it were a field name. The message it
      // answered with named a field the file does not have.
      Brackets(gs) => {
        out.write_string("[")
        for g in gs {
          out.write_string(key_text(g))
        }
        out.write_string("]")
      }
      Lit(Str(s)) => out.write_string("'\{s}'")
      _ => ()
    }
  }
  let text = out.to_string()
  if text == "" || text.has_prefix(".") {
    text
  } else {
    "." + text
  }
}

///|
/// One key inside a `[…]`: a literal, or the field that holds one.
fn key_text(g : @ast.Node) -> String {
  let parts = match g.it {
    Group(ps) => ps
    _ => [g]
  }
  // A single literal is the key itself; anything else is a path, and
  // `place_text` is what writes one.
  if parts.length() == 1 {
    match parts[0].it {
      Lit(Str(s)) => return "'\{s}'"
      Lit(Int_(i)) => return i.to_string()
      Lit(Flo(f)) => return f.to_string()
      _ => ()
    }
  }
  place_text(parts[:])
}

///|
/// A trailing `~nth: n` on an expectation.
fn kw_arg_of(parts : Array[@ast.Node]) -> (String, Json)? {
  let mut i = 0
  while i < parts.length() {
    if parts[i].it is Kw(name) &&
      i + 1 < parts.length() &&
      parts[i + 1].it is Block(bgs) &&
      bgs.length() == 1 {
      let v = json_of(@sh.read_group(bgs[0])) catch { _ => return None }
      return Some((name, v))
    }
    i = i + 1
  }
  None
}

///|
/// `~intents:` — the three answers, keyed by the name they answer.
fn intents_json(groups : Array[@ast.Node]) -> Json raise @sh.ExError {
  let out = Map([])
  for g in groups {
    guard g.it is Group(parts) && parts.length() >= 1 && parts[0].it is Id(verb) else {
      continue
    }
    let args = match parts.get(1) {
      Some(n) =>
        match n.it {
          Parens(gs) => @sh.positional(@sh.read_args(gs))
          _ => []
        }
      None => []
    }
    guard args.length() >= 1 && args[0] is @sh.EStr(name) else {
      raise @sh.ExError(
        message="an intent answer names the intent it answers",
        help="write `ok(\"<name>\", <value>)`, `failed(\"<name>\", <value>)` or `pass(\"<name>\")`",
        span=@sh.span_of(parts[0]),
      )
    }
    match verb {
      "pass" => out[name] = Json::string("pass")
      "ok" | "failed" => {
        guard args.length() == 2 else {
          raise @sh.ExError(
            message="`\{verb}` answers with one value",
            help="write `\{verb}(\"\{name}\", <value>)`",
            span=@sh.span_of(parts[0]),
          )
        }
        let one : Map[String, Json] = Map([])
        one[verb] = json_of(args[1])
        out[name] = Json::object(one)
      }
      other =>
        raise @sh.ExError(
          message="`\{other}` is not an intent answer",
          help="an intent is answered `ok`, `failed` or `pass`, and nothing else",
          span=@sh.span_of(parts[0]),
        )
    }
  }
  Json::object(out)
}
