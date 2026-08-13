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
///      in its footer.
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
  let out = StringBuilder::new()
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
    // same shape as asking the host for a capability, one level cheaper.
    (INPUT, "open") => {
      if self.link && self.url != "" {
        @control.emit("openLink", [
          @values.Value::Text(self.url),
          @values.Value::Text(self.text),
        ])
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
    (INPUT, "toggle") => {
      let reacted = !self.reacted
      let count = if reacted { self.count + 1.0 } else { self.count - 1.0 }
      @control.emit("reacted", [
        @values.Value::Text(self.emoji),
        @values.Value::Boolean(reacted),
      ])
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
  channel_name : String
  created_at : String
  body : UInt64
  reactions : Array[UInt64]
  compact : Bool
  edited : Bool
  pinned : Bool
}

///|
/// "2026-06-23T09:12:00Z" -> "09:12". No `cap-clock` anywhere near it: the
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
    "channelName" => Some(@values.Value::Text(self.channel_name))
    "createdAt" => Some(@values.Value::Text(self.created_at))
    "body" => Some(@values.Value::Instance(self.body))
    "reactions" => Some(instance_list(self.reactions))
    "compact" => Some(@values.Value::Boolean(self.compact))
    "edited" => Some(@values.Value::Boolean(self.edited))
    "pinned" => Some(@values.Value::Boolean(self.pinned))
    _ => None
  }
}

