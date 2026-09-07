// A whole `.tutu` file, with its `view:` section rewritten.
//
// Only that section changes. `spec:`, `logic:`, `fixtures:` and `tests:` are
// copied byte for byte from the source, because the alignment is a change to
// the MARKUP notation and nothing else -- and a converter that reprinted the
// other four would put its own formatting decisions into every file it touched
// for no reason.

///|
/// The `view:` section, printed whole.
///
/// Three declaration kinds live there and each has its own header: a view is
/// named after the component it draws, a macro writes its parameters, and a
/// style block has no name at all.
pub fn print_section(
  block : @tutufile.SectionBlock,
  css? : Bool = false,
) -> String raise @sh.ExError {
  // A macro CALL keeps its `~`, so the printer has to know which names are
  // macros before it prints any of them.
  let macros = []
  for d in block.decls {
    if d.kind is Macro {
      macros.push(d.name)
    }
  }
  let out = StringBuilder()
  out.write_string("view:\n")
  let mut first = true
  for d in block.decls {
    if !first {
      out.write_string("\n")
    }
    first = false
    match d.kind {
      Style => print_style(d, out, css~)
      // A macro's header carries its parameters and their defaults, and it is
      // copied from the source rather than reprinted: a default is any
      // expression, and reprinting one would be a second expression printer to
      // keep correct.
      Macro => {
        out.write_string("  " + macro_header(d) + ":\n")
        out.write_string(print_view(d, "    ", macros~, css~))
      }
      _ => {
        // A view with no body is written as a BARE NAME, with no `:` at all.
        // `MinimumViableComponent` is a real one -- a component that renders
        // nothing -- and giving it a colon writes a block with nothing under
        // it, which is a parse error two lines later.
        let body = print_view(d, "    ", macros~, css~)
        if body == "" {
          out.write_string("  " + d.name + "\n")
        } else {
          out.write_string("  " + d.name + ":\n")
          out.write_string(body)
        }
      }
    }
  }
  out.to_string()
}

///|
/// A style declaration, which is raw text and keeps its scope option.
fn print_style(
  d : @tutufile.Decl,
  out : StringBuilder,
  css? : Bool = false,
) -> Unit raise @sh.ExError {
  // `Decl::options` does NOT carry it: `~global` is written inside the style
  // block's parentheses, and `options_of` reads the options on a declaration's
  // HEADER. Asking the reader is what keeps the two answers the same one.
  let global = @toanode.style_is_global(d)
  let opts = if global { "~global" } else { "" }
  let raw = @toanode.style_of(d)
  // A block that will not convert, or converts to something that does not mean
  // the same CSS, stays raw text. That spelling is kept on purpose, so nothing
  // is lost by leaving one behind -- and a converter that guessed here would
  // rewrite a stylesheet nobody checked.
  if css && raw != "" {
    match css_block(raw, "    ", global) {
      Some(text) =>
        if css_agrees(raw, text, global) {
          out.write_string("  style(" + opts + "):\n" + text)
          return
        }
      None => ()
    }
  }
  out.write_string("  style(" + opts + "): @{" + raw + "}\n")
}

///|
/// A macro's header, with its parameters and their defaults as written.
///
/// Built from the declaration's TERMS rather than from `Decl::header`, which
/// spans `macro` and the name and stops before the parentheses -- so slicing it
/// writes `macro badge:` and loses every parameter. Copied rather than
/// reprinted because a default is any expression, and reprinting one would be a
/// second expression printer to keep correct.
fn macro_header(d : @tutufile.Decl) -> String {
  guard d.node.it is Group(parts) else { return "macro " + d.name }
  let out = StringBuilder()
  for p in parts {
    if p.it is Block(_) {
      break
    }
    out.write_string(p.to_source())
  }
  out.to_string().trim(chars=" \n").to_owned()
}

///|
/// A whole file, with its `view:` section rewritten in place.
///
/// Returns `None` when the file has no `view:` section, which is not an error:
/// a `.tutu` may be a spec and a logic block with nothing to draw.
pub fn print_file(
  src : String,
  file : @tutufile.TutuFile,
  css? : Bool = false,
) -> String? raise @sh.ExError {
  guard file.section(View) is Some(block) else { return None }
  guard block.decls.length() > 0 else { return None }
  // The extent to replace runs from the `view` head to the START OF THE NEXT
  // SECTION, not to the end of the last declaration.
  //
  // A declaration's own span stops before its at-notation body -- the `{…}`
  // braces are not inside the group -- so measuring from the declarations
  // leaves the original body sitting after the converted one. Sections are
  // top-level and ordered, so the neighbour is the reliable boundary.
  let start = block.span.start
  let mut stop = src.length()
  let mut seen = false
  for s in file.sections {
    if seen {
      stop = s.span.start
      break
    }
    if s.section is View {
      seen = true
    }
  }
  let before = src.clamped_view(start=0, end=start).to_owned()
  let after = src.clamped_view(start=stop, end=src.length()).to_owned()
  let body = print_section(block, css~).trim_end(chars="\n").to_owned()
  let tail = if after == "" { "\n" } else { "\n\n" + after }
  Some(before + body + tail)
}
