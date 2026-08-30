///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The mastodon guest module: five components that DISPLAY fediverse content —
/// one post (`Status`), its poll (`Poll`), a conversation (`Thread`), a feed
/// (`Timeline`) and an account (`Profile`). Styled after mastodon.social's own
/// reader: the rounded-square avatar, the name over the `@acct@server` handle,
/// the visibility glyph beside the stamp, and the reply / boost / favourite row.
///
/// It is the sibling of `guests/bluesky`, which reads the other big open social
/// network, and the three places they differ are the three things worth reading
/// this file for:
///
///   1. **The rich text is FOUND, not given.** ATProto hands a reader facets —
///      byte ranges with a kind — so `guests/bluesky` only has to cut on them.
///      Mastodon hands a reader `content`, which is HTML, and an untrusted
///      bundle may not emit markup at any tier. So this guest takes the PLAIN
///      text and scans it for `#tag`, `@mention` and `https://…` itself
///      (`segments_of`) — and then asks the record whether each one is real:
///      a `#` run links only when the status's own `tags` name it, an `@` run
///      only when its `mentions` do. The server is what knows whether
///      `@bob@example.test` is an account or somebody's email address, and this
///      bundle is not going to guess on its behalf.
///   2. **Federation is why one picture origin is enough.** A status in a
///      federated timeline comes from any server there is, so no view could
///      name the origins its avatars live on — except that an instance PROXIES
///      what it federates: a remote account's avatar is served from
///      `files.mastodon.social/cache/…`, the same host as a local one. So this
///      bundle's views reach exactly two
///      origins, both literals in the views: `files.mastodon.social` for every
///      picture, `mastodon.social` for every link.
///
///      The one thing that does NOT proxy is a remote status's permalink, which
///      belongs to the server that holds it. So a local status gets a
///      `mastodon.social` link and a remote one stays selectable text with its
///      url in the tooltip — the same split `guests/bluesky` makes between a
///      hashtag (an origin the view names) and a link somebody posted (an origin
///      the poster chose).
///   3. **A poll bar is an element, not a stylesheet.** Untrusted views have no
///      `style` attribute, so a share cannot be a width. Rather than draw a bar
///      out of N spacer elements (which `guests/bluesky` does for a reply
///      indent, because there is no element that means "indent"), the poll uses
///      the element the platform already has: `<progress :value max="100">`.
///      `value` is not a network or CSS sink, so nothing had to be reopened for
///      it.
///
/// No clock, for the reason `guests/bluesky` gives at length: the world has
/// none, and what a clock buys is "4h" instead of a date the record
/// already carries. The stamp is formatted from `createdAt`.
///
/// Its static declaration and views live beside the module; sdk.mbt does the ABI.

// ── the shape all five components are made of ────────────────────────────────

///|
/// One attachment: what it says it is, and where its picture lives.
///
/// `preview` is the small one Mastodon shows in a timeline and `url` the full
/// one behind it; both arrive as the urls the API hands out, and `media_path`
/// is what decides whether either can be drawn.
priv struct Media {
  description : String
  preview : String
  url : String
  /// "image" | "gifv" | "video" | "audio" | "unknown" — what the record says it
  /// is. Only a picture is drawn; anything else is its description on a chip.
  kind : String
}

///|
/// One poll option, as the record carries it.
priv struct PollOpt {
  title : String
  votes : Int
}

///|
/// A poll. Empty `options` is the whole "there is no poll here" marker, which is
/// what a status without one carries.
priv struct PollData {
  options : Array[PollOpt]
  /// Votes cast, and people who cast them — a multiple-choice poll has more of
  /// the first than the second.
  votes : Int
  voters : Int
  expires_at : String
  expired : Bool
  multiple : Bool
  /// Whether this reader had already voted when the record arrived.
  voted : Bool
  /// Which options they picked, by index.
  own_votes : Array[Int]
}

///|
/// One post. `Status` holds one of these, `Thread` a flattened reply tree and
/// `Timeline` / `Profile` a feed of them, so the projection helpers below are
/// written once and used by all four.
priv struct Toot {
  id : String
  /// The status's canonical url, as the record carries it. For a LOCAL status
  /// this bundle rebuilds the link from `acct` and `id` under the origin the
  /// view names; for a remote one this is all there is, and it stays text.
  url : String
  /// The full fediverse handle: `alice` on this server, `alice@other.test` from
  /// anywhere else. It is the key to everything — the profile link, the
  /// permalink, and whether either of them is local.
  acct : String
  display_name : String
  avatar : String
  /// What the post says, as PLAIN text. Mastodon's `content` is HTML and an
  /// untrusted bundle cannot emit markup, so what crosses this boundary is the
  /// text and the two lists that say which of its runs are real.
  content : String
  /// The content warning. Non-empty hides the body behind it.
  spoiler : String
  created_at : String
  /// "public" | "unlisted" | "private" | "direct".
  visibility : String
  /// The hashtags the SERVER resolved, without their `#`. A `#run` in the text
  /// that is not here is not a link.
  tags : Array[String]
  /// The accounts the server resolved, as full `acct`s. Same rule.
  mentions : Array[String]
  media : Array[Media]
  poll : PollData
  replies : Int
  reblogs : Int
  favourites : Int
  /// Who boosted this into the timeline it is being read in; "" when nobody did.
  boosted_by : String
  pinned : Bool
  edited : Bool
  /// Reply depth in a thread; 0 for a post standing on its own.
  depth : Int
}

///|
/// One profile metadata row: the four labelled links Mastodon lets an account
/// put under its bio, and the green check that says the link pointed back.
priv struct ProfileField {
  name : String
  value : String
  verified : Bool
}

///|
/// The one origin this bundle's pictures come from, with the `/` that ends it.
///
/// A CONFIG VARIABLE rather than a constant, which is what makes one build of
/// this bundle a reader for any instance there is. The host binds it, the host
/// normalizes it through the closing `/`, and the same string is what the views
/// name as `$$mediaOrigin` — so the two halves of the external-URL rule cannot
/// drift apart, because there is only one of them now.
///
/// The trailing slash is the whole check rather than a tidiness: without it
/// `https://files.mastodon.social.attacker.test/x` and
/// `https://files.mastodon.social@attacker.test/x` both pass a prefix test, and
/// both are somebody else's host. It is the same boundary the host insists on
/// when it reads the origin off the view (`dyncomp/policy/external_url.mbt`),
/// and `@policy.normalized_origin` is where it is put there.
///
/// One origin covers a FEDERATED timeline because an instance proxies what it
/// federates: a remote account's avatar and a remote status's attachment are
/// both re-served from this host, under `/cache/`.
fn media() -> String {
  @config.get("mediaOrigin")
}

///|
/// The server whose reader this is. Every link a view offers is a path under it:
/// a profile (`@acct`), a hashtag (`tags/name`), a local permalink. A remote
/// account still has one, because this server renders remote profiles at its own
/// address — `mastodon.social/@alice@other.test` is a page.
///
/// A `text` variable, not an `origin`, and the difference is enforced rather
/// than documented: this is the server's name as a person WRITES it, and every
/// use of it below is prose — a handle, a tooltip, the visible text under a
/// link. The href beside that text gets its origin from `$$webOrigin` in the
/// view, and a text variable is one a view cannot name at all.
fn home() -> String {
  @config.get("instanceName")
}

///|
/// What is left of a url once the media host is taken off the front, or `""` for
/// a url anywhere else — including a relative one, which is a request to the
/// HOST's origin and not this bundle's to make.
///
/// This is the guest's half of the external-URL rule: the view names the origin,
/// this decides that the record's url is actually ON it, and what crosses
/// between them is a path. A picture that fails the test is not drawn at all,
/// and drawing nothing is a state the views already have — it is what a record
/// with no picture gets.
///
/// Now that both sides read the same configured string, "the origin the view
/// names" is literally the same value this compares against — which is what
/// makes pointing this bundle at another instance a matter of binding two
/// variables rather than editing two files that have to agree.
fn media_path(url : String) -> String {
  let media = media()
  guard url.has_prefix(media) else { return "" }
  url[media.length():].to_owned()
}

