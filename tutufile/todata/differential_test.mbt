// The JSON a `fixtures:` or `tests:` section reads to, against the JSON the
// printer wrote — and then the parsed fixtures and scenes on either side.
//
// The parsers are the same on both paths: both blocks were JSON in the old
// notation, and what `@statedef.parse_init` and `@scenedef.parse_scenes` do
// with one is the same work whichever notation the file was written in. So the
// property to hold is that the JSON is the same, and that is what this asserts.

///|
fn sections(src : String) -> (Json, Json)? {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  let direct = match file.section(Fixtures) {
    Some(s) => fixtures_json(s.decls) catch { _ => return None }
    None =>
      match file.section(Tests) {
        Some(s) => scenes_json(s.decls) catch { _ => return None }
        None => return None
      }
  }
  // The printer's own answer, out of the block it wrote.
  let lowered = @lower.lower(src, id)
  if lowered.reports.length() > 0 {
    return None
  }
  let tag = if file.section(Fixtures) is Some(_) {
    "tutuca/fixtures"
  } else {
    "tutuca/test"
  }
  let printed = @json.parse(block_of(lowered.text, tag)) catch {
    _ => return None
  }
  Some((direct, printed))
}

///|
/// One `<script type="…">` block's body.
fn block_of(text : String, tag : String) -> String {
  let open = "<script type=\"" + tag + "\">"
  guard text.find(open) is Some(at) else { return "" }
  let rest = text[at + open.length():].to_owned()
  match rest.find("</script>") {
    Some(end_) => rest[:end_].to_owned()
    None => rest
  }
}

///|
test "a fixture reads to the same JSON both ways" {
  let srcs = [
    "spec:\n  T:\n    field n :: Int\n\nfixtures:\n  \"zero\":\n    it.n = 0\n",
    "spec:\n  T:\n    field n :: Int\n\nfixtures:\n  \"some\" ~default:\n    ~doc: \"a few\"\n    it.n = 3\n",
    "spec:\n  T:\n    field s :: String\n\nfixtures:\n  \"named\":\n    ~view: \"row\"\n    ~tags: [\"a\", \"b\"]\n    it.s = \"x\"\n",
  ]
  let broken = []
  for s in srcs {
    match sections(s) {
      Some((a, b)) =>
        if a != b {
          broken.push(
            s +
            "\n  direct:  " +
            a.stringify() +
            "\n  printed: " +
            b.stringify(),
          )
        }
      None => broken.push("neither path read: " + s)
    }
  }
  @debug.assert_eq(broken, [])
}

///|
test "a scene reads to the same JSON both ways" {
  let srcs = [
    "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"clicking\":\n    click(\"button\")\n    expect count(\"li\") == 1\n",
    "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"typing\":\n    ~component: T\n    type(\"input\", \"x\")\n    expect text(\"h1\") == \"x\"\n",
    "spec:\n  T:\n    field n :: Int\n\ntests:\n  \"sending\":\n    send(\"bump\")\n    expect state it.n == 1\n",
  ]
  let broken = []
  for s in srcs {
    match sections(s) {
      Some((a, b)) =>
        if a != b {
          broken.push(
            s +
            "\n  direct:  " +
            a.stringify() +
            "\n  printed: " +
            b.stringify(),
          )
        }
      None => broken.push("neither path read: " + s)
    }
  }
  @debug.assert_eq(broken, [])
}
