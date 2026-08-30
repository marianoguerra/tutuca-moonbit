///|
test "stories() covers the example registry and groups into sections" {
  let all = stories()
  assert_true(all.length() >= 40)
  let sections = @sb.sections_of(all, order=section_order)
  // curated sections come first and are non-empty
  assert_true(sections.length() >= 5)
  assert_eq(sections[0].title, "Basics")
  // every story lands in exactly one section (counts add up)
  let mut total = 0
  for sec in sections {
    assert_true(sec.stories.length() > 0)
    total = total + sec.stories.length()
  }
  assert_eq(total, all.length())
}
