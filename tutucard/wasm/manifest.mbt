// The static half of a bundle.
//
// A card already IS a manifest: the state block names the fields and their
// types, the `<template>`s are the views, the script names the messages and
// the methods, and a `tutuca/init` block is a named example. So this is a
// projection rather than a second thing to author — which is the answer to the
// "manifest authoring" open question in
// `docs/generative-dyncomps-in-the-browser-design.md`, at least for a card.
//
// The shape is `dyncomp/host/manifest.mbt`'s, and the one difference from a
// packed archive's is that views arrive as `html` rather than as a `src` the
// loader hydrates: there is no archive here, only a page that has the card.

///|
/// The `DynManifest` JSON for a compiled card.
fn manifest_json(
  g : Gen,
  decls : Array[@tscript.Decl],
  views : @viewfile.ViewSet,
  file : @viewfile.ViewFile,
) -> Json {
  let types : Array[Json] = []
  let ty_index : Map[String, Int] = Map([])
  let fields : Array[Json] = []
  for f in g.fields {
    let key = f.ty.show_source()
    let at = match ty_index.get(key) {
      Some(i) => i
      None => {
        let i = types.length()
        types.push(ty_entry(f.ty))
        ty_index[key] = i
        i
      }
    }
    fields.push(
      Json::object({
        "name": Json::string(f.name),
        "ty": Json::number(at.to_double()),
        "doc": Json::string(f.doc.unwrap_or("")),
        "required": Json::boolean(false),
      }),
    )
  }
  // Every name this card answers, of one kind — the ones it compiled and the
  // ones its escape block answered. A host routes by this list, so a name
  // answered in Wax has to be in it for the same reason a refused one has to be
  // out: the manifest DESCRIBES the guest.
  let compiled : (@tscript.DeclKind) -> Array[String] = kind => {
    let word = @tscript.kind_word(kind)
    let out : Array[String] = []
    for _key, e in g.escapes {
      if e.kind == word {
        out.push(e.name)
      }
    }
    for d in decls {
      if d.kind == kind && is_compiled(g, d) && !g.escaped(word, d.name) {
        out.push(d.name)
      }
    }
    out
  }
  let docs : Array[Json] = []
  for d in decls {
    if d.doc != "" {
      docs.push(
        Json::object({
          "name": Json::string(d.name),
          "doc": Json::string(d.doc),
        }),
      )
    }
  }
  let view_defs : Array[Json] = views.views.map(v => {
    Json::object({
      "name": Json::string(v.name),
      "html": Json::string(v.source),
    })
  })
  // The file's macros travel with it. `split_file` has been returning them all
  // along and this dropped them, which made `<x:badge>` in a compiled card an
  // unknown element that rendered as itself — the same bug the card LOADER had
  // and fixed, one backend later.
  let macro_defs : Array[Json] = file.macros.map(m => {
    let defaults : Map[String, Json] = Map([])
    for k, v in m.defaults {
      defaults[k] = Json::string(v)
    }
    Json::object({
      "name": Json::string(m.name),
      "defaults": Json::object(defaults),
      "html": Json::string(m.source),
    })
  })
  // `inits` stays empty. A `tutuca/init` block's field values are MoonBit
  // SOURCE — the generator that consumes them writes them into a `make` call
  // — and a manifest wants JSON. Projecting one into the other is a small
  // evaluator, which is a thing to add deliberately rather than in passing.
  Json::object({
    "manifestVersion": Json::number(1),
    "apiVersion": Json::number(7),
    "moduleName": Json::string(g.comp.to_lower() + "card"),
    "doc": Json::string(g.def.doc.unwrap_or("")),
    "version": Json::string("0.1.0"),
    "homepage": Json::string(""),
    "authors": Json::array([]),
    // Nothing is asked for, and that is not a placeholder: a compiled card has
    // no clock, no entropy and no timer, because nothing it can express needs
    // one. A capability it did not import could not be used anyway — the host
    // checks the IMPORT SECTION — so asking for one would be a promise rather
    // than a grant.
    "capabilities": Json::array([]),
    "stringEncoding": Json::string("utf8"),
    "macros": Json::array(macro_defs),
    "components": Json::array([
      Json::object({
        "name": Json::string(g.comp),
        "doc": Json::string(g.def.doc.unwrap_or("")),
        "keywords": Json::array([]),
        "category": Json::string(""),
        "messageDocs": Json::array(docs),
        "views": Json::array(view_defs),
        "types": Json::array(types),
        "fields": Json::array(fields),
        "receives": strings(compiled(DReceive)),
        "bubbles": strings(compiled(DBubble)),
        "responses": strings(compiled(DResponse)),
        "methods": strings(
          compiled(DCompute) + compiled(DPred) + compiled(DInvariant),
        ),
        "whens": strings(compiled(DPred)),
        // The two the manifest had no key for, which is half of why a card
        // using `@enrich-with` used to lose its bindings in silence: the other
        // half was that nothing compiled them, and a host cannot route to a
        // name it was never told about.
        "enriches": strings(compiled(DEnrich)),
        "enrichScopes": strings(compiled(DEnrichScope)),
        "requests": Json::array([]),
        "inits": Json::array([]),
        "style": Json::string(views.common_style),
      }),
    ]),
  })
}

///|
/// Whether a declaration made it into the module.
///
/// The manifest DESCRIBES the guest, so a name the generator refused must not
/// appear in it: a host told a component answers `toggle` will route `toggle`
/// to it and get `unhandled` back, having skipped the field mutator that would
/// have worked.
fn is_compiled(g : Gen, d : @tscript.Decl) -> Bool {
  if d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) {
    return g.callables.get(d.name) is Some(_)
  }
  for r in g.refusals {
    if r.name == d.name && r.kind == @tscript.kind_word(d.kind) {
      return false
    }
  }
  true
}

///|
fn strings(xs : Array[String]) -> Json {
  Json::array(xs.map(x => Json::string(x)))
}

///|
/// The flat type-table entry a declared type projects to.
fn ty_entry(ty : @statedef.StateTy) -> Json {
  let (kind, name, members) = match ty {
    TBool => ("ty-bool", "", [])
    TInt(..) => ("ty-int", "", [])
    TFloat => ("ty-float", "", [])
    TText => ("ty-text", "", [])
    TList(_) => ("ty-list", "", [])
    TTuple(_) => ("ty-tuple", "", [])
    TOption(_) => ("ty-option", "", [])
    TOMap(_) => ("ty-omap", "", [])
    TSet => ("ty-set", "", [])
    TRecord(n) => ("ty-record", n, [])
    TEnum(n) => ("ty-enum", n, [])
    TVariant(n) => ("ty-variant", n, [])
    TFlags(n) => ("ty-flags", n, [])
    TComp(n) => ("ty-comp", n.unwrap_or(""), [])
    TAny => ("ty-any", "", [])
  }
  Json::object({
    "kind": Json::string(kind),
    "items": Json::array([]),
    "name": Json::string(name),
    "members": strings(members),
  })
}
