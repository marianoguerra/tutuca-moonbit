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
priv struct SongState {
  title : String
} derive(ToJson, FromJson)

///|
fn song_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<span class=\"song\" @text=\".title\"></span>",
      ),
    },
    name="Song",
    init=SongState::{ title: "" },
  )
}

///|
/// The `songs` field holds the custom KeyedList as an opaque Obj — declared
/// `@tutuca.Value` in the state, it round-trips updates losslessly.
priv struct PlaylistState {
  songs : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn playlist_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<ul class="flex flex-col gap-1">
          #|  <li @each=".songs" class="flex gap-2 items-center">
          #|    <x render-it></x>
          #|    <button class="btn btn-xs rm" @on.click="$removeSong @key">remove</button>
          #|  </li>
          #|</ul>
        ),
      ),
    },
    name="Playlist",
    init=PlaylistState::{ songs: Obj(KeyedList::{ order: [], items: Map([]) }) },
    mutate={
      // The state only sees `&Obj`, so the removal REBUILDS the keyed
      // list from obj_seq_entries minus the key (there is no downcast back
      // to KeyedList — the port's trait-object rule).
      "removeSong": (s : PlaylistState, args) => {
        guard args is [Str(key), ..] else { return s }
        match s.songs {
          Obj(o) =>
            match o.obj_seq_entries() {
              Some(entries) => {
                let mut next = KeyedList::{ order: [], items: Map([]) }
                for entry in entries {
                  let (pk, v) = entry
                  match pk {
                    KStr(k) => if k != key { next = next.set(k, v) }
                    _ => ()
                  }
                }
                { songs: Obj(next) }
              }
              None => s
            }
          _ => s
        }
      },
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
