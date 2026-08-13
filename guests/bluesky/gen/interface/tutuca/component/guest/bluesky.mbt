///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The bluesky guest module: three components that DISPLAY ATProto content —
/// one message (`Post`), a reply tree (`Thread`), and an account (`Profile`).
/// Ported from the JS `tutuca-components/src/atproto` module group, which
/// renders the same surfaces from the same plain ATProto-shaped data.
///
/// Two things make this port different from the JS one, and both come from the
/// bundle being UNTRUSTED wasm rather than app code:
///
///   1. **Two origins, and they are written in the views.** An untrusted
///      bundle's views may not name a browser network or CSS sink
///      (`dyncomp/policy`'s view authority rule), because what a dynamic
///      attribute will hold is unknowable when the view is registered. What CAN
///      be known is the ORIGIN, when the view states it as a literal — so this
///      bundle asks for `cap-external-urls` and spends it on exactly two:
///      `cdn.bsky.app` for the pictures and `bsky.app` for the links. Both are
///      literals in the markup and neither is ever a value, which is why a host
///      can read this bundle's whole network reach off its views.
///
///      What the guest supplies is only the PATH. An avatar, a banner and a
///      thumbnail arrive as the full urls the API hands out and are read back
///      through `cdn_path`, which keeps the part after the CDN and refuses
///      everything else: a picture hosted anywhere but that CDN is not drawn,
///      and the initials underneath it are what shows. The same split decides
///      the links — a mention, a hashtag and the permalink are `bsky.app` paths
///      and navigate, while a link somebody POSTED points wherever they chose,
///      so it stays text with its target in the tooltip. An image is still its
///      alt text when the record carries no thumbnail.
///
///      A host that does not grant the capability refuses this bundle whole
///      rather than loading a degraded one, which is the bargain every
///      capability here makes. `dyncomp/SECURITY.md` §3 is the rest of it.
///   2. **No clock.** `env.now-ms` needs `cap-clock`, and a bundle that asks
///      for a capability is refused by every page that has not thought about
///      the question (see `examples/dyncomp-dice`). A timestamp is therefore
///      formatted from the record's own `createdAt` — "11 Aug 2026, 14:03" —
///      rather than shown as "2h ago", which no one here can know.
///
/// The three components split the persistence contract the way the counter and
/// the todo list do: `Post` and `Profile` are exactly their declared fields, so
/// they persist NOTHING and the host projects and rebuilds them itself, while
/// `Thread` keeps a collapsed-subtree set the schema never names and writes it.
///
/// Its static declaration and views live beside the module; sdk.mbt does the ABI.

// ── the shape all three components are made of ───────────────────────────────

///|
/// One ATProto facet: a range of the message text and what it points at.
///
/// The offsets are UTF-8 BYTE offsets — that is the wire format — while a
/// MoonBit string is UTF-16, which is why `segments_of` measures the text a
/// character at a time instead of slicing it directly.
priv struct Facet {
  start : Int
  stop : Int
  /// "link" | "mention" | "tag". Anything else renders as plain text.
  kind : String
  /// The uri, the mentioned handle, or the tag — without its `#`.
  value : String
}

///|
/// One attached image: what it says it is, and where its thumbnail lives.
///
/// Both halves are kept because both get drawn: the thumbnail when the CDN in
/// the view serves it, the alt text on a chip when it does not.
priv struct Img {
  alt : String
  /// The record's `thumb`, as it arrived — a full url. `cdn_path` is what
  /// decides whether any of it can be drawn.
  thumb : String
}

///|
/// One message. `Post` holds one of these, `Thread` a flattened tree of them
/// and `Profile` the account's recent ones, so the projection helpers below
/// are written once and used by all three.
priv struct Msg {
  uri : String
  display_name : String
  handle : String
  text : String
  created_at : String
  /// The author's picture, as the full url the API hands out.
  avatar : String
  facets : Array[Facet]
  images : Array[Img]
  replies : Int
  reposts : Int
  likes : Int
  /// Reply depth in a thread; 0 for a message standing on its own.
  depth : Int
}

///|
/// The one origin this bundle's pictures come from, with the `/` that ends it.
///
/// The trailing slash is the whole check rather than a tidiness: without it
/// `https://cdn.bsky.app.attacker.test/x` and `https://cdn.bsky.app@attacker.test/x`
/// both pass a prefix test, and both are somebody else's host. It is the same
/// boundary the host insists on when it reads the origin off the view
/// (`dyncomp/policy/external_url.mbt`), spelled here so the two agree.
const CDN = "https://cdn.bsky.app/"

///|
/// What is left of a url once the CDN is taken off the front, or `""` for a
/// url anywhere else — including a relative one, which is a request to the
/// HOST's origin and not this bundle's to make.
///
/// This is the guest's half of `cap-external-urls`: the view names the origin,
/// this decides that the record's url is actually ON it, and what crosses
/// between them is a path. A picture that fails the test is not drawn at all,
/// and drawing nothing is a state the views already have — it is what a record
/// with no picture gets.
fn cdn_path(url : String) -> String {
  guard url.has_prefix(CDN) else { return "" }
  url[CDN.length():].to_owned()
}

// ── reading the host's values ────────────────────────────────────────────────

///|
fn str_at(m : UInt64, key : String) -> String {
  match @values.map_get(m, key) {
    Some(@values.Value::Text(s)) => s
    _ => ""
  }
}

///|
fn int_at(m : UInt64, key : String) -> Int {
  match @values.map_get(m, key) {
    Some(@values.Value::Number(n)) => n.to_int()
    _ => 0
  }
}

///|
fn items_at(m : UInt64, key : String) -> Array[@values.Value] {
  match @values.map_get(m, key) {
    Some(@values.Value::List(h)) => list_items(h)
    _ => []
  }
}

///|
fn list_items(h : UInt64) -> Array[@values.Value] {
  let out : Array[@values.Value] = []
  for i in 0U..<@values.list_len(h) {
    out.push(@values.list_get(h, i))
  }
  out
}

