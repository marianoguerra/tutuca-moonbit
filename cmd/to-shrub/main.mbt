///|
/// Everything the `view:` section carries, as text, in declaration order.
///
/// The comparison the conversion rests on, and it covers the WHOLE section
/// rather than its views. A check that read only the views would be blind to a
/// style block -- which is how `~global` was silently dropped on the first pass
/// here, turning a page-wide stylesheet into a component-scoped one with
/// nothing to say so. Four of this repo's migration defects have been a check
/// one step from what broke; this is the fifth, caught before it shipped.
///
/// `@debug.to_string` renders a text node's contents exactly, so a space that
/// moved shows up as a difference. Nothing is normalised: whitespace is the one
/// dimension the aligned notation changes.
fn section_facts(src : String) -> Array[String] raise {
  let sources = @report.Sources::new()
  let id = sources.add("f.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(View) is Some(block) else { return [] }
  let macros = @toanode.macros_of(block.decls)
  let out = []
  for d in block.decls {
    match d.kind {
      Style =>
        out.push(
          "style global=" +
          @toanode.style_is_global(d).to_string() +
          " => " +
          @toanode.style_of(d),
        )
      View => {
        let b = @toanode.ViewBuilder::new(macros~)
        let v = b.view(d)
        out.push(d.name + " => " + @debug.to_string(v.anode))
        out.push(d.name + " style => " + v.style)
      }
      // A macro is compared through the views that CALL it: its body is
      // expanded into them, so a macro that converted wrongly changes a tree.
      _ => ()
    }
  }
  out
}

///|
/// Convert one file, or say why it was left alone.
fn convert(path : String) -> String raise {
  let src = @fs.read_file_to_string(path)
  let sources = @report.Sources::new()
  let id = sources.add(path, src)
  let file = @tutufile.read(src, id)
  if !file.ok() {
    return "SKIP (does not read) " + path
  }
  let out = match (Ok(@toshrub.print_file(src, file)) catch { e => Err(e) }) {
    Ok(Some(text)) => text
    Ok(None) => return "SKIP (no view section) " + path
    Err(_) => return "REFUSED (cannot print) " + path
  }
  // The check, and the whole reason this writes anything at all.
  let before = match (Ok(section_facts(src)) catch { _ => Err(0) }) {
    Ok(t) => t
    Err(_) => return "SKIP (views do not read) " + path
  }
  // A refusal leaves the conversion beside the file it could not replace, so
  // the reason can be read rather than guessed at.
  fn refuse(why : String) -> String {
    @fs.write_string_to_file(path + ".converted", out) catch { _ => () }
    "REFUSED (" + why + ") " + path
  }

  let after = match (Ok(section_facts(out)) catch { e => Err(e) }) {
    Ok(t) => t
    Err(@sh.ExError(message~, ..)) =>
      return refuse("converted file does not read: " + message)
    Err(_) => return refuse("converted file does not read")
  }
  if after.length() != before.length() {
    return refuse("declaration count changed")
  }
  for i, b in before {
    if after[i] != b {
      return refuse("tree differs")
    }
  }
  @fs.write_string_to_file(path, out)
  "ok " + path
}

///|
fn main {
  let args = @env.args()
  let mut ok = 0
  let mut left = 0
  for i, path in args {
    if i == 0 {
      continue
    }
    let line = convert(path) catch { _ => "REFUSED (raised) " + path }
    if line.has_prefix("ok ") {
      ok = ok + 1
    } else {
      left = left + 1
      println(line)
    }
  }
  println("converted \{ok}, left \{left}")
}
