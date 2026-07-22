// Emitting the generated MoonBit module.
//
// Output style is chosen so `moon fmt` leaves the file alone: one `///|`
// block per declaration, multi-line view sources as `#|` raw-string blocks
// (a view is full of double quotes — escaping them into a normal literal
// would make the generated file unreadable and diff-noisy).
//
// Sections are skipped entirely when empty, because MoonBit has no empty
// enum: a file with no `$method` calls emits no Method type at all.

///|
/// A double-quoted MoonBit string literal.
fn quote(s : String) -> String {
  let sb = StringBuilder::new()
  sb.write_char('"')
  for c in s.to_array() {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A `pub let` holding view or style source. Multi-line text becomes a `#|`
/// block; empty or single-line text stays a quoted literal.
fn emit_string_let(
  out : StringBuilder,
  doc : String,
  name : String,
  text : String,
) -> Unit {
  out.write_string("///|\n/// \{doc}\n")
  if text.contains("\n") {
    out.write_string("pub let \{name} : String =\n")
    for line in text.split("\n") {
      out.write_string("  #|\{line}\n")
    }
  } else {
    out.write_string("pub let \{name} : String = \{quote(text)}\n")
  }
  out.write_string("\n")
}

///|
/// `pub enum <Type> { … }` plus a `name()` giving the source spelling back.
fn emit_name_enum(
  out : StringBuilder,
  doc : String,
  type_name : String,
  accessor : String,
  variants : Array[(String, String)],
) -> Unit {
  out.write_string("///|\n/// \{doc}\npub(all) enum \{type_name} {\n")
  for pair in variants {
    out.write_string("  \{pair.1}\n")
  }
  out.write_string("} derive(Eq, @debug.Debug)\n\n")
  out.write_string(
    "///|\npub fn \{type_name}::\{accessor}(self : \{type_name}) -> String {\n  match self {\n",
  )
  for pair in variants {
    out.write_string("    \{pair.1} => \{quote(pair.0)}\n")
  }
  out.write_string("  }\n}\n\n")
}

///|
fn arg_type_name(t : ArgType) -> String {
  match t {
    VDouble => "Double"
    VString => "String"
    VBool => "Bool"
    VValue => "@tutuca.Value"
  }
}

///|
/// The @core.Value pattern that binds a payload of this type.
fn arg_pattern(t : ArgType, binder : String) -> String {
  match t {
    VDouble => "Num(\{binder})"
    VString => "Str(\{binder})"
    VBool => "Bool(\{binder})"
    VValue => binder
  }
}

///|
/// The `Msg` variant payload for one input, and the match arm that decodes
/// it. `args: None` means the call sites disagreed on arity, so the variant
/// carries the raw argument list instead.
fn emit_msg_variant(
  out : StringBuilder,
  sig : InputSig,
  variant : String,
) -> Unit {
  let sites = sig.sites.join(", ")
  out.write_string("  /// `\{sites}=\"\{sig.name} …\"`\n")
  match sig.args {
    None => out.write_string("  \{variant}(Array[@tutuca.Value])\n")
    Some(types) =>
      if types.is_empty() {
        out.write_string("  \{variant}\n")
      } else {
        out.write_string(
          "  \{variant}(" + types.map(arg_type_name).join(", ") + ")\n",
        )
      }
  }
}

///|
fn emit_msg_arm(out : StringBuilder, sig : InputSig, variant : String) -> Unit {
  match sig.args {
    None =>
      out.write_string("    (\{quote(sig.name)}, _) => \{variant}(args)\n")
    Some(types) =>
      if types.is_empty() {
        out.write_string("    (\{quote(sig.name)}, []) => \{variant}\n")
      } else {
        let binders = types.mapi((i, _) => "a\{i}")
        let pats = types.mapi((i, t) => arg_pattern(t, binders[i]))
        out.write_string(
          "    (\{quote(sig.name)}, [" +
          pats.join(", ") +
          "]) => \{variant}(" +
          binders.join(", ") +
          ")\n",
        )
      }
  }
}

///|
/// One `$`-callable bucket builder: the user writes an exhaustive match over
/// the method enum, so a `$name` added to a view breaks the build until it is
/// answered.
fn emit_bucket(
  out : StringBuilder,
  type_name : String,
  fn_name : String,
  handler_type : String,
  doc : String,
  variants : Array[(String, String)],
) -> Unit {
  let all = variants.map(p => p.1).join(", ")
  out.write_string(
    "///|\n" +
    "/// \{doc}\n" +
    "/// Return None for a name another bucket serves, or one of the mutators\n" +
    "/// generated from the state's fields.\n" +
    "pub fn[S] \{fn_name}(\n" +
    "  f : (\{type_name}) -> (\{handler_type})?,\n" +
    ") -> Map[String, \{handler_type}] {\n" +
    "  let out : Map[String, \{handler_type}] = Map([])\n" +
    "  for m in ([\{all}] : Array[\{type_name}]) {\n" +
    "    match f(m) {\n" +
    "      Some(h) => out[m.name()] = h\n" +
    "      None => ()\n" +
    "    }\n" +
    "  }\n" +
    "  out\n" +
    "}\n\n",
  )
}

///|
pub fn emit_module(
  name : String,
  source_file : String,
  views : ViewSet,
  surface : Surface,
) -> String raise GenError {
  let t = type_prefix(name)
  let v = value_prefix(name)
  let out = StringBuilder::new()
  out.write_string(
    "// GENERATED by `tutuca gen-views` from \{source_file} — DO NOT EDIT.\n" +
    "// Regenerate with:\n" +
    "//\n" +
    "//   tutuca gen-views \{source_file} --name \{name} --out <dir>\n" +
    "//\n" +
    "// The package this file lives in must import:\n" +
    "//   \"marianoguerra/tutuca/core\" @tutuca, \"marianoguerra/tutuca/component\",\n" +
    "//   \"moonbitlang/core/debug\"\n" +
    "\n",
  )

  // -- views ---------------------------------------------------------------
  let view_variants = variants_for(views.views.map(view => view.name))
  emit_name_enum(
    out,
    "The views declared in \{source_file}.",
    "\{t}View",
    "name",
    view_variants,
  )
  for view in views.views {
    let vn = if view.name == "main" {
      "\{v}_main_view"
    } else {
      "\{v}_\{value_prefix(view.name)}_view"
    }
    let doc = if view.name == "main" {
      "The `main` view — pass as `view~` to @component.component."
    } else {
      "The `\{view.name}` view."
    }
    emit_string_let(out, doc, vn, view.source)
  }
  let others = views.views.filter(view => view.name != "main")
  out.write_string(
    "///|\n" +
    "/// The non-main views — pass as `views~` to @component.component.\n" +
    "pub fn \{v}_views() -> Map[String, String] {\n",
  )
  if others.is_empty() {
    out.write_string("  Map([])\n}\n\n")
  } else {
    out.write_string("  {\n")
    for view in others {
      out.write_string(
        "    \{quote(view.name)}: \{v}_\{value_prefix(view.name)}_view,\n",
      )
    }
    out.write_string("  }\n}\n\n")
  }

  // -- styles --------------------------------------------------------------
  let main_style = match views.views.filter(view => view.name == "main") {
    [m, ..] => m.style
    _ => ""
  }
  emit_string_let(
    out,
    "The `main` view's style — pass as `style~`.",
    "\{v}_style",
    main_style,
  )
  emit_string_let(
    out,
    "The file-level style — pass as `common_style~`.",
    "\{v}_common_style",
    views.common_style,
  )
  emit_string_let(
    out,
    "The `data-global` style — pass as `global_style~`.",
    "\{v}_global_style",
    views.global_style,
  )
  out.write_string(
    "///|\n" +
    "/// Per-view styles — pass as `view_styles~`.\n" +
    "pub fn \{v}_view_styles() -> Map[String, String] {\n",
  )
  let styled = others.filter(view => view.style != "")
  if styled.is_empty() {
    out.write_string("  Map([])\n}\n\n")
  } else {
    out.write_string("  {\n")
    for view in styled {
      out.write_string("    \{quote(view.name)}: \{quote(view.style)},\n")
    }
    out.write_string("  }\n}\n\n")
  }

  // -- inputs --------------------------------------------------------------
  if !surface.inputs.is_empty() {
    let input_variants = variants_for(surface.inputs.map(i => i.name))
    emit_name_enum(
      out,
      "Every bare `@on` handler name the views reference.",
      "\{t}Input",
      "name",
      input_variants,
    )
    out.write_string(
      "///|\npub fn \{t}Input::parse(s : String) -> \{t}Input? {\n  match s {\n",
    )
    for pair in input_variants {
      out.write_string("    \{quote(pair.0)} => Some(\{pair.1})\n")
    }
    out.write_string("    _ => None\n  }\n}\n\n")

    // The typed decode: this is the point of the whole generator.
    out.write_string(
      "///|\n" +
      "/// The Input arm of @component.Dispatch, decoded. Payload types are\n" +
      "/// inferred from the argument shapes written at the call sites, so a\n" +
      "/// handler added to \{source_file} breaks every `match` over this type\n" +
      "/// until it is handled.\n" +
      "pub(all) enum \{t}Msg {\n",
    )
    for i, sig in surface.inputs {
      emit_msg_variant(out, sig, input_variants[i].1)
    }
    out.write_string(
      "  /// An Input dispatch the views do not declare, or a declared name\n" +
      "  /// whose runtime arguments did not match the inferred shape.\n" +
      "  Unknown(String, Array[@tutuca.Value])\n" +
      // No derives: @tutuca.Value carries Fn and &Obj, so it is neither Eq
      // nor Debug, and a payload of it would make the derive fail.
      "}\n\n",
    )
    out.write_string(
      "///|\n" +
      "/// None for Receive / Bubble / Response — those names are raised by\n" +
      "/// component code, never written in a view, so the views cannot type them.\n" +
      "pub fn \{t}Msg::of_dispatch(d : @component.Dispatch) -> \{t}Msg? {\n" +
      "  guard d is Input(name, args) else { return None }\n" +
      "  Some(\n" +
      "    match (name, args) {\n",
    )
    for i, sig in surface.inputs {
      out.write_string("  ")
      emit_msg_arm(out, sig, input_variants[i].1)
    }
    out.write_string("      _ => Unknown(name, args)\n    },\n  )\n}\n\n")
  }

  // -- $-callables ---------------------------------------------------------
  if !surface.methods.is_empty() {
    let method_variants = variants_for(surface.methods)
    emit_name_enum(
      out,
      "Every `$name` the views call.",
      "\{t}Method",
      "name",
      method_variants,
    )
    emit_bucket(
      out,
      "\{t}Method",
      "\{v}_mutate",
      "(S, Array[@tutuca.Value]) -> S",
      "Build `mutate~` from an exhaustive match over the names the views call.",
      method_variants,
    )
    emit_bucket(
      out,
      "\{t}Method",
      "\{v}_compute",
      "(S, Array[@tutuca.Value]) -> @tutuca.Value",
      "Build `compute~` from an exhaustive match over the names the views call.",
      method_variants,
    )
    emit_bucket(
      out,
      "\{t}Method",
      "\{v}_swap",
      "(S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?",
      "Build `swap~` from an exhaustive match over the names the views call.",
      method_variants,
    )
  }

  // -- fields --------------------------------------------------------------
  out.write_string(
    "///|\n" +
    "/// State fields the views read at a view's ROOT scope. Reads under an\n" +
    "/// @each, an @enrich-with, a push-view or an <x render> address the loop\n" +
    "/// item or the child component, not this state, so they are not listed.\n" +
    "pub let \{v}_fields : Array[String] = [" +
    surface.fields.map(quote).join(", ") +
    "]\n\n",
  )
  out.write_string(
    "///|\n" +
    "/// The fields in `\{v}_fields` that `s` does not carry — assert this is\n" +
    "/// empty in a test. Fields the component declares through `specs~` rather\n" +
    "/// than through its state struct go in `extra~`.\n" +
    "pub fn[S : ToJson] \{v}_missing_fields(\n" +
    "  s : S,\n" +
    "  extra? : Array[String] = [],\n" +
    ") -> Array[String] {\n" +
    "  let present : Map[String, Bool] = Map([])\n" +
    "  if s.to_json() is Object(o) {\n" +
    "    for k, _ in o {\n" +
    "      present[k] = true\n" +
    "    }\n" +
    "  }\n" +
    "  for k in extra {\n" +
    "    present[k] = true\n" +
    "  }\n" +
    "  \{v}_fields.filter(f => !present.contains(f))\n" +
    "}\n\n",
  )

  // -- element ids ---------------------------------------------------------
  if !surface.ids.is_empty() {
    let id_variants = variants_for(surface.ids)
    emit_name_enum(
      out,
      "Constant `id` attributes in the views — typed selectors for tests.",
      "\{t}Id",
      "id",
      id_variants,
    )
    out.write_string(
      "///|\n" +
      "/// The `#id` CSS selector for this element.\n" +
      "pub fn \{t}Id::selector(self : \{t}Id) -> String {\n" +
      "  \"#\" + self.id()\n" +
      "}\n",
    )
  }
  out.to_string()
}

///|
pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError {
  let views = split_views(source)
  let surface = view_surface(views.views)
  emit_module(name, source_file, views, surface)
}
