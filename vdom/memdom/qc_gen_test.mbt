// Vdom generators for the property tests: a sized recursive tree generator,
// a deterministic key-assignment pass, and an LCG-driven mutator that
// produces realistic (old, new) pairs with localized diffs (port of the
// approach in test/vdom-genutil.js — independent random pairs would almost
// always differ at the root and only exercise the replace path).

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
/// Uniform-ish value in 0..<n (n > 0).
fn Lcg::below(self : Lcg, n : Int) -> Int {
  (self.next() % n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn gen_text_node() -> @gen.Gen[@vdom.Vdom] {
  @gen.one_of_array(["a", "b", "hello", "x", ""]).fmap(@vdom.text)
}

///|
fn gen_comment_node() -> @gen.Gen[@vdom.Vdom] {
  @gen.one_of_array(["c1", "note", "m"]).fmap(@vdom.comment)
}

///|
fn gen_attr_pair() -> @gen.Gen[(String, @vdom.AttrValue)] {
  @gen.one_of([
    @gen.one_of_array(["x", "id1", "hello"]).fmap(v => {
      ("id", @vdom.AttrValue::Str(v))
    }),
    @gen.one_of_array(["red", "blue", "big red"]).fmap(v => {
      ("className", @vdom.AttrValue::Str(v))
    }),
    @gen.one_of_array(["color: red", "margin: 5px"]).fmap(v => {
      ("style", @vdom.AttrValue::Str(v))
    }),
    @gen.int_range(0, 100).fmap(v => ("data-n", @vdom.AttrValue::int(v))),
    @gen.one_of_array([true, false]).fmap(v => {
      ("aria-hidden", @vdom.AttrValue::Bool(v))
    }),
    @gen.one_of_array(["v1", ""]).fmap(v => ("title", @vdom.AttrValue::Str(v))),
  ])
}

///|
fn gen_attrs() -> @gen.Gen[Map[String, @vdom.AttrValue]] {
  @gen.int_range(0, 3).bind(k => {
    gen_attr_pair()
    .array_with_size(k)
    .fmap(pairs => {
      let m : Map[String, @vdom.AttrValue] = {}
      for p in pairs {
        m[p.0] = p.1
      }
      m
    })
  })
}

///|
fn gen_node(n : Int) -> @gen.Gen[@vdom.Vdom] {
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
fn gen_element(n : Int) -> @gen.Gen[@vdom.Vdom] {
  @gen.one_of_array(["div", "span", "p", "ul", "li", "section", "b"]).bind(tag => {
    gen_attrs().bind(attrs => {
      let kmax = if n < 4 { n } else { 4 }
      @gen.int_range(0, kmax).bind(k => {
        let child_budget = if k == 0 { 0 } else { (n - 1) / k }
        gen_node(child_budget)
        .array_with_size(k)
        .fmap(childs => @vdom.h(tag, attrs~, childs~))
      })
    })
  })
}

///|
/// Random Vdom tree (no keys); size-bounded at every recursion level.
fn gen_vdom() -> @gen.Gen[@vdom.Vdom] {
  @gen.sized(n => gen_node(if n > 12 { 12 } else { n }))
}

///|
/// Deterministically mark a random subset of element children with unique
/// keys (constructive — no rejection filtering).
fn assign_keys(v : @vdom.Vdom, rng : Lcg, counter : Ref[Int]) -> @vdom.Vdom {
  match v {
    Node(el) => {
      let childs = el.childs.map(c => {
        match assign_keys(c, rng, counter) {
          Node(cel) if rng.below(3) == 0 => {
            counter.val += 1
            @vdom.Vdom::Node({ ..cel, key: Some("k\{counter.val}") })
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
fn gen_keyed_vdom() -> @gen.Gen[@vdom.Vdom] {
  @gen.tuple(gen_vdom(), @gen.int_range(0, 1073741823)).fmap(p => {
    let rng = Lcg::{ state: p.1.reinterpret_as_uint() }
    assign_keys(p.0, rng, Ref(0))
  })
}

///|
fn copy_attrs(
  attrs : Map[String, @vdom.AttrValue],
) -> Map[String, @vdom.AttrValue] {
  let m : Map[String, @vdom.AttrValue] = {}
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
      Node({ ..el, tag, attrs, childs })
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
fn gen_mutated_pair() -> @gen.Gen[(@vdom.Vdom, @vdom.Vdom)] {
  @gen.tuple(gen_keyed_vdom(), @gen.int_range(0, 1073741823)).fmap(p => {
    let rng = Lcg::{ state: p.1.reinterpret_as_uint() }
    (p.0, mutate(p.0, rng))
  })
}
