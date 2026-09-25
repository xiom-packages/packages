# xiom.pem -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pem`, version `0.1.0`).
Module: `src/pem.xi` (`module xiom.pem`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI, no
base64 dependency (the codec is self-contained).

## 1. Scope

Ten free functions over `Str`, flat `Vec[UInt8]` values and the flat
`PemDocument` index:

```xi
pub fn pem_decode(text: Str) -> Result[PemDocument, Str]
pub fn pem_encode(doc: &PemDocument) -> Result[Str, Str]
pub fn pem_block_count(d: &PemDocument) -> Int
pub fn pem_label(d: &PemDocument, i: Int) -> Str
pub fn pem_header_count(d: &PemDocument, i: Int) -> Int
pub fn pem_header_line(d: &PemDocument, i: Int, j: Int) -> Str
pub fn pem_decoded_len(d: &PemDocument, i: Int) -> Int
pub fn pem_decoded_bytes(d: &PemDocument, i: Int) -> Vec[UInt8]
pub fn pem_line_width() -> Int
pub fn pem_base64_alphabet() -> Str
```

`PemDocument` stores blocks flatly (no `Vec[StructType]`): parallel `labels`,
`header_starts`, `header_counts`, `data_starts`, `data_lens` vectors, a
`headers: Vec[Str]` pool of raw header lines and a `data: Vec[UInt8]` pool of
decoded bytes. Block `i` occupies `labels[i]`; its headers are the
`header_counts[i]` lines at `headers[header_starts[i]]`; its decoded bytes
are the `data_lens[i]` bytes at `data[data_starts[i]]`.

All scanning is byte-wise. Every raw byte read via `xiom.string.byte_at` or a
`Vec[UInt8]` index is widened with `(x as Int) & 0xFF` before comparison or
arithmetic. No bitwise shifts are used: base64 groups are split with
multiplication, division and modulo. Both directions are O(n) and allocate
their result in memory.

## 2. Non-goals

- **No DER/X.509/BER/ASN.1 parsing.** Labels and payload bytes are opaque;
  the codec does not know what a certificate is.
- **No encryption, no PKCS semantics.** RFC 1421 headers are preserved raw
  and are never interpreted (no `Proc-Type`/`DEK-Info` behavior).
- **No streaming/incremental API**: whole-value decode/encode only.
- **No base64 dialects**: no URL-safe alphabet, no unpadded form, no
  whitespace skipping.
- **No header folding, continuation lines, escaping or lookup.**
- **No CR-only line endings.**

## 3. Block grammar

```
document   = *( blank-line / block )               ; text outside blocks is Err
block      = begin-line LF [ header-lines blank-line ] body-lines end-line [LF]
begin-line = "-----BEGIN " label "-----"
end-line   = "-----END "   label "-----"
headers    = header-line *( LF header-line )
header-line= name ":" value
label      = 1..64 labelchar with single interior spaces
labelchar  = %x21-2C / %x2E-7E                     ; printable, no space, no "-"
```

### 3.1 Lines and normalization

- A line ends at LF or at end of input; a final line without LF is accepted.
- One CR immediately before an LF is removed (CRLF normalization). A CR
  anywhere else is an ordinary byte and fails validation in its context.
- Outside blocks, empty lines are ignored. Any other line outside a block is
  `pem: text outside blocks`, except that a line starting with five dashes
  that is neither a valid BEGIN nor a valid END marker is
  `pem: malformed block marker` (a stray well-formed END is
  `pem: text outside blocks`).
- Empty input, or input made only of empty lines, decodes to a document with
  zero blocks and re-encodes to `""`.

### 3.2 Markers and labels

- BEGIN and END markers have exactly five hyphen-minuses on each side and
  exactly one space after the keyword. A marker must be the whole line.
- A valid label is 1..64 bytes; every byte is `%x21-2C` or `%x2E-7E`
  (printable US-ASCII except space and `-`), with space allowed only as a
  single separator between two such bytes. Leading, trailing and consecutive
  spaces are rejected, as is `-`.
- The END label must equal the BEGIN label byte-for-byte (case-sensitive);
  otherwise `pem: label mismatch`.
- A BEGIN marker inside an open block is `pem: nested block not allowed`.

### 3.3 Headers (RFC 1421, preserved raw)

Immediately after the BEGIN line, a maximal run of `Name: value` lines is
the header section; it must be followed by a blank line. The blank line ends
the header section and the body follows. A blank line as the first line
after BEGIN means "no headers" and the body follows. Header syntax: a
non-empty run of printable bytes (no space, no colon) followed by `:` and a
run of printable bytes (spaces allowed, may be empty); the line is stored
verbatim, without its terminator.

- Header-like line after the body has started:
  `pem: header after body` (this check precedes base64 character
  validation).
- Header run without a terminating blank line before the body or END:
  `pem: header section not terminated`.

### 3.4 Body lines

- The first non-blank, non-header line after BEGIN starts the body directly
  (canonical headerless form).
- An empty line after the body has started is `pem: blank line in body`
  (only the single header-separator blank is legal).
- Body line length: every line except the last must be exactly 64
  characters; the last must be 1..64 characters. Anything else is
  `pem: bad body line length`.
- Every body byte must be in `A-Za-z0-9+/` or be `=`; otherwise
  `pem: invalid base64 character`.
- Zero body lines (BEGIN directly followed by END, or BEGIN/blank/END)
  decode to an empty payload.

### 3.5 Multiple blocks

Blocks follow each other directly; empty lines between them are ignored. All
blocks are parsed before Ok is returned, and any error fails the whole
document (no partial result).

## 4. Base64 (RFC 4648 section 4, self-contained)

Alphabet, in value order: `A-Z` (0..25), `a-z` (26..51), `0-9` (52..61),
`+` (62), `/` (63); `=` (0x3D) is the pad character. Decoding is
case-sensitive.

**Encoding:** input is consumed in 3-byte groups, most significant first; a
final 1/2-byte group becomes 2/3 characters plus `==`/`=` padding; empty
input emits nothing. The encoder is total.

**Line wrapping (canonical):** the encoded characters are emitted in lines
of exactly `PEM_LINE_WIDTH` (64) characters, with LF endings; the final line
carries the remainder (it may also be 64 characters); an empty body emits no
body line.

**Decoding:** body lines are concatenated and decoded as one stream. The
concatenated length must be a multiple of 4. `=` may appear only in the
final run, and the run length must match the data remainder (`d % 4 == 3`
for one `=`, `d % 4 == 2` for two). Unused low bits of a padded final group
must be zero.

## 5. Decode algorithm

1. Split the input into lines (LF terminator, optional CR before LF).
2. Outside a block: skip empty lines; a valid BEGIN marker opens a block; a
   malformed marker-like line is `pem: malformed block marker`; anything
   else is `pem: text outside blocks`.
3. Inside a block, classify each line in this order:
   - a line starting with five dashes: BEGIN -> nested error; malformed ->
     `pem: malformed block marker`; END -> compare labels (`pem: label
     mismatch`), require header termination when headers were seen
     (`pem: header section not terminated`), decode the accumulated body and
     close the block;
   - empty: first one starts the body, any later one is
     `pem: blank line in body`;
   - header-like: accumulate while the body has not started, otherwise
     `pem: header after body`;
   - otherwise: a body line if the body started or no headers were seen,
     otherwise `pem: header section not terminated`.
4. Body lines are appended to a per-document character buffer; each new
   body line first checks that the previous body line was exactly 64
   characters and that this line is at most 64.
5. At END, the block's slice of the character buffer is decoded as in
   section 4; on success one slot is appended to every parallel vector and
   the decoded bytes are appended to the `data` pool.
6. At end of input an open block is `pem: unterminated block`. A document
   with no blocks is Ok.

## 6. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `pem_decode(text)` | any `Str` | `Ok(PemDocument)` with every block in input order | the decode catalog (section 7) |
| `pem_encode(doc)` | a `PemDocument` | `Ok(canonical text)` | `pem: invalid label`, `pem: malformed document` |
| `pem_block_count(d)` | any document | block count | none |
| `pem_label(d, i)` | any document | label or `""` out of range | none |
| `pem_header_count(d, i)` | any document | header count or `0` out of range | none |
| `pem_header_line(d, i, j)` | any document | raw line or `""` out of range | none |
| `pem_decoded_len(d, i)` | any document | byte length or `-1` out of range | none |
| `pem_decoded_bytes(d, i)` | any document | copy of the bytes or empty out of range | none |
| `pem_line_width()` | none | `64` | none |
| `pem_base64_alphabet()` | none | `"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"` | none |

### 6.1 Canonical emission

`pem_encode` first validates the whole document, then emits it (so an Err
leaves no partial output): for each block, the BEGIN line, every stored
header line, one blank line when the block has headers, the base64 body
wrapped at 64 characters per line (LF endings, no line for an empty body),
the END line and one trailing LF. An empty document emits `""`.

Validation order: parallel vector lengths agree (`pem: malformed document`),
per block label validity (`pem: invalid label`), header and data ranges fit
their pools and stored header lines have `Name: value` shape
(`pem: malformed document`).

### 6.2 Invariants

- `pem_encode(pem_decode(text))` is `Ok(t)` where `t` is the canonical form
  of `text` (LF endings, 64-character wrapping, blank line after headers,
  trailing LF).
- For every canonical document, `pem_decode(pem_encode(doc))` reproduces the
  same labels, header lines and decoded bytes (block round-trip).
- CRLF input and LF input decode identically, and both re-encode with LF.
- `pem_decode("")` is `Ok` with zero blocks and `pem_encode` of that document
  is `Ok("")`.

## 7. Error catalog

All decode errors start with the literal prefix `pem: `. The first
applicable rule in scan order wins.

| # | Message | Trigger |
|---|---|---|
| 1 | `pem: unterminated block` | EOF while a block is open. |
| 2 | `pem: label mismatch` | END label differs from the BEGIN label. |
| 3 | `pem: invalid base64 character` | Body byte outside `A-Za-z0-9+/=`. |
| 4 | `pem: bad padding` | Body length not a multiple of 4; `=` not the exact final run; incomplete group. |
| 5 | `pem: non-canonical trailing bits` | Padded final group with non-zero unused low bits. |
| 6 | `pem: text outside blocks` | Non-empty, non-marker line outside any block. |
| 7 | `pem: malformed block marker` | Five-dash line that is not a well-formed BEGIN/END marker. |
| 8 | `pem: nested block not allowed` | Valid BEGIN marker inside an open block. |
| 9 | `pem: blank line in body` | Empty line after the body started. |
| 10 | `pem: bad body line length` | Line > 64 characters, or a non-final line != 64. |
| 11 | `pem: header after body` | `Name: value` line after the body started. |
| 12 | `pem: header section not terminated` | Headers without a terminating blank line. |
| 13 | `pem: invalid label` | `pem_encode` only: stored label fails the grammar. |
| 14 | `pem: malformed document` | `pem_encode` only: vector length drift, out-of-range header/data range, or a malformed stored header line. |

Examples by message:

- (1): `"-----BEGIN CERTIFICATE-----\nTWFu\n"`,
  `"-----BEGIN CERTIFICATE-----\nProc-Type: 4,ENCRYPTED\n"`,
  `"-----BEGIN CERTIFICATE-----"`.
- (2): `"...BEGIN X-----"` with `"...END Y-----"`; case variants
  (`CERTIFICATE` vs `certificate`).
- (3): body `TW!u`, `TWF u`, `TWF-u`, `TWF_u`, `TW\tFu`, `TW\rFu`.
- (4): `TQ=`, `TQ===`, `TQ====`, `====`, `AAAA====`, `TQ==AAAA`,
  `AAAAAAAA=`.
- (5): `TR==`, `TWF=`, `TWH=`.
- (6): `"hello\n"` before a block; `"junk\n"` after a block; a stray
  `-----END ...-----`; a line of spaces.
- (7): `-----BEGIN CERTIFICATE----` (four trailing dashes),
  `-----BEGIN-----` (no separating space), `BAD-LABEL`, `A  B`,
  leading-space labels.
- (8): a second `-----BEGIN ...-----` before the first END.
- (9): a second blank line in the body.
- (10): 65 `A`s; two 4-character lines; a 60-character non-final line.
- (11): `Proc-Type: 4,ENCRYPTED` (or any `Name: value` line) after a body
  line.
- (12): BEGIN, a header, then a body line or END without the blank
  separator.
- (13): a hand-built label containing `-`.
- (14): a hand-built document whose `header_counts` length differs from
  `labels`, or whose header/data range overruns its pool.

## 8. Test plan

`tests/test_conformance.xi` (module `pem_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality uses
`xiom.string.compare.str_compare` (BUG 17 discipline). Pinned base64
expectations were cross-checked against an independent implementation
(.NET `Convert.ToBase64String`) and the decoder/encoder were additionally
diffed against it for every body length 0..128 plus 200/255/256/257/512/
1000/4096 bytes during development.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single block | one `CERTIFICATE` block, label/header count/decoded length/bytes |
| t2 | canonical encode | trailing LF added to a final unterminated line; idempotent re-encode |
| t3 | 64-character wrap | 52-byte body -> 64+8-character lines, exact bytes, re-encode identity |
| t4 | empty body | bare and blank-separated forms decode to 0 bytes; blank form re-encodes bare |
| t5 | multi-block | two blocks in order with independent ranges; blank separator normalized away |
| t6 | CRLF | CRLF and mixed endings decode; re-encode is LF; stray CR is rejected |
| t7 | headers | two raw header lines preserved, out-of-range header line is `""`, re-emitted |
| t8 | empty input | `""` and blank-only input -> zero blocks; empty document -> `""` |
| t9 | text outside blocks | text before/after, stray END, whitespace-only line |
| t10 | label mismatch | different label and case difference |
| t11 | unterminated block | body EOF, header EOF, marker-only EOF |
| t12 | invalid characters | `!`, space, `-`, `_`, TAB in the body |
| t13 | bad padding | wrong length, leading `=`, data after `=` |
| t14 | trailing bits | `TR==`, `TWF=`, `TWH=` rejected; `TWE=` -> `"Ma"` |
| t15 | pinned vectors | 1/2/3/4/47/48/49-byte sequences and `TQ==`/`TWFu` |
| t16 | header after body | header-shaped lines after body start |
| t17 | header termination | headers followed by body/END without the blank line; empty body with headers |
| t18 | blank line in body | blank after a body line; double blank after BEGIN |
| t19 | line length | 65 characters, short non-final line rejected; 64+4 accepted |
| t20 | markers/labels | 4-dash marker, missing space, hyphen/double-space/leading-space labels, spaced label accepted, nesting |
| t21 | accessor neutrals | `""`/`0`/`-1`/empty for out-of-range indexes |
| t22 | encoder validation | invalid label, vector drift, out-of-range header range, hand-built valid document |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pem
# port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

## 9. Known limitations

- **Armor only** (section 2): no DER/X.509, no ASN.1, no encryption, no PKCS
  semantics.
- **Canonical wrapping required**: non-final body lines must be exactly 64
  characters. Lax parsers accept other widths; this one rejects them.
- **No whitespace tolerance**: spaces/tabs inside a body line are invalid
  characters, not skipped.
- **Headers are opaque raw lines**: no folding, continuation, escaping or
  interpretation.
- **CR-only files are not supported.**
- **In-memory, O(n)**, no streaming.

## 10. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch, no `match` in the library.
- `Ok`/`Err` are constructed only in the leaf helpers
  `_ok_doc`/`_err_doc`/`_ok_bytes`/`_err_bytes`/`_ok_str`/`_err_str`.
- Every byte read is widened with `(x as Int) & 0xFF` before comparison or
  arithmetic; `Vec[Int]`/`Vec[Str]` element reads are bound to typed locals.
- No bitwise shifts: base64 groups are folded with `acc = acc * 64 + v` and
  split with division/modulo by powers of two (65536, 1024, 16, 4).
- `PemDocument` is assembled once at the end of `pem_decode` and crosses
  function boundaries by reference or through `_ok_doc`.
- No `==` on `Str` anywhere in the library: label comparison is the
  byte-wise `_str_eq`.