///|
fn facets_of(items : Array[@values.Value]) -> Array[Facet] {
  let out : Array[Facet] = []
  for v in items {
    guard v is @values.Value::Map(m) else { continue }
    out.push({
      start: int_at(m, "byteStart"),
      stop: int_at(m, "byteEnd"),
      kind: str_at(m, "kind"),
      value: str_at(m, "value"),
    })
  }
  out
}

///|
/// The attached images. A bare string is an alt text and no picture, which is
/// the shape the fixtures were written in before there was a picture to have.
fn images_of(items : Array[@values.Value]) -> Array[Img] {
  let out : Array[Img] = []
  for v in items {
    match v {
      @values.Value::Text(s) => out.push({ alt: s, thumb: "" })
      @values.Value::Map(m) =>
        out.push({ alt: str_at(m, "alt"), thumb: str_at(m, "thumb") })
      _ => ()
    }
  }
  out
}

///|
/// The images as they arrived, which is what a host reads back when it
/// projects the field.
fn images_value(images : Array[Img]) -> @values.Value {
  vlist(
    images.map(i => vmap([("alt", vtext(i.alt)), ("thumb", vtext(i.thumb))])),
  )
}

///|
/// The images as a VIEW reads them: the alt text, and the path the thumbnail
/// is at on the CDN the view names — empty for a record that carries none, or
/// one whose picture is somewhere this bundle cannot reach.
fn image_items_value(images : Array[Img]) -> @values.Value {
  vlist(
    images.map(i => {
      vmap([("alt", vtext(i.alt)), ("path", vtext(cdn_path(i.thumb)))])
    }),
  )
}

///|
/// One message out of the map a declared list field arrives as. Every key is
/// optional: a record the host built from a form, or from JSON somebody typed,
/// is missing most of them and still has to render.
fn msg_of(m : UInt64, depth? : Int = 0) -> Msg {
  {
    uri: str_at(m, "uri"),
    display_name: str_at(m, "displayName"),
    handle: str_at(m, "handle"),
    text: str_at(m, "text"),
    created_at: str_at(m, "createdAt"),
    avatar: str_at(m, "avatar"),
    facets: facets_of(items_at(m, "facets")),
    images: images_of(items_at(m, "images")),
    replies: int_at(m, "replyCount"),
    reposts: int_at(m, "repostCount"),
    likes: int_at(m, "likeCount"),
    depth: match @values.map_get(m, "depth") {
      Some(@values.Value::Number(n)) => n.to_int()
      _ => depth
    },
  }
}

///|
fn msgs_of(h : UInt64) -> Array[Msg] {
  let out : Array[Msg] = []
  for v in list_items(h) {
    match v {
      @values.Value::Map(m) => out.push(msg_of(m))
      _ => ()
    }
  }
  out
}

// ── building the host's values ───────────────────────────────────────────────

///|
fn vtext(s : String) -> @values.Value {
  @values.Value::Text(s)
}

///|
fn vnum(i : Int) -> @values.Value {
  @values.Value::Number(i.to_double())
}

///|
fn vmap(pairs : Array[(String, @values.Value)]) -> @values.Value {
  let m = @values.map_new()
  for p in pairs {
    @values.map_set(m, p.0, p.1)
  }
  @values.Value::Map(m)
}

///|
fn vlist(items : Array[@values.Value]) -> @values.Value {
  let h = @values.list_new()
  for v in items {
    @values.list_push(h, v)
  }
  @values.Value::List(h)
}

///|
/// A message back in the shape it arrived in — what the host reads when it
/// projects a declared list field to JSON, and what it hands back on a
/// hot-swap migration. The inverse of `msg_of`.
fn msg_value(m : Msg) -> @values.Value {
  vmap([
    ("uri", vtext(m.uri)),
    ("displayName", vtext(m.display_name)),
    ("handle", vtext(m.handle)),
    ("text", vtext(m.text)),
    ("createdAt", vtext(m.created_at)),
    ("avatar", vtext(m.avatar)),
    (
      "facets",
      vlist(
        m.facets.map(f => {
          vmap([
            ("byteStart", vnum(f.start)),
            ("byteEnd", vnum(f.stop)),
            ("kind", vtext(f.kind)),
            ("value", vtext(f.value)),
          ])
        }),
      ),
    ),
    ("images", images_value(m.images)),
    ("replyCount", vnum(m.replies)),
    ("repostCount", vnum(m.reposts)),
    ("likeCount", vnum(m.likes)),
    ("depth", vnum(m.depth)),
  ])
}

// ── rich text: facets over UTF-8 byte offsets ────────────────────────────────

