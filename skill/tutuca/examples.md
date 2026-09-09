# Practical component progression

Use these examples in order when learning, and choose the smallest relevant one when implementing a component. These are shared sources, not separate skill editions.

- **Quantity picker** — Fields, events, derived values and invariants. Read [the shared source](examples/quantity-picker.tutu). Increase the quantity to ten, then try both controls at their limits. The handlers enforce the bounds even when a message comes from somewhere other than a button. The total is derived from quantity and unit price.

- **Notification preferences** — Bindings, conditional fields and draft state. Read [the shared source](examples/notification-preferences.tutu). Enable email updates and apply an empty address. Enter an address, apply it, then edit and reset the draft. Draft fields and saved fields have distinct jobs; hiding an input does not discard its value.

- **Task list** — Child components, messages and keyed collections. Read [the shared source](examples/task-list.tutu). Add two tasks, complete one, and switch filters. Remove the completed task. Each child keeps its identity when the visible list changes; the parent owns collection membership and the completion index.

- **Contact directory** — Search, pagination, selection and owner-held state. Read [the shared source](examples/contact-directory.tutu). Go to the second page, search for Alex Chen, and edit the selected name to Avery. The selection keeps its key even when the edited contact no longer matches the search. The host filters before slicing a page.

- **Document workspace** — Composition, alternate views and asynchronous intents. Read [the shared source](examples/document-workspace.tutu). Edit a document, switch to the other document, and switch back. Preview the Markdown, simulate a failed save, then retry. Drafts stay with their document. Load and save use an in-memory demo service; restarting the example resets that storage.

On the landing page use Tutucard when MoonBit only assembles or mounts the component. Use the MoonBit playground when its displayed code supplies behavior the card source cannot express. Put explanations outside editors; the first visible line should be code. Keep focused language recipes in the reference section.

The directory needs the `contact_page` host handler. The workspace needs `load_document` and `save_document` handlers; the hosted playground provides demo implementations. In a standalone host, register your own handlers and test success, failure and route exhaustion.