///|
/// Whether this account lives on the server this reader belongs to. A local
/// `acct` is a bare username; a federated one carries its server after an `@`.
///
/// It decides one thing only: whether a status has a permalink this bundle can
/// turn into a link. Profiles and hashtags are local pages either way.
fn is_local(acct : String) -> Bool {
  acct != "" && !acct.contains("@")
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
fn bool_at(m : UInt64, key : String) -> Bool {
  match @values.map_get(m, key) {
    Some(@values.Value::Boolean(b)) => b
    _ => false
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
/// A list of names — `tags` and `mentions`, which arrive either as bare strings
/// or as the objects the API hands out (`{ name }`, `{ acct }`). Both spellings
/// are read, because a record typed into a form is the first and a record
/// fetched from a server is the second.
fn names_of(items : Array[@values.Value], key : String) -> Array[String] {
  let out : Array[String] = []
  for v in items {
    match v {
      @values.Value::Text(s) => if s != "" { out.push(s) }
      @values.Value::Map(m) => {
        let name = str_at(m, key)
        if name != "" {
          out.push(name)
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// The attachments. A bare string is a description and no picture, which is
/// every attachment before this bundle could load one.
fn media_of(items : Array[@values.Value]) -> Array[Media] {
  let out : Array[Media] = []
  for v in items {
    match v {
      @values.Value::Text(s) =>
        out.push({ description: s, preview: "", url: "", kind: "image", })
      @values.Value::Map(m) =>
        out.push({
          description: str_at(m, "description"),
          preview: str_at(m, "previewUrl"),
          url: str_at(m, "url"),
          kind: match str_at(m, "type") {
            "" => "image"
            k => k
          },
        })
      _ => ()
    }
  }
  out
}

///|
fn poll_of(v : @values.Value?) -> PollData {
  let empty : PollData = {
    options: [],
    votes: 0,
    voters: 0,
    expires_at: "",
    expired: false,
    multiple: false,
    voted: false,
    own_votes: [],
  }
  guard v is Some(@values.Value::Map(m)) else { return empty }
  {
    options: poll_options_of(items_at(m, "options")),
    votes: int_at(m, "votesCount"),
    voters: int_at(m, "votersCount"),
    expires_at: str_at(m, "expiresAt"),
    expired: bool_at(m, "expired"),
    multiple: bool_at(m, "multiple"),
    voted: bool_at(m, "voted"),
    own_votes: ints_of(items_at(m, "ownVotes")),
  }
}

///|
fn poll_options_of(items : Array[@values.Value]) -> Array[PollOpt] {
  let out : Array[PollOpt] = []
  for v in items {
    match v {
      @values.Value::Text(s) => out.push({ title: s, votes: 0, })
      @values.Value::Map(m) =>
        out.push({ title: str_at(m, "title"), votes: int_at(m, "votesCount"), })
      _ => ()
    }
  }
  out
}

///|
fn ints_of(items : Array[@values.Value]) -> Array[Int] {
  let out : Array[Int] = []
  for v in items {
    match v {
      @values.Value::Number(n) => out.push(n.to_int())
      _ => ()
    }
  }
  out
}

///|
fn fields_of(items : Array[@values.Value]) -> Array[ProfileField] {
  let out : Array[ProfileField] = []
  for v in items {
    guard v is @values.Value::Map(m) else { continue }
    out.push({
      name: str_at(m, "name"),
      value: str_at(m, "value"),
      verified: bool_at(m, "verified"),
    })
  }
  out
}

///|
/// One post out of the map a declared list field arrives as. Every key is
/// optional: a record the host built from a form, or from JSON somebody typed,
/// is missing most of them and still has to render.
fn toot_of(m : UInt64) -> Toot {
  {
    id: str_at(m, "id"),
    url: str_at(m, "url"),
    acct: str_at(m, "acct"),
    display_name: str_at(m, "displayName"),
    avatar: str_at(m, "avatar"),
    content: str_at(m, "content"),
    spoiler: str_at(m, "spoilerText"),
    created_at: str_at(m, "createdAt"),
    visibility: str_at(m, "visibility"),
    tags: names_of(items_at(m, "tags"), "name"),
    mentions: names_of(items_at(m, "mentions"), "acct"),
    media: media_of(items_at(m, "media")),
    poll: poll_of(@values.map_get(m, "poll")),
    replies: int_at(m, "repliesCount"),
    reblogs: int_at(m, "reblogsCount"),
    favourites: int_at(m, "favouritesCount"),
    boosted_by: str_at(m, "boostedBy"),
    pinned: bool_at(m, "pinned"),
    edited: bool_at(m, "edited"),
    depth: int_at(m, "depth"),
  }
}

///|
fn toots_of(h : UInt64) -> Array[Toot] {
  let out : Array[Toot] = []
  for v in list_items(h) {
    match v {
      @values.Value::Map(m) => out.push(toot_of(m))
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
fn vbool(b : Bool) -> @values.Value {
  @values.Value::Boolean(b)
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
fn names_value(names : Array[String]) -> @values.Value {
  vlist(names.map(vtext))
}

///|
fn media_value(media : Array[Media]) -> @values.Value {
  vlist(
    media.map(a => {
      vmap([
        ("description", vtext(a.description)),
        ("previewUrl", vtext(a.preview)),
        ("url", vtext(a.url)),
        ("type", vtext(a.kind)),
      ])
    }),
  )
}

///|
/// The attachments as a VIEW reads them: the description, and the path the
/// preview is at on the host the view names — empty for a record that carries
/// none, or one whose picture is somewhere this bundle cannot reach.
fn media_items_value(media : Array[Media]) -> @values.Value {
  vlist(
    media.map(a => {
      vmap([
        ("description", vtext(a.description)),
        ("path", vtext(media_path(a.preview))),
        ("fullPath", vtext(media_path(a.url))),
        ("type", vtext(a.kind)),
        // Mastodon puts an ALT chip on a picture that came with a description and
        // nothing on one that did not, which is a nudge at whoever posted it
        ("described", vbool(a.description != "")),
      ])
    }),
  )
}

///|
fn poll_options_value(options : Array[PollOpt]) -> @values.Value {
  vlist(
    options.map(o => {
      vmap([("title", vtext(o.title)), ("votesCount", vnum(o.votes))])
    }),
  )
}

///|
fn poll_value(p : PollData) -> @values.Value {
  vmap([
    ("options", poll_options_value(p.options)),
    ("votesCount", vnum(p.votes)),
    ("votersCount", vnum(p.voters)),
    ("expiresAt", vtext(p.expires_at)),
    ("expired", vbool(p.expired)),
    ("multiple", vbool(p.multiple)),
    ("voted", vbool(p.voted)),
    ("ownVotes", vlist(p.own_votes.map(vnum))),
  ])
}

///|
/// A post back in the shape it arrived in — what the host reads when it projects
/// a declared list field to JSON, and what it hands back on a hot-swap
/// migration. The inverse of `toot_of`.
fn toot_value(t : Toot) -> @values.Value {
  vmap([
    ("id", vtext(t.id)),
    ("url", vtext(t.url)),
    ("acct", vtext(t.acct)),
    ("displayName", vtext(t.display_name)),
    ("avatar", vtext(t.avatar)),
    ("content", vtext(t.content)),
    ("spoilerText", vtext(t.spoiler)),
    ("createdAt", vtext(t.created_at)),
    ("visibility", vtext(t.visibility)),
    ("tags", names_value(t.tags)),
    ("mentions", names_value(t.mentions)),
    ("media", media_value(t.media)),
    ("poll", poll_value(t.poll)),
    ("repliesCount", vnum(t.replies)),
    ("reblogsCount", vnum(t.reblogs)),
    ("favouritesCount", vnum(t.favourites)),
    ("boostedBy", vtext(t.boosted_by)),
    ("pinned", vbool(t.pinned)),
    ("edited", vbool(t.edited)),
    ("depth", vnum(t.depth)),
  ])
}

// ── rich text: found in the text, then checked against the record ────────────

///|
/// One run of the post: plain, or something the record confirmed is an entity.
priv struct Seg {
  /// What the run says. For a link this is the SHORTENED url — Mastodon drops
  /// the scheme and cuts the tail, and marks up the pieces it hid; a bundle that
  /// cannot emit markup does the cut and keeps the whole url in `target`.
  text : String
  /// Where the run points, as text — the run's tooltip either way, and all a run
  /// that cannot navigate has.
  target : String
  /// The `mastodon.social` PATH this run points at, for the two kinds whose
  /// target is on this server: a mention and a hashtag. `""` for a link, whose
  /// origin is whatever the person who posted it typed, so the view has no
  /// literal to pin it to.
  path : String
  /// "text" | "link" | "mention" | "tag"
  kind : String
}

///|
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// What may follow the `@` of a fediverse handle: a word character, or the `.`
/// and `-` a domain is made of.
fn is_acct_char(c : Char) -> Bool {
  is_word_char(c) || c == '.' || c == '-'
}

///|
fn slice(chars : Array[Char], from : Int, to : Int) -> String {
  let buf = StringBuilder()
  for i in from..<to {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// ASCII lower-case, which is all a tag comparison needs: Mastodon keys a
/// hashtag on its lower-cased name and shows whatever case it was typed in.
fn lower(s : String) -> String {
  s.to_lower()
}

///|
/// Whether the record confirms this `#run` is a hashtag. Case-insensitive,
/// because `#Fediverse` in the text is `fediverse` in `tags`.
fn tag_named(tags : Array[String], name : String) -> Bool {
  let want = lower(name)
  tags.iter().any(t => lower(t) == want)
}

///|
/// The full `acct` the record has for this `@run`, or `""` when it has none.
///
/// A local mention is typed `@alice` and carried as `alice`; a remote one is
/// typed `@alice@other.test` and carried the same way. Both spellings are
/// matched against the carried form, and the CARRIED one is what the link uses:
/// `mastodon.social/@alice@other.test` is a page here, `@alice` alone would be
/// somebody else.
fn mention_acct(mentions : Array[String], typed : String) -> String {
  let want = lower(typed)
  for m in mentions {
    let full = lower(m)
    if full == want {
      return m
    }
    // `@alice` in the text, `alice@other.test` in the record: the server
    // resolved a bare handle it knew, which is what it does inside a thread.
    if full.has_prefix(want + "@") {
      return m
    }
  }
  ""
}

///|
/// A url with the parts Mastodon hides taken off: the scheme, and the `/` that
/// ends a bare host. It is what a reader sees of an ADDRESS — a permalink, a
/// profile's link row — where the whole thing is the point.
fn bare_url(url : String) -> String {
  let bare = if url.has_prefix("https://") {
    url["https://".length():].to_owned()
  } else if url.has_prefix("http://") {
    url["http://".length():].to_owned()
  } else {
    url
  }
  if bare.has_suffix("/") {
    bare[0:bare.length() - 1].to_owned()
  } else {
    bare
  }
}

///|
/// A url as Mastodon shows one INSIDE a post: bare, and cut at 30 characters
/// with the ellipsis it uses — which is exactly what the `invisible` /
/// `ellipsis` spans in its own HTML do. The whole url stays in the segment's
/// `target`, which is the tooltip and the only thing a reader can copy: this
/// bundle cannot make it a link, since the origin belongs to whoever posted it.
///
/// It is deliberately not what an ADDRESS gets. A permalink cut short is a
/// permalink nobody can read back, and reading it back is all a reader has when
/// the link cannot be one.
fn pretty_url(url : String) -> String {
  let bare = bare_url(url)
  let chars : Array[Char] = bare.iter().collect()
  if chars.length() <= 30 {
    bare
  } else {
    slice(chars, 0, 30) + "…"
  }
}

///|
/// Where a url run ends: at whitespace, minus the punctuation that was the
/// sentence's rather than the url's. A `)` is only sentence punctuation when the
/// url has no `(` of its own, which is what keeps a wikipedia link whole.
fn url_end(chars : Array[Char], from : Int) -> Int {
  let mut to = from
  let mut opened = false
  while to < chars.length() {
    let c = chars[to]
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '"' || c == '<' {
      break
    }
    if c == '(' {
      opened = true
    }
    to = to + 1
  }
  while to > from {
    let c = chars[to - 1]
    let trailing = c == '.' ||
      c == ',' ||
      c == ';' ||
      c == ':' ||
      c == '!' ||
      c == '?' ||
      c == '\'' ||
      (c == ')' && !opened)
    if trailing {
      to = to - 1
    } else {
      break
    }
  }
  to
}

///|
/// Cut the post into a flat run of typed segments the view iterates. Pure, and
/// the one piece of real work in this bundle.
///
/// Mastodon's own `content` is HTML with the entities already marked up, and an
/// untrusted bundle may not emit markup — so this finds them in the plain text
/// instead, and then refuses to link anything the RECORD does not confirm. That
/// second half is the part worth keeping: a `#` run and an `@` run are shapes
/// anybody can type, and only the server knows which of them resolved.
fn segments_of(
  text : String,
  tags : Array[String],
  mentions : Array[String],
) -> Array[Seg] {
  let chars : Array[Char] = text.iter().collect()
  let segs : Array[Seg] = []
  let mut cursor = 0
  let mut i = 0
  fn flush(upto : Int) -> Unit {
    if upto > cursor {
      segs.push({
        text: slice(chars, cursor, upto),
        target: "",
        path: "",
        kind: "text",
      })
    }
  }

  fn at_boundary(at : Int) -> Bool {
    at == 0 || !is_word_char(chars[at - 1])
  }

  while i < chars.length() {
    let c = chars[i]
    if c == '#' && at_boundary(i) {
      let mut to = i + 1
      while to < chars.length() && is_word_char(chars[to]) {
        to = to + 1
      }
      let name = slice(chars, i + 1, to)
      if name != "" && tag_named(tags, name) {
        flush(i)
        segs.push({
          text: slice(chars, i, to),
          target: "\{home()}/tags/\{lower(name)}",
          path: "tags/\{lower(name)}",
          kind: "tag",
        })
        cursor = to
        i = to
        continue
      }
    } else if c == '@' && at_boundary(i) {
      let mut to = i + 1
      while to < chars.length() && is_acct_char(chars[to]) {
        to = to + 1
      }
      // a handle does not end on the `.` of the sentence it is in
      while to > i + 1 && (chars[to - 1] == '.' || chars[to - 1] == '-') {
        to = to - 1
      }
      let typed = slice(chars, i + 1, to)
      let acct = mention_acct(mentions, typed)
      if acct != "" {
        flush(i)
        segs.push({
          text: slice(chars, i, to),
          target: "\{home()}/@\{acct}",
          path: "@\{acct}",
          kind: "mention",
        })
        cursor = to
        i = to
        continue
      }
    } else if (c == 'h' || c == 'H') && at_boundary(i) {
      let rest = slice(chars, i, chars.length())
      let scheme = if lower(rest).has_prefix("https://") {
        8
      } else if lower(rest).has_prefix("http://") {
        7
      } else {
        0
      }
      if scheme > 0 {
        let to = url_end(chars, i + scheme)
        if to > i + scheme {
          let url = slice(chars, i, to)
          flush(i)
          segs.push({
            text: pretty_url(url),
            target: url,
            path: "",
            kind: "link",
          })
          cursor = to
          i = to
          continue
        }
      }
    }
    i = i + 1
  }
  flush(chars.length())
  segs
}

///|
/// The runs as a view reads them. `external` is the third state the two booleans
/// a view can ask for do not cover on their own: a run that points somewhere and
/// cannot be followed, which is a link somebody posted.
fn segments_value(t : Toot) -> @values.Value {
  vlist(
    segments_of(t.content, t.tags, t.mentions).map(s => {
      vmap([
        ("text", vtext(s.text)),
        ("target", vtext(s.target)),
        ("path", vtext(s.path)),
        ("external", vbool(s.target != "" && s.path == "")),
        ("kind", vtext(s.kind)),
      ])
    }),
  )
}

// ── the small formatting jobs a display component is made of ─────────────────

///|
/// What to call the author: the display name, else the handle, else the one
/// honest answer left.
fn display_name_or(display_name : String, acct : String) -> String {
  if display_name != "" {
    display_name
  } else if acct != "" {
    acct
  } else {
    "unknown"
  }
}

///|
/// The handle as the page writes it: always `@user@server`, because a fediverse
/// handle without its server is only half an address. A local account's server
/// is this one, and the record does not bother to say so.
fn full_handle(acct : String) -> String {
  if acct == "" {
    ""
  } else if acct.contains("@") {
    "@\{acct}"
  } else {
    "@\{acct}@\{home()}"
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
/// initials off the display name, or off the handle's first two parts.
fn initials_of(display_name : String, acct : String) -> String {
  let source = if display_name != "" { display_name } else { acct }
  let buf = StringBuilder()
  let mut taken = 0
  let mut fresh = true
  for c in source.iter() {
    if c == ' ' || c == '.' || c == '-' || c == '_' || c == '@' {
      fresh = true
      continue
    }
    if fresh && taken < 2 && is_word_char(c) {
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
/// An ISO 8601 stamp as something a person reads — "13 Aug 2026, 16:02".
///
/// No clock is involved, which is the point: mastodon.social writes "4h" beside
/// a post, and "4h" needs a clock — an ambient fact for a nicer
/// phrasing of something the record already says. A stamp this bundle cannot
/// parse is shown verbatim rather than blanked.
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
/// The year out of an ISO stamp — what a profile's "Joined" column shows.
fn year_label(iso : String) -> String {
  let chars : Array[Char] = iso.iter().collect()
  guard chars.length() >= 4 && check_digits(chars, [0, 1, 2, 3]) else {
    return iso
  }
  slice(chars, 0, 4)
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
/// A count the way a social app writes one: 1234 is "1.2K", 877054 is "877K".
/// Kept in the guest rather than the view because it is arithmetic, and a view
/// that did it would be a view doing arithmetic.
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
/// The visibility glyph mastodon.social puts beside the stamp, and what it
/// means. An unknown value reads as public, which is what an unmarked status is.
fn visibility_glyph(visibility : String) -> String {
  match visibility {
    "unlisted" => "🔓"
    "private" => "🔒"
    "direct" => "✉"
    _ => "🌐"
  }
}

///|
fn visibility_label(visibility : String) -> String {
  match visibility {
    "unlisted" => "Unlisted"
    "private" => "Followers only"
    "direct" => "Mentioned people only"
    _ => "Public"
  }
}

///|
/// The `mastodon.social` PATH a LOCAL status is at — `@acct/id`, which the view
/// puts under its own literal origin.
///
/// `""` for a status from anywhere else, and that is federation rather than
/// caution: this server proxies a remote account's PICTURES, so one origin draws
/// the whole timeline, but a remote status is a page on the server that holds
/// it. Its url is in the record and stays text, exactly as a link somebody
/// posted does.
fn permalink_path_of(t : Toot) -> String {
  guard t.id != "" && is_local(t.acct) else { return "" }
  "@\{t.acct}/\{t.id}"
}

///|
/// The same permalink as the text a person reads and can select. For a local
/// status the origin is spelled out here because it is prose; the `href` beside
/// it gets the origin from the view. For a remote one this is the record's own
/// url — all there is, and not a link.
fn permalink_of(t : Toot) -> String {
  let path = permalink_path_of(t)
  if path != "" {
    "\{home()}/\{path}"
  } else if t.url != "" {
    bare_url(t.url)
  } else {
    ""
  }
}

// ── Poll: the one thing on a status that is not text ─────────────────────────

///|
/// A poll under a status.
///
/// It is a component of its own rather than three more fields on `Status`
/// because it owns a decision: which option this reader picked. A single-choice
/// vote un-picks the previous one and moves every share, so the answer belongs
/// to the poll and not to any option in it — the same reason `Thread` owns which
/// rows are folded away.
///
/// The share is drawn with `<progress :value max="100">`. An untrusted view has
/// no `style` attribute, so a bar cannot be a width — but `value` is neither a
/// network nor a CSS sink, so the element the platform already has needed
/// nothing reopened for it.
priv struct Poll {
  data : PollData
  /// The status this poll belongs to, so a vote can say what it voted on. A
  /// poll has no way to find that out for itself.
  status_id : String
}

///|
/// This reader's own vote on top of the count the record came with. The record
/// is what the server said; `own_votes` is what the person did since, and the
/// two are kept apart so a refused write does not have to un-edit a number.
fn Poll::extra(self : Poll, i : Int) -> Int {
  if self.data.own_votes.contains(i) {
    1
  } else {
    0
  }
}

///|
fn Poll::total(self : Poll) -> Int {
  self.data.votes + self.data.own_votes.length()
}

///|
fn Poll::votes_at(self : Poll, i : Int) -> Int {
  self.data.options[i].votes + self.extra(i)
}

///|
/// Results are shown once there is nothing left to decide: this reader voted,
/// the record says they already had, or the poll is closed. Before that
/// mastodon.social shows the options as buttons and no numbers at all.
fn Poll::shows_results(self : Poll) -> Bool {
  self.data.expired || self.data.voted || self.data.own_votes.length() > 0
}

///|
/// How many votes the best-supported option has — what "leading" is measured
/// against, and what mastodon.social puts in bold.
fn Poll::best(self : Poll) -> Int {
  let mut best = 0
  for i in 0..<self.data.options.length() {
    let n = self.votes_at(i)
    if n > best {
      best = n
    }
  }
  best
}

///|
fn Poll::option_items(self : Poll) -> @values.Value {
  let total = self.total()
  let best = self.best()
  // Carried on every option rather than read off the component, because a `.`
  // path inside an `@each` resolves against the ITEM: a loop binds `@value`,
  // and a view that wrote `.showResults` in there would be asking an option for
  // a field the poll has. It is the same reason a segment carries `external`.
  let results = self.shows_results()
  let out : Array[@values.Value] = []
  for i in 0..<self.data.options.length() {
    let votes = self.votes_at(i)
    let share = if total > 0 { votes * 100 / total } else { 0 }
    out.push(
      vmap([
        ("title", vtext(self.data.options[i].title)),
        ("votesCount", vnum(votes)),
        ("votesLabel", vtext(count_label(votes))),
        ("share", vnum(share)),
        ("shareLabel", vtext("\{share}%")),
        ("chosen", vbool(self.data.own_votes.contains(i))),
        ("leading", vbool(results && votes > 0 && votes == best)),
        ("showResults", vbool(results)),
      ]),
    )
  }
  vlist(out)
}

///|
impl DynComponent for Poll with fn get_field(self, name) {
  let d = self.data
  match name {
    // declared
    "statusId" => Some(vtext(self.status_id))
    "options" => Some(poll_options_value(d.options))
    "votesCount" => Some(vnum(d.votes))
    "votersCount" => Some(vnum(d.voters))
    "expiresAt" => Some(vtext(d.expires_at))
    "expired" => Some(vbool(d.expired))
    "multiple" => Some(vbool(d.multiple))
    "voted" => Some(vbool(d.voted))
    "ownVotes" => Some(vlist(d.own_votes.map(vnum)))
    // derived: what the view iterates and reads
    "optionItems" => Some(self.option_items())
    "showResults" => Some(vbool(self.shows_results()))
    // Exact, unlike every other count here: a poll's total is the denominator
    // of the shares beside it, and "1K votes" is a denominator nobody can check.
    "totalLabel" => {
      let n = self.total()
      Some(vtext(if n == 1 { "1 vote" } else { "\{n} votes" }))
    }
    "stateLabel" =>
      Some(
        vtext(
          if d.expired {
            "Closed"
          } else if d.expires_at != "" {
            "Ends \{time_label(d.expires_at)}"
          } else {
            ""
          },
        ),
      )
    "openLabel" => Some(vtext(if d.multiple { "Pick any" } else { "Pick one" }))
    _ => None
  }
}

///|
/// Voting is optimistic and announced, the way a favourite is: the pick moves
/// here and the bubble is what somebody with a network connection turns into a
/// `POST /api/v1/polls/:id/votes`. This bundle has no network and is only saying
/// what happened.
impl DynComponent for Poll with fn handle_dispatch(self, bucket, name, args) {
  guard bucket is MessageDispatch && name == "vote" else { return Unhandled }
  guard args is [@values.Value::Number(n), ..] else { return Unhandled }
  let i = n.to_int()
  let d = self.data
  guard i >= 0 && i < d.options.length() else { return Unchanged }
  // A closed poll, or one the record says was already voted in, is a poll with
  // nothing left to decide.
  guard !d.expired && !d.voted else { return Unchanged }
  let picked = d.own_votes.contains(i)
  let own_votes = if d.multiple {
    let next = d.own_votes.filter(v => v != i)
    if !picked {
      next.push(i)
    }
    next
  } else if picked {
    []
  } else {
    [i]
  }
  @control.intent(
    if picked {
      "unvoted"
    } else {
      "voted"
    },
    [vtext(self.status_id), vnum(i)],
    {
      route: [DYN],
      on_ok: None,
      on_error: None,
      on_unhandled: None,
      live_path: false,
    },
  )
  Changed({ ..self, data: { ..d, own_votes, }, } as &DynComponent)
}

///|
impl DynComponent for Poll with fn render_call(self, name, _args) {
  match name {
    "summary" => {
      let n = self.data.options.length()
      let kind = if self.data.multiple {
        "multiple choice"
      } else {
        "one choice"
      }
      vtext(
        "poll, \{n} options, \{kind} — \{count_label(self.total())} votes cast",
      )
    }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Poll with fn with_field(self, name, v) {
  let d = self.data
  match (name, v) {
    ("statusId", @values.Value::Text(s)) =>
      Some({ ..self, status_id: s, } as &DynComponent)
    ("options", @values.Value::List(h)) =>
      Some(
        { ..self, data: { ..d, options: poll_options_of(list_items(h)), }, }
        as &DynComponent,
      )
    ("votesCount", @values.Value::Number(n)) =>
      Some({ ..self, data: { ..d, votes: n.to_int(), }, } as &DynComponent)
    ("votersCount", @values.Value::Number(n)) =>
      Some({ ..self, data: { ..d, voters: n.to_int(), }, } as &DynComponent)
    ("expiresAt", @values.Value::Text(s)) =>
      Some({ ..self, data: { ..d, expires_at: s, }, } as &DynComponent)
    ("expired", @values.Value::Boolean(b)) =>
      Some({ ..self, data: { ..d, expired: b, }, } as &DynComponent)
    ("multiple", @values.Value::Boolean(b)) =>
      Some({ ..self, data: { ..d, multiple: b, }, } as &DynComponent)
    ("voted", @values.Value::Boolean(b)) =>
      Some({ ..self, data: { ..d, voted: b, }, } as &DynComponent)
    ("ownVotes", @values.Value::List(h)) =>
      Some(
        { ..self, data: { ..d, own_votes: ints_of(list_items(h)), }, }
        as &DynComponent,
      )
    _ => None
  }
}

///|
fn make_poll(args : Array[(String, @values.Value)]) -> &DynComponent {
  let m = @values.map_new()
  let mut status_id = ""
  for arg in args {
    let (name, v) = arg
    if name == "statusId" {
      match v {
        @values.Value::Text(s) => status_id = s
        _ => ()
      }
    } else {
      @values.map_set(m, name, v)
    }
  }
  ({ data: poll_of(Some(@values.Value::Map(m))), status_id, } : Poll)
  as &DynComponent
}

// ── Status: one post, and one row of everything else ─────────────────────────

///|
/// One fediverse post.
///
/// It is also the row `Thread`, `Timeline` and `Profile` are made of, which is
/// why it carries `depth`, `focus` and `foldable`: a view cannot iterate a value
/// it found inside another iteration (the sequence a `@each` takes is a field
/// path, not a loop binding), so a post's rich text can only be a loop in the
/// component that OWNS it. One post per component is therefore not composition
/// for its own sake — it is the only shape in which a reply keeps its links.
///
/// Its state is exactly the fields the manifest declares plus the token of its
/// poll, which is the host's, so it does not persist.
priv struct Status {
  toot : Toot
  favourited : Bool
  reblogged : Bool
  bookmarked : Bool
  /// Whether this reader opened the content warning. Mastodon starts every
  /// warned post closed, however many times it has been seen.
  revealed : Bool
  /// The post its thread is about, marked; set by whoever built the row.
  focus : Bool
  /// How many replies sit under this one in the thread that built it. 0 hides
  /// the fold button.
  foldable : Int
  folded : Bool
  /// Whether this post is a ROW inside a larger surface — a thread, a feed —
  /// rather than standing on its own. A row draws smaller; it keeps its own
  /// favourite / boost / fold either way.
  owned : Bool
  /// The poll's child token, or empty for a post without one. A list rather
  /// than an option because that is what `<x render-each>` takes, and a poll is
  /// the one child a status has.
  poll_rows : Array[UInt64]
}

///|
/// What this reader's own answer adds to the count the record arrived with.
fn bump(on : Bool) -> Int {
  if on {
    1
  } else {
    0
  }
}

///|
/// Build the poll's child, if there is a poll. The token comes back immediately
/// and the child is constructed after the current call returns: the Component
/// Model forbids re-entering a component while a call into it is active, so
/// `make-instance` only reserves.
fn Status::build_poll(self : Status) -> Status {
  guard self.toot.poll.options.length() > 0 else {
    return { ..self, poll_rows: [], }
  }
  let p = self.toot.poll
  let token = @control.make_instance("Poll", [
    ("statusId", vtext(self.toot.id)),
    ("options", poll_options_value(p.options)),
    ("votesCount", vnum(p.votes)),
    ("votersCount", vnum(p.voters)),
    ("expiresAt", vtext(p.expires_at)),
    ("expired", vbool(p.expired)),
    ("multiple", vbool(p.multiple)),
    ("voted", vbool(p.voted)),
    ("ownVotes", vlist(p.own_votes.map(vnum))),
  ])
  { ..self, poll_rows: [token], }
}

///|
/// Whether the body is on screen: a post with no content warning is always, and
/// a warned one only once the reader asked.
fn Status::body_shown(self : Status) -> Bool {
  self.toot.spoiler == "" || self.revealed
}

///|
impl DynComponent for Status with fn get_field(self, name) {
  let t = self.toot
  match name {
    // the declared fields
    "id" => Some(vtext(t.id))
    "url" => Some(vtext(t.url))
    "acct" => Some(vtext(t.acct))
    "displayName" => Some(vtext(t.display_name))
    "avatar" => Some(vtext(t.avatar))
    "content" => Some(vtext(t.content))
    "spoilerText" => Some(vtext(t.spoiler))
    "createdAt" => Some(vtext(t.created_at))
    "visibility" => Some(vtext(t.visibility))
    "tags" => Some(names_value(t.tags))
    "mentions" => Some(names_value(t.mentions))
    "media" => Some(media_value(t.media))
    "poll" => Some(poll_value(t.poll))
    "repliesCount" => Some(vnum(t.replies))
    "reblogsCount" => Some(vnum(t.reblogs))
    "favouritesCount" => Some(vnum(t.favourites))
    "boostedBy" => Some(vtext(t.boosted_by))
    "pinned" => Some(vbool(t.pinned))
    "edited" => Some(vbool(t.edited))
    "favourited" => Some(vbool(self.favourited))
    "reblogged" => Some(vbool(self.reblogged))
    "bookmarked" => Some(vbool(self.bookmarked))
    "revealed" => Some(vbool(self.revealed))
    "depth" => Some(vnum(t.depth))
    "focus" => Some(vbool(self.focus))
    "foldable" => Some(vnum(self.foldable))
    "folded" => Some(vbool(self.folded))
    "owned" => Some(vbool(self.owned))
    // and what the view reads instead: the projections, computed here so the
    // template stays a template
    "name" => Some(vtext(display_name_or(t.display_name, t.acct)))
    "handleText" => Some(vtext(full_handle(t.acct)))
    "initials" => Some(vtext(initials_of(t.display_name, t.acct)))
    // The picture's path on the host the view names, and "" for an author with
    // no picture or one hosted somewhere else. The view draws the initials
    // UNDER the image rather than instead of it, so both of those, and a fetch
    // that fails after all of this, land on the same square.
    "avatarPath" => Some(vtext(media_path(t.avatar)))
    // The profile is a page on THIS server for a remote account too, so unlike
    // the permalink it never has to fall back to text.
    "profilePath" => Some(vtext(if t.acct == "" { "" } else { "@\{t.acct}" }))
    "time" => Some(vtext(time_label(t.created_at)))
    "segments" => Some(segments_value(t))
    "mediaItems" => Some(media_items_value(t.media))
    "replies" => Some(vtext(count_label(t.replies)))
    "reblogs" => Some(vtext(count_label(t.reblogs + bump(self.reblogged))))
    "favourites" =>
      Some(vtext(count_label(t.favourites + bump(self.favourited))))
    "permalink" => Some(vtext(permalink_of(t)))
    "permalinkPath" => Some(vtext(permalink_path_of(t)))
    // A status this reader can SEE the address of but not follow: it lives on
    // another server, so no view can name its origin. The view draws it as
    // selectable text, which is the same answer a link somebody posted gets.
    "remoteLink" =>
      Some(vbool(permalink_path_of(t) == "" && permalink_of(t) != ""))
    "visibilityGlyph" => Some(vtext(visibility_glyph(t.visibility)))
    "visibilityLabel" => Some(vtext(visibility_label(t.visibility)))
    "boostLabel" =>
      Some(
        vtext(if t.boosted_by == "" { "" } else { "\{t.boosted_by} boosted" }),
      )
    "hasSpoiler" => Some(vbool(t.spoiler != ""))
    "bodyShown" => Some(vbool(self.body_shown()))
    "pollRows" =>
      Some(vlist(self.poll_rows.map(tk => @values.Value::Instance(tk))))
    // The indent, as a list of that many things to draw. An untrusted view has
    // no `style` attribute to put a margin in — so the depth arrives as rails
    // the view iterates, which needs no CSS the guest wrote.
    "rail" =>
      Some(vlist(Array::make(if t.depth > 0 { t.depth } else { 0 }, vnum(0))))
    "foldLabel" =>
      Some(vtext(if self.folded { "+\{self.foldable}" } else { "−" }))
    _ => None
  }
}

///|
impl DynComponent for Status with fn handle_dispatch(self, bucket, name, _args) {
  guard bucket is MessageDispatch else { return Unhandled }
  match name {
    // Optimistic, and announced: the flag is THIS row's — it returns its own
    // successor, and the host writes it home into whatever list holds it — while
    // the bubble is what a host would turn into the API call. The two are
    // different jobs: one is what the screen shows, the other is what somebody
    // with a network connection should do about it. This bundle has no network
    // and is only saying what happened.
    "toggleFavourite" => {
      @control.intent(
        if self.favourited {
          "unfavourited"
        } else {
          "favourited"
        },
        [vtext(self.toot.id)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, favourited: !self.favourited, } as &DynComponent)
    }
    "toggleBoost" => {
      // A post nobody but its author and its mentions can see is a post there
      // is no boosting: mastodon.social draws the button struck through and
      // refuses the click, and so does this.
      guard self.can_boost() else { return Unchanged }
      @control.intent(
        if self.reblogged {
          "unboosted"
        } else {
          "boosted"
        },
        [vtext(self.toot.id)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, reblogged: !self.reblogged, } as &DynComponent)
    }
    "toggleBookmark" => {
      @control.intent(
        if self.bookmarked {
          "unbookmarked"
        } else {
          "bookmarked"
        },
        [vtext(self.toot.id)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, bookmarked: !self.bookmarked, } as &DynComponent)
    }
    // Opening a content warning is this reader's, is nobody else's business and
    // is not announced: unlike a favourite there is nothing for a host to write.
    "toggleReveal" => {
      guard self.toot.spoiler != "" else { return Unchanged }
      Changed({ ..self, revealed: !self.revealed, } as &DynComponent)
    }
    // There is no composer here, so replying is entirely an announcement: this
    // bundle says which post was answered and whoever holds it opens something.
    "reply" => {
      @control.intent("replyTo", [vtext(self.toot.id)], {
        route: [DYN],
        on_ok: None,
        on_error: None,
        on_unhandled: None,
        live_path: false,
      })
      Unchanged
    }
    // The fold flag is THIS row's, and the bubble is what the thread above
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
        [vtext(self.toot.id)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, folded: !self.folded, } as &DynComponent)
    }
    _ => Unhandled
  }
}

///|
/// Whether this post can be boosted at all. Mastodon refuses it for the two
/// visibilities that were never meant to travel.
fn Status::can_boost(self : Status) -> Bool {
  self.toot.visibility != "private" && self.toot.visibility != "direct"
}

///|
impl DynComponent for Status with fn render_call(self, name, _args) {
  let t = self.toot
  match name {
    // the accessible one-line description of the card, and the `title` a reader
    // gets on hover
    "summary" =>
      vtext(
        "\{display_name_or(t.display_name, t.acct)} \{full_handle(t.acct)} — \{count_label(t.replies)} replies, \{count_label(t.reblogs + bump(self.reblogged))} boosts, \{count_label(t.favourites + bump(self.favourited))} favourites",
      )
    // what the content-warning button will do, since its label is the same
    // either way on mastodon.social and only the caret turns
    "revealLabel" =>
      vtext(if self.revealed { "Show less" } else { "Show more" })
    "boostTitle" =>
      if !self.can_boost() {
        vtext("this post's visibility does not allow boosting")
      } else if self.reblogged {
        vtext("undo boost")
      } else {
        vtext("boost")
      }
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
impl DynComponent for Status with fn with_field(self, name, v) {
  let t = self.toot
  match (name, v) {
    ("id", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, id: s, }, } as &DynComponent)
    ("url", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, url: s, }, } as &DynComponent)
    ("acct", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, acct: s, }, } as &DynComponent)
    ("displayName", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, display_name: s, }, } as &DynComponent)
    ("avatar", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, avatar: s, }, } as &DynComponent)
    ("content", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, content: s, }, } as &DynComponent)
    ("spoilerText", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, spoiler: s, }, } as &DynComponent)
    ("createdAt", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, created_at: s, }, } as &DynComponent)
    ("visibility", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, visibility: s, }, } as &DynComponent)
    ("tags", @values.Value::List(h)) =>
      Some(
        { ..self, toot: { ..t, tags: names_of(list_items(h), "name"), }, }
        as &DynComponent,
      )
    ("mentions", @values.Value::List(h)) =>
      Some(
        { ..self, toot: { ..t, mentions: names_of(list_items(h), "acct"), }, }
        as &DynComponent,
      )
    ("media", @values.Value::List(h)) =>
      Some(
        { ..self, toot: { ..t, media: media_of(list_items(h)), }, }
        as &DynComponent,
      )
    // rewriting the poll rebuilds its child, since a poll is told at build time
    // what it is
    ("poll", _) =>
      Some(
        ({ ..self, toot: { ..t, poll: poll_of(Some(v)), }, } : Status).build_poll()
        as &DynComponent,
      )
    ("repliesCount", @values.Value::Number(n)) =>
      Some({ ..self, toot: { ..t, replies: n.to_int(), }, } as &DynComponent)
    ("reblogsCount", @values.Value::Number(n)) =>
      Some({ ..self, toot: { ..t, reblogs: n.to_int(), }, } as &DynComponent)
    ("favouritesCount", @values.Value::Number(n)) =>
      Some({ ..self, toot: { ..t, favourites: n.to_int(), }, } as &DynComponent)
    ("boostedBy", @values.Value::Text(s)) =>
      Some({ ..self, toot: { ..t, boosted_by: s, }, } as &DynComponent)
    ("pinned", @values.Value::Boolean(b)) =>
      Some({ ..self, toot: { ..t, pinned: b, }, } as &DynComponent)
    ("edited", @values.Value::Boolean(b)) =>
      Some({ ..self, toot: { ..t, edited: b, }, } as &DynComponent)
    ("depth", @values.Value::Number(n)) =>
      Some({ ..self, toot: { ..t, depth: n.to_int(), }, } as &DynComponent)
    ("favourited", @values.Value::Boolean(b)) =>
      Some({ ..self, favourited: b, } as &DynComponent)
    ("reblogged", @values.Value::Boolean(b)) =>
      Some({ ..self, reblogged: b, } as &DynComponent)
    ("bookmarked", @values.Value::Boolean(b)) =>
      Some({ ..self, bookmarked: b, } as &DynComponent)
    ("revealed", @values.Value::Boolean(b)) =>
      Some({ ..self, revealed: b, } as &DynComponent)
    ("focus", @values.Value::Boolean(b)) =>
      Some({ ..self, focus: b, } as &DynComponent)
    ("foldable", @values.Value::Number(n)) =>
      Some({ ..self, foldable: n.to_int(), } as &DynComponent)
    ("folded", @values.Value::Boolean(b)) =>
      Some({ ..self, folded: b, } as &DynComponent)
    ("owned", @values.Value::Boolean(b)) =>
      Some({ ..self, owned: b, } as &DynComponent)
    // the poll returned a successor and the host is writing it home
    ("pollRows", _) =>
      match tokens_of(v) {
        Some(poll_rows) => {
          guard poll_rows.length() == self.poll_rows.length() else { None }
          Some({ ..self, poll_rows, } as &DynComponent)
        }
        None => None
      }
    _ => None
  }
}

///|
fn empty_toot() -> Toot {
  {
    id: "",
    url: "",
    acct: "",
    display_name: "",
    avatar: "",
    content: "",
    spoiler: "",
    created_at: "",
    visibility: "public",
    tags: [],
    mentions: [],
    media: [],
    poll: poll_of(None),
    replies: 0,
    reblogs: 0,
    favourites: 0,
    boosted_by: "",
    pinned: false,
    edited: false,
    depth: 0,
  }
}

///|
fn make_status(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut toot = empty_toot()
  let mut favourited = false
  let mut reblogged = false
  let mut bookmarked = false
  let mut revealed = false
  let mut focus = false
  let mut foldable = 0
  let mut folded = false
  let mut owned = false
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("id", @values.Value::Text(s)) => toot = { ..toot, id: s, }
      ("url", @values.Value::Text(s)) => toot = { ..toot, url: s, }
      ("acct", @values.Value::Text(s)) => toot = { ..toot, acct: s, }
      ("displayName", @values.Value::Text(s)) =>
        toot = { ..toot, display_name: s, }
      ("avatar", @values.Value::Text(s)) => toot = { ..toot, avatar: s, }
      ("content", @values.Value::Text(s)) => toot = { ..toot, content: s, }
      ("spoilerText", @values.Value::Text(s)) => toot = { ..toot, spoiler: s, }
      ("createdAt", @values.Value::Text(s)) => toot = { ..toot, created_at: s, }
      ("visibility", @values.Value::Text(s)) =>
        toot = { ..toot, visibility: s, }
      ("tags", @values.Value::List(h)) =>
        toot = { ..toot, tags: names_of(list_items(h), "name"), }
      ("mentions", @values.Value::List(h)) =>
        toot = { ..toot, mentions: names_of(list_items(h), "acct"), }
      ("media", @values.Value::List(h)) =>
        toot = { ..toot, media: media_of(list_items(h)), }
      ("poll", _) => toot = { ..toot, poll: poll_of(Some(v)), }
      ("repliesCount", @values.Value::Number(n)) =>
        toot = { ..toot, replies: n.to_int(), }
      ("reblogsCount", @values.Value::Number(n)) =>
        toot = { ..toot, reblogs: n.to_int(), }
      ("favouritesCount", @values.Value::Number(n)) =>
        toot = { ..toot, favourites: n.to_int(), }
      ("boostedBy", @values.Value::Text(s)) => toot = { ..toot, boosted_by: s, }
      ("pinned", @values.Value::Boolean(b)) => toot = { ..toot, pinned: b, }
      ("edited", @values.Value::Boolean(b)) => toot = { ..toot, edited: b, }
      ("depth", @values.Value::Number(n)) =>
        toot = { ..toot, depth: n.to_int(), }
      ("favourited", @values.Value::Boolean(b)) => favourited = b
      ("reblogged", @values.Value::Boolean(b)) => reblogged = b
      ("bookmarked", @values.Value::Boolean(b)) => bookmarked = b
      ("revealed", @values.Value::Boolean(b)) => revealed = b
      ("focus", @values.Value::Boolean(b)) => focus = b
      ("foldable", @values.Value::Number(n)) => foldable = n.to_int()
      ("folded", @values.Value::Boolean(b)) => folded = b
      ("owned", @values.Value::Boolean(b)) => owned = b
      _ => ()
    }
  }
  (
    {
      toot,
      favourited,
      reblogged,
      bookmarked,
      revealed,
      focus,
      foldable,
      folded,
      owned,
      poll_rows: [],
    } : Status).build_poll()
  as &DynComponent
}

///|
/// One post as constructor args for a child `Status` — the same names the
/// manifest declares, because a child is built exactly the way the host would
/// build one.
fn child_args(
  t : Toot,
  focus~ : Bool,
  foldable~ : Int,
  folded? : Bool = false,
) -> Array[(String, @values.Value)] {
  [
    ("id", vtext(t.id)),
    ("url", vtext(t.url)),
    ("acct", vtext(t.acct)),
    ("displayName", vtext(t.display_name)),
    ("avatar", vtext(t.avatar)),
    ("content", vtext(t.content)),
    ("spoilerText", vtext(t.spoiler)),
    ("createdAt", vtext(t.created_at)),
    ("visibility", vtext(t.visibility)),
    ("tags", names_value(t.tags)),
    ("mentions", names_value(t.mentions)),
    ("media", media_value(t.media)),
    ("poll", poll_value(t.poll)),
    ("repliesCount", vnum(t.replies)),
    ("reblogsCount", vnum(t.reblogs)),
    ("favouritesCount", vnum(t.favourites)),
    ("boostedBy", vtext(t.boosted_by)),
    ("pinned", vbool(t.pinned)),
    ("edited", vbool(t.edited)),
    ("depth", vnum(t.depth)),
    ("focus", vbool(focus)),
    ("foldable", vnum(foldable)),
    ("folded", vbool(folded)),
    // this post is a row inside something larger, which is what the view reads
    // to draw it smaller
    ("owned", vbool(true)),
  ]
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
/// A set with `id` added or taken out — the flags a surface keeps for its rows,
/// which are sets rather than a field on the post because they are this
/// READER's doing and not part of the record.
fn with_id(set : Array[String], id : String, on : Bool) -> Array[String] {
  let out = set.filter(u => u != id)
  if on {
    out.push(id)
  }
  out
}

// ── Scope: what the answer above it does NOT cover ───────────────────────────

///|
/// The disclosure that an answer is partial.
///
/// A card is a claim, and a `Timeline` is almost never the whole of anything: a
/// federated timeline is what THIS instance has seen, a tag feed is what it has
/// federated, and every one of them is a page with a cap somebody chose. The
/// prose beside a card can say that; the card could not, so the card was the
/// more confident of the two while being the less informed.
///
/// It is deliberately not an error and not a warning. Nothing here is wrong: a
/// page is a page. What it turns a count into is a claim a reader can check.
///
/// Field-for-field the same component the bluesky bundle has, and that is the
/// point rather than a coincidence: a host drawing a mastodon card beside an
/// ATProto one should not have to learn two spellings of "this is not
/// everything". `slacklib`'s twin differs because what a slack answer leaves out
/// is conversations rather than pages of a feed.
priv struct Scope {
  /// A cap stopped this before the data ran out. The one field that matters
  /// most: it is the difference between "there is no more" and "I stopped".
  truncated : Bool
  /// What stopped it, in the caller's words: `"limit"`, `"depth"`.
  truncated_by : String
  /// There is another page, and nobody asked for it.
  more : Bool
  /// What this answer does not cover, one sentence each. Free text because the
  /// reasons are not a closed set — an instance that only federates what someone
  /// on it follows, and a filter the server applied, are both true and neither
  /// is a boolean.
  notes : Array[String]
}

///|
/// A list of plain strings, which is what `notes` arrives as.
fn strs_of(items : Array[@values.Value]) -> Array[String] {
  let out : Array[String] = []
  for v in items {
    if v is @values.Value::Text(s) && s != "" {
      out.push(s)
    }
  }
  out
}

///|
impl DynComponent for Scope with fn get_field(self, name) {
  match name {
    "truncated" => Some(vbool(self.truncated))
    "truncatedBy" => Some(vtext(self.truncated_by))
    "more" => Some(vbool(self.more))
    "notes" => Some(vlist(self.notes.map(vtext)))
    // A scope with nothing to disclose draws nothing at all. That is not the
    // same as a scope that is absent, and both are correct: the difference only
    // matters to whoever built it.
    "hasAny" =>
      Some(vbool(self.truncated || self.more || self.notes.length() > 0))
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
impl DynComponent for Scope with fn render_call(self, name, _args) {
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
      if parts.length() == 0 {
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
      Some({ ..self, truncated: b, } as &DynComponent)
    ("truncatedBy", @values.Value::Text(s)) =>
      Some({ ..self, truncated_by: s, } as &DynComponent)
    ("more", @values.Value::Boolean(b)) =>
      Some({ ..self, more: b, } as &DynComponent)
    ("notes", @values.Value::List(h)) =>
      Some({ ..self, notes: strs_of(list_items(h)), } as &DynComponent)
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
  ({ truncated, truncated_by, more, notes, } : Scope) as &DynComponent
}

///|
/// The `Scope` child a surface hangs under itself, and whether it has anything
/// to say.
///
/// One is always built, even for an answer with nothing to disclose. The keys of
/// the record ARE the component's field names, so a host that writes plain JSON
/// into `scope` gets the component it would have got by building one.
///
/// Whether it has anything to SAY comes back beside the token rather than out of
/// the child, and that is the contract talking rather than a shortcut: a token is
/// a bridge handle, and a parent holding one cannot read a field behind it.
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
// Three of the components below are a column of child `Status`es, and how long
// that column is was never theirs to decide: a caller asks a server for a
// timeline, a conversation or an account's posts, and what comes back is
// whatever a `limit` allowed. Forty rows is a card. Four hundred is a wall a
// reader scrolls past rather than reads, drawn out of four hundred child
// components before any one of them is looked at.
//
// So a long list gets a window and the four buttons that move it, in the
// vocabulary the `table` bundle already uses for the same job — `page`,
// `pageCount`, `pageSize`, `firstPage` / `prevPage` / `nextPage` / `lastPage`,
// `atFirst` / `atLast` — because a host drawing both should not have to learn
// two spellings of "show me the next lot".
//
// The window is over what the FILTERS left, not over the records: a search box
// narrows and the pager pages what is left, which is the order a reader means
// when they type in the box while on page three.
//
// And nothing here rebuilds a row. A page is a claim about what is on screen
// rather than about what exists, so a favourite three pages back is still there
// when the reader comes back to it — the property the filter already had, for
// the same reason: the children are built once and something else chooses among
// them.

///|
/// How many rows a paged card shows at once when nobody asked for a number.
const PAGE_SIZE = 25

///|
/// How long a list has to BE before a reader is made to page through it.
///
/// The pager is not furniture that is always there: below this a card draws
/// exactly what it drew before it could page at all — no footer, every row on
/// screen — because breaking forty posts into two pages costs a reader a click
/// and buys them nothing. A host that wants the window anyway asks for a
/// `pageSize`, which is what asking for one means.
const PAGE_ABOVE = 100

///|
/// The state of one paged list, and every answer a view asks about it.
///
/// Computed per read rather than stored, because two of the three numbers in it
/// are not the component's to keep: `total` is what the filters left, which
/// moves as a reader types, and `page` is a wish that has to be brought back
/// inside a list that may have shrunk under it. What a component stores is the
/// two wishes; this is what they come out as.
priv struct Pager {
  /// 0-based, and already clamped to what `total` and the window allow.
  page : Int
  /// How many rows a page holds. In effect whether or not it is being used, so
  /// `pageSize` reads back the same either way.
  size : Int
  /// Whether the list is long enough that a page is a window rather than the
  /// whole of it.
  on : Bool
  /// How many rows there are to page through: after the filters, before the
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
  { page, size, on, total, }
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
/// The positions this page shows, out of the ones the filters left.
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
/// The methods a paged card answers.
///
/// `paged` is the one a view asks first: a card showing everything it has draws
/// no footer at all, so the whole control hangs off this rather than off a row
/// count a template would have to do arithmetic on.
fn Pager::answer(self : Pager, name : String) -> @values.Value? {
  match name {
    "paged" => Some(vbool(self.on))
    "atFirst" => Some(vbool(self.page <= 0))
    "atLast" => Some(vbool(self.page >= self.pages() - 1))
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
/// Either the pager's answer or nothing, as a `compute` has to answer.
fn Pager::answer_or_nil(self : Pager, name : String) -> @values.Value {
  match self.answer(name) {
    Some(v) => v
    None => @values.Value::Nil
  }
}

///|
/// Every position in a list of `n`, for the components that have no filter to
/// narrow one: a page is the only thing between their rows and the screen.
fn all_positions(n : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<n {
    out.push(i)
  }
  out
}

// ── Thread: a reply tree, flattened, as a list of Statuses ───────────────────

///|
/// A conversation.
///
/// The tree arrives FLAT — every post carries its own `depth` — because a static
/// view cannot recurse, and because flat is what makes folding a subtree the
/// contiguous-range operation `replies_under` does in one pass.
///
/// Each post becomes a child `Status` through `control.make-instance`, and
/// `rows` is the tokens of the ones currently visible: the host renders them
/// with `<x render-each=".rows">`.
priv struct Thread {
  posts : Array[Toot]
  /// The id of the post the thread is about; "" for none.
  focus : String
  /// One child token per post, in `posts` order.
  children : Array[UInt64]
  /// The ids this reader folded away. It is here rather than on the row because
  /// it is the THREAD's question: which posts stop rendering because something
  /// above them is folded. The row keeps its own `folded` for its own glyph, and
  /// the two are different facts about the same click.
  collapsed : Array[String]
  /// The `Scope` child: what this conversation does not show — the depth the
  /// caller asked for, and the replies this instance has never federated.
  scope : UInt64
  /// Whether that child has anything to disclose, which is what the view gates
  /// the box on. Kept here because a token cannot be read back.
  has_scope : Bool
  /// Which page of the conversation is on screen, 0-based. A wish rather than a
  /// fact: folding a subtree takes rows away underneath it, so what it comes out
  /// as is whatever `paging` can honour.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
/// How many posts hang under the one at `i` — the contiguous run of deeper posts
/// that follows it, which is what "flattened" buys.
fn replies_under(posts : Array[Toot], i : Int) -> Int {
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
fn Thread::make_row(self : Thread, i : Int) -> UInt64 {
  let t = self.posts[i]
  @control.make_instance(
    "Status",
    child_args(
      t,
      focus=t.id != "" && t.id == self.focus,
      foldable=replies_under(self.posts, i),
      folded=self.collapsed.contains(t.id),
    ),
  )
}

///|
/// A child per post. Called when the posts or the focus change — never on a
/// favourite or a fold, which change the ONE row that changed.
fn Thread::build_rows(self : Thread) -> Thread {
  let children : Array[UInt64] = []
  for i in 0..<self.posts.length() {
    children.push(self.make_row(i))
  }
  { ..self, children, }
}

///|
/// Whether this thread has that post at all — a bubble naming one it does not is
/// not this thread's to act on.
fn Thread::has(self : Thread, id : String) -> Bool {
  self.posts.iter().any(t => t.id == id)
}

///|
/// The rows a view draws: every post except the ones under a folded one.
fn Thread::visible(self : Thread) -> Array[Int] {
  let out : Array[Int] = []
  let mut skip_below = -1
  for i in 0..<self.posts.length() {
    let t = self.posts[i]
    if skip_below >= 0 {
      if t.depth > skip_below {
        continue
      }
      skip_below = -1
    }
    if self.collapsed.contains(t.id) && replies_under(self.posts, i) > 0 {
      skip_below = t.depth
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
/// write-back lands by position and a guess would land on the wrong post.
fn Thread::shown(self : Thread) -> Array[Int] {
  self.pager().slice(self.visible())
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

///|
impl DynComponent for Thread with fn get_field(self, name) {
  match name {
    // declared
    "posts" => Some(vlist(self.posts.map(toot_value)))
    "focus" => Some(vtext(self.focus))
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(vbool(self.has_scope))
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
/// thing that can act on it. A favourite, a boost and a vote are handled by
/// nobody on the way up: this bundle cannot write to a server, so the component
/// above is the one that turns them into API calls.
impl DynComponent for Thread with fn handle_dispatch(self, bucket, name, args) {
  // The pager's four buttons are the only input of its own a thread has;
  // everything else that reaches it came up from a row. A page moves nothing
  // but which rows are drawn, so no row is rebuilt and nothing is announced —
  // there is nobody above who could act on "the reader turned a page".
  if bucket is MessageDispatch && is_page_message(name) {
    return match self.pager().moved(name) {
      Some(page) => Changed({ ..self, page, } as &DynComponent)
      None => Unchanged
    }
  }
  guard bucket is IntentDispatch else { return Unhandled }
  guard args is [@values.Value::Text(id), ..] else { return Unhandled }
  guard id != "" && self.has(id) else { return Unchanged }
  match name {
    // The row has already flipped its OWN `folded` and returned a successor;
    // what this adds is the half only the thread knows — which posts sit under
    // it and therefore stop rendering. It does not rebuild the row: destroying
    // and remaking it would throw away the successor the host just wrote home,
    // along with whatever else the reader had done to it.
    "folded" | "unfolded" => {
      @control.stop_propagation()
      let on = name == "folded"
      guard self.collapsed.contains(id) != on else { return Unchanged }
      Changed(
        { ..self, collapsed: with_id(self.collapsed, id, on), } as &DynComponent,
      )
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for Thread with fn render_call(self, name, _args) {
  match name {
    "summary" => {
      let total = self.posts.length()
      let shown = self.visible().length()
      if shown == total {
        vtext("\{total} posts")
      } else {
        vtext("\{total} posts · \{total - shown} folded away")
      }
    }
    _ => self.pager().answer_or_nil(name)
  }
}

///|
/// Writing either declared field rebuilds every row, because a row is told at
/// build time which post it is and whether it is the focus. What this reader had
/// done goes with them: it belonged to posts that are no longer the ones here.
///
/// The old tokens are not dropped here. The host owns a child's lifetime — it
/// wraps the token and sweeps what a superseded instance held once the
/// transaction settles — so a guest dropping a whole list would be racing it.
impl DynComponent for Thread with fn with_field(self, name, v) {
  match (name, v) {
    ("posts", @values.Value::List(h)) => {
      let next : Thread = {
        posts: toots_of(h),
        focus: self.focus,
        children: [],
        collapsed: [],
        // The scope is the ANSWER's, not the list's: a host writing new posts
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
      Some(({ ..self, focus: s, } : Thread).build_rows() as &DynComponent)
    ("scope", @values.Value::Instance(t)) =>
      Some({ ..self, scope: t, } as &DynComponent)
    // Asking for a page size is asking to be paged, so it starts at the first
    // page: the window a host just chose is not one this reader has been
    // anywhere in.
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0, } as &DynComponent)
    // A row returned a successor and the host is writing the whole list home.
    // What it hands back is the list it was SHOWN — `shown()` — so it goes home
    // through the same function that decided those positions.
    ("rows", _) =>
      match write_rows(self.children, self.shown(), v) {
        Some(children) => Some({ ..self, children, } as &DynComponent)
        None => None
      }
    _ => None
  }
}

///|
fn make_thread(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut posts : Array[Toot] = []
  let mut focus = ""
  let mut page_size = 0
  let mut scope_arg : @values.Value? = None
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      // hot-swap migration hands the declared fields back as args
      ("posts", @values.Value::List(h)) => posts = toots_of(h)
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

// ── Timeline: what mastodon.social/explore is ────────────────────────────────

///|
/// A feed: a heading, and a column of posts under it.
///
/// It is the surface the other four are read on — trending, a hashtag, a
/// server's local timeline — and the one that is interactive rather than only
/// displayed: it filters what it holds, which is the reason it keeps the records
/// rather than only the children. A row is built once and shown or not; nothing
/// is rebuilt to filter, so a favourite survives typing in the box.
priv struct Timeline {
  title : String
  posts : Array[Toot]
  /// What the reader typed. Matched against the text, the name and the handle,
  /// which is what a person means by "search this timeline".
  query : String
  /// Mastodon's "show media only" — a real toggle on a real timeline, and the
  /// one filter that is not text.
  media_only : Bool
  children : Array[UInt64]
  /// The `Scope` child: what this page does not cover. A timeline is almost
  /// never the whole of anything — a federated one is what THIS instance has
  /// seen — and the card said so nowhere until this field existed.
  scope : UInt64
  has_scope : Bool
  /// Which page of the column is on screen, 0-based. A wish rather than a fact:
  /// the search box narrows the list under it, so what it comes out as is
  /// whatever `paging` can honour.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
/// A row of a feed stands on its own: no depth, nothing to fold.
fn Timeline::make_row(self : Timeline, i : Int) -> UInt64 {
  @control.make_instance(
    "Status",
    child_args({ ..self.posts[i], depth: 0, }, focus=false, foldable=0),
  )
}

///|
fn Timeline::build_rows(self : Timeline) -> Timeline {
  let children : Array[UInt64] = []
  for i in 0..<self.posts.length() {
    children.push(self.make_row(i))
  }
  { ..self, children, }
}

///|
/// Whether one post survives both filters.
fn Timeline::keeps(self : Timeline, t : Toot) -> Bool {
  if self.media_only && t.media.length() == 0 {
    return false
  }
  let needle = self.query.trim().to_owned().to_lower()
  if needle == "" {
    return true
  }
  lower(t.content).contains(needle) ||
  lower(t.display_name).contains(needle) ||
  lower(t.acct).contains(needle) ||
  lower(t.spoiler).contains(needle)
}

///|
fn Timeline::visible(self : Timeline) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<self.posts.length() {
    if self.keeps(self.posts[i]) {
      out.push(i)
    }
  }
  out
}

///|
/// The pager over what the filters left. The order is the one a reader means:
/// the box narrows, and the pager pages what is left of it.
fn Timeline::pager(self : Timeline) -> Pager {
  paging(self.page, self.visible().length(), self.page_size)
}

///|
/// The positions actually on screen: kept by the filters, and on this page.
fn Timeline::shown(self : Timeline) -> Array[Int] {
  self.pager().slice(self.visible())
}

///|
impl DynComponent for Timeline with fn get_field(self, name) {
  match name {
    // declared
    "title" => Some(vtext(self.title))
    "posts" => Some(vlist(self.posts.map(toot_value)))
    "query" => Some(vtext(self.query))
    "mediaOnly" => Some(vbool(self.media_only))
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(vbool(self.has_scope))
    // derived
    "rows" => Some(rows_value(self.children, self.shown()))
    // Empty is a fact about the FILTERS, not about the page: a column with rows
    // on another page is not "Nothing here."
    "isEmpty" => Some(vbool(self.visible().length() == 0))
    "isFiltered" =>
      Some(vbool(self.media_only || self.query.trim().to_owned() != ""))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for Timeline with fn handle_dispatch(self, bucket, name, args) {
  guard bucket is MessageDispatch else { return Unhandled }
  match name {
    // The filter does NOT rebuild the rows: the children are built once and the
    // filter chooses among them, so what a reader did to a row is still there
    // when the row comes back.
    // Each of the three goes back to the first page, because a filter makes a
    // different list and page four of the old one is a position in a column
    // that is not there any more.
    "setQuery" =>
      match args {
        [@values.Value::Text(s), ..] => {
          guard s != self.query else { return Unchanged }
          Changed({ ..self, query: s, page: 0, } as &DynComponent)
        }
        _ => Unhandled
      }
    "clearQuery" => {
      guard self.query != "" else { return Unchanged }
      Changed({ ..self, query: "", page: 0, } as &DynComponent)
    }
    "toggleMediaOnly" =>
      Changed(
        { ..self, media_only: !self.media_only, page: 0, } as &DynComponent,
      )
    // Paging is not a filter: it changes which rows are drawn and nothing about
    // which rows there are, so no row is rebuilt.
    "firstPage" | "prevPage" | "nextPage" | "lastPage" =>
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
    _ => Unhandled
  }
}

///|
impl DynComponent for Timeline with fn render_call(self, name, _args) {
  match name {
    "countLabel" => {
      let total = self.posts.length()
      let shown = self.visible().length()
      if shown == total {
        vtext(if total == 1 { "1 post" } else { "\{total} posts" })
      } else {
        vtext("\{shown} of \{total} posts")
      }
    }
    "mediaLabel" =>
      vtext(if self.media_only { "✓ media only" } else { "media only" })
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for Timeline with fn with_field(self, name, v) {
  match (name, v) {
    ("title", @values.Value::Text(s)) =>
      Some({ ..self, title: s, } as &DynComponent)
    ("posts", @values.Value::List(h)) =>
      Some(
        ({ ..self, posts: toots_of(h), page: 0, } : Timeline).build_rows()
        as &DynComponent,
      )
    ("query", @values.Value::Text(s)) =>
      Some({ ..self, query: s, page: 0, } as &DynComponent)
    ("mediaOnly", @values.Value::Boolean(b)) =>
      Some({ ..self, media_only: b, page: 0, } as &DynComponent)
    ("scope", @values.Value::Instance(t)) =>
      Some({ ..self, scope: t, } as &DynComponent)
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0, } as &DynComponent)
    ("rows", _) =>
      match write_rows(self.children, self.shown(), v) {
        Some(children) => Some({ ..self, children, } as &DynComponent)
        None => None
      }
    _ => None
  }
}

///|
fn make_timeline(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut title = "Trending"
  let mut posts : Array[Toot] = []
  let mut query = ""
  let mut media_only = false
  let mut page_size = 0
  let mut scope_arg : @values.Value? = None
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("title", @values.Value::Text(s)) => title = s
      ("posts", @values.Value::List(h)) => posts = toots_of(h)
      ("query", @values.Value::Text(s)) => query = s
      ("mediaOnly", @values.Value::Boolean(b)) => media_only = b
      ("pageSize", @values.Value::Number(n)) => page_size = n.to_int()
      ("scope", _) => scope_arg = Some(v)
      _ => ()
    }
  }
  let (scope, has_scope) = scope_child(scope_arg)
  (
    {
      title,
      posts,
      query,
      media_only,
      children: [],
      scope,
      has_scope,
      page: 0,
      page_size,
    } : Timeline).build_rows()
  as &DynComponent
}

// ── Profile: an account ──────────────────────────────────────────────────────

///|
/// One account: who it is, what it says about itself, its four columns, the
/// links it put under its bio, and its recent posts — which are child
/// `Status`es, for the same reason a thread's rows are.
priv struct Profile {
  display_name : String
  acct : String
  /// The bio, as PLAIN text for the reason the post's body is.
  note : String
  /// The account's picture and the strip behind it, as the urls the API hands
  /// out. Both are read back through `media_path`, and both fall back to what
  /// was drawn before there were pictures: the initials, and a flat band.
  avatar : String
  header : String
  followers : Int
  follows : Int
  statuses : Int
  created_at : String
  bot : Bool
  locked : Bool
  following : Bool
  /// The four labelled rows Mastodon lets an account put under its bio, with
  /// the check that says the link pointed back at the profile.
  fields : Array[ProfileField]
  posts : Array[Toot]
  children : Array[UInt64]
  /// Which page of the account's posts is on screen, 0-based. An account with
  /// nothing else on the card can arrive carrying hundreds of them.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
fn Profile::make_row(self : Profile, i : Int) -> UInt64 {
  @control.make_instance(
    "Status",
    child_args({ ..self.posts[i], depth: 0, }, focus=false, foldable=0),
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
/// The pager over the account's posts. There is no filter here, so the page is
/// the only thing between the rows and the screen.
fn Profile::pager(self : Profile) -> Pager {
  paging(self.page, self.children.length(), self.page_size)
}

///|
/// The positions on this page.
fn Profile::shown(self : Profile) -> Array[Int] {
  self.pager().slice(all_positions(self.children.length()))
}

///|
fn fields_value(fields : Array[ProfileField]) -> @values.Value {
  vlist(
    fields.map(f => {
      vmap([
        ("name", vtext(f.name)),
        ("value", vtext(f.value)),
        ("verified", vbool(f.verified)),
      ])
    }),
  )
}

///|
/// The metadata rows as a view reads them.
///
/// A row's value is usually a link, and its origin belongs to the ACCOUNT rather
/// than to this server — so it is shown the way a link somebody posted is:
/// shortened text with the whole url in the tooltip, and no `href`. The green
/// check is the one thing this bundle can say about where it points, and it is
/// the server that said it.
fn field_items_value(fields : Array[ProfileField]) -> @values.Value {
  vlist(
    fields.map(f => {
      let is_url = f.value.has_prefix("https://") ||
        f.value.has_prefix("http://")
      vmap([
        ("name", vtext(f.name)),
        ("value", vtext(if is_url { bare_url(f.value) } else { f.value })),
        ("target", vtext(f.value)),
        ("verified", vbool(f.verified)),
      ])
    }),
  )
}

///|
impl DynComponent for Profile with fn get_field(self, name) {
  match name {
    // declared
    "displayName" => Some(vtext(self.display_name))
    "acct" => Some(vtext(self.acct))
    "note" => Some(vtext(self.note))
    "avatar" => Some(vtext(self.avatar))
    "header" => Some(vtext(self.header))
    "followersCount" => Some(vnum(self.followers))
    "followingCount" => Some(vnum(self.follows))
    "statusesCount" => Some(vnum(self.statuses))
    "createdAt" => Some(vtext(self.created_at))
    "bot" => Some(vbool(self.bot))
    "locked" => Some(vbool(self.locked))
    "following" => Some(vbool(self.following))
    "fields" => Some(fields_value(self.fields))
    "posts" => Some(vlist(self.posts.map(toot_value)))
    // derived
    "name" => Some(vtext(display_name_or(self.display_name, self.acct)))
    "handleText" => Some(vtext(full_handle(self.acct)))
    "initials" => Some(vtext(initials_of(self.display_name, self.acct)))
    "avatarPath" => Some(vtext(media_path(self.avatar)))
    "headerPath" => Some(vtext(media_path(self.header)))
    "profilePath" =>
      Some(vtext(if self.acct == "" { "" } else { "@\{self.acct}" }))
    "followersLabel" =>
      Some(vtext(count_label(self.followers + bump(self.following))))
    "followingLabel" => Some(vtext(count_label(self.follows)))
    "statusesLabel" => Some(vtext(count_label(self.statuses)))
    "joinedLabel" => Some(vtext(year_label(self.created_at)))
    "fieldItems" => Some(field_items_value(self.fields))
    "rows" => Some(rows_value(self.children, self.shown()))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for Profile with fn handle_dispatch(self, bucket, name, _args) {
  match (bucket, name) {
    // Same shape as a row's favourite: the flag moves, the follower count
    // follows it through `bump`, and the bubble is what a host would turn into
    // the follow it alone is allowed to write.
    (MessageDispatch, "toggleFollow") => {
      @control.intent(
        if self.following {
          "unfollowed"
        } else {
          "followed"
        },
        [vtext(self.acct)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, following: !self.following, } as &DynComponent)
    }
    // The pager under the account's posts.
    (MessageDispatch, _) => {
      guard is_page_message(name) else { return Unhandled }
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
    }
    // A row's favourite is the ROW's, and it announces upward for whoever can
    // write the record. A feed has nothing to add to that — unlike a thread,
    // which still owns which rows a fold hides — so it does not handle those
    // bubbles and they keep travelling.
    _ => Unhandled
  }
}

///|
impl DynComponent for Profile with fn render_call(self, name, _args) {
  match name {
    "summary" =>
      vtext(
        "\{display_name_or(self.display_name, self.acct)} \{full_handle(self.acct)} — \{count_label(self.followers + bump(self.following))} followers, \{count_label(self.statuses)} posts",
      )
    "followLabel" =>
      if self.following {
        vtext("Following")
      } else if self.locked {
        // a locked account is a request rather than a follow, and mastodon.social
        // says so on the button
        vtext("Request follow")
      } else {
        vtext("Follow")
      }
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for Profile with fn with_field(self, name, v) {
  match (name, v) {
    ("displayName", @values.Value::Text(s)) =>
      Some({ ..self, display_name: s, } as &DynComponent)
    ("acct", @values.Value::Text(s)) =>
      Some({ ..self, acct: s, } as &DynComponent)
    ("note", @values.Value::Text(s)) =>
      Some({ ..self, note: s, } as &DynComponent)
    ("avatar", @values.Value::Text(s)) =>
      Some({ ..self, avatar: s, } as &DynComponent)
    ("header", @values.Value::Text(s)) =>
      Some({ ..self, header: s, } as &DynComponent)
    ("followersCount", @values.Value::Number(n)) =>
      Some({ ..self, followers: n.to_int(), } as &DynComponent)
    ("followingCount", @values.Value::Number(n)) =>
      Some({ ..self, follows: n.to_int(), } as &DynComponent)
    ("statusesCount", @values.Value::Number(n)) =>
      Some({ ..self, statuses: n.to_int(), } as &DynComponent)
    ("createdAt", @values.Value::Text(s)) =>
      Some({ ..self, created_at: s, } as &DynComponent)
    ("bot", @values.Value::Boolean(b)) =>
      Some({ ..self, bot: b, } as &DynComponent)
    ("locked", @values.Value::Boolean(b)) =>
      Some({ ..self, locked: b, } as &DynComponent)
    ("following", @values.Value::Boolean(b)) =>
      Some({ ..self, following: b, } as &DynComponent)
    ("fields", @values.Value::List(h)) =>
      Some({ ..self, fields: fields_of(list_items(h)), } as &DynComponent)
    ("posts", @values.Value::List(h)) =>
      Some(
        ({ ..self, posts: toots_of(h), page: 0, } : Profile).build_rows()
        as &DynComponent,
      )
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0, } as &DynComponent)
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
  let mut acct = ""
  let mut note = ""
  let mut avatar = ""
  let mut header = ""
  let mut followers = 0
  let mut follows = 0
  let mut statuses = 0
  let mut created_at = ""
  let mut bot = false
  let mut locked = false
  let mut following = false
  let mut fields : Array[ProfileField] = []
  let mut posts : Array[Toot] = []
  let mut page_size = 0
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("displayName", @values.Value::Text(s)) => display_name = s
      ("acct", @values.Value::Text(s)) => acct = s
      ("note", @values.Value::Text(s)) => note = s
      ("avatar", @values.Value::Text(s)) => avatar = s
      ("header", @values.Value::Text(s)) => header = s
      ("followersCount", @values.Value::Number(n)) => followers = n.to_int()
      ("followingCount", @values.Value::Number(n)) => follows = n.to_int()
      ("statusesCount", @values.Value::Number(n)) => statuses = n.to_int()
      ("createdAt", @values.Value::Text(s)) => created_at = s
      ("bot", @values.Value::Boolean(b)) => bot = b
      ("locked", @values.Value::Boolean(b)) => locked = b
      ("following", @values.Value::Boolean(b)) => following = b
      ("fields", @values.Value::List(h)) => fields = fields_of(list_items(h))
      ("posts", @values.Value::List(h)) => posts = toots_of(h)
      ("pageSize", @values.Value::Number(n)) => page_size = n.to_int()
      _ => ()
    }
  }
  (
    {
      display_name,
      acct,
      note,
      avatar,
      header,
      followers,
      follows,
      statuses,
      created_at,
      bot,
      locked,
      following,
      fields,
      posts,
      children: [],
      page: 0,
      page_size,
    } : Profile).build_rows()
  as &DynComponent
}

///|
/// None of the five persists: each one's state is exactly the fields it declares
/// (plus child tokens, which are the host's), so the host projects and rebuilds
/// them itself and a `persist` here would be that list written twice.
fn dyn_module() -> DynModule {
  module_def([
    dyn_comp("Scope", make_scope),
    dyn_comp("Status", make_status),
    dyn_comp("Poll", make_poll),
    dyn_comp("Thread", make_thread),
    dyn_comp("Timeline", make_timeline),
    dyn_comp("Profile", make_profile),
  ])
}
