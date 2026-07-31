///| The layout vocabulary: a subset of flex and grid, and the reasons for the
/// boundary.
///
/// What is IN: direction, wrapping, the two axes' alignment, gaps, padding, a
/// grid's track lists, and a cell's span and placement. That is enough to
/// build a toolbar, a sidebar-and-content split, a card grid, a form, and a
/// dashboard — which is the set of things anyone actually asks for.
///
/// What is OUT, and why: arbitrary CSS lengths (a track is `Nfr`, `Npx` or
/// `auto`, so a track list is always three tokens a model can get right);
/// `grid-template-areas` (a second, redundant way to place a cell, and the one
/// that breaks when a cell is removed); absolute positioning and z-index (a
/// layout that can overlap the page around it is a layout that can hide it);
/// and per-node arbitrary CSS (the whole reason this is a vocabulary rather
/// than a style attribute).
///
/// Every value here renders to an inline style string the host generates. A
/// guest never supplies one, so none of this passes through the CSS validator
/// — layout CSS is host-authored by construction.

///|
/// Which way a stack runs. `Row`/`Column` and their reverses; nothing else,
/// because flex has nothing else.
pub(all) enum Direction {
  Row
  Column
  RowReverse
  ColumnReverse
} derive(Eq, Debug)

///|
pub fn Direction::to_css(self : Direction) -> String {
  match self {
    Row => "row"
    Column => "column"
    RowReverse => "row-reverse"
    ColumnReverse => "column-reverse"
  }
}

///|
pub fn Direction::parse(s : String) -> Direction? {
  match s {
    "row" => Some(Row)
    "column" => Some(Column)
    "row-reverse" => Some(RowReverse)
    "column-reverse" => Some(ColumnReverse)
    _ => None
  }
}

///|
/// Distribution along the main axis (`justify-content`).
pub(all) enum Justify {
  Start
  Center
  End
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq, Debug)

///|
pub fn Justify::to_css(self : Justify) -> String {
  match self {
    Start => "flex-start"
    Center => "center"
    End => "flex-end"
    SpaceBetween => "space-between"
    SpaceAround => "space-around"
    SpaceEvenly => "space-evenly"
  }
}

///|
pub fn Justify::parse(s : String) -> Justify? {
  match s {
    "start" => Some(Start)
    "center" => Some(Center)
    "end" => Some(End)
    "space-between" => Some(SpaceBetween)
    "space-around" => Some(SpaceAround)
    "space-evenly" => Some(SpaceEvenly)
    _ => None
  }
}

///|
/// Alignment across the cross axis (`align-items`).
pub(all) enum Align {
  AStart
  ACenter
  AEnd
  AStretch
  ABaseline
} derive(Eq, Debug)

///|
pub fn Align::to_css(self : Align) -> String {
  match self {
    AStart => "flex-start"
    ACenter => "center"
    AEnd => "flex-end"
    AStretch => "stretch"
    ABaseline => "baseline"
  }
}

///|
pub fn Align::parse(s : String) -> Align? {
  match s {
    "start" => Some(AStart)
    "center" => Some(ACenter)
    "end" => Some(AEnd)
    "stretch" => Some(AStretch)
    "baseline" => Some(ABaseline)
    _ => None
  }
}

///|
/// One grid track. Three shapes, not a CSS length: `2fr`, `120px`, `auto`.
///
/// This is the single most load-bearing restriction in the vocabulary. A track
/// list is the part of grid that is easiest to get subtly wrong — `minmax`,
/// `repeat`, `fit-content`, percentages, `calc` — and every one of those is a
/// place a generated layout silently collapses. Three tokens is a grammar
/// anything can produce correctly.
pub(all) enum Track {
  Fr(Int)
  Px(Int)
  Auto
} derive(Eq, Debug)

///|
pub fn Track::to_css(self : Track) -> String {
  match self {
    Fr(n) => "\{n}fr"
    Px(n) => "\{n}px"
    Auto => "auto"
  }
}

///|
/// Parse one track. Anything unrecognized is `None` rather than `auto`: a
/// silently-substituted track is a layout that looks nearly right, which is
/// harder to notice than one that is refused.
pub fn Track::parse(s : String) -> Track? {
  if s == "auto" {
    return Some(Auto)
  }
  if s.has_suffix("fr") {
    return match parse_int_prefix(s, 2) {
      Some(n) => Some(Fr(n))
      None => None
    }
  }
  if s.has_suffix("px") {
    return match parse_int_prefix(s, 2) {
      Some(n) => Some(Px(n))
      None => None
    }
  }
  None
}

///|
/// The leading integer of `s` with `suffix_len` characters dropped from the
/// end. Non-negative only — a negative track is not a thing.
fn parse_int_prefix(s : String, suffix_len : Int) -> Int? {
  let body = s[:s.char_length() - suffix_len].to_owned()
  if body == "" {
    return None
  }
  let mut n = 0
  for c in body {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// A track list as CSS, or "none" for an empty one (which is what a Stack-like
/// grid with no declared tracks means).
pub fn tracks_to_css(tracks : Array[Track]) -> String {
  if tracks.is_empty() {
    "none"
  } else {
    tracks.map(t => t.to_css()).join(" ")
  }
}
