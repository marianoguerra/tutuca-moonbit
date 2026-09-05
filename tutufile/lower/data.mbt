// The `fixtures:` and `tests:` sections, printed as the JSON blocks their
// readers take.
//
// One step language, printed twice: a fixture's `~drive` and a scene's steps
// are the same statements, which is the thing the two JSON blocks could never
// say about each other.

///|
/// A value expression as JSON.
pub fn json_of(ex : Ex) -> Json raise ExError {
  match ex {
    ENum(n) => Json::number(n)
    EStr(s) => Json::string(s)
    EBool(b) => Json::boolean(b)
    ENone => Json::null()
    EName("true") => Json::boolean(true)
    EName("false") => Json::boolean(false)
    EList(xs) => {
      let out = []
      for x in xs {
        out.push(json_of(x))
      }
      Json::array(out)
    }
    EMap(entries) => {
      let out = {}
      for e in entries {
        out[e.0] = json_of(e.1)
      }
      Json::object(out)
    }
    ECall(EName(name), args) => {
      // `ok [...]`, `failed "…"` and `pass` are an intent's three answers
      let pos = positional(args)
      match (name, pos.length()) {
        ("ok", 1) => Json::object({ "ok": json_of(pos[0]) })
        ("failed", 1) => Json::object({ "failed": json_of(pos[0]) })
        _ =>
          raise ExError(
            message="`\{name}` is not a value",
            help="a value is a number, a string, `true`, `false`, a list or a map",
            span=@report.Span::at(0),
          )
      }
    }
    _ =>
      raise ExError(
        message="this is not a value a fixture or a scene can carry",
        help="a value is a number, a string, `true`, `false`, a list or a map",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The `fixtures:` section as its JSON object.
pub fn print_fixtures(decls : Array[@tutufile.Decl]) -> String raise ExError {
  let out = {}
  for d in decls {
    out[d.name] = fixture_json(d)
  }
  Json::object(out).stringify(indent=2)
}

///|
fn fixture_json(decl : @tutufile.Decl) -> Json raise ExError {
  let env = {}
  let value = {}
  if decl.options.contains("default") {
    env["default"] = Json::boolean(true)
  }
  match decl_doc(decl) {
    Some(d) => env["doc"] = Json::string(d)
    None => ()
  }
  for group in body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    match parts[0].it {
      Kw(name) => {
        guard parts.length() >= 2 && parts[1].it is Block(bgs) else { continue }
        match name {
          "drive" => env["drive"] = steps_json(bgs)
          "intents" => env["intents"] = intents_json(bgs)
          _ => {
            guard bgs.length() == 1 else { continue }
            env[name] = json_of(read_group(bgs[0]))
          }
        }
      }
      // `it.field = value` — one entry of the state a fixture starts from
      Id("it") => {
        guard find_op(parts, ["="]) is Some(at) && parts.length() > 2 else {
          continue
        }
        guard parts[2].it is Id(field) else { continue }
        value[field] = json_of(read_ex(parts[at + 1:]))
      }
      _ => ()
    }
  }
  env["value"] = Json::object(value)
  Json::object(env)
}

///|
/// The `tests:` section as its JSON object.
pub fn print_scenes(decls : Array[@tutufile.Decl]) -> String raise ExError {
  let out = {}
  for d in decls {
    out[d.name] = scene_json(d)
  }
  Json::object(out).stringify(indent=2)
}

///|
fn scene_json(decl : @tutufile.Decl) -> Json raise ExError {
  let env = {}
  let steps = []
  for group in body_groups(decl) {
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
            env[name] = json_of(read_group(bgs[0]))
          }
        }
      }
      Kw(_) => ()
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
    Group(parts) => if parts.length() > 0 { node_text(parts[0]) } else { "" }
    _ => node_text(group)
  }
}

