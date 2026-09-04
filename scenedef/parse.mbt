// The `tutuca/test` reader. See spec.mbt for the types.

///|
pub fn Reader::word(self : Reader) -> String {
  match self {
    RText => "text"
    RTexts => "texts"
    RAttr => "attr"
    RProp => "prop"
    RValue => "value"
    RChecked => "checked"
    RCount => "count"
    RState => "state"
    RHtml => "html"
    RRenders => "renders"
    RRefused => "refused"
    RLog => "log"
  }
}

///|
/// Every reader, for the suggestion a misspelt one gets.
let readers : Array[Reader] = [
  RText,
  RTexts,
  RAttr,
  RProp,
  RValue,
  RChecked,
  RCount,
  RState,
  RHtml,
  RRenders,
  RRefused,
  RLog,
]

///|
/// Every verb key, in the order the docs list them. A step object carries
/// exactly one of these plus its modifiers.
let verbs : Array[String] = [
  "click", "type", "key", "check", "fire", "drag", "send", "expect",
]

///|
pub fn parse_scenes(source : String) -> Array[Scene] raise SceneError {
  let json = @json.parse(source) catch { e => raise NotJson(e.to_string()) }
  guard json is Object(scenes) else { raise NotScenes }
  let out : Array[Scene] = []
  for name, body in scenes {
    out.push(scene_of(name, body))
  }
  out
}

///|
pub fn parse_steps(
  steps : Json,
  where_ : String,
) -> Array[Step] raise SceneError {
  guard steps is Array(items) else {
    raise BadType(
      scene=where_,
      at=-1,
      key="drive",
      want="a list of steps",
      got=json_shape(steps),
    )
  }
  let out : Array[Step] = []
  for i, s in items {
    out.push(step_of(where_, i, s))
  }
  out
}

///|
fn scene_of(name : String, body : Json) -> Scene raise SceneError {
  guard body is Object(o) else { raise SceneNotObject(name) }
  let component = str_or(o, "component", "")
  let init = str_or(o, "init", "")
  let raw = o.get("raw") is Some(True)
  let args : Map[String, @tutuca.Value] = Map([])
  match o.get("args") {
    Some(Object(a)) =>
      for k, v in a {
        args[k] = @tutuca.Value::from_json(v)
      }
    Some(_) =>
      raise BadType(
        scene=name,
        at=-1,
        key="args",
        want="an object of field values",
        got=json_shape(o.get("args").unwrap()),
      )
    None => ()
  }
  let intents = intents_of(name, o)
  guard o.get("steps") is Some(Array(steps)) else { raise NoSteps(name) }
  let out : Array[Step] = []
  for i, s in steps {
    out.push(step_of(name, i, s))
  }
  { name, component, init, args, intents, raw, steps: out, }
}

///|
/// The scene's intent fixtures.
///
/// `{ "ok": v }`, `{ "failed": v }` or `"pass"` — the three answers an intent
/// has, and no fourth. A name that is not here answers nothing at all, which
/// is the `<name>Unhandled` path and is reached by writing no fixture rather
/// than by writing a special one.
fn intents_of(
  scene : String,
  o : Map[String, Json],
) -> Map[String, @tutuca.IntentAnswer] raise SceneError {
  match o.get("intents") {
    None => Map([])
    Some(i) => parse_answers(i, scene)
  }
}

///|
pub fn parse_answers(
  j : Json,
  where_ : String,
) -> Map[String, @tutuca.IntentAnswer] raise SceneError {
  let scene = where_
  let out : Map[String, @tutuca.IntentAnswer] = Map([])
  match j {
    Object(m) =>
      for name, a in m {
        out[name] = match a {
          String("pass") => Pass
          Object(one) =>
            match (one.get("ok"), one.get("failed")) {
              (Some(v), None) => Ok(@tutuca.Value::from_json(v))
              (None, Some(v)) => Failed(@tutuca.Value::from_json(v))
              (Some(_), Some(_)) =>
                raise BadIntent(
                  scene~,
                  name~,
                  why="it answers both `ok` and `failed`, and an intent has one answer",
                )
              (None, None) =>
                raise BadIntent(
                  scene~,
                  name~,
                  why="expected `ok`, `failed` or \"pass\"",
                )
            }
          _ =>
            raise BadIntent(
              scene~,
              name~,
              why="expected { \"ok\": … }, { \"failed\": … } or \"pass\"",
            )
        }
      }
    other =>
      raise BadType(
        scene~,
        at=-1,
        key="intents",
        want="an object of named answers",
        got=json_shape(other),
      )
  }
  out
}

