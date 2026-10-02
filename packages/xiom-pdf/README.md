# xiom.pdf

> **Status:** `incubating` -- conformance-tested (25/25); published at `v0.1.2` on the XIOM registry.
> **Scope:** pure-XIOM PDF document STRUCTURE parser -- no rendering, no font
> or colour semantics, no content-stream interpretation.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`). The DEFLATE/zlib decoder is a local port, so no
> `xiom.compress.*` import is needed.

`xiom.pdf` parses the structural layer of a PDF file from a byte buffer:
tokens, indirect objects, streams, cross-reference tables and streams,
trailer chains, the page tree and the Info dictionary. It validates structure
strictly and reports every error as `pdf: <what> at <byte offset>`.

## What works

- **Lexer** (`pdf_lex`) -- whitespace and `%` comments; names with `#xx`
  escapes; integers and reals (signs, leading/trailing dots, exponents);
  literal strings with `\n \r \t \b \f \( \) \\ \ooo` escapes, nested
  parentheses and backslash line continuation; hex strings with the odd-nibble
  rule; `[ ]`, `<< >>`; keywords (`obj endobj stream endstream xref trailer
  startxref R true false null`); indirect references `N G R`.
- **Objects and streams** -- `N G obj` + value + optional `stream` (the
  CRLF/LF rule) + `endobj`. The stream data is bounded by `/Length` when it is
  a direct integer and verified against `endstream`, resolved through the
  object map when `/Length` is an indirect reference, and otherwise located by
  an `endstream` scan and flagged (`pdf_stream_bounds_scanned`).
- **Cross-reference sections** -- classic tables (subsections of 20-byte
  `offset gen n/f` entries plus a trailer dictionary); xref streams
  (`/Type /XRef`, `/W`, `/Index`, entry types 0/1/2) with FlateDecode payloads
  inflated by the local DEFLATE port; hybrid files (`/XRefStm`) merged with
  stream-over-table precedence; `/Prev` chain walking with a visited guard.
- **Trailer** -- `/Size /Root /Info /ID /Prev /Encrypt` recorded first-wins
  from the newest section; `startxref`; encrypted documents are flagged
  (`pdf_is_encrypted`), never decrypted.
- **Object lookup** -- every in-use xref entry is parsed into an object table;
  `pdf_find_object` / `pdf_deref` resolve references; object streams
  (`/Type /ObjStm`) are decoded and their objects merged.
- **Page tree** -- walk of `/Pages` -> `/Kids` -> `/Count` with a depth cap
  and a cycle guard; page accessors for MediaBox, Resources presence and
  `/Contents` references.
- **Info dictionary** -- Title/Author/Subject/CreationDate extracted as pool
  spans plus a generic `pdf_info_field` lookup.

## Honest caveats

- **Structure only.** Nothing is rendered: content streams, fonts, colours,
  images, annotations and outlines are parsed as values, never interpreted.
- **Strict validation.** The first structural error aborts `pdf_open`
  (missing header/startxref, malformed xref entry, bad or mismatched object
  header, unterminated string/container, missing `endobj`). Filter decode
  failures and unresolvable `/Length` references are *not* errors: they are
  flagged and the raw bytes stay available.
- **Filters.** Only FlateDecode (single name or one-element array) is decoded,
  and only where the parser itself needs the payload (xref streams, object
  streams). Other filters and PNG predictors > 1 set
  `pdf_xref_decode_error`; general stream access always exposes raw bytes.
- **Encryption.** `/Encrypt` documents are detected and flagged; strings and
  streams are not decrypted, so object values are exposed as stored.
- **Streams are in memory.** The whole file is one `Vec[UInt8]`; there is no
  cross-buffer streaming. `/Length`-less streams are rejected (the
  specification requires `/Length`).
- **Bitmap of sizes.** Inflated output is capped at 16 MiB, compressed input
  at 1 MiB, nesting at 64, xref sections at 64, pages at 100000; exceeding a
  cap is an error or a documented flag.
