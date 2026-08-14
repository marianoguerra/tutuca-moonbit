// The seam itself.

///|
/// Something that rewrites a freshly built vdom tree before it is diffed.
///
/// It MUTATES rather than returning a new tree, and that is not a style
/// preference: `@vdom`'s morph short-circuits a subtree by physical identity
/// (and the render cache hands back the same `Vdom` object when a site's
/// inputs have not changed), so a filter that rebuilt nodes would silently
/// turn every render into a full diff.
pub(open) trait VdomFilter {
  /// Apply this filter's rules to ONE element. The primitive, because the
  /// caller decides when an element is ready to be filtered.
  ///
  /// It is the caller's rather than the filter's because `render` does not
  /// traverse at all: it filters each element where it CONSTRUCTS it, which is
  /// exactly-once by construction and costs no walk. A filter that owned its
  /// traversal would have to be handed the finished tree, and would then
  /// re-walk every subtree the render cache returned unchanged, on every render
  /// — which is what this used to do, and it made the filter O(whole tree)
  /// where the rest of the pipeline is O(changed).
  ///
  /// Children are already built when this is called. A filter that REPLACES
  /// them (raw markup becoming described nodes) is therefore replacing finished
  /// nodes, and owns checking what it built — nothing runs after it on nodes it
  /// created. `MarkupFilter` does exactly that, which is why
  /// `attr_value_allowed` is public.
  fn filter_elem(Self, @vdom.VElem) -> Unit

  /// The same, for a caller that already knows which rules can possibly apply.
  ///
  /// `render` knows: an attribute's NAME is a literal in the view, so which
  /// rules an element could concern is decided off the tree once and memoized
  /// (`@anode.DomData.sink_hints`), while its VALUE is what the filter is here
  /// to look at. A rule whose bit is clear has nothing to find and returns
  /// without touching the attribute map — which is the whole cost of the filter
  /// on the elements that carry no sink at all, and that is most of them.
  ///
  /// DEFAULTS TO IGNORING THE HINTS, which is why a filter this package does
  /// not own is still correct: a host's own rule looks for something no bit
  /// describes, so it gets asked about every element as it always was. Override
  /// it only to skip work, never to do different work — `filter_elem` stays the
  /// definition of what the rule IS, and `@sinks.SinkHints::all()` must always
  /// mean exactly the same as calling it.
  fn filter_elem_hinted(Self, @vdom.VElem, @sinks.SinkHints) -> Unit = _

  /// Apply this filter to a whole tree.
  ///
  /// The convenience entry point, for a caller holding a tree and no opinion
  /// about traversal. `render` does not use it.
  fn filter_tree(Self, @vdom.Vdom) -> Unit = _

  /// Everything dropped since the last call, oldest first, clearing the log.
  ///
  /// On the trait rather than on each filter because a host does not
  /// necessarily hold the concrete type: `App` installs a filter by default, so
  /// the one that drops something is often one the host never constructed. A
  /// filter that silently removed things with no way to ask what it removed
  /// would answer "why did my link vanish" with nothing.
  ///
  /// Defaults to none, for a filter that only rewrites.
  fn take_reports(Self) -> Array[Dropped] = _
}

///|
impl VdomFilter with fn filter_elem_hinted(self, el, _hints) {
  self.filter_elem(el)
}

///|
/// A walk holds no view tree, so it knows nothing and claims nothing:
/// `filter_elem` is the whole rule and this is what it always did.
impl VdomFilter with fn filter_tree(self, tree) {
  walk_elems(tree, el => self.filter_elem(el))
}

///|
impl VdomFilter with fn take_reports(_self) {
  []
}

///|
/// Visit every element in a tree, once.
///
/// Shared so that composing two attribute rules costs one traversal rather
/// than two. `Chain` exists for filters that genuinely need separate passes —
/// one that REPLACES a subtree has to finish before one that inspects
/// attributes — but two rules that both just inspect `attrs` do not, and the
/// filter runs on every render.
fn walk_elems(tree : @vdom.Vdom, visit : (@vdom.VElem) -> Unit) -> Unit {
  match tree {
    Node(el) => {
      visit(el)
      for child in el.childs {
        walk_elems(child, visit)
      }
    }
    Fragment(childs) =>
      for child in childs {
        walk_elems(child, visit)
      }
    Text(_) | Comment(_) => ()
  }
}

///|
/// One thing a filter removed, for a host to show a developer.
///
/// A filter cannot report the way the static pass does — by the time it runs
/// there is no author to report to, because the value may have come from
/// application state rather than from anyone's template. So it records, and
/// the host decides whether anyone is listening.
pub(all) struct Dropped {
  tag : String
  attr : String
  /// The value as it was, so "why did my link vanish" has an answer.
  value : String
  reason : String
} derive(Eq, Debug)

///|
pub fn Dropped::to_string(self : Dropped) -> String {
  "dropped \{self.attr} on <\{self.tag}>: \{self.reason} (\{self.value})"
}

///|
/// What a filter dropped since the host last looked, bounded.
///
/// Every filter needs exactly this and each used to carry its own copy: the
/// same two fields, the same `64`, the same two methods. Four copies of a
/// bound is four places for it to become a different bound — and the cap is
/// the part that matters, since a page rendering a hostile view drops on
/// every element of every render and an unbounded log is the leak.
pub struct DropLog {
  entries : Array[Dropped]
  max : Int
}

///|
pub fn DropLog::new(max_reports? : Int = 64) -> DropLog {
  { entries: [], max: max_reports }
}

///|
/// Record a drop, up to the bound. Silently ignored past it: the log is for a
/// host to show someone, and the first 64 say as much as the first 6400.
pub fn DropLog::record(self : DropLog, d : Dropped) -> Unit {
  if self.entries.length() < self.max {
    self.entries.push(d)
  }
}

///|
/// Everything recorded since the last call, and clears the log.
pub fn DropLog::take(self : DropLog) -> Array[Dropped] {
  let out = self.entries.copy()
  self.entries.clear()
  out
}

///|
/// Several filters as one, in order.
///
/// `App` holds a single filter, deliberately — a list there would make the
/// order a property of the host's call sequence rather than of anything
/// written down. Order matters between these: a filter that REPLACES a subtree
/// (raw markup becoming described children) must run before one that inspects
/// attributes, or the new subtree is never inspected. The markup filter
/// therefore checks what it builds itself, and this exists for hosts composing
/// their own.
pub struct Chain {
  filters : Array[&VdomFilter]
}

///|
pub fn Chain::new(filters : Array[&VdomFilter]) -> Chain {
  { filters, }
}

///|
/// Each member's rules on the element, in order.
///
/// One traversal for the whole chain rather than one per member, and the order
/// that mattered still holds: a member that replaces children runs before the
/// members after it, and the walk descends into what it built.
pub impl VdomFilter for Chain with fn filter_elem(self, el) {
  for f in self.filters {
    f.filter_elem(el)
  }
}

///|
/// Each member decides for itself what the hints let it skip.
///
/// Passed through rather than tested here: a chain has no idea which bits its
/// members care about, and a member this package does not own cares about none
/// of them. The early-out belongs in the rule.
pub impl VdomFilter for Chain with fn filter_elem_hinted(self, el, hints) {
  for f in self.filters {
    f.filter_elem_hinted(el, hints)
  }
}

///|
/// Every member's reports, in the order the members run.
pub impl VdomFilter for Chain with fn take_reports(self) {
  let out : Array[Dropped] = []
  for f in self.filters {
    out.append(f.take_reports())
  }
  out
}
