///| JSON -> constructor arguments, validated against the declared schema.
///
/// The direction that matters for anything untrusted. A tool call arrives as
/// JSON a language model wrote, and a form submits JSON a person typed; both
/// have to become `Map[String, Value]` or fail with something the sender can
/// act on. "Something the sender can act on" is the whole design constraint
/// here: an error carries a JSON POINTER, so a form highlights one input and a
/// model is told which argument it got wrong rather than that the call failed.

///|
/// One thing wrong, at one place. `pointer` is RFC 6901 against the submitted
/// document — `/items/2/text`, not `items[2].text` — because that is the
/// spelling every other layer here already uses (the surface data model binds
/// by JSON Pointer, and AG-UI's state deltas are JSON Patch).
pub(all) struct SchemaError {
  pointer : String
  message : String
} derive(Eq, Debug)

///|
fn err(pointer : String, message : String) -> SchemaError {
  { pointer, message, }
}

///|
/// A child pointer. Keys containing `~` or `/` are escaped per RFC 6901, which
/// matters more here than it looks: a guest names its own fields, so a field
/// called `a/b` is a thing an untrusted manifest can produce.
fn join(pointer : String, key : String) -> String {
  let escaped = key
    .replace_all(old="~", new="~0")
    .replace_all(old="/", new="~1")
  "\{pointer}/\{escaped}"
}

