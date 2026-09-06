# Read a picked file

**Problem:** let the user pick a file and show its metadata.

```tutu
spec:
  FilePicker:
    field name :: String
    field size :: Double
    field type :: String
    field has_file :: Bool

view:
  FilePicker:
    @section{@input(~type: "file", ~on_change: on_pick_file(e.value)) @hide(it.has_file){@p{No file selected yet.}} @show(it.has_file){@dl{@dt{Name}@dd{@(it.name)}@dt{Size}@dd{@(it.size)}@dt{Type}@dd{@(it.type)}}}}
```

`%type` is a MoonBit keyword, so the generated struct binds it as `type_`
while the view keeps reading `it.type` — the codec keys by the runtime name.

This handler stays in MoonBit, and the reason is narrow enough to state: a
`logic:` section CAN take the argument apart — `receive onPickFile(meta)` with
`it.name := meta.name.str()` compiles, since `str` renders any value — but the
metadata's `size` is a number inside an `Any`, and `num` converts a number
rather than coercing a `Value`, so `gen` refuses that arm. Unpacking a
dynamic payload into typed fields is what the MoonBit half is for.

```moonbit
///|
fn file_picker_comp() -> @component.Component {
  file_picker_component(
    update=(s, msg, _ctx) => match msg {
      // for a file input, `e.value` is the picked file's metadata as a Map
      // (name/size/type/lastModified); Null when no file is selected
      Receive("onPickFile", [Map(meta), ..]) =>
        Next({
          name: meta.get("name").unwrap_or(Null).str(),
          size: meta.get("size").unwrap_or(Null).num(),
          type_: meta.get("type").unwrap_or(Null).str(),
          has_file: true,
        })
      Receive("onPickFile", _) => Next({ ..s, has_file: false })
      _ => Unhandled
    },
  )
}
```

The value layer deliberately exposes no DOM objects, so the app glue maps
the chosen `File`'s synchronously-available metadata into a plain `Map`
delivered as `e.value` — no `event.target.files` digging in host JS (this differs from
the JS docs, where the handler takes `event`). The file's *contents* are
not in the metadata. To read them, use `@files.FileService` — `read_text(id~,
then~)` takes the `id` a dropped or picked file's descriptor carries and
answers the text through a continuation; see
[tracing.md](../tracing.md#files). Feed the result back in through an
`ask(~route: lex)` or `app.send_at_root`. Flatten
what you need into fields so the view can bind each piece (`type` is a
MoonBit keyword, so the struct field is `type_` with a `rename` in the
derive); gate the summary on a `has_file` flag with `@show`/`@hide`.
Harness tests fire the pick with
`h.fire("input", @render.DomEvent::new(name="change", value=Map({...})))`
— see [testing.md](../testing.md) *Custom events and file inputs*.
