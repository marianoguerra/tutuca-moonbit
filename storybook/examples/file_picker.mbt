// Port of docs/examples/file-picker.js.
//
// Teaches: reading a file input. `@on.change="onPickFile value"` — the app
// glue turns the chosen File's synchronously-available metadata
// (name/size/type/lastModified) into a Value::Map, which is what the JS
// handler read off `event.target.files[0]`. No file selected -> Null.

///|
let file_size_units : Array[String] = ["B", "KB", "MB", "GB", "TB"]

///|
/// Format a byte count as a human-readable size. Kept as a plain function so
/// it can be unit-tested directly and reused from the component's method.
fn format_size(bytes : Double) -> String {
  let mut n = bytes
  let mut unit = 0
  while n >= 1024 && unit < file_size_units.length() - 1 {
    n = n / 1024
    unit = unit + 1
  }
  let rounded = if unit == 0 { n } else { (n * 100).round() / 100 }
  "\{rounded} \{file_size_units[unit]}"
}

///|
/// Epoch milliseconds -> "YYYY-MM-DD HH:MM UTC" (JS shows a locale string;
/// the port keeps it locale-independent so tests are stable).
fn format_epoch_ms(ms : Double) -> String {
  let total_secs = (ms / 1000).to_int64()
  let days = (total_secs / 86400).to_int()
  let secs_of_day = (total_secs % 86400).to_int()
  // civil-from-days (Howard Hinnant's algorithm), epoch = 1970-01-01
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if m <= 2 { y + 1 } else { y }
  let hh = secs_of_day / 3600
  let mm = secs_of_day % 3600 / 60
  fn pad(n : Int) -> String {
    if n < 10 {
      "0\{n}"
    } else {
      "\{n}"
    }
  }

  "\{year}-\{pad(m)}-\{pad(d)} \{pad(hh)}:\{pad(mm)} UTC"
}

///|
fn fp_num(v : @tutuca.Value) -> Double {
  match v {
    Num(n) => n
    _ => 0
  }
}

///|
/// Copy the picked file's metadata Map into the flattened fields; anything
/// that is not a metadata Map clears the selection (JS withFile(undefined)).
fn with_file(
  inst : @component.Instance,
  file : @tutuca.Value,
) -> @component.Instance {
  match file {
    Map(meta) =>
      inst
      .set("name", meta.get("name").unwrap_or(Str("")))
      .set("size", meta.get("size").unwrap_or(Num(0)))
      .set("type", meta.get("type").unwrap_or(Str("")))
      .set("lastModified", meta.get("lastModified").unwrap_or(Num(0)))
      .set("hasFile", Bool(true))
    _ => inst.set("hasFile", Bool(false))
  }
}

///|
fn file_picker_comp() -> @component.Component {
  @component.component(
    name="FilePicker",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <label class="flex flex-col gap-1">
      #|    <span>Pick a file</span>
      #|    <input type="file" class="file-input" @on.change="onPickFile value" />
      #|  </label>
      #|
      #|  <table class="table" @show=".hasFile">
      #|    <tbody>
      #|      <tr><th>Name</th><td class="fname" @text=".name"></td></tr>
      #|      <tr><th>Size</th><td class="fsize" @text="$sizeLabel"></td></tr>
      #|      <tr><th>Type</th><td class="ftype" @text="$typeLabel"></td></tr>
      #|      <tr><th>Last modified</th><td class="fmodified" @text="$lastModifiedLabel"></td></tr>
      #|    </tbody>
      #|  </table>
      #|
      #|  <p class="empty" @hide=".hasFile">No file selected yet — pick one above.</p>
      #|</section>
    ),
    // The File metadata is flattened into plain fields so the view can bind
    // each piece reactively. `hasFile` gates summary vs. empty-state.
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "size": @component.FieldSpec::of_default(Num(0)),
      "type": @component.FieldSpec::of_default(Str("")),
      "lastModified": @component.FieldSpec::of_default(Num(0)),
      "hasFile": @component.FieldSpec::of_default(Bool(false)),
    },
    input={
      "onPickFile": (inst, args, _ctx) => {
        Some(with_file(inst, args.get(0).unwrap_or(Null)))
      },
    },
    methods={
      "sizeLabel": (inst, _args) => Str(format_size(fp_num(inst.get("size")))),
      "typeLabel": (inst, _args) => {
        match inst.get("type") {
          Str("") => Str("unknown")
          Str(s) => Str(s)
          _ => Str("unknown")
        }
      },
      "lastModifiedLabel": (inst, _args) => {
        Str(format_epoch_ms(fp_num(inst.get("lastModified"))))
      },
    },
  )
}

///|
pub fn file_picker_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="file-picker",
    components=[file_picker_comp()],
    examples=[
      { component: "FilePicker", title: "Empty", args: Map([]), view: None },
      {
        component: "FilePicker",
        title: "With a file",
        args: {
          "name": Str("report.pdf"),
          "size": Num(245678),
          "type": Str("application/pdf"),
          "lastModified": Num(1700000000000),
          "hasFile": Bool(true),
        },
        view: None,
      },
    ],
  )
}
