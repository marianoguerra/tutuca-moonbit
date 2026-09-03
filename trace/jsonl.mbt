// The file format: two header lines, then one line per event.
//
// ## Why lines
//
// A recording of a real session is long and is almost entirely a list of
// events. One JSON document would mean a recorder that buffers everything to
// close a bracket, a reader that parses megabytes to show the first row, and
// three shortening operations that all have to understand an event before they
// can drop one. Lines mean a recorder appends, a reader streams, and `prefix`
// and `compact` are slicing and filtering.
//
// ## The shape
//
//     {"tutucaTrace":1,"origin":{…},"relocatedFrom":[]}
//     {"root":{"$component":"TodoApp",…}}
//     {"seq":1,"turn":1,"at":[],"send":"init","args":[]}
//     {"seq":9,"turn":3,"walk":3,"at":[{"f":"items","k":2}],"intent":"save",…}
//     {"seq":10,"turn":3,"walk":3,"derived":true,"offered":"save","nth":0,…}
//     {"seq":11,"turn":3,"walk":3,"answer":{"ok":…},"nth":0,"at":[…]}
//
// The root is its own line rather than a field of the header because it is the
// one thing in the file that can be megabytes: keeping it separate is what lets
// a viewer draw the events before it has parsed the state, and what lets
// `rebase` replace it by replacing one line.
//
// The verb is the KEY, not a `"kind"` field, so an event line reads as what
// happened rather than as a tagged union. `derived` is written only when true,
// because an input is the ordinary case and the ordinary case should be quiet.
//
// ## What round-trips
//
// Arguments are written with `to_component_json`, so a component instance
// passed as an argument keeps its identity instead of flattening to its fields.
// Reading them back here yields the STRUCTURE — a `$component` map — because
// this package deliberately has no component source to build from; `replay`
// hydrates them when it mounts, where a scope exists. Everything else round
// trips exactly, within `Value`'s own limits (a function is null, an integer is
// a double).

///|
const TRACE_KEY : String = "tutucaTrace"

// --- Op ---------------------------------------------------------------------

///|
/// The four legs of an intent's route, as words. `Leg::word` is the repo's
/// spelling and this defers to it rather than writing "dyn" a second time.
fn opts_to_json(o : @tutuca.IntentOpts) -> Json {
  let obj : Map[String, Json] = {
    "route": Json::array(o.route.map(l => Json::string(l.word()))),
  }
  match o.on_ok_name {
    Some(n) => obj["ok"] = Json::string(n)
    None => ()
  }
  match o.on_failed_name {
    Some(n) => obj["failed"] = Json::string(n)
    None => ()
  }
  match o.on_unhandled_name {
    Some(n) => obj["unhandled"] = Json::string(n)
    None => ()
  }
  if o.live_path {
    obj["livePath"] = Json::boolean(true)
  }
  Json::object(obj)
}

///|
/// Options back. A missing `route` is the DEFAULT route and not an empty one:
/// an empty route walks nowhere, which is a different intent from one that did
/// not say where to go.
fn opts_of_json(j : Json) -> @tutuca.IntentOpts {
  guard j is Object(m) else { return @tutuca.IntentOpts::new() }
  let route : Array[@tutuca.Leg] = match m.get("route") {
    Some(Array(items)) => {
      let out : Array[@tutuca.Leg] = []
      for it in items {
        match it {
          String("dyn") => out.push(Dyn)
          String("lex") => out.push(Lex)
          _ => ()
        }
      }
      out
    }
    _ => @tutuca.default_route()
  }
  fn name(key : String) -> String? {
    match m.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  }

  @tutuca.IntentOpts::new(
    route~,
    on_ok_name?=name("ok"),
    on_failed_name?=name("failed"),
    on_unhandled_name?=name("unhandled"),
    live_path=m.get("livePath") is Some(True),
  )
}

///|
/// An answer. `Pass` is a bare word rather than an object because it carries
/// nothing, and an object with no fields reads as a value that went missing.
fn answer_to_json(a : @tutuca.IntentAnswer) -> Json {
  match a {
    Ok(v) => Json::object({ "ok": v.to_component_json() })
    Failed(e) => Json::object({ "failed": e.to_component_json() })
    Pass => Json::string("pass")
  }
}