- **NUL bytes.** `Str` cannot carry NUL: decoded strings/names with a NUL are
  still exposed as raw bytes (`pdf_node_bytes`), while text accessors return
  `""`. A NUL inside a NAME escape (`#00`) is rejected.

## Usage

```xiom
use xiom.pdf;

fn main() -> Int {
  let data = /* read the file bytes into a Vec[UInt8] */;
  let r = pdf_open(&data);
  match r {
    Ok(doc) => {
      // Header and xref
      //   pdf_version(&doc)             -> "1.7"
      //   pdf_xref_type(&doc)           -> 1 table, 2 stream, 3 hybrid
      //   pdf_trailer_root_num(&doc)    -> catalog object number
      // Object lookup
      let root = pdf_root_node(&doc);
      let pages = pdf_dict_get(&doc, root, "Pages");
      // Page tree
      let n = pdf_page_count(&doc);
      var i = 0;
      while i < n {
        let pg = pdf_page_node(&doc, i);
        let mb = pdf_page_mediabox_node(&doc, i);
        // pdf_array_item(&doc, mb, 0..3) -> numeric nodes
        i = i + 1;
      }
      // Streams (raw)
      let raw = pdf_stream_data(&doc, 0);
      // FlateDecode helper (raw DEFLATE first, whole zlib stream second)
      let inflated = pdf_flate_decode(&raw);
      let whole_ok = pdf_zlib_decode(&raw);
    },
    Err(e) => { /* e = "pdf: <what> at <offset>" */ },
  };
  return 0;
}
```

Token-level use:

```xiom
let tokens = pdf_lex(&some_bytes);
match tokens {
  Ok(t) => {
    // pdf_token_count(&t), pdf_token_kind_name(pdf_token_kind(&t, i)),
    // pdf_token_text(&t, i), pdf_token_int(&t, i), pdf_keyword_name(...)
  },
  Err(e) => { },
};
```

## API surface

| Group | Functions |
|---|---|
| open / lex | `pdf_open`, `pdf_lex` |
| tokens | `pdf_token_count/kind/kind_name/start/end/int/generation/keyword/bytes/text/span`, `pdf_keyword_name/code` |
| document | `pdf_version`, `pdf_header_offset`, `pdf_startxref`, `pdf_xref_type/type_name` |
| xref | `pdf_xref_count/object_number/offset/generation/kind/kind_name/find`, `pdf_xref_section_count/section_offset`, `pdf_xref_decode_error` |
| trailer | `pdf_trailer_node/size/prev/root_num/info_num`, `pdf_is_encrypted`, `pdf_encrypt_num`, `pdf_has_id`, `pdf_id`, `pdf_id_span` |
| objects | `pdf_object_count/number/generation/offset/node/status/from_objstm`, `pdf_find_object`, `pdf_deref`, `pdf_root_node`, `pdf_info_node` |
| values | `pdf_node_count/kind/kind_name/start/end/int/generation/bool/number/bytes/text/span/raw/raw_bytes` |
| arrays/dicts | `pdf_array_len/item`, `pdf_dict_len/key_node/value_node/get` |
| pages | `pdf_pages_root_num`, `pdf_declared_page_count`, `pdf_page_count/page_node/page_object_num/page_mediabox_node/page_resources_present/page_contents_count/page_contents_node`, `pdf_pages_depth_capped` |
| info | `pdf_info_span/text/field/title/author/subject/creation_date` |
| streams | `pdf_stream_count/object/dict/data/data_start/data_len/declared_length/length_source/length_indirect/bounds_scanned` |
| flate | `pdf_flate_decode`, `pdf_zlib_decode` |

## Verification

```
& .\scripts\port.ps1 -Package xiom.pdf
```

runs `tests/test_conformance.xi` (25 synthetic-PDF checks) from the
repository root.

## License

MIT OR Apache-2.0.
