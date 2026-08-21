// Named initial states, validated against the schema.
//
// A default is a value rather than a type, so it must not be smuggled into the
// schema through a comment convention. It gets a block of its own:
//
//   <script type="tutuca/init">
//   { "fresh":        { "value": {} },
//     "with-history": { "value": { "count": 3, "history": [1, 2, 3] },
//                       "doc": "What it looks like once it has been used." } }
//   </script>
//
// A fixture is an ENVELOPE — `value` plus what a gallery needs to know about
// it — rather than the field map itself. The keys sit one level above the field
// names, describing the fixture where the field names describe the component,
// so nothing can collide and none of them needs a sigil. (`$component`, inside
// a value, earns its own for the opposite reason.)
//
// Two shapes in one position need telling apart,
// and the ways are a sigil or sniffing the keys against the schema. The second
// is decidable — every key is already checked against the declared fields — and
// its failure mode is a component that later declares a field called `value`
// and silently changes how its own fixtures parse. One level of nesting is the
// cheaper half of that trade.
//
// Keeping the two apart is what lets several fixtures share one state type,
// which is exactly what a storybook's example list is. Every named state is
// checked against the schema at generation time, so a fixture naming a field
// the schema dropped fails the build instead of being silently coerced away
// by `FieldSpec::coerce_or_default` at runtime.

///|
/// One named initial state: the fixture name and the field values it sets.
///
/// Values are MoonBit source text, ready to spread over `State::zero()` —
/// the fixture names only what differs, exactly as a hand-written `init`
/// does.
pub(all) struct InitState {
  name : String
  /// The MoonBit identifier for this fixture.
  ident : String
  fields : Array[(String, String)]
  /// What this state IS, for a gallery that would otherwise show only names.
  doc : String
  /// Which view to render it under. Empty for the default resolution, which is
  /// `ExampleDef.view`'s `None` — the one thing a value cannot say about
  /// itself, since a component's `main` and its `row` hold the same fields.
  view : String
  /// What a picker filters on.
  tags : Array[String]
  /// Whether this is the state to show when nothing names one.
  default_ : Bool
  /// Steps to run after the value is seeded — a fixture arrived at by DOING.
  ///
  /// The honest form for a component that builds its own children: `new` is how
  /// a list grows a row, so a `value` naming three of them is something else
  /// having put them there.
  ///
  /// Kept as JSON, and VALIDATED as steps on the way in. Both halves are
  /// deliberate: a malformed step is a thing the author should hear about where
  /// the file is split, and what the steps mean belongs to whoever runs a
  /// fixture — which for a card is on the other side of a manifest. Parsing
  /// them into a shape only to write them back out would be this package
  /// holding an opinion it does not use.
  drive : Json
  /// The intent answers those steps need. Same rule.
  intents : Json
  /// The same values, as VALUES.
  ///
  /// `fields` is MoonBit source because the generator writes it into a `make`
  /// call, and that projection is lossy in the one direction a runtime needs:
  /// a card carries its fixtures in a manifest, and a manifest wants JSON.
  /// Turning source back into JSON is a small evaluator; keeping what was
  /// already parsed is not, since the block was JSON before either of them
  /// touched it.
  args : Map[String, @tutuca.Value]
} derive(Eq, @debug.Debug)

///|
/// Something wrong with an init block.
pub suberror InitError {
  /// The block is not JSON.
  NotJson(String)
  /// The block is JSON but not an object of named states.
  NotStates
  /// A named state is not an object of field values.
  StateNotObject(String)
  /// A fixture sets a field the schema does not declare.
  NoSuchField(state~ : String, field~ : String, suggestion~ : String?)
  /// A fixture's value does not fit the field's declared type.
  BadValue(state~ : String, field~ : String, want~ : String, got~ : String)
  /// A fixture with no `value`.
  NoValue(String)
  /// A fixture key this format does not have.
  NoSuchKey(state~ : String, key~ : String, suggestion~ : String?)
  /// A fixture key with the wrong shape.
  BadKey(state~ : String, key~ : String, want~ : String)
  /// A fixture's `drive` does not read as steps. Carries the message, since
  /// `scenedef` has already said it better than this could.
  BadDrive(state~ : String, message~ : String)
}

