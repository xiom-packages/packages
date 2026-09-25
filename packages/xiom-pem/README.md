# xiom.pem

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) PEM armor codec: `-----BEGIN <label>-----`
> / `-----END <label>-----` blocks with matching labels, optional RFC 1421
> `Name: value` headers preserved as raw lines, a self-contained strict
> base64 body, multiple blocks, CRLF/LF normalization and canonical
> 64-character-line emission.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`).

## What it is

`xiom.pem` is a small, dependency-light PEM armor codec. Decoding returns a
flat `PemDocument` (parallel vectors plus one header pool and one decoded
byte pool) and never interprets the payload: no DER/X.509 parsing, no
encryption and no PKCS semantics. Encoding emits the canonical armor text:
BEGIN line, preserved headers followed by one blank line, base64 wrapped at
exactly 64 characters, LF endings, END line, trailing LF.

The base64 decoder/encoder is implemented inside this package (no sibling or
stdlib base64 dependency) and is deliberately strict: no whitespace inside a
line, every body line except the last must be exactly 64 characters, `=`
padding is accepted but must be canonical, and non-zero unused trailing bits
are rejected rather than silently normalized.

## Install / use

```
xiom pkg install xiom.pem@0.1.0
```

```xi
use xiom.pem;
use xiom.io;

let text = "-----BEGIN CERTIFICATE-----\nTWFu\n-----END CERTIFICATE-----\n";
let r = pem_decode(text);
if r.is_ok {
  let doc: PemDocument = r.value;
  io.println(pem_label(&doc, 0));            // CERTIFICATE
  io.println(pem_decoded_len(&doc, 0));      // 3
  let bytes = pem_decoded_bytes(&doc, 0);    // "Man"
  ...
}
// Canonical re-emission (adds the trailing LF, wraps at 64, LF endings):
let e = pem_encode(&doc);
```

## API

| Function | Returns | Description |
|---|---|---|
| `pem_decode(text)` | `Result[PemDocument, Str]` | Parse armor text into a flat block index; strict, CRLF/LF tolerant. |
| `pem_encode(doc)` | `Result[Str, Str]` | Canonical emitter: 64-character lines, LF endings, headers preserved. |
| `pem_block_count(d)` | `Int` | Number of parsed blocks. |
| `pem_label(d, i)` | `Str` | Label of block `i` (`""` out of range). |
| `pem_header_count(d, i)` | `Int` | Raw header line count of block `i` (`0` out of range). |
| `pem_header_line(d, i, j)` | `Str` | Raw header line `j` of block `i` (`""` out of range). |
| `pem_decoded_len(d, i)` | `Int` | Decoded body length in bytes (`-1` out of range). |
| `pem_decoded_bytes(d, i)` | `Vec[UInt8]` | Copy of the decoded body bytes (empty out of range). |
| `pem_line_width()` | `Int` | The canonical body line width: 64. |
| `pem_base64_alphabet()` | `Str` | `A-Za-z0-9+/` (64 characters). |

`PEM_LINE_WIDTH` (64) and `PEM_MAX_LABEL` (64) are public constants.

`PemDocument` stores blocks flatly: `labels[i]`; the headers of block `i`
are `header_counts[i]` lines starting at `headers[header_starts[i]]`; the
decoded bytes are `data_lens[i]` bytes starting at `data[data_starts[i]]`.
Fields are implementation details; use the accessors.

## Block grammar

```
-----BEGIN <label>-----
[Name: value ...]        (optional RFC 1421 headers)
                          (blank line ends the header section)
