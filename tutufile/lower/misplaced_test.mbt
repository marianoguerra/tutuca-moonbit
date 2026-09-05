// The mistake a first `.tutu` file makes, and the one a model makes in a tool
// call: an option written after the element it meant to be inside.
//
// It reads as though it attaches to what precedes it, because elsewhere in
// the notation options do trail their forms. It has nothing to attach to
// here, and dropping it wrote a view with no styling and said nothing — which
// is the failure this whole notation was meant to stop making.

///|
test "an option outside its element is refused, with where it goes" {
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|view:
    #|  Counter:
    #|    @output{@(it.count)} ~class: "stat"
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 1)
  assert_eq(
    out.reports[0].message,
    "`~class` is outside the element it belongs to",
  )
  @debug.assert_eq(
    out.reports[0].help,
    Some("an attribute goes in the parentheses: `@tag(~class: <value>){ … }`"),
  )
}

///|
test "and the spelling that works is unchanged" {
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|view:
    #|  Counter:
    #|    @output(~class: "stat"){@(it.count)}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("<output class=\"stat\">"))
}

///|
test "a raw event attribute is refused where the notation has a handler" {
  // `~onclick: inc` lowered to `onclick="inc"` — script text a sanitizer
  // removes two layers later, with a message about sanitising rather than
  // about spelling.
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|view:
    #|  Counter:
    #|    @button(~onclick: inc){+}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 1)
  assert_eq(
    out.reports[0].message,
    "`~onclick` is not how a view names an event",
  )
  assert_true(out.reports[0].help.unwrap().has_prefix("write `~on_click:`"))
}

///|
test "an unknown attribute is still an attribute" {
  // The neighbouring case, and it stays: a name this printer does not know is
  // an attribute it does not know, and refusing every one of them would make
  // the notation a smaller HTML rather than the same one.
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|view:
    #|  Counter:
    #|    @output(~clazz: "typo"){@(it.count)}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("clazz=\"typo\""))
}
