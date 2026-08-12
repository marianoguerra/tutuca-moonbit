///|
fn plan_css(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["gen-tailwind-css", ..args])
}

///|
fn css_plan(args : Array[String]) -> @cli.CssPlan {
  match plan_css(args) {
    GenCss(_, plan~) => plan
    _ => abort("expected a GenCss outcome")
  }
}

///|
test "gen-tailwind-css defaults to the current directory and stdout" {
  let plan = css_plan([])
  assert_eq(plan.paths, ["."])
  assert_eq(plan.out, None)
  assert_eq(plan.entry, None)
  assert_eq(plan.print_classes, false)
  assert_eq(plan.polyfills, 3)
  assert_eq(plan.margaui, false)
}

///|
test "gen-margaui-css differs from gen-tailwind-css only in the stylesheet set" {
  let tw = css_plan(["views/", "-o", "app.css"])
  let mg = match @cli.plan(["gen-margaui-css", "views/", "-o", "app.css"]) {
    GenCss(_, plan~) => plan
    _ => abort("expected a GenCss outcome")
  }
  assert_eq(tw.margaui, false)
  assert_eq(mg.margaui, true)
  assert_eq(tw.paths, mg.paths)
  assert_eq(tw.out, mg.out)
}

///|
test "gen-css takes several roots and every flag" {
  let plan = css_plan([
    "a/one.html", "b/", "--out", "out.css", "--entry", "site.css", "--classes", "extra.txt",
    "--print-classes", "--polyfills", "1",
  ])
  assert_eq(plan.paths, ["a/one.html", "b/"])
  assert_eq(plan.out, Some("out.css"))
  assert_eq(plan.entry, Some("site.css"))
  assert_eq(plan.extra_classes, Some("extra.txt"))
  assert_eq(plan.print_classes, true)
  assert_eq(plan.polyfills, 1)
}

///|
test "gen-css accepts --flag=value as well as --flag value" {
  let plan = css_plan(["--out=out.css", "--polyfills=0", "--entry=e.css"])
  assert_eq(plan.out, Some("out.css"))
  assert_eq(plan.polyfills, 0)
  assert_eq(plan.entry, Some("e.css"))
}

///|
test "gen-css rejects a polyfill level the compiler does not have" {
  let emit = match plan_css(["--polyfills", "9"]) {
    Done(emit) => emit
    _ => abort("expected a Done outcome")
  }
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("'--polyfills' expects 0, 1, 2, 3, got '9'"))
  // The hint is the flag's own registry description, so what 1 and 2 mean
  // does not have to be written a second time in an error message.
  assert_true(emit.err.contains("1=@property"))
}

///|
test "gen-css rejects an unknown flag, naming the command it was given to" {
  let emit = match @cli.plan(["gen-margaui-css", "--nope"]) {
    Done(emit) => emit
    _ => abort("expected a Done outcome")
  }
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("unknown flag '--nope' for gen-margaui-css"))
}

///|
test "gen-css -h prints the command's help" {
  let emit = match plan_css(["-h"]) {
    Done(emit) => emit
    _ => abort("expected a Done outcome")
  }
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.contains("tutuca gen-tailwind-css"))
  assert_true(emit.out.contains("--print-classes"))
}

// --- collect_view_classes -------------------------------------------------

///|
fn classes_of(source : String) -> Array[String] {
  match @cli.collect_view_classes([("t.html", source)]) {
    Ok(classes) => classes
    Err(shape) => abort("collect failed: \{shape.message}")
  }
}

///|
test "collect_view_classes gathers literal classes across views and files" {
  let classes = classes_of(
    (
      #|<template><div class="card p-4"><span class="badge">x</span></div></template>
      #|<template id="row"><li class="row p-4"></li></template>
    ),
  )
  assert_eq(classes, ["badge", "card", "p-4", "row"])
}

///|
test "collect_view_classes reads :class and @if.class literals" {
  let classes = classes_of(
    (
      #|<template>
      #|  <a @if.class="equals? .tab 'a'" @then="'tab tab-active'" @else="'tab'"></a>
      #|  <b :class="$'badge badge-{.kind}'"></b>
      #|</template>
    ),
  )
  // The literal fragments only: the interpolated tail of the template string is
  // not a class name that exists in the source.
  assert_true(classes.contains("tab"))
  assert_true(classes.contains("tab-active"))
  assert_true(classes.contains("badge"))
  // The literal PREFIX of the interpolated fragment survives the split, so
  // "badge-" is collected as if it were a class. It compiles to nothing, which
  // is why this is harmless — but it is also why --print-classes output has
  // stubs in it, and why the real name needs --classes.
  assert_true(classes.contains("badge-"))
}

///|
/// A macro body is only scannable once expanded, which is why collection runs
/// through `build_views` rather than the raw parse.
test "collect_view_classes sees classes inside an expanded macro" {
  let classes = classes_of(
    (
      #|<template id="macro:chip" data-tone="'neutral'">
      #|  <span class="chip chip-sm" :data-tone="^tone"></span>
      #|</template>
      #|<template><div class="wrap"><x:chip></x:chip></div></template>
    ),
  )
  assert_true(classes.contains("wrap"))
  assert_true(classes.contains("chip"))
  assert_true(classes.contains("chip-sm"))
}

///|
test "collect_view_classes reports the file a bad view came from" {
  let shape = match
    @cli.collect_view_classes([("broken.html", "oops<template></template>")]) {
    Err(shape) => shape
    Ok(_) => abort("expected the malformed view to fail")
  }
  assert_eq(shape.code, @cli.CODE_VIEW_GEN_FAILED)
  assert_eq(shape.where_, Some("broken.html"))
  assert_true(shape.message.has_prefix("broken.html:"))
}

///|
/// Alphabetical, not MoonBit's `String` order — which sorts by length first and
/// would open the list with every one-character class name.
test "the collected class list is byte-lexicographic" {
  let classes = classes_of(
    (
      #|<template><div class="on b add btn"></div></template>
    ),
  )
  assert_eq(classes, ["add", "b", "btn", "on"])
}

///|
test "class_list_text prints one class per line" {
  assert_eq(@cli.class_list_text(["a", "b"]), "a\nb\n")
  assert_eq(@cli.class_list_text([]), "")
}

///|
test "gen_css_success counts views and classes" {
  assert_eq(
    @cli.gen_css_success("app.css", files=1, classes=1),
    "generated app.css from 1 view (1 class)\n",
  )
  assert_eq(
    @cli.gen_css_success("app.css", files=24, classes=248),
    "generated app.css from 24 views (248 classes)\n",
  )
}
