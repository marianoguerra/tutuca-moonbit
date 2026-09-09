///|
pub fn demo_intents(
  later? : (() -> Unit) -> Unit = f => f(),
) -> Map[String, Array[@component.IntentFn]] {
  let documents : Map[String, @tutuca.Value] = {
    "welcome": Str("# Welcome"),
    "notes": Str("# Meeting notes"),
  }
  {
    "contact_page": [
      IntentFn((call, answer) => {
        let contacts = call.args[0].map()
        let query = call.args[1].str().trim().to_owned().to_lower()
        let keys = call.args[3].list().map(v => v.str())
        let matches = keys.filter(key => {
          let contact = contacts.get(key).unwrap_or(Null)
          contact.field("name").str().to_lower().contains(query) ||
          contact.field("email").str().to_lower().contains(query)
        })
        let pages = (matches.length() + 2) / 3
        let pages = if pages < 1 { 1 } else { pages }
        let wanted = call.args[2].int()
        let page = if wanted < 0 {
          0
        } else if wanted >= pages {
          pages - 1
        } else {
          wanted
        }
        let visible : Array[@tutuca.Value] = []
        for i in (page * 3)..<matches.length() {
          if visible.length() == 3 {
            break
          }
          visible.push(Str(matches[i]))
        }
        answer(
          Ok(
            Map({
              "keys": List(visible),
              "page": Num(page.to_double()),
              "pages": Num(pages.to_double()),
            }),
          ),
        )
      }),
    ],
    "load_document": [
      IntentFn((call, answer) => {
        let id = call.args[0].str()
        let fail = call.args[1].is_truthy()
        later(() => {
          if fail {
            answer(Failed(Str("The demo request failed.")))
          } else {
            answer(
              Ok(
                Map({
                  "id": Str(id),
                  "source": documents.get(id).unwrap_or(Str("")),
                }),
              ),
            )
          }
        })
      }),
    ],
    "save_document": [
      IntentFn((call, answer) => {
        let id = call.args[0].str()
        let source = call.args[1]
        let fail = call.args[2].is_truthy()
        later(() => {
          if fail {
            answer(Failed(Str("The demo request failed.")))
          } else {
            documents[id] = source
            answer(Ok(Map({ "id": Str(id), "source": source })))
          }
        })
      }),
    ],
  }
}
