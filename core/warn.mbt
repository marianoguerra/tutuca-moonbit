// Runtime warning hook: the port's equivalent of the JS console.warn calls
// sprinkled through the value runtime (mk404Handler, unsupported wraps).

///|
/// Where runtime warnings go. Defaults to println (the closest portable
/// analogue of JS console.warn); a host can redirect it — e.g. into an error
/// pane or the browser console — without threading a context through eval.
pub let warn_hook : Ref[(String) -> Unit] = Ref(msg => println(msg))

///|
/// Report a runtime warning through `warn_hook`.
pub fn warn(msg : String) -> Unit {
  (warn_hook.val)(msg)
}
