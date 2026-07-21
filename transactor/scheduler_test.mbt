// has_pending + bounded settle(max_turns): the primitives a time-slicing
// backend loops on (App::drain_batched, JS _transactNextBatch). Sends with no
// matching handler still count as processed transactions, which is all these
// need — they exercise the queue, not handler effects.

///|
fn empty_root() -> &@tutuca.PathNode {
  @tutuca.Value::Map(Map([]))
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
  tx.settle(max_turns=2) // process 2 of 3
  assert_true(tx.has_pending())
  tx.settle() // drain the rest
  assert_false(tx.has_pending())
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
  let yields : Ref[Int] = { val: 0 }
  while tx.has_pending() {
    tx.settle(max_turns=2)
    if tx.has_pending() {
      yields.val += 1
    }
  }
  // 5 transactions in batches of 2 -> batches at 2,2,1; yields after the first
  // two batches only (the last batch empties the queue), so 2 yields.
  assert_eq(yields.val, 2)
  assert_false(tx.has_pending())
}
