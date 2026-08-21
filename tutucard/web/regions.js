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
 * `macros` is the `<template id="macro:name">` declarations, kept apart from
 * `views` because they are a different kind of thing: a view belongs to the
 * component and a macro belongs to the FILE, and a card that declares one
 * would otherwise show it as a view called `field` of a component called
 * `macro`.
 *
 * `tests` is the `<script type="tutuca/test">` block: what the card claims it
 * does, as scenes. One per file like `state` and `script`, and null when the
 * card declares none — which is most cards, and which the pane shows as empty
 * rather than hiding, for the reason the script pane does.
 *
 * `init` is the `<script type="tutuca/init">` block: the card's named example
 * states. One per file, and the same null-rather-than-hidden treatment. It is
 * the one block whose PANE has a second pane beside it — the Examples panel
 * mounts what this names — which is why it is worth editing here rather than
 * only in the raw view.
 *
 * @typedef {{
 *   state: Region | null,
 *   script: Region | null,
 *   tests: Region | null,
 *   init: Region | null,
 *   views: Array<Region & { name: string, id: string, idStart: number, idEnd: number }>,
 *   macros: Array<Region & { name: string, id: string, idStart: number, idEnd: number }>,
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
  const tests = element(
    source,
    /<script\s+type="tutuca\/test"\s*>/g,
    "</script>",
  );
  const init = element(
    source,
    /<script\s+type="tutuca\/init"\s*>/g,
    "</script>",
  );
  const views = [];
  const macros = [];
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
    // main view.
    const isMacro = id.startsWith("macro:");
    const view = id.includes(":") ? id.slice(id.indexOf(":") + 1) : "main";
    const comp = id.includes(":") ? id.slice(0, id.indexOf(":")) : "";
    // Where the id's TEXT starts, in file coordinates: past `<template`, into
    // the attributes, past `id="`. Getting this base wrong splices a rename
    // into the middle of the tag, which is not a thing an editor gets to do.
    const idStart = idAttr
      ? m.index + OPEN + m[1].indexOf(idAttr[0]) + 'id="'.length
      : -1;
    (isMacro ? macros : views).push({
      name: view,
      comp,
      id,
      text: source.slice(start, end),
      start,
      end,
      idStart,
      idEnd: idStart < 0 ? -1 : idStart + id.length,
    });
    tpl.lastIndex = end;
  }
  // What each TAB says.
  //
  // The view half alone while a card is one component, which is what it always
  // said: `main` and `row` are the two views of the only thing there is. That
  // stopped being enough the moment a card could declare two — `Todos:main` and
  // `Todo:main` are views of different components, and a strip reading
  // `main` `main` names neither. So the label is decided once the whole file
  // has been read, because it depends on how many components are IN it.
  const comps = new Set(views.map((v) => v.comp).filter((c) => c !== ""));
  if (comps.size > 1) {
    for (const v of views) {
      v.name = v.name === "main" ? v.comp : v.id;
    }
  }

  return {
    state: state && strip(state),
    script: script && strip(script),
    tests: tests && strip(tests),
    init: init && strip(init),
    views,
    macros,
  };
}

/** A region without the match object the scan carried. */
function strip(r) {
  return { text: r.text, start: r.start, end: r.end };
}

/**
 * How a block is laid out inside its tags: the lines between them, the
 * indentation those lines share, and whatever precedes the closing tag on its
 * own line. Null when the block keeps content on the tag's line
 * (`<template>x</template>`) — there is no indentation to speak of there, and
 * inventing one would rewrite the line on the first keystroke.
 */
function shape(text) {
  if (!text.startsWith("\n")) return null;
  const body = text.slice(1).split("\n");
  const tail = body.pop();
  if (tail.trim() !== "") return null; // the close shares a line with content
  const indents = body
    .filter((l) => l.trim() !== "")
    .map((l) => /^[ \t]*/.exec(l)[0]);
  const shortest = indents.reduce((a, b) => (b.length < a.length ? b : a), indents[0] ?? "");
  // Tabs here and spaces there: no common prefix exists, so take none rather
  // than slice a line at a column that means nothing in it.
  const indent = indents.every((i) => i.startsWith(shortest)) ? shortest : "";
  return { body, indent, tail };
}

/**
 * A block's body, without the indentation the tag it sits in gave it.
 *
 * The one thing the structured panes normalize. A pane that opens with a blank
 * line and puts `<div>` at column 2 is showing where the block sits in the
 * FILE, and the file is what the raw view is for — here the author is editing
 * the view itself, so it starts at column 0. `reindented` puts the file's shape
 * back, which keeps the characters that reach the card the author's.
 *
 * @param {string} text a region's text, as `parts` sliced it
 */
export function dedented(text) {
  const s = shape(text);
  if (!s) return text;
  return s.body
    .map((l) => (l.startsWith(s.indent) ? l.slice(s.indent.length) : l))
    .join("\n");
}

/**
 * A pane's text, indented the way `text` was, ready to splice back.
 *
 * `text` is the region as it stands — the indentation is read from the card
 * rather than remembered from the draw, so a pane edited after a raw edit lands
 * the way the block reads NOW.
 *
 * @param {string} text a region's text, as `parts` sliced it
 * @param {string} pane what the pane holds
 */
export function reindented(text, pane) {
  const s = shape(text);
  if (!s) return pane;
  // Blank lines stay blank: indenting them is how a file grows the trailing
  // whitespace nobody typed.
  const body = pane.split("\n").map((l) => (l === "" ? "" : s.indent + l));
  return `\n${body.join("\n")}\n${s.tail}`;
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

/**
 * The source with an empty `tutuca/init` block appended.
 *
 * The body is one fixture rather than `{}`, because the envelope is the thing
 * an author most needs shown: a fixture is `{ "value": { …fields… } }` with
 * `doc`, `view`, `drive`, `intents`, `tags` and `default` beside it, and a card
 * that opened on an empty object would teach the shorthand the format does not
 * have.
 *
 * @param {string} source
 */
export function addInit(source) {
  const sep = source.endsWith("\n") ? "" : "\n";
  return (
    `${source}${sep}\n<script type="tutuca/init">\n` +
    `{\n  "fresh": {\n    "doc": "",\n    "value": {}\n  }\n}\n</script>\n`
  );
}

/**
 * The source with a new empty macro appended.
 *
 * The body carries `<x:slot>` because a macro without one drops the children
 * of every call, which is the first thing an author writing one discovers by
 * losing them.
 *
 * @param {string} source
 * @param {string} name
 */
export function addMacro(source, name) {
  const sep = source.endsWith("\n") ? "" : "\n";
  return (
    `${source}${sep}\n<template id="macro:${name}">\n` +
    `  <div>\n    <x:slot></x:slot>\n  </div>\n</template>\n`
  );
}

/**
 * The source with macro `i` renamed. Its id always carries the `macro:`
 * prefix — that prefix is what makes it a macro rather than a view.
 *
 * @param {string} source
 * @param {Parts} p
 * @param {number} i
 * @param {string} name
 */
export function renameMacro(source, p, i, name) {
  const m = p.macros[i];
  if (!m || m.idStart < 0) return source;
  return source.slice(0, m.idStart) + `macro:${name}` + source.slice(m.idEnd);
}

