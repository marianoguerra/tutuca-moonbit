///|
test "known example lands in its curated section" {
  assert_eq(section_for("counter"), "Basics")
  assert_eq(section_for("json"), "Lists & Data")
  assert_eq(section_for("inspector"), "Inspectors")
  assert_eq(section_for("some-unmapped-name"), "Other")
}
