# Read a picked file

**Problem:** let the user pick a file and show its metadata.

```moonbit
priv struct FilePickerState {
  name : String
  size : Double
  type_ : String
  hasFile : Bool
} derive(
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

fn file_picker_comp() -> @component.Component {
  @component.component(
    name="FilePicker",
    view=(
      #|<section>
      #|  <input type="file" @on.change="onPickFile value" />
      #|  <p @hide=".hasFile">No file selected yet.</p>
      #|  <dl @show=".hasFile">
      #|    <dt>Name</dt><dd @text=".name"></dd>
      #|    <dt>Size</dt><dd @text=".size"></dd>
      #|    <dt>Type</dt><dd @text=".type"></dd>
      #|  </dl>
      #|</section>
    ),
    init=FilePickerState::{ name: "", size: 0, type_: "", hasFile: false },
    update=(s : FilePickerState, msg, _ctx) => match msg {
      // for a file input, `value` is the picked file's metadata as a Map
      // (name/size/type/lastModified); Null when no file is selected
      Input("onPickFile", [Map(meta), ..]) =>
        Some({
          name: meta.get("name").unwrap_or(Null).str(),
          size: meta.get("size").unwrap_or(Null).num(),
          type_: meta.get("type").unwrap_or(Null).str(),
          hasFile: true,
        })
      Input("onPickFile", _) => Some({ ..s, hasFile: false })
      _ => None
    },
  )
}
```

The value layer deliberately exposes no DOM objects, so the app glue maps
the chosen `File`'s synchronously-available metadata into a plain `Map`
delivered as `value` — no `event.target.files` digging (this differs from
the JS docs, where the handler takes `event`). The file's *contents* are
not in the metadata — read those host-side (JS FFI) and feed the result
back in through a `request`/`response` or `app.send_at_root`. Flatten
what you need into fields so the view can bind each piece (`type` is a
MoonBit keyword, so the struct field is `type_` with a `rename` in the
derive); gate the summary on a `hasFile` flag with `@show`/`@hide`.
Runnable version with size/date formatting helpers:
`examples/file_picker.mbt`; harness tests fire the pick with
`h.fire("input", @render.DomEvent::new(name="change", value=Map({...})))`.
