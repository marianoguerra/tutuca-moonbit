// Emitting direct state <-> Value codecs.
//
// The runtime used to bridge typed state to the Value world through JSON:
// `S -> Json -> Value` on the way in and back on the way out, once per state
// write. This replaced it, and then it was deleted — so what follows is not an
// optimization over a fallback, it is the only conversion there is.
//
// With the schema in hand the conversion is written out field by field, with
// no intermediate `Json` object. The interesting part was never the allocation
// saved but the fields that need NO conversion at all: an `any` or a
// child-slot field already holds a `@tutuca.Value`, and those cannot survive a
// JSON round trip — the bridge kept a process-global stash of them purely to
// smuggle them across. A direct codec never sends them through one.
//
// Emitted for EVERY schema-backed component. It used to be emitted only for
// the ones whose fields all had a direct form, which left the JSON bridge as
// the answer for the rest — and a fallback that some components still need is
// a fallback that cannot be deleted. The shapes below therefore cover the
// whole `StateTy` lattice, `record` / `enum` / `variant` / `option` / `tuple`
// included.
//
// The encodings were read off `derive(ToJson)` rather than invented, because
// while the JSON bridge still existed the two paths had to agree. The bridge
// is gone and the state struct derives nothing now, so these ARE the shapes —
// what a view reads is defined here:
//
//   record   {"title": …, "done": …}     keyed by MoonBit field name
//   enum     "Blue"                      the MoonBit case name
//   variant  "Ping" | ["SetTo", 7]       bare name, or name-then-payload
//   option   the value, or NO KEY AT ALL for None
//   tuple    [1, "a"]
//
// Adopting the direct codec was gated on a measurement, because a second
// encoder has to be kept in step with the derived one:
// benchmarks/codec_bench_test.mbt puts encode at ~2x and decode at ~5x,
// decode gaining most because the JSON path rebuilds a whole `Json` object
// just to hand it to `from_json`.

///|
/// Whether this component gets a direct codec at all.
///
/// Every schema-backed component does — this answers `true` for the whole
/// `StateTy` lattice and exists only so an unhandled shape fails loudly here
/// rather than emitting code that does not compile.
///
/// A state with NO carried fields gets one too. It looks pointless — the codec
/// is `Map([])` and `Some(State::{})` — but "pointless" is the argument FOR
/// emitting it: the runtime's only alternative is the JSON bridge, and a
/// component reaching for the bridge to convert nothing is the bridge
/// justifying its own existence. 14 of the corpus's 93 components are in that
/// shape (an empty `record state`, or one whose every field is a `component`
/// slot, which `in_struct` excludes), and each was a reason it could not go.
fn has_direct_codec(def : @statedef.StateDef) -> Bool {
  def.fields.iter().filter(f => f.ty.in_struct()).all(f => direct(def, f.ty))
}

