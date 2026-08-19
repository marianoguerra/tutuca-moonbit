// The gallery: the three components of the storybook, wired to a catalog.
//
// The shape is the one `dyncomp/ui` uses, and deliberately so — a `Registry` to
// read, a `MakeInstance` the host supplies because building a guest instance is
// the one thing a backend-agnostic package cannot do, and an optional
// `dev_tools` component the host puts in the bar. Anything that can be done
// without a browser is done here, which is why the whole gallery is drivable
// from `moon test`.

///|
/// Build one instance of a catalogued component: a named configuration through
/// its `init`, or the bare constructor when the name is empty.
///
/// Same signature as `dyncomp/ui`'s, so a wasm host can hand the SAME function
/// to both and a story is built by exactly the code that would have placed the
/// component for real.
pub type MakeInstance = (
  @registry.ComponentRef,
  String,
  Map[String, @tutuca.Value],
) -> @tutuca.Value?

///|
/// A mounted gallery's two halves: what it reads, and what it builds with.
pub struct Gallery {
  registry : @registry.Registry
  make : MakeInstance
  /// The gallery's own components, by name. Needed because a card and a
  /// sidebar row are built as VALUES from inside a handler, where no scope is
  /// in hand.
  comps : Map[String, @component.Component]
}

///|
fn Gallery::make_(
  self : Gallery,
  name : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args)
    None => Null
  }
}

// --- cards ------------------------------------------------------------------

///|
/// One story as a card, with its component already built.
///
/// A constructor that answers `None` becomes a card carrying the refusal
/// rather than a missing card: a configuration that no longer builds is the
/// single most useful thing a storybook can tell you, and dropping it silently
/// is how it stops being able to.
fn Gallery::card(self : Gallery, story : Story) -> @tutuca.Value {
  let built = (self.make)(story.ref_, story.init, Map([]))
  let (target, error) = match built {
    Some(v) => (v, "")
    None =>
      (
        Null,
        if story.init == "" {
          "\{story.ref_.to_id()} could not be built with its defaults"
        } else {
          "\{story.ref_.to_id()} could not be built from init '\{story.init}'"
        },
      )
  }
  self.make_("StoryCard", {
    "title": Str(story.title),
    "doc": Str(story.doc),
    "module": Str(story.ref_.module_),
    "name": Str(story.ref_.name),
    "init": Str(story.init),
    "args": Str(story.args),
    "target": target,
    "error": Str(error),
  })
}

///|
/// Every card, in catalog order.
fn Gallery::cards(self : Gallery) -> Array[@tutuca.Value] {
  stories_of(self.registry).map(s => self.card(s))
}

///|
/// The sidebar, with `selected` decided against the current filter.
fn Gallery::nav(
  self : Gallery,
  module_ : String,
  name : String,
) -> Array[@tutuca.Value] {
  nav_of(stories_of(self.registry)).map(e => {
    self.make_("StoryNav", {
      "module": Str(e.ref_.module_),
      "name": Str(e.ref_.name),
      "count": Num(e.count.to_double()),
      "selected": Bool(e.ref_.module_ == module_ && e.ref_.name == name),
    })
  })
}

// --- filtering --------------------------------------------------------------

///|
fn text_field(v : @tutuca.Value, name : String) -> String {
  match v.field(name) {
    Str(s) => s
    _ => ""
  }
}

///|
/// Whether one card survives the bar's filter and the sidebar's selection.
///
/// The two are independent on purpose: picking a component in the sidebar and
/// then typing narrows within it, rather than replacing what was picked. A
/// query with no sidebar selection searches everything, which is what the `all`
/// button restores.
fn card_matches(s : DyncompStorybookState, card : @tutuca.Value) -> Bool {
  if s.name != "" &&
    (
      text_field(card, "module") != s.module_ ||
      text_field(card, "name") != s.name
    ) {
    return false
  }
  let needle = s.query.trim().to_owned().to_lower()
  if needle == "" {
    return true
  }
  let hay = [
      text_field(card, "title"),
      text_field(card, "module"),
      text_field(card, "name"),
      text_field(card, "init"),
      text_field(card, "doc"),
    ]
    .join(" ")
    .to_lower()
  hay.contains(needle)
}

///|
fn shown_count(s : DyncompStorybookState) -> Int {
  let mut n = 0
  for c in s.cards {
    if card_matches(s, c) {
      n = n + 1
    }
  }
  n
}

