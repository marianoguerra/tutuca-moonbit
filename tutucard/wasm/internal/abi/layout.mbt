// The canonical ABI's numbers, the constant pool, and the three Wax types
// everything in this compiler speaks in.
//
// Split from the generator because the seam is thin — fifty-odd uses, each of
// them a name that reads BETTER qualified (`@abi.ret_get_field`,
// `@abi.guest_iface`). The instruction builders did not come with it: they are
// used three hundred times, and `@abi.call(@abi.get("s"), ...)` would undo the
// one thing `dsl.mbt` exists to do.
//
// Every number here was computed by the rules in `dyncomp/host/wasm/abi.mjs`
// (`alignment`, `sizeOf`, `payloadOffset`, `flatten`) and then CHECKED against
// it by driving a compiled module through `instantiate` — which is the only
// way a layout constant can be known to be right, since the host and the guest
// each write it out independently and a disagreement is silent.
//
// The one deliberate difference from the shipped MoonBit guests is the string
// encoding: they are built `--encoding utf16`, and these are utf8. A
// descriptor states which, per bundle, and `abi.mjs` implements both — so the
// choice is free, and utf8 is what a constant pool laid down as a data segment
// wants to hold.

///|
/// The one memory, and the name the emitted module knows it by.
pub let memory_name : String = "mem"

///|
/// `value` is 16 bytes on the wire: a 1-byte discriminant, padding to the
/// payload's 8-byte alignment, then 8 bytes of payload.
///
/// This is ONLY a wire shape. The tags that go with it live in
/// `runtime/runtime.wax`, beside the code that reads them, because lifting
/// and lowering is the only thing left that cares.
pub let cell_size : Int = 16

// --- static return areas ---------------------------------------------------
//
// An export whose result does not fit in one flat core value returns a POINTER
// to an area it owns. These are those areas, at fixed addresses below the
// heap: every one is read by the host before the next call into the guest, so
// one area per export is enough and none of them can be in flight at once.

///|
/// `option<value>` — 24 bytes, payload at +8.
pub let ret_get_field : Int = 16

///|
/// `event-result` — 8 bytes: discriminant, then the successor handle at +4.
pub let ret_event_result : Int = 48

///|
/// `property-result`, which has the same maximum payload and alignment.
pub let ret_set_property : Int = 48

///|
/// `option<own<instance>>` — 8 bytes, handle at +4.
pub let ret_with_field : Int = 64

///|
/// The same shape, for `restore`.
pub let ret_restore : Int = 80

///|
/// The shared value return area for `compute`, `enrich`, and `enrich-scope`.
pub let ret_render_value : Int = 96

///|
/// `option<value>` has the same wire layout as `get-field`.
pub let ret_get_property : Int = 16

///|
/// `value` — 16 bytes, for the one IMPORT that answers.
///
/// `control.lookup` is the only host function a guest calls for a value rather
/// than for an effect, and a `value` is more core values than a result may
/// carry — so the guest appends a pointer and the host stores into it. That
/// makes this a return area like the ones around it, read once during the call
/// that wrote it, even though the direction is the other way round.
///
/// 112 is the gap `ret_render_value` (96, 16 bytes) leaves before `ret_persist`.
pub let ret_lookup : Int = 112

///|
/// `list<u8>` — a (pointer, length) pair.
pub let ret_persist : Int = 128

///|
/// `request-result` — 24 bytes, the payload `value` at +8.
pub let ret_serve_intent : Int = 144

///|
/// The two bytes an intent's `route` is lowered into — `list<leg>`, one byte
/// per leg.
///
/// Not a return area but the same kind of thing: a fixed scratch the host
/// reads during ONE call and never after, so one of it is enough. A route is
/// at most two legs (the closed table below), the bytes are written at flush
/// time immediately before `control.intent` or `control.forward` is called,
/// and the host has lifted the list by the time that call returns.
///
/// 176 rather than the next multiple of anything: `ret_serve_intent` is 24
/// bytes from 144, and the runtime's own scratch starts at 192 (`tc_flat` in
/// `runtime/lower_values.wax`). This is the gap between them.
pub let route_buf : Int = 176

///|
/// Where the constant pool starts. Everything below it is return areas.
pub let pool_base : Int = 1024

///|
/// The guest world's names, spelled once.
pub let guest_iface : String = "tutuca:component/guest@0.11.0"

///|
/// The namespace an exported resource's intrinsics are imported from.
pub let resource_iface : String = "[export]tutuca:component/guest@0.11.0"

///|
pub let control_iface : String = "tutuca:component/control@0.11.0"

///|
/// The card compiler's two handler categories. The fixed WIT operations pick
/// one directly; the compact internal dispatch chain uses these numbers.
///
/// Read off `HandlerBucket::ordinal` rather than written down again: the
/// numbering is the WIT variant's case order, and it was spelled here, in
/// `dyncomp/host/guest.mbt` and in `guests/sdk.mbt` — three copies of a
/// contract that no compiler holds to itself.
pub let bucket_receive : Int = @tutuca.HandlerBucket::ordinal(Receive)

