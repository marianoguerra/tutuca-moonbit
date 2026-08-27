///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The slack guest behavior: a chat conversation as six nested components.
///
/// It is a port of the Feeling-of-Computing conversations reader
/// (`at-foc/src/components.js`) onto the `tutuca:component` contract, and it
/// exists to exercise the part of that contract the other sample guests do
/// not: a DEEP tree of same-bundle children. `ChannelHistory` holds `Thread`s,
/// each holding `Message`s, each holding one `RichText` of `Segment`s and a
/// list of `Reaction`s — five levels of `control.make-instance`, all
/// constructed from ordinary JSON in one `init`.
///
/// Two consequences of the contract shape the design, and both are worth
/// knowing before editing this file:
///
///   1. An instance token is a BRIDGE handle, not a guest pointer. A parent
///      that holds children cannot read them back — `Value::Instance(t)` says
///      nothing about what is behind `t`. So `ChannelHistory` keeps the raw
///      text and timestamps it built each thread FROM (`haystack` / `times`),
///      parallel to the tokens, and filters and orders those. A `@when` filter
///      over the token list could not have worked.
///   2. `href` is a network sink an untrusted bundle may not use
///      (`dyncomp/policy/view_authority.mbt`), so a link segment is styled
///      text that EMITS `openLink` instead of navigating. Whoever is above
///      decides what a URL means; here `ChannelHistory` catches it and says so
///      in its footer. That is still true of a POSTED link, and it is why the
///      avatar is a different case rather than the same one: what a message
///      links to is chosen by whoever wrote it, and what an avatar loads is
///      chosen by Slack. So the host allows external URLs for
///      the three origins Slack actually serves a profile picture from,
///      each written as a literal in `Message`'s view — see `avatar_path` and
///      the README.
///
/// The declaration and views live in manifest.json and views/; sdk.mbt handles
/// the generated ABI declarations.

// --- reading what a constructor was handed --------------------------------

///|
/// A constructor argument by name. Args arrive as an association array
/// because that is the WIT list<tuple<string, value>>; there are never enough
/// of them for the linear scan to matter.
fn arg(args : Array[(String, @values.Value)], name : String) -> @values.Value? {
  for a in args {
    let (k, v) = a
    if k == name {
      return Some(v)
    }
  }
  None
}

///|
fn as_text(v : @values.Value?, default? : String = "") -> String {
  match v {
    Some(@values.Value::Text(s)) => s
    _ => default
  }
}

///|
fn as_bool(v : @values.Value?, default? : Bool = false) -> Bool {
  match v {
    Some(@values.Value::Boolean(b)) => b
    _ => default
  }
}

///|
fn as_num(v : @values.Value?, default? : Double = 0.0) -> Double {
  match v {
    Some(@values.Value::Number(n)) => n
    _ => default
  }
}

///|
/// An arena list materialized into MoonBit. The handles inside stay valid for
/// the rest of THIS host call, which is all a constructor needs.
fn as_items(v : @values.Value?) -> Array[@values.Value] {
  let out : Array[@values.Value] = []
  match v {
    Some(@values.Value::List(h)) =>
      for i in 0U..<@values.list_len(h) {
        out.push(@values.list_get(h, i))
      }
    _ => ()
  }
  out
}

///|
/// A JSON object, read as the constructor args of a child component: the keys
/// a fixture writes ARE the field names the child declares, so no per-component
/// decoder is needed anywhere in this file.
fn args_of(v : @values.Value) -> Array[(String, @values.Value)] {
  let out : Array[(String, @values.Value)] = []
  if v is @values.Value::Map(h) {
    for k in @values.map_keys(h) {
      if @values.map_get(h, k) is Some(child) {
        out.push((k, child))
      }
    }
  }
  out
}

///|
/// A field of a JSON object that arrived as an arena map.
fn field_of(v : @values.Value, name : String) -> @values.Value? {
  match v {
    @values.Value::Map(h) => @values.map_get(h, name)
    _ => None
  }
}

///|
/// The inverse of `instance_list`: a list the HOST is writing back, as tokens.
///
/// `None` unless every element is an instance, which is what makes a write of
/// plain data — a fixture, a form, anything that is not the list this component
/// handed out — a refusal rather than a silently emptied field.
///
/// This is the read side of a write path that only became usable once the host
/// learned to encode a nested child inside a compound value
/// (`dyncomp/host/wasm/glue.mbt`'s `child_json`). Before that, a child in a LIST
/// that returned a successor could not be put back, and the successor was
/// simply lost — the guest counted, and the screen did not.
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
fn instance_list(tokens : Array[UInt64]) -> @values.Value {
  let h = @values.list_new()
  for t in tokens {
    @values.list_push(h, @values.Value::Instance(t))
  }
  @values.Value::List(h)
}

// --- building same-bundle children ----------------------------------------

///|
/// One child from whatever the field held: a token passes through untouched,
/// a JSON object becomes that component's constructor args, and anything else
/// (including a missing field) builds the component's own default.
///
/// `extra` is appended AFTER the object's own keys, so a caller can force a
/// field the fixture did not write — `compact` on a reply, below. It does not
/// reach the pass-through case: an instance the caller was handed is already
/// somebody else's.
fn child(
  component : String,
  v : @values.Value?,
  extra? : Array[(String, @values.Value)] = [],
) -> UInt64 {
  match v {
    Some(@values.Value::Instance(t)) => t
    Some(obj) => @control.make_instance(component, [..args_of(obj), ..extra])
    None => @control.make_instance(component, extra)
  }
}

///|
/// A list field of children, each built the same way.
fn children(
  component : String,
  v : @values.Value?,
  extra? : Array[(String, @values.Value)] = [],
) -> Array[UInt64] {
  let out : Array[UInt64] = []
  for item in as_items(v) {
    out.push(child(component, Some(item), extra~))
  }
  out
}

// --- Segment: one styled run of a message body ----------------------------

///|
priv struct Segment {
  text : String
  bold : Bool
  italic : Bool
  strike : Bool
  code : Bool
  mention : Bool
  channel : Bool
  link : Bool
  url : String
}

///|
/// Composed at render time from eight independent flags, which is why the
/// bundle ships a second, never-rendered view (`views/Segment.margauiClasses.html`):
/// the host's class scanner reads `class=` LITERALS off the compiled views to
/// decide which utility CSS to emit, and a string built here is invisible to it.
fn Segment::seg_class(self : Segment) -> String {
  let out = StringBuilder()
  out.write_string("seg")
  if self.bold {
    out.write_string(" font-bold")
  }
  if self.italic {
    out.write_string(" italic")
  }
  if self.strike {
    out.write_string(" line-through")
  }
  if self.code {
    out.write_string(" font-mono text-sm bg-base-200 rounded px-1")
  }
  if self.mention {
    out.write_string(" text-secondary font-medium")
  }
  if self.channel {
    out.write_string(" text-accent font-medium")
  }
  if self.link {
    out.write_string(" link link-primary cursor-pointer")
  }
  out.to_string()
}

///|
impl DynComponent for Segment with fn get_field(self, name) {
  match name {
    "text" => Some(@values.Value::Text(self.text))
    "bold" => Some(@values.Value::Boolean(self.bold))
    "italic" => Some(@values.Value::Boolean(self.italic))
    "strike" => Some(@values.Value::Boolean(self.strike))
    "code" => Some(@values.Value::Boolean(self.code))
    "mention" => Some(@values.Value::Boolean(self.mention))
    "channel" => Some(@values.Value::Boolean(self.channel))
    "link" => Some(@values.Value::Boolean(self.link))
    "url" => Some(@values.Value::Text(self.url))
    _ => None
  }
}