///|
/// What the empty line says, which depends on WHY it is empty: nothing loaded,
/// or nothing matching. A single sentence for both would be wrong half the
/// time, and the half it is wrong for is the one where a person is waiting for
/// a bundle to arrive.
fn empty_message(s : DyncompStorybookState) -> String {
  if s.cards.is_empty() {
    "No bundles loaded. Drop a .tutuca.tar.gz on the page, or load one by URL."
  } else if s.query != "" {
    "Nothing matches \"\{s.query}\"."
  } else {
    "Nothing to show."
  }
}

// --- the components ---------------------------------------------------------

///|
fn nav_comp() -> @component.Component {
  story_nav_component(update=(s, msg, ctx) => {
    match StoryNavMsg::from_dispatch(msg) {
      // The row reports which one it is; the gallery decides what selecting
      // means. A row that filtered the list itself would need to know there is
      // a list.
      Some(Pick) => {
        StoryNavBubble::NavPicked(s.module_, s.name).bubble(ctx)
        Unchanged
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
fn card_comp() -> @component.Component {
  story_card_component(
    compute=m => {
      match m {
        RefLabel =>
          Some((s, _args) => {
            Str(if s.module_ == "" { s.name } else { "\{s.module_}/\{s.name}" })
          })
      }
    },
    update=(s, msg, ctx) => {
      match StoryCardMsg::from_dispatch(msg) {
        // Rebuilding means asking the host for a fresh instance, which a card
        // cannot do — so it says what it is and lets the gallery answer.
        Some(Rebuild) => {
          StoryCardBubble::RebuildCard(s.module_, s.name, s.init_).bubble(ctx)
          Unhandled
        }
        Some(Unknown(_, _)) | None => Unhandled
      }
    },
  )
}

///|
fn Gallery::root_comp(
  self : Gallery,
  dev_tools~ : String,
) -> @component.Component {
  let cards = self.cards()
  let nav = self.nav("", "")
  let init : DyncompStorybookState = {
    ..DyncompStorybookState::zero(),
    cards,
    nav,
    theme: "light",
    mode: "main",
    status: "",
    emptyMessage: "No bundles loaded. Drop a .tutuca.tar.gz on the page, or load one by URL.",
  }
  dyncomp_storybook_component(
    // The host's own component in the bar, named at the seam because the
    // generator resolves a sibling only within one file and this one lives
    // wherever the host is.
    slots=if dev_tools == "" { Map([]) } else { { "devTools": dev_tools } },
    init~,
    compute=m => {
      match m {
        LayoutLabel =>
          Some((s, _args) => Str(if s.wide { "one per row" } else { "grid" }))
        DetailsLabel =>
          Some((s, _args) => {
            Str(if s.mode == "details" { "hide details" } else { "details" })
          })
        IsEmpty => Some((s, _args) => Bool(shown_count(s) == 0))
      }
    },
    // The filter runs at RENDER time over cards that already exist, which is
    // the whole reason the cards are built once: a keystroke must not tear down
    // and rebuild a live component tree, and a story whose component was mid-
    // interaction would lose it.
    when=w => {
      match w {
        Matches => Some((s, _key, item, _iter) => card_matches(s, item))
      }
    },
    update=(s, msg, ctx) => {
      match DyncompStorybookMsg::from_dispatch(msg) {
        Some(SetQuery(q)) =>
          return Next({ ..s, query: q, emptyMessage: "" } |> with_empty_message)
        Some(ChooseTheme(t)) => return Next({ ..s, theme: t })
        Some(ToggleWide) => return Next({ ..s, wide: not_(s.wide) })
        Some(ToggleDetails) =>
          return Next({
            ..s,
            mode: if s.mode == "details" {
              "main"
            } else {
              "details"
            },
          })
        Some(ShowAll) =>
          return Next(
            { ..s, module_: "", name: "", nav: self.nav("", "") }
            |> with_empty_message,
          )
        // Files dropped on the page. Forwarded to whatever the host put in the
        // bar, because reading one is exactly the kind of thing a
        // backend-agnostic package cannot do.
        Some(FilesDropped(_)) => {
          // The generator types `value` as text, because it reads the host
          // element's static `type` and a `<div>` has none. What actually
          // arrives is the list of dropped files, so it is read raw.
          let files = match msg {
            Input(_, [first, ..]) => first
            _ => Null
          }
          ctx.send_at_path(
            ctx.path().concat([FieldStep("devTools")]),
            "filesDropped",
            [files],
          )
          return Unhandled
        }
        Some(Unknown(_, _)) | None => ()
      }
      match DyncompStorybookReceive::from_dispatch(msg) {
        Some(CatalogChanged(module_)) => return Next(self.reloaded(s, module_))
        Some(SetStatus(t)) => return Next({ ..s, status: t })
        // The merged `Receive` now carries this component's own VIEW names as
        // well as the schema's, so `Unknown` no longer covers everything this
        // match has nothing to say about. They are answered by the Input match
        // beside this one, and task 19 folds the two into one.
        _ => ()
      }
      // The same two, arriving from BELOW: the host's loader sits inside the
      // bar, so its news bubbles rather than being sent. Both directions are
      // declared because both happen — a test pushes the news down, and a
      // running page has it come up.
      match DyncompStorybookBubble::from_dispatch(msg) {
        Some(CatalogChanged(module_)) => return Next(self.reloaded(s, module_))
        Some(Unknown(_, _)) | None => ()
      }
      match StoryNavBubble::from_dispatch(msg) {
        Some(NavPicked(module_, name)) =>
          return Next(
            { ..s, module_, name, nav: self.nav(module_, name) }
            |> with_empty_message,
          )
        Some(Unknown(_, _)) | None => ()
      }
      match StoryCardBubble::from_dispatch(msg) {
        // One card, from scratch. Rebuilding the whole set here would throw
        // away every OTHER card's live state to reset one of them.
        Some(RebuildCard(module_, name, init_)) => {
          let ref_ : @registry.ComponentRef = { module_, name }
          let cards = s.cards.map(c => {
            if text_field(c, "module") == module_ &&
              text_field(c, "name") == name &&
              text_field(c, "init") == init_ {
              match self.story_for(ref_, init_) {
                Some(story) => self.card(story)
                None => c
              }
            } else {
              c
            }
          })
          return Next({ ..s, cards, })
        }
        Some(Unknown(_, _)) | None => ()
      }
      Unhandled
    },
  )
}

///|
/// `!` as a function, so a record-update expression can use it inline.
fn not_(b : Bool) -> Bool {
  !b
}

///|
/// Keep the empty line's sentence in step with the state it describes. Applied
/// through `|>` at every place that changes what "empty" would mean, rather
/// than recomputed in the view: it is one string, and a `compute` that runs on
/// every render to produce it would be the same answer many more times.
fn with_empty_message(s : DyncompStorybookState) -> DyncompStorybookState {
  { ..s, emptyMessage: empty_message(s) }
}

///|
/// The story a card was built from, looked up again by (component, init).
fn Gallery::story_for(
  self : Gallery,
  ref_ : @registry.ComponentRef,
  init : String,
) -> Story? {
  for s in stories_of(self.registry) {
    if s.ref_ == ref_ && s.init == init {
      return Some(s)
    }
  }
  None
}

///|
/// The gallery as a module, and the `Gallery` behind it.
///
/// `dev_tools` names a component the HOST supplies for the bar — loading
/// bundles, in the wasm shell's case. A gallery driven by a test names none,
/// and the slot renders as nothing.
pub fn gallery_module(
  registry : @registry.Registry,
  make : MakeInstance,
  dev_tools? : String = "",
) -> (@component.ModuleDef, Gallery) {
  let gallery : Gallery = { registry, make, comps: Map([]) }
  // Leaves first, and not for tidiness: the root's `init` builds cards and
  // sidebar rows out of them, so `comps` has to hold them by the time it runs.
  let chrome = [nav_comp(), card_comp()]
  for c in chrome {
    gallery.comps[c.name] = c
  }
  let root = gallery.root_comp(dev_tools~)
  gallery.comps[root.name] = root
  (
    @component.ModuleDef::new(
      name="dyncompstorybook",
      components=[root, ..chrome],
    ),
    gallery,
  )
}

///|
/// A bundle arrived, or the same one arrived again and hot-swapped.
///
/// Every card is rebuilt rather than only the new module's: a hot swap changes
/// which components a module declares, so keeping the old cards would leave
/// instances of code that is no longer loaded on the page, looking fine.
fn Gallery::reloaded(
  self : Gallery,
  s : DyncompStorybookState,
  module_ : String,
) -> DyncompStorybookState {
  { ..self.refresh(s), status: "loaded \{module_}" }
}

///|
/// Rebuild the story set against the catalog as it is now.
///
/// A host calls this after a bundle registers, by sending `catalogChanged` to
/// the root; this is the same work, exposed for a host that would rather push
/// the new state itself.
pub fn Gallery::refresh(
  self : Gallery,
  s : DyncompStorybookState,
) -> DyncompStorybookState {
  { ..s, cards: self.cards(), nav: self.nav(s.module_, s.name) }
  |> with_empty_message
}
