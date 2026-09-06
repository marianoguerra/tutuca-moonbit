;; A — Dashboard. Hand-written WAT over the canonical preamble, which the
;; builder prepends: the author writes the module, never the types.
;;
;; It holds OTHER PEOPLE'S components. Not tokens for them, not paths to them —
;; the instances themselves, in its own state, in a list it can walk. `total`
;; and `labels` read a field THROUGH each child, which is the operation the
;; current format refuses at compile time ("a card cannot read or write through
;; one — the instance belongs to the host and a guest holds only a token").
;;
;; Nothing here knows which module made a child, and there is nowhere it could
;; find out that would matter: a child is a `tg.inst`, its vtable is two
;; funcrefs, and calling one is `call_ref`.

  (import "tut" "str_eq"
    (func $str_eq (param (ref $tgabi__tg_bytes)) (param (ref $tgabi__tg_bytes)) (result i32)))
  ;; `(type $tgabi__tg_get)` and `(type $tgabi__tg_call)`, not a same-shaped inline signature:
  ;; the shared vocabulary's types are FROZEN types too, so this import is
  ;; checked against the group rather than against a singleton that merely looks
  ;; like it.
;; Declared INLINE rather than by naming `$tgabi__tg_get`. Under `tgc/1` these
  ;; bound to the frozen function types so the link would check against the
  ;; whole group; under `tgc/2` the group is the four types that cycle, and
  ;; every one of these mentions `$tgabi__tg_inst`, which is in it. A parameter
  ;; carries its group's identity, so the check survives — and the runtime
  ;; exports these as ordinary functions, which is what they are.
  (import "tut" "get_field" (func $get_field (type $tgabi__tg_get)))
  (import "tut" "call_op" (func $call_op (type $tgabi__tg_call)))
  (import "tut" "no_args" (func $no_args (result (ref $tgabi__tg_vals))))

  ;; The state. Its own type, outside the frozen group, which is the point of
  ;; `state` being `eqref`: nobody else can name this, and `ref.cast` traps for
  ;; anyone who tries.
  (type $dash (sub final (struct (field $slots (ref $tgabi__tg_vals)))))

  (global $n.slots (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 5 (i32.const 115) (i32.const 108) (i32.const 111) (i32.const 116) (i32.const 115)))
  (global $n.total (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 5 (i32.const 116) (i32.const 111) (i32.const 116) (i32.const 97) (i32.const 108)))
  (global $n.labels (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 6 (i32.const 108) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108) (i32.const 115)))
  (global $n.count (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 5 (i32.const 99) (i32.const 111) (i32.const 117) (i32.const 110) (i32.const 116)))
  (global $n.label (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 5 (i32.const 108) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108)))
  (global $n.bump (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 4 (i32.const 98) (i32.const 117) (i32.const 109) (i32.const 112)))
  (global $n.bumpAll (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 7 (i32.const 98) (i32.const 117) (i32.const 109) (i32.const 112) (i32.const 65) (i32.const 108) (i32.const 108)))
  (global $n.module (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 6 (i32.const 109) (i32.const 111) (i32.const 100) (i32.const 117) (i32.const 108) (i32.const 101)))
    ;; `name`, which is what a component descriptor calls itself — the manifest's
  ;; spelling, and there is one description of a component rather than two.
  (global $n.component (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 4 (i32.const 110) (i32.const 97) (i32.const 109) (i32.const 101)))
  (global $n.protocols (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 9 (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 99) (i32.const 111) (i32.const 108) (i32.const 115)))
  (global $n.Dashboard (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 9 (i32.const 68) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.modname (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 19 (i32.const 116) (i32.const 103) (i32.const 99) (i32.const 46) (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 46) (i32.const 100) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.compname (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 9 (i32.const 68) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.tile (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 15 (i32.const 116) (i32.const 117) (i32.const 116) (i32.const 46) (i32.const 100) (i32.const 101) (i32.const 109) (i32.const 111) (i32.const 46) (i32.const 116) (i32.const 105) (i32.const 108) (i32.const 101) (i32.const 64) (i32.const 49)))
  (global $n.holder (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 17 (i32.const 116) (i32.const 117) (i32.const 116) (i32.const 46) (i32.const 100) (i32.const 101) (i32.const 109) (i32.const 111) (i32.const 46) (i32.const 104) (i32.const 111) (i32.const 108) (i32.const 100) (i32.const 101) (i32.const 114) (i32.const 64) (i32.const 49)))

  (global $n.peerLabels (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 10 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114) (i32.const 76) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108) (i32.const 115)))
  (global $n.peerLabel (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 9 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114) (i32.const 76) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108)))

  (global $n.deep (ref $tgabi__tg_bytes) (array.new_fixed $tgabi__tg_bytes 4 (i32.const 100) (i32.const 101) (i32.const 101) (i32.const 112)))

  (elem declare func $get $call)
  (global $vt (ref $tgabi__tg_vt) (struct.new $tgabi__tg_vt (ref.func $get) (ref.func $call)))
  (global $next_id (mut i64) (i64.const 1))

  (global (export "tgc.abi") i32 (i32.const 1))

  ;; ── the two vtable slots ──────────────────────────────────────────────

  ;; `(type $tgabi__tg_get)` and not an inline signature. An inline one would be an
  ;; identical-looking type in a NEW singleton group, and `ref.func` of it is
  ;; not a `(ref $tgabi__tg_get)` — which is the freeze rule biting at the smallest
  ;; possible scale, and worth meeting here rather than at a link failure.
  (func $get (type $tgabi__tg_get)
             (param $self (ref $tgabi__tg_inst)) (param $name (ref $tgabi__tg_bytes))
             (result (ref null $tgabi__tg_val))
    (local $st (ref $dash))
    (local.set $st
      (ref.cast (ref $dash) (struct.get $tgabi__tg_inst $state (local.get $self))))
    (if (call $str_eq (local.get $name) (global.get $n.slots))
      (then (return (call $as_list (struct.get $dash $slots (local.get $st))))))
    (if (call $str_eq (local.get $name) (global.get $n.total))
      (then (return (call $total (local.get $st)))))
    (if (call $str_eq (local.get $name) (global.get $n.labels))
      (then (return (call $through (local.get $st) (global.get $n.label)))))
    ;; The RE-ENTRANT path. Each child is asked for `peerLabel`, and a child
    ;; whose peer is this very Dashboard answers by calling back in — so this
    ;; function is on the stack twice, through two other modules. The Component
    ;; Model forbids exactly this ("forbids re-entering a component while a call
    ;; into it is active"); core wasm has no such rule and needs none.
    (if (call $str_eq (local.get $name) (global.get $n.peerLabels))
      (then (return (call $through (local.get $st) (global.get $n.peerLabel)))))
    ;; The UNBOUNDED case, and it is here to be caught rather than used: `deep`
    ;; reads `deep` through every child, so two of these holding each other
    ;; recurse until something stops them. `tgc/SECURITY.md` §4 says what does.
    (if (call $str_eq (local.get $name) (global.get $n.deep))
      (then (return (call $through (local.get $st) (global.get $n.deep)))))
    ;; So that a child asking THIS one for a label has something to hear.
    (if (call $str_eq (local.get $name) (global.get $n.label))
      (then (return (struct.new $tgabi__tg_str (i32.const 4) (global.get $n.compname)))))
    ;; Absence, not null-the-value: there is no such field.
    (ref.null $tgabi__tg_val))

  (func $call (type $tgabi__tg_call)
              (param $self (ref $tgabi__tg_inst)) (param $op i32)
              (param $name (ref $tgabi__tg_bytes)) (param $args (ref $tgabi__tg_vals))
              (param $v (ref null $tgabi__tg_val))
              (result (ref null $tgabi__tg_val))
    ;; OpImplements: a holder, and not a tile.
    (if (i32.eq (local.get $op) (i32.const 11))
      (then (return (struct.new $tgabi__tg_bool (i32.const 1)
        (call $str_eq (local.get $name) (global.get $n.holder))))))
    ;; OpWithField — the copy-on-write write-through a host path writes
    ;; through, and the only way to give this one a child AFTER it was built. A
    ;; cycle needs that: two dashboards cannot both be constructed holding the
    ;; other.
    (if (i32.eq (local.get $op) (i32.const 1))
      (then
        (if (call $str_eq (local.get $name) (global.get $n.slots))
          (then
            (if (ref.test (ref $tgabi__tg_list) (local.get $v))
              (then
                (return
                  (struct.new $tgabi__tg_comp (i32.const 10)
                    (call $instance
                      (struct.get $tgabi__tg_list $items
                        (ref.cast (ref $tgabi__tg_list) (local.get $v)))
                      (struct.get $tgabi__tg_inst $desc (local.get $self)))))))))))
    ;; OpHandleMessage
    (if (i32.eq (local.get $op) (i32.const 2))
      (then
        (if (call $str_eq (local.get $name) (global.get $n.bumpAll))
          (then (return (call $bump_all (local.get $self)))))))
    ;; An op or a name this module does not answer. The same answer an older
    ;; module gives for an op invented after it was built, which is what makes
    ;; the op space extensible rather than merely large.
    (ref.null $tgabi__tg_val))

  ;; ── reading THROUGH the children ──────────────────────────────────────

  (func $total (param $st (ref $dash)) (result (ref null $tgabi__tg_val))
    (local $slots (ref $tgabi__tg_vals)) (local $i i32) (local $n i32)
    (local $acc i64) (local $v (ref null $tgabi__tg_val))
    (local.set $slots (struct.get $dash $slots (local.get $st)))
    (local.set $n (array.len (local.get $slots)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $v
          (call $get_field (call $child (local.get $slots) (local.get $i))
                           (global.get $n.count)))
        ;; A child that has no `count` contributes nothing. It is not an error
        ;; for a stranger's component to be shaped differently.
        (if (ref.test (ref $tgabi__tg_int) (local.get $v))
          (then (local.set $acc (i64.add (local.get $acc)
            (struct.get $tgabi__tg_int $value (ref.cast (ref $tgabi__tg_int) (local.get $v)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (struct.new $tgabi__tg_int (i32.const 3) (local.get $acc)))

  ;; One field of every child, gathered. The field is a PARAMETER because
  ;; "read this name through each of them" is one operation, not two.
  (func $through (param $st (ref $dash)) (param $field (ref $tgabi__tg_bytes))
        (result (ref null $tgabi__tg_val))
    (local $slots (ref $tgabi__tg_vals)) (local $i i32) (local $n i32)
    (local $out (ref $tgabi__tg_vals))
    (local.set $slots (struct.get $dash $slots (local.get $st)))
    (local.set $n (array.len (local.get $slots)))
    (local.set $out (array.new $tgabi__tg_vals (ref.null $tgabi__tg_val) (local.get $n)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (array.set $tgabi__tg_vals (local.get $out) (local.get $i)
          (call $get_field (call $child (local.get $slots) (local.get $i))
                           (local.get $field)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (call $as_list (local.get $out)))

  ;; ── the transition ────────────────────────────────────────────────────

  ;; Copy-on-write, and it is the language's model rather than an imitation of
  ;; it: each child answers with its own successor, and this builds one of its
  ;; own around them. A child that answers null did not change and is kept.
  (func $bump_all (param $self (ref $tgabi__tg_inst)) (result (ref null $tgabi__tg_val))
    (local $st (ref $dash)) (local $slots (ref $tgabi__tg_vals))
    (local $out (ref $tgabi__tg_vals)) (local $i i32) (local $n i32)
    (local $answer (ref null $tgabi__tg_val))
    (local.set $st
      (ref.cast (ref $dash) (struct.get $tgabi__tg_inst $state (local.get $self))))
    (local.set $slots (struct.get $dash $slots (local.get $st)))
    (local.set $n (array.len (local.get $slots)))
    (local.set $out (array.new $tgabi__tg_vals (ref.null $tgabi__tg_val) (local.get $n)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $answer
          (call $call_op (call $child (local.get $slots) (local.get $i))
                (i32.const 2) (global.get $n.bump) (call $no_args)
                (ref.null $tgabi__tg_val)))
        (array.set $tgabi__tg_vals (local.get $out) (local.get $i)
          (select (result (ref null $tgabi__tg_val))
            (local.get $answer)
            (array.get $tgabi__tg_vals (local.get $slots) (local.get $i))
            (ref.test (ref $tgabi__tg_comp) (local.get $answer))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (struct.new $tgabi__tg_comp (i32.const 10)
      (call $instance (local.get $out)
        (struct.get $tgabi__tg_inst $desc (local.get $self)))))

  ;; ── construction ──────────────────────────────────────────────────────

  (func (export "tgc.make") (param $name (ref $tgabi__tg_bytes))
        (param $args (ref null $tgabi__tg_val)) (result (ref null $tgabi__tg_inst))
    (if (i32.eqz (call $str_eq (local.get $name) (global.get $n.compname)))
      (then (return (ref.null $tgabi__tg_inst))))
    (return_call $instance
      (if (result (ref $tgabi__tg_vals)) (ref.test (ref $tgabi__tg_list) (local.get $args))
        (then (struct.get $tgabi__tg_list $items
                (ref.cast (ref $tgabi__tg_list) (local.get $args))))
        (else (array.new_fixed $tgabi__tg_vals 0)))
      (call $describe)))

  (func $instance (param $slots (ref $tgabi__tg_vals)) (param $desc (ref $tgabi__tg_val))
        (result (ref $tgabi__tg_inst))
    (global.set $next_id (i64.add (global.get $next_id) (i64.const 1)))
    (struct.new $tgabi__tg_inst (global.get $vt) (local.get $desc)
      (struct.new $dash (local.get $slots)) (global.get $next_id)))

  ;; The manifest, as an ordinary value. Not a sidecar file, not an archive
  ;; member: a module that says what it is needs no packer, and a toolchain that
  ;; has never heard of this repo can still produce one.
  (func $describe (result (ref $tgabi__tg_val))
    (struct.new $tgabi__tg_map (i32.const 8)
      (array.new_fixed $tgabi__tg_entries 3
        (struct.new $tgabi__tg_entry (global.get $n.module)
          (struct.new $tgabi__tg_str (i32.const 4) (global.get $n.modname)))
        (struct.new $tgabi__tg_entry (global.get $n.component)
          (struct.new $tgabi__tg_str (i32.const 4) (global.get $n.compname)))
        (struct.new $tgabi__tg_entry (global.get $n.protocols)
          (call $as_list (array.new_fixed $tgabi__tg_vals 1
            (struct.new $tgabi__tg_str (i32.const 4) (global.get $n.holder))))))
      (i32.const 3)))

  (func (export "tgc.describe") (result (ref $tgabi__tg_val)) (return_call $describe))

  (func (export "tgc.serve") (param $name (ref $tgabi__tg_bytes))
        (param $args (ref $tgabi__tg_vals)) (result (ref null $tgabi__tg_val))
    (ref.null $tgabi__tg_val))

  ;; ── helpers ───────────────────────────────────────────────────────────

  (func $as_list (param $items (ref $tgabi__tg_vals)) (result (ref null $tgabi__tg_val))
    (struct.new $tgabi__tg_list (i32.const 7) (local.get $items)
      (array.len (local.get $items))))

  (func $child (param $slots (ref $tgabi__tg_vals)) (param $i i32)
        (result (ref $tgabi__tg_inst))
    (struct.get $tgabi__tg_comp $value
      (ref.cast (ref $tgabi__tg_comp) (array.get $tgabi__tg_vals (local.get $slots) (local.get $i)))))
