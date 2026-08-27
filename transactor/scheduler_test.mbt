// has_pending + bounded settle(max_turns): the primitives a time-slicing
// backend loops on (App::drain_batched). Sends with no
// matching handler still count as processed transactions, which is all these
// need — they exercise the queue, not handler effects.

///|
fn empty_root() -> @tutuca.Value {
  Map(Map([]))
}

///|
test "has_pending tracks the queue; bounded settle leaves the rest" {
  let tx = @transactor.Transactor::new(empty_root())
  assert_false(tx.has_pending())
  for _i in 0..<3 {
    tx.push_send(
      @tutuca.DispatchPath::new(),
      "noop",
      ([] : Array[@tutuca.Value]),
    )
    |> ignore
  }
  assert_true(tx.has_pending())
  let first = tx.settle(max_turns=2) // process 2 of 3
  assert_eq(first, { processed: 2, pending: true, })
  assert_true(tx.has_pending())
  let last = tx.settle() // drain the rest
  assert_eq(last, { processed: 1, pending: false, })
  assert_false(tx.has_pending())
}

///|
test "non-positive settle budget makes no progress and reports pending work" {
  let tx = @transactor.Transactor::new(empty_root())
  tx.push_send(@tutuca.DispatchPath::new(), "noop", ([] : Array[@tutuca.Value]))
  |> ignore
  assert_eq(tx.settle(max_turns=0), { processed: 0, pending: true, })
  assert_eq(tx.settle(max_turns=-1), { processed: 0, pending: true, })
  assert_eq(tx.settle(), { processed: 1, pending: false, })
}

///|
test "batched drive yields between batches until the queue drains" {
  let tx = @transactor.Transactor::new(empty_root())
  for _i in 0..<5 {
    tx.push_send(
      @tutuca.DispatchPath::new(),
      "noop",
      ([] : Array[@tutuca.Value]),
    )
    |> ignore
  }
  // the App::drain_batched loop, replicated with a yield counter
  let yields : Ref[Int] = { val: 0, }
  while tx.has_pending() {
    let batch = tx.settle(max_turns=2)
    if batch.pending {
      yields.val += 1
    }
  }
  // 5 transactions in batches of 2 -> batches at 2,2,1; yields after the first
  // two batches only (the last batch empties the queue), so 2 yields.
  assert_eq(yields.val, 2)
  assert_false(tx.has_pending())
}

///|
test "queue cursor compaction preserves every transaction" {
  let tx = @transactor.Transactor::new(empty_root())
  for _ in 0..<2050 {
    tx.push_send(
      @tutuca.DispatchPath::new(),
      "noop",
      ([] : Array[@tutuca.Value]),
    )
    |> ignore
  }
  let mut processed = 0
  while tx.has_pending() {
    processed += tx.settle(max_turns=1).processed
  }
  assert_eq(processed, 2050)
}
