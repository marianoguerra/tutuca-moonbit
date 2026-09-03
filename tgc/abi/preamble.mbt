///|
/// The frozen rec group, in Wax.
///
/// Read it as the answer to one question: what does a module have to declare so
/// that a reference it builds is the SAME TYPE as a reference a stranger's
/// module built? Everything else in `tgc` follows from this text being identical
/// everywhere.
pub fn preamble_wax() -> String {
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

///|
/// The same types as WAT.
///
/// A hand-written module reads this; so does the message a host prints when a
/// module's group does not match. The two renderings are checked against each
/// other by compiling both and comparing the canonical type sections, which is
/// what "the same types" has to mean here — textual correspondence would not be
/// evidence of anything.
pub fn preamble_wat() -> String {
  let src =
    #|;; tgc/1 — the canonical preamble. FROZEN. See preamble_wax for the argument.
    #|;; A bare type IS a singleton rec group; `(rec ...)` around one member is
    #|;; the same canonical type, and this is the spelling Wax emits.
    #|(type $tg.bytes (sub final (array (mut i8))))
    #|(rec
    #|  (type $tg.val     (sub (struct (field $kind i32))))
    #|  (type $tg.vals    (sub final (array (mut (ref null $tg.val)))))
    #|  (type $tg.entry   (sub final (struct (field $key (ref $tg.bytes))
    #|                                       (field $value (mut (ref null $tg.val))))))
    #|  (type $tg.entries (sub final (array (mut (ref null $tg.entry)))))
    #|  (type $tg.get     (sub final (func (param (ref $tg.inst) (ref $tg.bytes))
    #|                                     (result (ref null $tg.val)))))
    #|  (type $tg.call    (sub final (func (param (ref $tg.inst) i32 (ref $tg.bytes)
    #|                                            (ref $tg.vals) (ref null $tg.val))
    #|                                     (result (ref null $tg.val)))))
    #|  (type $tg.fn      (sub final (func (param (ref $tg.vals) (ref null eq))
    #|                                     (result (ref null $tg.val)))))
    #|  (type $tg.vt      (sub final (struct (field $get  (ref $tg.get))
    #|                                       (field $call (ref $tg.call)))))
    #|  (type $tg.inst    (sub final (struct (field $vt    (ref $tg.vt))
    #|                                       (field $desc  (ref $tg.val))
    #|                                       (field $state (ref null eq))
    #|                                       (field $id    i64))))
    #|  (type $tg.bool    (sub final $tg.val (struct (field $kind i32) (field $value i32))))
    #|  (type $tg.num     (sub final $tg.val (struct (field $kind i32) (field $value f64))))
    #|  (type $tg.int     (sub final $tg.val (struct (field $kind i32) (field $value i64))))
    #|  (type $tg.str     (sub final $tg.val (struct (field $kind i32) (field $value (ref $tg.bytes)))))
    #|  (type $tg.bin     (sub final $tg.val (struct (field $kind i32) (field $value (ref $tg.bytes)))))
    #|  (type $tg.instant (sub final $tg.val (struct (field $kind i32) (field $secs i64)
    #|                                                                (field $nanos i32))))
    #|  (type $tg.list    (sub final $tg.val (struct (field $kind i32)
    #|                                               (field $items (mut (ref $tg.vals)))
    #|                                               (field $count (mut i32)))))
    #|  (type $tg.map     (sub final $tg.val (struct (field $kind i32)
    #|                                               (field $entries (mut (ref $tg.entries)))
    #|                                               (field $count (mut i32)))))
    #|  (type $tg.func    (sub final $tg.val (struct (field $kind i32) (field $call (ref $tg.fn))
    #|                                                                (field $env (ref null eq)))))
    #|  (type $tg.comp    (sub final $tg.val (struct (field $kind i32) (field $value (ref $tg.inst)))))
    #|  (type $tg.ext     (sub final $tg.val (struct (field $kind i32) (field $ext_kind i32)
    #|                                                                (field $payload (ref null eq)))))
    #|)
  src
}
