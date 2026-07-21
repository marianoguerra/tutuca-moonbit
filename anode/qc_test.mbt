// Property tests for the parse layer. Generators avoid `:`/`@` attributes so
// the properties hold independently of the value layer's implementation
// (parser totality over templates WITH directives is covered by the example
// suites once the value port lands).
//
// Deferred until the value layer has bodies:
//  - wrapper-order invariant (@show/@hide/... chain == source order)
//  - registry density over templates with x-ops (nodes[i].node_id == i)

///|
priv enum ChildSpec {
  Ws(String)
  Txt(String)
  Cmt(String)
  BlockEl
  InlineEl
}

///|
fn spec_of(x : Int) -> ChildSpec {
  let i = if x < 0 { -(x + 1) } else { x }
  match i % 8 {
    0 => Ws(" ")
    1 => Ws("\n  ")
    2 => Ws("\t\r")
    3 => Txt("a")
    4 => Txt("b x")
    5 => Cmt(" note ")
    6 => BlockEl
    _ => InlineEl
  }
}

///|
fn materialize(specs : Array[ChildSpec]) -> Array[@anode.ANode] {
  specs.map(s => {
    match s {
      Ws(v) | Txt(v) => Text({ val: v })
      Cmt(v) => Comment({ val: v })
      BlockEl =>
        Dom({ tag: "p", attrs: ConstAttrs(Map([])), childs: [], ns: None })
      InlineEl =>
        Dom({ tag: "span", attrs: ConstAttrs(Map([])), childs: [], ns: None })
    }
  })
}

///|
test "condense leaves no whitespace-only run with a newline" {
  // NOTE: condense_childs_whites is deliberately NOT idempotent (matching
  // the JS original): in [" ", " ", " "] the middle space survives pass one
  // as an interior run, then a second pass would see it at the edge and
  // drop it. It runs exactly once per element, so the invariant that holds
  // is the newline one: every interior newline run collapses to " "/"" and
  // every edge whitespace run is dropped.
  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let out = @anode.condense_childs_whites(materialize(xs.map(spec_of)))
    for n in out {
      if n.is_whitespace() && n.has_newline() {
        return false
      }
    }
    true
  })
}

///|
test "condense_childs_whites preserves non-whitespace text content" {
  fn non_ws_texts(nodes : Array[@anode.ANode]) -> Array[String] {
    let out : Array[String] = []
    for n in nodes {
      match n {
        Text(d) | Comment(d) => if !n.is_whitespace() { out.push(d.val) }
        _ => ()
      }
    }
    out
  }

  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let specs = xs.map(spec_of)
    let before = non_ws_texts(materialize(specs))
    let after = non_ws_texts(@anode.condense_childs_whites(materialize(specs)))
    after == before
  })
}

///|
test "condense_childs_whites preserves element count and order" {
  fn tags(nodes : Array[@anode.ANode]) -> Array[String] {
    let out : Array[String] = []
    for n in nodes {
      if n is Dom(d) {
        out.push(d.tag)
      }
    }
    out
  }

  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let specs = xs.map(spec_of)
    let before = tags(materialize(specs))
    let after = tags(@anode.condense_childs_whites(materialize(specs)))
    after == before
  })
}

///|
test "ANode::parse never panics on directive-free tag soup" {
  let fragments = [
    "<div>", "</div>", "<table>", "<tr>", "<td>", "</span>", "<svg>", "</svg>", "<x>",
    "</x>", "<x render-it></x>", "<x slot=\"s\">", "</x>", "text ", "<!-- c -->",
    "<pre> a\n b</pre>", "<ul><li>a<li>b</ul>", "<p class=\"a\">", "</p>", "<x:m>",
    "</x:m>", "<x nope=\"v\"></x>",
  ]
  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let buf = StringBuilder::new()
    for x in xs {
      let i = if x < 0 { -(x + 1) } else { x }
      buf.write_string(fragments[i % fragments.length()])
    }
    let px = @anode.ParseContext::new(handler=SilentHandler::{  })
    @anode.ANode::parse(buf.to_string(), px) |> ignore
    true
  })
}

///|
priv struct SilentHandler {}

///|
impl @anode.ParseHandler for SilentHandler with fn on_parse_issue(_, _, _) {

}