///|
/// How many bytes this character takes in UTF-8 — the unit ATProto facets
/// count in.
fn utf8_len(c : Char) -> Int {
  let n = c.to_int()
  if n < 0x80 {
    1
  } else if n < 0x800 {
    2
  } else if n < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// One run of the message text: plain, or the visible half of a facet.
priv struct Seg {
  text : String
  /// Where the facet points, as text — the run's tooltip either way, and all a
  /// segment that cannot navigate has.
  target : String
  /// The bsky.app PATH this run points at, for the two kinds whose target is
  /// on bsky.app: a mention and a hashtag. `""` for a link, whose origin is
  /// whatever the person who posted it typed, so the view has no literal to
  /// pin it to.
  path : String
  /// "text" | "link" | "mention" | "tag"
  kind : String
}

///|
/// The facets, in start order and without the overlaps: a facet that begins
/// inside its predecessor is dropped rather than allowed to shred the text.
/// Insertion sort because a message carries a handful of facets and a sort
/// written out is one fewer API to be wrong about.
fn ordered_facets(facets : Array[Facet]) -> Array[Facet] {
  let out : Array[Facet] = []
  for f in facets {
    if f.stop <= f.start || f.start < 0 {
      continue
    }
    let mut i = out.length()
    out.push(f)
    while i > 0 && out[i - 1].start > f.start {
      out[i] = out[i - 1]
      out[i - 1] = f
      i = i - 1
    }
  }
  let kept : Array[Facet] = []
  let mut cursor = 0
  for f in out {
    if f.start >= cursor {
      kept.push(f)
      cursor = f.stop
    }
  }
  kept
}

///|
fn slice(chars : Array[Char], from : Int, to : Int) -> String {
  let buf = StringBuilder::new()
  for i in from..<to {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Where a facet points, spelled the way bsky.app spells it. The tooltip of
/// the run it belongs to, and for a link the only thing it has: the origin
/// belongs to whoever posted it, so no view can name it.
fn facet_target(kind : String, value : String) -> String {
  match kind {
    "link" => value
    "mention" => "bsky.app/profile/\{value}"
    "tag" => "bsky.app/hashtag/\{value}"
    _ => ""
  }
}

///|
/// The same target as a bsky.app path, which is the half a view can turn into
/// a link. A link facet has none, deliberately.
fn facet_path(kind : String, value : String) -> String {
  guard value != "" else { return "" }
  match kind {
    "mention" => "profile/\{value}"
    "tag" => "hashtag/\{value}"
    _ => ""
  }
}

///|
/// Cut the message text on its facet boundaries into a flat run of typed
/// segments the view iterates. Pure, and the one piece of real work in this
/// bundle: the offsets are UTF-8 bytes, so the text is measured character by
/// character and a facet whose offsets land mid-character is dropped rather
/// than allowed to split one.
fn segments_of(text : String, facets : Array[Facet]) -> Array[Seg] {
  let chars : Array[Char] = text.iter().collect()
  // byte offset of each character index, plus the end
  let offs = Array::make(chars.length() + 1, 0)
  for i in 0..<chars.length() {
    offs[i + 1] = offs[i] + utf8_len(chars[i])
  }
  fn char_at_byte(b : Int) -> Int {
    for i in 0..<offs.length() {
      if offs[i] == b {
        return i
      }
      if offs[i] > b {
        return -1
      }
    }
    -1
  }

  let segs : Array[Seg] = []
  let mut cursor = 0
  for f in ordered_facets(facets) {
    let from = char_at_byte(f.start)
    let to = char_at_byte(f.stop)
    if from < 0 || to < 0 || from < cursor {
      continue
    }
    if from > cursor {
      segs.push({
        text: slice(chars, cursor, from),
        target: "",
        path: "",
        kind: "text",
      })
    }
    segs.push({
      text: slice(chars, from, to),
      target: facet_target(f.kind, f.value),
      path: facet_path(f.kind, f.value),
      kind: f.kind,
    })
    cursor = to
  }
  if cursor < chars.length() {
    segs.push({
      text: slice(chars, cursor, chars.length()),
      target: "",
      path: "",
      kind: "text",
    })
  }
  segs
}

///|
/// The runs as a view reads them. `external` is the third state the two
/// booleans a view can ask for do not cover on their own: a run that points
/// somewhere and cannot be followed, which is a link somebody posted.
fn segments_value(m : Msg) -> @values.Value {
  vlist(
    segments_of(m.text, m.facets).map(s => {
      vmap([
        ("text", vtext(s.text)),
        ("target", vtext(s.target)),
        ("path", vtext(s.path)),
        ("external", @values.Value::Boolean(s.target != "" && s.path == "")),
        ("kind", vtext(s.kind)),
      ])
    }),
  )
}

// ── the small formatting jobs a display component is made of ─────────────────

///|
/// What to call the author: the display name, else the handle, else the one
/// honest answer left.
fn name_of(m : Msg) -> String {
  display_name_or(m.display_name, m.handle)
}

///|
fn display_name_or(display_name : String, handle : String) -> String {
  if display_name != "" {
    display_name
  } else if handle != "" {
    handle
  } else {
    "unknown"
  }
}

///|
fn at_handle(handle : String) -> String {
  if handle == "" {
    ""
  } else {
    "@\{handle}"
  }
}

///|
/// ASCII upper-case, which is all an initial needs: a letter outside ASCII is
/// left as it is rather than case-mapped wrongly.
fn upper(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// The avatar, in the only form an untrusted bundle can draw one: up to two
/// initials off the display name, or off the handle's first two labels.
fn initials_of(display_name : String, handle : String) -> String {
  let source = if display_name != "" { display_name } else { handle }
  let buf = StringBuilder::new()
  let mut taken = 0
  let mut fresh = true
  for c in source.iter() {
    if c == ' ' || c == '.' || c == '-' || c == '_' || c == '@' {
      fresh = true
      continue
    }
    if fresh && taken < 2 {
      buf.write_char(upper(c))
      taken = taken + 1
    }
    fresh = false
  }
  let text = buf.to_string()
  if text == "" {
    "?"
  } else {
    text
  }
}

///|
fn month_name(n : Int) -> String {
  match n {
    1 => "Jan"
    2 => "Feb"
    3 => "Mar"
    4 => "Apr"
    5 => "May"
    6 => "Jun"
    7 => "Jul"
    8 => "Aug"
    9 => "Sep"
    10 => "Oct"
    11 => "Nov"
    _ => "Dec"
  }
}

///|
/// An ISO 8601 stamp as something a person reads — "11 Aug 2026, 14:03".
///
/// No clock is involved, which is the point: "2h ago" would need `cap-clock`,
/// and a bundle that asks for a capability is a bundle some pages refuse. A
/// stamp this bundle cannot parse is shown verbatim rather than blanked.
fn time_label(iso : String) -> String {
  let chars : Array[Char] = iso.iter().collect()
  guard chars.length() >= 16 else { return iso }
  let digits_ok = check_digits(chars, [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15])
  guard digits_ok && chars[4] == '-' && chars[7] == '-' && chars[13] == ':' else {
    return iso
  }
  let month = two_digit(chars, 5)
  guard month >= 1 && month <= 12 else { return iso }
  let day = slice(chars, 8, 10)
  let year = slice(chars, 0, 4)
  let time = slice(chars, 11, 16)
  "\{day} \{month_name(month)} \{year}, \{time}"
}

///|
fn check_digits(chars : Array[Char], at : Array[Int]) -> Bool {
  for i in at {
    if i >= chars.length() || chars[i] < '0' || chars[i] > '9' {
      return false
    }
  }
  true
}

///|
fn two_digit(chars : Array[Char], at : Int) -> Int {
  (chars[at].to_int() - '0'.to_int()) * 10 +
  (chars[at + 1].to_int() - '0'.to_int())
}

///|
/// A count the way a social app writes one: 1234 is "1.2K", 12345 is "12K".
/// Kept in the guest rather than the view because it is arithmetic, and a
/// view that did it would be a view doing arithmetic.
fn count_label(n : Int) -> String {
  if n < 0 {
    return "0"
  }
  if n < 1000 {
    return n.to_string()
  }
  if n < 1000000 {
    return scaled(n, 1000, "K")
  }
  scaled(n, 1000000, "M")
}

///|
fn scaled(n : Int, unit : Int, suffix : String) -> String {
  let whole = n / unit
  let tenth = n % unit * 10 / unit
  if whole < 10 && tenth > 0 {
    "\{whole}.\{tenth}\{suffix}"
  } else {
    "\{whole}\{suffix}"
  }
}

///|
/// `at://did/app.bsky.feed.post/rkey` as the bsky.app PATH the record is at —
/// `profile/<who>/post/<rkey>`, which the view puts under its own literal
/// origin. `""` for a uri that is not a post: there is no permalink to offer,
/// and offering one built out of a shrug would be worse than none.
fn permalink_path_of(uri : String, handle : String) -> String {
  guard uri.has_prefix("at://") else { return "" }
  let chars : Array[Char] = uri.iter().collect()
  let parts : Array[String] = []
  let mut from = 5
  for i in 5..<chars.length() {
    if chars[i] == '/' {
      parts.push(slice(chars, from, i))
      from = i + 1
    }
  }
  parts.push(slice(chars, from, chars.length()))
  guard parts.length() == 3 && parts[1] == "app.bsky.feed.post" else {
    return ""
  }
  let who = if handle != "" { handle } else { parts[0] }
  "profile/\{who}/post/\{parts[2]}"
}

///|
/// The same permalink as the text a person reads and can select, which is what
/// the link says on the page. The origin is spelled out here because it is
/// prose; the `href` beside it gets the origin from the view.
fn permalink_of(uri : String, handle : String) -> String {
  let path = permalink_path_of(uri, handle)
  if path == "" {
    ""
  } else {
    "bsky.app/\{path}"
  }
}

///|
// ── Post: one message, and one row of a thread ───────────────────────────────

///|
/// One bluesky message.
///
/// It is also the row `Thread` and `Profile` are made of, which is why it
/// carries `depth`, `focus` and `foldable`: a view cannot iterate a value it
/// found inside another iteration (the sequence a `@each` takes is a field
/// path, not a loop binding), so a message's rich text can only be a loop in
/// the component that OWNS it. One message per component is therefore not
/// composition for its own sake — it is the only shape in which a reply keeps
/// its links.
///
/// Its state is exactly the fields the manifest declares, so it does not
/// persist: the host projects it and builds it back itself.
priv struct Post {
  msg : Msg
  liked : Bool
  reposted : Bool
  /// The message a thread is ABOUT, marked; set by whoever built the row.
  focus : Bool
  /// How many replies sit under this one in the thread that built it. 0 when
  /// the message stands on its own, and what the fold button counts.
  foldable : Int
  folded : Bool
  /// Whether this message is a ROW inside a larger surface — a thread, a feed —
  /// rather than standing on its own. A row draws smaller (the view picks the
  /// avatar size from it) and sits under something that owns the list it is in.
  ///
  /// It used to mean more than that: a row's like / repost / fold was kept by
  /// the component above, because a child in a list could not return a successor
  /// (the host encoded a nested instance only at the top level of a written
  /// value, so the list came back as plain data and the write was refused). That
  /// is fixed, so a row keeps its own answers like anything else.
  owned : Bool
}

///|
/// What this reader's own like adds to the count the record arrived with. The
/// record is what the network said; the flag is what the person did since, and
/// the two are kept apart so a refused write does not have to un-edit a number.
fn bump(on : Bool) -> Int {
  if on {
    1
  } else {
    0
  }
}

///|
impl DynComponent for Post with fn get_field(self, name) {
  let m = self.msg
  match name {
    // the declared fields
    "uri" => Some(vtext(m.uri))
    "displayName" => Some(vtext(m.display_name))
    "handle" => Some(vtext(m.handle))
    "text" => Some(vtext(m.text))
    "createdAt" => Some(vtext(m.created_at))
    "avatar" => Some(vtext(m.avatar))
    "facets" => Some(facets_value(m.facets))
    "images" => Some(images_value(m.images))
    "replyCount" => Some(vnum(m.replies))
    "repostCount" => Some(vnum(m.reposts))
    "likeCount" => Some(vnum(m.likes))
    "liked" => Some(@values.Value::Boolean(self.liked))
    "reposted" => Some(@values.Value::Boolean(self.reposted))
    "depth" => Some(vnum(m.depth))
    "focus" => Some(@values.Value::Boolean(self.focus))
    "foldable" => Some(vnum(self.foldable))
    "folded" => Some(@values.Value::Boolean(self.folded))
    "owned" => Some(@values.Value::Boolean(self.owned))
    // and what the view reads instead: the projections, computed here so the
    // template stays a template
    "name" => Some(vtext(name_of(m)))
    "handleText" => Some(vtext(at_handle(m.handle)))
    "initials" => Some(vtext(initials_of(m.display_name, m.handle)))
    // The picture's path on the CDN the view names, and "" for an author with
    // no picture or one hosted somewhere else. The view draws the initials
    // UNDER the image rather than instead of it, so both of those, and a fetch
    // that fails after all of this, land on the same disc.
    "avatarPath" => Some(vtext(cdn_path(m.avatar)))
    "time" => Some(vtext(time_label(m.created_at)))
    "segments" => Some(segments_value(m))
    "imageItems" => Some(image_items_value(m.images))
    "replies" => Some(vtext(count_label(m.replies)))
    "reposts" => Some(vtext(count_label(m.reposts + bump(self.reposted))))
    "likes" => Some(vtext(count_label(m.likes + bump(self.liked))))
    "permalink" => Some(vtext(permalink_of(m.uri, m.handle)))
    "permalinkPath" => Some(vtext(permalink_path_of(m.uri, m.handle)))
    // The indent, as a list of that many things to draw. An untrusted view has
    // no `style` attribute to put a margin in — so the depth arrives as rails
    // the view iterates, which needs no CSS the guest wrote.
    "rail" =>
      Some(vlist(Array::make(if m.depth > 0 { m.depth } else { 0 }, vnum(0))))
    "foldLabel" =>
      Some(vtext(if self.folded { "+\{self.foldable}" } else { "−" }))
    _ => None
  }
}

///|
fn facets_value(facets : Array[Facet]) -> @values.Value {
  vlist(
    facets.map(f => {
      vmap([
        ("byteStart", vnum(f.start)),
        ("byteEnd", vnum(f.stop)),
        ("kind", vtext(f.kind)),
        ("value", vtext(f.value)),
      ])
    }),
  )
}

///|
impl DynComponent for Post with fn handle(self, bucket, name, _args) {
  guard bucket is INPUT else { return Unhandled }
  match name {
    // Optimistic, and announced: the flag is THIS row's — it returns its own
    // successor, and the host writes it home into whatever list holds it — while
    // the bubble is what a host would turn into the `app.bsky.feed.like` write.
    // The two are different jobs: one is what the screen shows, the other is
    // what somebody with a network connection should do about it. This bundle
    // has no network and is only saying what happened.
    "toggleLike" => {
      @control.emit(if self.liked { "unliked" } else { "liked" }, [
        vtext(self.msg.uri),
      ])
      Changed({ ..self, liked: !self.liked } as &DynComponent)
    }
    "toggleRepost" => {
      @control.emit(if self.reposted { "unreposted" } else { "reposted" }, [
        vtext(self.msg.uri),
      ])
      Changed({ ..self, reposted: !self.reposted } as &DynComponent)
    }
    // The fold flag is THIS row's too, and the bubble is what the thread above
    // hears: the row knows it is folded, and only the thread knows which rows
    // are UNDER it and therefore stop rendering. Both halves are needed, and
    // they are not the same fact.
    "toggleFold" => {
      guard self.foldable > 0 else { return Unchanged }
      @control.emit(if self.folded { "unfolded" } else { "folded" }, [
        vtext(self.msg.uri),
      ])
      Changed({ ..self, folded: !self.folded } as &DynComponent)
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for Post with fn call_method(self, name, _args) {
  match name {
    // the accessible one-line description of the card, and the `title` a
    // reader gets on hover
    "summary" => {
      let m = self.msg
      vtext(
        "\{name_of(m)} \{at_handle(m.handle)} — \{count_label(m.replies)} replies, \{count_label(m.reposts + bump(self.reposted))} reposts, \{count_label(m.likes + bump(self.liked))} likes",
      )
    }
    // what the fold button says it will do, since its label is a glyph
    "foldTitle" =>
      if self.folded {
        vtext("show \{self.foldable} replies")
      } else {
        vtext("fold \{self.foldable} replies away")
      }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Post with fn with_field(self, name, v) {
  let m = self.msg
  match (name, v) {
    ("uri", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, uri: s } } as &DynComponent)
    ("displayName", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, display_name: s } } as &DynComponent)
    ("handle", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, handle: s } } as &DynComponent)
    ("text", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, text: s } } as &DynComponent)
    ("createdAt", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, created_at: s } } as &DynComponent)
    ("avatar", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, avatar: s } } as &DynComponent)
    ("facets", @values.Value::List(h)) =>
      Some(
        { ..self, msg: { ..m, facets: facets_of(list_items(h)) } }
        as &DynComponent,
      )
    ("images", @values.Value::List(h)) =>
      Some(
        { ..self, msg: { ..m, images: images_of(list_items(h)) } }
        as &DynComponent,
      )
    ("replyCount", @values.Value::Number(n)) =>
      Some({ ..self, msg: { ..m, replies: n.to_int() } } as &DynComponent)
    ("repostCount", @values.Value::Number(n)) =>
      Some({ ..self, msg: { ..m, reposts: n.to_int() } } as &DynComponent)
    ("likeCount", @values.Value::Number(n)) =>
      Some({ ..self, msg: { ..m, likes: n.to_int() } } as &DynComponent)
    ("depth", @values.Value::Number(n)) =>
      Some({ ..self, msg: { ..m, depth: n.to_int() } } as &DynComponent)
    ("liked", @values.Value::Boolean(b)) =>
      Some({ ..self, liked: b } as &DynComponent)
    ("reposted", @values.Value::Boolean(b)) =>
      Some({ ..self, reposted: b } as &DynComponent)
    ("focus", @values.Value::Boolean(b)) =>
      Some({ ..self, focus: b } as &DynComponent)
    ("foldable", @values.Value::Number(n)) =>
      Some({ ..self, foldable: n.to_int() } as &DynComponent)
    ("folded", @values.Value::Boolean(b)) =>
      Some({ ..self, folded: b } as &DynComponent)
    ("owned", @values.Value::Boolean(b)) =>
      Some({ ..self, owned: b } as &DynComponent)
    _ => None
  }
}