///|
/// The avatar, in the only form an untrusted bundle can draw one: up to two
/// initials off whatever name the message arrived with.
///
/// A bundle may not name an image source (`dyncomp/policy/view_authority.mbt`),
/// so there is no photograph to be had here and there never will be. That is a
/// smaller loss than it sounds: what a reader uses an avatar for is telling one
/// speaker's run of messages from the next one's at a glance, and a disc with
/// two letters in it does that. `bluesky/Post` draws the same thing for the same
/// reason, and this is its twin rather than its cousin.
///
/// One initial per word, so `Ada Lovelace` is `AL` and a one-word name is one
/// letter — the convention a reader already knows, and the same rule `bluesky`
/// applies, so a host drawing both does not draw two different kinds of disc.
fn initials_of(author : String) -> String {
  let buf = StringBuilder::new()
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
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Message with fn with_field(self, name, v) {
  let next : Message? = match (name, v) {
    ("id", @values.Value::Text(s)) => Some({ ..self, id: s })
    ("author", @values.Value::Text(s)) => Some({ ..self, author: s })
    ("channelName", @values.Value::Text(s)) => Some({ ..self, channel_name: s })
    ("createdAt", @values.Value::Text(s)) => Some({ ..self, created_at: s })
    ("compact", @values.Value::Boolean(b)) => Some({ ..self, compact: b })
    ("edited", @values.Value::Boolean(b)) => Some({ ..self, edited: b })
    ("pinned", @values.Value::Boolean(b)) => Some({ ..self, pinned: b })
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
    channel_name: as_text(arg(args, "channelName")),
    created_at: as_text(arg(args, "createdAt")),
    body: child("RichText", body_args(arg(args, "body"))),
    reactions: children("Reaction", arg(args, "reactions")),
    compact: as_bool(arg(args, "compact")),
    edited: as_bool(arg(args, "edited")),
    pinned: as_bool(arg(args, "pinned")),
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

// --- Thread: a root message and its replies -------------------------------

///|
priv struct Thread {
  root : UInt64
  replies : Array[UInt64]
  expanded : Bool
}

///|
impl DynComponent for Thread with fn get_field(self, name) {
  match name {
    "root" => Some(@values.Value::Instance(self.root))
    "replies" => Some(instance_list(self.replies))
    "expanded" => Some(@values.Value::Boolean(self.expanded))
    "replyCount" =>
      Some(@values.Value::Number(self.replies.length().to_double()))
    _ => None
  }
}

///|
impl DynComponent for Thread with fn call_method(self, name, _args) {
  match name {
    "hasReplies" => @values.Value::Boolean(!self.replies.is_empty())
    "replyLabel" => {
      let n = self.replies.length()
      let caret = if self.expanded { "▾" } else { "▸" }
      let noun = if n == 1 { "reply" } else { "replies" }
      @values.Value::Text("\{caret} \{n} \{noun}")
    }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Thread with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    (INPUT, "toggle") =>
      Changed({ ..self, expanded: !self.expanded } as &DynComponent)
    // What `ChannelHistory`'s expand-all/collapse-all reaches with
    // `control.send-at`: a receive rather than an input, because it is not
    // this component's own button that raised it.
    (RECEIVE, "setExpanded") =>
      match args {
        [@values.Value::Boolean(b), ..] =>
          Changed({ ..self, expanded: b } as &DynComponent)
        _ => Unchanged
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
    ("replies", _) =>
      match tokens_of(v) {
        Some(replies) => Some({ ..self, replies, } as &DynComponent)
        None => None
      }
    _ => None
  }
}

///|
fn make_thread(args : Array[(String, @values.Value)]) -> &DynComponent {
  let t : Thread = {
    root: child("Message", arg(args, "root")),
    // A reply is compact whatever the fixture says, the way `fromData` forced
    // it in the original: "is this a reply" is a fact about POSITION, and the
    // thread is the only one that knows it.
    replies: children("Message", arg(args, "replies"), extra=[
      ("compact", @values.Value::Boolean(true)),
    ]),
    expanded: as_bool(arg(args, "expanded"), default=true),
  }
  t as &DynComponent
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
}

///|
/// Everything a thread says, for the filter: the root's author and body plus
/// every reply's. Built from the JSON, once, at construction.
fn thread_text(v : @values.Value) -> String {
  let out = StringBuilder::new()
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
impl DynComponent for ChannelHistory with fn get_field(self, name) {
  match name {
    "channel" => Some(@values.Value::Text(self.channel))
    "topic" => Some(@values.Value::Text(self.topic))
    "memberCount" => Some(@values.Value::Number(self.member_count))
    "threads" => {
      let shown : Array[UInt64] = []
      for i in self.visible() {
        shown.push(self.threads[i])
      }
      Some(instance_list(shown))
    }
    "query" => Some(@values.Value::Text(self.query))
    "newestFirst" => Some(@values.Value::Boolean(self.newest_first))
    "loading" => Some(@values.Value::Boolean(self.loading))
    "error" => Some(@values.Value::Text(self.error))
    "lastAction" => Some(@values.Value::Text(self.last_action))
    _ => None
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
    "isEmpty" =>
      @values.Value::Boolean(
        !self.loading && self.error == "" && self.visible().is_empty(),
      )
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for ChannelHistory with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    (INPUT, "setQuery") =>
      match args {
        [@values.Value::Text(q), ..] =>
          Changed({ ..self, query: q } as &DynComponent)
        _ => Unchanged
      }
    (INPUT, "toggleOrder") =>
      Changed({ ..self, newest_first: !self.newest_first } as &DynComponent)
    (INPUT, "expandAll") => {
      self.set_all_expanded(true)
      Unchanged
    }
    (INPUT, "collapseAll") => {
      self.set_all_expanded(false)
      Unchanged
    }
    // A `Segment` deep inside a reply asked for a URL to be opened. Nothing
    // below here could decide what that means; this component can, and it
    // stops the bubble rather than letting the page hear it too.
    (BUBBLE, "openLink") => {
      @control.stop_propagation()
      let url = as_text(args.get(0))
      Changed({ ..self, last_action: "link: \{url}" } as &DynComponent)
    }
    (BUBBLE, "reacted") => {
      @control.stop_propagation()
      let emoji = as_text(args.get(0))
      let on = as_bool(args.get(1))
      let verb = if on { "reacted" } else { "took back" }
      Changed({ ..self, last_action: "\{verb} \{emoji}" } as &DynComponent)
    }
    _ => Unhandled
  }
}

///|
/// Expand or collapse every thread the view is currently showing.
///
/// The path is an INDEX into the rendered `threads` list, which is why
/// `visible()` decides both what `get_field` returns and how many steps this
/// walks: a positional path against a filtered list has to count the same
/// positions the renderer did.
fn ChannelHistory::set_all_expanded(self : ChannelHistory, on : Bool) -> Unit {
  let shown = self.visible().length()
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
    ("query", @values.Value::Text(s)) => Some({ ..self, query: s })
    ("newestFirst", @values.Value::Boolean(b)) =>
      Some({ ..self, newest_first: b })
    ("loading", @values.Value::Boolean(b)) => Some({ ..self, loading: b })
    ("error", @values.Value::Text(s)) => Some({ ..self, error: s })
    // What the host hands back is the list it was SHOWN — filtered and
    // ordered — so it goes home through `visible()`, which is the same
    // function that decided those positions in the first place. A length that
    // does not match means the two disagree about what is on screen, and
    // guessing which position a token belongs to would be worse than refusing.
    ("threads", _) =>
      match tokens_of(v) {
        Some(shown) => {
          let idx = self.visible()
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
  }
  c as &DynComponent
}

// --- the bundle -----------------------------------------------------------

///|
/// Order matters only for a reader: the host resolves by name. It runs
/// smallest-first, the way the components nest.
///
/// No component persists. Five of the six hold nothing but their declared
/// fields, so the host projects and rebuilds them from the schema; the sixth
/// (`ChannelHistory`) holds the parallel search arrays too, and it rebuilds
/// them from `threads` in its constructor — which is the same answer, arrived
/// at without a second copy of the field list.
fn dyn_module() -> DynModule {
  module_def([
    dyn_comp("Segment", make_segment),
    dyn_comp("RichText", make_rich_text),
    dyn_comp("Reaction", make_reaction),
    dyn_comp("Message", make_message),
    dyn_comp("Thread", make_thread),
    dyn_comp("ChannelHistory", make_channel_history),
  ])
}
