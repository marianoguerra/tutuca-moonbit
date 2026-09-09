# Guides

Long-form, human-facing, and executable where it can be: the tutorial is generated from the shared component sources and their interaction tests; `first_principles.mbt.md` runs its executable code blocks through `moon test docs`.

| | |
|---|---|
| [tutorial.mbt.md](tutorial.mbt.md) | five practical components, from a quantity picker to a document workspace |
| [first_principles.mbt.md](first_principles.mbt.md) | the framework rebuilt layer by layer, if you want to know *why* it works |
| [dynamic-components.md](dynamic-components.md) | hosting a component fetched at runtime from someone you have no reason to trust |
| [storybook.md](storybook.md) | the gallery as a library, and why the story set is a projection |
| [sanitizer.md](sanitizer.md) | the WHATWG Sanitizer port: what it covers and what it argues for |
| [css-validator.md](css-validator.md) | why CSS is closed by reading a value rather than refusing a name |
| [playground-wasm.md](playground-wasm.md) | how the in-browser playground compiles and runs on both backends |
| [tutu-format.md](tutu-format.md) | the `.tutu` format, sections, generation and runtime boundaries |

**The authoring reference is elsewhere.** `skill/tutuca/` is what an agent
reads — the spec and script languages, views, events, testing, protocols,
cards — and it ships inside the CLI (`tutuca install-skill`), which is why its
snippets are compiled by `ci` and these guides are not a second copy of it.