///|
/// The one-line message the CLI reports.
pub fn InitError::message(self : InitError) -> String {
  match self {
    NotJson(m) => "init block: not valid JSON (\{m})"
    NotStates =>
      "init block: expected an object of named states, e.g. { \"fresh\": { \"count\": 0 } }"
    StateNotObject(n) => "init block: state `\{n}` is not an object of fields"
    NoSuchField(state~, field~, suggestion~) =>
      "init block: state `\{state}` sets `\{field}`, which the schema does not declare" +
      (match suggestion {
        Some(s) => " — did you mean `\{s}`?"
        None => ""
      })
    BadValue(state~, field~, want~, got~) =>
      "init block: state `\{state}` sets `\{field}` to \{got}, but the schema declares it \{want}"
    NoValue(n) =>
      "init block: state `\{n}` has no `value` — a fixture is { \"value\": { …fields… } }, with `doc`, `view`, `drive`, `intents`, `tags` and `default` beside it"
    NoSuchKey(state~, key~, suggestion~) =>
      "init block: state `\{state}` has no key `\{key}`" +
      (match suggestion {
        Some(k) => " — did you mean `\{k}`?"
        None =>
          "; a fixture takes `value`, `doc`, `view`, `drive`, `intents`, `tags` and `default`"
      })
    BadKey(state~, key~, want~) =>
      "init block: state `\{state}`'s `\{key}` should be \{want}"
    BadDrive(state~, message~) => "init block: state `\{state}`: \{message}"
  }
}

///|
pub impl Show for InitError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Parse and validate an init block against a component's schema.
pub fn parse_init(
  source : String,
  def : StateDef,
) -> Array[InitState] raise InitError {
  let json = @json.parse(source) catch { e => raise NotJson(e.to_string()) }
  guard json is Object(states) else { raise NotStates }
  let out : Array[InitState] = []
  let names : Array[String] = []
  for k, _ in states {
    names.push(k)
  }
  names.sort_by((a, b) => str_cmp(a, b))
  for name in names {
    guard states.get(name) is Some(Object(env)) else {
      raise StateNotObject(name)
    }
    // The envelope. Every key is checked, because a fixture is a thing an agent
    // writes and a misspelt `doc` that is silently dropped is a sentence
    // nobody sees missing.
    for k, _ in env {
      if !init_keys.contains(k) {
        raise NoSuchKey(state=name, key=k, suggestion=nearest(k, init_keys))
      }
    }
    guard env.get("value") is Some(Object(fields)) else {
      match env.get("value") {
        Some(other) =>
          raise BadKey(
            state=name,
            key="value",
            want="an object of field values, but this is " + shape_of(other),
          )
        None => raise NoValue(name)
      }
    }
    let doc = str_key(env, name, "doc")
    let view = str_key(env, name, "view")
    let default_ = match env.get("default") {
      Some(True) => true
      Some(False) | None => false
      Some(_) => raise BadKey(state=name, key="default", want="true or false")
    }
    let tags : Array[String] = match env.get("tags") {
      None => []
      Some(Array(items)) => {
        let out : Array[String] = []
        for t in items {
          guard t is String(t) else {
            raise BadKey(state=name, key="tags", want="a list of strings")
          }
          out.push(t)
        }
        out
      }
      Some(_) => raise BadKey(state=name, key="tags", want="a list of strings")
    }
    let drive = match env.get("drive") {
      None => Json::array([])
      Some(d) => {
        ignore(
          @scenedef.parse_steps(d, "fixture `" + name + "`") catch {
            e => raise BadDrive(state=name, message=e.message())
          },
        )
        d
      }
    }
    let intents = match env.get("intents") {
      None => Json::object({})
      Some(i) => {
        ignore(
          @scenedef.parse_answers(i, "fixture `" + name + "`") catch {
            e => raise BadDrive(state=name, message=e.message())
          },
        )
        i
      }
    }
    let set : Array[(String, String)] = []
    // In schema order, not JSON order, so the emitted record reads the same
    // way the struct does.
    for f in def.fields {
      if fields.get(f.name) is Some(v) {
        set.push((f.binding, literal(def, f, v, name)))
      } else if fields.get(f.name) is Some(v) {
        set.push((f.binding, literal(def, f, v, name)))
      }
    }
    // Anything left over names no field: the whole point of the check.
    for k, _ in fields {
      if def.field(camel_name(k)) is None {
        raise NoSuchField(
          state=name,
          field=k,
          suggestion=nearest(camel_name(k), def.fields.map(f => f.name)),
        )
      }
    }
    // The declared fields only, so a fixture cannot smuggle a key past the
    // check above — which has already refused anything the schema lacks.
    let args : Map[String, @tutuca.Value] = Map([])
    for f in def.fields {
      if fields.get(f.name) is Some(v) {
        args[f.name] = @tutuca.Value::from_json(v)
      }
    }
    out.push({
      name,
      ident: camel_name(name),
      fields: set,
      args,
      doc,
      view,
      tags,
      default_,
      drive,
      intents,
    })
  }
  out
}

///|
/// A JSON value as MoonBit source of the field's declared type.
fn literal(
  def : StateDef,
  f : FieldDef,
  v : Json,
  state : String,
) -> String raise InitError {
  lit_of(def, f.ty, v, state, f.name)
}

