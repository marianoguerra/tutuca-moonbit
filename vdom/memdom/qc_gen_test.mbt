// Vdom generators for the property tests: a sized recursive tree generator,
// a deterministic key-assignment pass, and an LCG-driven mutator that
// produces realistic (old, new) pairs with localized diffs — independent
// random pairs would almost
// always differ at the root and only exercise the replace path.

///|
struct Lcg {
  mut state : UInt32
}

///|
fn Lcg::next(self : Lcg) -> UInt32 {
  self.state = self.state * 1664525 + 1013904223
  self.state
}

///|
/// Uniform-ish value in 0..<n (n > 0).
fn Lcg::below(self : Lcg, n : Int32) -> Int32 {
  (self.next() % n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn gen_text_node() -> @gen.Generator[@vdom.Vdom] {
  @gen.elements(["a", "b", "hello", "x", ""]).map(@vdom.text)
}

///|
fn gen_comment_node() -> @gen.Generator[@vdom.Vdom] {
  @gen.elements(["c1", "note", "m"]).map(@vdom.comment)
}

///|
fn gen_attr_pair() -> @gen.Generator[(String, @vdom.AttrValue)] {
  @gen.one_of([
    @gen.elements(["x", "id1", "hello"]).map(v => ("id", Str(v))),
    @gen.elements(["red", "blue", "big red"]).map(v => ("className", Str(v))),
    @gen.elements(["color: red", "margin: 5px"]).map(v => ("style", Str(v))),
    @gen.int_range(0, 100).map(v => ("data-n", @vdom.AttrValue::int(v))),
    @gen.elements([true, false]).map(v => ("aria-hidden", Bool(v))),
    @gen.elements(["v1", ""]).map(v => ("title", Str(v))),
  ])
}

///|
fn gen_attrs() -> @gen.Generator[Map[String, @vdom.AttrValue]] {
  @gen.int_range(0, 3).flat_map(k => {
    gen_attr_pair()
    .array_with_size(k)
    .map(pairs => {
      let m : Map[String, @vdom.AttrValue] = Map([])
      for p in pairs {
        m[p.0] = p.1
      }
      m
    })
  })
}

///|
fn gen_node(n : Int32) -> @gen.Generator[@vdom.Vdom] {
  if n <= 0 {
    @gen.frequency([(3, gen_text_node()), (1, gen_comment_node())])
  } else {
    @gen.frequency([
      (5, gen_element(n)),
      (2, gen_text_node()),
      (1, gen_comment_node()),
    ])
  }
}

///|
fn gen_element(n : Int32) -> @gen.Generator[@vdom.Vdom] {
  @gen.elements(["div", "span", "p", "ul", "li", "section", "b"]).flat_map(tag => {
    gen_attrs().flat_map(attrs => {
      let kmax = if n < 4 { n } else { 4 }
      @gen.int_range(0, kmax).flat_map(k => {
        let child_budget = if k == 0 { 0 } else { (n - 1) / k }
        gen_node(child_budget)
        .array_with_size(k)
        .map(childs => @vdom.h(tag, attrs~, childs~))
      })
    })
  })
}

///|
/// Random Vdom tree (no keys); size-bounded at every recursion level.
fn gen_vdom() -> @gen.Generator[@vdom.Vdom] {
  @gen.sized(n => gen_node(if n > 12 { 12 } else { n }))
}

///|
/// Deterministically mark a random subset of element children with unique
/// keys (constructive — no rejection filtering).
fn assign_keys(v : @vdom.Vdom, rng : Lcg, counter : Ref[Int32]) -> @vdom.Vdom {
  match v {
    Node(el) => {
      let childs = el.childs.map(c => {
        match assign_keys(c, rng, counter) {
          Node(cel) if rng.below(3) == 0 => {
            counter.val += 1
            @vdom.Vdom::Node({ ..cel, key: Some("k\{counter.val}"), })
          }
          other => other
        }
      })
      Node({ ..el, childs, })
    }
    other => other
  }
}

///|
fn gen_keyed_vdom() -> @gen.Generator[@vdom.Vdom] {
  gen_vdom()
  .zip(@gen.int_range(0, 1073741823))
  .map(p => {
    let rng = Lcg::{ state: p.1.reinterpret_as_uint(), }
    assign_keys(p.0, rng, Ref(0))
  })
}

///|
fn copy_attrs(
  attrs : Map[String, @vdom.AttrValue],
) -> Map[String, @vdom.AttrValue] {
  let m : Map[String, @vdom.AttrValue] = Map([])
  for k, v in attrs {
    m[k] = v
  }
  m
}

///|
/// Rebuild the tree, applying localized random mutations: text/comment/tag
/// changes, attr set/remove, child add/remove/replace, children reversal
/// (the shuffle that exercises keyed reordering).
fn mutate(v : @vdom.Vdom, rng : Lcg) -> @vdom.Vdom {
  match v {
    Text(s) => if rng.below(4) == 0 { @vdom.text("\{s}!") } else { v }
    Comment(s) => if rng.below(4) == 0 { @vdom.comment("\{s}?") } else { v }
    Fragment(cs) => Fragment(mutate_childs(cs, rng))
    Node(el) => {
      let childs = mutate_childs(el.childs, rng)
      let attrs = copy_attrs(el.attrs)
      match rng.below(6) {
        0 => attrs["data-m"] = @vdom.AttrValue::int(rng.below(100))
        1 => attrs["className"] = Str("mut\{rng.below(10)}")
        2 =>
          if attrs.length() > 0 {
            let keys = attrs.keys().collect()
            attrs.remove(keys[rng.below(keys.length())])
          }
        _ => ()
      }
      let tag = if rng.below(10) == 0 {
        if el.tag == "DIV" {
          "SPAN"
        } else {
          "DIV"
        }
      } else {
        el.tag
      }
      Node({ ..el, tag, attrs, childs, })
    }
  }
}

///|
fn mutate_childs(cs : Array[@vdom.Vdom], rng : Lcg) -> Array[@vdom.Vdom] {
  let mut out = cs.map(c => mutate(c, rng))
  match rng.below(8) {
    0 => out.push(@vdom.text("new\{rng.below(100)}"))
    1 => if out.length() > 0 { let _ = out.remove(rng.below(out.length())) }
    2 =>
      if out.length() > 0 {
        out[rng.below(out.length())] = @vdom.text("repl\{rng.below(100)}")
      }
    3 => out = out.rev() // deterministic "shuffle": exercises keyed reorder
    _ => ()
  }
  out
}

///|
/// (old, new) pairs where new is a localized mutation of old.
fn gen_mutated_pair() -> @gen.Generator[(@vdom.Vdom, @vdom.Vdom)] {
  gen_keyed_vdom()
  .zip(@gen.int_range(0, 1073741823))
  .map(p => {
    let rng = Lcg::{ state: p.1.reinterpret_as_uint(), }
    (p.0, mutate(p.0, rng))
  })
}
