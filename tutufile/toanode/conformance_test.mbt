// The claim the alignment rests on: THE STATIC SUBSET OF A TUTUCA VIEW IS
// SHRUBBERY HTML.
//
// Not asserted, decided. The same source is read twice — once by
// `marianoguerra/shrubbery-html`, which knows nothing about tutuca, and once
// by this package — and the two markup trees are compared. Where they differ,
// one of the two is wrong about a notation both claim to implement.
//
// It compares TREES rather than printed HTML because tutuca has no markup
// printer: a card's manifest carries its `.tutu`, not its HTML. What is
// canonicalised is what the two formats share — element names, attributes and
// their values, and text — and nothing else, because everything else is one
// side's extension and the other side is right to lack it.
//
// The corpus is `shrub-html`'s own, transcribed rather than fetched: a test
// that reached into a sibling checkout would pass or fail on whether that
// checkout was there.

///|
/// A markup tree, canonicalised.
fn html_canon(node : @htmlast.Node) -> String {
  let out = StringBuilder()
  fn walk(n : @htmlast.Node) -> Unit {
    match n {
      Element(e) => {
        out.write_string("<" + e.name.name)
        for a in e.attrs {
          out.write_string(" " + a.name.name + "=" + a.value.text())
        }
        out.write_string(">")
        for c in e.children {
          walk(c)
        }
        out.write_string("</" + e.name.name + ">")
      }
      Text(t) => out.write_string("#" + t.text)
      _ => ()
    }
  }

  walk(node)
  out.to_string()
}

///|
/// The same, for the tree this package reads.
fn anode_canon(node : @anode.ANode) -> String {
  let out = StringBuilder()
  fn walk(n : @anode.ANode) -> Unit {
    match n {
      Dom(d) => {
        out.write_string("<" + d.tag)
        match d.attrs {
          ConstAttrs(m) =>
            for name, v in m {
              // `data-vid` is the compiler's own stamp, not the author's.
              if name != "data-vid" && name != "data-cid" && name != "data-eid" {
                out.write_string(" " + name + "=" + lit_text(v))
              }
            }
          DynAttrs(_) => out.write_string(" ?dyn")
        }
        out.write_string(">")
        for c in d.childs {
          walk(c)
        }
        out.write_string("</" + d.tag + ">")
      }
      Text(t) => out.write_string("#" + t.val)
      Fragment(f) =>
        for c in f.childs {
          walk(c)
        }
      _ => ()
    }
  }

  walk(node)
  out.to_string()
}

///|
fn lit_text(v : @tutuca.Lit) -> String {
  match v {
    LStr(s) => s
    LNum(n) =>
      if n == n.floor() {
        n.to_int().to_string()
      } else {
        n.to_string()
      }
    LBool(b) => b.to_string()
    _ => "?"
  }
}

///|
/// One source, read by both, canonicalised, compared.
fn agrees(view : String) -> Unit raise {
  let theirs = @shrubbery_html.lower(view)
  assert_false(theirs.has_errors(), msg="shrubbery-html refused: " + view)
  let doc = theirs.document()
  let want = StringBuilder()
  for c in doc.children {
    want.write_string(html_canon(c))
  }
  let mine = direct_view(card("  Card:\n" + indent(view)))
  assert_true(mine is Some(_), msg="tutuca refused: " + view)
  assert_eq(anode_canon(mine.unwrap()), want.to_string(), msg=view)
}

///|
/// A Shrubbery HTML fragment, indented to sit under a component.
fn indent(src : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for line in src.split("\n") {
    if line.trim(chars=" ") == "" {
      continue
    }
    if !first {
      out.write_string("\n")
    }
    first = false
    out.write_string("    " + line.to_owned())
  }
  out.to_string()
}

///|
test "an element, its attributes and its text" {
  agrees("div(): \"hi\"")
  agrees("div(class: \"box\"): \"hello\"")
  agrees("p(id: \"a\", class: \"b\"): \"x\"")
}

///|
test "nesting, and text that carries its own space" {
  agrees("p():\n  \"Read \"\n  a(href: \"/x\"): \"more\"\n  \".\"")
  agrees("div():\n  span(): \"a\"\n  \" \"\n  span(): \"b\"")
}

///|
test "an underscore is a hyphen on both sides" {
  agrees("div(data_id: \"3\", aria_label: \"Close\"): \"x\"")
}

///|
test "a name a vocabulary spells its own way" {
  agrees("div(class: \"card\"):\n  h1(): \"Hello\"\n  p(): \"Written here.\"")
}

///|
/// The oracle has teeth.
///
/// A comparison that passes because both sides canonicalise to nothing is not
/// a comparison, and this repo has shipped that shape before. So: the
/// canonical form is asserted to be the markup it should be, and a
/// one-character difference is asserted to show.
test "the comparison is not vacuous" {
  let theirs = @shrubbery_html.lower("div(class: \"box\"): \"hello\"")
  let want = StringBuilder()
  for c in theirs.document().children {
    want.write_string(html_canon(c))
  }
  inspect(want.to_string(), content="<div class=box>#hello</div>")
  let mine = direct_view(card("  Card:\n    div(class: \"box\"): \"hello\"")).unwrap()
  inspect(anode_canon(mine), content="<div class=box>#hello</div>")
  // The same view with one character changed does NOT canonicalise the same.
  let other = direct_view(card("  Card:\n    div(class: \"BOX\"): \"hello\"")).unwrap()
  assert_not_eq(anode_canon(other), want.to_string())
}
