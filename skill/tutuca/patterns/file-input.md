# Read a picked file

**Problem:** let the user pick a file and show its metadata.

```html
<!-- file_picker.html -->
<script type="tutuca/state">
  state FilePicker { name: String, size: Double, type: String, hasFile: Bool }
</script>

<template>
  <section>
    <input type="file" @on.change="onPickFile value">
    <p @hide=".hasFile">No file selected yet.</p>
    <dl @show=".hasFile">
      <dt>Name</dt><dd @text=".name"></dd>
      <dt>Size</dt><dd @text=".size"></dd>
      <dt>Type</dt><dd @text=".type"></dd>
    </dl>
  </section>
</template>
```

`%type` is a MoonBit keyword, so the generated struct binds it as `type_`
while the view keeps reading `.type` — the codec keys by the runtime name.

```moonbit
///|
fn file_picker_comp() -> @component.Component {
  file_picker_component(
    update=(s, msg, _ctx) => match msg {
      // for a file input, `value` is the picked file's metadata as a Map
      // (name/size/type/lastModified); Null when no file is selected
      Input("onPickFile", [Map(meta), ..]) =>
        Next({
          name: meta.get("name").unwrap_or(Null).str(),
          size: meta.get("size").unwrap_or(Null).num(),
          type_: meta.get("type").unwrap_or(Null).str(),
          hasFile: true,
        })
      Input("onPickFile", _) => Next({ ..s, hasFile: false })
      _ => Unhandled
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
Harness tests fire the pick with
`h.fire("input", @render.DomEvent::new(name="change", value=Map({...})))`
— see [testing.md](../testing.md) *Custom events and file inputs*.
