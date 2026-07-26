// Port of docs/examples/custom-collection.js.
//
// Teaches: making `@each` iterate a CUSTOM collection. JS installs a
// `SEQ_INFO` walker on the prototype; the MoonBit analogue is implementing
// `@tutuca.Obj::obj_seq_entries` — the renderer iterates the entries it
// returns, keyed (`sk` breadcrumbs) so event paths resolve back to entries.
// `obj_item` resolves the same keys for seq-access reads.

///|
/// A minimal immutable keyed list: values in a map, explicit key order in an
/// array. Operations return new instances so state transactions see a change.
priv struct KeyedList {
  order : Array[String]
  items : Map[String, @tutuca.Value]
}

///|
fn KeyedList::set(self : KeyedList, k : String, v : @tutuca.Value) -> KeyedList {
  let order = if self.items.contains(k) { self.order } else { self.order + [k] }
  let items = self.items.to_array() |> Map::from_array
  items[k] = v
  { order, items }
}

///|
impl @tutuca.Obj for KeyedList with fn obj_seq_entries(self) {
  Some(self.order.map(k => (KStr(k), self.items.get(k).unwrap_or(Null))))
}

///|
impl @tutuca.Obj for KeyedList with fn obj_item(self, key) {
  match key {
    KStr(s) => self.items.get(s)
    _ => None
  }
}

///|
fn song_comp() -> @component.Component {
  song_component(init={ title: "" })
}

///|
fn playlist_comp() -> @component.Component {
  playlist_component(
    init={ songs: Obj(KeyedList::{ order: [], items: Map([]) }) },
    // The state only sees `&Obj`, so the removal REBUILDS the keyed list from
    // obj_seq_entries minus the key (there is no downcast back to KeyedList —
    // the port's trait-object rule).
    update=(s, msg, _ctx) => {
      match PlaylistMsg::from_dispatch(msg) {
        Some(RemoveSong(key_v)) => {
          guard key_v is Str(key) else { return None }
          guard s.songs is Obj(o) else { return None }
          guard o.obj_seq_entries() is Some(entries) else { return None }
          let mut next = KeyedList::{ order: [], items: Map([]) }
          for entry in entries {
            let (pk, v) = entry
            match pk {
              KStr(k) => if k != key { next = next.set(k, v) }
              _ => ()
            }
          }
          Some({ songs: Obj(next) })
        }
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
fn demo_songs(song : @component.Component) -> KeyedList {
  KeyedList::{ order: [], items: Map([]) }
  .set("intro", song.make({ "title": Str("Intro") }))
  .set("middle", song.make({ "title": Str("Middle Eight") }))
  .set("outro", song.make({ "title": Str("Outro") }))
}

///|
pub fn custom_collection_module() -> @component.ModuleDef {
  let song = song_comp()
  @component.ModuleDef::new(
    name="custom-collection",
    components=[playlist_comp(), song],
    examples=[
      {
        component: "Playlist",
        title: "Playlist",
        args: { "songs": Obj(demo_songs(song)) },
        view: None,
      },
    ],
  )
}
