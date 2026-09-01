///|
/// The CLI's own version, reported by `agent-context` and stamped into
/// feedback records. Compile-time, since a native binary has no package
/// directory to read at runtime.
///
/// It tracks the CLI's surface, NOT the module's — those were the same number
/// once and have not been for a long time. `MODULE_VERSION` below is the
/// module's, and is the one that has to move with `moon.mod`.
pub const VERSION : String = "0.12.2"

///|
/// The module version this binary was built from — what `new-storybook` pins
/// in the `moon.mod` it writes, so a scaffolded project depends on a release
/// that actually contains what the scaffold imports.
///
/// Keep in sync with `version` in moon.mod; `scripts/check-module-version.mjs`
/// does it for you in `ci`.
pub const MODULE_VERSION : String = "0.45.0"
