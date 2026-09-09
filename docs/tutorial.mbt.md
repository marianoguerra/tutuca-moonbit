# Build practical components with Tutuca

Follow these five examples in order. Each keeps its spec, logic and views together in a `.tutu` file. The same sources run in the card playground and supply the compiled examples. Their interaction tests cover both paths. Start in the card editor; read the MoonBit assembly when you need host integration or an ahead-of-time backend adapter.

State is one immutable value tree. Views read it; handlers update it; messages and intents connect components by path. No external services are needed for this tutorial.

## 1. Quantity picker

Choose a quantity within limits and see the total. Fields, events, derived values and invariants.

Increase the quantity to ten, then try both controls at their limits. The handlers enforce the bounds even when a message comes from somewhere other than a button. The total is derived from quantity and unit price.

```tutu
spec:
  QuantityPicker:
    field quantity :: Int
    field unit_cents :: Int

    invariant quantity_in_range:
      ~format: "Choose a quantity from 1 to 10."
      (it.quantity >= 1 && it.quantity <= 10)

logic:
  QuantityPicker:
    receive decrease:
      it.quantity := math.max(1, it.quantity - 1)

    receive increase:
      it.quantity := math.min(10, it.quantity + 1)

    compute total_cents: it.quantity * it.unit_cents
    compute total: @str{Total: €@((it.quantity * it.unit_cents) / 100)}
    pred minimum: it.quantity <= 1
    pred maximum: it.quantity >= 10

view:
  QuantityPicker:
    section(class: "card bg-base-200 max-w-md"):
      div(class: "card-body gap-3"):
        h2(class: "card-title"): "Quantity picker"
        p(): "Notebook · €5 each"
        div(class: "join items-center"):
          button(class: "btn join-item decrease", aria_label: "Decrease quantity", disabled: minimum(), ~on_click: decrease): "−"
          output(class: "px-4 quantity", aria_live: "polite"): @(it.quantity)
          button(class: "btn join-item increase", aria_label: "Increase quantity", disabled: maximum(), ~on_click: increase): "+"
        p(class: "total"): @(total())
```

