// Named initial states, validated against the schema.
//
// A default is a value rather than a type, so it must not be smuggled into the
// schema through a comment convention. It gets a block of its own:
//
//   <script type="tutuca/init">
//   { "fresh": {}, "with-history": { "count": 3, "history": [1, 2, 3] } }
//   </script>
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
    guard states.get(name) is Some(Object(fields)) else {
      raise StateNotObject(name)
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
    out.push({ name, ident: camel_name(name), fields: set, args })
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
/// literals like every other — `quote` is the one that spells them. The copy
/// that used to live here escaped `"`, `\` and `\n` only, so a default
/// carrying a tab emitted a literal tab into the module.
fn json_quote(s : String) -> String {
  quote(s)
}
