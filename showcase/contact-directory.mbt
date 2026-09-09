///|
pub fn contact_directory_module() -> @component.ModuleDef {
  let editor = contact_editor_component()
  let directory = contact_directory_component(
    initial=ContactDirectoryState::fresh(),
    update=(s, dispatch, _ctx) => {
      match dispatch {
        Receive("contact_page_ok", [result, ..]) =>
          Next({
            ..s,
            keys: result.field("keys").list().map(v => v.str()),
            page: result.field("page").int(),
            pages: result.field("pages").int(),
            error: "",
          })
        Receive("select", [Str(id), ..]) => {
          guard s.contacts.get(id) is Some(contact) else { return Unchanged }
          Next({
            ..s,
            selected: id,
            editor: editor.make({
              "id": Str(id),
              "name": contact.field("name"),
              "email": contact.field("email"),
            }),
          })
        }
        _ => Unhandled
      }
    },
    enrich=_ => {
      Some((s, binds, _key, value, _iter, _stack) => {
        binds["label"] = s.contacts
          .get(value.str())
          .unwrap_or(Null)
          .field("name")
      })
    },
  )
  @component.ModuleDef::new(
    name="contact-directory",
    components=[directory, editor],
    intents=demo_intents(),
    examples=[
      {
        component: "ContactDirectory",
        title: "Contact directory",
        args: Map([]),
        view: None,
      },
      {
        component: "ContactDirectory",
        title: "No results",
        args: contact_directory_init_args("no results").unwrap(),
        view: None,
      },
    ],
  )
}
