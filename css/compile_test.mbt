///|
/// The embedded margaui bundle compiles a mix of a plain Tailwind utility and a
/// daisyUI-style component class, and carries the light/dark theme vars the
/// data-theme flip switches between. Guards the whole embed-and-compile path.
test "compile_margaui emits utilities, components, and theme vars" {
  let css = @css.compile_margaui(["flex", "btn", "bg-primary"])
  assert_true(css.contains("display: flex"))
  assert_true(css.contains(".btn"))
  assert_true(css.contains("var(--color-primary"))
  // light lives at :root / [data-theme=light]; dark overrides via [data-theme=dark]
  assert_true(css.contains("[data-theme=\"dark\"]"))
  assert_true(css.contains("--color-primary:"))
}

///|
test "empty class set still yields the base stylesheet" {
  let css = @css.compile_margaui([])
  // preflight/theme layers emit even with no utility candidates
  assert_true(css.length() > 0)
}

///|
/// The tailwind-only build is stock Tailwind: utilities and the base layers, but
/// none of margaui's component classes. `btn` is a margaui component, so it has
/// no utility to compile against here and must not produce a rule.
test "compile_tailwind emits utilities but no margaui components" {
  let css = @css.compile_tailwind(["flex", "text-center", "btn"])
  assert_true(css.contains("display: flex"))
  assert_true(css.contains("text-align: center"))
  assert_false(css.contains(".btn"))
  // preflight is part of the entry
  assert_true(css.contains("box-sizing: border-box"))
}

///|
/// Pins the stylesheet sync. Both of these fail against margaui's hand-mirrored
/// tw/*.css: `mauve` is one of the four palettes upstream added in 4.3.2 and
/// margaui never picked up, and the achromatic `oklch(… 0 none)` form arrived in
/// 4.3.3. The css-bundle task takes these files from the tailwindcss npm release
/// pinned to the tag the compiler port is derived from, so both must hold — if
/// this test breaks, the stylesheets have drifted away from the engine again.
test "the embedded Tailwind theme matches the version the compiler was ported from" {
  let css = @css.compile_tailwind(["bg-neutral-500", "bg-mauve-500"])
  assert_true(css.contains("oklch(55.6% 0 none)"))
  assert_true(css.contains("--color-mauve-500"))
}

///|
/// margaui resolves its `./tw/*` imports against `tailwind_bundle`, so the same
/// two markers have to survive the merge — the proof that `--skip-prefix tw/`
/// dropped margaui's stale copies rather than the good ones.
test "compile_margaui resolves ./tw/* against the pinned Tailwind bundle" {
  let css = @css.compile_margaui(["bg-neutral-500", "bg-mauve-500"])
  assert_true(css.contains("oklch(55.6% 0 none)"))
  assert_true(css.contains("--color-mauve-500"))
}

///|
/// The two bundles are disjoint: the tailwind module owns `tw/*` and the margaui
/// module owns everything else, so a merged map has no duplicate keys to resolve
/// in an order `MemoryStylesheetLoader` does not promise.
test "the tailwind and margaui bundles do not overlap" {
  // Order is whatever the generator's key sort produced — assert on membership,
  // not sequence, so this does not double as a snapshot of that sort.
  let tw_keys = @css.tailwind_bundle.map(pair => pair.0)
  assert_eq(tw_keys.length(), 3)
  for name in ["tw/theme.css", "tw/preflight.css", "tw/utilities.css"] {
    assert_true(tw_keys.contains(name))
  }
  for pair in @css.margaui_bundle {
    assert_false(tw_keys.contains(pair.0))
  }
}