///|
impl DynComponent for Segment with fn call_method(self, name, _args) {
  match name {
    "segClass" => @values.Value::Text(self.seg_class())
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Segment with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    // A link segment cannot navigate: `href` is refused for an untrusted
    // bundle, so the URL travels UP and whoever is above decides. That is the
    // same shape as asking the host over an intent, one level cheaper.
    (RECEIVE, "open") => {
      if self.link && self.url != "" {
        @control.intent(
          "openLink",
          [@values.Value::Text(self.url), @values.Value::Text(self.text)],
          {
            route: [DYN],
            on_ok: None,
            on_error: None,
            on_unhandled: None,
            live_path: false,
          },
        )
      }
      Unchanged
    }
    _ => Unhandled
  }
}

///|
/// Every field is scalar, so the host's generated mutators (`setText`,
/// `toggleBold`, …) all work — which is what makes a Segment editable in a
/// storybook without this bundle declaring a single input handler for it.
impl DynComponent for Segment with fn with_field(self, name, v) {
  let next : Segment? = match (name, v) {
    ("text", @values.Value::Text(s)) => Some({ ..self, text: s })
    ("bold", @values.Value::Boolean(b)) => Some({ ..self, bold: b })
    ("italic", @values.Value::Boolean(b)) => Some({ ..self, italic: b })
    ("strike", @values.Value::Boolean(b)) => Some({ ..self, strike: b })
    ("code", @values.Value::Boolean(b)) => Some({ ..self, code: b })
    ("mention", @values.Value::Boolean(b)) => Some({ ..self, mention: b })
    ("channel", @values.Value::Boolean(b)) => Some({ ..self, channel: b })
    ("link", @values.Value::Boolean(b)) => Some({ ..self, link: b })
    ("url", @values.Value::Text(s)) => Some({ ..self, url: s })
    _ => None
  }
  match next {
    Some(s) => Some(s as &DynComponent)
    None => None
  }
}

///|
fn make_segment(args : Array[(String, @values.Value)]) -> &DynComponent {
  let s : Segment = {
    text: as_text(arg(args, "text")),
    bold: as_bool(arg(args, "bold")),
    italic: as_bool(arg(args, "italic")),
    strike: as_bool(arg(args, "strike")),
    code: as_bool(arg(args, "code")),
    mention: as_bool(arg(args, "mention")),
    channel: as_bool(arg(args, "channel")),
    link: as_bool(arg(args, "link")),
    url: as_text(arg(args, "url")),
  }
  s as &DynComponent
}

// --- RichText: a message body as a flat list of segments ------------------

///|
priv struct RichText {
  segments : Array[UInt64]
}

///|
impl DynComponent for RichText with fn get_field(self, name) {
  match name {
    "segments" => Some(instance_list(self.segments))
    _ => None
  }
}

///|
fn make_rich_text(args : Array[(String, @values.Value)]) -> &DynComponent {
  let r : RichText = { segments: children("Segment", arg(args, "segments")) }
  r as &DynComponent
}

// --- Reaction: one emoji with its count -----------------------------------

///|
priv struct Reaction {
  emoji : String
  count : Double
  reacted : Bool
}

///|
impl DynComponent for Reaction with fn get_field(self, name) {
  match name {
    "emoji" => Some(@values.Value::Text(self.emoji))
    "count" => Some(@values.Value::Number(self.count))
    "reacted" => Some(@values.Value::Boolean(self.reacted))
    _ => None
  }
}

