# Read a picked file

**Problem:** let the user pick a file and show its metadata.

```moonbit
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
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "size": @component.FieldSpec::of_default(Num(0)),
      "type": @component.FieldSpec::of_default(Str("")),
      "hasFile": @component.FieldSpec::of_default(Bool(false)),
    },
    input={
      // for a file input, `value` is the picked file's metadata as a Map
      // (name/size/type/lastModified); Null when no file is selected
      "onPickFile": (inst, args, _ctx) => {
        match args.get(0) {
          Some(Map(meta)) =>
            Some(
              inst
              .set("name", meta.get("name").unwrap_or(Str("")))
              .set("size", meta.get("size").unwrap_or(Num(0)))
              .set("type", meta.get("type").unwrap_or(Str("")))
              .set("hasFile", Bool(true)),
            )
          _ => Some(inst.set("hasFile", Bool(false)))
        }
      },
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
what you need into fields so the view can bind each piece; gate the
summary on a `hasFile` flag with `@show`/`@hide`. Runnable version with
size/date formatting helpers: `examples/file_picker.mbt`; harness tests
fire the pick with
`h.fire("input", @render.DomEvent::new(name="change", value=Map({...})))`.
