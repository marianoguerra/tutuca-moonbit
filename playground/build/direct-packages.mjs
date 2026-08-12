// The packages a playground user may import directly (distinct aliases — no
// browser/browser clash).
//
// The value+path runtime lives in the `core/` package
// (marianoguerra/tutuca/core), but examples import it as @tutuca. The
// in-browser moonc aliases a direct import by the .mi's own package name (it
// has no moon.pkg to re-alias core -> @tutuca the way the library's packages
// do), so we expose the module-ROOT package instead (marianoguerra/tutuca,
// name -> alias @tutuca), a thin facade that re-exports core's value types (see
// reexport.mbt). Its .mi is lib/tutuca.mi.
//
// In its own file because TWO things need it and they are not the same thing:
// `assemble.mjs` bakes these into the payload the browser links against, and
// `scripts/check-playground-examples.mjs` writes the equivalent `moon.pkg` so
// an example can be checked by `moon check` instead. The second used to
// restate the list, described as a "mirror" — which is a promise a comment
// cannot keep. An example that compiles in CI and not in the browser (or the
// reverse) is exactly what that check exists to prevent.
//
// Each entry is [alias, package-subpath]. `host` is the mount host: the
// browser needs it, and a `moon check` of an example does not — examples never
// drive it directly — so the consumer that does not want it filters it out by
// name rather than keeping a second list.
export const DIRECT = [
  ["host", "playground/host/host"],
  ["component", "component/component"],
  ["tutuca", "tutuca"],
  ["anode", "anode/anode"],
  ["app", "app/app"],
  ["render", "render/render"],
  ["vdom", "vdom/vdom"],
  ["transactor", "transactor/transactor"],
];

/// The `import { … }` lines for a generated `moon.pkg`, one per direct package.
///
/// `tutuca` is the module root, so it is spelled `"marianoguerra/tutuca"` with
/// an explicit `@tutuca` alias; everything else takes its alias from its own
/// last path segment, which is what the in-browser compiler does too.
export function moonPkgImports(exclude = []) {
  return DIRECT.filter(([alias]) => !exclude.includes(alias)).map(([alias]) =>
    alias === "tutuca"
      ? `  "marianoguerra/tutuca" @tutuca,`
      : `  "marianoguerra/tutuca/${alias}",`,
  );
}
