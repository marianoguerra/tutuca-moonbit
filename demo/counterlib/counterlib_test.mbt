// The counter, driven through the DOM.
//
// A blackbox test rather than an inline one, because the headless harness is a
// test-only dependency: `counterlib` itself must stay target-agnostic, since
// one module value drives both the browser app and the embedded CLI.

///|
/// The script block, running.
///
/// `add` and `resetTo` are declared in `counter.html`'s
/// `<script type="tutuca/script">` block and nowhere else — no MoonBit in this
/// module mentions either name. So a click that moves the count is the whole
/// chain end to end: the block parsed, checked against the schema, compiled to
/// `counter_inline_update`, and composed ahead of an `update~` that is not
/// passed at all.
test "the counter's behaviour comes from its script block" {
  let h = @harness.mount(@counterlib.module_def(), "Counter")
  assert_eq(h.text("#count"), "0")
  h.click("#inc")
  h.click("#inc")
  assert_eq(h.text("#count"), "2")
  h.click("#dec")
  assert_eq(h.text("#count"), "1")
  // `.history.push .count` reads the value the line above wrote, so the trail
  // is where the counter LANDED each time rather than where it started.
  assert_eq(h.texts("li"), ["1", "2", "1"])
  // …and the two names the block does NOT answer still fall through to the
  // mutators the schema's fields generate.
  h.type_into("#label", "Renamed")
  assert_eq(h.text("h1"), "Renamed: 1")
  h.click("#reset")
  assert_eq(h.text("#count"), "0")
  h.destroy()
}