///|
fn empty_msg() -> Msg {
  {
    uri: "",
    display_name: "",
    handle: "",
    text: "",
    created_at: "",
    avatar: "",
    facets: [],
    images: [],
    replies: 0,
    reposts: 0,
    likes: 0,
    depth: 0,
  }
}

///|
fn make_post(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut msg = empty_msg()
  let mut liked = false
  let mut reposted = false
  let mut focus = false
  let mut foldable = 0
  let mut folded = false
  let mut owned = false
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("uri", @values.Value::Text(s)) => msg = { ..msg, uri: s }
      ("displayName", @values.Value::Text(s)) =>
        msg = { ..msg, display_name: s }
      ("handle", @values.Value::Text(s)) => msg = { ..msg, handle: s }
      ("text", @values.Value::Text(s)) => msg = { ..msg, text: s }
      ("createdAt", @values.Value::Text(s)) => msg = { ..msg, created_at: s }
      ("avatar", @values.Value::Text(s)) => msg = { ..msg, avatar: s }
      ("facets", @values.Value::List(h)) =>
        msg = { ..msg, facets: facets_of(list_items(h)) }
      ("images", @values.Value::List(h)) =>
        msg = { ..msg, images: images_of(list_items(h)) }
      ("replyCount", @values.Value::Number(n)) =>
        msg = { ..msg, replies: n.to_int() }
      ("repostCount", @values.Value::Number(n)) =>
        msg = { ..msg, reposts: n.to_int() }
      ("likeCount", @values.Value::Number(n)) =>
        msg = { ..msg, likes: n.to_int() }
      ("depth", @values.Value::Number(n)) => msg = { ..msg, depth: n.to_int() }
      ("liked", @values.Value::Boolean(b)) => liked = b
      ("reposted", @values.Value::Boolean(b)) => reposted = b
      ("focus", @values.Value::Boolean(b)) => focus = b
      ("foldable", @values.Value::Number(n)) => foldable = n.to_int()
      ("folded", @values.Value::Boolean(b)) => folded = b
      ("owned", @values.Value::Boolean(b)) => owned = b
      _ => ()
    }
  }
  ({ msg, liked, reposted, focus, foldable, folded, owned } : Post)
  as &DynComponent
}