///|
fn lit_of(
  def : StateDef,
  ty : StateTy,
  v : Json,
  state : String,
  field : String,
) -> String raise InitError {
  let bad = (got : String) => {
    InitError::BadValue(state~, field~, want=ty.show_source(), got~)
  }
  match (ty, v) {
    (TBool, True) => "true"
    (TBool, False) => "false"
    (TText, String(s)) => json_quote(s)
    (TFloat, Number(n, ..)) =>
      if n == n.to_int().to_double() {
        "\{n.to_int()}.0"
      } else {
        n.to_string()
      }
    (TInt(..), Number(n, ..)) =>
      // Checked here rather than truncated: a fixture that writes 2.5 into an
      // s32 field has said something it did not mean.
      if n == n.to_int().to_double() {
        n.to_int().to_string()
      } else {
        raise bad("\{n}, which is not a whole number")
      }
    (TOption(_), Null) => "None"
    (TOption(inner), _) => "Some(" + lit_of(def, inner, v, state, field) + ")"
    (TList(e), Array(items)) =>
      "[" + items.map(x => lit_of(def, e, x, state, field)).join(", ") + "]"
    (TSet, Array(items)) | (TFlags(_), Array(items)) => {
      // A set arrives as its member list and is stored Map-backed, which is
      // how the runtime holds every set.
      let entries = items.map(x => {
        match x {
          String(s) => json_quote(s) + ": true"
          _ => ""
        }
      })
      "Map([" + entries.filter(e => e != "").join(", ") + "])"
    }
    (TOMap(inner), Object(o)) => {
      let entries : Array[String] = []
      for k, x in o {
        entries.push(json_quote(k) + ": " + lit_of(def, inner, x, state, field))
      }
      "Map([" + entries.join(", ") + "])"
    }
    (TRecord(n), Object(o)) =>
      match def.user_ty(n) {
        Some({ name, kind: URecord(fs), .. }) => {
          let parts : Array[String] = []
          for sub in fs {
            let jv = match o.get(sub.name) {
              Some(x) => x
              None => o.get(sub.name).unwrap_or(Json::null())
            }
            parts.push(
              sub.binding + ": " + lit_of(def, sub.ty, jv, state, field),
            )
          }
          name + "::{ " + parts.join(", ") + " }"
        }
        _ => raise bad("an object")
      }
    (TEnum(n), String(s)) =>
      match def.user_ty(n) {
        Some({ name, kind: UEnum(cs), .. }) => {
          for c in cs {
            if c.0 == s || camel_name(c.0) == s {
              return name + "::" + c.1
            }
          }
          raise bad("\"\{s}\", which is not one of its cases")
        }
        _ => raise bad("\"\{s}\"")
      }
    // The dynamic escape hatch takes whatever it is given, as a Value.
    (TAny, _) | (TComp(_), _) => "@tutuca.Value::from_json(\{json_src(v)})"
    (_, Null) => def.zero_expr(ty)
    _ => raise bad(json_shape(v))
  }
}

///|
/// What a JSON value IS, for the "but you wrote" half of a message.
fn json_shape(v : Json) -> String {
  match v {
    Null => "null"
    True | False => "a boolean"
    Number(_) => "a number"
    String(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
}

///|
/// A JSON value as MoonBit source that rebuilds it.
fn json_src(v : Json) -> String {
  match v {
    Null => "Json::null()"
    True => "Json::boolean(true)"
    False => "Json::boolean(false)"
    Number(n, ..) => "Json::number(\{n})"
    String(s) => "Json::string(\{json_quote(s)})"
    Array(items) =>
      "Json::array([" + items.map(x => json_src(x)).join(", ") + "])"
    Object(o) => {
      let parts : Array[String] = []
      for k, x in o {
        parts.push(json_quote(k) + ": " + json_src(x))
      }
      "Json::object({ " + parts.join(", ") + " })"
    }
  }
}

///|
/// These land in generated MoonBit source, so they are MoonBit string
/// literals like every other — `quote` is the one that spells them.
fn json_quote(s : String) -> String {
  quote(s)
}

///|
/// Every key a fixture may carry.
let init_keys : Array[String] = [
  "value", "doc", "view", "drive", "intents", "tags", "default",
]

///|
/// A string-valued envelope key, or "" when absent.
fn str_key(
  env : Map[String, Json],
  state : String,
  key : String,
) -> String raise InitError {
  match env.get(key) {
    None => ""
    Some(String(v)) => v
    Some(_) => raise BadKey(state~, key~, want="a string")
  }
}

///|
/// What a JSON value IS, for a message that says what was found as well as what
/// was wanted.
fn shape_of(j : Json) -> String {
  match j {
    Null => "null"
    True | False => "a boolean"
    Number(_) => "a number"
    String(_) => "a string"
    Array(_) => "a list"
    Object(_) => "an object"
  }
}
