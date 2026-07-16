///|
/// Epoch milliseconds -> ISO-8601 UTC with millisecond precision, matching
/// JS Date.toISOString() for dates the CLI will ever stamp. Civil-from-days
/// per Howard Hinnant's algorithm; inputs are post-1970 so plain integer
/// division is enough.
pub fn iso8601_utc(ms : UInt64) -> String {
  let total = ms.reinterpret_as_int64()
  let days = (total / 86400000).to_int()
  let msod = (total % 86400000).to_int()
  let hour = msod / 3600000
  let minute = msod % 3600000 / 60000
  let second = msod % 60000 / 1000
  let milli = msod % 1000
  let z = days + 719468
  let era = z / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = yoe + era * 400 + (if month <= 2 { 1 } else { 0 })
  let p2 = (n : Int) => n.to_string().pad_start(2, '0')
  "\{year.to_string().pad_start(4, '0')}-\{p2(month)}-\{p2(day)}" +
  "T\{p2(hour)}:\{p2(minute)}:\{p2(second)}.\{milli.to_string().pad_start(3, '0')}Z"
}
