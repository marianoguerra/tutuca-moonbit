// A module's views, read out of the card's own source.
//
// The manifest carries the `.tutu` the card was compiled from, whole, and this
// reads it with `tutufile/toanode` — the same reader `tutuca gen` uses ahead of
// time. One notation and one reader on both sides, which is what lets a
// differential test say the two agree.
//
// What it replaces was a printer: the manifest used to carry each view as
// HTML, and a host parsed it back with `ANode::parse`. That cost a printer the
// compiler had to keep byte-exact and cost every host that loads a module the
// HTML tokenizer — 195 KB of a 439 KB bundle, measured in
// benchmarks/OPTIMIZATIONS.md, and `@anode.View::new` is the only function that
// names the parser. Nothing here does.

///|
/// Every view a module declares, by `<Component>.<name>`.
///
/// Built once per module rather than once per view: the macros have to be in
/// hand before any view is read — a view expands a macro call where it stands —
/// and the source is read once for both.
///
/// `config_vars` is the host's table, and passing it here is what makes a
/// `host.name` in a view resolve to what the host offers. A name the table does
/// not carry is refused, at load, rather than rendered as Null every frame.
fn read_views(
  tutu : String,
  config_vars : Map[String, String],
  styles : Map[String, String],
) -> Map[String, @anode.View] raise ManifestError {
  let out : Map[String, @anode.View] = Map([])
  guard tutu != "" else { return out }
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", tutu)
  let file = @tutufile.read(tutu, id)
  if file.reports is [r, ..] {
    raise ManifestError("module refused: card source: \{r.message}")
  }
  guard file.section(View) is Some(section) else { return out }
  let macros = @toanode.macros_of(section.decls) catch {
    e => raise ManifestError("module refused: macros: \{ex_line(e)}")
  }
  for d in section.decls {
    guard d.kind is View else { continue }
    // The component's scoped style, on its `main` view — which is where a
    // manifest puts it, and where `Component::compile` looks for it. A view
    // with a `@style{…}` of its own keeps that one; this is the fallback.
    let style = styles.get(d.name).unwrap_or("")
    let built = @toanode.ViewBuilder::new(macros~, config=config_vars).view(
      d,
      style~,
    ) catch {
      e => raise ManifestError("module refused: view \{d.name}: \{ex_line(e)}")
    }
    out[d.name] = built
  }
  out
}

///|
/// A reader's error as one line, message and repair together.
///
/// Both halves, because the help is where the SPELLING to write is: a card
/// author reading "`~onclick` is not an option" still has to guess, and one
/// reading it beside "write `~on_click:`" does not.
fn ex_line(e : @sh.ExError) -> String {
  let @sh.ExError(message~, help~, ..) = e
  message + " — " + help
}