///|
/// The steps of a `~drive` or a scene.
fn steps_json(groups : Array[@ast.Node]) -> Json raise ExError {
  let out = []
  for g in groups {
    out.push(step_json(g))
  }
  Json::array(out)
}

///|
/// One step: a driving verb, or a reading `expect`.
fn step_json(group : @ast.Node) -> Json raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 else {
    raise ExError(
      message="a step is a verb",
      help="write `click(\"button\")`, or `expect text(\"o\") == \"3\"`",
      span=span_of(group),
    )
  }
  guard parts[0].it is Id(verb) else {
    raise ExError(
      message="a step is a verb",
      help="write `click(\"button\")`, or `expect text(\"o\") == \"3\"`",
      span=span_of(parts[0]),
    )
  }
  if verb == "expect" {
    return expect_json(parts, group)
  }
  guard parts.length() >= 2 && parts[1].it is Parens(gs) else {
    raise ExError(
      message="`\{verb}` is called with what it acts on",
      help="write `\{verb}(\"<selector>\")`",
      span=span_of(parts[0]),
    )
  }
  let args = read_args(gs)
  let pos = positional(args)
  let obj = {}
  let arg = fn(i : Int) -> Json raise ExError { json_of(pos[i]) }
  match verb {
    "click" => obj["click"] = arg(0)
    "type" => {
      obj["type"] = arg(0)
      obj["value"] = arg(1)
    }
    "key" => {
      obj["key"] = arg(0)
      obj["is"] = arg(1)
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
      raise ExError(
        message="`\{other}` is not a step",
        help="the verbs are `click`, `type`, `key`, `check`, `fire`, `drag` and `send`",
        span=span_of(parts[0]),
      )
  }
  match kw_arg(args, "nth") {
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
) -> Json raise ExError {
  guard parts.length() >= 2 && parts[1].it is Id(reader) else {
    raise ExError(
      message="`expect` names what to read",
      help="write `expect text(\"o\") == \"3\"`",
      span=span_of(group),
    )
  }
  let obj = { "expect": Json::string(reader) }
  let mut i = 2
  // a reader with a subject: `text("o")`, `attr("a", "href")`
  if i < parts.length() && parts[i].it is Parens(gs) {
    let pos = positional(read_args(gs))
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
    obj["at"] = Json::string(place_text(parts[i:stop]))
    i = stop
  }
  // the comparison, if there is one; without it the step records instead
  if i < parts.length() {
    match parts[i].it {
      Op("==") => obj["is"] = json_of(read_ex(parts[i + 1:]))
      Id("contains") => obj["contains"] = json_of(read_ex(parts[i + 1:]))
      _ =>
        raise ExError(
          message="an expectation compares with `==` or `contains`",
          help="leave the comparison out to record what it reads instead",
          span=span_of(parts[i]),
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
      Brackets(gs) => {
        out.write_string("[")
        for g in gs {
          out.write_string(node_text(g))
        }
        out.write_string("]")
      }
      Lit(Str(s)) => out.write_string("'\{s}'")
      _ => ()
    }
  }
  let text = out.to_string()
  if text.has_prefix(".") {
    text
  } else {
    "." + text
  }
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
      let v = json_of(read_group(bgs[0])) catch { _ => return None }
      return Some((name, v))
    }
    i = i + 1
  }
  None
}

///|
/// `~intents:` — the three answers, keyed by the name they answer.
fn intents_json(groups : Array[@ast.Node]) -> Json raise ExError {
  let out = {}
  for g in groups {
    guard g.it is Group(parts) && parts.length() >= 1 && parts[0].it is Id(name) else {
      continue
    }
    if parts.length() == 1 {
      out[name] = Json::string("pass")
      continue
    }
    guard parts[1].it is Block(bgs) && bgs.length() == 1 else { continue }
    let answer = read_group(bgs[0])
    out[name] = match answer {
      EName("pass") => Json::string("pass")
      other => json_of(other)
    }
  }
  Json::object(out)
}
