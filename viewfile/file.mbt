// What a read view file holds, and the small facts every consumer asks of it.
//
// This package used to SPLIT: it ran the WHATWG tokenizer over an `.html`
// view file to find element boundaries and sliced the original text between
// them, so a view came back as raw source and every consumer parsed it again.
// A `.tutu` is read once, into the shape it means (`viewgen/read.mbt`), so
// there is nothing to slice and nothing to re-parse — what is left here is the
// shape itself and the three questions asked of it.

///|
/// The 1-based line `offset` falls on, for a diagnostic that points at the file
/// the author edits rather than at the block sliced out of it.
///
/// Here because every caller is reporting against a span this package produced,
/// and because two of them — `viewgen` and `cli` — had written it out
/// byte-identically. `line_at` below is the same rule over an array the caller
/// already has, which is what the splitter itself works in.
pub fn line_of(text : String, offset : Int) -> Int {
  let mut line = 1
  let mut i = 0
  for c in text {
    if i >= offset {
      break
    }
    if c == '\n' {
      line = line + 1
    }
    i = i + 1
  }
  line
}

///|
/// The component name for a ViewSet: its own, or the caller's fallback for a
/// file that declares a single unnamed component.
pub fn ViewSet::component_name(self : ViewSet, fallback : String) -> String {
  if self.name == "" {
    fallback
  } else {
    self.name
  }
}

///|
/// The whole block, which is what a consumer that wants its DECLARATIONS
/// needs: a file that was READ carries them and a file that was SPLIT carries
/// the text they come from.
///
/// The pairing rule is `script_for`'s, in one place: an unqualified block
/// answers for the file's single component.
pub fn ViewFile::script_block_for(
  self : ViewFile,
  comp : String,
) -> ScriptBlock? {
  for s in self.scripts {
    if s.comp == comp {
      return Some(s)
    }
  }
  if self.scripts.length() == 1 && self.scripts[0].comp == "" {
    return Some(self.scripts[0])
  }
  None
}

///|
/// The declarations a block holds, parsing its text when it carries none.
///
/// A `.tutu` is READ into declarations and an `.html` block is parsed from
/// text; every consumer wants the declarations, so the difference lives here
/// rather than at each of them.
pub fn ScriptBlock::declarations(
  self : ScriptBlock,
) -> Array[@tscript.Decl] raise @tscript.ScriptError {
  match self.decls {
    Some(d) => d
    None => @tscript.parse_script(self.block.text)
  }
}

///|
/// The schema entry for a component, or None when the file declares none.
///
/// The pairing rule is `component_name`'s on both sides: a `state` block with
/// no name and a template with no `Comp:` prefix are the SAME component, and
/// the caller's fallback is what they are both called. Living here rather than
/// in each consumer is what stops a second reading of that rule from drifting
/// — `viewgen` emits against this schema and `gen-css` collects classes
/// against it, and the two seeing different schemas for one file is a bug that
/// shows up as a view the CSS pass refuses and the generator accepts.
pub fn ViewFile::state_of(
  self : ViewFile,
  comp : String,
  fallback~ : String,
) -> @statedef.StateDef? {
  for def in self.state {
    if def.component_name(fallback) == comp {
      return Some(def)
    }
  }
  None
}