///|
/// One message as constructor args for a child `Post` — the same names the
/// manifest declares, because a child is built exactly the way the host would
/// build one.
fn child_args(
  m : Msg,
  focus~ : Bool,
  foldable~ : Int,
  liked? : Bool = false,
  reposted? : Bool = false,
  folded? : Bool = false,
) -> Array[(String, @values.Value)] {
  [
    ("uri", vtext(m.uri)),
    ("displayName", vtext(m.display_name)),
    ("handle", vtext(m.handle)),
    ("text", vtext(m.text)),
    ("createdAt", vtext(m.created_at)),
    ("avatar", vtext(m.avatar)),
    ("facets", facets_value(m.facets)),
    ("images", images_value(m.images)),
    ("replyCount", vnum(m.replies)),
    ("repostCount", vnum(m.reposts)),
    ("likeCount", vnum(m.likes)),
    ("depth", vnum(m.depth)),
    ("focus", @values.Value::Boolean(focus)),
    ("foldable", vnum(foldable)),
    ("liked", @values.Value::Boolean(liked)),
    ("reposted", @values.Value::Boolean(reposted)),
    ("folded", @values.Value::Boolean(folded)),
    // this message is a row inside something larger, which is what the view
    // reads to draw it smaller
    ("owned", @values.Value::Boolean(true)),
  ]
}