///|
/// The routed bucket: a dispatch offered to each hop of a route until
/// something answers.
pub let bucket_intent : Int = @tutuca.HandlerBucket::ordinal(Intent)

///|
/// A route, as one small integer.
///
/// This is the COMPILER's compact form and nothing else: the set is closed —
/// two legs, in one of two orders, or one of them, or none — so the generator
/// carries a code through `tc_effect_route` rather than a pointer and a
/// length. The design's section 3 is what closes it: the leg words are a
/// closed set and the parser reads them until it finds a literal.
///
/// The WIRE form is the WIT's, which is `list<leg>` inside `intent-opts`. A
/// code is lowered to that list at the boundary — one byte per leg at
/// `route_buf`, `dyn` = 0 and `lex` = 1 — by `flush_fn`, which is the only
/// place the two spellings meet.
///
/// EMPTY is not "no legs"; it is "not written", so it lowers to a list of
/// length ZERO rather than to a default this side invented: the default lives
/// in `@tutuca.IntentOpts::new`, host-side, and a guest that says nothing
/// cannot disagree with it.
pub let route_none : Int = 0

///|
pub let route_dyn : Int = 1

///|
pub let route_lex : Int = 2

///|
pub let route_dyn_lex : Int = 3

///|
pub let route_lex_dyn : Int = 4

///|
/// `control.log`'s level, in WIT order: debug, info, warn, error.
///
/// A declined contract is a warning and not an error, which is the reading the
/// interpreter already takes: it goes through `warn_hook`, and a transition
/// that did not happen is the rule working rather than the card being broken.
pub let log_warn : Int = 2

// ---------------------------------------------------------------------------
// the constant pool

///|
/// Every constant the module needs, as bytes laid down by one data segment.
///
/// Strings AND doubles. A double could be a Wax float literal, but the
/// spellings that survive a round trip exactly are the awkward ones, and a
/// generator that got one wrong would produce a module that is merely slightly
/// off rather than one that fails — so both kinds of constant are eight or
/// more bytes in memory and one load away, and there is no literal to get
/// wrong.
pub struct Pool {
  bytes : Array[Byte]
  /// Interned by content: two `'ok'` literals in a card are one string here.
  strings : Map[String, Int]
  /// The same strings in the order they were interned, as (address, byte
  /// length). `#[start]` walks this to build `tc_consts`, so a string's INDEX
  /// here is the name every use site knows it by.
  string_list : Array[(Int, Int)]
  doubles : Map[Double, Int]
}

///|
pub fn Pool::new() -> Pool {
  { bytes: [], strings: Map([]), string_list: [], doubles: Map([]), }
}

///|
/// The index of `s` among the interned strings, adding it if it is new.
///
/// An index rather than an address, because a string is not read out of
/// memory at each use: `#[start]` builds one `utf8_string` per constant — one
/// validation and one hash, once — and a use site is `tc_const(i)`.
pub fn Pool::string_index(self : Pool, s : String) -> Int {
  match self.strings.get(s) {
    Some(i) => i
    None => {
      let at = pool_base + self.bytes.length()
      for b in @utf8.encode(s) {
        self.bytes.push(b)
      }
      let i = self.string_list.length()
      self.string_list.push((at, utf8_len(s)))
      self.strings[s] = i
      i
    }
  }
}

///|
/// The BYTE length of `s` as utf8 — which is what the canonical ABI calls a
/// string's length, and not what `String::length` answers.
pub fn utf8_len(s : String) -> Int {
  @utf8.encode(s).length()
}

///|
/// The address of `x`'s eight bytes, little-endian, 8-byte aligned.
pub fn Pool::double(self : Pool, x : Double) -> Int {
  match self.doubles.get(x) {
    Some(at) => at
    None => {
      while (pool_base + self.bytes.length()) % 8 != 0 {
        self.bytes.push(0)
      }
      let at = pool_base + self.bytes.length()
      let bits = x.reinterpret_as_uint64()
      for i in 0..<8 {
        self.bytes.push(((bits >> (i * 8)) & 0xffUL).to_byte())
      }
      self.doubles[x] = at
      at
    }
  }
}

///|
/// The first address above the pool the bump allocator may hand out, 16-byte
/// aligned so a `value` cell is always aligned.
pub fn Pool::heap_base(self : Pool) -> Int {
  let end = pool_base + self.bytes.length()
  (end + 15) / 16 * 16
}

///|
pub fn Pool::to_bytes(self : Pool) -> Bytes {
  Bytes::from_array(self.bytes)
}

///|
/// An instruction with no source location of its own.
///
/// Locations are what buys a generator the whole diagnostic renderer — the
/// snippet, the caret, the quick fixes — pointing at ITS syntax. This one
/// hands over `dummy_loc` because a Wax type error in generated code is a bug
/// in `cardwasm`, not in the card: the card's own errors are found by
/// `tscript/check` before a single instruction is built, and reported against
/// the card's spans by `Refusal`.
pub type I = @ast.Instr[@basic.Location]

///|
/// One field of a module, with its span. A module is an array of these.
pub type Field = @basic.Annotated[
  @ast.ModuleField[@basic.Location],
  @basic.Location,
]

///|
pub type VT = @wasm_types.ValType[@ast.Ident]
