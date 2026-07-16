// lint_html driver: feeds @html5's WHATWG tokenizer into the prediction
// machine. Token-level rules that need raw source (case, offsets) use
// rawscan.mbt on each token's span; rules the tokenizer already detects
// (duplicate attrs, end-tag attrs, missing values, CDATA, bogus comments)
// come from its collected ParseErrors, drained inline so namespace gating
// and finding order stay correct.

///|
pub fn lint_html(
  html : String,
  fragment_context? : String = "template",
  transparent_tag_prefixes? : Array[String] = ["x"],
) -> Array[Finding] {
  let chars : Array[Char] = html.iter().collect()
  let m = Machine::new(chars, fragment_context, transparent_tag_prefixes)
  let tk = @html5.Tokenizer::new(html)
  let mut err_idx = 0
  let mut run_start = -1
  let mut run_end = -1
  for ;; {
    let pos_before = tk.get_position().offset
    let token = tk.next_token()
    let pos_after = tk.get_position().offset
    // Coalesce Character tokens into text runs; flush on anything else.
    match token {
      Character(_) => {
        if run_start < 0 {
          run_start = pos_before
        }
        run_end = pos_after
      }
      _ =>
        if run_start >= 0 {
          m.on_text(run_start, run_end)
          run_start = -1
          run_end = -1
        }
    }
    match token {
      StartTag(name~, attrs=_, self_closing~) => {
        let (raw_name, name_start, raw_attrs) = scan_start_tag(
          chars, pos_before, pos_after,
        )
        m.handle_start_tag(name, raw_name, raw_attrs, self_closing, name_start)
        // The standalone tokenizer lacks the tree constructor's feedback
        // loop: switch content states by tag name, namespace-unaware —
        // exactly what htmlparser2 did for the JS linter.
        if !self_closing {
          match name {
            "script" => tk.switch_to_script_data()
            "title" | "textarea" => tk.switch_to_rcdata()
            "style" | "xmp" | "iframe" | "noembed" | "noframes" =>
              tk.switch_to_rawtext()
            "plaintext" => tk.switch_to_plaintext()
            _ => ()
          }
        }
      }
      // Offset +2 points at the tag name (past "</").
      EndTag(name~) => m.handle_end_tag(name, pos_before + 2)
      EOF => {
        err_idx = drain_errors(m, tk, err_idx)
        break
      }
      _ => ()
    }
    err_idx = drain_errors(m, tk, err_idx)
  }
  m.out
}

///|
/// Map newly collected tokenizer ParseErrors to findings. Only the codes the
/// JS linter surfaced are mapped; everything else (charref/doctype noise) is
/// intentionally dropped.
fn drain_errors(m : Machine, tk : @html5.Tokenizer, from : Int) -> Int {
  let errs = tk.get_errors()
  for i in from..<errs.length() {
    let err = errs[i]
    let offset = err.position.offset
    match err.code {
      EndTagWithAttributes =>
        m.report(
          HtmlAttributesOnEndTag,
          Warn,
          offset,
          [],
          suggestion=Remove(what="attributes from the end tag"),
        )
      EndTagWithTrailingSolidus =>
        m.report(HtmlSelfClosingEndTag, Warn, offset, [])
      MissingAttributeValue =>
        m.report(HtmlMissingAttributeValue, Warn, offset, [])
      DuplicateAttribute =>
        m.report(
          HtmlDuplicateAttribute,
          Warn,
          offset,
          [],
          suggestion=Remove(what="the duplicate attribute"),
        )
      // CDATA is only valid in foreign content; gate on the machine's
      // namespace at this point in the stream.
      CdataInHtmlContent =>
        if m.current_namespace() is NsHtml {
          m.report(HtmlCdataInHtmlNamespace, Warn, offset, [
            ("mode", m.insertion_mode.to_name()),
          ])
        }
      IncorrectlyOpenedComment | UnexpectedQuestionMarkInsteadOfTagName =>
        m.report(HtmlBogusComment, Warn, offset, [
          ("mode", m.insertion_mode.to_name()),
        ])
      // `</1foo>` style bogus comments arrive as this code; `<3`-style text
      // does too, so only report when the source really opened an end tag.
      InvalidFirstCharacterOfTagName =>
        if offset >= 1 &&
          offset < m.chars.length() &&
          m.chars[offset - 1] == '/' {
          m.report(HtmlBogusComment, Warn, offset, [
            ("mode", m.insertion_mode.to_name()),
          ])
        }
      _ => ()
    }
  }
  errs.length()
}