// ── Thread: a reply tree, flattened, as a list of Posts ──────────────────────

///|
/// A conversation.
///
/// The tree arrives FLAT — every message carries its own `depth` — because a
/// static view cannot recurse, and because flat is what makes folding a
/// subtree the contiguous-range operation `replies_under` does in one pass.
///
/// Each message becomes a child `Post` through `control.make-instance`, and
/// `rows` is the tokens of the ones currently visible: the host renders them
/// with `<x render-each=".rows">`.
///
/// A row's LIKE, REPOST and FOLD live here rather than in the row, keyed by
/// uri: the thread is what knows which messages are under which, so it is what
/// can answer a fold, and keeping the other two beside it means one answer to
/// "what has this reader done". A row announces (`liked`, `folded`, …) and this
/// rebuilds that one row with the new flag.
///
/// It is also the shape that survived a host limitation: until `child_json`
/// (`dyncomp/host/dynobj.mbt`) recursed, a successor a CHILD returned could not
/// travel back into a parent's LIST field, so a row that kept its own state
/// changed in the guest and not on the screen. That is fixed; this design is
/// kept because it is the better one, not because it is the only one.
priv struct Thread {
  posts : Array[Msg]
  /// The uri of the message the thread is about; "" for none.
  focus : String
  /// One child token per message, in `posts` order.
  children : Array[UInt64]
  /// The uris this reader folded away. It is here rather than on the row
  /// because it is the THREAD's question: which messages stop rendering because
  /// something above them is folded. The row keeps its own `folded` for its own
  /// glyph, and the two are different facts about the same click.
  ///
  /// Likes and reposts are NOT here. They used to be, kept only so a rebuilt row
  /// could be handed them back — a workaround for a child in a list being unable
  /// to return a successor. The row keeps them now.
  collapsed : Array[String]
}

///|
/// How many messages hang under the one at `i` — the contiguous run of deeper
/// messages that follows it, which is what "flattened" buys.
fn replies_under(posts : Array[Msg], i : Int) -> Int {
  let depth = posts[i].depth
  let mut n = 0
  for j in (i + 1)..<posts.length() {
    if posts[j].depth <= depth {
      break
    }
    n = n + 1
  }
  n
}

///|
/// A list the HOST is writing back, as child tokens.
///
/// `None` unless every element is an instance, which is what makes a write of
/// plain data — a fixture, a form, anything that is not the list this component
/// handed out — a refusal rather than a silently emptied field.
fn tokens_of(v : @values.Value) -> Array[UInt64]? {
  guard v is @values.Value::List(h) else { return None }
  let out : Array[UInt64] = []
  for i in 0U..<@values.list_len(h) {
    guard @values.list_get(h, i) is @values.Value::Instance(t) else {
      return None
    }
    out.push(t)
  }
  Some(out)
}

///|
/// A set with `uri` added or taken out — the flags this thread keeps for its
/// rows, which are sets rather than a field on the message because they are
/// this READER's doing and not part of the record.
fn with_uri(set : Array[String], uri : String, on : Bool) -> Array[String] {
  let out = set.filter(u => u != uri)
  if on {
    out.push(uri)
  }
  out
}

///|
/// Build the child for one message: the record, plus where it sits and what
/// this reader has done to it.
///
/// The token comes back immediately and the child is constructed after the
/// current call returns: the Component Model forbids re-entering a component
/// while a call into it is active, so `make-instance` only reserves. Nothing
/// here reads a child, so nothing here has to wait for one.
fn Thread::make_row(self : Thread, i : Int) -> UInt64 {
  let m = self.posts[i]
  @control.make_instance(
    "Post",
    child_args(
      m,
      focus=m.uri != "" && m.uri == self.focus,
      foldable=replies_under(self.posts, i),
      folded=self.collapsed.contains(m.uri),
    ),
  )
}

