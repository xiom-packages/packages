# xiom.quotedprintable -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.quotedprintable` (`src/quotedprintable.xi`). Pure XIOM, no FFI.
Manifest: `package.xi` (deps: `xiom.std >=0.60.0 <1.0.0`).

## 1. Scope

An RFC 2045 section 6.7 quoted-printable codec for arbitrary bytes plus a
text convenience wrapper:

```xi
pub fn qp_encode(data: &Vec[UInt8]) -> Vec[UInt8]
pub fn qp_decode(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn qp_encode_str(s: Str) -> Str
pub fn qp_decode_str(s: Str) -> Result[Str, Str]
pub fn qp_is_valid(data: &Vec[UInt8]) -> Bool
pub fn qp_line_limit() -> Int
```

The byte API is binary-safe: any byte value 0x00..0xFF is accepted and every
byte round-trips through `qp_encode` / `qp_decode`. Complexity is O(n) over
the input length for every function. The library never compares `Str`
values; callers use `xiom.string.compare.str_compare`.

## 2. Non-goals

- **No header/parameter encoding.** RFC 2047 encoded words
  (`=?UTF-8?Q?...?=`, Q/B encodings), header folding and phrase/comment
  syntax are not implemented.
- **No charset handling.** Bytes are opaque. No UTF-8 validation, no
  transcoding, no `CHARSET` interpretation, no line-ending normalization of
  the decoded payload.
- **No MIME assembly.** No message headers, content-type parameters,
  boundaries or `Content-Transfer-Encoding` fields; this is a payload codec
  only.
- **No base64 / uuencode / yenc.** Only quoted-printable.
- **No streaming.** Whole payloads are materialized as `Vec[UInt8]`; there is
  no incremental encoder/decoder state.
- **No hard line breaks on encode.** The encoder emits soft breaks only (see
  section 4); input CR/LF bytes are escaped.

## 3. Notation

- `n` = input length in bytes.
- **Token**: the output for one input byte: 1 literal character, or the
  3-character escape `=` + two hex digits.
- **Payload capacity**: 75 characters per line; the soft-break marker `=`
  occupies the 76th character of a wrapped line.
- **Literal set**: bytes `0x21..0x7E` except `=` (`0x3D`).
- **Whitespace set (literal-optional)**: TAB (`0x09`) and space (`0x20`).

## 4. Encoding (`qp_encode`)

The encoder walks the input once, left to right, maintaining `line_len` (the
number of characters already written on the current line). For input byte
`b` at index `i`:

1. **Literal**: when `b` is in the literal set, the token is `b` itself
   (1 character).
2. **Whitespace**: when `b` is TAB or space, the token is the literal byte
   (1 character) **iff** `i + 1 < n` **and** `line_len + 4 <= 75`; otherwise
   the token is the 3-character escape. The `+4` reserves one character for
   `b` and three for a worst-case following escape, which guarantees that a
   literal whitespace byte is always followed by at least one more character
   on the same line -- so no encoded line ever ends in a literal space/TAB,
   and a trailing space/TAB at end of input is always escaped.
3. **Escape**: every other byte becomes `=` + two **uppercase** hex digits
   (`0123456789ABCDEF`): `0x00` -> `=00`, `0x09` -> `=09`, `0x0A` -> `=0A`,
   `0x0D` -> `=0D`, `0x20` -> `=20`, `0x3D` -> `=3D`, `0x7F` -> `=7F`,
   `0x80` -> `=80`, `0xFF` -> `=FF` (3 characters).
4. **Line breaking**: before a token of `size` characters is written, if
   `line_len + size > 75`, the encoder writes `=` + CRLF (a soft line break)
   and resets `line_len = 0`. The token then starts the next line.
5. The encoder never writes a hard line break, never appends a trailing CRLF
   to the final line, and produces empty output for empty input.

### 4.1 Line-length rule (exact)

- A physical line is the characters between CRLFs (or between a CRLF and end
  of output, for the final line).
- No physical line exceeds **76 characters**, excluding the CRLF that
  follows it. The soft-break marker `=` is the 76th character of a wrapped
  line.
- A wrapped line therefore carries at most 75 payload characters; the final
  line carries at most 75 characters and no marker.
