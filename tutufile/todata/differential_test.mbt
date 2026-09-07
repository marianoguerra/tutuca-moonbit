// The JSON a `fixtures:` or `tests:` section reads to.
//
// This was a DIFFERENTIAL assertion: the same source read here and printed
// into the block the old notation carried, compared as JSON — the parsers are
// the same on both paths, because both blocks WERE JSON, so the JSON being
// equal was the whole property. That is what made the printer safe to delete,
// and it went with it.
//
// The corpus is what is left, and it is the half worth keeping: every shape a
// fixture and a scene take, snapshotted as the JSON they read to. Read it, do
// not just refresh it — `@statedef.parse_init` and `@scenedef.parse_scenes`
// are on the other side of these strings.

///|
/// The section's JSON, whichever of the two the file carries.
fn section_json(src : String) -> String {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  let out = match file.section(Fixtures) {
    Some(s) =>
      fixtures_json(s.decls) catch {
        @sh.ExError(message~, ..) => return "ERR " + message
      }
    None =>
      match file.section(Tests) {
        Some(s) =>
          scenes_json(s.decls) catch {
            @sh.ExError(message~, ..) => return "ERR " + message
          }
        None => return "no section"
      }
  }
  out.stringify()
}

///|
test "a fixture reads to its JSON" {
  inspect(
    section_json(
      "spec:\n  T:\n    field n :: Int\n\nfixtures:\n  \"zero\":\n    it.n = 0\n",
    ),
    content=(
      #|{"zero":{"value":{"n":0}}}
    ),
  )
  inspect(
    section_json(
      "spec:\n  T:\n    field n :: Int\n\nfixtures:\n  \"some\" ~default:\n    ~doc: \"a few\"\n    it.n = 3\n",
    ),
    content=(
      #|{"some":{"default":true,"doc":"a few","value":{"n":3}}}
    ),
  )
  inspect(
    section_json(
      "spec:\n  T:\n    field s :: String\n\nfixtures:\n  \"named\":\n    ~view: \"row\"\n    ~tags: [\"a\", \"b\"]\n    it.s = \"x\"\n",
    ),
    content=(
      #|{"named":{"view":"row","tags":["a","b"],"value":{"s":"x"}}}
    ),
  )
}

///|
test "a scene reads to its JSON" {
  inspect(
    section_json(
      "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"clicking\":\n    click(\"button\")\n    expect count(\"li\") == 1\n",
    ),
    content=(
      #|{"clicking":{"steps":[{"click":"button"},{"expect":"count","at":"li","is":1}]}}
    ),
  )
  inspect(
    section_json(
      "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"typing\":\n    ~component: T\n    type(\"input\", \"x\")\n    expect text(\"h1\") == \"x\"\n",
    ),
    content=(
      #|{"typing":{"component":"T","steps":[{"type":"input","value":"x"},{"expect":"text","at":"h1","is":"x"}]}}
    ),
  )
  inspect(
    section_json(
      "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"sending\":\n    send(\"bump\")\n    expect state it.n == 1\n",
    ),
    content=(
      #|{"sending":{"steps":[{"send":"bump"},{"expect":"state","at":".n","is":1}]}}
    ),
  )
}
