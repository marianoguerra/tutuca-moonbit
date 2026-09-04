///| The four ways a component gets into the palette.
///
/// All of them end in the same place: bytes, instantiated, registered,
/// catalogued. What differs is only where the source came from, which is the
/// property worth having — a card a person pasted is not a second kind of
/// thing.

///|
/// Hand the bytes to JS, which instantiates and calls `finish_load` back.
///
/// It has to go out and come back because `WebAssembly.compile` answers a
/// promise and there is nothing here that can wait on one.
extern "js" fn begin_instantiate(
  key : String,
  wasm_b64 : String,
  manifest_json : String,
) -> Unit =
  #|(key, wasm, manifest) => globalThis.__universal.instantiate(key, wasm, manifest)

///|
/// Fetch a file beside the page. Answers "" for one that is not there.
extern "js" fn fetch_text(path : String, tag : String) -> Unit =
  #|(path, tag) => globalThis.__universal.fetchText(path, tag)

///|
/// The library, as the page was told it.
let library : Ref[Array[(String, String)]] = Ref([])

///|
/// Whether every card should be loaded at boot.
///
/// `?loadAll` and nothing else. The default is an empty palette but the kit,
/// because a demo that loads eleven cards before it draws anything is a demo
/// about waiting.
extern "js" fn wants_load_all() -> Bool =
  #|() => new URLSearchParams(location.search).has("loadAll")

///|
/// The library index, handed over by the page at boot.
pub fn set_library(names_csv : String, paths_csv : String) -> Unit {
  let names = names_csv.split(",").map(s => s.to_owned()).collect()
  let paths = paths_csv.split(",").map(s => s.to_owned()).collect()
  let rows : Array[(String, String)] = []
  for i in 0..<names.length() {
    if names[i] != "" {
      rows.push((names[i], paths.get(i).unwrap_or("")))
    }
  }
  library.val = rows
  match live.val {
    Some(app) =>
      app.send_at_root("setLibrary", args=[List(@ui.library_rows(rows))])
      |> ignore
    None => ()
  }
  if wants_load_all() {
    load_all()
  }
}

///|
/// A card's source arrived. `tag` is the path it was asked for.
pub fn card_fetched(tag : String, source : String) -> Unit {
  if source == "" {
    note("\{tag}: could not be read", tone="error")
    return
  }
  load_card(source, stem_of(tag)) |> ignore
}

///|
fn stem_of(path : String) -> String {
  let parts = path.split("/").map(p => p.to_owned()).collect()
  let last = parts.get(parts.length() - 1).unwrap_or(path)
  match last.split(".").collect() {
    [head, ..] => head.to_owned()
    _ => last
  }
}

///|
fn load_path(path : String) -> Unit {
  if path == "" {
    return
  }
  status("loading \{path}")
  fetch_text(path, path)
}

///|
fn load_all() -> Unit {
  for row in library.val {
    load_path(row.1)
  }
}

///|
/// Whatever the person ticked. The shell holds the ticks, so this asks it.
fn load_chosen() -> Unit {
  guard live.val is Some(app) else { return }
  let root = app.root_value()
  match root.field("library") {
    List(rows) =>
      for row in rows {
        if row.field("chosen") == Bool(true) && row.field("path") is Str(p) {
          load_path(p)
        }
      }
    _ => ()
  }
}

///|
/// A file was dropped on the page.
///
/// Handled OUTSIDE the tutuca tree, in `page.js`, which sidesteps the one
/// collision this could have had: `drop` is the only DOM event that crosses
/// component boundaries, and dispatch gives it to the first ancestor with a
/// handler — so a hole claiming it would swallow the page-wide drop.
pub fn dropped(name : String, text : String) -> Unit {
  if text == "" {
    note("\{name}: nothing to read", tone="error")
    return
  }
  load_card(text, stem_of(name)) |> ignore
}