///|
fn step_of(scene : String, at : Int, s : Json) -> Step raise SceneError {
  guard s is Object(o) else { raise StepNotObject(scene~, at~) }
  // Exactly one verb. Finding two is worth its own error: the keys of a JSON
  // object have no order the author can rely on, so a step saying both `click`
  // and `type` does not say which happens first, and picking one would be this
  // reader inventing an answer.
  let mut verb = ""
  for k in verbs {
    if o.get(k) is Some(_) {
      if verb != "" {
        raise TwoVerbs(scene~, at~, first=verb, second=k)
      }
      verb = k
    }
  }
  if verb == "" {
    let mut suggestion : String? = None
    for k, _ in o {
      if suggestion is None {
        suggestion = nearest(k, verbs)
      }
    }
    raise NoVerb(scene~, at~, suggestion~)
  }
  let nth = int_or(scene, at, o, "nth", 0)
  match verb {
    "click" => Click(sel=sel_at(scene, at, o, "click"), nth~)
    "type" =>
      Type(
        sel=sel_at(scene, at, o, "type"),
        value=need_str(scene, at, o, "type", "value"),
        nth~,
      )
    "key" =>
      Key(
        sel=sel_at(scene, at, o, "key"),
        key=need_str(scene, at, o, "key", "is"),
        value=o.get("value").map(v => @tutuca.Value::from_json(v)),
        nth~,
      )
    "check" =>
      Check(
        sel=sel_at(scene, at, o, "check"),
        checked=match o.get("is") {
          Some(True) => true
          Some(False) => false
          Some(other) =>
            raise BadType(
              scene~,
              at~,
              key="is",
              want="true or false",
              got=json_shape(other),
            )
          None => raise MissingKey(scene~, at~, verb="check", key="is")
        },
        nth~,
      )
    "fire" =>
      Fire(
        sel=sel_at(scene, at, o, "fire"),
        event=need_str(scene, at, o, "fire", "event"),
        value=o.get("value").map(v => @tutuca.Value::from_json(v)),
        key=str_or(o, "key", ""),
        nth~,
      )
    "drag" =>
      Drag(
        sel=sel_at(scene, at, o, "drag"),
        from=int_or(scene, at, o, "from", 0),
        to=int_or(scene, at, o, "to", 0),
      )
    "send" =>
      Send(
        name=need_str_at(scene, at, o, "send"),
        args=match o.get("args") {
          Some(Array(xs)) => xs.map(x => @tutuca.Value::from_json(x))
          Some(other) =>
            raise BadType(
              scene~,
              at~,
              key="args",
              want="a list of values",
              got=json_shape(other),
            )
          None => []
        },
      )
    _ => Read(expect_of(scene, at, o, nth))
  }
}

///|
fn expect_of(
  scene : String,
  at : Int,
  o : Map[String, Json],
  nth : Int,
) -> Expect raise SceneError {
  let word = need_str_at(scene, at, o, "expect")
  let mut reader : Reader? = None
  for r in readers {
    if r.word() == word {
      reader = Some(r)
    }
  }
  guard reader is Some(reader) else {
    raise NoSuchReader(
      scene~,
      at~,
      reader=word,
      suggestion=nearest(word, readers.map(r => r.word())),
    )
  }
  // `at` is a selector for every reader that looks at the DOM, a dotted place
  // for `state`, and nothing at all for the three that read the app.
  let raw_at = str_or(o, "at", "")
  let mut sel = ""
  let mut place : Array[@tutuca.Step] = []
  match reader {
    RState =>
      if raw_at != "" {
        place = parse_place(raw_at) catch {
          e => raise BadPlace(scene~, at~, place=raw_at, why=e.message())
        }
      }
    RHtml | RRenders | RRefused | RLog => ()
    _ => {
      if raw_at == "" {
        raise MissingKey(scene~, at~, verb="expect " + word, key="at")
      }
      check_selector(scene, at, raw_at)
      sel = raw_at
    }
  }
  let want : Want? = match (o.get("is"), o.get("contains")) {
    (Some(v), None) => Some(WIs(@tutuca.Value::from_json(v)))
    (None, Some(String(s))) =>
      // Only the two readers that answer a string can be approximate. For
      // anything else `is` says what is meant, and a `contains` over a number
      // would be a comparison nobody wrote on purpose.
      if reader is (RHtml | RText | RLog) {
        Some(WContains(s))
      } else {
        raise NotContainable(scene~, at~, reader=word)
      }
    (None, Some(other)) =>
      raise BadType(
        scene~,
        at~,
        key="contains",
        want="a string",
        got=json_shape(other),
      )
    (Some(_), Some(_)) =>
      raise BadType(
        scene~,
        at~,
        key="is",
        want="one of `is` or `contains`",
        got="both",
      )
    // RECORD: read it and hand the answer back rather than judging it.
    (None, None) => None
  }
  { reader, sel, place, name: str_or(o, "name", ""), nth, want, }
}

// ---------------------------------------------------------------------------
// selectors, places, and the small readers the above leans on

///|
/// The harness takes ONE compound selector — a tag plus any number of `#id`,
/// `.class` and `[attr]` qualifiers — and no combinators. `.pane .row` is read
/// as one malformed token there and silently matches nothing, which is the
/// worst way for a test to be wrong: it passes.
fn check_selector(
  scene : String,
  at : Int,
  sel : String,
) -> Unit raise SceneError {
  if sel.contains(" ") || sel.contains(">") || sel.contains(",") {
    raise BadSelector(
      scene~,
      at~,
      sel~,
      why="a selector is ONE compound selector — a tag plus any number of #id, .class and [attr] qualifiers. There is no descendant combinator and no list; scope by a class the target itself carries",
    )
  }
}

