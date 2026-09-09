# Shared component examples

`catalog.json` defines the public learning order: Quantity picker, Notification
preferences, Task list, Contact directory, and Document workspace. Each `.tutu`
is the canonical card, including fixtures and interaction tests. Its `.mbt`
assembles the compiled module and supplies any backend adapters the generator
explicitly refuses. `services.mbt` supplies the directory query and document
storage handlers shared by the compiled modules and card host.

The browser card host delays document responses. Compiled tests inject a
scheduler to exercise late responses deterministically. Storage is created per
module or mount and lasts only for that demo session.

Run `moon run --target native cmd/dev -- gen-showcase` after changing sources,
catalog metadata, or page templates. It copies sources into the playgrounds
and bundled skill and generates the landing page, tutorials, and Storybook
metadata. Run `gen` after editing `.tutu`, then `gen-showcase` after formatting
the compiled assembly. `check-showcase` checks all copies without rewriting.

Keep explanations outside the editor. Editable source starts with code. The
landing uses Tutucard unless the displayed MoonBit implements substantive
behavior. Specialized examples remain in the Reference collections and retain
their existing regression coverage.

This directory is repository content, not a published library package.
Consumer examples receive self-contained scaffold copies and never import it.