[Open the card](https://marianoguerra.github.io/tutuca-moonbit/tutucard/?example=quantity-picker) · [Compiled assembly](https://github.com/marianoguerra/tutuca-moonbit/blob/main/showcase/quantity-picker.mbt)

## 2. Notification preferences

Edit, validate and apply notification settings. Bindings, conditional fields and draft state.

Enable email updates and apply an empty address. Enter an address, apply it, then edit and reset the draft. Draft fields and saved fields have distinct jobs; hiding an input does not discard its value.

```tutu
spec:
  NotificationPreferences:
    field enabled :: Bool
    field email :: String
    field frequency :: String
    field saved_enabled :: Bool
    field saved_email :: String
    field saved_frequency :: String
    field feedback :: String

logic:
  NotificationPreferences:
    receive apply:
      if (it.enabled && !(it.email.contains("@")))
      | it.feedback := "Enter an email address containing @."
      |
          it.saved_enabled := it.enabled
          it.saved_email := it.email.trim()
          it.saved_frequency := it.frequency
          it.feedback := "Preferences applied for this session."

    receive reset:
      it.enabled := it.saved_enabled
      it.email := it.saved_email
      it.frequency := it.saved_frequency
      it.feedback := "Draft reset."

view:
  NotificationPreferences:
    section(class: "card bg-base-200 max-w-md"):
      div(class: "card-body gap-3"):
        h2(class: "card-title"): "Notification preferences"
        label(class: "flex gap-2 items-center"):
          input(type: "checkbox", class: "checkbox enabled", checked: it.enabled, ~on_click: it.enabled := !it.enabled)
          "Email me updates"
        show(it.enabled):
          label():
            "Email address"
            input(type: "email", class: "input w-full email", value: it.email, ~on_input: it.email := e.value)
          label():
            "Frequency"
            select(class: "select w-full frequency", value: it.frequency, ~on_change: it.frequency := e.value):
              option(value: "daily"): "Daily digest"
              option(value: "weekly"): "Weekly digest"
        div(class: "flex gap-2"):
          button(class: "btn btn-primary apply", ~on_click: apply): "Apply preferences"
          button(class: "btn reset", ~on_click: reset): "Reset draft"
        p(class: "feedback", role: "status"): @(it.feedback)
```

[Open the card](https://marianoguerra.github.io/tutuca-moonbit/tutucard/?example=notification-preferences) · [Compiled assembly](https://github.com/marianoguerra/tutuca-moonbit/blob/main/showcase/notification-preferences.mbt)

## 3. Task list

Add, complete and filter tasks with stable identities. Child components, messages and keyed collections.

Add two tasks, complete one, and switch filters. Remove the completed task. Each child keeps its identity when the visible list changes; the parent owns collection membership and the completion index.

```tutu
spec:
  TaskList:
    field draft :: String
    field next_id :: Int
    field items :: Map.of(String, Instance.of(TaskItem))
    field completed :: Map.of(String, Bool)
    field filter :: String
    intent remove_task(String)
    intent task_done(String, Bool)

  TaskItem:
    field id :: String
    field text :: String
    field done :: Bool

logic:
  TaskList:
    receive add:
      if (it.draft.trim() != "")
      |
          it.next_id += 1
          it.items.set_at(@str{task-@(it.next_id)}, TaskItem(id: @str{task-@(it.next_id)}, text: it.draft.trim()))
          it.draft := ""

    answer remove_task(id):
      it.items.delete_at(id)
      it.completed.delete_at(id)

    answer task_done(id, done):
      if done
      | it.completed.set_at(id, true)
      | it.completed.delete_at(id)

    pred visible(value, key): (it.filter == "all" || (it.filter == "completed" && it.completed[key]) || (it.filter == "active" && !it.completed[key]))
    compute remaining: it.items.length() - it.completed.length()

  TaskItem:
    receive toggle:
      it.done := !it.done
      notify("task_done", it.id, it.done, ~route: dyn)

    receive remove:
      notify("remove_task", it.id, ~route: dyn)

view:
  TaskList:
    section(class: "card bg-base-200 max-w-lg"):
      div(class: "card-body gap-3"):
        h2(class: "card-title"): "Task list"
        label():
          "New task"
          input(class: "input w-full draft", value: it.draft, ~on_input: it.draft := e.value, ~on_keydown: add ~send)
        button(class: "btn btn-primary add", ~on_click: add): "Add task"
        div(class: "join"):
          button(class: "btn join-item all", ~on_click: it.filter := "all"): "All"
          button(class: "btn join-item active", ~on_click: it.filter := "active"): "Active"
          button(class: "btn join-item completed", ~on_click: it.filter := "completed"): "Completed"
        ul(class: "flex flex-col gap-2"):
          each(value, key in it.items, ~when: visible):
            render(value)
        show(it.items.is_empty()):
          p(): "No tasks yet. Add something you need to do."
        p(class: "remaining", aria_live: "polite"):
          @(remaining())
          " remaining"

  TaskItem:
    li(class: "flex gap-2 items-center task"):
      label(class: "flex gap-2 items-center grow"):
        input(type: "checkbox", class: "checkbox done", checked: it.done, ~on_click: toggle)
        span(class: if it.done | "label line-through" | "label"): @(it.text)
      button(class: "btn btn-sm remove", ~on_click: remove): "Remove"
```

[Open the card](https://marianoguerra.github.io/tutuca-moonbit/tutucard/?example=task-list) · [Compiled assembly](https://github.com/marianoguerra/tutuca-moonbit/blob/main/showcase/task-list.mbt)

## 4. Contact directory

Find a contact and edit their details. Search, pagination, selection and owner-held state.

Go to the second page, search for Alex Chen, and edit the selected name to Avery. The selection keeps its key even when the edited contact no longer matches the search. The host filters before slicing a page.

```tutu
spec:
  ContactDirectory:
    field contacts :: Map.of(String, Any)
    field order :: List.of(String)
    field query :: String
    field page :: Int
    field pages :: Int
    field keys :: List.of(String)
    field selected :: String
    field editor :: Instance.of(ContactEditor)
    field error :: String
    message init
    message contact_page_ok(Any)
    message contact_page_failed(Any)
    message contact_page_unhandled
    intent update_contact(String, String, String)

  ContactEditor:
    field id :: String
    field name :: String
    field email :: String
    field feedback :: String

  struct ContactData(name :: String, email :: String)

logic:
  ContactDirectory:
    receive init:
      ask("contact_page", it.contacts, it.query, it.page, it.order, ~route: lex)

    receive search(query):
      it.query := query
      it.page := 0
      send("init")

    receive previous:
      it.page := math.max(0, it.page - 1)
      send("init")

    receive next:
      it.page := math.min(it.pages - 1, it.page + 1)
      send("init")

    receive contact_page_ok(result):
      it.keys := result.keys
      it.page := result.page.to_int()
      it.pages := result.pages.to_int()
      it.error := ""

    receive contact_page_failed(error):
      it.error := "Could not search contacts. Try again."

    receive contact_page_unhandled:
      it.error := "Connect the contact_page host handler to search contacts."

    receive select(id):
      it.selected := id
      it.editor := ContactEditor(id: id, name: it.contacts[id].name, email: it.contacts[id].email)

    answer update_contact(id, name, email):
      it.contacts.set_at(id, ContactData(name: name, email: email))
      send("init")

    enrich contact_label(value, key):
      label = it.contacts[value].name
    compute page_label: @str{Page @(it.page + 1) of @(it.pages)}
    pred first_page: it.page <= 0
    pred last_page: it.page >= (it.pages - 1)

  ContactEditor:
    receive save:
      if (it.name.trim() == "" || !(it.email.contains("@")))
      | it.feedback := "Enter a name and an email address containing @."
      |
          notify("update_contact", it.id, it.name.trim(), it.email.trim(), ~route: dyn)
          it.feedback := "Contact updated for this session."

view:
  ContactDirectory:
    section(class: "card bg-base-200 max-w-2xl"):
      div(class: "card-body gap-3"):
        h2(class: "card-title"): "Contact directory"
        label():
          "Search by name or email"
          input(type: "search", class: "input w-full query", value: it.query, ~on_input: search(e.value))
        ul(class: "flex flex-col gap-2"):
          each(value, key in it.keys, ~enrich_with: contact_label):
            li():
              button(class: "btn btn-ghost contact", ~on_click: select(value)): @(label)
        show(it.keys.is_empty()):
          p(class: "empty"): "No contacts match your search."
        div(class: "join items-center"):
          button(class: "btn join-item previous", disabled: first_page(), ~on_click: previous): "Previous"
          span(class: "px-3 page"): @(page_label())
          button(class: "btn join-item next", disabled: last_page(), ~on_click: next): "Next"
        p(class: "error", role: "status"): @(it.error)
        hide(it.selected.is_empty()):
          render(it.editor)

  ContactEditor:
    section(class: "flex flex-col gap-2 editor"):
      h3(): "Edit contact"
      label():
        "Name"
        input(class: "input w-full name", value: it.name, ~on_input: it.name := e.value)
      label():
        "Email"
        input(class: "input w-full email", value: it.email, ~on_input: it.email := e.value)
      button(class: "btn btn-primary save", ~on_click: save): "Save contact"
      p(class: "feedback", role: "status"): @(it.feedback)
```

[Open the card](https://marianoguerra.github.io/tutuca-moonbit/tutucard/?example=contact-directory) · [Compiled assembly](https://github.com/marianoguerra/tutuca-moonbit/blob/main/showcase/contact-directory.mbt)

## 5. Document workspace

Edit Markdown documents and save through a host service. Composition, alternate views and asynchronous intents.

Edit a document, switch to the other document, and switch back. Preview the Markdown, simulate a failed save, then retry. Drafts stay with their document. Load and save use an in-memory demo service; restarting the example resets that storage.

```tutu
spec:
  DocumentWorkspace:
    field documents :: Map.of(String, Instance.of(DocumentEditor))
    field selected :: String
    message init

  DocumentEditor:
    field id :: String
    field title :: String
    field source :: String
    field saved_source :: String
    field revision :: Int
    field load_revision :: Int
    field busy :: Bool
    field fail_next :: Bool
    field feedback :: String
    field view :: String
    message load_document_ok(Any)
    message load_document_failed(Any)
    message load_document_unhandled
    message save_document_ok(Any)
    message save_document_failed(Any)
    message save_document_unhandled

logic:
  DocumentWorkspace:
    pred selected_document(value, key): key == it.selected

    receive init:
      if it.documents.is_empty()
      |
          it.documents.set_at("welcome", DocumentEditor(id: "welcome", title: "Welcome", source: "# Welcome", saved_source: "# Welcome", view: "edit"))
          it.documents.set_at("notes", DocumentEditor(id: "notes", title: "Meeting notes", source: "# Meeting notes", saved_source: "# Meeting notes", view: "edit"))
          it.selected := "welcome"

  DocumentEditor:
    receive edit(text):
      it.source := text
      it.revision += 1
      it.feedback := ""

    receive load:
      if !it.busy
      |
          it.busy := true
          it.load_revision := it.revision
          it.feedback := "Loading…"
          ask("load_document", it.id, it.fail_next, ~route: lex)
          it.fail_next := false

    receive save:
      if !it.busy
      |
          it.busy := true
          it.feedback := "Saving…"
          ask("save_document", it.id, it.source, it.fail_next, ~route: lex)
          it.fail_next := false

    receive load_document_ok(result):
      if (result.id == it.id)
      |
          it.busy := false
          if (it.revision == it.load_revision && it.source == it.saved_source)
          |
              it.source := result.source.to_string()
              it.saved_source := result.source.to_string()
              it.feedback := "Document loaded."
          | it.feedback := "Your unsaved draft was kept."

    receive load_document_failed(error):
      it.busy := false
      it.feedback := "Could not load. Choose Reload to retry."

    receive load_document_unhandled:
      it.busy := false
      it.feedback := "Connect the load_document host handler to reload."

    receive save_document_ok(result):
      if (result.id == it.id)
      |
          it.busy := false
          it.saved_source := result.source.to_string()
          it.feedback := "Saved in this demo session."

    receive save_document_failed(error):
      it.busy := false
      it.feedback := "Could not save. Your draft is kept; choose Save to retry."

    receive save_document_unhandled:
      it.busy := false
      it.feedback := "Connect the save_document host handler to save."

    pred dirty: it.source != it.saved_source

view:
  DocumentWorkspace:
    section(class: "card bg-base-200 max-w-3xl"):
      div(class: "card-body gap-3"):
        h2(class: "card-title"): "Document workspace"
        nav(class: "join", aria_label: "Documents"):
          button(class: "btn join-item welcome", ~on_click: it.selected := "welcome"): "Welcome"
          button(class: "btn join-item notes", ~on_click: it.selected := "notes"): "Meeting notes"
        each(value, key in it.documents, ~when: selected_document):
          render(value)
        p(class: "text-sm opacity-70"): "Demo storage lasts until this example is restarted."

  DocumentEditor:
    section(class: "flex flex-col gap-3 document"):
      h3(class: "title"): @(it.title)
      div(class: "join"):
        button(class: "btn join-item edit-tab", ~on_click: it.view := "edit"): "Edit"
        button(class: "btn join-item preview-tab", ~on_click: it.view := "preview"): "Preview"
      show(it.view == "edit"):
        label():
          "Markdown source"
          textarea(class: "textarea w-full min-h-48 source", value: it.source, ~on_input: edit(e.value))
      show(it.view == "preview"):
        article(class: "prose preview", inner_md: it.source)
      div(class: "flex gap-2"):
        button(class: "btn btn-primary save", disabled: it.busy, ~on_click: save): "Save"
        button(class: "btn reload", disabled: it.busy, ~on_click: load): "Reload"
      label(class: "flex gap-2 items-center"):
        input(type: "checkbox", class: "checkbox fail-next", checked: it.fail_next, ~on_click: it.fail_next := !it.fail_next)
        "Simulate the next request failing"
      show(dirty()):
        p(class: "dirty"): "Unsaved changes"
      p(class: "feedback", role: "status"): @(it.feedback)
```

[Open the card](https://marianoguerra.github.io/tutuca-moonbit/tutucard/?example=document-workspace) · [Compiled assembly](https://github.com/marianoguerra/tutuca-moonbit/blob/main/showcase/document-workspace.mbt)

## Test and integrate

Each shared source carries `tests:` scenarios. Run them in the card playground's Tests pane. Compiled components use `moon test` with the component harness; this repository runs their tests in `showcase/`. Quantity picker and notification preferences need only module assembly. The other compiled examples include adapters for script declarations the ahead-of-time backend refuses; the adjacent `.mbt` files implement those adapters once. The directory's host handler filters and paginates; the workspace's host owns demo storage.

For a project of your own, keep component behavior in `.tutu`, register host services on its module, and mount it with your chosen browser adapter. [First principles](first_principles.mbt.md) explains the runtime; [the authoring reference](../skill/tutuca/SKILL.md) covers the full language.
