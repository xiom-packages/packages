# xiom.quotedprintable

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** RFC 2045 section 6.7 quoted-printable transfer encoding for
> arbitrary bytes plus a `Str` convenience wrapper.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.quotedprintable` encodes byte payloads into the quoted-printable
transfer encoding used by MIME (RFC 2045) and decodes them back:

- printable ASCII `0x21..0x7E` (except `=`) is copied literally;
- `=` and every other byte become `=` + two **uppercase** hex digits
  (`0x00` -> `=00`, `0x0D` -> `=0D`, `0xFF` -> `=FF`);
- TAB and space stay literal while not at the end of an encoded line;
- long input wraps with soft line breaks (`=` + CRLF) so that no line
  exceeds the documented **76-character** limit (excluding the CRLF);
- the encoder never emits a hard line break, so input CR/LF bytes are
  escaped as `=0D`/`=0A` and every byte round-trips.

The codec is binary-safe: the primary API operates on `Vec[UInt8]` values,
and there is a `Str` wrapper for text. The decoder is strict: `=` must begin
either a two-hex-digit escape or a CRLF soft break (lowercase hex is
accepted on input); a raw CRLF hard break decodes to CR LF, as found in text
bodies.

## Install

```
xiom pkg install xiom.quotedprintable@0.1.0
```

## Quick start

```xi
use xiom.quotedprintable;
use xiom.io;

fn main() -> Int {
  io.println(qp_encode_str("a=b"));       // a=3Db
  io.println(qp_encode_str("Grüße"));     // Gr=C3=BC=C3=9Fe

  var data = Vec[UInt8].new();
  data.push(0 as UInt8);
  data.push(65 as UInt8);                 // 'A'
  let enc = qp_encode(&data);             // "=00A" as bytes
  io.println(Str::from_utf8(enc));        // =00A

  let back = qp_decode_str("a=3Db");
  if back.is_ok {
    io.println(back.value);               // a=b
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `qp_encode(data)` | `Vec[UInt8]` | Encode bytes; uppercase escapes, `=`+CRLF soft breaks, no trailing CRLF on the final line. |
| `qp_decode(data)` | `Result[Vec[UInt8], Str]` | Decode bytes strictly; `Err("quotedprintable: ...")` on malformed input. |
| `qp_encode_str(s)` | `Str` | Encode the raw UTF-8 bytes of a `Str` as quoted-printable text. |
| `qp_decode_str(s)` | `Result[Str, Str]` | Decode quoted-printable text to a `Str`; same error catalog. |
| `qp_is_valid(data)` | `Bool` | `true` when `qp_decode(data)` would return `Ok`; `true` for empty input. |
| `qp_line_limit()` | `Int` | The documented encoded-line limit, `76` (excluding the trailing CRLF). |

All functions are free functions and total where documented; complexity is
O(n) over the input length.

## Error model

`qp_decode` / `qp_decode_str` return `Err(m)` on the **first** violation:

| Message | Trigger |
|---|---|
| `quotedprintable: stray equals` | `=` followed by a byte that cannot begin an escape and is not CR/LF (`a=x`, `=!2`, `==41`). |
| `quotedprintable: invalid hex digit` | the second character of an escape is not a hex digit (`=4G`, `=1Z2`, `=2g`). |
| `quotedprintable: truncated escape at EOF` | input ends after `=` or after `=` plus one hex digit (`abc=`, `abc=4`, `=A`). |
| `quotedprintable: invalid line break` | raw LF, raw CR without LF, `=` + LF, or `=` + CR not followed by LF (`a\nb`, `a\rb`, `=\n`, `=\rX`). |

The message strings are stable API. `qp_encode` never fails.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.quotedprintable
```

Expected tail: 20 `[PASS]` lines, `xiom.quotedprintable: all tests passed`,
then `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No header/parameter encoding.** RFC 2047 encoded words
  (`=?UTF-8?...?=`, `Q`/`B` encodings) are out of scope.
- **No charset handling.** Bytes are opaque; the codec never inspects or
  converts character sets. `qp_encode_str` encodes the raw UTF-8 bytes of
  the `Str`; `qp_decode_str` materializes decoded bytes without UTF-8 or NUL
  validation (use the byte API for binary payloads).
- **No MIME assembly.** No headers, boundaries, content-transfer-encoding
  fields, or base64; this package only transforms payload bytes.
- **Encoder emits soft breaks only.** A raw CRLF in the input is escaped as
  `=0D=0A`; the decoder accepts hard CRLF breaks for interoperability with
  text bodies but never produces them when encoding.
- **No trailing-whitespace stripping on decode.** Literal spaces/TABs before
  a hard break are preserved byte-exactly (encoders should escape them,
  which `qp_encode` does).
- **Whole-buffer, no streaming.** Payloads are in-memory `Vec[UInt8]`
  values; there is no incremental decoder state.
- **Line limit is a target, not a minimum.** A physical line carries at most
  75 payload characters plus the soft-break `=` (76 total); the final line
  is at most 75 characters. Shorter lines are possible around escaped
  whitespace at the wrapping boundary.

See `SPEC.md` for the exact rules, the decode algorithm and the test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
