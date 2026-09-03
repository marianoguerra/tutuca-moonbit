// The canonical spelling of an `Instant`.
//
// It lives in `core` rather than beside a codec because `Value::Instant` is
// the thing being spelled: `to_display_string`, `to_json` and the CBOR and
// JSON codecs all have to agree about what 1 756 915 200 seconds and 123 456
// 789 nanoseconds LOOKS like, and two hand-kept spellings of that are two
// answers.
//
// `moonbitlang/x/time` owns the calendar — turning an epoch second into a date
// is exactly the arithmetic nobody should write twice — and this owns the
// spelling, which the library does not: `ZonedDateTime::to_string` appends a
// zone name, and RFC 3339 wants an offset.

///|
/// A timestamp that is not one.
pub suberror BadInstant {
  BadInstant(String)
}

///|
pub impl Show for BadInstant with fn output(self, logger) {
  guard self is BadInstant(text)
  logger.write_string("not an RFC 3339 timestamp: \{text}")
}

///|
/// RFC 3339, always UTC.
///
/// `moonbitlang/x/time` owns the calendar — turning 1 725 000 000 into a date is
/// exactly the arithmetic nobody should write twice — and this owns the
/// spelling, which the library does not: `ZonedDateTime::to_string` appends a
/// zone name, and RFC 3339 wants an offset.
pub fn instant_to_rfc3339(secs : Int64, nanos : Int) -> String {
  let z = @time.ZonedDateTime::from_unix_second(secs, nanosecond=nanos) catch {
    // Unreachable for any instant TInstant can hold; a total function is still
    // better than a raise nobody can trigger.
    _ => return "1970-01-01T00:00:00Z"
  }
  let buf = StringBuilder()
  buf.write_string(pad(z.year().to_int64(), 4))
  buf.write_string("-")
  buf.write_string(pad(z.month().to_int64(), 2))
  buf.write_string("-")
  buf.write_string(pad(z.day().to_int64(), 2))
  buf.write_string("T")
  buf.write_string(pad(z.hour().to_int64(), 2))
  buf.write_string(":")
  buf.write_string(pad(z.minute().to_int64(), 2))
  buf.write_string(":")
  buf.write_string(pad(z.second().to_int64(), 2))
  buf.write_string(fraction(z.nanosecond()))
  buf.write_string("Z")
  buf.to_string()
}

///|
/// Sub-second digits in groups of three, trailing all-zero groups dropped.
///
/// Three groups rather than nine digits with the zeros trimmed, because
/// `.100` and `.1` are the same instant and only one of them is a spelling a
/// reader recognises as milliseconds.
fn fraction(nanos : Int) -> String {
  if nanos == 0 {
    return ""
  }
  let nine = pad(nanos.to_int64(), 9)
  let keep = if nanos % 1_000_000 == 0 {
    3
  } else if nanos % 1000 == 0 {
    6
  } else {
    9
  }
  "." + nine[:keep].to_owned()
}

///|
fn pad(n : Int64, width : Int) -> String {
  let neg = n < 0L
  let digits = (if neg { -n } else { n }).to_string()
  let buf = StringBuilder()
  if neg {
    buf.write_string("-")
  }
  for _ in 0..<(width - digits.length()) {
    buf.write_string("0")
  }
  buf.write_string(digits)
  buf.to_string()
}

///|
/// The reverse. `Z` and a numeric offset both parse; the offset is APPLIED and
/// not kept, because what comes back is an instant and an instant has no zone.
pub fn instant_of_rfc3339(text : String) -> (Int64, Int) raise BadInstant {
  let cs : Array[Char] = text.iter().collect()
  let n = cs.length()
  guard n >= 20 else { raise BadInstant(text) }
  // date-time up to seconds is fixed-width: 1970-01-01T00:00:00
  let year = int_at(cs, text, 0, 4)
  guard cs[4] == '-' else { raise BadInstant(text) }
  let month = int_at(cs, text, 5, 2)
  guard cs[7] == '-' else { raise BadInstant(text) }
  let day = int_at(cs, text, 8, 2)
  let sep = cs[10]
  guard sep == 'T' || sep == 't' || sep == ' ' else { raise BadInstant(text) }
  let hour = int_at(cs, text, 11, 2)
  guard cs[13] == ':' else { raise BadInstant(text) }
  let minute = int_at(cs, text, 14, 2)
  guard cs[16] == ':' else { raise BadInstant(text) }
  let second = int_at(cs, text, 17, 2)
  let mut i = 19
  let mut nanos = 0
  if i < n && cs[i] == '.' {
    i = i + 1
    let start = i
    while i < n && is_digit(cs[i]) {
      i = i + 1
    }
    guard i > start else { raise BadInstant(text) }
    // Nine digits of significance. More is truncated rather than rejected:
    // a producer with picoseconds said something true that this cannot hold,
    // and refusing the whole timestamp over the tail is the worse answer.
    for d in start..<i {
      let place = d - start
      if place < 9 {
        nanos = nanos * 10 + (cs[d].to_int() - '0'.to_int())
      }
    }
    for _ in (i - start)..<9 {
      nanos = nanos * 10
    }
  }
  guard i < n else { raise BadInstant(text) }
  let mut offset_secs = 0L
  match cs[i] {
    'Z' | 'z' => {
      i = i + 1
      guard i == n else { raise BadInstant(text) }
    }
    c => {
      guard c == '+' || c == '-' else { raise BadInstant(text) }
      guard n - i == 6 else { raise BadInstant(text) }
      let oh = int_at(cs, text, i + 1, 2)
      guard cs[i + 3] == ':' else { raise BadInstant(text) }
      let om = int_at(cs, text, i + 4, 2)
      let magnitude = (oh * 3600 + om * 60).to_int64()
      offset_secs = if c == '-' { -magnitude } else { magnitude }
    }
  }
  let z = @time.ZonedDateTime::of(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    nanosecond=nanos,
  ) catch {
    _ => raise BadInstant(text)
  }
  (z.to_unix_second() - offset_secs, nanos)
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn int_at(
  cs : Array[Char],
  text : String,
  at : Int,
  width : Int,
) -> Int raise BadInstant {
  guard at + width <= cs.length() else { raise BadInstant(text) }
  let mut acc = 0
  for i in at..<(at + width) {
    let c = cs[i]
    guard is_digit(c) else { raise BadInstant(text) }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
  }
  acc
}

///|
/// The display spelling of an instant, for `to_display_string` and `to_json`.
fn instant_text(secs : Int64, nanos : Int) -> String {
  instant_to_rfc3339(secs, nanos)
}

///|
/// Base64 (RFC 4648 §4, padded), for the one arm JSON has no shape for.
fn base64(b : Bytes) -> String {
  @base64.encode(b[:])
}

///|
/// The `$`-tagged spelling the format uses for a value JSON cannot carry.
///
/// The tag key is `$` and the payload key is `v`, and a MAP whose own keys
/// include `$` is written tagged too — without that escape the discriminator is
/// ambiguous. `Value::to_json` does not need the escape (a `Map` here is a
/// tutuca map, and `tgc/value` owns the round trip), but the SPELLING has to
/// match or the two encoders answer differently for the same value.
fn tagged_json(name : String, payload : Json) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["$"] = Json::string(name)
  obj["v"] = payload
  Json::object(obj)
}
