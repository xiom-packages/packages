# xiom.gemtext

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parse a Gemtext document into flat line storage and emit its
> canonical form; no Gemini transport, no URL validation, no rendering.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare`, `xiom.string.builder` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.gemtext` is a small, dependency-free codec for Gemtext, the line-based
text format served by Gemini servers. `gemtext_parse` classifies every line
of a document -- text, link (`=> URL [label]`), heading (`#`/`##`/`###`),
list item (`*`), quote (`>`), preformatted toggle (```` ``` ````), raw
preformatted content, and blank -- and stores it flat: seven parallel `Vec`s
for kinds, texts, link urls, link labels, heading levels and the preformatted
span pairs. `gemtext_emit` writes the canonical form back, one normalized
line per line with exactly one trailing newline.

The parser is byte-wise over a UTF-8 `Str`. CRLF is normalized to LF; TAB,
LF and CR-before-LF are the only accepted control bytes; a line starting with
`=>` without a URL is a deterministic `Err`. Lines inside a preformatted
block are always raw text lines, even when they start with `=>` or `#`. The
exact grammar, the URL-whitespace stance, the error catalog and the test
matrix are in `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `gemtext_parse(text)` | `Result[GemtextDoc, Str]` | Classify every line of `text` into flat storage, in order. CRLF works like LF; empty input has zero lines. Errors: control byte, link with missing url. |
| `gemtext_line_count(d)` | `Int` | Number of stored lines; `0` for the empty document. |
| `gemtext_kind(d, i)` | `Str` | `"text"`, `"link"`, `"heading"`, `"list-item"`, `"quote"`, `"preformatted"`, `"preformatted-text"` or `"blank"`; `""` out of range. |
| `gemtext_text(d, i)` | `Str` | Line text: text/heading/item/quote/raw text, the alt text on an opening toggle; `""` for links, blanks and a closing toggle. `""` out of range. |
| `gemtext_link_url(d, i)` | `Str` | Link URL; `""` when line `i` is not a link or `i` is out of range. |
| `gemtext_link_label(d, i)` | `Str` | Link label (may be `""`); `""` when line `i` is not a link or `i` is out of range. |
| `gemtext_heading_level(d, i)` | `Int` | Heading level `1`..`3`; `0` when line `i` is not a heading or `i` is out of range. |
| `gemtext_preformatted_span_count(d)` | `Int` | Number of preformatted blocks (toggle pairs). |
| `gemtext_preformatted_start(d, s)` | `Int` | Opening toggle line of span `s`; `-1` out of range. |
| `gemtext_preformatted_end(d, s)` | `Int` | One past the closing toggle line, so span `s` covers `[start, end)`; `-1` out of range. An unclosed block ends at the line count. |
| `gemtext_emit(d)` | `Str` | Canonical Gemtext: every line normalized, exactly one trailing LF, empty document emits `""`. |

A preformatted block occupies the half-open line range
`[gemtext_preformatted_start(d, s), gemtext_preformatted_end(d, s))` and
includes both toggle lines; lines between them that start with `=>` or `#`
are `"preformatted-text"`, never links or headings.

## Quick start

```xi
use xiom.gemtext;
use xiom.io;

fn main() -> Int {
  let src = "# Title\n=> https://example.com Home\n\n``` Python\nprint(1)\n```\n";
  let r = gemtext_parse(src);
  match r {
    Ok(d) => {
      io.println(gemtext_line_count(&d));            // 6
      io.println(gemtext_kind(&d, 0));               // heading
      io.println(gemtext_heading_level(&d, 0));      // 1
      io.println(gemtext_text(&d, 0));               // Title
      io.println(gemtext_link_url(&d, 1));           // https://example.com
      io.println(gemtext_link_label(&d, 1));         // Home
      io.println(gemtext_kind(&d, 4));               // preformatted-text
      io.println(gemtext_preformatted_span_count(&d)); // 1
      io.println(gemtext_preformatted_start(&d, 0)); // 3
      io.println(gemtext_preformatted_end(&d, 0));   // 6
      io.println(gemtext_emit(&d));                  // canonical src
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Error model

`gemtext_parse` has one error channel, `Result[GemtextDoc, Str]`. The first
error aborts the parse; no partial document is returned. Messages are
deterministic (decimal values via `xiom.convert.int_to_string`):

| Message | Condition |
|---|---|
| `gemtext: control byte <byte> at <pos>` | a C0 control other than TAB/LF/CR-before-LF, or DEL, at byte offset `<pos>` |
| `gemtext: link with missing url at <pos>` | a line starting with `=>` with an empty or whitespace-only remainder; `<pos>` is the line's byte offset |

Everything else is classified, never an error: `#### x` and `#x` are text
lines, an unrecognized construct (`- item`, `1. item`, leading spaces) is a
text line, and a URL never contains whitespace -- whitespace ends the URL and
starts the label, so `=> https://a b/c` is URL `https://a` with label `b/c`.
No URL validation happens beyond non-empty and whitespace-free.

## Canonical emission

`gemtext_emit` re-joins each stored line with a single space where a marker
and text are separate (`=> url label`, `# text`, `* text`, `> text`,
```` ``` alt ````) and leaves text, list-item and quote text and
preformatted-text bytes alone. It always writes one LF per line, including
the last, and emits `""` for the empty document. For already-canonical input,
`gemtext_emit(gemtext_parse(x)) == x`; canonicalization is idempotent.

## Usage notes

- Distinguish link text from its label: `gemtext_text(d, i)` is `""` on link
  lines; use `gemtext_link_url` / `gemtext_link_label`.
- Use `gemtext_line_count` plus `gemtext_kind` to iterate; every accessor is
  range-checked.
- Blank is empty or whitespace-only; whitespace-only lines inside a
  preformatted block stay raw `"preformatted-text"`.
- A closing toggle's trailing bytes are ignored (its text is `""`), and an
  opening toggle's alt text is whitespace-trimmed.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.gemtext
```

Expected tail: 23 `[PASS]` lines, `xiom.gemtext: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- Gemtext subset only: no Gemini protocol transport (TLS, requests,
  `text/gemini` negotiation), no URL validation, no rendering, no inline
  markup, no tables or nested structures, no link titles.
- A URL cannot contain whitespace: the first space/tab ends it and starts the
  optional label.
- Control bytes (including NUL and binary payloads) are rejected everywhere,
  including inside preformatted blocks; DEL is rejected too. Bytes >= 0x80
  pass through byte-exact (no UTF-8 validation).
- A line starting with ` ``` ` always closes a preformatted block, so a
  toggle line cannot appear inside raw content.
- Heading and alt text are trimmed at parse time and whitespace-only lines
  are blank, so those bytes are not recoverable through emission.
- Errors are first-failure only, with byte offsets (no line numbers) and no
  recovery or partial results; the API is whole-document (no streaming).
- Hand-built `GemtextDoc` values are emitted best-effort, not validated.

See `SPEC.md` for the full grammar, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