///|
fn answer_of_json(
  j : Json,
  line~ : Int,
) -> @tutuca.IntentAnswer raise TraceError {
  match j {
    String("pass") => Pass
    Object(m) =>
      match (m.get("ok"), m.get("failed")) {
        (Some(v), _) => Ok(@tutuca.Value::from_json(v))
        (_, Some(e)) => Failed(@tutuca.Value::from_json(e))
        _ => raise BadField(line~, key="answer", want="ok, failed or \"pass\"")
      }
    _ => raise BadField(line~, key="answer", want="ok, failed or \"pass\"")
  }
}

///|
fn args_to_json(args : Array[@tutuca.Value]) -> Json {
  Json::array(args.map(a => a.to_component_json()))
}

///|
fn args_of_json(j : Json?) -> Array[@tutuca.Value] {
  match j {
    Some(Array(items)) => items.map(it => @tutuca.Value::from_json(it))
    _ => []
  }
}

// --- Event ------------------------------------------------------------------

///|
pub fn Event::to_json(self : Event) -> Json {
  let obj : Map[String, Json] = { "seq": Json::number(self.seq.to_double()) }
  if self.turn != 0 {
    obj["turn"] = Json::number(self.turn.to_double())
  }
  if self.walk != 0 {
    obj["walk"] = Json::number(self.walk.to_double())
  }
  if self.parent != 0 {
    obj["parent"] = Json::number(self.parent.to_double())
  }
  // Only when true: an input is the ordinary case, and a file where every line
  // says so is a file where the exceptional lines do not stand out.
  if !self.input {
    obj["derived"] = Json::boolean(true)
  }
  obj["at"] = self.at.to_json()
  match self.op {
    Send(name~, args~) => {
      obj["send"] = Json::string(name)
      obj["args"] = args_to_json(args)
    }
    Intent(name~, args~, opts~) => {
      obj["intent"] = Json::string(name)
      obj["args"] = args_to_json(args)
      obj["opts"] = opts_to_json(opts)
    }
    Offered(name~, args~, nth~) => {
      obj["offered"] = Json::string(name)
      obj["args"] = args_to_json(args)
      obj["nth"] = Json::number(nth.to_double())
    }
    Answer(nth~, answer~) => {
      obj["answer"] = answer_to_json(answer)
      obj["nth"] = Json::number(nth.to_double())
    }
    Refused(code~, asked~, rule~, sentence~) => {
      obj["refused"] = Json::string(code)
      obj["asked"] = Json::string(asked)
      if rule != "" {
        obj["rule"] = Json::string(rule)
      }
      if sentence != "" {
        obj["sentence"] = Json::string(sentence)
      }
    }
  }
  match self.after {
    Some(a) => obj["after"] = a
    None => ()
  }
  Json::object(obj)
}

