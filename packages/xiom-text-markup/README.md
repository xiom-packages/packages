# xiom.text-markup

> **Status:** `incubating` -- conformance-tested (26/26); not yet published on the XIOM registry.
> **Scope:** a deterministic BBCode-style inline markup codec: parse `[b]`,
> `[i]`, `[u]`, `[code]` and `[url=...]` with proper-nesting validation, expose
> span records over the source text, render to plain text and re-serialize
> canonically.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`,
> `xiom.string.builder` and `xiom.convert.int_to_string`). Tests additionally
> use `xiom.test` and `xiom.io`.

## What it is

`xiom.text-markup` is a small, total, pure-XIOM codec for the inline half of
BBCode-style markup. It gives you three views of one document:

1. **Records** -- `markup_parse` returns a `Markup` arena (eight parallel `Vec`
   fields) with one record per closed tag pair: the tag code, the open-tag and
   close-tag byte spans, and the raw attribute span. There is no
   `Vec[StructType]` anywhere.
2. **Plain text** -- `markup_to_plain` strips every tag, decodes the three
   escapes and the four named entities, and copies `[code]` content verbatim.
3. **Canonical text** -- `markup_to_canonical` re-emits the tags in their
   original spelling and the text with minimal escaping, so re-parsing the
   output yields the same records and the same plain text.

Parsing validates proper nesting: every close tag must match the innermost
open tag, so `[i][b]x[/i][/b]` is a documented error rather than silent
recovery. See `SPEC.md` for the grammar, the nesting and escape rules and the
exact error catalog.

## Relationship to the other text packages

| Package | What it does | Where the overlap ends |
|---|---|---|
| `xiom.markdown` | line-based Markdown subset to HTML (`**bold**`, `*em*`, links, lists, fences). | Markdown markers are sigils, not bracketed tags; there are no attributes and invalid nesting is rendered literally. `xiom.text-markup` parses `[tag]` syntax with attributes, span records and exact nesting errors, and produces spans/plain text, not HTML. |
| `xiom.html` | HTML parsing/serialization. | HTML has named elements, entities and its own tree/error model; this package is the small BBCode-style inline dialect only. |

## API

Tags and table:

| Function | Returns | Description |
|---|---|---|
| `markup_tag_name(code)` | `Str` | `"b"`, `"i"`, `"u"`, `"code"`, `"url"`, `"none"`. |
| `markup_tag_code(name)` | `Int` | Exact, case-sensitive code, or `MARKUP_TAG_NONE`. |

Parse and whole-document helpers:

| Function | Returns | Description |
|---|---|---|
| `markup_parse(source)` | `Result[Markup, Str]` | Parse with nesting validation; first error in source order. |
| `markup_is_valid(source)` | `Bool` | True when `markup_parse` succeeds. |
| `markup_plain(source)` / `markup_canonical(source)` | `Result[Str, Str]` | Parse + render in one call. |

Records (range-safe: `NONE`/`-1`/`""` out of range):

| Function | Returns | Description |
|---|---|---|
| `markup_span_count(m)` | `Int` | Number of tag-pair records. |
| `markup_span_tag(m, i)` | `Int` | Tag code of record `i`. |
| `markup_span_open_start(m, i)` / `markup_span_open_end(m, i)` | `Int` | Open-tag byte span (`[b]`). |
| `markup_span_close_start(m, i)` / `markup_span_close_end(m, i)` | `Int` | Close-tag byte span (`[/b]`). |
| `markup_span_attr(source, m, i)` | `Str` | Raw attribute value span (url only), else `""`. |
| `markup_span_inner(source, m, i)` | `Str` | Raw bytes between the open and close tags. |

Renderers:

| Function | Returns | Description |
|---|---|---|
| `markup_to_plain(source, m)` | `Str` | Tags stripped; `\[`, `\]`, `\\` and `&amp;`, `&lt;`, `&gt;`, `&quot;` decoded; code content verbatim. |
| `markup_to_canonical(source, m)` | `Str` | Tags re-emitted; text decoded then minimally escaped; idempotent. |

## Usage

```xi
use xiom.text_markup;
use xiom.io;

fn main() -> Int {
  let src = "[b]bold[/b] and [url=https://x.io]a link[/url]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      io.println(markup_span_count(&m));                    // 2
      io.println(markup_span_attr(src, &m, 1));             // https://x.io
      io.println(markup_to_plain(src, &m));                 // bold and a link
      io.println(markup_to_canonical(src, &m));             // the input itself
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.text-markup
```

Expected tail: 26 `[PASS]` lines, `xiom.text-markup: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Inline tags only.** No block structure, no lists, no headings, no tables;
  that is `xiom.markdown`'s territory.
- **Five tags, lowercase, case-sensitive.** `[B]` and `[foo]` are
  `unknown tag` errors, not aliases.
- **One attribute form.** Only `url` takes an attribute, spelled
  `[url=value]`; the value is the raw bytes up to the first `]` and must be
  non-empty. `[url]` is valid and carries no attribute.
- **`[code]` consumes to the first `[/code]`.** Nothing inside is interpreted
  (tags, escapes and entities are literal), and the closing sequence cannot be
  escaped.
- **Entities are decoded, not re-encoded.** Canonical form emits `& < > "`
  bare; the four named entities are decoded by both renderers.
- **No error recovery.** The first error aborts with an exact message and
  position; no partial records are returned.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
