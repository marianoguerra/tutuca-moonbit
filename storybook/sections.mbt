// Grouping stories into the sidebar's sections. The story SET comes from
// wherever the gallery's owner builds it (a hand-written list, or the
// projection in project.mbt); this file only decides what order the groups
// appear in.

///|
/// Group stories into ordered sections: the names in `order` first (empty ones
/// dropped), then any section not named there, in first-seen order. A story
/// whose `section` is unlisted still shows up — a gallery never loses a story
/// to a metadata gap.
pub fn sections_of(
  stories : Array[Story],
  order? : Array[String] = [],
) -> Array[Section] {
  let by_name : Map[String, Array[Story]] = Map([])
  let seen_order : Array[String] = []
  for s in stories {
    match by_name.get(s.section) {
      Some(arr) => arr.push(s)
      None => {
        by_name[s.section] = [s]
        seen_order.push(s.section)
      }
    }
  }
  let out : Array[Section] = []
  let emitted : Map[String, Bool] = Map([])
  for name in order {
    match by_name.get(name) {
      Some(arr) => {
        out.push({ title: name, stories: arr, })
        emitted[name] = true
      }
      None => ()
    }
  }
  // any section not in the curated order, appended in first-seen order
  for name in seen_order {
    if !emitted.contains(name) {
      match by_name.get(name) {
        Some(arr) => out.push({ title: name, stories: arr, })
        None => ()
      }
    }
  }
  out
}
