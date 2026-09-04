# Guides

Long-form, human-facing, and executable where it can be: `tutorial.mbt.md` and
`first_principles.mbt.md` are blackbox test files, so `moon test docs` compiles
and runs every code block in them.

| | |
|---|---|
| [tutorial.mbt.md](tutorial.mbt.md) | build an app from a counter up |
| [first_principles.mbt.md](first_principles.mbt.md) | the framework rebuilt layer by layer, if you want to know *why* it works |
| [dynamic-components.md](dynamic-components.md) | hosting a component fetched at runtime from someone you have no reason to trust |
| [storybook.md](storybook.md) | the gallery as a library, and why the story set is a projection |
| [sanitizer.md](sanitizer.md) | the WHATWG Sanitizer port: what it covers and what it argues for |
| [css-validator.md](css-validator.md) | why CSS is closed by reading a value rather than refusing a name |
| [playground-wasm.md](playground-wasm.md) | how the in-browser playground compiles and runs on both backends |

**The authoring reference is elsewhere.** `skill/tutuca/` is what an agent
reads — the spec and script languages, views, events, testing, protocols,
cards — and it ships inside the CLI (`tutuca install-skill`), which is why its
snippets are compiled by `ci` and these guides are not a second copy of it.
