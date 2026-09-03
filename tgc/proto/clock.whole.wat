(module
  ;; C — Clock. A COMPLETE module, carrying its own preamble, spelled its own
  ;; way: different type names, different field names, an unrelated singleton
  ;; group declared first, and the functions in a different order.
  ;;
  ;; Nothing here came from this repository except the SHAPE of the recursion
  ;; group. That is the claim the whole format rests on — wasm GC canonicalizes
  ;; a rec group structurally, so a module written by somebody who has only read
  ;; the spec receives the same runtime types as one this repo's compiler
  ;; emitted — and it is why this file exists rather than a third copy of the
  ;; canonical spelling.
  ;;
  ;; It also carries the two arms the format added and the old one could not:
  ;; an `Instant` and a `Bin`, both of which survive a round trip through two
  ;; other modules because a value is a reference rather than a flattened
  ;; triple.

  ;; An unrelated type, declared FIRST, to move every index in the module.
  (type $unrelated (sub final (array (mut i32))))

  (type $V_bytes (sub final (array (mut i8))))
  (rec
    (type $V (sub (struct (field $k i32))))
    (type $V_seq (sub final (array (mut (ref null $V)))))
    (type $V_pair (sub final (struct (field $key (ref $V_bytes))
                                     (field $val (mut (ref null $V))))))
    (type $V_pairs (sub final (array (mut (ref null $V_pair)))))
    (type $V_read (sub final (func (param (ref $V_obj) (ref $V_bytes))
                                   (result (ref null $V)))))
    (type $V_do (sub final (func (param (ref $V_obj) i32 (ref $V_bytes)
                                        (ref $V_seq) (ref null $V))
                                 (result (ref null $V)))))
    (type $V_lambda (sub final (func (param (ref $V_seq) (ref null eq))
                                     (result (ref null $V)))))
    (type $V_table (sub final (struct (field $read (ref $V_read))
                                      (field $do (ref $V_do)))))
    (type $V_obj (sub final (struct (field $table (ref $V_table))
                                    (field $about (ref $V))
                                    (field $inner (ref null eq))
                                    (field $ident i64))))
    (type $V_yes (sub final $V (struct (field $k i32) (field $val i32))))
    (type $V_dbl (sub final $V (struct (field $k i32) (field $val f64))))
    (type $V_whole (sub final $V (struct (field $k i32) (field $val i64))))
    (type $V_text (sub final $V (struct (field $k i32) (field $val (ref $V_bytes)))))
    (type $V_blob (sub final $V (struct (field $k i32) (field $val (ref $V_bytes)))))
    (type $V_when (sub final $V (struct (field $k i32) (field $sec i64)
                                                       (field $nano i32))))
    (type $V_seqv (sub final $V (struct (field $k i32)
                                        (field $xs (mut (ref $V_seq)))
                                        (field $n (mut i32)))))
    (type $V_mapv (sub final $V (struct (field $k i32)
                                        (field $ps (mut (ref $V_pairs)))
                                        (field $n (mut i32)))))
    (type $V_lam (sub final $V (struct (field $k i32) (field $f (ref $V_lambda))
                                                      (field $env (ref null eq)))))
    (type $V_objv (sub final $V (struct (field $k i32) (field $val (ref $V_obj)))))
    (type $V_more (sub final $V (struct (field $k i32) (field $which i32)
                                                       (field $load (ref null eq)))))
  )

  (import "tut" "str_eq"
    (func $eq (param (ref $V_bytes)) (param (ref $V_bytes)) (result i32)))
  ;; The frozen function type, under this module's own name for it. The import
  ;; is checked against the group, not against a singleton that looks like it.
  (import "tut" "get_field" (func $peek (type $V_read)))

  (type $clock (sub final (struct (field $sec i64) (field $nano i32)
                                  (field $peer (ref null $V_obj)))))

  (global $s.at (ref $V_bytes) (array.new_fixed $V_bytes 2 (i32.const 97) (i32.const 116)))
  (global $s.label (ref $V_bytes) (array.new_fixed $V_bytes 5 (i32.const 108) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108)))
  (global $s.blob (ref $V_bytes) (array.new_fixed $V_bytes 4 (i32.const 98) (i32.const 108) (i32.const 111) (i32.const 98)))
  (global $s.peer (ref $V_bytes) (array.new_fixed $V_bytes 4 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114)))
  (global $s.peerCount (ref $V_bytes) (array.new_fixed $V_bytes 9 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114) (i32.const 67) (i32.const 111) (i32.const 117) (i32.const 110) (i32.const 116)))
  (global $s.bump (ref $V_bytes) (array.new_fixed $V_bytes 4 (i32.const 98) (i32.const 117) (i32.const 109) (i32.const 112)))
  (global $s.tile (ref $V_bytes) (array.new_fixed $V_bytes 15 (i32.const 116) (i32.const 117) (i32.const 116) (i32.const 46) (i32.const 100) (i32.const 101) (i32.const 109) (i32.const 111) (i32.const 46) (i32.const 116) (i32.const 105) (i32.const 108) (i32.const 101) (i32.const 64) (i32.const 49)))
  (global $s.module (ref $V_bytes) (array.new_fixed $V_bytes 6 (i32.const 109) (i32.const 111) (i32.const 100) (i32.const 117) (i32.const 108) (i32.const 101)))
  (global $s.component (ref $V_bytes) (array.new_fixed $V_bytes 4 (i32.const 110) (i32.const 97) (i32.const 109) (i32.const 101)))
  (global $s.protocols (ref $V_bytes) (array.new_fixed $V_bytes 9 (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 99) (i32.const 111) (i32.const 108) (i32.const 115)))
  (global $s.modname (ref $V_bytes) (array.new_fixed $V_bytes 15 (i32.const 116) (i32.const 103) (i32.const 99) (i32.const 46) (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 46) (i32.const 99) (i32.const 108) (i32.const 111) (i32.const 99) (i32.const 107)))
  (global $s.compname (ref $V_bytes) (array.new_fixed $V_bytes 5 (i32.const 67) (i32.const 108) (i32.const 111) (i32.const 99) (i32.const 107)))
  (global $s.count (ref $V_bytes) (array.new_fixed $V_bytes 5 (i32.const 99) (i32.const 111) (i32.const 117) (i32.const 110) (i32.const 116)))

  (elem declare func $read $do)
  (global $table (ref $V_table) (struct.new $V_table (ref.func $read) (ref.func $do)))
  (global $ids (mut i64) (i64.const 900))
  (global (export "tgc.abi") i32 (i32.const 1))

  (func $read (type $V_read)
        (param $self (ref $V_obj)) (param $name (ref $V_bytes))
        (result (ref null $V))
    (local $st (ref $clock))
    (local.set $st (ref.cast (ref $clock) (struct.get $V_obj $inner (local.get $self))))
    (if (call $eq (local.get $name) (global.get $s.at))
      (then (return (struct.new $V_when (i32.const 6)
        (struct.get $clock $sec (local.get $st))
        (struct.get $clock $nano (local.get $st))))))
    ;; A `count` so the Dashboard's `total` has something to add: a clock's
    ;; count is its second. Nothing agreed this beyond the protocol.
    (if (call $eq (local.get $name) (global.get $s.count))
      (then (return (struct.new $V_whole (i32.const 3)
        (struct.get $clock $sec (local.get $st))))))
    (if (call $eq (local.get $name) (global.get $s.label))
      (then (return (struct.new $V_text (i32.const 4) (global.get $s.compname)))))
    ;; Bytes, carried as bytes. The old format had no arm for these at all.
    (if (call $eq (local.get $name) (global.get $s.blob))
      (then (return (struct.new $V_blob (i32.const 5)
        (array.new_fixed $V_bytes 4 (i32.const 0) (i32.const 255)
                                    (i32.const 254) (i32.const 1))))))
    (if (call $eq (local.get $name) (global.get $s.peer))
      (then
        (if (ref.is_null (struct.get $clock $peer (local.get $st)))
          (then (return (ref.null $V))))
        (return (struct.new $V_objv (i32.const 10)
          (ref.as_non_null (struct.get $clock $peer (local.get $st)))))))
    ;; Reading through the peer WHILE this module is inside a call of its own.
    ;; The component model forbids re-entering a component while a call into it
    ;; is active; core wasm has no such rule, so this is simply a call.
    (if (call $eq (local.get $name) (global.get $s.peerCount))
      (then
        (if (ref.is_null (struct.get $clock $peer (local.get $st)))
          (then (return (ref.null $V))))
        (return (call $peek
          (ref.as_non_null (struct.get $clock $peer (local.get $st)))
          (global.get $s.count)))))
    (ref.null $V))

  (func $do (type $V_do)
        (param $self (ref $V_obj)) (param $op i32) (param $name (ref $V_bytes))
        (param $args (ref $V_seq)) (param $v (ref null $V))
        (result (ref null $V))
    (local $st (ref $clock))
    (if (i32.eq (local.get $op) (i32.const 11))
      (then (return (struct.new $V_yes (i32.const 1)
        (call $eq (local.get $name) (global.get $s.tile))))))
    (local.set $st (ref.cast (ref $clock) (struct.get $V_obj $inner (local.get $self))))
    ;; OpHandleMessage / bump — one second on.
    (if (i32.eq (local.get $op) (i32.const 2))
      (then
        (if (call $eq (local.get $name) (global.get $s.bump))
          (then (return (struct.new $V_objv (i32.const 10)
            (call $make
              (i64.add (struct.get $clock $sec (local.get $st)) (i64.const 1))
              (struct.get $clock $nano (local.get $st))
              (struct.get $clock $peer (local.get $st))
              (struct.get $V_obj $about (local.get $self)))))))))
    ;; OpWithField / peer.
    (if (i32.eq (local.get $op) (i32.const 1))
      (then
        (if (call $eq (local.get $name) (global.get $s.peer))
          (then (return (struct.new $V_objv (i32.const 10)
            (call $make
              (struct.get $clock $sec (local.get $st))
              (struct.get $clock $nano (local.get $st))
              (call $as_obj (local.get $v))
              (struct.get $V_obj $about (local.get $self)))))))))
    (ref.null $V))

  (func $as_obj (param $v (ref null $V)) (result (ref null $V_obj))
    (if (ref.test (ref $V_objv) (local.get $v))
      (then (return (struct.get $V_objv $val
        (ref.cast (ref $V_objv) (local.get $v))))))
    (ref.null $V_obj))

  (func $make (param $sec i64) (param $nano i32) (param $peer (ref null $V_obj))
        (param $about (ref $V)) (result (ref $V_obj))
    (global.set $ids (i64.add (global.get $ids) (i64.const 1)))
    (struct.new $V_obj (global.get $table) (local.get $about)
      (struct.new $clock (local.get $sec) (local.get $nano) (local.get $peer))
      (global.get $ids)))

  (func $about (result (ref $V))
    (struct.new $V_mapv (i32.const 8)
      (array.new_fixed $V_pairs 3
        (struct.new $V_pair (global.get $s.module)
          (struct.new $V_text (i32.const 4) (global.get $s.modname)))
        (struct.new $V_pair (global.get $s.component)
          (struct.new $V_text (i32.const 4) (global.get $s.compname)))
        (struct.new $V_pair (global.get $s.protocols)
          (struct.new $V_seqv (i32.const 7)
            (array.new_fixed $V_seq 1
              (struct.new $V_text (i32.const 4) (global.get $s.tile)))
            (i32.const 1))))
      (i32.const 3)))

  (func (export "tgc.describe") (result (ref $V)) (return_call $about))

  (func (export "tgc.make") (param $name (ref $V_bytes)) (param $args (ref null $V))
        (result (ref null $V_obj))
    (if (i32.eqz (call $eq (local.get $name) (global.get $s.compname)))
      (then (return (ref.null $V_obj))))
    ;; The epoch second of 2025-09-03T16:00:00Z, and 123456789 nanoseconds. A
    ;; fixed instant rather than a clock reading, because this module imports no
    ;; clock: what it cannot compute it is given, and here it is given at build
    ;; time.
    (return_call $make (i64.const 1756915200) (i32.const 123456789)
      (ref.null $V_obj) (call $about)))

  (func (export "tgc.serve") (param $name (ref $V_bytes)) (param $args (ref $V_seq))
        (result (ref null $V))
    (ref.null $V))
)
