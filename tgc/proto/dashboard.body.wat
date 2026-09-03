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
    (func $str_eq (param (ref $tg.bytes)) (param (ref $tg.bytes)) (result i32)))
  ;; `(type $tg.get)` and `(type $tg.call)`, not a same-shaped inline signature:
  ;; the shared vocabulary's types are FROZEN types too, so this import is
  ;; checked against the group rather than against a singleton that merely looks
  ;; like it.
  (import "tut" "get_field" (func $get_field (type $tg.get)))
  (import "tut" "call_op" (func $call_op (type $tg.call)))
  (import "tut" "no_args" (func $no_args (result (ref $tg.vals))))

  ;; The state. Its own type, outside the frozen group, which is the point of
  ;; `state` being `eqref`: nobody else can name this, and `ref.cast` traps for
  ;; anyone who tries.
  (type $dash (sub final (struct (field $slots (ref $tg.vals)))))

  (global $n.slots (ref $tg.bytes) (array.new_fixed $tg.bytes 5 (i32.const 115) (i32.const 108) (i32.const 111) (i32.const 116) (i32.const 115)))
  (global $n.total (ref $tg.bytes) (array.new_fixed $tg.bytes 5 (i32.const 116) (i32.const 111) (i32.const 116) (i32.const 97) (i32.const 108)))
  (global $n.labels (ref $tg.bytes) (array.new_fixed $tg.bytes 6 (i32.const 108) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108) (i32.const 115)))
  (global $n.count (ref $tg.bytes) (array.new_fixed $tg.bytes 5 (i32.const 99) (i32.const 111) (i32.const 117) (i32.const 110) (i32.const 116)))
  (global $n.label (ref $tg.bytes) (array.new_fixed $tg.bytes 5 (i32.const 108) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108)))
  (global $n.bump (ref $tg.bytes) (array.new_fixed $tg.bytes 4 (i32.const 98) (i32.const 117) (i32.const 109) (i32.const 112)))
  (global $n.bumpAll (ref $tg.bytes) (array.new_fixed $tg.bytes 7 (i32.const 98) (i32.const 117) (i32.const 109) (i32.const 112) (i32.const 65) (i32.const 108) (i32.const 108)))
  (global $n.module (ref $tg.bytes) (array.new_fixed $tg.bytes 6 (i32.const 109) (i32.const 111) (i32.const 100) (i32.const 117) (i32.const 108) (i32.const 101)))
    ;; `name`, which is what a component descriptor calls itself — the manifest's
  ;; spelling, and there is one description of a component rather than two.
  (global $n.component (ref $tg.bytes) (array.new_fixed $tg.bytes 4 (i32.const 110) (i32.const 97) (i32.const 109) (i32.const 101)))
  (global $n.protocols (ref $tg.bytes) (array.new_fixed $tg.bytes 9 (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 99) (i32.const 111) (i32.const 108) (i32.const 115)))
  (global $n.Dashboard (ref $tg.bytes) (array.new_fixed $tg.bytes 9 (i32.const 68) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.modname (ref $tg.bytes) (array.new_fixed $tg.bytes 19 (i32.const 116) (i32.const 103) (i32.const 99) (i32.const 46) (i32.const 112) (i32.const 114) (i32.const 111) (i32.const 116) (i32.const 111) (i32.const 46) (i32.const 100) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.compname (ref $tg.bytes) (array.new_fixed $tg.bytes 9 (i32.const 68) (i32.const 97) (i32.const 115) (i32.const 104) (i32.const 98) (i32.const 111) (i32.const 97) (i32.const 114) (i32.const 100)))
  (global $n.tile (ref $tg.bytes) (array.new_fixed $tg.bytes 15 (i32.const 116) (i32.const 117) (i32.const 116) (i32.const 46) (i32.const 100) (i32.const 101) (i32.const 109) (i32.const 111) (i32.const 46) (i32.const 116) (i32.const 105) (i32.const 108) (i32.const 101) (i32.const 64) (i32.const 49)))
  (global $n.holder (ref $tg.bytes) (array.new_fixed $tg.bytes 17 (i32.const 116) (i32.const 117) (i32.const 116) (i32.const 46) (i32.const 100) (i32.const 101) (i32.const 109) (i32.const 111) (i32.const 46) (i32.const 104) (i32.const 111) (i32.const 108) (i32.const 100) (i32.const 101) (i32.const 114) (i32.const 64) (i32.const 49)))

  (global $n.peerLabels (ref $tg.bytes) (array.new_fixed $tg.bytes 10 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114) (i32.const 76) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108) (i32.const 115)))
  (global $n.peerLabel (ref $tg.bytes) (array.new_fixed $tg.bytes 9 (i32.const 112) (i32.const 101) (i32.const 101) (i32.const 114) (i32.const 76) (i32.const 97) (i32.const 98) (i32.const 101) (i32.const 108)))

  (elem declare func $get $call)
  (global $vt (ref $tg.vt) (struct.new $tg.vt (ref.func $get) (ref.func $call)))
  (global $next_id (mut i64) (i64.const 1))

  (global (export "tgc.abi") i32 (i32.const 1))

  ;; ── the two vtable slots ──────────────────────────────────────────────

  ;; `(type $tg.get)` and not an inline signature. An inline one would be an
  ;; identical-looking type in a NEW singleton group, and `ref.func` of it is
  ;; not a `(ref $tg.get)` — which is the freeze rule biting at the smallest
  ;; possible scale, and worth meeting here rather than at a link failure.
  (func $get (type $tg.get)
             (param $self (ref $tg.inst)) (param $name (ref $tg.bytes))
             (result (ref null $tg.val))
    (local $st (ref $dash))
    (local.set $st
      (ref.cast (ref $dash) (struct.get $tg.inst $state (local.get $self))))
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
    ;; So that a child asking THIS one for a label has something to hear.
    (if (call $str_eq (local.get $name) (global.get $n.label))
      (then (return (struct.new $tg.str (i32.const 4) (global.get $n.compname)))))
    ;; Absence, not null-the-value: there is no such field.
    (ref.null $tg.val))

  (func $call (type $tg.call)
              (param $self (ref $tg.inst)) (param $op i32)
              (param $name (ref $tg.bytes)) (param $args (ref $tg.vals))
              (param $v (ref null $tg.val))
              (result (ref null $tg.val))
    ;; OpImplements: a holder, and not a tile.
    (if (i32.eq (local.get $op) (i32.const 11))
      (then (return (struct.new $tg.bool (i32.const 1)
        (call $str_eq (local.get $name) (global.get $n.holder))))))
    ;; OpHandleMessage
    (if (i32.eq (local.get $op) (i32.const 2))
      (then
        (if (call $str_eq (local.get $name) (global.get $n.bumpAll))
          (then (return (call $bump_all (local.get $self)))))))
    ;; An op or a name this module does not answer. The same answer an older
    ;; module gives for an op invented after it was built, which is what makes
    ;; the op space extensible rather than merely large.
    (ref.null $tg.val))

  ;; ── reading THROUGH the children ──────────────────────────────────────

  (func $total (param $st (ref $dash)) (result (ref null $tg.val))
    (local $slots (ref $tg.vals)) (local $i i32) (local $n i32)
    (local $acc i64) (local $v (ref null $tg.val))
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
        (if (ref.test (ref $tg.int) (local.get $v))
          (then (local.set $acc (i64.add (local.get $acc)
            (struct.get $tg.int $value (ref.cast (ref $tg.int) (local.get $v)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (struct.new $tg.int (i32.const 3) (local.get $acc)))

  ;; One field of every child, gathered. The field is a PARAMETER because
  ;; "read this name through each of them" is one operation, not two.
  (func $through (param $st (ref $dash)) (param $field (ref $tg.bytes))
        (result (ref null $tg.val))
    (local $slots (ref $tg.vals)) (local $i i32) (local $n i32)
    (local $out (ref $tg.vals))
    (local.set $slots (struct.get $dash $slots (local.get $st)))
    (local.set $n (array.len (local.get $slots)))
    (local.set $out (array.new $tg.vals (ref.null $tg.val) (local.get $n)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (array.set $tg.vals (local.get $out) (local.get $i)
          (call $get_field (call $child (local.get $slots) (local.get $i))
                           (local.get $field)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (call $as_list (local.get $out)))

  ;; ── the transition ────────────────────────────────────────────────────

  ;; Copy-on-write, and it is the language's model rather than an imitation of
  ;; it: each child answers with its own successor, and this builds one of its
  ;; own around them. A child that answers null did not change and is kept.
  (func $bump_all (param $self (ref $tg.inst)) (result (ref null $tg.val))
    (local $st (ref $dash)) (local $slots (ref $tg.vals))
    (local $out (ref $tg.vals)) (local $i i32) (local $n i32)
    (local $answer (ref null $tg.val))
    (local.set $st
      (ref.cast (ref $dash) (struct.get $tg.inst $state (local.get $self))))
    (local.set $slots (struct.get $dash $slots (local.get $st)))
    (local.set $n (array.len (local.get $slots)))
    (local.set $out (array.new $tg.vals (ref.null $tg.val) (local.get $n)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $answer
          (call $call_op (call $child (local.get $slots) (local.get $i))
                (i32.const 2) (global.get $n.bump) (call $no_args)
                (ref.null $tg.val)))
        (array.set $tg.vals (local.get $out) (local.get $i)
          (select (result (ref null $tg.val))
            (local.get $answer)
            (array.get $tg.vals (local.get $slots) (local.get $i))
            (ref.test (ref $tg.comp) (local.get $answer))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (struct.new $tg.comp (i32.const 10)
      (call $instance (local.get $out)
        (struct.get $tg.inst $desc (local.get $self)))))

  ;; ── construction ──────────────────────────────────────────────────────

  (func (export "tgc.make") (param $name (ref $tg.bytes))
        (param $args (ref null $tg.val)) (result (ref null $tg.inst))
    (if (i32.eqz (call $str_eq (local.get $name) (global.get $n.compname)))
      (then (return (ref.null $tg.inst))))
    (return_call $instance
      (if (result (ref $tg.vals)) (ref.test (ref $tg.list) (local.get $args))
        (then (struct.get $tg.list $items
                (ref.cast (ref $tg.list) (local.get $args))))
        (else (array.new_fixed $tg.vals 0)))
      (call $describe)))

  (func $instance (param $slots (ref $tg.vals)) (param $desc (ref $tg.val))
        (result (ref $tg.inst))
    (global.set $next_id (i64.add (global.get $next_id) (i64.const 1)))
    (struct.new $tg.inst (global.get $vt) (local.get $desc)
      (struct.new $dash (local.get $slots)) (global.get $next_id)))

  ;; The manifest, as an ordinary value. Not a sidecar file, not an archive
  ;; member: a module that says what it is needs no packer, and a toolchain that
  ;; has never heard of this repo can still produce one.
  (func $describe (result (ref $tg.val))
    (struct.new $tg.map (i32.const 8)
      (array.new_fixed $tg.entries 3
        (struct.new $tg.entry (global.get $n.module)
          (struct.new $tg.str (i32.const 4) (global.get $n.modname)))
        (struct.new $tg.entry (global.get $n.component)
          (struct.new $tg.str (i32.const 4) (global.get $n.compname)))
        (struct.new $tg.entry (global.get $n.protocols)
          (call $as_list (array.new_fixed $tg.vals 1
            (struct.new $tg.str (i32.const 4) (global.get $n.holder))))))
      (i32.const 3)))

  (func (export "tgc.describe") (result (ref $tg.val)) (return_call $describe))

  (func (export "tgc.serve") (param $name (ref $tg.bytes))
        (param $args (ref $tg.vals)) (result (ref null $tg.val))
    (ref.null $tg.val))

  ;; ── helpers ───────────────────────────────────────────────────────────

  (func $as_list (param $items (ref $tg.vals)) (result (ref null $tg.val))
    (struct.new $tg.list (i32.const 7) (local.get $items)
      (array.len (local.get $items))))

  (func $child (param $slots (ref $tg.vals)) (param $i i32)
        (result (ref $tg.inst))
    (struct.get $tg.comp $value
      (ref.cast (ref $tg.comp) (array.get $tg.vals (local.get $slots) (local.get $i)))))
