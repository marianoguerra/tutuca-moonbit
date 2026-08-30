///| `MemFiles` is the in-memory half of the file seam, and these are the four
/// questions a caller of `FileService` actually has: did a save arrive intact,
/// does a read answer it, what does an unknown id do, and does a failure carry
/// a sentence rather than a silence.

///|
/// Saving records the name, the type and the text, in order.
test "save_text records what it was handed" {
  let fs = @files.MemFiles::new()
  let svc : &@files.FileService = fs
  svc.save_text(name="a.trace.jsonl", mime="text/plain", "one")
  svc.save_text(name="b.trace.jsonl", mime="text/plain", "two")
  json_inspect(fs.saved().map(f => f.name), content=[
    "a.trace.jsonl", "b.trace.jsonl",
  ])
  json_inspect(fs.last_saved().unwrap().text, content="two")
}

///|
/// The round trip the whole seam exists for: text out through a save, the same
/// text back through a read.
test "a saved file reads back as itself" {
  let fs = @files.MemFiles::new()
  let svc : &@files.FileService = fs
  let written = "{\"tutucaTrace\":1}\n{\"root\":{}}\n"
  svc.save_text(
    name=@files.trace_filename("counter"),
    mime=@files.TRACE_MIME,
    written,
  )
  let id = fs.round_trip().unwrap()
  let got : Ref[String] = { val: "", }
  svc.read_text(id~, then=r => {
    match r {
      Ok(text) => got.val = text
      Err(why) => got.val = "unexpected error: \{why}"
    }
  })
  assert_eq(got.val, written)
}

///|
/// An id nothing answers to fails with a sentence naming it, rather than
/// answering empty text — which a caller would parse as an empty trace.
test "an unknown id is an error, not empty text" {
  let fs = @files.MemFiles::new()
  let svc : &@files.FileService = fs
  let got : Ref[String] = { val: "", }
  svc.read_text(id=7, then=r => {
    match r {
      Ok(_) => got.val = "unexpectedly ok"
      Err(why) => got.val = why
    }
  })
  assert_eq(got.val, "no file #7")
}

///|
/// A read the host refused carries the host's own sentence through.
test "a refused read carries its reason" {
  let fs = @files.MemFiles::new()
  let svc : &@files.FileService = fs
  fs.provide_error(id=1, "the viewer cancelled")
  let got : Ref[String] = { val: "", }
  svc.read_text(id=1, then=r => {
    match r {
      Ok(_) => got.val = "unexpectedly ok"
      Err(why) => got.val = why
    }
  })
  assert_eq(got.val, "the viewer cancelled")
}

///|
/// The filename is one shape in one place: the CLI reads `.trace.jsonl`, so a
/// save that spelled it differently would produce a file `tutuca trace` is not
/// looking for.
test "trace_filename is the CLI's spelling" {
  assert_eq(@files.trace_filename("counter"), "counter.trace.jsonl")
  assert_eq(@files.trace_filename(""), "recording.trace.jsonl")
}