///|
fn int_at(m : Map[String, Json], key : String) -> Int {
  match m.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
fn str_at(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
pub fn Event::from_json(j : Json, line~ : Int) -> Event raise TraceError {
  guard j is Object(m) else { raise BadField(line~, key="", want="an object") }
  let at = match m.get("at") {
    None => Place([])
    Some(aj) =>
      match Place::from_json(aj) {
        Some(p) => p
        None => raise BadPlace(line~, why="`at` is not a list of steps")
      }
  }
  let args = args_of_json(m.get("args"))
  // The verb is the key, and exactly one of them may be present. Checked in a
  // fixed order so a line that somehow says two is read the same way twice
  // rather than by map iteration order.
  let op : Op = if m.get("send") is Some(String(name)) {
    Send(name~, args~)
  } else if m.get("intent") is Some(String(name)) {
    Intent(
      name~,
      args~,
      opts=opts_of_json(m.get("opts").unwrap_or(Json::null())),
    )
  } else if m.get("offered") is Some(String(name)) {
    Offered(name~, args~, nth=int_at(m, "nth"))
  } else if m.get("answer") is Some(aj) {
    Answer(nth=int_at(m, "nth"), answer=answer_of_json(aj, line~))
  } else if m.get("refused") is Some(String(code)) {
    Refused(
      code~,
      asked=str_at(m, "asked"),
      rule=str_at(m, "rule"),
      sentence=str_at(m, "sentence"),
    )
  } else {
    raise NoOp(line~, keys=m.keys().collect())
  }
  {
    seq: int_at(m, "seq"),
    turn: int_at(m, "turn"),
    walk: int_at(m, "walk"),
    parent: int_at(m, "parent"),
    at,
    op,
    // Absent means input, which is what makes the ordinary line short.
    input: !(m.get("derived") is Some(True)),
    after: m.get("after"),
  }
}

// --- Origin -----------------------------------------------------------------

///|
fn origin_to_json(o : Origin) -> Json {
  let obj : Map[String, Json] = Map([])
  fn put(key : String, v : String) -> Unit {
    if v != "" {
      obj[key] = Json::string(v)
    }
  }

  put("module", o.module_)
  put("component", o.component)
  put("example", o.example)
  put("view", o.view)
  put("fingerprint", o.fingerprint)
  Json::object(obj)
}

///|
fn origin_of_json(j : Json) -> Origin {
  guard j is Object(m) else { return Origin::empty() }
  {
    module_: str_at(m, "module"),
    component: str_at(m, "component"),
    example: str_at(m, "example"),
    view: str_at(m, "view"),
    fingerprint: str_at(m, "fingerprint"),
  }
}

// --- the file ---------------------------------------------------------------

///|
fn Trace::header_line(self : Trace) -> Json {
  let obj : Map[String, Json] = {
    "origin": origin_to_json(self.origin),
    "relocatedFrom": Json::array(self.relocated_from.map(p => p.to_json())),
  }
  obj[TRACE_KEY] = Json::number(self.version.to_double())
  // Only when true, like every other flag in this format: the ordinary
  // recording is the complete one, and the ordinary line should be quiet.
  if self.compacted {
    obj["compacted"] = Json::boolean(true)
  }
  Json::object(obj)
}

///|
fn root_line(root : Json) -> Json {
  Json::object({ "root": root })
}

///|
pub fn Trace::to_jsonl(self : Trace) -> String {
  let b = StringBuilder()
  b.write_string(self.header_line().stringify())
  b.write_string("\n")
  b.write_string(root_line(self.root).stringify())
  b.write_string("\n")
  for e in self.events {
    b.write_string(e.to_json().stringify())
    b.write_string("\n")
  }
  b.to_string()
}

///|
/// The lines of a file, with the blank ones dropped.
///
/// Blank lines because a file that has been concatenated, edited by hand, or
/// written with a trailing newline has them, and refusing one would be refusing
/// a file that is otherwise perfectly readable.
fn nonblank_lines(text : String) -> Array[(Int, String)] {
  let out : Array[(Int, String)] = []
  let mut n = 0
  for raw in text.split("\n") {
    n = n + 1
    let line = raw.trim().to_owned()
    if line != "" {
      out.push((n, line))
    }
  }
  out
}

///|
fn parse_line(line : String, n : Int) -> Json raise TraceError {
  @json.parse(line) catch {
    e => raise NotJson(line=n, why=e.to_string())
  }
}

///|
pub fn split_lines(
  text : String,
) -> (Array[String], Array[String]) raise TraceError {
  let lines = nonblank_lines(text)
  if lines.length() < 2 {
    raise NoHeader("a trace needs a header line and a root line")
  }
  // Only enough parsing to know a header from an event: `trim` slices lines and
  // must not fail on an event kind it has never heard of.
  let (n0, l0) = lines[0]
  guard parse_line(l0, n0) is Object(m0) && m0.get(TRACE_KEY) is Some(_) else {
    raise NotATrace(line=n0)
  }
  let (n1, l1) = lines[1]
  guard parse_line(l1, n1) is Object(m1) && m1.get("root") is Some(_) else {
    raise NoRoot(line=n1)
  }
  let events : Array[String] = []
  for i in 2..<lines.length() {
    let (n, l) = lines[i]
    match parse_line(l, n) {
      Object(m) =>
        if m.get(TRACE_KEY) is Some(_) || m.get("root") is Some(_) {
          raise LateHeader(line=n)
        }
      _ => raise BadField(line=n, key="", want="an object")
    }
    events.push(l)
  }
  ([l0, l1], events)
}

///|
pub fn from_jsonl(text : String) -> Trace raise TraceError {
  let lines = nonblank_lines(text)
  let (headers, event_lines) = split_lines(text)
  guard parse_line(headers[0], 1) is Object(m0) else { raise NotATrace(line=1) }
  let version = match m0.get(TRACE_KEY) {
    Some(Number(n, ..)) => n.to_int()
    _ => raise NotATrace(line=1)
  }
  if version != VERSION {
    raise BadVersion(line=1, got=version, want=VERSION)
  }
  guard parse_line(headers[1], 2) is Object(m1) && m1.get("root") is Some(root) else {
    raise NoRoot(line=2)
  }
  let relocated_from : Array[Place] = match m0.get("relocatedFrom") {
    Some(Array(items)) => {
      let out : Array[Place] = []
      for it in items {
        match Place::from_json(it) {
          Some(p) => out.push(p)
          None => raise BadPlace(line=1, why="`relocatedFrom` holds a bad step")
        }
      }
      out
    }
    _ => []
  }
  let events : Array[Event] = []
  for i, l in event_lines {
    // The reported line is the one in the FILE, blank lines and all, because
    // that is the number an editor shows.
    let n = lines[i + 2].0
    events.push(Event::from_json(parse_line(l, n), line=n))
  }
  {
    version,
    origin: origin_of_json(m0.get("origin").unwrap_or(Json::null())),
    root,
    relocated_from,
    compacted: m0.get("compacted") is Some(True),
    events,
  }
}

///|
pub fn Trace::to_json(self : Trace) -> Json {
  guard self.header_line() is Object(head) else { return Json::null() }
  head["root"] = self.root
  head["events"] = Json::array(self.events.map(e => e.to_json()))
  Json::object(head)
}

///|
pub fn Trace::from_json(j : Json) -> Trace raise TraceError {
  guard j is Object(m) else { raise NotATrace(line=0) }
  guard m.get(TRACE_KEY) is Some(Number(v, ..)) else { raise NotATrace(line=0) }
  let version = v.to_int()
  if version != VERSION {
    raise BadVersion(line=0, got=version, want=VERSION)
  }
  guard m.get("root") is Some(root) else { raise NoRoot(line=0) }
  let relocated_from : Array[Place] = match m.get("relocatedFrom") {
    Some(Array(items)) => {
      let out : Array[Place] = []
      for it in items {
        match Place::from_json(it) {
          Some(p) => out.push(p)
          None => raise BadPlace(line=0, why="`relocatedFrom` holds a bad step")
        }
      }
      out
    }
    _ => []
  }
  let events : Array[Event] = []
  match m.get("events") {
    Some(Array(items)) =>
      for i, it in items {
        events.push(Event::from_json(it, line=i + 1))
      }
    _ => ()
  }
  {
    version,
    origin: origin_of_json(m.get("origin").unwrap_or(Json::null())),
    root,
    relocated_from,
    compacted: m.get("compacted") is Some(True),
    events,
  }
}

// --- messages ---------------------------------------------------------------

///|
pub fn TraceError::message(self : TraceError) -> String {
  match self {
    NoHeader(why) => "not a trace: \{why}"
    NotJson(line~, why~) => "line \{line}: \{why}"
    NotATrace(line~) => "line \{line}: the first line must name `\{TRACE_KEY}`"
    BadVersion(line~, got~, want~) =>
      "line \{line}: trace version \{got}, but this reader knows \{want}"
    NoRoot(line~) => "line \{line}: the second line must hold `root`"
    LateHeader(line~) => "line \{line}: a header line after the events began"
    NoOp(line~, keys~) =>
      "line \{line}: no verb here — found \{keys.join(", ")}"
    BadField(line~, key~, want~) =>
      if key == "" {
        "line \{line}: expected \{want}"
      } else {
        "line \{line}: `\{key}` should be \{want}"
      }
    BadPlace(line~, why~) =>
      if line == 0 {
        "bad place: \{why}"
      } else {
        "line \{line}: \{why}"
      }
  }
}