///|
/// A child per message. Called when the messages or the focus change — never
/// on a like or a fold, which rebuild the ONE row that changed.
fn Thread::build_rows(self : Thread) -> Thread {
  let children : Array[UInt64] = []
  for i in 0..<self.posts.length() {
    children.push(self.make_row(i))
  }
  { ..self, children, }
}

///|
/// Whether this thread has that message at all — a bubble naming one it does
/// not is not this thread's to act on.
fn Thread::has(self : Thread, uri : String) -> Bool {
  self.posts.iter().any(m => m.uri == uri)
}

///|
/// The rows a view draws: every message except the ones under a folded one.
fn Thread::visible(self : Thread) -> Array[Int] {
  let out : Array[Int] = []
  let mut skip_below = -1
  for i in 0..<self.posts.length() {
    let m = self.posts[i]
    if skip_below >= 0 {
      if m.depth > skip_below {
        continue
      }
      skip_below = -1
    }
    if self.collapsed.contains(m.uri) && replies_under(self.posts, i) > 0 {
      skip_below = m.depth
    }
    out.push(i)
  }
  out
}

///|
impl DynComponent for Thread with fn get_field(self, name) {
  match name {
    // declared
    "posts" => Some(vlist(self.posts.map(msg_value)))
    "focus" => Some(vtext(self.focus))
    // derived: the child components the view renders, minus the folded-away
    "rows" =>
      Some(
        vlist(
          self
          .visible()
          .filter(i => i < self.children.length())
          .map(i => @values.Value::Instance(self.children[i])),
        ),
      )
    _ => None
  }
}

///|
/// Everything a row announces arrives here.
///
/// `folded` stops here — a page has no use for it and the thread is the only
/// thing that can act on it. `liked` and `reposted` are handled AND left to
/// travel on: this bundle cannot write to a PDS, so the component above is the
/// one that turns a like into an `app.bsky.feed.like` record.
impl DynComponent for Thread with fn handle(self, bucket, name, args) {
  guard bucket is BUBBLE else { return Unhandled }
  guard args is [@values.Value::Text(uri), ..] else { return Unhandled }
  guard uri != "" && self.has(uri) else { return Unchanged }
  match name {
    // The row has already flipped its OWN `folded` and returned a successor;
    // what this adds is the half only the thread knows — which messages sit
    // under it and therefore stop rendering. It does not rebuild the row:
    // destroying and remaking it would throw away the successor the host just
    // wrote home, along with whatever else the reader had done to it.
    "folded" | "unfolded" => {
      @control.stop_propagation()
      let on = name == "folded"
      guard self.collapsed.contains(uri) != on else { return Unchanged }
      Changed(
        { ..self, collapsed: with_uri(self.collapsed, uri, on) }
        as &DynComponent,
      )
    }
    // `liked` / `reposted` are deliberately not handled: the row keeps them, and
    // the announcement is for whoever above can actually write a record.
    _ => Unhandled
  }
}

///|
impl DynComponent for Thread with fn call_method(self, name, _args) {
  match name {
    "summary" => {
      let total = self.posts.length()
      let shown = self.visible().length()
      if shown == total {
        vtext("\{total} messages")
      } else {
        vtext("\{total} messages · \{total - shown} folded away")
      }
    }
    _ => @values.Value::Nil
  }
}

///|
/// Writing either declared field rebuilds every row, because a row is told at
/// build time which message it is and whether it is the focus. What this
/// reader had done goes with them: it belonged to messages that are no longer
/// the ones here.
///
/// The old tokens are not dropped here. The host owns a child's lifetime — it
/// wraps the token and sweeps what a superseded instance held once the
/// transaction settles — so a guest dropping a whole list would be racing it.
/// `rebuild_row` is the one place a token is released, because there the guest
/// is the only one who knows the row is gone.
impl DynComponent for Thread with fn with_field(self, name, v) {
  match (name, v) {
    ("posts", @values.Value::List(h)) => {
      let next : Thread = {
        posts: msgs_of(h),
        focus: self.focus,
        children: [],
        collapsed: [],
      }
      Some(next.build_rows() as &DynComponent)
    }
    ("focus", @values.Value::Text(s)) =>
      Some(({ ..self, focus: s } : Thread).build_rows() as &DynComponent)
    // A row returned a successor and the host is writing the whole list home.
    // What it hands back is the list it was SHOWN — `visible()` — so it goes
    // home through the same function that decided those positions. A length that
    // does not match means the two disagree about what is on screen, and
    // guessing which position a token belongs to is worse than refusing.
    ("rows", _) =>
      match tokens_of(v) {
        Some(shown) => {
          let at = self.visible().filter(i => i < self.children.length())
          guard at.length() == shown.length() else { None }
          let children = self.children.copy()
          for k, i in at {
            children[i] = shown[k]
          }
          Some({ ..self, children, } as &DynComponent)
        }
        None => None
      }
    _ => None
  }
}

///|
/// No `persist`: a thread is its declared fields plus host-owned tokens, and a
/// token means nothing in a later session. The host projects `posts` and
/// `focus` and constructs from them, which rebuilds the rows here; what a
/// reader had folded is what a reload costs.
fn make_thread(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut posts : Array[Msg] = []
  let mut focus = ""
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      // hot-swap migration hands the declared fields back as args
      ("posts", @values.Value::List(h)) => posts = msgs_of(h)
      ("focus", @values.Value::Text(s)) => focus = s
      _ => ()
    }
  }
  ({ posts, focus, children: [], collapsed: [] } : Thread).build_rows()
  as &DynComponent
}

// ── Profile: an account ──────────────────────────────────────────────────────

///|
/// One account: who it is, what it says about itself, its three counts, and
/// its recent messages — which are child `Post`s, for the same reason a
/// thread's rows are, and whose likes it keeps for the same reason.
priv struct Profile {
  display_name : String
  handle : String
  description : String
  /// The account's picture and the strip behind it, as the full urls the API
  /// hands out. Both are read back through `cdn_path`, and both fall back to
  /// what was drawn before there were pictures: the initials, and a flat band
  /// of `base-200`.
  avatar : String
  banner : String
  followers : Int
  follows : Int
  posts_count : Int
  following : Bool
  posts : Array[Msg]
  children : Array[UInt64]
}

