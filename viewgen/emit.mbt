// Emitting the generated MoonBit module.
//
// The output is valid but UNFORMATTED MoonBit: `moon fmt` owns the layout,
// and the `gen-views` dev task runs it right after generating. Emitting
// fmt-identical text would mean reimplementing its width-based line breaking.
// What this file does control is structure — one `///|` block per
// declaration, and multi-line view sources as `#|` raw-string blocks (a view
// is full of double quotes; escaping them into a normal literal would make
// the generated file unreadable and diff-noisy).
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
  derives : String,
) -> Unit {
  out.write_string("///|\n/// \{doc}\npub(all) enum \{type_name} {\n")
  for pair in variants {
    out.write_string("  \{pair.1}\n")
  }
  out.write_string("} derive(\{derives})\n\n")
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
/// One component's section of the generated types module.
fn emit_component(
  name : String,
  source_file : String,
  views : ViewSet,
  surface : Surface,
  debug_derive : Bool,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(name)
  let v = value_prefix(name)
  // The playground compiles the generated module inside a package with no
  // moon.pkg to import moonbitlang/core/debug from, so it asks for Eq alone.
  let derives = if debug_derive { "Eq, @debug.Debug" } else { "Eq" }

  // -- views ---------------------------------------------------------------
  let view_variants = variants_for(views.views.map(view => view.name))
  emit_name_enum(
    out,
    "The views declared in \{source_file}.",
    "\{t}View",
    "name",
    view_variants,
    derives,
  )
  // The built views themselves live in the IR module as `<v>_views()`; the
  // per-view sources and styles are carried inside those @anode.View values,
  // so nothing here re-emits them.

  // -- component-level styles ----------------------------------------------
  // Per-view style rides inside each View; only the two component-wide styles
  // are separate arguments to component().
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

  // -- inputs --------------------------------------------------------------
  if !surface.inputs.is_empty() {
    let input_variants = variants_for(surface.inputs.map(i => i.name))
    emit_name_enum(
      out,
      "Every bare `@on` handler name the views reference.",
      "\{t}Input",
      "name",
      input_variants,
      derives,
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
      derives,
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
      derives,
    )
    out.write_string(
      "///|\n" +
      "/// The `#id` CSS selector for this element.\n" +
      "pub fn \{t}Id::selector(self : \{t}Id) -> String {\n" +
      "  \"#\" + self.id()\n" +
      "}\n\n",
    )
  }
}

///|
/// The generated types module for a whole view file: one section per
/// component it declares.
pub fn emit_module(
  name : String,
  source_file : String,
  file : ViewFile,
  debug_derive? : Bool = true,
) -> String raise GenError {
  let out = StringBuilder::new()
  out.write_string(
    "// GENERATED by `tutuca gen-views` from \{source_file} — DO NOT EDIT.\n" +
    "// Regenerate with:\n" +
    "//\n" +
    "//   tutuca gen-views \{source_file} --name \{name} --out <dir>\n" +
    "//\n" +
    "// The package this file lives in must import:\n" +
    "//   \"marianoguerra/tutuca/core\" @tutuca, \"marianoguerra/tutuca/component\"" +
    (if debug_derive { ",\n//   \"moonbitlang/core/debug\"\n" } else { "\n" }) +
    "\n",
  )
  for comp in file.components {
    let cname = comp.component_name(name)
    let surface = view_surface(comp.views, macros=file.macros)
    emit_component(cname, source_file, comp, surface, debug_derive, out)
  }
  out.to_string()
}

///|
pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError {
  emit_module(name, source_file, split_file(source))
}
