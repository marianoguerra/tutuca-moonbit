///|
/// The spellings, and the round trip. A timestamp that prints one way and reads
/// back as a different instant is the failure this exists to prevent, so every
/// row asserts both directions rather than just the print.
test "instant spellings round-trip" {
  let rows : Array[(Int64, Int, String)] = [
    (0L, 0, "1970-01-01T00:00:00Z"),
    (1_756_915_200L, 0, "2025-09-03T16:00:00Z"),
    (1_756_915_200L, 123_000_000, "2025-09-03T16:00:00.123Z"),
    (1_756_915_200L, 123_456_000, "2025-09-03T16:00:00.123456Z"),
    (1_756_915_200L, 123_456_789, "2025-09-03T16:00:00.123456789Z"),
    (1_756_915_200L, 1, "2025-09-03T16:00:00.000000001Z"),
    // Before the epoch: `secs` goes negative and `nanos` stays positive, the
    // way `timespec` does it, so there is one spelling per instant.
    (-1L, 500_000_000, "1969-12-31T23:59:59.500Z"),
  ]
  for row in rows {
    let (secs, nanos, want) = row
    assert_eq(@core.instant_to_rfc3339(secs, nanos), want)
    let (s2, n2) = @core.instant_of_rfc3339(want)
    assert_eq(s2, secs)
    assert_eq(n2, nanos)
  }
}

///|
/// An offset is APPLIED, not kept: what comes back is an instant, and an
/// instant has no zone.
test "a numeric offset resolves to the same instant as Z" {
  let (a, _) = @core.instant_of_rfc3339("2025-09-03T16:00:00Z")
  let (b, _) = @core.instant_of_rfc3339("2025-09-03T18:00:00+02:00")
  let (c, _) = @core.instant_of_rfc3339("2025-09-03T13:00:00-03:00")
  assert_eq(a, b)
  assert_eq(a, c)
}

///|
/// A timestamp that is not one says so, with the text that was not one.
test "malformed timestamps are refused" {
  for
    bad in [
      "", "2025-09-03", "2025-09-03T16:00:00", "2025-13-03T16:00:00Z", "2025-09-03T16:00:00+2:00",
    ] {
    let got = try {
      let _ = @core.instant_of_rfc3339(bad)
      "accepted"
    } catch {
      BadInstant(_) => "refused"
    }
    assert_eq(got, "refused", msg="for \{bad}")
  }
}