[base64 body lines]
-----END <label>-----
```

- **Labels** are 1..64 printable US-ASCII bytes, no hyphen-minus, with
  single interior spaces allowed (`CERTIFICATE`, `RSA PRIVATE KEY`,
  `ENCRYPTED PRIVATE KEY`). Leading, trailing and consecutive spaces are
  rejected. BEGIN and END labels must match byte-for-byte (case-sensitive).
- **Markers** use exactly five dashes on each side and exactly one space
  after `BEGIN`/`END`. Anything else on a marker-like line is
  `pem: malformed block marker`.
- **Headers** are `Name: value` lines (non-empty printable name without
  space or colon, printable value, may be empty) and are preserved verbatim.
  They end at the first blank line. A header-like line after the body has
  started is `pem: header after body`; headers without a terminating blank
  line are `pem: header section not terminated`.
- **Line endings:** LF or CRLF. One CR immediately before an LF is removed;
  a CR anywhere else is an ordinary byte and fails validation. A final line
  without a terminator is accepted.
- **Multiple blocks** may follow each other directly; empty lines outside
  blocks are ignored, any other text outside a block is
  `pem: text outside blocks`. Empty input (or only empty lines) decodes to a
  document with zero blocks.
- **Empty body:** `BEGIN` directly followed by `END` (or by a blank line and
  `END`) decodes to zero bytes and re-encodes as the bare two-line form.

## Base64 and line rules

- Standard RFC 4648 alphabet `A-Za-z0-9+/` with `=` padding; decoding is
  case-sensitive. `=` may appear only as the final run; its count must match
  the final group (`XX==`, `XXX=`) and the body length must be a multiple of
  four.
- Whitespace inside a body line is invalid; a blank line inside the body is
  `pem: blank line in body`.
- **Line lengths are enforced:** every body line except the last must be
  exactly 64 characters; the last carries 1..64. A longer line, or a
  short non-final line, is `pem: bad body line length`.
- **Canonical padding:** the unused low bits of a padded final group must be
  zero. `TR==` is `pem: non-canonical trailing bits`, not a silent alias of
  `TQ==`.
- The encoder wraps at exactly 64 characters and never emits padding except
  in the final group.

## Error model

All decode errors start with the literal prefix `pem: `. The first
violation in scan order wins; `pem_encode` has two document-validation
errors of its own.

| Message | Trigger |
|---|---|
| `pem: unterminated block` | End of input before the matching `END` line. |
| `pem: label mismatch` | `END` label differs from the `BEGIN` label. |
| `pem: invalid base64 character` | A byte outside `A-Za-z0-9+/=` in a body line (including space, TAB, `-`, `_`, a stray CR). |
| `pem: bad padding` | Length not a multiple of 4, `=` not the exact final run, or an incomplete group. |
| `pem: non-canonical trailing bits` | A padded final group whose unused low bits are not zero. |
| `pem: text outside blocks` | A non-empty line between or around blocks that is not a valid BEGIN marker (a stray well-formed END marker included). |
| `pem: malformed block marker` | A line starting with five dashes that is not a well-formed BEGIN/END marker. |
| `pem: nested block not allowed` | A valid `BEGIN` marker inside an open block. |
| `pem: blank line in body` | An empty line after the body has started. |
| `pem: bad body line length` | Body line longer than 64, or a non-final line that is not exactly 64. |
| `pem: header after body` | A `Name: value` line after the body has started. |
| `pem: header section not terminated` | Header lines with no blank line before the body (or before `END`). |
| `pem: invalid label` | `pem_encode` only: a stored label that would not parse. |
| `pem: malformed document` | `pem_encode` only: parallel vectors disagree, a range does not fit its pool, or a stored header line has no `Name: value` shape. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.pem
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Armor only.** No DER/X.509/BER parsing, no ASN.1, no certificate or key
  semantics, no encryption and no PKCS interpretation: payload bytes are
  opaque.
- **Strict body lines.** Canonical 64-character wrapping is required; bodies
  wrapped at other widths are rejected rather than re-flowed.
- **No whitespace tolerance.** RFC 7468 permits lax parsers; this one does
  not skip whitespace inside lines.
- **Header values are raw ASCII.** No header parsing, continuation lines,
  folding or escaping; headers are returned exactly as written.
- **CR-only line endings are not supported** (LF and CRLF only).
- **In-memory, O(n).** No streaming reader/writer.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
