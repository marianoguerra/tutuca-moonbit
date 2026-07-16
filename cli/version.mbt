///|
/// Own-version constant, reported by `agent-context` and stamped into
/// feedback records. The JS CLI walks up from import.meta.url to its own
/// package.json; a native binary has no package directory to walk, so this
/// is compile-time. Keep in sync with `version` in moon.mod.
pub const VERSION : String = "0.1.0"
