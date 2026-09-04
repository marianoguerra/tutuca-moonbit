///|
/// Where the last `+` was clicked.
///
/// Held here, outside the state, because a `DispatchPath` is not a `Value` and
/// there is nowhere in a component's state to put one. One slot: a picker is
/// modal precisely so there can only ever be one cell waiting.
let pending_cell : Ref[@tutuca.DispatchPath?] = Ref(None)

///|
/// Remember the cell that asked, REWRITTEN so it addresses a place.
///
/// The rewrite is not a nicety. A path captured inside `render-each` carries
/// `EachRenderItStep` frames, which describe a RENDER — where this item was
/// drawn — rather than a place in the state. Sending to one reaches nothing,
/// and reaches nothing SILENTLY: no error, no refusal, the component simply
/// never hears it. Every container's cells go through `render-each`, so this
/// fires on every placement into a container and not in some corner.
///
/// The two steps carry identical payloads, so the rewrite is exact rather than
/// approximate. It happens at REMEMBER time so that what is stored is an
/// address from the moment it is taken.
pub fn remember_cell(at : @tutuca.DispatchPath) -> Unit {
  let frames : Array[@tutuca.DispatchFrame] = []
  for frame in at.frames {
    let items : Array[@tutuca.DispatchStep] = []
    for item in frame.items {
      match item {
        Plain(step~, origin~) =>
          match step {
            EachRenderItStep(field~, key~) =>
              items.push(Plain(step=SeqStep(field~, key~), origin~))
            _ => items.push(item)
          }
      }
    }
    frames.push({ base: frame.base, items, binds: frame.binds, })
  }
  pending_cell.val = Some({ frames, })
}

///|
/// Nobody is waiting any more — the picker was dismissed.
pub fn forget_cell() -> Unit {
  pending_cell.val = None
}

///|
/// Is anything waiting? Asked without consuming, by the code that has to decide
/// whether a built arrangement goes into a cell or becomes the whole canvas.
pub fn peek_cell() -> @tutuca.DispatchPath? {
  pending_cell.val
}

///|
/// The cell, once.
///
/// Distinct from `peek_cell` on purpose: a cell is filled once, and a path left
/// behind after a place would put the next pick into the same hole.
pub fn take_cell() -> @tutuca.DispatchPath? {
  let out = pending_cell.val
  pending_cell.val = None
  out
}

///|
/// One row of the palette, as the page hands it over.
pub(all) struct PickerHit {
  component : String
  module_ : String
  preset : String
  summary : String
  why : String
}

///|
/// Turn hits into rows.
///
/// Built HERE rather than in the page, because a row is a component and
/// building one needs this package's registry. The page knows what matched;
/// this knows what a row is. They meet at `pickerHits`.
pub fn picker_rows(hits : Array[PickerHit]) -> Array[@tutuca.Value] {
  let rows : Array[@tutuca.Value] = hits.map(hit => {
    picker_row.make({
      "component": Str(hit.component),
      "module": Str(hit.module_),
      "preset": Str(hit.preset),
      "summary": Str(hit.summary),
      "why": Str(hit.why),
      "selected": Bool(false),
    })
  })
  // The first row is where the keyboard starts, and it is set HERE rather than
  // by the picker, because the picker is handed a finished list and a list that
  // arrived with no cursor in it would render one keystroke behind.
  if rows.length() > 0 {
    rows[0] = rows[0].call_field("setSelected", [Bool(true)])
  }
  rows
}

///|
/// One row of the library.
pub fn library_rows(cards : Array[(String, String)]) -> Array[@tutuca.Value] {
  cards.map(c => {
    card_row.make({
      "name": Str(c.0),
      "path": Str(c.1),
      "loaded": Bool(false),
      "chosen": Bool(false),
      "error": Str(""),
    })
  })
}

///|
/// Four empty states, and they are four different sentences.
///
/// "nothing matches" and "nothing is registered yet" are different problems
/// with different fixes, and a list that said the same thing for both would
/// send somebody looking for a typo in a page with an empty catalog.
pub fn empty_message(
  query : String,
  total~ : Int,
  offered? : Bool = true,
) -> String {
  if !offered {
    "this page cannot place components"
  } else if total == 0 {
    "nothing is loaded yet — load a card from the library below"
  } else if query == "" {
    "nothing to place"
  } else {
    "nothing matches \"" + query + "\""
  }
}

///|
/// The three names a pick carries, as one string.
///
/// `pending`/`argument` is a single channel, so the three have to travel as
/// one. The encoder and the decoder are next to each other for the only reason
/// that matters: two halves of a format in two files is how they disagree.
pub fn pick_argument(
  module_ : String,
  component : String,
  preset : String,
) -> String {
  module_ + " " + component + " " + preset
}

///|
pub fn pick_parts(argument : String) -> (String, String, String) {
  let parts = argument.split(" ").map(p => p.to_owned()).collect()
  (
    parts.get(0).unwrap_or(""),
    parts.get(1).unwrap_or(""),
    parts.get(2).unwrap_or(""),
  )
}

///|
/// The default name a whole arrangement is saved under.
pub let saved_key : String = "tutuca.universal.arrangement"