- `qp_line_limit()` returns `76`; it is the RFC 2045 section 6.7 rule #4
  limit ("encoded lines are limited to 76 characters, not counting the
  trailing CRLF").

### 4.2 Encoding examples

| Input bytes | Output | Note |
|---|---|---|
| (empty) | (empty) | no lines at all |
| `Hello` | `Hello` | all literal |
| `a=b` | `a=3Db` | `=` always escaped |
| `a ` | `a=20` | trailing space escaped |
| `  ` (two spaces) | ` =20` | first space literal (next token fits), last escaped |
| `a  b` | `a  b` | interior spaces literal |
| `\tA` | `\tA` | leading TAB literal |
| `\t` | `=09` | lone TAB is line-final |
| `café` (UTF-8 `63 61 66 C3 A9`) | `caf=C3=A9` | high bytes escaped per byte |
| `0x00` | `=00` | NUL escaped |
| 75 x `a` | 75 x `a` | one line, no break |
| 76 x `a` | 75 x `a` + `=` CRLF + `a` | first line 76 chars incl. marker |

## 5. Decoding (`qp_decode`)

The decoder walks the input once, left to right. For input byte `b`:

1. **Escape** (`b == '='`):
   - End of input after `=`: `Err("quotedprintable: truncated escape at EOF")`.
   - `=` followed by CR: if the next byte is LF, skip all three bytes (soft
     line break, nothing emitted); otherwise (EOF or any other byte)
     `Err("quotedprintable: invalid line break")`.
   - `=` followed by LF: `Err("quotedprintable: invalid line break")`.
   - `=` followed by any other byte `c`: if `c` is not a hex digit,
     `Err("quotedprintable: stray equals")`; if `c` is a hex digit but the
     input ends, `Err("quotedprintable: truncated escape at EOF")`; if the
     second byte is not a hex digit,
     `Err("quotedprintable: invalid hex digit")`; otherwise emit the byte
     `0x(c1 c2)` and skip three bytes.
   - Hex digits are case-insensitive (`a-f` and `A-F`); uppercase is the
     canonical encoder output.
2. **Hard line break** (`b == CR`): the next byte must be LF; then emit
   CR LF and skip two bytes. A CR at end of input or followed by anything
   other than LF is `Err("quotedprintable: invalid line break")`.
3. **Bare LF** (`b == LF`): `Err("quotedprintable: invalid line break")`.
4. **Literal**: every other byte is copied unchanged, including spaces and
   TABs. Trailing whitespace before a hard break is **not** stripped; the
   decoder is byte-preserving apart from escapes and line breaks.

Empty input decodes to `Ok(empty)`.

### 5.1 Error precedence

The decoder reports the **first** violation in input order. The catalog is
fixed:

| Message | Trigger | Examples |
|---|---|---|
| `quotedprintable: stray equals` | `=` followed by a byte that cannot begin an escape (not `0-9A-Fa-f`) and is not CR/LF | `a=x`, `=!2`, `=%`, `==41` |
| `quotedprintable: invalid hex digit` | the first character is a hex digit and the second is not | `=4G`, `=1Z2`, `=2g` |
| `quotedprintable: truncated escape at EOF` | input ends after `=` or after `=` plus one hex digit | `abc=`, `abc=4`, `=A` |
| `quotedprintable: invalid line break` | raw LF; raw CR without LF; `=` + LF; `=` + CR not followed by LF | `a\nb`, `a\rb`, `a\r`, `=\n`, `=\r`, `=\rX` |

`qp_is_valid(data)` is exactly `qp_decode(data).is_ok` in `Bool` form and is
true for empty input.

## 6. Text wrapper

- `qp_encode_str(s)` encodes the raw bytes of `s` (one byte per index,
  UTF-8 sequences are not decoded) and returns the encoded text as a `Str`.
- `qp_decode_str(s)` decodes the bytes of `s` and materializes the result as
  a `Str`. It performs **no UTF-8 validation and no NUL handling**: decoded
  bytes are returned as-is. Use the byte API when the payload is binary.
- Both wrappers share the encoder/decoder rules and the error catalog above;
  `qp_decode_str` propagates the same `Err` messages.

## 7. API contract

| Function | Params | Returns | Errors | Complexity |
|---|---|---|---|---|
| `qp_encode` | `data: &Vec[UInt8]` | encoded bytes | none (total) | O(n) |
| `qp_decode` | `data: &Vec[UInt8]` | `Ok(bytes)` | catalog, section 5.1 | O(n) |
| `qp_encode_str` | `s: Str` | encoded text | none (total) | O(n) |
| `qp_decode_str` | `s: Str` | `Ok(text)` | catalog, section 5.1 | O(n) |
| `qp_is_valid` | `data: &Vec[UInt8]` | `Bool` | none | O(n) |
| `qp_line_limit` | none | `76` | none | O(1) |

Round-trip guarantees (proved by the test suite):

- `qp_decode(qp_encode(x)) == Ok(x)` for every byte vector `x`.
- `qp_decode_str(qp_encode_str(s)) == Ok(s)` for every `Str` `s` that the
  test suite exercises (ASCII, UTF-8 text, long text).
- The encoder output contains no raw CR or LF except the `=` + CRLF soft
  breaks, and no physical line exceeds 76 characters.

## 8. Test matrix

`tests/test_conformance.xi` (module `quotedprintable_tests`) runs 20 named
checks, one `fn` per check, through `assert(cond, "name")`; `main` prints
`[PASS]`/`[FAIL]` and returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | empty input | `qp_encode([]) == []`; decode/`encode_str`/`decode_str` all yield empty `Ok` |
| t2 | ASCII passthrough | printable text is unchanged, decode round-trips |
| t3 | escapes | `=` -> `=3D`; 0x00/0x08/0x0B/0x0C/0x1F/0x7F/0x80/0xFF -> `=00` ... `=FF` uppercase |
| t4 | literal TAB/space | interior TAB/space stay literal; leading TAB before a byte stays literal |
| t5 | trailing whitespace | `a ` -> `a=20`, `a\t` -> `a=09`, `"  "` -> `" =20"`, interior spaces literal |
| t6 | non-ASCII | `café ✓` -> `caf=C3=A9 =E2=9C=93`; no output byte > 0x7E; round-trips |
| t7 | line boundary | 75 bytes stay on one line; 76 bytes wrap at 75 + `=`; marker/CRLF positions |
| t8 | long binary | 200-byte sequence: scan proves no line > 76 and every CRLF is a soft break; round-trips |
| t9 | hex decoding | `=41=42=43` -> `ABC`; lowercase `=6a` -> `j`; `=00`/`=FF` exact |
| t10 | soft breaks | `ab=\r\ncd` -> `abcd`; consecutive and trailing soft breaks |
| t11 | hard breaks | raw CRLF -> CR LF; `=0D=0A` -> CR LF |
| t12 | literals | printable/TAB/space decode verbatim; leading/trailing literal spaces preserved |
| t13 | stray equals | `a=x`, `=!2`, `=%`, `==41` -> exact Err |
| t14 | invalid hex digit | `=4G`, `=1Z2`, `=2g` -> exact Err |
| t15 | truncated escape | `abc=`, `abc=4`, `=A` -> exact Err |
| t16 | invalid line break | bare LF, bare CR, `=\n`, `=\r`, `a\r`, `=\rX` -> exact Err |
| t17 | all bytes | 0x00..0xFF round-trips; lines stay within the limit |
| t18 | length sweep | round-trips for lengths 0..8 and a 257-byte sequence |
| t19 | text wrapper | UTF-8 text and a 300-character string round-trip; long input wraps |
| t20 | validity/limit | `qp_line_limit() == 76`; `qp_is_valid` accepts well-formed input and rejects `a=x`, `=\r` |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.quotedprintable
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 9. Compiler / stdlib notes (v0.61.3)

- Free functions only; no methods, lambdas, `Vec[fn]` dispatch or
  `Vec[StructType]`. The library uses if/elif chains, not `match`.
- `Ok`/`Err` construction for `Result` is confined to the leaf helpers
  `_ok_bytes` / `_err_bytes` / `_ok_str` / `_err_str` (constructing Results
  directly inside larger functions miscompiles in this compiler).
- Every `Vec[UInt8]` element read is widened once with
  `(data[i] as Int) & 0xFF` before comparison or arithmetic.
- `qp_decode_str` binds `dec.value` to a local before passing it to
  `builder.sb_to_str`, because a `Result` field passed directly into a
  `&Vec[UInt8]` parameter reads as an empty vector in this compiler.
- The encoder performs no retroactive vector writes: each token's size and
  each soft break are decided before the token is pushed.
- Tests compare strings with `xiom.string.compare.str_compare` (BUG 17:
  `==` on Str values read from a `Vec` lowers to a pointer comparison) and
  read bytes with explicit `Int` widening.

## 10. Known limitations

- RFC 2047 encoded words and any header context are out of scope.
- No charset conversion or UTF-8 validation; bytes are opaque.
- `qp_decode_str` can produce a `Str` holding arbitrary bytes (including
  embedded NUL); callers that need text should validate it themselves.
- The decoder accepts raw CRLF hard breaks for interoperability (standard
  text-body behavior) but the encoder never emits them.
- Trailing whitespace before a hard break is preserved, not stripped; this
  is byte-preserving but less lenient than some transport implementations.
- No streaming/incremental API; whole buffers are materialized in memory.
- Thread-safety is the caller's concern; the API is stateless free
  functions over value types.
