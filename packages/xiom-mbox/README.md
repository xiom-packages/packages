# xiom.mbox

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** mbox mailbox codec: message separation on `From ` lines,
> mboxrd quoting, byte-range bodies into a shared pool, and a canonical
> emitter; in-memory `Str` only, no file I/O.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.builder.sb_to_str`). Tests
> additionally use `xiom.string.compare`, `xiom.test` and `xiom.io`.

## Scope

`xiom.mbox` parses an in-memory mbox mailbox into a flat `Mailbox`: the whole
input is kept verbatim in `pool`, and each message is four index-aligned byte
ranges into it (envelope line start/end, body start/end). No message structs
are stored (`Vec[StructType]` is unsupported by the compiler) and no bytes are
copied on parse. The accessors expose the envelope line and its address/date
as raw text, the body span, the body bytes materialized into the caller's
buffer, and the header/body separator line inside a message.

The separation rule is the classic one: the mailbox must start with a `From `
line (or be empty), and later `From ` lines open a new message only when they
follow an empty line; otherwise they are body content. Line terminators are LF
and CRLF; a bare CR is ordinary data. The mboxrd quoting stance is pinned:
the pool and `mbox_body_raw` are verbatim, `mbox_body_into` removes one `>`
from `>+From ` lines, and `mbox_emit` re-quotes body lines that start with
`From `, so canonical input round-trips byte-for-byte.

It intentionally does **not** parse RFC 5322 headers or dates, decode transfer
encodings, or implement mboxcl/mboxo variants -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `mbox_parse(text)` | `Result[Mailbox, Str]` | Parse a whole mailbox; `Err("mbox: ...")` on text before the first `From ` line. |
| `mbox_count(m)` | `Int` | Number of messages (0 for an empty mailbox). |
| `mbox_envelope_line(m, i)` | `Str` | Message `i`'s `From ...` line, verbatim, without its terminator. |
| `mbox_envelope_address(m, i)` | `Str` | First whitespace-delimited token after `From `, raw; `""` when absent. |
| `mbox_envelope_date(m, i)` | `Str` | Raw text after the address token, trailing spaces/tabs removed. |
| `mbox_body_offset(m, i)` | `Int` | Pool offset of the body's first byte (after the envelope terminator); `-1` when invalid. |
| `mbox_body_len(m, i)` | `Int` | Body byte length: to the next delimiter, or to the pool end for the last message. |
| `mbox_body_raw(m, i)` | `Str` | Body verbatim from the pool (quoted lines included). |
| `mbox_body_into(m, i, out)` | `Int` | Append the decoded body to the caller's buffer; returns the bytes appended. |
| `mbox_header_separator(m, i)` | `Int` | Offset of the first empty line in the body span (the RFC 5322 header separator), or `-1`. |
| `mbox_header_body_start(m, i)` | `Int` | Offset just after that separator line, or `-1`. |
| `mbox_emit(m, eol)` | `Str` | Canonical serializer: envelope lines, re-quoted bodies, line terminators rewritten to `eol`. |

## Usage

```xi
use xiom.mbox;
use xiom.io;
use xiom.string.builder;

fn main() -> Int {
  let text = "From alice@example.com Mon Jan  1 00:00:00 2024\nSubject: Hi\n\n>From the archives\n\nFrom bob@example.com Tue Jan  2 00:00:00 2024\nSubject: Re\n\nHello\n";
  let r = mbox_parse(text);
  match r {
    Ok(box) => {
      io.println(mbox_envelope_line(&box, 0));   // From alice@example.com ...
      var buf = Vec[UInt8].new();
      let _n = mbox_body_into(&box, 0, &mut buf);
      io.println(builder.sb_to_str(&buf));       // decoded: ">From" becomes "From"
      io.println(mbox_emit(&box, "\n"));         // canonical serialization
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.mbox
```

Expected tail: 18 `[PASS]` lines, `xiom.mbox: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Separation only**: no RFC 5322 header parsing (sibling `xiom.eml`), no
  date parsing (`mbox_envelope_date` is raw text), no transfer decoding.
- **No mboxcl/mboxo variants**: only the mboxrd quoting stance is implemented;
  Content-Length: headers are not recognized and not honored.
- **No file I/O**: parse takes a `Str` and emit returns a `Str`; reading and
  writing files is the caller's concern.
- Emitting rewrites line terminators to the requested `eol`, so mixed-ending
  input normalizes; a body line that is already quoted is preserved verbatim
  (no additional `>` is added).
- Accessors on an out-of-range index (or a hand-built, misaligned `Mailbox`)
  return `""`, `-1` or `0` as documented; they never panic.
- Errors carry a single fixed message and no line/column numbers.

See `SPEC.md` for the full separation grammar, the mboxrd stance, the emitter
shape, the error catalog and the test plan. License: MIT OR Apache-2.0 (see
the repository root `LICENSE`).
