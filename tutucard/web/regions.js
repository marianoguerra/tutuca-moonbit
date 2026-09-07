// Where each part of a card lives in its own text.
//
// The structured view is not a second copy of the card. It is a projection of
// the SAME string, and every pane edits that string by splicing at the offsets
// recorded here. That is what makes the two views agree without diffing them:
// there is one source of truth and two ways to look at it.
//
// Slicing rather than parsing-and-reprinting, deliberately. `tutufile` reads a
// card properly and would hand back a normalized file, and running an editor's
// buffer through it would rewrite the author's file on every keystroke. What is
// wanted here is the opposite: give back exactly the characters that are there,
// and put back exactly what was typed.
//
// A `.tutu` makes this simpler than the notation it replaced. A section is a
// word at column 0 with a `:` after it and an indented body under it, so the
// regions are found by INDENTATION rather than by matching tags — no open/close
// pair to get out of step, and no id attribute to splice into the middle of.

/**
 * A slice of the card, and where it came from.
 *
 * @typedef {{ text: string, start: number, end: number }} Region
 */

/**
 * The card's parts.
 *
 * `spec` and `script` are null when the card has no such section — which is
 * legitimate, and which the structured view shows as an empty pane rather than
 * hiding, because "there is no logic yet" is what an author is about to fix.
 *
 * `macros` is the `macro name(…):` declarations, kept apart from `views`
 * because they are a different kind of thing: a view belongs to the component
 * and a macro belongs to the FILE.
 *
 * `tests` is the `tests:` section: what the card claims it does, as scenes.
 * One per file like `spec` and `script`, and null when the card declares none
 * — which is most cards, and which the pane shows as empty rather than hiding,
 * for the reason the logic pane does.
 *
 * `fixtures` is the `fixtures:` section: the card's named example states. One
 * per file, and the same null-rather-than-hidden treatment. It is the one
 * section whose PANE has a second pane beside it — the Examples panel mounts
 * what this names — which is why it is worth editing here rather than only in
 * the raw view.
 *
 * @typedef {{
 *   spec: Region | null,
 *   script: Region | null,
 *   tests: Region | null,
 *   fixtures: Region | null,
 *   views: Array<Region & { name: string, comp: string, id: string, idStart: number, idEnd: number }>,
 *   macros: Array<Region & { name: string, comp: string, id: string, idStart: number, idEnd: number }>,
 * }} Parts
 */

/** The section a `.tutu` heading opens, by the word it is spelled with. */
const SECTIONS = ["spec", "logic", "view", "fixtures", "tests"];

/** Every line of `source`, with the offset it starts at. */
function lines(source) {
  const out = [];
  let at = 0;
  for (const text of source.split("\n")) {
    out.push({ text, start: at, end: at + text.length });
    at += text.length + 1;
  }
  return out;
}

/** Whether a line opens a section: a bare word at column 0, then `:`. */
function sectionOn(line) {
  const m = /^([a-z]+):[ \t]*$/.exec(line.text);
  return m && SECTIONS.includes(m[1]) ? m[1] : null;
}

/**
 * The sections of a card, by name, as regions over its body.
 *
 * A body runs from the end of the heading line to the start of the next
 * heading — so it carries the leading newline `shape` reads the indentation
 * from, and stops before the blank line that separates two sections.
 */
function sections(source) {
  const ls = lines(source);
  const found = {};
  let open = null;
  const close = (endLine) => {
    if (!open) return;
    let end = endLine;
    // Trailing blank lines belong to the gap between sections, not to the body.
    while (end > open.first && ls[end - 1].text.trim() === "") end -= 1;
    const start = ls[open.at].end;
    found[open.name] = {
      text: source.slice(start, ls[end - 1].end),
      start,
      end: ls[end - 1].end,
    };
    open = null;
  };
  for (let i = 0; i < ls.length; i += 1) {
    const name = sectionOn(ls[i]);
    if (name === null) continue;
    close(i);
    open = { name, at: i, first: i + 1 };
  }
  close(ls.length);
  return found;
}

/**
 * Split a card into the regions the structured view edits.
 *
 * @param {string} source
 * @returns {Parts}
 */
export function parts(source) {
  const secs = sections(source);
  const views = [];
  const macros = [];
  if (secs.view) {
    const ls = lines(source).filter(
      (l) => l.start >= secs.view.start && l.end <= secs.view.end,
    );
    // A heading inside `view:` sits at exactly two spaces: `  Counter:`,
    // `  Counter.row:` for one of its named views, `  macro badge(…):` for a
    // macro. Anything deeper is that heading's body.
    const heads = [];
    for (let i = 0; i < ls.length; i += 1) {
      const m = /^ {2}(macro[ \t]+)?([A-Za-z_][\w.]*)[ \t]*(\([^)]*\))?[ \t]*:[ \t]*$/
        .exec(ls[i].text);
      if (m) heads.push({ i, isMacro: Boolean(m[1]), id: m[2], head: m });
    }
    for (let h = 0; h < heads.length; h += 1) {
      const { i, isMacro, id, head } = heads[h];
      let last = h + 1 < heads.length ? heads[h + 1].i : ls.length;
      while (last > i + 1 && ls[last - 1].text.trim() === "") last -= 1;
      const start = ls[i].end;
      const end = ls[Math.max(i, last - 1)].end;
      // Where the NAME's text starts, in file coordinates. A rename splices
      // exactly those characters, so the offset is measured rather than
      // guessed at.
      const idStart = ls[i].start + head[0].indexOf(id);
      // `Note.edit` is one component and one of its views; a bare heading is
      // the component's `main`.
      const comp = isMacro ? "" : id.split(".")[0];
      const name = isMacro
        ? id
        : id.includes(".")
          ? id.slice(id.indexOf(".") + 1)
          : "main";
      (isMacro ? macros : views).push({
        name,
        comp,
        id,
        text: source.slice(start, end),
        start,
        end,
        idStart,
        idEnd: idStart + id.length,
      });
    }
  }
  // What each TAB says.
  //
  // The view half alone while a card is one component, which is what it always
  // said: `main` and `row` are the two views of the only thing there is. That
  // stopped being enough the moment a card could declare two — `Todos` and
  // `Todo` are views of different components, and a strip reading `main` `main`
  // names neither. So the label is decided once the whole file has been read,
  // because it depends on how many components are IN it.
  const comps = new Set(views.map((v) => v.comp).filter((c) => c !== ""));
  if (comps.size > 1) {
    for (const v of views) v.name = v.name === "main" ? v.comp : v.id;
  }
  return {
    spec: secs.spec ?? null,
    script: secs.logic ?? null,
    tests: secs.tests ?? null,
    fixtures: secs.fixtures ?? null,
    views,
    macros,
  };
}

