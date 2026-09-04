///|
/// One search result, and why it ranked where it did.
///
/// `why` is not a nicety. A search whose order cannot be accounted for is one
/// people stop trusting, and that is as true of a model choosing a component as
/// of a person scrolling a list.
pub(all) struct Hit {
  entry : Entry
  /// The preset this row offers, or "" for the component's own row.
  preset : String
  score : Int
  why : Array[String]
} derive(Eq, @debug.Debug)

///|
/// What this row shows as its name: the preset's, when it has one.
pub fn Hit::label(self : Hit) -> String {
  if self.preset == "" {
    self.entry.ref_.name
  } else {
    self.preset
  }
}

///|
pub fn Hit::summary(self : Hit) -> String {
  if self.preset == "" {
    self.entry.summary()
  } else {
    match self.entry.presets.iter().find_first(p => p.name == self.preset) {
      Some(p) => p.doc
      None => self.entry.summary()
    }
  }
}

///|
/// Everything that can be placed on this page.
pub struct Catalog {
  rows : Array[Entry]
}

///|
pub fn Catalog::new() -> Catalog {
  { rows: [], }
}

///|
/// Add a module's components, REPLACING whatever that module had before.
///
/// Replacing rather than appending is what lets a card be redrawn under one
/// name without leaving a palette full of its previous selves.
pub fn Catalog::add(self : Catalog, entries : Array[Entry]) -> Unit {
  for e in entries {
    self.forget(e.ref_.module_)
    break
  }
  for e in entries {
    self.rows.push(e)
  }
}

///|
pub fn Catalog::forget(self : Catalog, module_ : String) -> Unit {
  let keep = self.rows.filter(e => e.ref_.module_ != module_)
  self.rows.clear()
  for e in keep {
    self.rows.push(e)
  }
}

///|
pub fn Catalog::all(self : Catalog) -> Array[Entry] {
  self.rows
}

///|
/// The first component with this name, in registration order.
///
/// Registration order is the tie-break and the kit registers first, so a card
/// somebody loads cannot take `Box` away from the thing every saved
/// arrangement means by it. HIDDEN entries resolve here — a saved arrangement
/// names holes constantly — even though the palette never lists them.
pub fn Catalog::find(
  self : Catalog,
  name : String,
  module_? : String = "",
) -> Entry? {
  self.rows
  .iter()
  .find_first(e => {
    e.ref_.name == name && (module_ == "" || e.ref_.module_ == module_)
  })
}

///|
fn lower(s : String) -> String {
  s.to_lower()
}

///|
/// What one term is worth against one row, and the words for it.
fn score_term(
  name : String,
  entry : Entry,
  term : String,
  why : Array[String],
) -> Int {
  let mut score = 0
  let n = lower(name)
  if n == term {
    score += 100
    why.push("name")
  } else if n.has_prefix(term) {
    score += 50
    why.push("name starts with \"\{term}\"")
  } else if n.contains(term) {
    score += 25
    why.push("name contains \"\{term}\"")
  }
  for keyword in entry.keywords {
    if lower(keyword) == term {
      score += 40
      why.push("keyword \"\{keyword}\"")
    } else if lower(keyword).contains(term) {
      score += 15
      why.push("keyword \"\{keyword}\"")
    }
  }
  if lower(entry.category) == term {
    score += 20
    why.push("category \"\{entry.category}\"")
  }
  if lower(entry.doc).contains(term) {
    score += 10
    why.push("described as it")
  }
  for field in entry.fields {
    if lower(field.name) == term {
      score += 8
      why.push("takes \"\{field.name}\"")
    }
  }
  score
}

///|
/// Search, ranked, with the reasons attached.
///
/// An EMPTY query is the palette opening: everything offerable, in registration
/// order, so the kit is at the top and what a person just loaded is at the
/// bottom where they left it.
pub fn Catalog::search(
  self : Catalog,
  query : String,
  limit? : Int = 20,
) -> Array[Hit] {
  let terms = lower(query).split(" ").filter(t => t.length() > 0).collect()
  let hits : Array[Hit] = []
  for entry in self.rows {
    if entry.hidden {
      continue
    }
    // One row for the component, and one for each preset. A preset ranks on
    // its OWN name first, which is what makes "vbox" find one thing and "box"
    // find all three.
    let rows : Array[(String, String)] = [(entry.ref_.name, "")]
    for p in entry.presets {
      rows.push((p.name, p.name))
    }
    for row in rows {
      let (label, preset) = row
      if terms.is_empty() {
        hits.push({ entry, preset, score: 0, why: [], })
        continue
      }
      let why : Array[String] = []
      let mut total = 0
      let mut every = true
      for term in terms {
        let got = score_term(label, entry, term.to_owned(), why)
        if got == 0 {
          every = false
        }
        total += got
      }
      // Every term has to land somewhere. A row that matched one word of three
      // is not what was asked for, and letting it through is how a list stops
      // being an answer and becomes a suggestion.
      if every && total > 0 {
        hits.push({ entry, preset, score: total, why, })
      }
    }
  }
  // STABLE, so a keystroke that changed nothing does not reorder the list under
  // the finger about to click.
  let ordered = hits.copy()
  ordered.sort_by((a, b) => b.score - a.score)
  if ordered.length() > limit {
    ordered[:limit].iter().collect()
  } else {
    ordered
  }
}