///|
/// What a value IS, for an error message. `Value::to_display_string` renders
/// the content; this names the shape, which is what a type mismatch is about.
fn json_kind(j : Json) -> String {
  match j {
    Null => "null"
    True | False => "boolean"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
/// Decode one JSON value against one declared type, appending to `errors`.
///
/// Returns a `Value` even when it failed, so that one bad field does not stop
/// the other twelve from being checked — a form that reported its first error
/// and stopped would make a person fix a long list one round trip at a time.
/// The caller keys off `errors`, never off the return.
fn coerce_ty(
  j : Json,
  ty : @tutuca.TyInfo,
  pointer : String,
  errors : Array[SchemaError],
) -> @tutuca.Value {
  match (ty, j) {
    // `any` takes the document as it stands; there is nothing to check.
    (TyAny, _) => @tutuca.Value::from_json(j)
    (TyOption(_), Null) => Null
    (TyOption(e), _) => coerce_ty(j, e, pointer, errors)
    (TyBool, True) => Bool(true)
    (TyBool, False) => Bool(false)
    (TyFloat, Number(n, ..)) => Num(n)
    (TyInt(width=32, signed=true), Number(n, ..)) =>
      if n != n.trunc() {
        errors.push(err(pointer, "expected an integer, got \{n}"))
        Num(n.trunc())
      } else {
        Num(n)
      }
    (TyText, String(s)) => Str(s)
    (TyList(e), Array(items)) => {
      let out : Array[@tutuca.Value] = []
      for i, item in items {
        out.push(coerce_ty(item, e, join(pointer, i.to_string()), errors))
      }
      List(out)
    }
    (TyTuple(ts), Array(items)) => {
      if items.length() != ts.length() {
        errors.push(
          err(pointer, "expected \{ts.length()} items, got \{items.length()}"),
        )
      }
      let out : Array[@tutuca.Value] = []
      for i, t in ts {
        if i < items.length() {
          out.push(coerce_ty(items[i], t, join(pointer, i.to_string()), errors))
        } else {
          out.push(t.zero())
        }
      }
      List(out)
    }
    // A set arrives as an array (that is how a schema describes it) and is
    // held as a Map, which is the refinement `TySet`/`TyFlags` name.
    (TySet, Array(items)) | (TyFlags(_, _), Array(items)) => {
      let members = ty.members()
      let m : Map[String, @tutuca.Value] = Map([])
      for i, item in items {
        match item {
          String(s) => {
            if !members.is_empty() && !members.contains(s) {
              errors.push(
                err(
                  join(pointer, i.to_string()),
                  "not a member: \{s} (expected one of \{members.join(", ")})",
                ),
              )
            }
            m[s] = Bool(true)
          }
          _ =>
            errors.push(
              err(
                join(pointer, i.to_string()),
                "expected a string, got \{json_kind(item)}",
              ),
            )
        }
      }
      Map(m)
    }
    (TyOMap(v), Object(fields)) => {
      let m : Map[String, @tutuca.Value] = Map([])
      for k, item in fields {
        m[k] = coerce_ty(item, v, join(pointer, k), errors)
      }
      Map(m)
    }
    // A named record / enum / variant is a shape the declared schema knows the
    // NAME of and nothing more, so there is nothing here to check it against.
    // Taking it as-is is the honest answer: the guest's own decoder is what
    // knows the fields, and it will reject what this cannot.
    (TyRecord(_), _) | (TyEnum(_), _) | (TyVariant(_), _) =>
      @tutuca.Value::from_json(j)
    // A table is the exception to the paragraph above: it is a standard shape,
    // so this layer knows its fields and checks them — including the equal-width
    // rule, which no JSON Schema can state. See coerce_table.mbt.
    (TyTable, _) => coerce_table(j, pointer, errors)
    // A component slot is not filled from JSON. The reference is carried
    // through so the caller can resolve it (make-instance) and write the
    // instance in; refusing it here would make an object schema that advertises
    // a componentRef unusable.
    (TyComp(_), _) => @tutuca.Value::from_json(j)
    _ => {
      errors.push(
        err(pointer, "expected \{ty.show_source()}, got \{json_kind(j)}"),
      )
      ty.zero()
    }
  }
}

///|
/// Check one already-decoded value against the half its type cannot state.
///
/// Separate from `coerce_ty` because the two answer different questions —
/// "is this the right shape" and "is this an acceptable one" — and only the
/// first has a fallback. A value that is the right shape and out of range is
/// returned unchanged, with the complaint recorded.
///
/// The bounds are DOMAINS, and `domain_holds` is what says whether one holds.
/// What this adds is the sentence: the runtime's own refusal names the field
/// and the state it was written into, and a schema error names a JSON pointer
/// and what the caller should have sent.
fn check_domains(
  v : @tutuca.Value,
  ty : @tutuca.Ty,
  domains : Array[@tutuca.Domain],
  pointer : String,
  errors : Array[SchemaError],
) -> Unit {
  // A "length" is characters on text and elements on a collection; the type
  // decides which, so the message can say which.
  let unit = match v {
    Str(_) => "characters"
    List(_) => "items"
    Map(_) => "entries"
    _ => ""
  }
  for d in domains {
    if !d.applies_to(ty) {
      continue
    }
    // Against an EMPTY field map: a schema check has one value in hand and no
    // state around it, so a domain that reads a sibling field cannot be
    // answered here — and `domain_holds` answers `true` for one it cannot
    // read, which is the same "unknown is not wrong" the runtime follows.
    if @tutuca.domain_holds(d, v, Map([])) {
      continue
    }
    errors.push(err(pointer, domain_complaint(d, v, unit)))
  }
}

///|
/// How long a value is, in the unit its shape implies.
fn length_of(v : @tutuca.Value) -> Int {
  match v {
    Str(s) => s.char_length()
    List(items) => items.length()
    Map(m) => m.length()
    _ => 0
  }
}

///|
/// What to tell the sender about a domain their value broke.
fn domain_complaint(
  d : @tutuca.Domain,
  v : @tutuca.Value,
  unit : String,
) -> String {
  let got = v.to_display_string()
  fn side(op : @tutuca.DomainOp, n : Double) -> String {
    match op {
      DGe => "at least \{n}"
      DGt => "greater than \{n}"
      DLe => "at most \{n}"
      DLt => "less than \{n}"
    }
  }

  match d {
    DCompare(op~, rhs=DLit(n)) => "must be \{side(op, n)}, got \{got}"
    DBetween(lo=DLit(a), hi=DLit(b)) =>
      "must be between \{a} and \{b}, got \{got}"
    DLen(DCompare(op~, rhs=DLit(n))) =>
      "must have \{side(op, n)} \{unit}, got \{length_of(v)}"
    DLen(DBetween(lo=DLit(a), hi=DLit(b))) =>
      "must have between \{a} and \{b} \{unit}, got \{length_of(v)}"
    DNonEmpty => "must not be empty"
    DOneOf(allowed) => {
      let shown = allowed.map(a => a.to_display_string()).join(", ")
      "must be one of \{shown}"
    }
    // Everything else keeps the runtime's own sentence, which names the fields
    // it read — there is one place that composes those and this is not a
    // second one.
    _ =>
      @tutuca.broken_domain_sentence({ field: "value", domain: d, }, {
        "value": v,
      })
  }
}

///|
/// Decode a JSON object into constructor arguments for `schema`.
///
/// Errors are collected rather than raised, and an empty array is the only
/// signal of success. Two rules that are decisions rather than details:
///
/// - An UNDECLARED key is an error. A schema is what a caller was shown, so a
///   key outside it is either a typo or a misunderstanding, and both are worth
///   saying. (The emitted schema stays open, because a constructor may take
///   more than the declared fields — this is the stricter of the two on
///   purpose, since it has a name to complain about.)
/// - A missing OPTIONAL field is simply absent from the result, not filled with
///   its zero. The constructor decides what an unsupplied field means, and
///   handing it a zero would take that decision away.
pub fn coerce(
  schema : @tutuca.SchemaInfo,
  j : Json,
  docs? : Map[String, FieldDoc] = Map([]),
) -> Result[Map[String, @tutuca.Value], Array[SchemaError]] {
  let errors : Array[SchemaError] = []
  guard j is Object(fields) else {
    return Err([err("", "expected an object, got \{json_kind(j)}")])
  }
  let out : Map[String, @tutuca.Value] = Map([])
  for f in schema.fields {
    let fd = docs.get(f.name).unwrap_or(FieldDoc::none())
    match fields.get(f.name) {
      Some(fj) => {
        let pointer = join("", f.name)
        let v = coerce_ty(fj, f.ty, pointer, errors)
        check_domains(v, f.ty, fd.domains, pointer, errors)
        out[f.name] = v
      }
      None =>
        if is_required(f, fd) {
          errors.push(err(join("", f.name), "required"))
        }
    }
  }
  let declared = schema.field_names()
  for k, _ in fields {
    if !declared.contains(k) {
      errors.push(err(join("", k), "no such field"))
    }
  }
  if errors.is_empty() {
    Ok(out)
  } else {
    Err(errors)
  }
}
