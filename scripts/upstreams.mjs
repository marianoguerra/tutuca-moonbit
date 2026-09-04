// URL builders for the upstreams the generated tables are fetched from.
//
// Shared so the URL shape has one owner, NOT so the pins do: each generator
// pins its own commit and passes it in. `fetch-dom-props.mjs` extracts WebIDL
// from `ed/idl/` and `fetch-css-properties.mjs` extracts CSS grammars from the
// spec extracts, and there is no reason an upgrade to one has to be an upgrade
// to the other — coupling the pins would make every table move whenever any
// spec did.
//
// Each generator's own header says what it pins and how to bump it.

/// A file in w3c/webref at `commit`, raw.
export const webrefRaw = (commit, path) =>
  `https://raw.githubusercontent.com/w3c/webref/${commit}/${path}`;

/// The recursive tree listing for w3c/webref at `commit`. Used to discover
/// which spec extracts exist rather than hard-coding the list.
export const webrefTree = (commit) =>
  `https://api.github.com/repos/w3c/webref/git/trees/${commit}?recursive=1`;

/// A file in mdn/data at `commit`, raw.
export const mdnRaw = (commit, path) =>
  `https://raw.githubusercontent.com/mdn/data/${commit}/${path}`;
