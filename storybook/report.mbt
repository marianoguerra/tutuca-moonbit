// `tutuca storybook --dry-run` output: the compiled story registry as text or
// JSON. The interactive gallery is compiled into the wasm host; this is how the
// CLI reports what that gallery contains without serving it.

///|
/// Human-readable listing: one section header per group, its stories indented.
pub fn dry_run_text(sections : Array[Section]) -> String {
  let sb = StringBuilder::new()
  let mut total = 0
  for sec in sections {
    sb.write_string("\{sec.title}\n")
    for s in sec.stories {
      total = total + 1
      sb.write_string("  - \{s.id}\n")
    }
  }
  sb.write_string("\n\{total} stories in \{sections.length()} sections\n")
  sb.to_string()
}

///|
/// Structured listing for `--dry-run --json`.
pub fn dry_run_json(sections : Array[Section]) -> Json {
  let secs : Array[Json] = []
  for sec in sections {
    let ids : Array[Json] = []
    for s in sec.stories {
      ids.push(s.id.to_json())
    }
    secs.push(
      Json::object({
        "section": sec.title.to_json(),
        "stories": Json::array(ids),
      }),
    )
  }
  Json::object({ "sections": Json::array(secs) })
}
