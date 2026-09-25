# xiom.gemtext -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.gemtext`, version `0.1.0`).
Module: `src/gemtext.xi` (`module xiom.gemtext`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`,
`xiom.string.builder`, `xiom.convert`).

## 1. Scope

A pure-XIOM (no FFI) codec for Gemtext, the line-based text format of the
Gemini protocol:

- `gemtext_parse(text)` -- classify every line and store the document flat;
- read-only accessors -- line count, kind, text, link url/label, heading
  level, preformatted spans;
- `gemtext_emit(doc)` -- the canonical Gemtext form of a parsed document,
  with exactly one trailing LF per line.

`Str` is treated as a UTF-8 byte buffer; parsing is byte-wise and the codec
assumes no line semantics beyond the ones below. Storage is flat (parallel
`Vec`s) because XIOM v0.61.3 cannot hold `Vec[StructType]`.

## 2. Non-goals

- Gemini protocol transport (TLS, requests, responses, `text/gemini` MIME
  negotiation); this package never touches the network.
- URL validation beyond non-empty/no-whitespace: no scheme check, no percent
  encoding, no normalization, no resolution.
- Rendering: no HTML conversion, no terminal layout, no link numbering.
- Inline markup inside text, headings, list items, quotes or labels: line
  text is always kept verbatim.
- Line semantics beyond the eight kinds: no tables, no nesting, no
  continuation lines, no link titles.
- Streaming/incremental parsing; the whole document is one `Str`.
- UTF-8 validation or normalization: bytes >= 0x80 pass through byte-exact.
- Control bytes other than TAB, LF and CR-before-LF (they are rejected, not
  sanitized).

## 3. Input model

- Input is one `Str`; lines are separated by LF (0x0A).
- A single CR (0x0D) immediately before an LF is stripped, so CRLF input
  behaves exactly like LF input. A CR anywhere else is rejected.
- The characters TAB (0x09) and space (0x20) are horizontal whitespace
  (`hspace` below). A space is not the same as a tab: heading and list-item
  markers require a literal space.
- Every other C0 byte (0x00-0x1F except TAB/LF/CR-before-LF) and DEL (0x7F)
  is rejected with the error in section 5. This applies to the whole input,
  including lines inside preformatted blocks.
- Empty input has zero lines. A trailing LF adds no empty last line:
  `"a\n"` is one line, `"a\n\n"` is two.

## 4. Line grammar

Informal grammar (`hspace = SP | TAB`; `text` is arbitrary bytes):

```
document     = *line                        LF-separated; empty input = 0 lines
line         = blank | toggle | link | heading | item | quote | text
blank        = 0*(hspace)                   (whitespace-only or empty)
toggle       = "```" *char                  opens or closes a preformatted block
link         = "=>" *hspace url [hspace label]
url          = 1*(BYTE - hspace)            non-empty, whitespace-free
label        = *char                        rest of the line (may be empty)
heading      = ("#" | "##" | "###") (SP text | eol)
item         = "*" | "*" SP text
quote        = ">" | ">" SP text
text         = line
```

Classification order, first match wins (every decision is covered by the
conformance suite):

1. **Inside a preformatted block** every line is raw `"preformatted-text"`,
   except a line starting with ` ``` `, which is the closing toggle
   (`"preformatted"`, text `""`, trailing bytes ignored). Inside a block,
   `=>`, `#`, `*`, `>` and even empty/whitespace-only lines keep their raw
   bytes and their raw kind.
2. **Blank** -- `str_trim(line) == ""`. Stored kind `"blank"`, text `""`.
   Canonical emission writes an empty line.
3. **Toggle** -- the line starts with exactly ` ``` ` at byte 0. The toggle
   opens a block and its text is the alt text: the remainder after the three
   backticks, whitespace-trimmed. Four backticks are one toggle plus alt
   `` ` ``; leading whitespace means the line is not a toggle.
4. **Link** -- the line starts with `=>` at byte 0. Whitespace after `=>` is
   optional. The URL is the maximal run of non-`hspace` bytes; the first
   `hspace` ends it. The label is the rest of the line with leading
   whitespace dropped (trailing whitespace kept, inner spaces kept, may be
   empty). The URL is required: `=>`, `=>   ` and `=>\t` are errors
   (section 5). A leading space before `=>` makes the line text.
5. **Heading** -- 1, 2 or 3 `#` followed by a literal space (0x20) or by the
   end of the line. The heading text is the remainder after the hashes,
   whitespace-trimmed; `###` alone is an empty level-3 heading. Four or more
   hashes (`#### x`, `########`), no space (`#x`), a tab (`##\tx`) and
   leading whitespace (` # x`) all make the line **text**.
6. **List item** -- `*` alone (empty item) or `*` followed by a literal
   space; the item text is the rest of the line (leading extra spaces kept
   after the single marker space). `**x**`, `*-` and `*\tx` are text.
7. **Quote** -- the first byte is `>`. `> ` (two bytes) is dropped, or `>`
   alone; the quote text is the remainder (`>x` -> `x`, `>>` -> `>`, `>` ->
   `""`, `> ` -> `""`). Nested quotes have no semantics.
8. **Text** -- everything else, stored verbatim (no trimming, no marker
   interpretation).

## 5. Error catalog

`gemtext_parse` returns `Result[GemtextDoc, Str]`. The first error aborts the
parse; no partial document is returned, and messages are deterministic
(decimal numbers built with `xiom.convert.int_to_string`).

| Message | Condition | Position |
|---|---|---|
| `gemtext: control byte <byte> at <pos>` | the byte at `<pos>` is a C0 control other than TAB/LF/CR-before-LF, or DEL; `<byte>` is its unsigned decimal value (`0`..`31`, `127`) | the byte itself |
| `gemtext: link with missing url at <pos>` | a line starting with `=>` whose remainder is empty or whitespace-only | the byte offset of the line's first byte |

Documented non-errors:

- **URL whitespace stance.** A URL cannot contain whitespace. Whitespace
  after the URL starts the label, so `=> https://a b/c` parses as URL
  `https://a` and label `b/c`; it is not an error. There is no escaping
  mechanism for a whitespace-bearing URL in this subset.
- **Heading with >3 hashes is text.** `####`, `########` and `#### x` are
  text lines, never headings and never errors.
- **Anything unrecognized is text.** `- item`, `1. item`, `![img](u)`,
  `*not a marker` and a leading-space `=>` are all text lines.

## 6. Flat storage and API contract

```xi
pub type GemtextDoc = {
  kinds: Vec[Str];        // one kind per line, in document order
  texts: Vec[Str];        // line text (see the accessor table below)
  urls: Vec[Str];         // link URL, "" otherwise
  labels: Vec[Str];       // link label, "" otherwise
  levels: Vec[Int];       // heading level 1..3, 0 otherwise
  pre_starts: Vec[Int];   // opening toggle line of each preformatted block
  pre_ends: Vec[Int];     // one past the closing toggle line of the block
}

pub fn gemtext_parse(text: Str) -> Result[GemtextDoc, Str]
pub fn gemtext_line_count(d: &GemtextDoc) -> Int
pub fn gemtext_kind(d: &GemtextDoc, i: Int) -> Str
pub fn gemtext_text(d: &GemtextDoc, i: Int) -> Str
pub fn gemtext_link_url(d: &GemtextDoc, i: Int) -> Str
pub fn gemtext_link_label(d: &GemtextDoc, i: Int) -> Str
pub fn gemtext_heading_level(d: &GemtextDoc, i: Int) -> Int
pub fn gemtext_preformatted_span_count(d: &GemtextDoc) -> Int
pub fn gemtext_preformatted_start(d: &GemtextDoc, s: Int) -> Int
pub fn gemtext_preformatted_end(d: &GemtextDoc, s: Int) -> Int
pub fn gemtext_emit(d: &GemtextDoc) -> Str
```

Kind strings: `"text"`, `"link"`, `"heading"`, `"list-item"`, `"quote"`,
`"preformatted"`, `"preformatted-text"`, `"blank"`. Parsing always keeps all
seven `Vec`s aligned and both span `Vec`s the same length.

Per-kind `gemtext_text` and fields:

| Kind | `gemtext_text` | `urls` / `labels` | `levels` |
|---|---|---|---|
| `text` | the line verbatim | `""` | `0` |
| `link` | `""` (use the link accessors) | URL / label (label may be `""`) | `0` |
| `heading` | heading text, trimmed | `""` | `1`, `2` or `3` |
| `list-item` | item text | `""` | `0` |
| `quote` | quote text | `""` | `0` |
| `preformatted` (opening) | alt text, trimmed | `""` | `0` |
| `preformatted` (closing) | `""` | `""` | `0` |
| `preformatted-text` | the raw line | `""` | `0` |
| `blank` | `""` | `""` | `0` |

Preformatted spans: span `s` covers the half-open line range
`[gemtext_preformatted_start(d, s), gemtext_preformatted_end(d, s))`,
including the opening and closing toggle lines. A block left open at end of
input closes leniently, so its `end` is the line count. An opening toggle is
any `"preformatted"` line at a span start; every other `"preformatted"` line
is a closing toggle.

Out-of-range accessors: `gemtext_kind`/`gemtext_text`/`gemtext_link_url`/
`gemtext_link_label` return `""`, `gemtext_heading_level` returns `0`, and
`gemtext_preformatted_start`/`gemtext_preformatted_end` return `-1` for any
negative or beyond-end index.

## 7. Canonical emission

`gemtext_emit` writes every line in document order, one normalized line per
stored line, and exactly one LF after each line. The empty document (zero
lines) emits the empty string.

| Kind | Canonical line |
|---|---|
| `text` | the text verbatim |
| `link` | `=> URL` or `=> URL LABEL` |
| `heading` | `###...` (level count) or `###... TEXT` |
| `list-item` | `*` or `* TEXT` |
| `quote` | `>` or `> TEXT` |
| `preformatted`, opening | `` ``` `` or `` ``` ALT `` |
| `preformatted`, closing | `` ``` `` |
| `preformatted-text` | the raw text |
| `blank` | the empty line |

Normalizations on emission: whitespace-only blank lines become empty lines;
heading text, alt text, link URLs/labels and empty text are re-joined with a
single space; heading text was trimmed at parse time; text lines, quote text,
list-item text and preformatted-text stay byte-exact; a closing toggle's
trailing bytes are dropped; there is always one final LF (also when the input
had none). Hand-built documents are emitted best-effort: heading levels
outside 1..3 are clamped, `"preformatted-text"` outside a block emits as text,
and an unpaired opening toggle is emitted open (re-parsing closes it
leniently at EOF).

## 8. Round-trip guarantee

For a parse-produced document `d`:

- `gemtext_emit(d)` is canonical: re-parsing it and emitting again returns
  the same bytes (idempotence, test t21);
- for already-canonical input `x`: `gemtext_emit(gemtext_parse(x)) == x`
  (tests t1, t9, t10, t13-t17, t23);
- the corpus includes preformatted blocks with alt text, raw content that
  looks like markup, whitespace-only content lines, empty and unclosed
  blocks, a link with no label, blank lines and the empty document.

## 9. Test plan

`tests/test_conformance.xi` (`module gemtext_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check; `main` prints
`[PASS]`/`[FAIL]` per check and returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | mixed document | kinds, texts, urls, labels, order, emission (section 4) |
| t2 | heading levels | `#`/`##`/`###` levels 1-3, out-of-range 0 |
| t3 | heading boundaries | `####`, `#x`, 8 hashes are text; `###`/`#` are empty headings |
| t4 | heading trimming/space | text trimmed; `##\tx` is text (literal 0x20 only) |
| t5 | link with label | url/label accessors; link text is `""` |
| t6 | link without label | `=>https://x` parses; emits `=> https://x` |
| t7 | missing URL errors | `=>`, `=>   `, `=>\t` and a later line report the line start |
| t8 | URL whitespace stance | URL ends at whitespace; label keeps inner spaces |
| t9 | list items | `* one`, lone `*`, `**x`, `*-` |
| t10 | quotes | space optional, empty quote, `>>` -> `>` |
| t11 | blank lines | whitespace-only is blank and emits empty |
| t12 | empty document | 0 lines, `""` emit, safe accessors |
| t13 | CRLF | CRLF parses like LF, emits LF |
| t14 | preformatted + alt | alt text, one span `[0,4)`, exact round-trip |
| t15 | preformatted raw | `=>`/`#`/`*`/`>`/spaces content stays raw in a span `[0,7)` |
| t16 | pre boundaries | empty block, unclosed block (lenient EOF), trailing LF |
| t17 | alt text | alt trimmed; extra backticks/spaces become alt text |
| t18 | trailing newline | single trailing LF; empty document stays `""` |
| t19 | control bytes | `0x01`, `0x02`, `0x7F`, lone CR, `0x1F` rejected with offsets |
| t20 | tab vs control | TAB allowed; controls rejected inside preformatted blocks |
| t21 | idempotence | `#   T   `, `=>url`, `>no space`, blank and text lines canonicalize; second emit is byte-identical |
| t22 | span accessors | pairs and `-1` out of range |
| t23 | non-ASCII | UTF-8 text and quote bytes pass through byte-exact |

All `Str` comparisons use `xiom.string.compare.str_compare` (BUG 17: `==` on
`Str` values read from `Vec[Str]` elements lowers to a pointer comparison).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.gemtext
```

Last verified: compiler 0.61.3,
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## 10. Known limitations

- Gemtext subset only: no transport, no URL validation, no rendering, no
  inline markup, no nested structures, no link titles.
- A whitespace-free URL means whitespace terminates the URL; a URL that
  genuinely contains spaces cannot be represented.
- Line text is verbatim, but whitespace-only lines are blank by definition
  and heading/alt text is trimmed on parse (they cannot be recovered
  byte-exact through emission).
- Control bytes (including NUL and binary payloads) are rejected everywhere,
  so the codec is for textual Gemtext documents only; DEL is rejected too.
- A line starting with ` ``` ` inside a preformatted block always closes it,
  so a toggle line cannot appear inside raw content.
- Errors are first-failure only: no recovery, no partial document, no
  line-number diagnostics (byte offsets only).
- Whole-document API: no streaming or incremental parsing.
- Hand-built `GemtextDoc` values are trusted only leniently by the emitter
  (section 7); they are not validated.

## 11. Compiler / stdlib notes for v0.61.3

- Free functions only; no methods on `GemtextDoc` and no `Vec[StructType]`
  (seven parallel `Vec`s store the document).
- `Str` values read from `Vec[Str]` elements are compared with
  `xiom.string.compare.str_compare` (BUG 17).
- Every `byte_at` byte is widened with `(b as Int) & 0xFF` before range
  comparisons, so UTF-8 bytes >= 0x80 cannot sign-extend into the C0 range
  (test t23).
- `Vec[Int]` element reads are bound to typed locals (`levels[i]`,
  `pre_starts[s]`, `pre_ends[s]`).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_doc`/`_err_doc`;
  line classification returns small plain structs (`_LineInfo`, `_LinkParts`).
- Output is built in a `Vec[UInt8]` and materialized with
  `xiom.string.builder.sb_to_str` (one allocation per `Str`); inputs are
  control-byte-free by construction, so no NUL can reach the builder.
- No `extern "C"`, no `match` on new types in the library, no inline
  lambdas, no `&struct.field` passed as `&Vec` (trap 4).
