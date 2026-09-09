# Storybook examples

Learn presents Quantity picker, Notification preferences, Task list,
Contact directory, and Document workspace in increasing complexity.
Their sources, fixtures, host services and compiled adapters live in
`showcase/`. `gen-showcase` generates the gallery metadata and the copies
used by the landing page, tutorials, playgrounds and bundled skill.

Reference contains focused examples of language features, recursion,
graphics, drag and drop, host integration, and diagnostics. Its stories
come from `all_examples()`; `stories()` adds the shared Learn progression.

## Run and test

```sh
moon test showcase
moon test storybook/examples
moon run --target native cmd/dev -- dist
python3 -m http.server --directory dist
```

Open `/storybook/` for the gallery. It includes live component state,
message traces, fuzzing, specifications, and raw values. Both compiled
examples and card scenes have interaction tests.

## Add an example

Choose an existing Learn component when it covers the behavior. Add a
Reference example for a distinct feature, together with a focused test.
Keep explanations in this guide or story descriptions; editable source
starts with code. Edit `.tutu` sources and run `gen` to refresh generated
MoonBit files. Never edit a `*_gen.mbt` file directly.

For an independent gallery project, use `tutuca new-storybook`. Its
quantity picker is self-contained and uses the published library.
