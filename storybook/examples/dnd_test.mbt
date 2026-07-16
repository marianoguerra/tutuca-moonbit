///|
test "dnd: dragging a row onto a later one reorders the list" {
  let h = @harness.mount_example(dnd_module(), "Default")
  inspect(h.text(".row"), content="0: those belonging to the Emperor")
  // drag row 0 onto row 2
  h.drag(".row", 0, 2)
  debug_inspect(
    h.texts(".row")[0:4],
    content=(
      #|<ArrayView:
      #|  [
      #|    "0: embalmed ones",
      #|    "1: trained ones",
      #|    "2: those belonging to the Emperor",
      #|    "3: suckling pigs",
      #|  ]>
    ),
  )
}

///|
test "dnd: dragging upward moves the row earlier" {
  let h = @harness.mount_example(dnd_module(), "Default")
  h.drag(".row", 3, 0) // "suckling pigs" to the top
  debug_inspect(
    h.texts(".row")[0:4],
    content=(
      #|<ArrayView:
      #|  [
      #|    "0: suckling pigs",
      #|    "1: those belonging to the Emperor",
      #|    "2: embalmed ones",
      #|    "3: trained ones",
      #|  ]>
    ),
  )
}

///|
test "dnd: dropping a row on itself changes nothing" {
  let h = @harness.mount_example(dnd_module(), "Default")
  h.drag(".row", 2, 2)
  inspect(h.text(".row", nth=2), content="2: trained ones")
  inspect(h.find_all(".row").length(), content="14")
}

///|
test "dnd: the drag markup carries the drag/drop pairing attributes" {
  let h = @harness.mount_example(dnd_module(), "Default")
  debug_inspect(
    h.attr(".row", "draggable"),
    content=(
      #|Some("true")
    ),
  )
  debug_inspect(
    h.attr(".row", "data-dragtype"),
    content=(
      #|Some("my-list-item")
    ),
  )
  debug_inspect(
    h.attr(".row", "data-droptarget"),
    content=(
      #|Some("my-list-item")
    ),
  )
}

///|
test "dnd: a filtered view drags by the row's ORIGINAL key, not its screen position" {
  let h = @harness.mount_example(dnd_module(), "Pre-filtered")
  // only the rows containing "ones" are visible, but they keep their real keys
  debug_inspect(
    h.texts(".row"),
    content=(
      #|[
      #|  "1: embalmed ones",
      #|  "2: trained ones",
      #|  "5: fabled ones",
      #|  "9: innumerable ones",
      #|]
    ),
  )
  // drag the 1st visible row (key 1) onto the 3rd (key 5): the handler works on
  // the underlying list, so the unfiltered items in between are untouched
  h.drag(".row", 0, 2)
  debug_inspect(
    h.texts(".row"),
    content=(
      #|[
      #|  "1: trained ones",
      #|  "4: fabled ones",
      #|  "5: embalmed ones",
      #|  "9: innumerable ones",
      #|]
    ),
  )
}