///|
/// True when a type has a direct Value form. Recursive, because a
/// `list<card>` is only as direct as `card` is.
fn direct(def : @statedef.StateDef, ty : @statedef.StateTy) -> Bool {
  match ty {
    TBool | TInt(..) | TFloat | TText | TAny | TSet | TFlags(_) | TComp(_) =>
      true
    TList(e) | TOMap(e) | TOption(e) => direct(def, e)
    TTuple(ts) => ts.iter().all(t => direct(def, t))
    // A named type is direct when it resolves and its own parts are. An
    // unresolved name falls back to @tutuca.Value (see moonbit_ty), which is
    // direct by definition.
    TRecord(n) | TEnum(n) | TVariant(n) =>
      match def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) => fs.iter().all(f => direct(def, f.ty))
        Some({ kind: UVariant(cs), .. }) =>
          cs.iter().all(c => c.payload.iter().all(p => direct(def, p)))
        // an enum is payload-free, and flags are Map-backed
        Some(_) | None => true
      }
  }
}

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
          "/// The `\{ty.wit_name}` record as a `@tutuca.Value`.\n" +
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
          "/// The `\{ty.wit_name}` record back out. None on a shape mismatch.\n" +
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
        out.write_string("  Some(\{ty.name}::{\n")
        for f in fields {
          out.write_string("    \{f.binding}: f_\{f.binding},\n")
        }
        out.write_string("  })\n}\n\n")
      }
      UEnum(cases) => {
        out.write_string(
          "///|\n" +
          "/// The `\{ty.wit_name}` enum as a `@tutuca.Value`: the case name.\n" +
          "fn \{base}_to_value(x : \{ty.name}) -> @tutuca.Value {\n" +
          "  match x {\n",
        )
        for c in cases {
          out.write_string("    \{c.1} => Str(\{quote(c.1)})\n")
        }
        out.write_string("  }\n}\n\n")
        out.write_string(
          "///|\n" +
          "/// The `\{ty.wit_name}` enum back out. None on an unknown case.\n" +
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
          "/// The `\{ty.wit_name}` variant as a `@tutuca.Value`: the bare case\n" +
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
          "/// The `\{ty.wit_name}` variant back out. None on an unknown case or\n" +
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
      // needs no converter of its own — the structural TSet/TFlags arms
      // below carry it.
      UFlags(_) => ()
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
  guard has_direct_codec(def) else { return }
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
  let has_optional = carried.iter().any(f => f.ty is TOption(_))
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
        TOption(inner) =>
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
  out.write_string("  Some(\{t}State::{\n")
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
fn enc_expr(
  def : @statedef.StateDef,
  ty : @statedef.StateTy,
  e : String,
) -> String {
  match ty {
    TBool => "Bool(\{e})"
    TInt(..) => "Num(\{e}.to_double())"
    TFloat => "Num(\{e})"
    TText => "Str(\{e})"
    // Already a Value. This is the case the JSON path cannot do at all
    // without the stash.
    TAny | TComp(_) => e
    TList(inner) =>
      "(List(\{e}.map(x => \{enc_expr(def, inner, "x")})) : @tutuca.Value)"
    TSet | TFlags(_) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, b in \{e} { m[k] = Bool(b) }; (Map(m) : @tutuca.Value) }"
    TOMap(inner) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, x in \{e} { m[k] = \{enc_expr(def, inner, "x")} }; (Map(m) : @tutuca.Value) }"
    // Nested (inside a list, a map, a record): there is no key to omit here,
    // so None becomes Null. The key-omitting form is at the state level.
    TOption(inner) =>
      "(match \{e} { Some(x) => \{enc_expr(def, inner, "x")}; None => Null })"
    TTuple(ts) => {
      let parts = ts.mapi((i, t) => enc_expr(def, t, "\{e}.\{i}")).join(", ")
      "(List([\{parts}]) : @tutuca.Value)"
    }
    TRecord(n) | TEnum(n) | TVariant(n) =>
      match def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) if fs.is_empty() => e
        Some(ut) => "\{uty_fn(ut)}_to_value(\{e})"
        // unresolved: moonbit_ty made it a @tutuca.Value, so it already is one
        None => e
      }
  }
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
  ty : @statedef.StateTy,
  src : String,
  name : String,
  base : String,
  depth : Int,
) -> String {
  let pad = "  ".repeat(depth)
  let tmp = "t\{depth}_\{base}"
  match ty {
    // Absent reads as Null, which is what an unset `any` field holds anyway.
    TAny | TComp(_) => "\{pad}let \{name} = \{src}.unwrap_or(Null)\n"
    // The absent key IS None — the encoder omits it rather than writing null,
    // and a nested Null means the same thing.
    TOption(inner) =>
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = match \{src} {\n" +
      "\{pad}  None | Some(Null) => None\n" +
      "\{pad}  Some(\{tmp}) => {\n" +
      dec_val(def, inner, tmp, "x\{depth}_\{base}", base, depth + 2) +
      "\{pad}    Some(x\{depth}_\{base})\n" +
      "\{pad}  }\n" +
      "\{pad}}\n"
    // A scalar's pattern nests inside the `Some`, so it reads (and unwraps) in
    // one guard rather than two.
    TBool => "\{pad}guard \{src} is Some(Bool(\{name})) else { return None }\n"
    TFloat => "\{pad}guard \{src} is Some(Num(\{name})) else { return None }\n"
    TText => "\{pad}guard \{src} is Some(Str(\{name})) else { return None }\n"
    TInt(..) =>
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
  ty : @statedef.StateTy,
  src : String,
  name : String,
  base : String,
  depth : Int,
) -> String {
  let pad = "  ".repeat(depth)
  let tmp = "u\{depth}_\{base}"
  match ty {
    TAny | TComp(_) => "\{pad}let \{name} = \{src}\n"
    TBool => "\{pad}guard \{src} is Bool(\{name}) else { return None }\n"
    TFloat => "\{pad}guard \{src} is Num(\{name}) else { return None }\n"
    TText => "\{pad}guard \{src} is Str(\{name}) else { return None }\n"
    TInt(..) =>
      "\{pad}guard \{src} is Num(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} = \{tmp}.to_int()\n"
    TList(inner) =>
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
    TSet | TFlags(_) =>
      "\{pad}guard \{src} is Map(\{tmp}) else { return None }\n" +
      "\{pad}let \{name} : Map[String, Bool] = Map([])\n" +
      "\{pad}for k, x in \{tmp} {\n" +
      "\{pad}  \{name}[k] = x is Bool(true)\n" +
      "\{pad}}\n"
    TOMap(inner) =>
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
    TOption(inner) =>
      "\{pad}let \{name} : \{def.moonbit_ty(ty)} = match \{src} {\n" +
      "\{pad}  Null => None\n" +
      "\{pad}  \{tmp} => {\n" +
      dec_val(def, inner, tmp, "x\{depth}_\{base}", base, depth + 2) +
      "\{pad}    Some(x\{depth}_\{base})\n" +
      "\{pad}  }\n" +
      "\{pad}}\n"
    TTuple(ts) => {
      let sb = StringBuilder::new()
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
    TRecord(n) | TEnum(n) | TVariant(n) =>
      match def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) if fs.is_empty() =>
          "\{pad}let \{name} = \{src}\n"
        Some(ut) =>
          "\{pad}guard \{uty_fn(ut)}_of_value(\{src}) is Some(\{name}) else { return None }\n"
        None => "\{pad}let \{name} = \{src}\n"
      }
  }
}
