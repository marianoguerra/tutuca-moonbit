// An address, and the four questions a recording asks of one: where does this
// print, does it point into that subtree, what does it look like from there,
// and can it be dispatched at.

///|
pub fn Place::of_path(p : @tutuca.Path) -> Place {
  Place(p.to_keys())
}

///|
/// A `StepKey` back into a `Step`.
///
/// The two directions are not symmetric and cannot be: `to_keys` flattens seven
/// step variants onto two, so what comes back is the pair that ADDRESSES
/// something — a field, or an item of a sequence. The five it does not produce
/// are frame-only (they carry render bindings and address nothing) or live (a
/// seq-access step whose key is re-read from state, which `pin_keys` has
/// already frozen by the time a recording sees it).
fn step_of_key(k : @tutuca.StepKey) -> @tutuca.Step {
  match k.key {
    Some(key) => SeqStep(field=k.field, key~)
    None => FieldStep(k.field)
  }
}

///|
pub fn Place::to_steps(self : Place) -> Array[@tutuca.Step] {
  let Place(keys) = self
  keys.map(step_of_key)
}

///|
pub fn Place::to_path(self : Place) -> @tutuca.Path {
  @tutuca.Path::new(steps=self.to_steps())
}

///|
pub fn Place::label(self : Place) -> String {
  let Place(keys) = self
  @tutuca.step_keys_label(keys)
}

///|
pub fn Place::depth(self : Place) -> Int {
  let Place(keys) = self
  keys.length()
}

///|
/// Whether this address is at or below `prefix`.
///
/// Step-by-step and not a string comparison on the labels, which would be the
/// obvious shortcut and would be wrong: `rows` is a prefix of `rowsExtra` as
/// text and of nothing as an address.
pub fn Place::starts_with(self : Place, prefix : Place) -> Bool {
  let Place(mine) = self
  let Place(theirs) = prefix
  if theirs.length() > mine.length() {
    return false
  }
  for i, k in theirs {
    if mine[i] != k {
      return false
    }
  }
  true
}

///|
pub fn Place::strip_prefix(self : Place, prefix : Place) -> Place? {
  guard self.starts_with(prefix) else { return None }
  let Place(mine) = self
  Some(Place(mine[prefix.depth():].to_owned()))
}

///|
pub fn Place::under(self : Place, prefix : Place) -> Place {
  let Place(above) = prefix
  let Place(mine) = self
  let out : Array[@tutuca.StepKey] = above.copy()
  out.append(mine)
  Place(out)
}

///|
pub fn Place::to_json(self : Place) -> Json {
  let Place(keys) = self
  Json::array(keys.map(k => k.to_json()))
}

///|
pub fn Place::from_json(j : Json) -> Place? {
  guard j is Array(items) else { return None }
  let out : Array[@tutuca.StepKey] = []
  for it in items {
    match @tutuca.StepKey::from_json(it) {
      Some(k) => out.push(k)
      None => return None
    }
  }
  Some(Place(out))
}

///|
/// Read a dotted place.
///
/// A hand-rolled reader rather than `@scenedef.parse_place`, and the reason is
/// a dependency rather than a disagreement: `scenedef` answers in `Step`, which
/// is the richer type, and this package is deliberately below it. The spelling
/// is the same one — `.rows[0].label`, `.byId['a'].n` — restricted to what an
/// ADDRESS needs, which is a field, a literal index and a literal key.
pub fn parse_place(src : String) -> Place raise TraceError {
  let keys : Array[@tutuca.StepKey] = []
  let cs = src.to_array()
  let n = cs.length()
  let mut i = 0
  // A leading dot is optional: `.rows[0]` and `rows[0]` are the same address,
  // and both spellings turn up — one from a scene, one from a label.
  if i < n && cs[i] == '.' {
    i = i + 1
  }
  if src == "" || src == "." {
    return Place([])
  }
  while i < n {
    let start = i
    while i < n && cs[i] != '.' && cs[i] != '[' {
      i = i + 1
    }
    let field = String::from_array(cs[start:i].to_owned())
    if field == "" {
      raise BadPlace(line=0, why="empty field name in `\{src}`")
    }
    if i < n && cs[i] == '[' {
      i = i + 1
      let key_start = i
      while i < n && cs[i] != ']' {
        i = i + 1
      }
      if i >= n {
        raise BadPlace(line=0, why="unclosed `[` in `\{src}`")
      }
      let raw = String::from_array(cs[key_start:i].to_owned())
      i = i + 1
      keys.push({ field, key: Some(parse_key(raw, src)), })
    } else {
      keys.push({ field, key: None, })
    }
    if i < n && cs[i] == '.' {
      i = i + 1
      if i >= n {
        raise BadPlace(line=0, why="trailing `.` in `\{src}`")
      }
    }
  }
  Place(keys)
}

///|
/// A key between brackets: a quoted string, or a number.
///
/// Quoting is what decides, not the content: `['1']` is the string key `1` and
/// `[1]` is the index. A map really can be keyed by "1", and guessing from the
/// digits would make that address unwritable.
fn parse_key(raw : String, src : String) -> @tutuca.PathKey raise TraceError {
  let cs = raw.to_array()
  let n = cs.length()
  if n >= 2 &&
    ((cs[0] == '\'' && cs[n - 1] == '\'') || (cs[0] == '"' && cs[n - 1] == '"')) {
    return KStr(String::from_array(cs[1:n - 1].to_owned()))
  }
  if n == 0 {
    raise BadPlace(line=0, why="empty key in `\{src}`")
  }
  let mut v = 0
  for c in cs {
    if c < '0' || c > '9' {
      raise BadPlace(
        line=0,
        why="`\{raw}` in `\{src}` is neither a number nor a quoted key",
      )
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  KInt(v)
}
