///|
/// Compile the margaui/Tailwind utility classes `classes` into CSS.
///
/// `classes` is the literal class set tutuca's `collect_classes()` gathered from
/// the compiled views; candidate discovery is the caller's job (the compiler
/// does not scan content). The margaui `@import` graph is resolved entirely
/// in-memory from the embedded bundle, so this runs on wasm-gc (no filesystem)
/// through the sync compile path. Injecting the result is the host's job:
/// `@wglue.inject_style(doc, "margaui-css", compile_classes(...))`.
pub fn compile_classes(classes : ArrayView[String]) -> String raise {
  let loader = @tw.MemoryStylesheetLoader::new(files=margaui_bundle)
  @tw.compile_sync(
    margaui_entry,
    options=@tw.CompileOptions::new(sync_loader=loader),
  ).build(classes)
}
