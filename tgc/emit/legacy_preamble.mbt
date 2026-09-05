// THE OLD ROUTE. Deleted when the wap backend lands — do not build on it.
//
// `tgc/emit` still emits Wax SOURCE and still prepends the `tgc/1` preamble to
// it. `tgc/abi` has moved on: the format is `tgc/2` and its preamble is wap, so
// `@abi.preamble_wax` is gone and this is the text it used to answer, kept
// HERE, inside the one package that is mid-rewrite, rather than left in `abi`
// where it would be a second spelling of a structural type — which is the exact
// thing that package exists to prevent.
//
// Nothing else may read it. When `emit` builds wap AST this file goes, and with
// it the last copy of the `tgc/1` type section outside git history.

///|
fn legacy_preamble_wax() -> String {
  let src =
    #|// tgc/1 — the canonical preamble. FROZEN. Every tgc module carries it verbatim.
    #|//
    #|// Wasm GC canonicalizes a recursion group structurally, so two modules that
    #|// declare this group receive the SAME runtime types: a reference built in one
    #|// is readable in the other with no conversion, no linker and no registry.
    #|// Adding a type to the group, reordering it, or changing one field breaks the
    #|// identity of EVERY type in it. Extend through tg_ext instead.
    #|
    #|// UTF-8 text AND binary. Its own group, so a later singleton cannot perturb
    #|// the core one.
    #|type tg_bytes = [mut i8];
    #|
    #|rec {
    #|    // kind 0 is Null. `ref.null` is not null-the-value, it is ABSENCE: "no such
    #|    // field" as against "the field is null".
    #|    type tg_val     = open { kind: i32 };
    #|    type tg_vals    = [mut &?tg_val];
    #|    type tg_entry   = { key: &tg_bytes, value: mut &?tg_val };
    #|    type tg_entries = [mut &?tg_entry];
    #|
    #|    // The two vtable slots. `get` is separate only because it runs once per
    #|    // `.name` per render; everything else is one op-coded `call`, so the op
    #|    // space can grow without the group changing.
    #|    type tg_get  = fn(&tg_inst, &tg_bytes) -> &?tg_val;
    #|    type tg_call = fn(&tg_inst, i32, &tg_bytes, &tg_vals, &?tg_val) -> &?tg_val;
    #|    type tg_fn   = fn(&tg_vals, &?eq) -> &?tg_val;
    #|
    #|    type tg_vt   = { get: &tg_get, call: &tg_call };
    #|
    #|    // An instance any module can hold, store and call. `state` is `&?eq`: the
    #|    // owner casts it back to its own type, and anyone else TRAPS. Opacity is
    #|    // the engine's, not a convention's.
    #|    type tg_inst = {
    #|        vt:    &tg_vt,
    #|        desc:  &tg_val,
    #|        state: &?eq,
    #|        id:    i64,
    #|    };
    #|
    #|    type tg_bool    : tg_val = { .., value: i32 };
    #|    type tg_num     : tg_val = { .., value: f64 };
    #|    type tg_int     : tg_val = { .., value: i64 };
    #|    type tg_str     : tg_val = { .., value: &tg_bytes };
    #|    type tg_bin     : tg_val = { .., value: &tg_bytes };
    #|    type tg_instant : tg_val = { .., secs: i64, nanos: i32 };
    #|    // Capacity plus length: a wasm-GC array is fixed-length, so a growable
    #|    // list amortizes over a longer backing store.
    #|    type tg_list    : tg_val = { .., items: mut &tg_vals, count: mut i32 };
    #|    // An entry array rather than a hash map: tutuca's maps are insertion
    #|    // ordered and `@each` renders in that order.
    #|    type tg_map     : tg_val = { .., entries: mut &tg_entries, count: mut i32 };
    #|    type tg_func    : tg_val = { .., call: &tg_fn, env: &?eq };
    #|    type tg_comp    : tg_val = { .., value: &tg_inst };
    #|    // The ONE extension point. A tag nobody knows is a value nobody reads,
    #|    // which is survivable; a group nobody shares is a module nobody links.
    #|    type tg_ext     : tg_val = { .., ext_kind: i32, payload: &?eq };
    #|}
  src
}
