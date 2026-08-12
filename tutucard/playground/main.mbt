// The executable shell: install the entry points when the script loads.
//
// An executable rather than a library for the same reason
// `playground/viewgen_js` is one — the page loads one script and expects
// `globalThis.__tutucard` to be there afterwards, with nothing to call first.

///|
fn main {
  install()
}
