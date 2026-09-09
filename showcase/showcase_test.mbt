///|
test "quantity bounds and total" {
  let h = @harness.mount(quantity_picker_module(), "QuantityPicker")
  assert_eq(h.text("output.quantity"), "1")
  h.click("button.increase")
  assert_eq(h.text("p.total"), "Total: €10")
  for _ in 0..<15 {
    h.send_at_root("increase")
  }
  assert_eq(h.text("output.quantity"), "10")
  for _ in 0..<15 {
    h.send_at_root("decrease")
  }
  assert_eq(h.text("output.quantity"), "1")
}

///|
test "preferences validate apply and reset" {
  let h = @harness.mount(
    notification_preferences_module(),
    "NotificationPreferences",
  )
  h.click("input.enabled")
  h.click("button.apply")
  assert_eq(h.text("p.feedback"), "Enter an email address containing @.")
  h.type_into("input.email", "alex@example.test")
  h.click("button.apply")
  h.type_into("input.email", "draft@example.test")
  h.click("button.reset")
  assert_eq(h.value_of("input.email"), "alex@example.test")
}

///|
test "task children retain identity through filtering and removal" {
  let h = @harness.mount(task_list_module(), "TaskList")
  h.type_into("input.draft", "   ")
  h.click("button.add")
  assert_eq(h.find_all("li.task").length(), 0)
  for title in ["Return library books", "Book a dentist appointment"] {
    h.type_into("input.draft", title)
    h.click("button.add")
  }
  h.click("input.done")
  assert_eq(h.text("p.remaining"), "1 remaining")
  h.click("button.active")
  assert_eq(h.text("span.label"), "Book a dentist appointment")
  h.click("button.completed")
  assert_eq(h.text("span.label"), "Return library books")
  h.click("button.remove")
  h.click("button.all")
  assert_eq(h.text("span.label"), "Book a dentist appointment")
}

///|
test "contact search precedes paging and editing retains selection" {
  let h = @harness.mount(contact_directory_module(), "ContactDirectory")
  assert_eq(h.texts("button.contact"), [
    "Alex Chen", "Bea Singh", "Casey Rivera",
  ])
  h.click("button.next")
  assert_eq(h.drive_value().field("keys").list().map(v => v.str()), [
    "dev", "ellis", "fran",
  ])
  assert_eq(h.texts("button.contact"), [
    "Dev Morgan", "Ellis Park", "Fran Silva",
  ])
  h.type_into("input.query", "Alex Chen")
  assert_eq(h.texts("button.contact"), ["Alex Chen"])
  assert_eq(h.text("span.page"), "Page 1 of 1")
  h.click("button.contact")
  h.type_into("input.name", "Avery Chen")
  h.click("button.save")
  assert_eq(h.drive_value().field("selected").str(), "alex")
  assert_eq(h.find_all("button.contact").length(), 0)
  h.type_into("input.query", "Avery")
  assert_eq(h.text("button.contact"), "Avery Chen")
  h.type_into("input.query", "nobody")
  assert_eq(h.text("p.empty"), "No contacts match your search.")
}

///|
test "document save responses follow their original child and preserve newer edits" {
  let pending : Array[() -> Unit] = []
  let h = @harness.mount(
    document_workspace_module(later=f => pending.push(f)),
    "DocumentWorkspace",
    markdown_filter=@mdfilter.make_filter,
  )
  h.type_into("textarea.source", "# First draft")
  h.click("button.save")
  assert_eq(h.text("p.feedback"), "Saving…")
  h.type_into("textarea.source", "# Newer draft")
  h.click("button.notes")
  pending.remove(0)()
  h.send_at_root("init")
  assert_eq(h.value_of("textarea.source"), "# Meeting notes")
  h.click("button.welcome")
  assert_eq(h.text("p.feedback"), "Saved in this demo session.")
  assert_eq(h.value_of("textarea.source"), "# Newer draft")
  assert_eq(h.text("p.dirty"), "Unsaved changes")
  h.click("input.fail-next")
  h.click("button.save")
  pending.remove(0)()
  h.send_at_root("init")
  assert_eq(
    h.text("p.feedback"),
    "Could not save. Your draft is kept; choose Save to retry.",
  )
  h.click("button.save")
  pending.remove(0)()
  h.send_at_root("init")
  assert_eq(h.find_all("p.dirty").length(), 0)
  h.click("button.preview-tab")
  assert_eq(h.text("article.preview"), "Newer draft")
}
