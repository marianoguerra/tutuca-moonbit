// QuickCheck properties for the path traversal contract. Trees are random
// Value trees WITHOUT Fn (so Value Eq is total); valid paths are derived by
// walking a generated tree with an LCG (a path invented independently of the
// tree would almost never resolve), planting "zz-sel" key fields so
// SeqAccessStep's live key resolution is exercised; invalid paths mutate one
// step of a valid path into a guaranteed miss.
//
// Properties: the lens laws (get-put / put-get / put-put), unresolvable-put
// is identity, compact preserves addressing, pin_keys preserves lookup and is
// idempotent, resolve_chain coherence, and first-level structural sharing.
// Handler/update laws live in app_test.mbt (plain Values carry no handlers).

///|
struct Lcg {
  mut state : UInt
}

///|
fn Lcg::next(self : Lcg) -> UInt {
  self.state = self.state * 1664525 + 1013904223
  self.state
}

///|
fn Lcg::below(self : Lcg, n : Int) -> Int {
  (self.next() % n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn gen_scalar() -> @gen.Gen[@tutuca.Value] {
  @gen.one_of([
    @gen.one_of_array([
      @tutuca.Value::Null,
      @tutuca.Value::Bool(true),
      @tutuca.Value::Bool(false),
    ]),
    @gen.int_range(0, 100).fmap(n => @tutuca.Value::Num(n.to_double())),
    @gen.one_of_array(["x", "y", "hello", ""]).fmap(s => @tutuca.Value::Str(s)),
  ])
}

///|
fn gen_entry(depth : Int) -> @gen.Gen[(String, @tutuca.Value)] {
  @gen.one_of_array(["a", "b", "c", "items", "sel"]).bind(k => {
    gen_value(depth - 1).fmap(v => (k, v))
  })
}

///|
fn gen_vmap(depth : Int) -> @gen.Gen[@tutuca.Value] {
  @gen.int_range(1, 4).bind(k => {
    gen_entry(depth)
    .array_with_size(k)
    .fmap(entries => {
      let m : Map[String, @tutuca.Value] = {}
      for e in entries {
        m[e.0] = e.1
      }
      @tutuca.Value::Map(m)
    })
  })
}

///|
fn gen_vlist(depth : Int) -> @gen.Gen[@tutuca.Value] {
  @gen.int_range(1, 4).bind(k => {
    gen_value(depth - 1).array_with_size(k).fmap(a => @tutuca.Value::List(a))
  })
}

///|
fn gen_value(depth : Int) -> @gen.Gen[@tutuca.Value] {
  if depth <= 0 {
    gen_scalar()
  } else {
    @gen.one_of([
      gen_scalar(),
      gen_vmap(depth),
      gen_vmap(depth),
      gen_vlist(depth),
    ])
  }
}

///|
fn map_keys(m : Map[String, @tutuca.Value]) -> Array[String] {
  let keys : Array[String] = []
  for k, _v in m {
    keys.push(k)
  }
  keys
}

///|
/// Derive a path that resolves BY CONSTRUCTION: walk the tree choosing real
/// children. At a map field holding a keyed container it sometimes addresses
/// the item as SeqStep / EachRenderItStep, or plants a live "zz-sel" key
/// sibling and addresses it as SeqAccessStep.
fn derive_path(root : @tutuca.Value, rng : Lcg) -> Array[@tutuca.Step] {
  let steps : Array[@tutuca.Step] = []
  let mut cur = root
  for _hop in 0..<6 {
    guard cur is Map(m) && !m.is_empty() else { break }
    // frame-only steps may appear anywhere and must not affect addressing
    if rng.below(4) == 0 {
      steps.push(BindStep(binds={}))
    }
    let keys = map_keys(m)
    let k = keys[rng.below(keys.length())]
    guard m.get(k) is Some(child) else { break }
    match child {
      Map(cm) =>
        if !cm.is_empty() && rng.below(2) == 0 {
          let cks = map_keys(cm)
          let ck = cks[rng.below(cks.length())]
          match rng.below(3) {
            0 => steps.push(SeqStep(field=k, key=KStr(ck)))
            1 => steps.push(EachRenderItStep(field=k, key=KStr(ck)))
            _ => {
              m["zz-sel"] = @tutuca.Value::Str(ck)
              steps.push(SeqAccessStep(seq_field=k, key_field="zz-sel"))
            }
          }
          guard cm.get(ck) is Some(item) else { break }
          cur = item
        } else {
          steps.push(FieldStep(k))
          cur = child
        }
      List(a) =>
        if !a.is_empty() && rng.below(2) == 0 {
          let i = rng.below(a.length())
          steps.push(SeqStep(field=k, key=KInt(i)))
          cur = a[i]
        } else {
          steps.push(FieldStep(k))
          cur = child
        }
      _ => {
        steps.push(FieldStep(k))
        cur = child
      }
    }
    if rng.below(3) == 0 {
      break
    }
  }
  steps
}

///|
/// Mutate one step into a guaranteed miss ("zz-missing" is never a real
/// field; 9999 is beyond any generated container).
fn invalidate(steps : Array[@tutuca.Step], rng : Lcg) -> Array[@tutuca.Step] {
  if steps.is_empty() {
    return [FieldStep("zz-missing")]
  }
  let out = steps.copy()
  let i = rng.below(out.length())
  out[i] = match out[i] {
    FieldStep(_) => FieldStep("zz-missing")
    SeqStep(field~, ..) => SeqStep(field~, key=KInt(9999))
    EachRenderItStep(field~, ..) => EachRenderItStep(field~, key=KInt(9999))
    SeqAccessStep(seq_field~, ..) =>
      SeqAccessStep(seq_field~, key_field="zz-missing")
    // a frame-only step can't miss; make the position an addressing miss
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) =>
      FieldStep("zz-missing")
  }
  out
}

///|
fn gen_tree_and_path() -> @gen.Gen[(@tutuca.Value, Array[@tutuca.Step])] {
  gen_value(3).bind(tree => {
    @gen.int_range(0, 1073741823).fmap(seed => {
      let rng = Lcg::{ state: seed.reinterpret_as_uint() }
      (tree, derive_path(tree, rng))
    })
  })
}

///|
fn gen_tree_path_value() -> @gen.Gen[
  (@tutuca.Value, Array[@tutuca.Step], @tutuca.Value),
] {
  gen_tree_and_path().bind(tp => gen_value(1).fmap(v => (tp.0, tp.1, v)))
}

///|
fn as_v(n : &@tutuca.PathNode) -> @tutuca.Value {
  n.as_value().unwrap_or(@tutuca.Value::Null)
}

///|
test "property: derived paths resolve; get-put restores the same tree" {
  @qc.quick_check(
    @qc.forall(gen_tree_and_path(), tp => {
      let (tree, steps) = tp
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      match p.lookup(root) {
        Some(leaf) => as_v(p.set_value(root, leaf)) == tree
        None => false
      }
    }),
    max_success=300,
  )
}

///|
test "property: put-get reads back the written value" {
  @qc.quick_check(
    @qc.forall(gen_tree_path_value(), tpv => {
      let (tree, steps, v) = tpv
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      match p.lookup(p.set_value(root, v)) {
        Some(leaf) => as_v(leaf) == v
        None => false
      }
    }),
    max_success=300,
  )
}

///|
test "property: put-put — the last write wins" {
  @qc.quick_check(
    @qc.forall(
      gen_tree_path_value().bind(tpv => gen_value(1).fmap(v2 => (tpv, v2))),
      x => {
        let ((tree, steps, v1), v2) = x
        let root : &@tutuca.PathNode = tree
        let p = @tutuca.Path::new(steps~)
        as_v(p.set_value(p.set_value(root, v1), v2)) ==
        as_v(p.set_value(root, v2))
      },
    ),
    max_success=300,
  )
}

///|
test "property: put through an unresolvable path is physically identity" {
  @qc.quick_check(
    @qc.forall(
      gen_tree_path_value().bind(tpv => {
        @gen.int_range(0, 1073741823).fmap(seed => (tpv, seed))
      }),
      x => {
        let ((tree, steps, v), seed) = x
        let rng = Lcg::{ state: seed.reinterpret_as_uint() }
        let bad = invalidate(steps, rng)
        let root : &@tutuca.PathNode = tree
        let p = @tutuca.Path::new(steps=bad)
        p.lookup(root) is None && physical_equal(p.set_value(root, v), root)
      },
    ),
    max_success=300,
  )
}

///|
test "property: compact preserves addressing for lookup and set_value" {
  @qc.quick_check(
    @qc.forall(gen_tree_path_value(), tpv => {
      let (tree, steps, v) = tpv
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      let c = p.compact()
      let same_lookup = match (p.lookup(root), c.lookup(root)) {
        (Some(a), Some(b)) => as_v(a) == as_v(b)
        (None, None) => true
        _ => false
      }
      same_lookup && as_v(p.set_value(root, v)) == as_v(c.set_value(root, v))
    }),
    max_success=300,
  )
}

///|
test "property: pin_keys preserves lookup, is idempotent, no-op stays physical" {
  @qc.quick_check(
    @qc.forall(gen_tree_and_path(), tp => {
      let (tree, steps) = tp
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      let pinned = p.pin_keys(root)
      let same_lookup = match (p.lookup(root), pinned.lookup(root)) {
        (Some(a), Some(b)) => as_v(a) == as_v(b)
        (None, None) => true
        _ => false
      }
      let idempotent = pinned.pin_keys(root) == pinned
      let has_access = steps
        .iter()
        .any(s => s is SeqAccessStep(seq_field=_, key_field=_))
      let no_op_identity = has_access || physical_equal(pinned, p)
      same_lookup && idempotent && no_op_identity
    }),
    max_success=300,
  )
}

///|
test "property: resolve_chain coherence" {
  @qc.quick_check(
    @qc.forall(gen_tree_and_path(), tp => {
      let (tree, steps) = tp
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      let chain = p.resolve_chain(root)
      let head_ok = chain.length() > 0 && physical_equal(chain[0], root)
      let full_ok = match p.lookup(root) {
        Some(leaf) =>
          chain.length() == steps.length() + 1 &&
          as_v(chain[chain.length() - 1]) == as_v(leaf)
        None => chain.length() <= steps.length()
      }
      head_ok && full_ok
    }),
    max_success=300,
  )
}

///|
test "property: set_value shares first-level siblings physically" {
  @qc.quick_check(
    @qc.forall(gen_tree_path_value(), tpv => {
      let (tree, steps, v) = tpv
      let root : &@tutuca.PathNode = tree
      let p = @tutuca.Path::new(steps~)
      let root2 = p.set_value(root, v)
      guard steps is [first_step, ..] else { return true }
      guard step_field(first_step) is Some(f) else { return true }
      match (tree, as_v(root2)) {
        (Map(m1), Map(m2)) => {
          for k, v1 in m1 {
            if k != f && k != "zz-sel" {
              match m2.get(k) {
                Some(v2) => if !physical_equal(v1, v2) { return false }
                None => return false
              }
            }
          }
          true
        }
        _ => true
      }
    }),
    max_success=300,
  )
}

///|
fn step_field(step : @tutuca.Step) -> String? {
  match step {
    FieldStep(f) => Some(f)
    SeqStep(field~, ..) => Some(field)
    EachRenderItStep(field~, ..) => Some(field)
    SeqAccessStep(seq_field~, ..) => Some(seq_field)
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => None
  }
}
