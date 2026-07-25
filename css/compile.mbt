///|
/// Compile the Tailwind utility classes `classes` into CSS.
///
/// The stylesheets are stock Tailwind — theme, preflight and utilities from the
/// npm release the compiler port is derived from (see
/// `scripts/fetch-tailwind.mjs`), with no margaui component layers. Use
/// `compile_margaui` for those.
pub fn compile_tailwind(
  classes : ArrayView[String],
  polyfills? : Int = @tw.POLYFILL_ALL,
) -> String raise {
  compile_with(tailwind_entry, tailwind_bundle, classes, polyfills)
}

///|
/// Compile the margaui/Tailwind utility classes `classes` into CSS.
///
/// margaui's entry `@import`s `./tw/*` on top of its own component layers, and
/// those three files live in `tailwind_bundle` rather than `margaui_bundle` — so
/// this resolves against both maps. That is what keeps margaui on the same
/// Tailwind the compiler was ported from; margaui's checkout carries its own
/// hand-maintained tw/*.css, and they have run a minor version behind.
pub fn compile_margaui(
  classes : ArrayView[String],
  polyfills? : Int = @tw.POLYFILL_ALL,
) -> String raise {
  compile_with(
    margaui_entry,
    [..tailwind_bundle, ..margaui_bundle],
    classes,
    polyfills,
  )
}

///|
/// Shared body: candidate discovery is the caller's job (the compiler does not
/// scan content), and the `@import` graph is resolved entirely in-memory from
/// the embedded bundle, so this runs on wasm-gc — no filesystem — through the
/// sync compile path. Injecting the result is the host's job:
/// `@wglue.inject_style(doc, "margaui-css", compile_margaui(...))`.
fn compile_with(
  entry : String,
  files : Array[(String, String)],
  classes : ArrayView[String],
  polyfills : Int,
) -> String raise {
  let loader = @tw.MemoryStylesheetLoader::new(files~)
  @tw.compile_sync(
    entry,
    options=@tw.CompileOptions::new(sync_loader=loader, polyfills~),
  ).build(classes)
}
