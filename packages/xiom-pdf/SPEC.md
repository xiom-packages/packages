# xiom.pdf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pdf` (`src/pdf.xi`), pure XIOM, no FFI.
Companion: `README.md` (usage and API table).

This document describes exactly what `src/pdf.xi` implements: the accepted
grammar, the limits, the error catalog with its byte-offset convention, the
flag/status codes, and the conformance matrix.

## 1. Scope

In scope: the PDF structural layer -- lexical syntax, indirect objects,
streams, cross-reference tables and streams, hybrid files, trailer chains,
object lookup, object streams, the page tree and the Info dictionary.

Out of scope: rendering, content-stream interpretation, fonts, colours,
images, annotations, outlines, encryption (flagged, never decrypted), filters
other than FlateDecode (flagged, raw bytes exposed), PNG/TIFF predictors > 1
(flagged), and cross-buffer/streaming input (the whole file is one
`Vec[UInt8]`).

## 2. Grammar

### 2.1 Character classes

- Whitespace: `NUL, HT, LF, FF, CR, SP` (bytes 0, 9, 10, 12, 13, 32).
- Delimiters: `( ) < > [ ] { } / %`.
- Regular: every other byte.
- Comments: `%` up to (not including) the next CR or LF; skipped wherever
  tokens are scanned (including between dictionary pairs and array elements).

### 2.2 Tokens (`pdf_lex`)

| Token | Kind | Notes |
|---|---|---|
| integer | `_TK_INT = 0` | optional `+`/`-`, digits; > 18 digits is an error |
| real | `_TK_REAL = 1` | digits with one `.`, leading `.`/`-.` and trailing `4.` allowed, optional `e`/`E` exponent; raw text kept in the pool |
| literal string | `_TK_STR = 2` | `( ... )`, nested unescaped parentheses; decoded bytes in the pool |
| hex string | `_TK_HEX = 3` | `< ... >`, whitespace allowed, an odd final nibble is padded with 0 |
| name | `_TK_NAME = 4` | `/` + regular chars; `#xx` escapes decode one byte; `#00` is rejected |
| array open/close | `_TK_ARR_OPEN = 5`, `_TK_ARR_CLOSE = 6` | `[` `]` |
| dict open/close | `_TK_DICT_OPEN = 7`, `_TK_DICT_CLOSE = 8` | `<<` `>>` (`>>` is one token; a lone `>` is an error) |
| keyword | `_TK_KEYWORD = 9` | `true false null obj endobj stream endstream xref trailer startxref R n f`; any other bare word is an error |

Literal-string escapes: `\n \r \t \b \f \( \) \\`, `\ooo` (1-3 octal digits,
value masked to 8 bits), a backslash before CR/LF (or CRLF) is a line
continuation, and any other escaped byte yields that byte (the backslash is
dropped). A backslash at end of input is an unterminated string.

A number must be followed by whitespace, a delimiter or end of input; a name
longer than 4096 decoded bytes is an error.

### 2.3 Values (arena nodes)

Node kinds: `_NK_NULL=0`, `_NK_BOOL=1` (num 0/1), `_NK_INT=2` (num),
`_NK_REAL=3` (pool span = raw token text), `_NK_STRING=4` (pool span),
`_NK_NAME=5` (pool span), `_NK_ARRAY=6`, `_NK_DICT=7`, `_NK_REF=8`
(num = object number, gen = generation).

Arrays hold elements; dictionaries hold alternating key (NAME) and value
child nodes. `N G R` (two integers followed by `R`) is parsed as one REF node
with source span from the first integer through the `R`; a standalone `R` is
an unexpected token. Nesting deeper than 64 is an error.

### 2.4 Indirect objects

`N G obj <value> [stream ... endstream] endobj`.

- After the value, exactly `endobj` must follow (a `stream` keyword is
  accepted only when the value is a dictionary, and the object then ends with
  `endstream endobj`).
