// Emitting direct state <-> Value codecs.
//
// With the schema in hand the conversion is written out field by field, with
// no intermediate `Json` object. The interesting part is not the allocation
// saved but the fields that need NO conversion at all: an `any` or a
// child-slot field already holds a `@tutuca.Value`, and a direct codec never
// sends it through one.
//
// Emitted for EVERY schema-backed component. The shapes below cover the
// whole `@tutuca.Ty` lattice, `record` / `enum` / `variant` / `option` / `tuple`
// included.
//
// The state struct derives nothing, so these ARE the shapes — what a view
// reads is defined here:
//
//   record   {"title": …, "done": …}     keyed by MoonBit field name
//   enum     "Blue"                      the MoonBit case name
//   variant  "Ping" | ["SetTo", 7]       bare name, or name-then-payload
//   option   the value, or NO KEY AT ALL for None
//   tuple    [1, "a"]

// ---------------------------------------------------------------------------
// Converters for the named types, emitted once each
// ---------------------------------------------------------------------------

///|
/// The base name of the pair of converters for a user type: `counter_card`.
///
/// Derived from `ty.name`, which the emitter already component-prefixed
/// (`CounterCard`) to keep named types from colliding across the components
/// sharing a module — so prefixing again here would only stutter.
fn uty_fn(ty : @statedef.UserTy) -> String {
  value_prefix(ty.name)
}

