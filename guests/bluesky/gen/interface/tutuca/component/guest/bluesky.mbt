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
/// A link somebody attached, as the AppView unfurled it.
///
/// The `uri` is where the poster pointed, so it is a target and never a link:
/// the same rule a link FACET follows, and for the same reason — no view can
/// name an origin the person who wrote the message chose. The thumbnail is a
/// different case, because the AppView re-hosts it: it arrives on the CDN this
/// bundle's views already name, so `cdn_path` decides it like any other picture.
priv struct Ext {
  uri : String
  title : String
  description : String
  /// The unfurled preview picture, as the full url the record carries.
  thumb : String
}

///|
/// The message a quote post is wrapped around.
///
/// Flat, and only what a quote card shows: a quote's OWN rich text would need a
/// loop inside a loop, which a static view cannot do (the sequence an `@each`
/// takes is a field path, not a loop binding). So the quoted text is drawn
/// plain, with its permalink under it for whoever wants the real thing.
priv struct Quote {
  uri : String
  display_name : String
  handle : String
  avatar : String
  text : String
  created_at : String
}

///|
/// An attached video. There is no player here — a playlist is an `.m3u8` fetch
/// this bundle has no way to make and no reason to be trusted with — so what a
/// video is, is its poster frame on the CDN and its alt text.
priv struct Vid {
  thumb : String
  alt : String
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
  /// Who put this message in front of this reader: the handle of the account
  /// that reposted it, `""` when nobody did.
  ///
  /// A feed item and a post are not the same record, and this is the field where
  /// that shows. Without it a stranger's post drawn in an account's feed reads as
  /// something that account wrote — the one wrong claim a reader cannot detect by
  /// looking harder. The author is NOT rewritten to say so: the message is still
  /// the message, and the attribution is a line above the card.
  reposted_by : String
  /// Whether the feed it came from had it pinned to the top.
  pinned : Bool
  /// Moderation label values on the record (`porn`, `graphic-media`, `!warn`, …),
  /// as the labellers set them.
  ///
  /// The one dropped field that is a safety question rather than a fidelity one:
  /// a labelled message drawn with no indicator is a labelled message this reader
  /// was not told about. Nothing here HIDES anything — that is the host's policy
  /// to make and it needs the reader's own preferences to make it — but a card
  /// that says which labels a record carries is a card that stopped being silent.
  labels : Array[String]
  /// An unfurled link, a quoted message and a video: the three embeds that were
  /// text-only before, and between them most of what gets posted.
  external : Ext?
  quote : Quote?
  video : Vid?
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
fn bool_at(m : UInt64, key : String) -> Bool {
  match @values.map_get(m, key) {
    Some(@values.Value::Boolean(b)) => b
    _ => false
  }
}

///|
/// A list of plain strings, which is what `labels` arrives as. A label that came
/// as `{ "val": … }` — the shape the wire uses — is read from there too, so a
/// host projecting the raw record does not have to flatten it first.
fn strs_of(items : Array[@values.Value]) -> Array[String] {
  let out : Array[String] = []
  for v in items {
    match v {
      @values.Value::Text(s) => if s != "" { out.push(s) }
      @values.Value::Map(m) => {
        let val = str_at(m, "val")
        if val != "" {
          out.push(val)
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// The nested record under `key`, or `None` when the field is absent or is not a
/// map. An embed that arrives as anything else is dropped rather than half-read.
fn map_at(m : UInt64, key : String) -> UInt64? {
  match @values.map_get(m, key) {
    Some(@values.Value::Map(h)) => Some(h)
    _ => None
  }
}

///|
/// An unfurled link. Dropped whole unless it points somewhere: a preview card
/// with no target is a box a reader cannot act on.
fn ext_of(m : UInt64) -> Ext? {
  guard map_at(m, "external") is Some(h) else { return None }
  let uri = str_at(h, "uri")
  guard uri != "" else { return None }
  Some({
    uri,
    title: str_at(h, "title"),
    description: str_at(h, "description"),
    thumb: str_at(h, "thumb"),
  })
}

///|
/// The quoted message. Kept when it has an author or something to say; a quote
/// of a record that was deleted or blocked arrives empty, and drawing an empty
/// card would say a message is there when it is not.
fn quote_of(m : UInt64) -> Quote? {
  guard map_at(m, "quote") is Some(h) else { return None }
  let handle = str_at(h, "handle")
  let display_name = str_at(h, "displayName")
  let text = str_at(h, "text")
  guard handle != "" || display_name != "" || text != "" else { return None }
  Some({
    uri: str_at(h, "uri"),
    display_name,
    handle,
    avatar: str_at(h, "avatar"),
    text,
    created_at: str_at(h, "createdAt"),
  })
}

///|
/// The video. A record with neither a poster frame nor alt text has nothing this
/// bundle can draw, so it is not a video as far as the card is concerned.
fn video_of(m : UInt64) -> Vid? {
  guard map_at(m, "video") is Some(h) else { return None }
  let thumb = str_at(h, "thumb")
  let alt = str_at(h, "alt")
  guard thumb != "" || alt != "" else { return None }
  Some({ thumb, alt })
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
    reposted_by: str_at(m, "repostedBy"),
    pinned: bool_at(m, "pinned"),
    labels: strs_of(items_at(m, "labels")),
    external: ext_of(m),
    quote: quote_of(m),
    video: video_of(m),
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
    ("repostedBy", vtext(m.reposted_by)),
    ("pinned", @values.Value::Boolean(m.pinned)),
    ("labels", labels_value(m.labels)),
    ("external", ext_value(m.external)),
    ("quote", quote_value(m.quote)),
    ("video", video_value(m.video)),
  ])
}

///|
fn labels_value(labels : Array[String]) -> @values.Value {
  vlist(labels.map(vtext))
}

///|
/// An embed back in the shape it arrived in. `Nil` for one that is not there,
/// which is what the host writes back when it projects the field: a record with
/// no video and a record whose video this bundle refused to read are the same
/// record as far as anything downstream is concerned.
fn ext_value(e : Ext?) -> @values.Value {
  match e {
    Some(e) =>
      vmap([
        ("uri", vtext(e.uri)),
        ("title", vtext(e.title)),
        ("description", vtext(e.description)),
        ("thumb", vtext(e.thumb)),
      ])
    None => @values.Value::Nil
  }
}

///|
fn quote_value(q : Quote?) -> @values.Value {
  match q {
    Some(q) =>
      vmap([
        ("uri", vtext(q.uri)),
        ("displayName", vtext(q.display_name)),
        ("handle", vtext(q.handle)),
        ("avatar", vtext(q.avatar)),
        ("text", vtext(q.text)),
        ("createdAt", vtext(q.created_at)),
      ])
    None => @values.Value::Nil
  }
}

///|
fn video_value(v : Vid?) -> @values.Value {
  match v {
    Some(v) => vmap([("thumb", vtext(v.thumb)), ("alt", vtext(v.alt))])
    None => @values.Value::Nil
  }
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
/// The same stamp with the clock taken off — "11 Aug 2026". What a join date is:
/// nobody has ever wanted the minute an account was created.
fn date_label(iso : String) -> String {
  let full = time_label(iso)
  let chars : Array[Char] = full.iter().collect()
  for i in 0..<chars.length() {
    if chars[i] == ',' {
      return slice(chars, 0, i)
    }
  }
  full
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
/// The host part of a url, without a `www.` nobody reads — what a link preview
/// says it will take you to.
///
/// This is a LABEL and not a check. Deciding whether a url may be followed is
/// `cdn_path`'s job and the view's, and neither of them ever sees this string:
/// an unfurled link is drawn as text with its full target in the tooltip, so the
/// worst a host written here can do is be read.
fn host_of(url : String) -> String {
  let rest = if url.has_prefix("https://") {
    url[8:].to_owned()
  } else if url.has_prefix("http://") {
    url[7:].to_owned()
  } else {
    url
  }
  let buf = StringBuilder::new()
  for c in rest.iter() {
    if c == '/' || c == '?' || c == '#' {
      break
    }
    buf.write_char(c)
  }
  let host = buf.to_string()
  if host.has_prefix("www.") {
    host[4:].to_owned()
  } else {
    host
  }
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
    "repostedBy" => Some(vtext(m.reposted_by))
    "pinned" => Some(@values.Value::Boolean(m.pinned))
    "labels" => Some(labels_value(m.labels))
    "external" => Some(ext_value(m.external))
    "quote" => Some(quote_value(m.quote))
    "video" => Some(video_value(m.video))
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
    // Why this message is in front of this reader, drawn ABOVE the card rather
    // than woven into it: the message is still the message, and the attribution
    // is a fact about the feed it arrived in.
    "hasAttribution" =>
      Some(@values.Value::Boolean(m.reposted_by != "" || m.pinned))
    "viaRepost" => Some(@values.Value::Boolean(m.reposted_by != ""))
    "repostLabel" =>
      Some(
        vtext(
          if m.reposted_by == "" {
            ""
          } else {
            "Reposted by @\{m.reposted_by}"
          },
        ),
      )
    "repostPath" =>
      Some(
        vtext(if m.reposted_by == "" { "" } else { "profile/\{m.reposted_by}" }),
      )
    // Every label the record carries, named. Nothing is hidden and nothing is
    // interpreted: which labels mean "blur this" depends on the reader's own
    // preferences and on which labellers they subscribe to, neither of which is
    // in this bundle's reach. Saying what is on the record is.
    "hasLabels" => Some(@values.Value::Boolean(!m.labels.is_empty()))
    "labelTitle" =>
      Some(
        vtext(
          if m.labels.is_empty() {
            ""
          } else {
            "labelled \{m.labels.join(", ")} by a moderation service"
          },
        ),
      )
    // The three embeds. Each is drawn only when the guest could read one, so a
    // record with an embed shape nobody here knows is a record with no embed —
    // the same state as a plain post, which already renders.
    "hasEmbed" =>
      Some(
        @values.Value::Boolean(
          m.external is Some(_) || m.quote is Some(_) || m.video is Some(_),
        ),
      )
    "hasExternal" => Some(@values.Value::Boolean(m.external is Some(_)))
    "externalTitle" => Some(vtext(ext_field(m.external, e => e.title)))
    "externalDescription" =>
      Some(vtext(ext_field(m.external, e => e.description)))
    // Where it points, as the tooltip and as the line under the title. Never an
    // href: the poster chose this origin, so no view can name it — the same
    // split a link facet makes.
    "externalTarget" => Some(vtext(ext_field(m.external, e => e.uri)))
    "externalHost" => Some(vtext(ext_field(m.external, e => host_of(e.uri))))
    // The preview picture is a different case, because the AppView re-hosts it:
    // it arrives on the CDN the view already names, so it is drawn like any
    // other picture and refused the same way.
    "externalThumbPath" =>
      Some(vtext(ext_field(m.external, e => cdn_path(e.thumb))))
    "hasQuote" => Some(@values.Value::Boolean(m.quote is Some(_)))
    "quoteName" =>
      Some(
        vtext(
          quote_field(m.quote, q => display_name_or(q.display_name, q.handle)),
        ),
      )
    "quoteHandleText" =>
      Some(vtext(quote_field(m.quote, q => at_handle(q.handle))))
    "quoteInitials" =>
      Some(
        vtext(quote_field(m.quote, q => initials_of(q.display_name, q.handle))),
      )
    "quoteAvatarPath" =>
      Some(vtext(quote_field(m.quote, q => cdn_path(q.avatar))))
    "quoteText" => Some(vtext(quote_field(m.quote, q => q.text)))
    "quoteTime" =>
      Some(vtext(quote_field(m.quote, q => time_label(q.created_at))))
    "quotePermalink" =>
      Some(vtext(quote_field(m.quote, q => permalink_of(q.uri, q.handle))))
    "quotePermalinkPath" =>
      Some(vtext(quote_field(m.quote, q => permalink_path_of(q.uri, q.handle))))
    "hasVideo" => Some(@values.Value::Boolean(m.video is Some(_)))
    "videoAlt" =>
      Some(
        vtext(
          match m.video {
            Some(v) => if v.alt == "" { "video" } else { v.alt }
            None => ""
          },
        ),
      )
    "videoThumbPath" =>
      Some(
        vtext(
          match m.video {
            Some(v) => cdn_path(v.thumb)
            None => ""
          },
        ),
      )
    _ => None
  }
}

///|
/// One string off an embed that may not be there. `""` for absent, which is the
/// state every view here already draws: the empty answer and the missing one
/// look the same on the page, and `hasExternal` is what decides whether the block
/// is there at all.
fn ext_field(e : Ext?, pick : (Ext) -> String) -> String {
  match e {
    Some(e) => pick(e)
    None => ""
  }
}

///|
fn quote_field(q : Quote?, pick : (Quote) -> String) -> String {
  match q {
    Some(q) => pick(q)
    None => ""
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
  guard bucket is RECEIVE else { return Unhandled }
  match name {
    // Optimistic, and announced: the flag is THIS row's — it returns its own
    // successor, and the host writes it home into whatever list holds it — while
    // the bubble is what a host would turn into the `app.bsky.feed.like` write.
    // The two are different jobs: one is what the screen shows, the other is
    // what somebody with a network connection should do about it. This bundle
    // has no network and is only saying what happened.
    "toggleLike" => {
      @control.intent(
        if self.liked {
          "unliked"
        } else {
          "liked"
        },
        [vtext(self.msg.uri)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, liked: !self.liked } as &DynComponent)
    }
    "toggleRepost" => {
      @control.intent(
        if self.reposted {
          "unreposted"
        } else {
          "reposted"
        },
        [vtext(self.msg.uri)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, reposted: !self.reposted } as &DynComponent)
    }
    // The fold flag is THIS row's too, and the bubble is what the thread above
    // hears: the row knows it is folded, and only the thread knows which rows
    // are UNDER it and therefore stop rendering. Both halves are needed, and
    // they are not the same fact.
    "toggleFold" => {
      guard self.foldable > 0 else { return Unchanged }
      @control.intent(
        if self.folded {
          "unfolded"
        } else {
          "folded"
        },
        [vtext(self.msg.uri)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
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
    ("repostedBy", @values.Value::Text(s)) =>
      Some({ ..self, msg: { ..m, reposted_by: s } } as &DynComponent)
    ("pinned", @values.Value::Boolean(b)) =>
      Some({ ..self, msg: { ..m, pinned: b } } as &DynComponent)
    ("labels", @values.Value::List(h)) =>
      Some(
        { ..self, msg: { ..m, labels: strs_of(list_items(h)) } }
        as &DynComponent,
      )
    // An embed is written whole or cleared whole. `Nil` is the clear, and it is
    // the value `get_field` hands back for a record that has none — so a host
    // that projects a plain post and writes it home leaves it plain. Anything
    // that is neither is refused rather than read as a clear: emptying a field
    // because a write could not be understood is the quiet kind of wrong.
    ("external", @values.Value::Map(_)) =>
      Some(
        { ..self, msg: { ..m, external: ext_of(wrapped("external", v)) } }
        as &DynComponent,
      )
    ("external", @values.Value::Nil) =>
      Some({ ..self, msg: { ..m, external: None } } as &DynComponent)
    ("quote", @values.Value::Map(_)) =>
      Some(
        { ..self, msg: { ..m, quote: quote_of(wrapped("quote", v)) } }
        as &DynComponent,
      )
    ("quote", @values.Value::Nil) =>
      Some({ ..self, msg: { ..m, quote: None } } as &DynComponent)
    ("video", @values.Value::Map(_)) =>
      Some(
        { ..self, msg: { ..m, video: video_of(wrapped("video", v)) } }
        as &DynComponent,
      )
    ("video", @values.Value::Nil) =>
      Some({ ..self, msg: { ..m, video: None } } as &DynComponent)
    _ => None
  }
}

///|
/// `v` under one key, as a map — the shape the `*_of` readers take.
fn wrapped(key : String, v : @values.Value) -> UInt64 {
  let h = @values.map_new()
  @values.map_set(h, key, v)
  h
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
    reposted_by: "",
    pinned: false,
    labels: [],
    external: None,
    quote: None,
    video: None,
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
      ("repostedBy", @values.Value::Text(s)) => msg = { ..msg, reposted_by: s }
      ("pinned", @values.Value::Boolean(b)) => msg = { ..msg, pinned: b }
      ("labels", @values.Value::List(h)) =>
        msg = { ..msg, labels: strs_of(list_items(h)) }
      ("external", @values.Value::Map(_)) =>
        msg = { ..msg, external: ext_of(wrapped("external", v)) }
      ("quote", @values.Value::Map(_)) =>
        msg = { ..msg, quote: quote_of(wrapped("quote", v)) }
      ("video", @values.Value::Map(_)) =>
        msg = { ..msg, video: video_of(wrapped("video", v)) }
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
    ("repostedBy", vtext(m.reposted_by)),
    ("pinned", @values.Value::Boolean(m.pinned)),
    ("labels", labels_value(m.labels)),
    ("external", ext_value(m.external)),
    ("quote", quote_value(m.quote)),
    ("video", video_value(m.video)),
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

// ── Scope: what the answer above it does NOT cover ───────────────────────────

///|
/// The disclosure that an answer is partial.
///
/// A card is a claim, and until this component existed the claim was always
/// "here is the feed" — never "here are the 25 the service handed over, out of a
/// number nobody counted, from an index that only holds recent public posts".
/// The prose beside a card has said that for releases; the card has not, so the
/// card was the more confident of the two while being the less informed.
///
/// It is deliberately not an error and not a warning. Nothing here is wrong: a
/// page is a page. What it turns a count into is a claim a reader can check,
/// which is the only thing that makes the two halves of a dual answer agree.
///
/// Its twin lives in the slack bundle, with the vocabulary that bundle needs
/// (public channels, private channels, DMs). This one carries what an ATProto
/// read can honestly say: whether a cap stopped it, whether there is another
/// page, and the sentences that name what an index does not hold.
priv struct Scope {
  /// A cap stopped this before the data ran out. The one field that matters
  /// most: it is the difference between "there is no more" and "I stopped".
  truncated : Bool
  /// What stopped it, in the caller's words: `"limit"`, `"depth"`.
  truncated_by : String
  /// There is another page, and nobody asked for it.
  more : Bool
  /// What this answer does not cover, one sentence each. Free text because the
  /// reasons are not a closed set — an index that only holds recent public
  /// posts and a filter the service applied are both true and neither is a
  /// boolean.
  notes : Array[String]
}

///|
impl DynComponent for Scope with fn get_field(self, name) {
  match name {
    "truncated" => Some(@values.Value::Boolean(self.truncated))
    "truncatedBy" => Some(vtext(self.truncated_by))
    "more" => Some(@values.Value::Boolean(self.more))
    "notes" => Some(vlist(self.notes.map(vtext)))
    // A scope with nothing to disclose draws nothing at all. That is not the
    // same as a scope that is absent, and both are correct: the difference only
    // matters to whoever built it.
    "hasAny" =>
      Some(
        @values.Value::Boolean(
          self.truncated || self.more || !self.notes.is_empty(),
        ),
      )
    "truncatedLabel" =>
      Some(
        vtext(
          if !self.truncated {
            ""
          } else if self.truncated_by == "" {
            "stopped early — this is not everything"
          } else {
            "stopped at the \{self.truncated_by} cap — this is not everything"
          },
        ),
      )
    "moreLabel" =>
      Some(vtext(if self.more { "more pages were not read" } else { "" }))
    _ => None
  }
}

///|
impl DynComponent for Scope with fn call_method(self, name, _args) {
  match name {
    "summary" => {
      let parts : Array[String] = []
      if self.truncated {
        parts.push(
          if self.truncated_by == "" {
            "stopped early"
          } else {
            "stopped at the \{self.truncated_by} cap"
          },
        )
      }
      if self.more {
        parts.push("more pages unread")
      }
      for n in self.notes {
        parts.push(n)
      }
      if parts.is_empty() {
        vtext("")
      } else {
        vtext("scope: \{parts.join("; ")}")
      }
    }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Scope with fn with_field(self, name, v) {
  match (name, v) {
    ("truncated", @values.Value::Boolean(b)) =>
      Some({ ..self, truncated: b } as &DynComponent)
    ("truncatedBy", @values.Value::Text(s)) =>
      Some({ ..self, truncated_by: s } as &DynComponent)
    ("more", @values.Value::Boolean(b)) =>
      Some({ ..self, more: b } as &DynComponent)
    ("notes", @values.Value::List(h)) =>
      Some({ ..self, notes: strs_of(list_items(h)) } as &DynComponent)
    _ => None
  }
}

///|
fn make_scope(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut truncated = false
  let mut truncated_by = ""
  let mut more = false
  let mut notes : Array[String] = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("truncated", @values.Value::Boolean(b)) => truncated = b
      ("truncatedBy", @values.Value::Text(s)) => truncated_by = s
      ("more", @values.Value::Boolean(b)) => more = b
      ("notes", @values.Value::List(h)) => notes = strs_of(list_items(h))
      _ => ()
    }
  }
  ({ truncated, truncated_by, more, notes } : Scope) as &DynComponent
}

///|
/// The `Scope` child a surface hangs under itself, from whatever its `scope`
/// field held.
///
/// One is always built, even for an answer with nothing to disclose. The keys of
/// the record ARE the component's field names, so a host that writes plain JSON
/// into `scope` gets the component it would have got by building one.
///
/// Whether it has anything to SAY comes back beside the token rather than out of
/// the child, and that is the contract talking rather than a shortcut: a token is
/// a bridge handle, and a parent holding one cannot read a field behind it. So
/// the surface decides whether to draw the box from the record it was handed,
/// and the child decides what goes in it.
fn scope_child(v : @values.Value?) -> (UInt64, Bool) {
  let args : Array[(String, @values.Value)] = []
  let mut any = false
  match v {
    Some(@values.Value::Map(h)) =>
      for k in @values.map_keys(h) {
        match @values.map_get(h, k) {
          Some(child) => {
            args.push((k, child))
            any = any ||
              (match (k, child) {
                ("truncated", @values.Value::Boolean(b)) => b
                ("more", @values.Value::Boolean(b)) => b
                ("notes", @values.Value::List(l)) => @values.list_len(l) > 0U
                _ => false
              })
          }
          None => ()
        }
      }
    _ => ()
  }
  (@control.make_instance("Scope", args), any)
}

// ── Paging: a window over a list that arrived long ───────────────────────────
//
// Three of the components below are a column of child `Post`s, and how long
// that column is was never theirs to decide: a caller asks a service for a
// timeline, a conversation or an account's messages, and what comes back is
// whatever a `limit` allowed. Forty rows is a card. Four hundred is a wall a
// reader scrolls past rather than reads, drawn out of four hundred child
// components before any one of them is looked at.
//
// So a long list gets a window and the four buttons that move it, in the
// vocabulary the `table` bundle already uses for the same job — `page`,
// `pageCount`, `pageSize`, `firstPage` / `prevPage` / `nextPage` / `lastPage`,
// `atFirst` / `atLast` — because a host drawing this card beside another's
// should not have to learn two spellings of "show me the next lot". Its twin
// lives in the mastodon bundle, for the same reason the `Scope` component has
// one: two networks, one thing a reader needs to be able to do.
//
// Nothing here rebuilds a row. A page is a claim about what is on screen rather
// than about what exists, so a like three pages back is still there when the
// reader comes back to it.

///|
/// How many rows a paged card shows at once when nobody asked for a number.
const PAGE_SIZE = 25

///|
/// How long a list has to BE before a reader is made to page through it.
///
/// The pager is not furniture that is always there: below this a card draws
/// exactly what it drew before it could page at all — no footer, every row on
/// screen — because breaking forty messages into two pages costs a reader a
/// click and buys them nothing. A host that wants the window anyway asks for a
/// `pageSize`, which is what asking for one means.
const PAGE_ABOVE = 100

///|
/// The state of one paged list, and every answer a view asks about it.
///
/// Computed per read rather than stored, because two of the three numbers in it
/// are not the component's to keep: `total` is what the folds left, which moves
/// as a reader collapses a branch, and `page` is a wish that has to be brought
/// back inside a list that may have shrunk under it.
priv struct Pager {
  /// 0-based, and already clamped to what `total` and the window allow.
  page : Int
  /// How many rows a page holds. In effect whether or not it is being used, so
  /// `pageSize` reads back the same either way.
  size : Int
  /// Whether the list is long enough that a page is a window rather than the
  /// whole of it.
  on : Bool
  /// How many rows there are to page through: after the folds, before the
  /// window.
  total : Int
}

///|
/// The pager for a list of `total` rows sitting at `page`, given the page size
/// the host asked for — 0 for "did not ask".
fn paging(page : Int, total : Int, page_size : Int) -> Pager {
  let size = if page_size > 0 { page_size } else { PAGE_SIZE }
  let on = if page_size > 0 { total > page_size } else { total > PAGE_ABOVE }
  let last = if on { (total + size - 1) / size - 1 } else { 0 }
  let page = if page < 0 { 0 } else if page > last { last } else { page }
  { page, size, on, total }
}

///|
/// How many pages there are. One when the whole list is on screen, so a card
/// that is not paging reads "1 of 1" rather than "1 of 0".
fn Pager::pages(self : Pager) -> Int {
  if self.on {
    (self.total + self.size - 1) / self.size
  } else {
    1
  }
}

///|
/// The positions this page shows, out of the ones the folds left.
fn Pager::slice(self : Pager, at : Array[Int]) -> Array[Int] {
  guard self.on else { return at }
  let start = self.page * self.size
  let stop = if start + self.size < at.length() {
    start + self.size
  } else {
    at.length()
  }
  let out : Array[Int] = []
  for i in start..<stop {
    out.push(at[i])
  }
  out
}

///|
/// Where one of the four buttons lands, or `None` for one that would not move —
/// which is what a view disables and what a handler answers `unchanged` to.
fn Pager::moved(self : Pager, name : String) -> Int? {
  let want = match name {
    "firstPage" => 0
    "prevPage" => self.page - 1
    "nextPage" => self.page + 1
    "lastPage" => self.pages() - 1
    _ => return None
  }
  let last = self.pages() - 1
  let next = if want < 0 { 0 } else if want > last { last } else { want }
  if next == self.page {
    None
  } else {
    Some(next)
  }
}

///|
/// Whether a name is one of the pager's four buttons. Asked before `moved`,
/// because `moved` answering `None` means "that button would not move", and a
/// name this component has never heard of has to keep travelling instead.
fn is_page_message(name : String) -> Bool {
  name == "firstPage" ||
  name == "prevPage" ||
  name == "nextPage" ||
  name == "lastPage"
}

///|
/// The fields a paged card answers on top of its own.
///
/// `page` is 1-based because it is a label rather than an index — the choice the
/// `table` bundle's pager made, and the one a reader would make.
fn Pager::field(self : Pager, name : String) -> @values.Value? {
  match name {
    "page" => Some(vnum(self.page + 1))
    "pageCount" => Some(vnum(self.pages()))
    "pageSize" => Some(vnum(self.size))
    _ => None
  }
}

///|
/// The methods a paged card answers.
///
/// `paged` is the one a view asks first: a card showing everything it has draws
/// no footer at all, so the whole control hangs off this rather than off a row
/// count a template would have to do arithmetic on.
fn Pager::answer(self : Pager, name : String) -> @values.Value? {
  match name {
    "paged" => Some(@values.Value::Boolean(self.on))
    "atFirst" => Some(@values.Value::Boolean(self.page <= 0))
    "atLast" => Some(@values.Value::Boolean(self.page >= self.pages() - 1))
    "pageLabel" => Some(vtext("\{self.page + 1} of \{self.pages()}"))
    // Which rows these are, which is the half a page number does not say.
    "rangeLabel" => {
      guard self.on else { return Some(vtext("")) }
      let first = self.page * self.size + 1
      let last = if first + self.size - 1 < self.total {
        first + self.size - 1
      } else {
        self.total
      }
      Some(vtext("\{first}–\{last} of \{self.total}"))
    }
    _ => None
  }
}

///|
/// Either the pager's answer or nothing, as a `call_method` has to answer.
fn Pager::answer_or_nil(self : Pager, name : String) -> @values.Value {
  match self.answer(name) {
    Some(v) => v
    None => @values.Value::Nil
  }
}

///|
/// Every position in a list of `n`, for the components that have no fold to
/// narrow one: a page is the only thing between their rows and the screen.
fn all_positions(n : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<n {
    out.push(i)
  }
  out
}

///|
/// The child tokens for a set of positions, as the value a view renders.
fn rows_value(children : Array[UInt64], at : Array[Int]) -> @values.Value {
  vlist(
    at
    .filter(i => i < children.length())
    .map(i => @values.Value::Instance(children[i])),
  )
}

///|
/// A list of successors the host is writing home, back into the child array at
/// the positions that were on screen. A length that does not match means the two
/// disagree about what is being shown, and guessing which position a token
/// belongs to is worse than refusing.
fn write_rows(
  children : Array[UInt64],
  at : Array[Int],
  v : @values.Value,
) -> Array[UInt64]? {
  guard tokens_of(v) is Some(shown) else { return None }
  let positions = at.filter(i => i < children.length())
  guard positions.length() == shown.length() else { return None }
  let next = children.copy()
  for k, i in positions {
    next[i] = shown[k]
  }
  Some(next)
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
  /// The `Scope` child: what this conversation does NOT show. A thread comes
  /// back capped by a depth the caller chose and by one the service chose, and
  /// the card said neither until this field existed.
  scope : UInt64
  /// Whether that child has anything to disclose, which is what the view gates
  /// the box on. Kept here because a token cannot be read back — see
  /// `scope_child`.
  has_scope : Bool
  /// Which page of the conversation is on screen, 0-based. A wish rather than a
  /// fact: folding a subtree takes rows away underneath it, so what it comes out
  /// as is whatever `paging` can honour.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
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
/// The pager over what the folds left.
fn Thread::pager(self : Thread) -> Pager {
  paging(self.page, self.visible().length(), self.page_size)
}

///|
/// The positions actually on screen: unfolded, and on this page. Every caller
/// that counts rendered positions goes through this one function, because a
/// write-back lands by position and a guess would land on the wrong message.
fn Thread::shown(self : Thread) -> Array[Int] {
  self.pager().slice(self.visible())
}

///|
impl DynComponent for Thread with fn get_field(self, name) {
  match name {
    // declared
    "posts" => Some(vlist(self.posts.map(msg_value)))
    "focus" => Some(vtext(self.focus))
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(@values.Value::Boolean(self.has_scope))
    // derived: the child components the view renders, minus the folded-away and
    // minus the pages a reader is not on
    "rows" => Some(rows_value(self.children, self.shown()))
    _ => self.pager().field(name)
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
  // The pager's four buttons are the only input of its own a thread has;
  // everything else that reaches it came up from a row. A page moves nothing
  // but which rows are drawn, so no row is rebuilt and nothing is announced —
  // there is nobody above who could act on "the reader turned a page".
  if bucket is RECEIVE && is_page_message(name) {
    return match self.pager().moved(name) {
      Some(page) => Changed({ ..self, page, } as &DynComponent)
      None => Unchanged
    }
  }
  guard bucket is INTENT else { return Unhandled }
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
    _ => self.pager().answer_or_nil(name)
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
        // The scope is the ANSWER's, not the list's: a host writing new messages
        // home is not making a new claim about what was covered, so the child it
        // was handed stays. Rebuilding one here would also strand the old token.
        scope: self.scope,
        has_scope: self.has_scope,
        // A new conversation starts at its beginning. Page four of the old one
        // is a position in a list that is no longer here.
        page: 0,
        page_size: self.page_size,
      }
      Some(next.build_rows() as &DynComponent)
    }
    ("focus", @values.Value::Text(s)) =>
      Some(({ ..self, focus: s } : Thread).build_rows() as &DynComponent)
    ("scope", @values.Value::Instance(t)) =>
      Some({ ..self, scope: t } as &DynComponent)
    // Asking for a page size is asking to be paged, so it starts at the first
    // page: the window a host just chose is not one this reader has been
    // anywhere in.
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 } as &DynComponent)
    // A row returned a successor and the host is writing the whole list home.
    // What it hands back is the list it was SHOWN — `shown()` — so it goes
    // home through the same function that decided those positions. A length that
    // does not match means the two disagree about what is on screen, and
    // guessing which position a token belongs to is worse than refusing.
    ("rows", _) =>
      match tokens_of(v) {
        Some(shown) => {
          let at = self.shown().filter(i => i < self.children.length())
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
  let mut page_size = 0
  let mut scope_arg : @values.Value? = None
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      // hot-swap migration hands the declared fields back as args
      ("posts", @values.Value::List(h)) => posts = msgs_of(h)
      ("focus", @values.Value::Text(s)) => focus = s
      ("pageSize", @values.Value::Number(n)) => page_size = n.to_int()
      ("scope", _) => scope_arg = Some(v)
      _ => ()
    }
  }
  let (scope, has_scope) = scope_child(scope_arg)
  (
    {
      posts,
      focus,
      children: [],
      collapsed: [],
      scope,
      has_scope,
      page: 0,
      page_size,
    } : Thread).build_rows()
  as &DynComponent
}

// ── Feed: a list of messages that is not a conversation ──────────────────────

///|
/// A feed: a timeline, an author's posts, a page of search results.
///
/// It exists because `Thread` was doing this job and `Thread` is a conversation.
/// Every message a feed carries arrives at depth 0 and nothing under it is a
/// reply to anything above it, so a thread rendering it drew the right rows for
/// the wrong reason — the rails and the fold button degraded to nothing, which
/// is not the same as meaning nothing. A reader looking at a card cannot tell
/// "these five messages happen to be flat" from "these five messages are a
/// conversation that happens to be flat", and only one of those is true.
///
/// So: same rows, same children, no reply vocabulary at all. A row here is a
/// `Post` at depth 0 with nothing foldable, and the only thing the feed adds is
/// the `Scope` under it — because a feed is a PAGE of something larger far more
/// often than a thread is.
///
/// Like `Profile`, it does not handle a row's `liked` / `reposted`: the row keeps
/// its own answer, and the bubble is for whoever above can write a record.
priv struct Feed {
  /// What this list IS — "@bsky.app — posts and replies", `search: "wasm"`.
  ///
  /// A feed is the one surface here that cannot say what it is from its own
  /// contents: a `Thread` is the conversation its focus is in and a `Profile` is
  /// the account it names, but three flat messages are three flat messages
  /// whether they came from a timeline, an author or a search. Whoever asked for
  /// them is the only one who knows, so they are the one who says. Empty for a
  /// list that would rather not, and the summary line stands on its own.
  title : String
  posts : Array[Msg]
  /// One child `Post` per message, in `posts` order. No filtering — a feed shows
  /// every row it has, so the only thing between its children and the screen is
  /// which page a reader is on.
  children : Array[UInt64]
  scope : UInt64
  has_scope : Bool
  /// Which page of the feed is on screen, 0-based.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  /// A feed is the surface most likely to need it: it is a PAGE of something
  /// larger far more often than a thread is, and the something is usually big.
  page_size : Int
}

///|
/// A message in a feed stands on its own: depth 0, nothing to fold, no focus.
/// The reason it is in front of this reader — a repost, a pin — travels with the
/// record and is drawn by the row.
fn Feed::make_row(self : Feed, i : Int) -> UInt64 {
  let m = self.posts[i]
  @control.make_instance(
    "Post",
    child_args({ ..m, depth: 0 }, focus=false, foldable=0),
  )
}

///|
fn Feed::build_rows(self : Feed) -> Feed {
  let children : Array[UInt64] = []
  for i in 0..<self.posts.length() {
    children.push(self.make_row(i))
  }
  { ..self, children, }
}

///|
/// The pager over the whole feed — there is no filter in front of it.
fn Feed::pager(self : Feed) -> Pager {
  paging(self.page, self.children.length(), self.page_size)
}

///|
/// The positions on this page.
fn Feed::shown(self : Feed) -> Array[Int] {
  self.pager().slice(all_positions(self.children.length()))
}

///|
impl DynComponent for Feed with fn get_field(self, name) {
  match name {
    "title" => Some(vtext(self.title))
    "hasTitle" => Some(@values.Value::Boolean(self.title != ""))
    "posts" => Some(vlist(self.posts.map(msg_value)))
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(@values.Value::Boolean(self.has_scope))
    "rows" => Some(rows_value(self.children, self.shown()))
    _ => self.pager().field(name)
  }
}

///|
/// A feed's only input of its own is the pager: everything else that reaches it
/// came up from a row, and a row's like is the row's.
impl DynComponent for Feed with fn handle(self, bucket, name, _args) {
  guard bucket is RECEIVE && is_page_message(name) else { return Unhandled }
  match self.pager().moved(name) {
    Some(page) => Changed({ ..self, page, } as &DynComponent)
    None => Unchanged
  }
}

///|
impl DynComponent for Feed with fn call_method(self, name, _args) {
  match name {
    "summary" => {
      let n = self.posts.length()
      let reposts = self.posts.iter().filter(m => m.reposted_by != "").count()
      if reposts == 0 {
        vtext(if n == 1 { "1 message" } else { "\{n} messages" })
      } else {
        vtext("\{n} messages · \{reposts} reposted in")
      }
    }
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for Feed with fn with_field(self, name, v) {
  match (name, v) {
    ("title", @values.Value::Text(s)) =>
      Some({ ..self, title: s } as &DynComponent)
    ("posts", @values.Value::List(h)) =>
      Some(
        ({ ..self, posts: msgs_of(h), page: 0 } : Feed).build_rows()
        as &DynComponent,
      )
    ("scope", @values.Value::Instance(t)) =>
      Some({ ..self, scope: t } as &DynComponent)
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 } as &DynComponent)
    // A row returned a successor and the host is writing the whole list home.
    // What it hands back is the page it was shown, so it goes home through the
    // same function that decided those positions.
    ("rows", _) =>
      match write_rows(self.children, self.shown(), v) {
        Some(children) => Some({ ..self, children, } as &DynComponent)
        None => None
      }
    _ => None
  }
}

///|
fn make_feed(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut title = ""
  let mut posts : Array[Msg] = []
  let mut page_size = 0
  let mut scope_arg : @values.Value? = None
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("title", @values.Value::Text(s)) => title = s
      ("posts", @values.Value::List(h)) => posts = msgs_of(h)
      ("pageSize", @values.Value::Number(n)) => page_size = n.to_int()
      ("scope", _) => scope_arg = Some(v)
      _ => ()
    }
  }
  let (scope, has_scope) = scope_child(scope_arg)
  ({ title, posts, children: [], scope, has_scope, page: 0, page_size } : Feed).build_rows()
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
  /// When the account was created, as an ISO 8601 stamp. Drawn as a date and not
  /// a duration, for the same reason a message's time is: "3 years ago" needs a
  /// clock, and `cap-clock` is a capability this bundle does without.
  created_at : String
  /// The at:// uri of the message this account pinned to its profile, `""` for
  /// none.
  ///
  /// The URI and not the message: `getProfiles` answers with a strong ref, so
  /// the content is one more request away and this bundle makes none. What a
  /// card can honestly offer is therefore the link — which is what the prose has
  /// been offering for as long as the prose has existed.
  pinned_post : String
  /// Which page of the account's messages is on screen, 0-based. An account with
  /// nothing else on the card can arrive carrying hundreds of them.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
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
/// The pager over the account's messages. There is no filter here, so the page
/// is the only thing between the rows and the screen.
fn Profile::pager(self : Profile) -> Pager {
  paging(self.page, self.children.length(), self.page_size)
}

///|
/// The positions on this page.
fn Profile::shown(self : Profile) -> Array[Int] {
  self.pager().slice(all_positions(self.children.length()))
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
    "createdAt" => Some(vtext(self.created_at))
    "pinnedPost" => Some(vtext(self.pinned_post))
    // derived
    "joinedLabel" =>
      Some(
        vtext(
          if self.created_at == "" {
            ""
          } else {
            "Joined \{date_label(self.created_at)}"
          },
        ),
      )
    "hasJoined" => Some(@values.Value::Boolean(self.created_at != ""))
    "pinnedPath" =>
      Some(vtext(permalink_path_of(self.pinned_post, self.handle)))
    "hasPinned" =>
      Some(
        @values.Value::Boolean(
          permalink_path_of(self.pinned_post, self.handle) != "",
        ),
      )
    "name" => Some(vtext(display_name_or(self.display_name, self.handle)))
    "handleText" => Some(vtext(at_handle(self.handle)))
    "initials" => Some(vtext(initials_of(self.display_name, self.handle)))
    "avatarPath" => Some(vtext(cdn_path(self.avatar)))
    "bannerPath" => Some(vtext(cdn_path(self.banner)))
    "followersLabel" =>
      Some(vtext(count_label(self.followers + bump(self.following))))
    "followsLabel" => Some(vtext(count_label(self.follows)))
    "postsLabel" => Some(vtext(count_label(self.posts_count)))
    "rows" => Some(rows_value(self.children, self.shown()))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for Profile with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    // Same shape as a row's like: the flag moves, the follower count follows
    // it through `bump`, and the bubble is what a host would turn into the
    // `app.bsky.graph.follow` record it alone is allowed to write.
    (RECEIVE, "toggleFollow") => {
      @control.intent(
        if self.following {
          "unfollowed"
        } else {
          "followed"
        },
        [vtext(self.handle)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, following: !self.following } as &DynComponent)
    }
    // The pager under the account's messages.
    (RECEIVE, _) => {
      guard is_page_message(name) else { return Unhandled }
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
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
    _ => self.pager().answer_or_nil(name)
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
    ("createdAt", @values.Value::Text(s)) =>
      Some({ ..self, created_at: s } as &DynComponent)
    ("pinnedPost", @values.Value::Text(s)) =>
      Some({ ..self, pinned_post: s } as &DynComponent)
    ("posts", @values.Value::List(h)) =>
      Some(
        ({ ..self, posts: msgs_of(h), page: 0 } : Profile).build_rows()
        as &DynComponent,
      )
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 } as &DynComponent)
    // A row returned a successor and the host is writing the whole list home.
    // What it hands back is the page it was shown, so it goes home through the
    // same function that decided those positions.
    ("rows", _) =>
      match write_rows(self.children, self.shown(), v) {
        Some(children) => Some({ ..self, children, } as &DynComponent)
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
  let mut created_at = ""
  let mut pinned_post = ""
  let mut page_size = 0
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("createdAt", @values.Value::Text(s)) => created_at = s
      ("pinnedPost", @values.Value::Text(s)) => pinned_post = s
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
      ("pageSize", @values.Value::Number(n)) => page_size = n.to_int()
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
      created_at,
      pinned_post,
      page: 0,
      page_size,
    } : Profile).build_rows()
  as &DynComponent
}

///|
/// None of the five persists: each one's state is exactly the fields it declares
/// (plus child tokens, which are the host's), so the host projects and rebuilds
/// them itself and a `persist` here would be that list written twice.
///
/// Smallest first, the way they nest: a `Scope` says what an answer left out, a
/// `Post` is one message, and the three surfaces above them are the three shapes
/// a bluesky read comes back in — a list (`Feed`), a conversation (`Thread`) and
/// an account (`Profile`).
fn dyn_module() -> DynModule {
  module_def([
    dyn_comp("Scope", make_scope),
    dyn_comp("Post", make_post),
    dyn_comp("Feed", make_feed),
    dyn_comp("Thread", make_thread),
    dyn_comp("Profile", make_profile),
  ])
}