- `stream` must be followed by LF or CRLF (a lone CR or any other byte is an
  error).
- Stream data starts right after that EOL and is bounded by `/Length`:
  - direct integer: the range is accepted only when `endstream` (optionally
    preceded by one EOL) follows exactly at `start + Length`; otherwise the
    parser falls back to the endstream scan and flags the stream.
  - indirect reference `N G R`: the parser records the reference; after the
    object map is built the referenced integer is looked up and the range is
    re-bounded when it lands on `endstream` (`_LS_INDIRECT`); otherwise the
    scanned bounds stay and the stream stays flagged.
  - missing `/Length`, or a `/Length` that is neither an integer nor a
    reference, is an error.
- A stream whose `endstream` cannot be found is an error ("unterminated
  stream"). The scan is the first occurrence of the literal `endstream`; this
  is the documented heuristic when `/Length` is unavailable or wrong.
- `endstream` must be followed by `endobj` (after whitespace/comments).

### 2.5 Cross-reference tables (classic)

At the `startxref` offset: `xref`, then zero or more subsections
`start count`, each entry exactly the classic layout -- 10 decimal digits of
offset, one space, 5 decimal digits of generation, one space, `n` or `f`,
then a 1-2 byte EOL (`CRLF`, ` LF`, ` CR`, or LF/CR alone; one optional space
before the terminator is accepted). Offset and generation fields must be
digits of the exact widths; anything else is a malformed entry. The table
ends with `trailer` and one dictionary.

### 2.6 Cross-reference streams

An indirect object whose dictionary has `/Type /XRef`, `/W [w0 w1 w2]` (each
0..8) and optional `/Index [start count ...]` (default `[0 /Size]`).
Entries are `w0+w1+w2` big-endian bytes:
type 0 free (`gen` from field 3), type 1 in-use (`offset`, `gen`),
type 2 object-stream member (`objstm number`, `index inside it`);
when `w0 == 0` the type defaults to 1. A field whose top bit would overflow
`Int` is an error. The data may be raw (no `/Filter`) or a single
`FlateDecode`/`Fl` filter (name or one-element array), inflated by the local
DEFLATE port; `DecodeParms` with `Predictor > 1` or an unresolvable form is
not decoded: the document records `pdf_xref_decode_error` and no entries are
merged. The stream dictionary also supplies trailer fields.

### 2.7 Hybrid files

A classic trailer with `/XRefStm <offset>`: after the classic entries and
trailer fields are recorded, the xref stream at that offset is parsed and its
entries are merged. Precedence: within one generation, stream entries beat
table entries; between generations, the newest section beats older ones
(`/Prev` chain). Trailer fields are first-wins from the newest section that
carries them (a hybrid stream can supply `/Info` etc. that the classic
trailer lacks).

### 2.8 Trailer chain

`startxref` points at the newest section. Each section's `/Prev` points at
the next older one; the walk keeps a visited-offset guard and stops after 64
sections. Fields recorded: `/Size`, `/Root`, `/Info`, `/ID` (two strings),
`/Prev`, `/Encrypt` (flag + object number), `/XRefStm`. `pdf_xref_sections`
lists the offsets newest-first.

Encrypted documents (`/Encrypt` present) are flagged
(`pdf_is_encrypted`, `pdf_encrypt_num`) and parsed structurally, never
decrypted.

### 2.9 Object streams

Every entry of kind `_XK_OBJSTM` names an object stream; the parser decodes
each distinct stream once (raw or FlateDecode), reads `/N` pairs of
`object number, relative offset` and parses the object at `First + offset` in
the decoded payload. Extracted objects are marked
`pdf_object_from_objstm`; their recorded offset is the best-effort file
offset of the decoded byte. A stream that cannot be decoded sets
`pdf_xref_decode_error` and its members stay unresolved (they are not listed
as objects).

### 2.10 Page tree

From the catalog's `/Pages`: `/Kids` arrays recurse, any other kid counts as
a leaf page; `/Count` is recorded separately. The walk is depth-capped at 64
(`pdf_pages_depth_capped`) and cycle-guarded by node index, and records at
most 100000 pages.

## 3. Limits

| Constant | Value | Meaning |
|---|---|---|
| `_PDF_MAX_NEST` | 64 | value nesting depth |
| `_PDF_MAX_XREF_SECTIONS` | 64 | `/Prev` chain length |
| `_PDF_MAX_XREF_ENTRIES` | 1000000 | merged xref entries |
| `_PDF_MAX_TOKENS` | 1000000 | `pdf_lex` output |
| `_PDF_MAX_PAGE_DEPTH` | 64 | page-tree recursion |
| `_PDF_MAX_PAGES` | 100000 | recorded pages |
| `_PDF_MAX_OBJSTM_N` | 100000 | `/N` of one object stream |
| `_PDF_MAX_INFLATE_IN` | 1 MiB | compressed input fed to the inflate port |
| `_PDF_MAX_INFLATE_OUT` | 16 MiB | inflated output |
| name length | 4096 | decoded name bytes |
| string length | 1 MiB | decoded literal-string bytes |

## 4. Error catalog

Every error is `"pdf: <text> at <byte offset>"` (flate errors are
`"pdf: flate <text> at <byte offset>"`). Offsets are absolute file offsets
except for object-stream payloads, whose offsets are relative to the decoded
payload.

| Message | Trigger |
|---|---|
| `missing PDF header` | no `%PDF-` within the first 1024 bytes |
| `bad PDF header version` | version token missing, not starting with a digit, or without `.` |
| `missing startxref` | no `startxref` keyword |
| `bad startxref value` | `startxref` not followed by an integer |
| `xref offset out of range` | `startxref`/`/Prev`/`/XRefStm` beyond the buffer |
| `unterminated xref table` | table ends before `trailer` |
| `bad xref subsection header` | subsection is not `start count` |
| `malformed xref entry` | wrong field widths, missing spaces, bad `n`/`f`, bad EOL |
| `too many xref entries` | entry limits exceeded |
| `bad trailer dictionary` | `trailer` not followed by a dictionary |
| `xref stream offset out of range` | `/XRefStm` beyond the buffer |
| `bad xref stream object` | value unresolved |
| `xref stream object is not a dictionary` | value not a dictionary |
| `missing /Type /XRef` | xref stream without `/Type /XRef` |
| `xref stream missing /W` | no `/W` |
| `bad xref stream /W` | not exactly three integers 0..8, or all-zero |
| `bad xref stream /Index` | not pairs of non-negative integers |
| `xref stream missing /Size` | no `/Index` and no `/Size` |
| `truncated xref stream data` | entry data shorter than `/Index` demands |
| `xref stream field overflow` | entry field exceeds `Int` |
| `bad object header` | offset does not hold `N G obj` |
| `object header mismatch` | header object number differs from the xref entry |
| `missing endobj` | object does not end with `endobj` |
| `stream value is not a dictionary` | `stream` after a non-dictionary value |
| `stream keyword not followed by LF or CRLF` | bad EOL after `stream` |
| `stream dictionary missing /Length` | no `/Length` |
| `bad /Length value` | `/Length` neither integer nor reference |
| `unterminated stream` | no `endstream` found |
| `unexpected end of input` | input ends where a token is required |
| `unknown keyword` | bare word that is not a PDF keyword |
| `unexpected token` | bracket/keyword where a value must start |
| `dictionary key is not a name` | non-name token inside `<< >>` |
| `nesting too deep` | value nesting over 64 |
| `unterminated string` | literal string never closes |
| `unterminated hex string` | hex string never closes |
| `bad hex digit` | non-hex, non-whitespace byte inside `< >` |
| `bad name escape` | `#` not followed by two hex digits |
| `NUL in name` | `#00` in a name |
| `name too long` | name over 4096 decoded bytes |
| `string too long` | literal string over 1 MiB decoded |
| `bad number` | malformed number or a number glued to a letter |
| `number too large` | integer with more than 18 digits |
| `expected integer` | digit run required (xref parse) |
| flate errors | see below |

Flate errors: `unsupported zlib method`, `invalid zlib window size`,
`bad zlib fcheck`, `zlib preset dictionary unsupported`, `truncated zlib
header`, `truncated zlib trailer`, `adler mismatch`, `truncated deflate block
header`, `invalid deflate block type`, `truncated stored block`, `stored
block length check failed`, `invalid code length`, `too many literal/length
codes`, `too many distance codes`, `truncated dynamic header`, `invalid code
length symbol`, `repeat with no previous length`, `code length repeat
overflow`, `missing end-of-block code`, `truncated dynamic lengths`,
`truncated huffman block`, `invalid literal/length code`, `invalid length
symbol`, `truncated length extra bits`, `invalid distance code`, `truncated
distance extra bits`, `distance too far back`, `inflated output too large`,
`trailing bytes after zlib stream`, `bad deflate start`.

## 5. Flags and status codes

Not errors (the document opens and the situation is queryable):

| Query | Meaning |
|---|---|
| `pdf_xref_decode_error` | non-empty when an xref/object stream could not be decoded (unsupported filter/predictor or corrupt data) |
| `pdf_stream_bounds_scanned` | true when the bounds came from the endstream scan |
| `pdf_stream_length_source` | 0 none, 1 direct, 2 indirect resolved, 3 scanned, 4 scanned (indirect unresolved) |
| `pdf_is_encrypted` / `pdf_encrypt_num` | `/Encrypt` was present |
| `pdf_pages_depth_capped` | the page walk hit the depth cap |
| `pdf_object_from_objstm` | the object came out of an object stream |
| `pdf_object_status` | `_OS_OK = 0`; `_OS_OBJSTM_MISSING = 2` reserved for unresolved object-stream members |
| `pdf_objstm_used` | at least one object stream was decoded |
| `pdf_node_text` / `pdf_token_text` | `""` when the bytes contain NUL; raw bytes via `pdf_node_bytes` / `pdf_token_bytes` |

## 6. Conformance matrix (tests/test_conformance.xi)

25 tests, all printing `[PASS]`:

| # | Covers |
|---|---|
| 1 | one-page classic document: header, xref, catalog, page tree, MediaBox, Resources, /Contents |
| 2 | lexer token kinds and values incl. `N G R` |
| 3 | literal-string escapes `\n \t \ooo \\ \( \)` |
| 4 | nested parentheses, hex pairs, CRLF line continuation |
| 5 | name `#xx` escapes; NUL and bad escapes rejected |
| 6 | number forms; number glued to a word rejected |
| 7 | `%` comments between tokens |
| 8 | stream direct `/Length` verified, raw bytes, flags |
| 9 | indirect `/Length` resolved through the object map |
| 10 | unresolvable indirect `/Length` -> scan + flag |
| 11 | incremental update `/Prev` chain, newest object wins |
| 12 | xref stream `/W` + `/Index` (raw data), raw stream exposure |
| 13 | xref stream FlateDecode via the local inflate port |
| 14 | hybrid `/XRefStm` merge |
| 15 | `/Encrypt` flagged |
| 16 | Info Title/Author/Subject/CreationDate + spans |
| 17 | trailer `/ID` strings |
| 18 | missing startxref/header, malformed xref entry |
| 19 | bad/mismatched object headers |
| 20 | unterminated string, bad hex digit, bad name escape |
| 21 | missing endobj, missing /Length, non-numeric /Length |
| 22 | `stream` EOL rule |
| 23 | object streams: type-2 entries, `/N` pairs, extraction |
| 24 | DEFLATE (dynamic Huffman fixture) and zlib (stored block) decoders |
| 25 | two-page tree, free entries stay free |