///|
pub fn parse_place(src : String) -> Array[@tutuca.Step] raise PlaceError {
  let cs = src.to_array()
  let n = cs.length()
  guard n > 0 && cs[0] == '.' else {
    raise PlaceError("a place starts at a field of the state, e.g. `.count`")
  }
  let out : Array[@tutuca.Step] = []
  let mut i = 0
  while i < n {
    guard cs[i] == '.' else {
      raise PlaceError("expected `.` before a field name")
    }
    i = i + 1
    let start = i
    while i < n && cs[i] != '.' && cs[i] != '[' {
      i = i + 1
    }
    guard i > start else { raise PlaceError("a field name cannot be empty") }
    let field = String::from_array(cs[start:i].to_owned())
    if i < n && cs[i] == '[' {
      i = i + 1
      let kstart = i
      while i < n && cs[i] != ']' {
        i = i + 1
      }
      guard i < n else { raise PlaceError("a key is not closed: expected `]`") }
      let key_src = String::from_array(cs[kstart:i].to_owned())
      i = i + 1
      out.push(SeqStep(field~, key=key_of(key_src)))
    } else {
      out.push(FieldStep(field))
    }
  }
  out
}

///|
/// A literal key: `[0]` is a position, `['a']` or `["a"]` is a name.
///
/// A bare word is refused rather than guessed at. `.byId[a]` could mean the
/// key `a` or the key held in `.a`, and the block language DOES have the
/// second spelling — so reading it as the first here would be this package
/// disagreeing with the language about what a card already means.
fn key_of(src : String) -> @tutuca.PathKey raise PlaceError {
  let s = src.trim(chars=" ").to_owned()
  if s.length() >= 2 &&
    (
      (s.has_prefix("'") && s.has_suffix("'")) ||
      (s.has_prefix("\"") && s.has_suffix("\""))
    ) {
    return KStr(s[1:s.length() - 1].to_owned())
  }
  (@string.parse_int(s) |> KInt) catch {
    _ =>
      raise PlaceError(
        "a key is a whole number (`[0]`) or a quoted name (`['a']`); a bare `\{s}` would be ambiguous with the key held in `.\{s}`",
      )
  }
}

///|
fn str_or(o : Map[String, Json], key : String, dflt : String) -> String {
  match o.get(key) {
    Some(String(s)) => s
    _ => dflt
  }
}

///|
fn int_or(
  scene : String,
  at : Int,
  o : Map[String, Json],
  key : String,
  dflt : Int,
) -> Int raise SceneError {
  match o.get(key) {
    None => dflt
    Some(Number(n, ..)) => n.to_int()
    Some(other) =>
      raise BadType(scene~, at~, key~, want="a number", got=json_shape(other))
  }
}

///|
/// The verb's own value, which for every selector verb is the selector.
fn sel_at(
  scene : String,
  at : Int,
  o : Map[String, Json],
  verb : String,
) -> String raise SceneError {
  let s = need_str_at(scene, at, o, verb)
  check_selector(scene, at, s)
  s
}

///|
fn need_str_at(
  scene : String,
  at : Int,
  o : Map[String, Json],
  key : String,
) -> String raise SceneError {
  match o.get(key) {
    Some(String(s)) => s
    Some(other) =>
      raise BadType(scene~, at~, key~, want="a string", got=json_shape(other))
    None => raise MissingKey(scene~, at~, verb=key, key~)
  }
}

///|
fn need_str(
  scene : String,
  at : Int,
  o : Map[String, Json],
  verb : String,
  key : String,
) -> String raise SceneError {
  match o.get(key) {
    Some(String(s)) => s
    Some(other) =>
      raise BadType(scene~, at~, key~, want="a string", got=json_shape(other))
    None => raise MissingKey(scene~, at~, verb~, key~)
  }
}

///|
/// What a JSON value IS, for a message that says what was found as well as
/// what was wanted.
/// What a JSON value IS, for a message that says what arrived instead of what
/// was wanted. Public because `statedef`'s init-block reader wants the same
/// words: two vocabularies for the same six shapes is two error messages the
/// reader has to learn.
pub fn json_shape(j : Json) -> String {
  match j {
    Null => "null"
    True | False => "a boolean"
    Number(_) => "a number"
    String(_) => "a string"
    Array(_) => "a list"
    Object(_) => "an object"
  }
}

///|
/// The nearest of `options` to `word`, when one is near enough to be worth
/// suggesting. Edit distance over a handful of short words, which is what the
/// schema's own `NoSuchField` suggestion does.
fn nearest(word : String, options : Array[String]) -> String? {
  @tutuca.closest_name(word, options, limit=2)
}

///|
pub fn PlaceError::message(self : PlaceError) -> String {
  let PlaceError(m) = self
  m
}