///|
/// A message in a feed stands on its own: no depth, nothing to fold.
fn Profile::make_row(self : Profile, i : Int) -> UInt64 {
  let m = self.posts[i]
  @control.make_instance(
    "Post",
    child_args({ ..m, depth: 0 }, focus=false, foldable=0),
  )
}

///|
fn Profile::build_rows(self : Profile) -> Profile {
  let children : Array[UInt64] = []
  for i in 0..<self.posts.length() {
    children.push(self.make_row(i))
  }
  { ..self, children, }
}

///|
impl DynComponent for Profile with fn get_field(self, name) {
  match name {
    // declared
    "displayName" => Some(vtext(self.display_name))
    "handle" => Some(vtext(self.handle))
    "description" => Some(vtext(self.description))
    "avatar" => Some(vtext(self.avatar))
    "banner" => Some(vtext(self.banner))
    "followersCount" => Some(vnum(self.followers))
    "followsCount" => Some(vnum(self.follows))
    "postsCount" => Some(vnum(self.posts_count))
    "following" => Some(@values.Value::Boolean(self.following))
    "posts" => Some(vlist(self.posts.map(msg_value)))
    // derived
    "name" => Some(vtext(display_name_or(self.display_name, self.handle)))
    "handleText" => Some(vtext(at_handle(self.handle)))
    "initials" => Some(vtext(initials_of(self.display_name, self.handle)))
    "avatarPath" => Some(vtext(cdn_path(self.avatar)))
    "bannerPath" => Some(vtext(cdn_path(self.banner)))
    "followersLabel" =>
      Some(vtext(count_label(self.followers + bump(self.following))))
    "followsLabel" => Some(vtext(count_label(self.follows)))
    "postsLabel" => Some(vtext(count_label(self.posts_count)))
    "rows" => Some(vlist(self.children.map(t => @values.Value::Instance(t))))
    _ => None
  }
}

///|
impl DynComponent for Profile with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    // Same shape as a row's like: the flag moves, the follower count follows
    // it through `bump`, and the bubble is what a host would turn into the
    // `app.bsky.graph.follow` record it alone is allowed to write.
    (INPUT, "toggleFollow") => {
      @control.emit(if self.following { "unfollowed" } else { "followed" }, [
        vtext(self.handle),
      ])
      Changed({ ..self, following: !self.following } as &DynComponent)
    }
    // A row's like or repost is the ROW's, and it announces upward for whoever
    // can write the record. A feed has nothing to add to that — unlike a thread,
    // which still owns which rows a fold hides — so it does not handle them and
    // they keep bubbling.
    _ => Unhandled
  }
}

///|
impl DynComponent for Profile with fn call_method(self, name, _args) {
  match name {
    "summary" =>
      vtext(
        "\{display_name_or(self.display_name, self.handle)} \{at_handle(self.handle)} — \{count_label(self.followers + bump(self.following))} followers, \{count_label(self.posts_count)} posts",
      )
    "followLabel" => vtext(if self.following { "Following" } else { "Follow" })
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Profile with fn with_field(self, name, v) {
  match (name, v) {
    ("displayName", @values.Value::Text(s)) =>
      Some({ ..self, display_name: s } as &DynComponent)
    ("handle", @values.Value::Text(s)) =>
      Some({ ..self, handle: s } as &DynComponent)
    ("description", @values.Value::Text(s)) =>
      Some({ ..self, description: s } as &DynComponent)
    ("avatar", @values.Value::Text(s)) =>
      Some({ ..self, avatar: s } as &DynComponent)
    ("banner", @values.Value::Text(s)) =>
      Some({ ..self, banner: s } as &DynComponent)
    ("followersCount", @values.Value::Number(n)) =>
      Some({ ..self, followers: n.to_int() } as &DynComponent)
    ("followsCount", @values.Value::Number(n)) =>
      Some({ ..self, follows: n.to_int() } as &DynComponent)
    ("postsCount", @values.Value::Number(n)) =>
      Some({ ..self, posts_count: n.to_int() } as &DynComponent)
    ("following", @values.Value::Boolean(b)) =>
      Some({ ..self, following: b } as &DynComponent)
    ("posts", @values.Value::List(h)) =>
      Some(
        ({ ..self, posts: msgs_of(h) } : Profile).build_rows() as &DynComponent,
      )
    // A row returned a successor and the host is writing the whole list home.
    // A feed shows every row it has, so the positions map straight across.
    ("rows", _) =>
      match tokens_of(v) {
        Some(children) => {
          guard children.length() == self.children.length() else { None }
          Some({ ..self, children, } as &DynComponent)
        }
        None => None
      }
    _ => None
  }
}

///|
fn make_profile(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut display_name = ""
  let mut handle = ""
  let mut description = ""
  let mut avatar = ""
  let mut banner = ""
  let mut followers = 0
  let mut follows = 0
  let mut posts_count = 0
  let mut following = false
  let mut posts : Array[Msg] = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("displayName", @values.Value::Text(s)) => display_name = s
      ("handle", @values.Value::Text(s)) => handle = s
      ("description", @values.Value::Text(s)) => description = s
      ("avatar", @values.Value::Text(s)) => avatar = s
      ("banner", @values.Value::Text(s)) => banner = s
      ("followersCount", @values.Value::Number(n)) => followers = n.to_int()
      ("followsCount", @values.Value::Number(n)) => follows = n.to_int()
      ("postsCount", @values.Value::Number(n)) => posts_count = n.to_int()
      ("following", @values.Value::Boolean(b)) => following = b
      ("posts", @values.Value::List(h)) => posts = msgs_of(h)
      _ => ()
    }
  }
  (
    {
      display_name,
      handle,
      description,
      avatar,
      banner,
      followers,
      follows,
      posts_count,
      following,
      posts,
      children: [],
    } : Profile).build_rows()
  as &DynComponent
}

///|
/// None of the three persists: each one's state is exactly the fields it
/// declares (plus child tokens, which are the host's), so the host projects and
/// rebuilds them itself and a `persist` here would be that list written twice.
fn dyn_module() -> DynModule {
  module_def([
    dyn_comp("Post", make_post),
    dyn_comp("Thread", make_thread),
    dyn_comp("Profile", make_profile),
  ])
}