///|
/// `<v>_<ty>_to_value` / `<v>_<ty>_of_value` for every named type the state
/// mentions.
///
/// Functions rather than inlined expressions because a record can nest, and a
/// converter that can call itself is the only shape that terminates on a type
/// graph rather than on a fixed depth.
fn emit_user_codecs(def : @statedef.StateDef, out : StringBuilder) -> Unit {
  for ty in def.types {
    let base = uty_fn(ty)
    match ty.kind {
      // A transparent alias: it named a marker and emitted no MoonBit type,
      // so there is nothing to convert to or from.
      URecord(fields) if fields.is_empty() => continue
      URecord(fields) => {
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` record as a `@tutuca.Value`.\n" +
          "fn \{base}_to_value(x : \{ty.name}) -> @tutuca.Value {\n" +
          "  Map({\n",
        )
        for f in fields {
          out.write_string(
            "    \{quote(f.name)}: \{enc_expr(def, f.ty, "x." + f.binding)},\n",
          )
        }
        out.write_string("  })\n}\n\n")
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` record back out. None on a shape mismatch.\n" +
          "fn \{base}_of_value(v : @tutuca.Value) -> \{ty.name}? {\n" +
          "  guard v is Map(m) else { return None }\n",
        )
        for f in fields {
          out.write_string(
            dec_stmts(
              def,
              f.ty,
              "m.get(\{quote(f.name)})",
              "f_" + f.binding,
              f.binding,
              2,
            ),
          )
        }
        // `\{ty.name}?` return type, so the name is inferable — see the state
        // decoder for why spelling it is a warning.
        out.write_string("  Some({\n")
        for f in fields {
          out.write_string("    \{f.binding}: f_\{f.binding},\n")
        }
        out.write_string("  })\n}\n\n")
      }
      UEnum(cases) => {
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` enum as a `@tutuca.Value`: the case name.\n" +
          "fn \{base}_to_value(x : \{ty.name}) -> @tutuca.Value {\n" +
          "  match x {\n",
        )
        for c in cases {
          out.write_string("    \{c.1} => Str(\{quote(c.1)})\n")
        }
        out.write_string("  }\n}\n\n")
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` enum back out. None on an unknown case.\n" +
          "fn \{base}_of_value(v : @tutuca.Value) -> \{ty.name}? {\n" +
          "  guard v is Str(s) else { return None }\n" +
          "  match s {\n",
        )
        for c in cases {
          out.write_string("    \{quote(c.1)} => Some(\{c.1})\n")
        }
        out.write_string("    _ => None\n  }\n}\n\n")
      }
      UVariant(cases) => {
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` variant as a `@tutuca.Value`: the bare case\n" +
          "/// name when it carries nothing, else the name followed by its\n" +
          "/// payload.\n" +
          "fn \{base}_to_value(x : \{ty.name}) -> @tutuca.Value {\n" +
          "  match x {\n",
        )
        for c in cases {
          if c.payload.is_empty() {
            out.write_string("    \{c.variant} => Str(\{quote(c.variant)})\n")
          } else {
            let binds = c.payload.mapi((i, _) => "p\{i}").join(", ")
            let parts = c.payload
              .mapi((i, p) => enc_expr(def, p, "p\{i}"))
              .join(", ")
            out.write_string(
              "    \{c.variant}(\{binds}) => List([Str(\{quote(c.variant)}), \{parts}])\n",
            )
          }
        }
        out.write_string("  }\n}\n\n")
        out.write_string(
          "///|\n" +
          "/// The `\{ty.source_name}` variant back out. None on an unknown case or\n" +
          "/// a payload that does not match the declared shape.\n" +
          "fn \{base}_of_value(v : @tutuca.Value) -> \{ty.name}? {\n",
        )
        // payload-free cases arrive as a bare string
        out.write_string("  if v is Str(s) {\n    match s {\n")
        for c in cases {
          if c.payload.is_empty() {
            out.write_string(
              "      \{quote(c.variant)} => return Some(\{c.variant})\n",
            )
          }
        }
        out.write_string("      _ => return None\n    }\n  }\n")
        out.write_string("  guard v is List(items) else { return None }\n")
        out.write_string(
          "  guard items.get(0) is Some(Str(tag)) else { return None }\n",
        )
        out.write_string("  match tag {\n")
        for c in cases {
          if !c.payload.is_empty() {
            out.write_string("    \{quote(c.variant)} => {\n")
            for i, p in c.payload {
              out.write_string(
                dec_stmts(def, p, "items.get(\{i + 1})", "a\{i}", "a\{i}", 3),
              )
            }
            let args = c.payload.mapi((i, _) => "a\{i}").join(", ")
            out.write_string("      Some(\{c.variant}(\{args}))\n    }\n")
          }
        }
        out.write_string("    _ => None\n  }\n}\n\n")
      }
      // A `flags` set is Map-backed at runtime like any other set, so it
      // needs no converter of its own — the structural TySet/TyFlags arms
      // below carry it.
    }
  }
}

// ---------------------------------------------------------------------------
// The state codec
// ---------------------------------------------------------------------------

///|
/// `<v>_encode` / `<v>_decode`, plus a converter for every named type they
/// reach.
fn emit_codec(
  t : String,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  emit_user_codecs(def, out)
  let carried = def.fields.filter(f => f.ty.in_struct())
  // With nothing to read off the state, the parameters go unused — and an
  // unused binding is a warning, so they are named for it.
  let (s_param, f_param) = if carried.is_empty() {
    ("_s", "_f")
  } else {
    ("s", "f")
  }
  // `option` is the one shape whose ABSENCE is the encoding: None omits the
  // key rather than writing null, so a state carrying one cannot be a map
  // literal and is built by insertion instead.
  let has_optional = carried.iter().any(f => f.ty is TyOption(_))
  out.write_string(
    "///|\n" +
    "/// The state as the fields map the render and path layers read, built\n" +
    "/// field by field rather than through a `Json` round trip.\n" +
    "///\n" +
    "/// A field that already holds a `@tutuca.Value` is passed straight\n" +
    "/// through. That is the case a JSON round trip could not do at all: an\n" +
    "/// `Obj` or an `Fn` does not survive one.\n" +
    "impl @component.Fields for \{t}State with fn encode(\{s_param}) {\n",
  )
  if carried.is_empty() {
    // `{}` at this position reads as an empty STRUCT literal, not a map.
    out.write_string("  Map([])\n")
  } else if has_optional {
    out.write_string("  let out : Map[String, @tutuca.Value] = Map([])\n")
    for f in carried {
      match f.ty {
        TyOption(inner) =>
          out.write_string(
            "  match s.\{f.binding} {\n" +
            "    Some(x) => out[\{quote(f.name)}] = \{enc_expr(def, inner, "x")}\n" +
            "    None => ()\n" +
            "  }\n",
          )
        _ =>
          out.write_string(
            "  out[\{quote(f.name)}] = \{enc_expr(def, f.ty, "s." + f.binding)}\n",
          )
      }
    }
    out.write_string("  out\n")
  } else {
    out.write_string("  {\n")
    for f in carried {
      out.write_string(
        "    \{quote(f.name)}: \{enc_expr(def, f.ty, "s." + f.binding)},\n",
      )
    }
    out.write_string("  }\n")
  }
  out.write_string("}\n\n")
  out.write_string(
    "///|\n" +
    "/// The fields map back into the state. None on a shape mismatch, which\n" +
    "/// callers treat as a no-op write — the same contract as the JSON path.\n" +
    "impl @component.Fields for \{t}State with fn decode(\{f_param}) {\n",
  )
  for f in carried {
    out.write_string(
      dec_stmts(
        def,
        f.ty,
        "f.get(\{quote(f.name)})",
        "v_" + f.binding,
        f.binding,
        1,
      ),
    )
  }
  // `Some(...)` against a `\{t}State?` return type, so the struct name is
  // inferable and spelling it is `unnecessary_annotation`. The field-less
  // state has no usable literal at all (see `emit_state_struct`) and goes
  // through its derived `Default::default()` — through the trait, since the
  // `\{t}State::default()` spelling is a deprecated implicit promotion.
  if carried.is_empty() {
    out.write_string("  Some(Default::default())\n}\n\n")
    return
  }
  out.write_string("  Some({\n")
  for f in carried {
    out.write_string("    \{f.binding}: v_\{f.binding},\n")
  }
  out.write_string("  })\n}\n\n")
}

// ---------------------------------------------------------------------------
// Encoding: a MoonBit expression of type @tutuca.Value
// ---------------------------------------------------------------------------

///|
/// A field as a `@tutuca.Value`.
///
/// One line, because the projection is `statedef`'s: the script backend writes
/// the same conversion wherever a typed expression meets a builtin or a
/// channel payload, and two implementations would disagree about a set or a
/// nested record long before anyone noticed.
fn enc_expr(def : @statedef.StateDef, ty : @tutuca.Ty, e : String) -> String {
  def.to_value_src(ty, e)
}

// ---------------------------------------------------------------------------
// Decoding: statements that bind `name`, or `return None`
// ---------------------------------------------------------------------------

///|
/// Statements binding `name` to the decoded value of `src`, where `src` is a
/// `@tutuca.Value?` — a `Map::get` or an `Array::get`.
///
/// Only two shapes care about the difference between "absent" and "present but
/// Null": `any`, whose absence is just Null, and `option`, whose absence IS the
/// None. Everything else wants a plain value, so it unwraps once here and
/// recurses through `dec_val` — which is what keeps the emitted source free of
/// `guard Some(x) is Some(y)`.
fn dec_stmts(
  def : @statedef.StateDef,
  ty : @tutuca.Ty,
  src : String,
  name : String,
  base : String,
  depth : Int,
) -> String {
  let pad = "  ".repeat(depth)
  let tmp = "t\{depth}_\{base}"
  match ty {
    // Absent reads as Null, which is what an unset `any` field holds anyway.
    TyAny | TyComp(_) => "\{pad}let \{name} = \{src}.unwrap_or(Null)\n"
    // The absent key IS None — the encoder omits it rather than writing null,
    // and a nested Null means the same thing.
    TyOption(inner) =>
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = match \{src} {\n" +
      "\{pad}  None | Some(Null) => None\n" +
      "\{pad}  Some(\{tmp}) => {\n" +
      dec_val(def, inner, tmp, "x\{depth}_\{base}", base, depth + 2) +
      "\{pad}    Some(x\{depth}_\{base})\n" +
      "\{pad}  }\n" +
      "\{pad}}\n"
    // A scalar's pattern nests inside the `Some`, so it reads (and unwraps) in
    // one guard rather than two.
    TyBool => "\{pad}guard \{src} is Some(Bool(\{name})) else { return None }\n"
    TyFloat => "\{pad}guard \{src} is Some(Num(\{name})) else { return None }\n"
    TyText => "\{pad}guard \{src} is Some(Str(\{name})) else { return None }\n"
    TyInt(..) =>
      "\{pad}guard \{src} is Some(Num(\{tmp})) else { return None }\n" +
      "\{pad}let \{name} = \{tmp}.to_int()\n"
    _ =>
      "\{pad}guard \{src} is Some(\{tmp}) else { return None }\n" +
      dec_val(def, ty, tmp, name, base, depth)
  }
}

///|
/// Statements binding `name` to the decoded value of `src`, where `src` is a
/// plain `@tutuca.Value`.
///
/// Mismatches `return None` out of the whole enclosing converter, which is
/// exactly the contract: a fields map that does not fit the state decodes to
/// nothing, and the caller treats that as a no-op write.
///
/// `depth` is the indent level, and doubles as the source of unique temporary
/// names: a nested list's element binding cannot collide with its parent's.
fn dec_val(
  def : @statedef.StateDef,
  ty : @tutuca.Ty,
  src : String,
  name : String,
  base : String,
  depth : Int,
) -> String {
  let pad = "  ".repeat(depth)
  let tmp = "u\{depth}_\{base}"
  match ty {
    // A table is a `Value` with a known shape and no MoonBit type, so it
    // decodes the way `Any` does: it is already what it will be stored as.
    TyAny | TyComp(_) | TyCompProtocols(_) | TyTable =>
      "\{pad}let \{name} = \{src}\n"
    TyBool => "\{pad}guard \{src} is Bool(\{name}) else { return None }\n"
    TyFloat => "\{pad}guard \{src} is Num(\{name}) else { return None }\n"
    TyText => "\{pad}guard \{src} is Str(\{name}) else { return None }\n"
    TyInt(..) =>
      "\{pad}guard \{src} is Num(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} = \{tmp}.to_int()\n"
    TyList(inner) =>
      "\{pad}guard \{src} is List(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = []\n" +
      "\{pad}for e\{depth}_\{base} in \{tmp} {\n" +
      dec_val(
        def,
        inner,
        "e\{depth}_\{base}",
        "x\{depth}_\{base}",
        base,
        depth + 1,
      ) +
      "\{pad}  \{name}.push(x\{depth}_\{base})\n" +
      "\{pad}}\n"
    TySet | TyFlags(_, _) =>
      "\{pad}guard \{src} is Map(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} : Map[String, Bool] = Map([])\n" +
      "\{pad}for k, x in \{tmp} {\n" +
      "\{pad}  \{name}[k] = x is Bool(true)\n" +
      "\{pad}}\n"
    TyOMap(inner) =>
      "\{pad}guard \{src} is Map(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = Map([])\n" +
      "\{pad}for k, e\{depth}_\{base} in \{tmp} {\n" +
      dec_val(
        def,
        inner,
        "e\{depth}_\{base}",
        "x\{depth}_\{base}",
        base,
        depth + 1,
      ) +
      "\{pad}  \{name}[k] = x\{depth}_\{base}\n" +
      "\{pad}}\n"
    // Nested (inside a list, a map, a record): Null is the only spelling of
    // absence available, since there is no key to leave out.
    TyOption(inner) =>
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = match \{src} {\n" +
      "\{pad}  Null => None\n" +
      "\{pad}  \{tmp} => {\n" +
      dec_val(def, inner, tmp, "x\{depth}_\{base}", base, depth + 2) +
      "\{pad}    Some(x\{depth}_\{base})\n" +
      "\{pad}  }\n" +
      "\{pad}}\n"
    TyTuple(ts) => {
      let sb = StringBuilder()
      sb.write_string(
        "\{pad}guard \{src} is List(\{tmp}) else { return None }\n" +
        "\{pad}guard \{tmp}.length() == \{ts.length()} else { return None }\n",
      )
      for i, t in ts {
        sb.write_string(
          dec_stmts(
            def,
            t,
            "\{tmp}.get(\{i})",
            "e\{i}_\{base}",
            "\{i}_\{base}",
            depth,
          ),
        )
      }
      let parts = ts.mapi((i, _) => "e\{i}_\{base}").join(", ")
      sb.write_string("\{pad}let \{name} = (\{parts})\n")
      sb.to_string()
    }
    TyRecord(n) | TyEnum(n) | TyVariant(n) =>
      match def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) if fs.is_empty() =>
          "\{pad}let \{name} = \{src}\n"
        Some(ut) =>
          "\{pad}guard \{uty_fn(ut)}_of_value(\{src}) is Some(\{name}) else { return None }\n"
        None => "\{pad}let \{name} = \{src}\n"
      }
  }
}
