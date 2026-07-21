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
  @component.component(
    name="Song",
    view="<span class=\"song\" @text=\".title\"></span>",
    fields={ "title": @component.FieldSpec::of_default(Str("")) },
  )
}

///|
fn playlist_comp() -> @component.Component {
  @component.component(
    name="Playlist",
    view=(
      #|<ul class="flex flex-col gap-1">
      #|  <li @each=".songs" class="flex gap-2 items-center">
      #|    <x render-it></x>
      #|    <button class="btn btn-xs rm" @on.click="$removeSong @key">remove</button>
      #|  </li>
      #|</ul>
    ),
    fields={
      "songs": @component.FieldSpec::of_default(
        Obj(KeyedList::{ order: [], items: Map([]) }),
      ),
    },
    methods={
      // The instance only sees `&Obj`, so the removal REBUILDS the keyed
      // list from obj_seq_entries minus the key (there is no downcast back
      // to KeyedList — the port's trait-object rule).
      "removeSong": (inst, args) => {
        guard args is [Str(key), ..] else { return inst.to_value() }
        match inst.get("songs") {
          Obj(o) =>
            match o.obj_seq_entries() {
              Some(entries) => {
                let mut next = KeyedList::{ order: [], items: Map([]) }
                for entry in entries {
                  let (pk, v) = entry
                  match pk {
                    KStr(s) => if s != key { next = next.set(s, v) }
                    _ => ()
                  }
                }
                inst.set("songs", Obj(next)).to_value()
              }
              None => inst.to_value()
            }
          _ => inst.to_value()
        }
      },
    },
  )
}

///|
fn demo_songs(song : @component.Component) -> KeyedList {
  KeyedList::{ order: [], items: Map([]) }
  .set("intro", song.make({ "title": Str("Intro") }).to_value())
  .set("middle", song.make({ "title": Str("Middle Eight") }).to_value())
  .set("outro", song.make({ "title": Str("Outro") }).to_value())
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