/**
 * How a region is laid out under its heading: the lines below it and the
 * indentation they share. Null when there is nothing under it.
 */
function shape(text) {
  if (!text.startsWith("\n")) return null;
  const body = text.slice(1).split("\n");
  const indents = body
    .filter((l) => l.trim() !== "")
    .map((l) => /^[ \t]*/.exec(l)[0]);
  if (indents.length === 0) return null;
  const shortest = indents.reduce((a, b) => (b.length < a.length ? b : a));
  // Tabs here and spaces there: no common prefix exists, so take none rather
  // than slice a line at a column that means nothing in it.
  const indent = indents.every((i) => i.startsWith(shortest)) ? shortest : "";
  return { body, indent };
}

/**
 * A region's body, without the indentation the section it sits in gave it.
 *
 * The one thing the structured panes normalize. A pane that opens with a blank
 * line and puts `@div` at column 4 is showing where the body sits in the FILE,
 * and the file is what the raw view is for — here the author is editing the
 * view itself, so it starts at column 0. `reindented` puts the file's shape
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
 * the way the section reads NOW.
 *
 * @param {string} text a region's text, as `parts` sliced it
 * @param {string} pane what the pane holds
 */
export function reindented(text, pane) {
  const s = shape(text);
  const indent = s ? s.indent : "  ";
  // Blank lines stay blank: indenting them is how a file grows the trailing
  // whitespace nobody typed.
  const body = pane.split("\n").map((l) => (l === "" ? "" : indent + l));
  return `\n${body.join("\n")}`;
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

/** The component this card declares, for naming a new view. */
export function componentOf(source) {
  const p = parts(source);
  const named = p.views.find((v) => v.comp !== "");
  if (named) return named.comp;
  if (p.spec) {
    const m = /^ {2}([A-Z]\w*)/m.exec(p.spec.text);
    if (m) return m[1];
  }
  return "";
}

/** The source with `text` appended to a section, or the section created. */
function intoSection(source, name, text) {
  const secs = sections(source);
  const s = secs[name];
  if (s) {
    return source.slice(0, s.end) + text + source.slice(s.end);
  }
  const sep = source.endsWith("\n") ? "" : "\n";
  return `${source}${sep}\n${name}:${text}\n`;
}

/**
 * The source with a new empty view appended to `view:`.
 *
 * Appended rather than inserted beside its siblings, because an editor that
 * moved the author's other views to make room would be rewriting a file they
 * can see.
 *
 * @param {string} source
 * @param {string} name
 */
export function addView(source, name) {
  const comp = componentOf(source);
  const id = comp && name !== "main" ? `${comp}.${name}` : comp || name;
  return intoSection(source, "view", `\n\n  ${id}:\n    @div`);
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
  if (!v) return source;
  const comp = v.comp || componentOf(source);
  const id = name === "main" ? comp || name : comp ? `${comp}.${name}` : name;
  return source.slice(0, v.idStart) + id + source.slice(v.idEnd);
}

/**
 * The source with an empty `fixtures:` section appended.
 *
 * The body is one fixture rather than nothing, because the envelope is the
 * thing an author most needs shown: a fixture is a name, the fields it seeds,
 * and `~doc:`, `~view:`, `~drive:`, `~intents:`, `~tags:` and `~default`
 * beside them.
 *
 * @param {string} source
 */
export function addInit(source) {
  return intoSection(source, "fixtures", `\n\n  "fresh" ~default:\n    ~doc: ""`);
}

/**
 * The source with a new empty macro appended.
 *
 * The body carries `@slot` because a macro without one drops the children of
 * every call, which is the first thing an author writing one discovers by
 * losing them.
 *
 * @param {string} source
 * @param {string} name
 */
export function addMacro(source, name) {
  return intoSection(source, "view", `\n\n  macro ${name}():\n    @div{@slot}`);
}

/**
 * The source with macro `i` renamed.
 *
 * @param {string} source
 * @param {Parts} p
 * @param {number} i
 * @param {string} name
 */
export function renameMacro(source, p, i, name) {
  const m = p.macros[i];
  if (!m) return source;
  return source.slice(0, m.idStart) + name + source.slice(m.idEnd);
}
