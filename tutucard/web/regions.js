// Where each part of a card lives in its own text.
//
// The structured view is not a second copy of the card. It is a projection of
// the SAME string, and every pane edits that string by splicing at the offsets
// recorded here. That is what makes the two views agree without diffing them:
// there is one source of truth and two ways to look at it.
//
// Slicing rather than parsing-and-reprinting, deliberately. `viewfile` splits a
// card properly — it lifts styles, dedents templates, and normalizes what it
// hands back — and running an editor's buffer through it would rewrite the
// author's file on every keystroke. What is wanted here is the opposite: give
// back exactly the characters that are there, and put back exactly what was
// typed.

/**
 * A slice of the card, and where it came from.
 *
 * @typedef {{ text: string, start: number, end: number }} Region
 */

/**
 * The card's parts.
 *
 * `state` and `script` are null when the card has no such block — which is
 * legitimate, and which the structured view shows as an empty pane rather than
 * hiding, because "there is no script yet" is what an author is about to fix.
 *
 * @typedef {{
 *   state: Region | null,
 *   script: Region | null,
 *   views: Array<Region & { name: string, id: string, idStart: number, idEnd: number }>,
 * }} Parts
 */

/** The inner span of the first element matching `open`, or null. */
function element(source, openRe, closeTag) {
  openRe.lastIndex = 0;
  const open = openRe.exec(source);
  if (!open) return null;
  const start = open.index + open[0].length;
  const end = source.indexOf(closeTag, start);
  if (end < 0) return null;
  return { match: open, text: source.slice(start, end), start, end };
}

/**
 * Split a card into the regions the structured view edits.
 *
 * @param {string} source
 * @returns {Parts}
 */
export function parts(source) {
  const state = element(
    source,
    /<script\s+type="tutuca\/state"\s*>/g,
    "</script>",
  );
  const script = element(
    source,
    /<script\s+type="tutuca\/script"[^>]*>/g,
    "</script>",
  );
  const views = [];
  const tpl = /<template([^>]*)>/g;
  const OPEN = "<template".length;
  let m;
  while ((m = tpl.exec(source)) !== null) {
    const start = m.index + m[0].length;
    const end = source.indexOf("</template>", start);
    if (end < 0) break;
    const idAttr = /\bid="([^"]*)"/.exec(m[1]);
    const id = idAttr ? idAttr[1] : "";
    // `Counter:row` is the row view of Counter; a bare id is the component's
    // main view. The tab shows the VIEW half, since a card is one component.
    const name = id.includes(":") ? id.slice(id.indexOf(":") + 1) : "main";
    // Where the id's TEXT starts, in file coordinates: past `<template`, into
    // the attributes, past `id="`. Getting this base wrong splices a rename
    // into the middle of the tag, which is not a thing an editor gets to do.
    const idStart = idAttr
      ? m.index + OPEN + m[1].indexOf(idAttr[0]) + 'id="'.length
      : -1;
    views.push({
      name,
      id,
      text: source.slice(start, end),
      start,
      end,
      idStart,
      idEnd: idStart < 0 ? -1 : idStart + id.length,
    });
    tpl.lastIndex = end;
  }
  return { state: state && strip(state), script: script && strip(script), views };
}

/** A region without the match object the scan carried. */
function strip(r) {
  return { text: r.text, start: r.start, end: r.end };
}

/**
 * The source with `region`'s characters replaced.
 *
 * One splice at a time, and the caller re-splits afterwards: two edits against
 * one set of offsets would have the second land in the wrong place, and an
 * editor that corrupts a file to save a re-scan is not a trade worth making.
 *
 * @param {string} source
 * @param {Region} region
 * @param {string} text
 */
export function splice(source, region, text) {
  return source.slice(0, region.start) + text + source.slice(region.end);
}

/** The component this card declares, for naming a new view's template id. */
export function componentOf(source) {
  const tpl = /<template[^>]*\bid="([A-Z][\w:]*)"/.exec(source);
  if (tpl) return tpl[1].split(":")[0];
  const st = /\bstate\s+([A-Z]\w*)\s*\{/.exec(source);
  return st ? st[1] : "";
}

/**
 * The source with a new empty view appended.
 *
 * Appended rather than inserted beside its siblings, because an editor that
 * moved the author's other templates to make room would be rewriting a file
 * they can see.
 *
 * @param {string} source
 * @param {string} name
 */
export function addView(source, name) {
  const comp = componentOf(source);
  // A card whose templates are unnamed has to name them all the moment a
  // second one exists — the same rule the file itself follows — so the FIRST
  // added view is what turns `<template>` into `<template id="Comp">`.
  let out = source;
  const bare = /<template\s*>/.exec(out);
  if (bare && comp) {
    out = out.slice(0, bare.index) + `<template id="${comp}">` +
      out.slice(bare.index + bare[0].length);
  }
  const id = comp ? `${comp}:${name}` : name;
  const sep = out.endsWith("\n") ? "" : "\n";
  return `${out}${sep}\n<template id="${id}">\n  <div></div>\n</template>\n`;
}

/**
 * The source with view `i` renamed.
 *
 * @param {string} source
 * @param {Parts} p
 * @param {number} i
 * @param {string} name
 */
export function renameView(source, p, i, name) {
  const v = p.views[i];
  const comp = componentOf(source);
  const id = name === "main" && !comp ? "" : comp ? `${comp}:${name}` : name;
  if (v.idStart < 0) {
    // No id at all: the bare `<template>` becomes a named one.
    const open = source.lastIndexOf("<template", v.start);
    const close = source.indexOf(">", open);
    return (
      source.slice(0, open) + `<template id="${id}">` + source.slice(close + 1)
    );
  }
  return source.slice(0, v.idStart) + id + source.slice(v.idEnd);
}