///|
impl DynComponent for Reaction with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    // Both halves: the count is this component's own state, and the fact that
    // somebody reacted is news for whoever is above.
    (RECEIVE, "toggle") => {
      let reacted = !self.reacted
      let count = if reacted { self.count + 1.0 } else { self.count - 1.0 }
      @control.intent(
        "reacted",
        [@values.Value::Text(self.emoji), @values.Value::Boolean(reacted)],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Changed({ ..self, reacted, count } as &DynComponent)
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for Reaction with fn with_field(self, name, v) {
  let next : Reaction? = match (name, v) {
    ("emoji", @values.Value::Text(s)) => Some({ ..self, emoji: s })
    ("count", @values.Value::Number(n)) => Some({ ..self, count: n })
    ("reacted", @values.Value::Boolean(b)) => Some({ ..self, reacted: b })
    _ => None
  }
  match next {
    Some(r) => Some(r as &DynComponent)
    None => None
  }
}

///|
fn make_reaction(args : Array[(String, @values.Value)]) -> &DynComponent {
  let r : Reaction = {
    emoji: as_text(arg(args, "emoji"), default="👍"),
    count: as_num(arg(args, "count"), default=1.0),
    reacted: as_bool(arg(args, "reacted")),
  }
  r as &DynComponent
}

// --- Message: one message, root or (compact) reply ------------------------

///|
priv struct Message {
  id : String
  author : String
  /// The author's picture, as the full url a Slack profile carries in
  /// `image_48` / `image_72`. Kept as it arrived; `avatar_path` is what
  /// decides whether any of it can be drawn.
  avatar : String
  channel_name : String
  created_at : String
  body : UInt64
  reactions : Array[UInt64]
  compact : Bool
  edited : Bool
  pinned : Bool
  /// The workspace archive link for this message, as whoever built the card
  /// derived it.
  ///
  /// Shown and clickable, and still NOT an `href` — for the reason the header
  /// gives about posted links, arriving here from the other direction. A
  /// permalink is `https://<team>.slack.com/archives/…`, and the subdomain is
  /// the workspace's: there is no origin a view can write as a literal, so
  /// there is nothing for the external-URL allowance to be spent on. Clicking it emits
  /// `openLink`, exactly as a link segment does, and whoever is above decides
  /// what opening it means.
  permalink : String
}

///|
/// "2026-06-23T09:12:00Z" -> "09:12". No clock anywhere near it: the
/// timestamp is data the message arrived with, and slicing a string it already
/// holds is not a fact about the world.
fn clock_of(created_at : String) -> String {
  if created_at.length() >= 16 && created_at[10:11] == "T" {
    created_at[11:16].to_owned()
  } else {
    created_at
  }
}

///|
impl DynComponent for Message with fn get_field(self, name) {
  match name {
    "id" => Some(@values.Value::Text(self.id))
    "author" => Some(@values.Value::Text(self.author))
    "avatar" => Some(@values.Value::Text(self.avatar))
    "channelName" => Some(@values.Value::Text(self.channel_name))
    "createdAt" => Some(@values.Value::Text(self.created_at))
    "body" => Some(@values.Value::Instance(self.body))
    "reactions" => Some(instance_list(self.reactions))
    "compact" => Some(@values.Value::Boolean(self.compact))
    "edited" => Some(@values.Value::Boolean(self.edited))
    "pinned" => Some(@values.Value::Boolean(self.pinned))
    "permalink" => Some(@values.Value::Text(self.permalink))
    _ => None
  }
}

///|
/// The three origins Slack serves a profile picture from, each of which is
/// also written out as a literal in `views/Message.main.html`.
///
/// Three rather than one because Slack really does use three: a workspace
/// upload comes back on `avatars.slack-edge.com`, the same file reached through
/// the workspace CDN on `ca.slack-edge.com`, and an account that never uploaded
/// one gets its default from `secure.gravatar.com`. A bundle that named only
/// the first would draw initials for half a real channel.
///
/// The trailing slash on each is the whole check, not punctuation: without it
/// `https://ca.slack-edge.com.attacker.test/x` and
/// `https://ca.slack-edge.com@attacker.test/x` both pass a prefix test and both
/// are somebody else's host. It is the same boundary the host insists on when
/// it reads the origin off the view (`dyncomp/policy/external_url.mbt`).
const SLACK_CDN = "https://ca.slack-edge.com/"

///|
const SLACK_AVATARS = "https://avatars.slack-edge.com/"

///|
const GRAVATAR = "https://secure.gravatar.com/"

///|
/// What is left of the message's avatar url once `origin` is taken off the
/// front, or `""` when the picture is somewhere else — including a relative
/// url, which is a request to the HOST's origin and not this bundle's to make.
///
/// This is the guest's half of the external-URL rule: the view names the origin,
/// this decides that the profile's url is actually ON it, and what crosses
/// between them is a path. A picture that fails all three tests is not drawn,
/// and the initials underneath it are what shows — which is what every message
/// showed before this bundle could load a picture at all.
fn avatar_path(avatar : String, origin : String) -> String {
  guard avatar.has_prefix(origin) else { return "" }
  avatar[origin.length():].to_owned()
}

///|
/// The avatar under the picture: up to two initials off whatever name the
/// message arrived with.
///
/// Not the fallback in the sense of a branch — the view draws the image OVER
/// this disc, so a message with no picture, a picture on an origin no view
/// names, and a fetch that fails anyway all land on the same two letters. An
/// untrusted view has no `onerror` to write, and does not need one.
///
/// What a reader uses an avatar for is telling one speaker's run of messages
/// from the next one's at a glance, and a disc with two letters in it does that
/// on its own. `bluesky/Post` draws the same thing for the same reason, and
/// this is its twin rather than its cousin.
///
/// One initial per word, so `Ada Lovelace` is `AL` and a one-word name is one
/// letter — the convention a reader already knows, and the same rule `bluesky`
/// applies, so a host drawing both does not draw two different kinds of disc.
fn initials_of(author : String) -> String {
  let buf = StringBuilder()
  let mut taken = 0
  let mut fresh = true
  for c in author.iter() {
    if c == ' ' || c == '.' || c == '-' || c == '_' || c == '@' {
      fresh = true
      continue
    }
    if fresh && taken < 2 {
      buf.write_char(upper_char(c))
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
/// ASCII only, deliberately: full Unicode upper-casing needs a table this bundle
/// has no reason to carry, and a letter outside ASCII is drawn as written rather
/// than mangled.
fn upper_char(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    Char::from_int(c.to_int() - 32)
  } else {
    c
  }
}

///|
impl DynComponent for Message with fn call_method(self, name, _args) {
  match name {
    "initials" => @values.Value::Text(initials_of(self.author))
    // One per origin the view names, and only one of them is ever non-empty:
    // the view shows the image whose path it got, and nothing at all when it
    // got none.
    "slackCdnPath" => @values.Value::Text(avatar_path(self.avatar, SLACK_CDN))
    "slackAvatarsPath" =>
      @values.Value::Text(avatar_path(self.avatar, SLACK_AVATARS))
    "gravatarPath" => @values.Value::Text(avatar_path(self.avatar, GRAVATAR))
    "authorLabel" =>
      @values.Value::Text(
        if self.author == "" {
          "@someone"
        } else {
          "@\{self.author}"
        },
      )
    "channelLabel" => @values.Value::Text("#\{self.channel_name}")
    // A reply already sits under its root's channel badge, so it does not
    // repeat it — the one place `compact` means more than styling.
    "hasChannel" =>
      @values.Value::Boolean(!self.compact && self.channel_name != "")
    "timeLabel" => @values.Value::Text(clock_of(self.created_at))
    // The `ts`, drawn rather than only carried.
    //
    // It is the ARGUMENT every follow-up tool takes — read the thread, react,
    // link — and it lived in a field no view mentioned, so a reader who wanted
    // one had to retype it off the prose beside the card and get it wrong.
    // Drawing it is the cheapest fix to the most expensive mistake this bundle
    // was making.
    "hasId" => @values.Value::Boolean(self.id != "")
    "idTitle" =>
      @values.Value::Text(
        if self.id == "" {
          ""
        } else {
          "ts \{self.id} — the timestamp every follow-up call takes"
        },
      )
    "hasPermalink" => @values.Value::Boolean(self.permalink != "")
    _ => @values.Value::Nil
  }
}

///|
/// The permalink travels UP rather than being followed, the same way a link
/// somebody posted does.
///
/// The two are the same case arrived at from opposite directions: a posted link
/// points wherever its author chose, and a permalink points at a workspace whose
/// subdomain is not known when the view is registered. Neither is an origin a
/// view can write as a literal, so neither is an `href` an untrusted bundle may
/// have — and both are perfectly good things to announce.
impl DynComponent for Message with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    (RECEIVE, "openPermalink") => {
      if self.permalink != "" {
        @control.intent(
          "openLink",
          [
            @values.Value::Text(self.permalink),
            @values.Value::Text("permalink"),
          ],
          {
            route: [DYN],
            on_ok: None,
            on_error: None,
            on_unhandled: None,
            live_path: false,
          },
        )
      }
      Unchanged
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for Message with fn with_field(self, name, v) {
  let next : Message? = match (name, v) {
    ("id", @values.Value::Text(s)) => Some({ ..self, id: s })
    ("author", @values.Value::Text(s)) => Some({ ..self, author: s })
    ("avatar", @values.Value::Text(s)) => Some({ ..self, avatar: s })
    ("channelName", @values.Value::Text(s)) => Some({ ..self, channel_name: s })
    ("createdAt", @values.Value::Text(s)) => Some({ ..self, created_at: s })
    ("compact", @values.Value::Boolean(b)) => Some({ ..self, compact: b })
    ("edited", @values.Value::Boolean(b)) => Some({ ..self, edited: b })
    ("pinned", @values.Value::Boolean(b)) => Some({ ..self, pinned: b })
    ("permalink", @values.Value::Text(s)) => Some({ ..self, permalink: s })
    // The child write-back path: a `Reaction` that counted itself up returns a
    // successor, and the host puts the whole list back through here.
    ("body", @values.Value::Instance(t)) => Some({ ..self, body: t })
    ("reactions", _) =>
      match tokens_of(v) {
        Some(reactions) => Some({ ..self, reactions, })
        None => None
      }
    _ => None
  }
  match next {
    Some(m) => Some(m as &DynComponent)
    None => None
  }
}

///|
fn make_message(args : Array[(String, @values.Value)]) -> &DynComponent {
  let m : Message = {
    id: as_text(arg(args, "id")),
    author: as_text(arg(args, "author")),
    avatar: as_text(arg(args, "avatar")),
    channel_name: as_text(arg(args, "channelName")),
    created_at: as_text(arg(args, "createdAt")),
    body: child("RichText", body_args(arg(args, "body"))),
    reactions: children("Reaction", arg(args, "reactions")),
    compact: as_bool(arg(args, "compact")),
    edited: as_bool(arg(args, "edited")),
    pinned: as_bool(arg(args, "pinned")),
    permalink: as_text(arg(args, "permalink")),
  }
  m as &DynComponent
}

///|
/// `body` accepts both shapes a fixture wants to write: the RichText object
/// (`{"segments": […]}`) and the bare segment list (`[…]`), which is what a
/// message reads like when nobody is thinking about components.
fn body_args(v : @values.Value?) -> @values.Value? {
  match v {
    Some(@values.Value::List(_) as list) => {
      let h = @values.map_new()
      @values.map_set(h, "segments", list)
      Some(@values.Value::Map(h))
    }
    other => other
  }
}

// --- Paging: a window over a list that arrived long ------------------------
//
// Three of the components below are a column of something: a thread's replies,
// a channel's conversations, a channel's files. How long that column is was
// never theirs to decide — a caller asks for a history with a `limit` and gets
// back whatever it allowed. Forty rows is a card. Four hundred is a wall a
// reader scrolls past rather than reads, and for the two that build children it
// is four hundred child components drawn before any one of them is looked at.
//
// So a long list gets a window and the four buttons that move it, in the
// vocabulary the `table` bundle already uses for the same job — `page`,
// `pageCount`, `pageSize`, `firstPage` / `prevPage` / `nextPage` / `lastPage`,
// `atFirst` / `atLast` — because a host drawing this card beside the bluesky or
// mastodon one should not have to learn three spellings of "show me the next
// lot".
//
// The window is over what the FILTER left, not over the records: the search box
// narrows and the pager pages what is left, which is the order a reader means
// when they type in the box while on page three. Nothing here rebuilds a child,
// so what a reader did to a message is still there when the page comes back.

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
/// are not the component's to keep: `total` is what the filter left, which moves
/// as a reader types, and `page` is a wish that has to be brought back inside a
/// list that may have shrunk under it.
priv struct Pager {
  /// 0-based, and already clamped to what `total` and the window allow.
  page : Int
  /// How many rows a page holds. In effect whether or not it is being used, so
  /// `pageSize` reads back the same either way.
  size : Int
  /// Whether the list is long enough that a page is a window rather than the
  /// whole of it.
  on : Bool
  /// How many rows there are to page through: after the filter, before the
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
/// The positions this page shows, out of the ones the filter left.
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
    "page" => Some(@values.Value::Number((self.page + 1).to_double()))
    "pageCount" => Some(@values.Value::Number(self.pages().to_double()))
    "pageSize" => Some(@values.Value::Number(self.size.to_double()))
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
    "pageLabel" =>
      Some(@values.Value::Text("\{self.page + 1} of \{self.pages()}"))
    // Which rows these are, which is the half a page number does not say.
    "rangeLabel" => {
      guard self.on else { return Some(@values.Value::Text("")) }
      let first = self.page * self.size + 1
      let last = if first + self.size - 1 < self.total {
        first + self.size - 1
      } else {
        self.total
      }
      Some(@values.Value::Text("\{first}–\{last} of \{self.total}"))
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
/// Every position in a list of `n`, for the components with no filter to narrow
/// one: a page is the only thing between their rows and the screen.
fn all_positions(n : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<n {
    out.push(i)
  }
  out
}

// --- Thread: a root message and its replies -------------------------------

///|
priv struct Thread {
  root : UInt64
  replies : Array[UInt64]
  expanded : Bool
  /// How many replies EXIST, which is not how many arrived.
  ///
  /// The two came apart the moment a channel history became a card:
  /// `conversations.history` answers with roots carrying a `reply_count` and
  /// never with the replies themselves, so every message became a thread with
  /// "21 replies" written on it and nothing behind the caret. This field is what
  /// the count means, and `replies.length()` is what is loaded — a thread that
  /// was told nothing takes the second as the first, which is what a fully-read
  /// thread already is.
  reply_count : Int
  /// Where the root lives, so a thread with unloaded replies can say the two
  /// arguments that would load them.
  ///
  /// Kept HERE rather than read off the root `Message`, because a token is a
  /// bridge handle and a parent holding one cannot read a field behind it — the
  /// same constraint that makes `ChannelHistory` keep `haystack` and `times`.
  channel_name : String
  root_ts : String
  /// Which page of the replies is on screen, 0-based. A thread on a busy
  /// channel is the one list here that arrives long without anybody asking for
  /// it.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
/// The pager over the replies that ARE here. `reply_count` is how many exist,
/// which is a different number and not one a window can be cut out of.
fn Thread::pager(self : Thread) -> Pager {
  paging(self.page, self.replies.length(), self.page_size)
}

///|
/// The positions on this page.
fn Thread::shown(self : Thread) -> Array[Int] {
  self.pager().slice(all_positions(self.replies.length()))
}

///|
impl DynComponent for Thread with fn get_field(self, name) {
  match name {
    "root" => Some(@values.Value::Instance(self.root))
    "replies" => {
      let shown : Array[UInt64] = []
      for i in self.shown() {
        shown.push(self.replies[i])
      }
      Some(instance_list(shown))
    }
    "expanded" => Some(@values.Value::Boolean(self.expanded))
    "replyCount" => Some(@values.Value::Number(self.reply_count.to_double()))
    "channelName" => Some(@values.Value::Text(self.channel_name))
    "rootTs" => Some(@values.Value::Text(self.root_ts))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for Thread with fn call_method(self, name, _args) {
  match name {
    // The caret is for replies that are HERE. A count with nothing behind it
    // got one anyway until this split existed, and a caret that expands onto
    // nothing is the dead end that sent a reader off to retype a timestamp.
    "hasReplies" => @values.Value::Boolean(!self.replies.is_empty())
    "hasUnloadedReplies" =>
      @values.Value::Boolean(self.replies.is_empty() && self.reply_count > 0)
    "replyLabel" => {
      let caret = if self.expanded { "▾" } else { "▸" }
      let loaded = self.replies.length()
      let noun = if self.reply_count == 1 { "reply" } else { "replies" }
      // A page of a long thread says it is a page. Claiming "3 replies" for the
      // three that arrived out of twenty-one is the same silence one level down.
      if self.reply_count > loaded {
        @values.Value::Text("\{caret} \{loaded} of \{self.reply_count} \{noun}")
      } else {
        @values.Value::Text("\{caret} \{loaded} \{noun}")
      }
    }
    "loadLabel" => {
      let noun = if self.reply_count == 1 { "reply" } else { "replies" }
      @values.Value::Text("\{self.reply_count} \{noun} — not loaded")
    }
    // What to call for them, spelled out with both arguments filled in. The
    // whole failure this addresses is a reader who had the count and had to
    // guess the timestamp; a card that CAN say it should say it.
    "loadTitle" =>
      @values.Value::Text(
        if self.root_ts == "" {
          "the replies were not fetched with this message"
        } else if self.channel_name == "" {
          "read them with ts=\{self.root_ts}"
        } else {
          "read them with channel=\{self.channel_name}, ts=\{self.root_ts}"
        },
      )
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for Thread with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    (RECEIVE, "toggle") =>
      Changed({ ..self, expanded: !self.expanded } as &DynComponent)
    // The replies are not here and this bundle cannot go and get them: it has
    // no network, and the whole point of that is that it is checkable by
    // looking. So it says which two arguments would, and whoever is above is
    // the one that can make the call.
    (RECEIVE, "openThread") => {
      @control.intent(
        "openThread",
        [
          @values.Value::Text(self.channel_name),
          @values.Value::Text(self.root_ts),
          @values.Value::Number(self.reply_count.to_double()),
        ],
        {
          route: [DYN],
          on_ok: None,
          on_error: None,
          on_unhandled: None,
          live_path: false,
        },
      )
      Unchanged
    }
    // What `ChannelHistory`'s expand-all/collapse-all reaches with
    // `control.send-at`: a receive rather than an input, because it is not
    // this component's own button that raised it.
    (RECEIVE, "setExpanded") =>
      match args {
        [@values.Value::Boolean(b), ..] =>
          Changed({ ..self, expanded: b } as &DynComponent)
        _ => Unchanged
      }
    // The pager under the replies. A page moves nothing but which of them are
    // drawn, so no child is rebuilt and nothing is announced.
    (RECEIVE, _) => {
      guard is_page_message(name) else { return Unhandled }
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for Thread with fn with_field(self, name, v) {
  match (name, v) {
    ("expanded", @values.Value::Boolean(b)) =>
      Some({ ..self, expanded: b } as &DynComponent)
    ("root", @values.Value::Instance(t)) =>
      Some({ ..self, root: t } as &DynComponent)
    ("replyCount", @values.Value::Number(n)) =>
      Some({ ..self, reply_count: n.to_int() } as &DynComponent)
    ("channelName", @values.Value::Text(s)) =>
      Some({ ..self, channel_name: s } as &DynComponent)
    ("rootTs", @values.Value::Text(s)) =>
      Some({ ..self, root_ts: s } as &DynComponent)
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 } as &DynComponent)
    // Writing the replies home does NOT move the count: how many exist is a
    // fact about the conversation, and how many are on screen is a fact about
    // this page of it.
    //
    // Two different writes arrive here, and the length is what tells them
    // apart. `replies` is a DECLARED field, so a host may hand back the page it
    // was shown with a successor in it — which goes home by position, through
    // the same function that decided those positions — or a whole new list,
    // which is what happens when whoever heard `openThread` went and fetched
    // the replies this card never had. The second starts at the first page,
    // because it is a different conversation's worth of rows.
    ("replies", _) =>
      match tokens_of(v) {
        Some(shown) => {
          let at = self.shown()
          if at.length() != shown.length() {
            Some({ ..self, replies: shown, page: 0 } as &DynComponent)
          } else {
            let replies = self.replies.copy()
            for k, i in at {
              replies[i] = shown[k]
            }
            Some({ ..self, replies, } as &DynComponent)
          }
        }
        None => None
      }
    _ => None
  }
}

///|
fn make_thread(args : Array[(String, @values.Value)]) -> &DynComponent {
  // A reply is compact whatever the fixture says, the way `fromData` forced it
  // in the original: "is this a reply" is a fact about POSITION, and the thread
  // is the only one that knows it.
  let replies = children("Message", arg(args, "replies"), extra=[
    ("compact", @values.Value::Boolean(true)),
  ])
  let root_args = arg(args, "root")
  let t : Thread = {
    root: child("Message", root_args),
    replies,
    expanded: as_bool(arg(args, "expanded"), default=true),
    // Told, or taken from what arrived — which for a thread that was read whole
    // is the same number.
    reply_count: as_num(
      arg(args, "replyCount"),
      default=replies.length().to_double(),
    ).to_int(),
    // The root's own fields are the default, because they are the same fact and
    // a caller writing the message should not have to write it twice. Read off
    // the JSON while it is still JSON: once the root is a token, it is gone.
    channel_name: match arg(args, "channelName") {
      Some(@values.Value::Text(s)) => s
      _ => root_text(root_args, "channelName")
    },
    root_ts: match arg(args, "rootTs") {
      Some(@values.Value::Text(s)) => s
      _ => root_text(root_args, "id")
    },
    page: 0,
    page_size: as_num(arg(args, "pageSize")).to_int(),
  }
  t as &DynComponent
}

///|
/// One string off the root message's own constructor JSON. `""` when the root
/// arrived as an instance the caller built elsewhere — a token says nothing
/// about what is behind it, and guessing would be worse than an empty label.
fn root_text(root : @values.Value?, key : String) -> String {
  match root {
    Some(obj) => as_text(field_of(obj, key))
    None => ""
  }
}

// --- Scope: what the answer above it does NOT cover ------------------------

///|
/// The disclosure that an answer is partial.
///
/// Every read here answers from a token, and a token sees a SLICE of a
/// workspace: the public channels, the private ones it was invited to, and the
/// DMs belonging to whoever it is. Nothing in a list of results says which slice
/// produced it, and that silence is the most dangerous thing these cards do —
/// not because anything in them is wrong, but because "no results" and "no
/// results in the part I can see" look identical, and only one of them means
/// what it appears to mean.
///
/// It is not an error and not a warning. It is the sentence that turns a count
/// into a claim someone can check, and it existed in the prose long before it
/// existed here, which made the card the more confident of the two while being
/// the less informed.
///
/// Its twin lives in the bluesky bundle with that protocol's vocabulary. The two
/// are deliberately not one component: what a slack answer leaves out is
/// conversations, and what an ATProto answer leaves out is pages of an index.
priv struct Scope {
  public_channels : Bool
  private_channels : Bool
  /// False by default, and that is a statement about these TOOLS rather than
  /// about the token: `conversations.list` is asked for public and private
  /// channels, so an `im` is never in the set, whatever the token could see.
  dms : Bool
  /// How many conversations were actually read. Negative for "nobody counted",
  /// which is not the same as zero.
  channels_scanned : Double
  /// A cap stopped the scan before the data ran out. The single most important
  /// field: the difference between "there is no more" and "I stopped looking".
  truncated : Bool
  /// What stopped it, in the caller's own words: `limit`, `max_search_channels`.
  truncated_by : String
  /// Anything else worth saying, in one sentence.
  note : String
}

///|
fn Scope::has_any(self : Scope) -> Bool {
  self.truncated || !self.dms || self.note != "" || self.channels_scanned >= 0.0
}

///|
impl DynComponent for Scope with fn get_field(self, name) {
  match name {
    "publicChannels" => Some(@values.Value::Boolean(self.public_channels))
    "privateChannels" => Some(@values.Value::Boolean(self.private_channels))
    "dms" => Some(@values.Value::Boolean(self.dms))
    "channelsScanned" => Some(@values.Value::Number(self.channels_scanned))
    "truncated" => Some(@values.Value::Boolean(self.truncated))
    "truncatedBy" => Some(@values.Value::Text(self.truncated_by))
    "note" => Some(@values.Value::Text(self.note))
    _ => None
  }
}

///|
impl DynComponent for Scope with fn call_method(self, name, _args) {
  match name {
    "hasAny" => @values.Value::Boolean(self.has_any())
    "kindsLabel" =>
      @values.Value::Text(
        if self.public_channels && self.private_channels {
          "public channels, and the private ones this token is in"
        } else if self.public_channels {
          "public channels only"
        } else if self.private_channels {
          "private channels only"
        } else {
          "no channels"
        },
      )
    "hasScanned" => @values.Value::Boolean(self.channels_scanned >= 0.0)
    "scannedLabel" => {
      let n = self.channels_scanned.to_int()
      @values.Value::Text(
        if n == 1 {
          "1 conversation read"
        } else {
          "\{n} conversations read"
        },
      )
    }
    // The absence is the disclosure. A card that lists what it DID cover and
    // says nothing about DMs reads as covering everything.
    "hasDmNote" => @values.Value::Boolean(!self.dms)
    "dmLabel" => @values.Value::Text("DMs and group DMs are never included")
    "truncatedLabel" =>
      @values.Value::Text(
        if !self.truncated {
          ""
        } else if self.truncated_by == "" {
          "stopped early — this is not the whole workspace"
        } else {
          "stopped at the \{self.truncated_by} cap — this is not the whole workspace"
        },
      )
    "summary" => {
      let parts : Array[String] = []
      parts.push(
        if self.public_channels && self.private_channels {
          "public channels and the private channels this token is in"
        } else if self.public_channels {
          "public channels only"
        } else if self.private_channels {
          "private channels only"
        } else {
          "no channels"
        },
      )
      if self.channels_scanned >= 0.0 {
        parts.push("\{self.channels_scanned.to_int()} scanned")
      }
      if !self.dms {
        parts.push("DMs and group DMs are never included")
      }
      if self.truncated {
        parts.push(
          if self.truncated_by == "" {
            "stopped early, so this is not the whole workspace"
          } else {
            "stopped early at the \{self.truncated_by} cap, so this is not the whole workspace"
          },
        )
      }
      if self.note != "" {
        parts.push(self.note)
      }
      @values.Value::Text("scope: " + parts.join("; "))
    }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Scope with fn with_field(self, name, v) {
  let next : Scope? = match (name, v) {
    ("publicChannels", @values.Value::Boolean(b)) =>
      Some({ ..self, public_channels: b })
    ("privateChannels", @values.Value::Boolean(b)) =>
      Some({ ..self, private_channels: b })
    ("dms", @values.Value::Boolean(b)) => Some({ ..self, dms: b })
    ("channelsScanned", @values.Value::Number(n)) =>
      Some({ ..self, channels_scanned: n })
    ("truncated", @values.Value::Boolean(b)) => Some({ ..self, truncated: b })
    ("truncatedBy", @values.Value::Text(s)) => Some({ ..self, truncated_by: s })
    ("note", @values.Value::Text(s)) => Some({ ..self, note: s })
    _ => None
  }
  match next {
    Some(s) => Some(s as &DynComponent)
    None => None
  }
}

///|
fn make_scope(args : Array[(String, @values.Value)]) -> &DynComponent {
  let s : Scope = {
    public_channels: as_bool(arg(args, "publicChannels"), default=true),
    private_channels: as_bool(arg(args, "privateChannels")),
    dms: as_bool(arg(args, "dms")),
    // -1 rather than 0: an answer that counted nothing and an answer that read
    // no conversations are different answers.
    channels_scanned: as_num(arg(args, "channelsScanned"), default=-1.0),
    truncated: as_bool(arg(args, "truncated")),
    truncated_by: as_text(arg(args, "truncatedBy")),
    note: as_text(arg(args, "note")),
  }
  s as &DynComponent
}

///|
/// The `Scope` child a surface hangs under itself, and whether it has anything
/// to say.
///
/// One is always built, even for an answer with no scope at all — an
/// always-present child that draws nothing is simpler to reason about than an
/// optional one. Whether to DRAW it comes back beside the token rather than out
/// of the child, because a token is a bridge handle and a parent holding one
/// cannot read a field behind it.
fn scope_child(v : @values.Value?) -> (UInt64, Bool) {
  match v {
    Some(@values.Value::Map(_) as obj) =>
      (@control.make_instance("Scope", args_of(obj)), true)
    // Not "a scope with default values" — no scope at all. A card whose builder
    // said nothing about coverage should not grow a coverage box out of
    // defaults it was never given.
    _ => (@control.make_instance("Scope", []), false)
  }
}

// --- FileList: the files a search or a channel turned up -------------------

///|
/// One file's metadata, flattened for a row.
///
/// Metadata only, and that is the tool's limit rather than this component's: the
/// slack package implements no binary transfer, so nothing anywhere in this
/// bundle can hand anybody a file's contents. A row therefore says what the file
/// IS and where it lives, and the link travels up like every other link here.
priv struct FileRow {
  id : String
  label : String
  mimetype : String
  /// Bytes, as they arrived. Negative for a file that did not say.
  size : Double
  author : String
  created_at : String
  permalink : String
}

///|
/// A file list, as one component rather than one component per row.
///
/// The other lists in this bundle are components of components because their
/// rows CONTAIN a loop — a message has segments and reactions, and a view cannot
/// iterate a value it found inside another iteration. A file row contains
/// nothing, so it is an `@each` over flat records and the bundle stays five
/// components deep instead of six.
priv struct FileList {
  /// What was being listed, for the header: a channel name, a user, `""` for
  /// the whole workspace the token can see.
  filter : String
  files : Array[FileRow]
  scope : UInt64
  has_scope : Bool
  /// Which page of the list is on screen, 0-based.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
/// The pager over the files.
fn FileList::pager(self : FileList) -> Pager {
  paging(self.page, self.files.length(), self.page_size)
}

///|
/// The positions on this page. A row is a record rather than a child here, so
/// these are also what `openFile` looks a row up by: `@key` counts the rows the
/// view was given, which on page two is not where the file is.
fn FileList::shown(self : FileList) -> Array[Int] {
  self.pager().slice(all_positions(self.files.length()))
}

///|
fn file_row_of(v : @values.Value) -> FileRow {
  let title = as_text(field_of(v, "title"))
  let filename = as_text(field_of(v, "name"))
  let id = as_text(field_of(v, "id"))
  {
    id,
    // Slack's own order: a file's title is what somebody typed and its name is
    // what the upload was called. Either beats the id, and the id beats blank.
    label: if title != "" {
      title
    } else if filename != "" {
      filename
    } else {
      id
    },
    mimetype: as_text(field_of(v, "mimetype")),
    size: as_num(field_of(v, "size"), default=-1.0),
    author: as_text(field_of(v, "author")),
    created_at: as_text(field_of(v, "createdAt")),
    permalink: as_text(field_of(v, "permalink")),
  }
}

///|
/// A byte count as somebody reads one. Integer arithmetic on the way down, so
/// the label never depends on how a double prints.
fn size_label(bytes : Double) -> String {
  if bytes < 0.0 {
    return ""
  }
  let n = bytes.to_int()
  if n < 1024 {
    return "\{n} B"
  }
  if n < 1024 * 1024 {
    return "\{scaled_by(n, 1024)} KB"
  }
  if n < 1024 * 1024 * 1024 {
    return "\{scaled_by(n, 1024 * 1024)} MB"
  }
  "\{scaled_by(n, 1024 * 1024 * 1024)} GB"
}

///|
/// `n / unit` to one decimal, without a float in sight.
fn scaled_by(n : Int, unit : Int) -> String {
  let whole = n / unit
  let tenth = n % unit * 10 / unit
  if whole < 10 && tenth > 0 {
    "\{whole}.\{tenth}"
  } else {
    "\{whole}"
  }
}

///|
impl DynComponent for FileList with fn get_field(self, name) {
  match name {
    "filter" => Some(@values.Value::Text(self.filter))
    "files" => {
      let h = @values.list_new()
      for f in self.files {
        let m = @values.map_new()
        @values.map_set(m, "id", @values.Value::Text(f.id))
        @values.map_set(m, "label", @values.Value::Text(f.label))
        @values.map_set(m, "mimetype", @values.Value::Text(f.mimetype))
        @values.map_set(m, "size", @values.Value::Number(f.size))
        @values.map_set(m, "author", @values.Value::Text(f.author))
        @values.map_set(m, "createdAt", @values.Value::Text(f.created_at))
        @values.map_set(m, "permalink", @values.Value::Text(f.permalink))
        @values.list_push(h, @values.Value::Map(m))
      }
      Some(@values.Value::List(h))
    }
    // What a ROW draws: everything already spelled the way it goes on screen, so
    // the view stays a template and does no arithmetic.
    "rows" => {
      let h = @values.list_new()
      for at in self.shown() {
        let f = self.files[at]
        let m = @values.map_new()
        @values.map_set(m, "id", @values.Value::Text(f.id))
        @values.map_set(m, "label", @values.Value::Text(f.label))
        @values.map_set(m, "kind", @values.Value::Text(f.mimetype))
        @values.map_set(m, "size", @values.Value::Text(size_label(f.size)))
        @values.map_set(
          m,
          "by",
          @values.Value::Text(if f.author == "" { "" } else { "@\{f.author}" }),
        )
        @values.map_set(m, "time", @values.Value::Text(clock_of(f.created_at)))
        @values.map_set(m, "linked", @values.Value::Boolean(f.permalink != ""))
        @values.map_set(m, "permalink", @values.Value::Text(f.permalink))
        @values.list_push(h, @values.Value::Map(m))
      }
      Some(@values.Value::List(h))
    }
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(@values.Value::Boolean(self.has_scope))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for FileList with fn call_method(self, name, _args) {
  match name {
    "title" =>
      @values.Value::Text(
        if self.filter == "" {
          "Files"
        } else {
          "Files in \{self.filter}"
        },
      )
    "countLabel" => {
      let n = self.files.length()
      @values.Value::Text(if n == 1 { "1 file" } else { "\{n} files" })
    }
    "isEmpty" => @values.Value::Boolean(self.files.is_empty())
    // Said once, on the list rather than on every row: the bytes are not here,
    // and a card that looked like it could open a file and could not would be
    // worse than one that never suggested it.
    "note" =>
      @values.Value::Text("file contents are not available through this server")
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for FileList with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    // The row's index, not its url: `@key` is what a loop can hand a handler,
    // and looking the row up here means the view never carries a link it might
    // pass to the wrong component.
    (RECEIVE, "openFile") => {
      // The index is into the rows the view was GIVEN, which on page two are
      // not the first rows of the list — so it is read back through the same
      // window that decided them.
      let shown = self.shown()
      let at = as_num(args.get(0), default=-1.0).to_int()
      if at >= 0 && at < shown.length() {
        let f = self.files[shown[at]]
        if f.permalink != "" {
          @control.intent(
            "openLink",
            [@values.Value::Text(f.permalink), @values.Value::Text(f.label)],
            {
              route: [DYN],
              on_ok: None,
              on_error: None,
              on_unhandled: None,
              live_path: false,
            },
          )
        }
      }
      Unchanged
    }
    (RECEIVE, _) => {
      guard is_page_message(name) else { return Unhandled }
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
    }
    _ => Unhandled
  }
}

///|
impl DynComponent for FileList with fn with_field(self, name, v) {
  match (name, v) {
    ("filter", @values.Value::Text(s)) =>
      Some({ ..self, filter: s } as &DynComponent)
    ("files", @values.Value::List(_)) =>
      Some(
        { ..self, files: as_items(Some(v)).map(file_row_of), page: 0 }
        as &DynComponent,
      )
    ("scope", @values.Value::Instance(t)) =>
      Some({ ..self, scope: t } as &DynComponent)
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 } as &DynComponent)
    _ => None
  }
}

///|
fn make_file_list(args : Array[(String, @values.Value)]) -> &DynComponent {
  let (scope, has_scope) = scope_child(arg(args, "scope"))
  let f : FileList = {
    filter: as_text(arg(args, "filter")),
    files: as_items(arg(args, "files")).map(file_row_of),
    scope,
    has_scope,
    page: 0,
    page_size: as_num(arg(args, "pageSize")).to_int(),
  }
  f as &DynComponent
}

// --- ChannelHistory: one channel's conversations --------------------------

///|
priv struct ChannelHistory {
  channel : String
  topic : String
  member_count : Double
  threads : Array[UInt64]
  /// Parallel to `threads`: the root timestamp each was built from, for the
  /// ordering toggle.
  times : Array[String]
  /// Parallel to `threads`: everything the thread says, lowercased, for the
  /// filter box. See this file's header — a token cannot be read back, so a
  /// parent that wants to search its children has to keep what it built them
  /// from.
  haystack : Array[String]
  query : String
  newest_first : Bool
  loading : Bool
  error : String
  /// The last thing a child reported, shown in the footer. This is the whole
  /// point of the bubbles: a `Segment` five levels down said something, and
  /// the component that owns the page decided what it meant.
  last_action : String
  /// The `Scope` child: which conversations this page was read from, and which
  /// were never looked at.
  ///
  /// A channel card is honest about its own arithmetic — "11 of 40
  /// conversations" is right there in `countLabel` — and said nothing at all
  /// about the workspace those forty came out of. The prose beside it has said
  /// it for releases, which made the card the more confident of the two while
  /// being the less informed.
  scope : UInt64
  /// Whether that child has anything to disclose. Kept here for the reason
  /// everything else in this struct is: a token cannot be read back.
  has_scope : Bool
  /// Which page of the channel is on screen, 0-based. A wish rather than a
  /// fact: the search box narrows the list under it, so what it comes out as is
  /// whatever `paging` can honour.
  page : Int
  /// The page size the host asked for, 0 for "did not ask" — see `PAGE_ABOVE`.
  page_size : Int
}

///|
/// Everything a thread says, for the filter: the root's author and body plus
/// every reply's. Built from the JSON, once, at construction.
fn thread_text(v : @values.Value) -> String {
  let out = StringBuilder()
  fn add_message(m : @values.Value) {
    out.write_string(as_text(field_of(m, "author")))
    out.write_string(" ")
    out.write_string(as_text(field_of(m, "channelName")))
    out.write_string(" ")
    let body = match field_of(m, "body") {
      Some(@values.Value::List(_) as list) => Some(list)
      Some(obj) => field_of(obj, "segments")
      None => None
    }
    for seg in as_items(body) {
      out.write_string(as_text(field_of(seg, "text")))
      out.write_string(" ")
    }
  }

  match field_of(v, "root") {
    Some(root) => add_message(root)
    None => ()
  }
  for reply in as_items(field_of(v, "replies")) {
    add_message(reply)
  }
  out.to_string().to_lower()
}

///|
/// The root timestamp a thread is ordered by.
fn thread_time(v : @values.Value) -> String {
  match field_of(v, "root") {
    Some(root) => as_text(field_of(root, "createdAt"))
    None => ""
  }
}

///|
/// Which threads the view shows, in the order it shows them: the filter box
/// narrows, the ordering toggle sorts. Indices into `threads`, so the callers
/// that need the RENDERED position (expand-all's `send-at` path) and the one
/// that needs the tokens (`get_field`) agree by construction.
fn ChannelHistory::visible(self : ChannelHistory) -> Array[Int] {
  let needle = self.query.trim().to_owned().to_lower()
  let idx : Array[Int] = []
  for i in 0..<self.threads.length() {
    if needle == "" || self.haystack[i].contains(needle) {
      idx.push(i)
    }
  }
  // Insertion sort: a channel page holds tens of threads, and a hand-written
  // pass keeps the comparison — string ISO-8601 timestamps, which order
  // lexicographically — in view.
  for i in 1..<idx.length() {
    let cur = idx[i]
    let mut j = i - 1
    while j >= 0 &&
          out_of_order(self.times[idx[j]], self.times[cur], self.newest_first) {
      idx[j + 1] = idx[j]
      j = j - 1
    }
    idx[j + 1] = cur
  }
  idx
}

///|
fn out_of_order(a : String, b : String, newest_first : Bool) -> Bool {
  if newest_first {
    a < b
  } else {
    a > b
  }
}

///|
/// The pager over what the filter left.
fn ChannelHistory::pager(self : ChannelHistory) -> Pager {
  paging(self.page, self.visible().length(), self.page_size)
}

///|
/// Which threads are RENDERED, in the order they are rendered: filtered,
/// ordered, and on this page.
///
/// `visible()` decides which and in what order; this cuts the page out of it.
/// Everything that counts rendered positions goes through here — the field the
/// view reads, the write-back that lands by position, and expand-all's
/// positional paths — because a path counted against a different list would
/// reach a different thread.
fn ChannelHistory::shown(self : ChannelHistory) -> Array[Int] {
  self.pager().slice(self.visible())
}

///|
impl DynComponent for ChannelHistory with fn get_field(self, name) {
  match name {
    "channel" => Some(@values.Value::Text(self.channel))
    "topic" => Some(@values.Value::Text(self.topic))
    "memberCount" => Some(@values.Value::Number(self.member_count))
    "threads" => {
      let shown : Array[UInt64] = []
      for i in self.shown() {
        shown.push(self.threads[i])
      }
      Some(instance_list(shown))
    }
    "query" => Some(@values.Value::Text(self.query))
    "newestFirst" => Some(@values.Value::Boolean(self.newest_first))
    "loading" => Some(@values.Value::Boolean(self.loading))
    "error" => Some(@values.Value::Text(self.error))
    "lastAction" => Some(@values.Value::Text(self.last_action))
    "scope" => Some(@values.Value::Instance(self.scope))
    "hasScope" => Some(@values.Value::Boolean(self.has_scope))
    _ => self.pager().field(name)
  }
}

///|
impl DynComponent for ChannelHistory with fn call_method(self, name, _args) {
  match name {
    "channelLabel" => @values.Value::Text("#\{self.channel}")
    "memberLabel" =>
      @values.Value::Text("\{self.member_count.to_int()} members")
    "orderLabel" =>
      @values.Value::Text(
        if self.newest_first {
          "newest first"
        } else {
          "oldest first"
        },
      )
    "countLabel" => {
      let shown = self.visible().length()
      let total = self.threads.length()
      let noun = if total == 1 { "conversation" } else { "conversations" }
      @values.Value::Text(
        if shown == total {
          "\{total} \{noun}"
        } else {
          "\{shown} of \{total} \{noun}"
        },
      )
    }
    "hasError" => @values.Value::Boolean(self.error != "")
    // Empty is a fact about the FILTER, not about the page: a channel with
    // conversations on another page is not "No messages."
    "isEmpty" =>
      @values.Value::Boolean(
        !self.loading && self.error == "" && self.visible().is_empty(),
      )
    _ => self.pager().answer_or_nil(name)
  }
}

///|
impl DynComponent for ChannelHistory with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    // The filter and the ordering each go back to the first page: both make a
    // different list, and page four of the old one is a position in a channel
    // that is not there any more.
    (RECEIVE, "setQuery") =>
      match args {
        [@values.Value::Text(q), ..] =>
          Changed({ ..self, query: q, page: 0 } as &DynComponent)
        _ => Unchanged
      }
    (RECEIVE, "toggleOrder") =>
      Changed(
        { ..self, newest_first: !self.newest_first, page: 0 } as &DynComponent,
      )
    // Paging is not a filter: it changes which conversations are drawn and
    // nothing about which ones there are, so no child is rebuilt.
    (RECEIVE, "firstPage" | "prevPage" | "nextPage" | "lastPage") =>
      match self.pager().moved(name) {
        Some(page) => Changed({ ..self, page, } as &DynComponent)
        None => Unchanged
      }
    (RECEIVE, "expandAll") => {
      self.set_all_expanded(true)
      Unchanged
    }
    (RECEIVE, "collapseAll") => {
      self.set_all_expanded(false)
      Unchanged
    }
    // A `Segment` deep inside a reply asked for a URL to be opened. Nothing
    // below here could decide what that means; this component can, and it
    // stops the bubble rather than letting the page hear it too.
    (INTENT, "openLink") => {
      @control.stop_propagation()
      let url = as_text(args.get(0))
      Changed({ ..self, last_action: "link: \{url}" } as &DynComponent)
    }
    (INTENT, "reacted") => {
      @control.stop_propagation()
      let emoji = as_text(args.get(0))
      let on = as_bool(args.get(1))
      let verb = if on { "reacted" } else { "took back" }
      Changed({ ..self, last_action: "\{verb} \{emoji}" } as &DynComponent)
    }
    // A thread with a count and no replies asked for them. This bundle has no
    // network, so what it can do is say the call — with both arguments filled
    // in, which is the whole difference between a dead end and a next step.
    (INTENT, "openThread") => {
      @control.stop_propagation()
      let channel = as_text(args.get(0))
      let ts = as_text(args.get(1))
      Changed(
        {
          ..self,
          last_action: if ts == "" {
            "that message carries no timestamp to read replies by"
          } else {
            "read the replies: channel=\{channel}, ts=\{ts}"
          },
        }
        as &DynComponent,
      )
    }
    _ => Unhandled
  }
}

///|
/// Expand or collapse every thread the view is currently showing.
///
/// The path is an INDEX into the rendered `threads` list, which is why
/// `shown()` decides both what `get_field` returns and how many steps this
/// walks: a positional path against a filtered and paged list has to count the
/// same positions the renderer did.
///
/// "Showing" therefore means this page, which is also what the button means: a
/// reader pressing expand-all is asking about the conversations in front of
/// them, not about four hundred they would have to page to.
fn ChannelHistory::set_all_expanded(self : ChannelHistory, on : Bool) -> Unit {
  let shown = self.shown().length()
  for i in 0..<shown {
    @control.send_at(
      [
        @control.PathStep::At({
          field: "threads",
          index: i.reinterpret_as_uint(),
        }),
      ],
      "setExpanded",
      [@values.Value::Boolean(on)],
    )
  }
}

///|
impl DynComponent for ChannelHistory with fn with_field(self, name, v) {
  let next : ChannelHistory? = match (name, v) {
    ("channel", @values.Value::Text(s)) => Some({ ..self, channel: s })
    ("topic", @values.Value::Text(s)) => Some({ ..self, topic: s })
    ("memberCount", @values.Value::Number(n)) =>
      Some({ ..self, member_count: n })
    ("query", @values.Value::Text(s)) => Some({ ..self, query: s, page: 0 })
    ("newestFirst", @values.Value::Boolean(b)) =>
      Some({ ..self, newest_first: b, page: 0 })
    ("pageSize", @values.Value::Number(n)) =>
      Some({ ..self, page_size: n.to_int(), page: 0 })
    ("loading", @values.Value::Boolean(b)) => Some({ ..self, loading: b })
    ("error", @values.Value::Text(s)) => Some({ ..self, error: s })
    ("scope", @values.Value::Instance(t)) => Some({ ..self, scope: t })
    // What the host hands back is the list it was SHOWN — filtered, ordered
    // and paged — so it goes home through `shown()`, which is the same
    // function that decided those positions in the first place. A length that
    // does not match means the two disagree about what is on screen, and
    // guessing which position a token belongs to would be worse than refusing.
    ("threads", _) =>
      match tokens_of(v) {
        Some(shown) => {
          let idx = self.shown()
          guard idx.length() == shown.length() else { None }
          let threads = self.threads.copy()
          for i, at in idx {
            threads[at] = shown[i]
          }
          Some({ ..self, threads, })
        }
        None => None
      }
    _ => None
  }
  match next {
    Some(c) => Some(c as &DynComponent)
    None => None
  }
}

///|
fn make_channel_history(args : Array[(String, @values.Value)]) -> &DynComponent {
  let raw = as_items(arg(args, "threads"))
  let threads : Array[UInt64] = []
  let times : Array[String] = []
  let haystack : Array[String] = []
  for item in raw {
    threads.push(child("Thread", Some(item)))
    times.push(thread_time(item))
    haystack.push(thread_text(item))
  }
  let (scope, has_scope) = scope_child(arg(args, "scope"))
  let c : ChannelHistory = {
    channel: as_text(arg(args, "channel"), default="general"),
    topic: as_text(arg(args, "topic")),
    member_count: as_num(arg(args, "memberCount")),
    threads,
    times,
    haystack,
    query: as_text(arg(args, "query")),
    newest_first: as_bool(arg(args, "newestFirst"), default=true),
    loading: as_bool(arg(args, "loading")),
    error: as_text(arg(args, "error")),
    last_action: "",
    scope,
    has_scope,
    page: 0,
    page_size: as_num(arg(args, "pageSize")).to_int(),
  }
  c as &DynComponent
}

// --- the bundle -----------------------------------------------------------

///|
/// Order matters only for a reader: the host resolves by name. It runs
/// smallest-first, the way the components nest.
///
/// No component persists. Seven of the eight hold nothing but their declared
/// fields, so the host projects and rebuilds them from the schema; the eighth
/// (`ChannelHistory`) holds the parallel search arrays too, and it rebuilds
/// them from `threads` in its constructor — which is the same answer, arrived
/// at without a second copy of the field list.
///
/// `Scope` sits at the top with `Segment` because it is the same size of thing:
/// a leaf that says one small true sentence, which two of the surfaces below
/// hang under themselves.
fn dyn_module() -> DynModule {
  module_def([
    dyn_comp("Segment", make_segment),
    dyn_comp("Scope", make_scope),
    dyn_comp("RichText", make_rich_text),
    dyn_comp("Reaction", make_reaction),
    dyn_comp("Message", make_message),
    dyn_comp("Thread", make_thread),
    dyn_comp("FileList", make_file_list),
    dyn_comp("ChannelHistory", make_channel_history),
  ])
}
