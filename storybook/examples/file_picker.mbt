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
priv struct FilePickerState {
  name : String
  size : Double
  type_ : String
  lastModified : Double
  hasFile : Bool
} derive (
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

///|
/// Copy the picked file's metadata Map into the flattened fields; anything
/// that is not a metadata Map clears the selection (JS withFile(undefined)).
fn with_file(s : FilePickerState, file : @tutuca.Value) -> FilePickerState {
  match file {
    Map(meta) =>
      {
        name: meta.get("name").unwrap_or(Str("")).str(),
        size: meta.get("size").unwrap_or(Num(0)).num(),
        type_: meta.get("type").unwrap_or(Str("")).str(),
        lastModified: meta.get("lastModified").unwrap_or(Num(0)).num(),
        hasFile: true,
      }
    _ => { ..s, hasFile: false }
  }
}

///|
fn file_picker_comp() -> @component.Component {
  @component.component(
    views=file_picker_views(),
    name="FilePicker",
    // The File metadata is flattened into plain fields so the view can bind
    // each piece reactively. `hasFile` gates summary vs. empty-state.
    init=FilePickerState::{
      name: "",
      size: 0,
      type_: "",
      lastModified: 0,
      hasFile: false,
    },
    update=(s : FilePickerState, msg, _ctx) => {
      match msg {
        Input("onPickFile", args) =>
          Some(with_file(s, args.get(0).unwrap_or(Null)))
        _ => None
      }
    },
    compute={
      "sizeLabel": (s : FilePickerState, _args) => Str(format_size(s.size)),
      "typeLabel": (s : FilePickerState, _args) => {
        match s.type_ {
          "" => Str("unknown")
          t => Str(t)
        }
      },
      "lastModifiedLabel": (s : FilePickerState, _args) => {
        Str(format_epoch_ms(s.lastModified))
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
