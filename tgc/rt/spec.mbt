///|
/// The runtime module's Wax source.
///
/// Compile it with `tgc/emit`'s `compile_runtime`, or hand it to `cmd/tgc`.
/// It carries no preamble of its own: the compiler prepends the canonical one,
/// which is why a runtime built here and a component built anywhere else share
/// types without either having been told about the other.
declare pub fn source() -> String
