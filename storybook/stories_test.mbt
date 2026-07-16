///|
test "stories() covers the example registry and groups into sections" {
  let all = stories()
  assert_true(all.length() >= 40)
  let sections = sections_of(all)
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

///|
test "dry-run text lists sections and stories" {
  let sections = sections_of(stories())
  let text = dry_run_text(sections)
  assert_true(text.contains("Basics"))
  assert_true(text.contains("- counter"))
  assert_true(text.contains("stories in"))
}
