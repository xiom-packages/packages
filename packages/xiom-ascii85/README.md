# xiom.ascii85

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) Adobe ASCII85 (Base85) encoding/decoding:
> the PostScript/PDF text encoding over the `!`..`u` alphabet, with the `z`
> four-zero-byte shorthand.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`).

## What it is

`xiom.ascii85` is a small, dependency-light ASCII85 codec. Each 4-byte group
is written as 5 characters of the 85-character alphabet (`!` = 0 ... `u` = 84)
in big-endian digit order; an all-zero group is written as the `z` shorthand;
a final partial group of `n` bytes is written as `n + 1` characters. Decoding
returns a `Result` with deterministic `ascii85: `-prefixed error strings and
is deliberately strict: `z` is only legal at a group boundary, a single
leftover character is an error, and any group value above `0xFFFFFFFF` is an
error.

## API

| Function | Returns | Description |
|---|---|---|
| `a85_encode(data)` | `Str` | Encode bytes: 4-byte group -> 5 chars, all-zero group -> `z`, `n`-byte tail -> `n+1` chars; empty -> `""`. |
| `a85_decode(text)` | `Result[Vec[UInt8], Str]` | Decode ASCII85; whitespace ignored, optional `<~`/`~>` delimiters, `z` at group boundaries; `Err` on invalid characters, misplaced `z`, a single leftover char, or 32-bit overflow. |
| `a85_is_valid(text)` | `Bool` | True iff `a85_decode(text)` would return `Ok`; true for empty input. |
| `a85_max_decoded_len(chars)` | `Int` | Upper bound `ceil(chars * 4 / 5)`; `0` when `chars <= 0`. |

Error catalog (all decode errors start with `ascii85: `):

| Message | Raised by |
|---|---|
| `ascii85: invalid character` | `a85_decode`: byte outside `!`..`u`, including an interior `~`. |
| `ascii85: z inside group` | `a85_decode`: `z` after one or more digits of an unfinished group. |
| `ascii85: incomplete group` | `a85_decode`: a single leftover character. |
| `ascii85: value overflows 32 bits` | `a85_decode`: group value > `0xFFFFFFFF` (for a partial group, after the implicit `u` padding). |

## Usage

```xi
use xiom.ascii85;
use xiom.io;

var data = Vec[UInt8].new();
data.push(77u8);   // 'M'
data.push(97u8);   // 'a'
data.push(110u8);  // 'n'
data.push(32u8);   // ' '
let enc = a85_encode(&data);
io.println(enc);                       // 9jqo^

let dec = a85_decode(enc);
match dec {
  Ok(v) => { if v.len() == 4 { io.println("round-trip ok"); } },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ascii85
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No delimiter emission.** `a85_encode` never writes `<~`/`~>`; callers
  that need Adobe framing add it themselves. `a85_decode` accepts one
  optional leading `<~` and one optional trailing `~>`.
- **No line wrapping.** Output is one unbroken string (no `wrapcol`-style
  folding). The decoders ignore whitespace, so wrapped input decodes fine.
- **No `y` fold-spaces.** The `btoa` extension (`y` = four spaces) is not
  implemented; `y` is an ordinary digit.
- **Whitespace policy.** TAB (9), LF (10), VT (11), FF (12), CR (13) and
  space (32) are ignored anywhere by the decoder; any other byte outside
  `!`..`u` is an error.
- **Non-canonical input decodes.** A full zero group may be written as `z`
  or as `!!!!!`; a partial tail is padded with the maximum digit `u` before
  the top bytes are taken, so non-canonical tails decode to the same bytes as
  their canonical form. Encoders always emit the canonical form.
- **Strictness deviations.** A single leftover character is `Err` (some
  implementations silently drop it), and `z` must sit at a group boundary.
- **Boundary note.** `s8W-!` is exactly `0xFFFFFFFF` and decodes fine;
  `s8W-"` is `0x100000000` and overflows.
- **In-memory only.** Everything works on `Vec[UInt8]`/`Str` values; there
  is no streaming or incremental API, and no `Str` convenience wrapper.
- Pure XIOM: no FFI, no file I/O, no registry integration.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
