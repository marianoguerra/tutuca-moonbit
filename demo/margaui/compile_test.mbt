///|
/// The embedded margaui bundle compiles a mix of a plain Tailwind utility and a
/// daisyUI-style component class, and carries the light/dark theme vars the
/// data-theme flip switches between. Guards the whole embed-and-compile path.
test "compile_classes emits utilities, components, and theme vars" {
  let css = compile_classes(["flex", "btn", "bg-primary"])
  assert_true(css.contains("display: flex"))
  assert_true(css.contains(".btn"))
  assert_true(css.contains("var(--color-primary"))
  // light lives at :root / [data-theme=light]; dark overrides via [data-theme=dark]
  assert_true(css.contains("[data-theme=\"dark\"]"))
  assert_true(css.contains("--color-primary:"))
}

///|
test "empty class set still yields the base stylesheet" {
  let css = compile_classes([])
  // preflight/theme layers emit even with no utility candidates
  assert_true(css.length() > 0)
}
