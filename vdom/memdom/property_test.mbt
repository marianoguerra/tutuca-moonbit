// QuickCheck properties (port of test/vdom-property.test.js):
//   1. is_equal_to is an equivalence relation; h() trees never contain
//      Fragment children (normalization invariant)
//   2. morphing old -> new produces a DOM structurally equal to a fresh
//      render of new
//   3. keyed reorder preserves DOM node identity
//   4. diff_props roundtrips: apply(a, diff(a, b)) == b

///|
fn no_fragment_childs(v : @vdom.Vdom) -> Bool {
  match v {
    Node(el) =>
      el.childs.iter().all(c => !(c is Fragment(_)) && no_fragment_childs(c))
    Fragment(cs) =>
      cs.iter().all(c => !(c is Fragment(_)) && no_fragment_childs(c))
    _ => true
  }
}

///|
test "property: is_equal_to is reflexive and symmetric; h normalizes" {
  @qc.quick_check(
    @qc.forall(gen_keyed_vdom(), v => v.is_equal_to(v) && no_fragment_childs(v)),
    max_success=200,
  )
  @qc.quick_check(
    @qc.forall(gen_mutated_pair(), p => {
      let (a, b) = p
      a.is_equal_to(b) == b.is_equal_to(a)
    }),
    max_success=200,
  )
}

///|
test "property: morph produces the same DOM as a fresh render" {
  @qc.quick_check(
    @qc.forall(gen_mutated_pair(), p => {
      let (a, b) = p
      let (c1, o1) = new_env()
      let r1 = @vdom.render(a, c1, o1)
      let _ = @vdom.render(b, c1, o1, prev=r1)
      let (c2, o2) = new_env()
      let _ = @vdom.render(b, c2, o2)
      dom_equal_test(c1, c2)
    }),
    max_success=300,
  )
}

///|
fn dom_equal_test(a : @memdom.MemNode, b : @memdom.MemNode) -> Bool {
  @memdom.dom_equal(a, b)
}

///|
test "property: equal trees morph without touching the DOM" {
  @qc.quick_check(
    @qc.forall(gen_keyed_vdom(), v => {
      let (c, o) = new_env()
      let r1 = @vdom.render(v, c, o)
      let before = c.childs.copy()
      let _ = @vdom.render(v, c, o, prev=r1)
      if c.childs.length() != before.length() {
        return false
      }
      for i in 0..<before.length() {
        if !physical_equal(c.childs[i], before[i]) {
          return false
        }
      }
      true
    }),
    max_success=200,
  )
}

///|
test "property: keyed reorder preserves DOM node identity" {
  // n keyed children k0..k(n-1), target order = seeded Fisher-Yates shuffle
  let gen = @gen.tuple(@gen.int_range(2, 9), @gen.int_range(0, 1073741823))
  @qc.quick_check(
    @qc.forall(gen, p => {
      let (n, seed) = p
      let rng = Lcg::{ state: seed.reinterpret_as_uint() }
      let keys : Array[String] = []
      for i in 0..<n {
        keys.push("k\{i}")
      }
      let order = keys.copy()
      for i = n - 1; i > 0; i = i - 1 {
        let j = rng.below(i + 1)
        let tmp = order[i]
        order[i] = order[j]
        order[j] = tmp
      }
      fn tree(ks : Array[String]) {
        @vdom.h(
          "div",
          childs=ks.map(k => {
            @vdom.h("div", attrs={ "id": Str(k) }, key=k, childs=[@vdom.text(k)])
          }),
        )
      }

      let (c, o) = new_env()
      let r1 = @vdom.render(tree(keys), c, o)
      let root = c.childs[0]
      // key -> MemNode before the morph
      let by_key : Map[String, @memdom.MemNode] = {}
      for child in root.childs {
        if child.get_attribute("id") is Some(k) {
          by_key[k] = child
        }
      }
      let _ = @vdom.render(tree(order), c, o, prev=r1)
      if !physical_equal(c.childs[0], root) || root.childs.length() != n {
        return false
      }
      for i in 0..<n {
        guard by_key.get(order[i]) is Some(expected) else { return false }
        if !physical_equal(root.childs[i], expected) {
          return false
        }
      }
      true
    }),
    max_success=200,
  )
}

///|
fn apply_props_diff(
  a : Map[String, @vdom.AttrValue],
  diff : Map[String, @vdom.AttrValue?]?,
) -> Map[String, @vdom.AttrValue] {
  let out : Map[String, @vdom.AttrValue] = {}
  for k, v in a {
    out[k] = v
  }
  match diff {
    None => ()
    Some(d) =>
      for k, v in d {
        match v {
          None => out.remove(k)
          Some(nv) => out[k] = nv
        }
      }
  }
  out
}

///|
test "property: diff_props roundtrips" {
  @qc.quick_check(
    @qc.forall(@gen.tuple(gen_attrs(), gen_attrs()), p => {
      let (a, b) = p
      apply_props_diff(a, @vdom.diff_props(a, b)) == b
    }),
    max_success=300,
  )
}
