# xiom.expat

> **Status:** 0.1.0 (incubating, not published).
> **Scope:** pure-XIOM expat-style event parser for XML 1.0.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`, `xiom.convert`).

An event-based XML 1.0 parser in the spirit of expat: byte-oriented, no DTD
validation, no namespace resolution beyond recording prefixed names and
`xmlns` attribute strings verbatim. `SPEC.md` documents the exact grammar
subset, limits, API contract and error catalog this package actually
implements -- this README is the quick tour.

## What works

- **Encoding** -- UTF-8 byte-oriented by default; UTF-8 BOM stripped;
  a declared `ISO-8859-1` / `latin1` encoding triggers a Latin-1 fallback
  (bytes `0x80-0xFF` are decoded to `U+0080-U+00FF`); an XML declaration's
  `version`, `encoding` and `standalone` pseudo-attributes are recorded.
- **Events** -- XML declaration, DOCTYPE (name, `SYSTEM`/`PUBLIC` ids, raw
  internal subset), comments, processing instructions, CDATA sections, start
  elements with attributes, end elements, character-data runs (whitespace
  preserved). Empty elements emit a start event followed by an end event.
  Every event carries its byte offset plus 1-based line/column, its consumed
  byte count, and (for start events) a slice of the attribute store.
- **Entities** -- `&lt; &gt; &amp; &apos; &quot;`, decimal/hex character
  references (`&#65;`, `&#x41;`), and internal-subset general entities
  (`<!ENTITY name "value">`) with recursive expansion capped at depth 16 and
  64 KiB per text/attribute run. Unknown or malformed references are errors.
  References expand in text and attribute values only (never inside comments,
  PIs or CDATA).
- **Well-formedness** -- matching end tags against a bounded open-element
  stack (depth 256), single root element, no non-whitespace text before or
  after the root, attribute quoting/duplicate detection, raw `<` rejected in
  attribute values, raw `]]>` rejected in text, raw control bytes rejected,
  UTF-8 validated (overlongs, truncated sequences, surrogates and > U+10FFFF
  rejected).

## Honest caveats

- **UTF-16 is detected and rejected.** `UTF-16LE`/`UTF-16BE` BOMs are
  recognised (`expat: UTF-16LE input unsupported at 0`), but XIOM `Str` is
  NUL-terminated and cannot carry UTF-16 bytes (every ASCII code unit contains
  a NUL byte), so a UTF-16 document cannot survive in a `Str` at all.
- **No DTD validation.** The internal subset is preserved raw and scanned only
  for `<!ENTITY>` declarations; `<!ELEMENT>`, `<!ATTLIST>` and friends are
  skipped, not validated. External and parameter entities are unsupported
  (parameter entity declarations are an error).
- **No namespace resolution.** `ns:tag` is one opaque name; `xmlns:ns="uri"`
  is an ordinary attribute. `expat_prefix_of` / `expat_local_of` split on the
  first `:` as a convenience.
- **ASCII name subset.** `NameStartChar`/`NameChar` are enforced for ASCII;
  bytes `>= 0x80` (validated UTF-8) pass through as name/character data, so
  the full Unicode name ranges are not enforced.
- **No line-end normalization.** Raw CR/LF bytes are preserved in text,
  comment, PI and CDATA payloads (attribute values are normalized: tab/LF/CR
  become space). Offsets are byte offsets into the decoded text (BOM stripped;
  Latin-1 re-encoded).
- **No error recovery** -- the first malformed construct aborts with
  `Err("expat: <what> at <byte offset>")`. The whole input is one `Str`; there
  is no cross-buffer streaming, but `expat_open` + `expat_next_event` does
  incremental event consumption over the in-memory text.

## Usage

```xiom
use xiom.expat;

fn main() -> Int {
  let r = expat_parse("<?xml version=\"1.0\"?><r a=\"1\">hi<b/></r>");
  match r {
    Err(e) => { /* e is "expat: <what> at <offset>" */ },
    Ok(st) => {
      // Walk the event stream.
      var i = 0;
      while i < expat_event_count(&st) {
        // expat_event_kind_name: "decl"|"doctype"|"comment"|"pi"|"cdata"|"start"|"end"|"text"
        // expat_event_name / expat_event_data / expat_event_offset ...
        i = i + 1;
      }
      // One-shot helpers:
      //   expat_element_count(&st)            -> element count
      //   expat_element_name(&st, ei)         -> element name
      //   expat_extract_attribute(&st, ei, n) -> attribute value or ""
      //   expat_text_content(&st, ei)         -> concatenated text/CDATA
    },
  };
  return 0;
}
```

Streaming consumption of the same text:

```xiom
let o = expat_open(text);
match o {
  Ok(st) => {
    var s = st;
    loop {
      let r = expat_next_event(&mut s);
      match r {
        Ok(k) => { if k < 0 { break; } /* k is the event kind */ },
        Err(e) => { break; },
      };
    }
  },
  Err(e) => { },
};
```

## API surface

| Function | Purpose |
|---|---|
| `expat_parse(text)` | whole document -> `Result[ExpatState, Str]` |
| `expat_open(text)` | session without consuming events |
| `expat_next_event(&mut st)` | next event kind, or `Ok(-1)` at end |
| `expat_event_count/kind/kind_name/name/data` | event readers |
| `expat_event_system_id/public_id/standalone` | DOCTYPE / declaration payloads |
| `expat_event_offset/line/column/consumed` | positions |
| `expat_event_attr_count/name/value/quote` | per-event attributes |
| `expat_encoding/version/standalone/has_decl/has_doctype/depth` | document metadata |
| `expat_entity_count/name/value` | internal entities from the subset |
| `expat_element_count/event/name/depth` | element index -> event |
| `expat_element_attr_count/name/value` | attributes by element index |
| `expat_extract_attribute(st, ei, name)` | attribute value by name |
| `expat_text_content(st, ei)` | descendant text + CDATA |
| `expat_prefix_of(name)`, `expat_local_of(name)` | qualified-name split, no resolution |

## Verification

```
& .\scripts\port.ps1 -Package xiom.expat
```

runs `tests/test_conformance.xi` (25 checks) from the repository root.

## License

MIT OR Apache-2.0.
