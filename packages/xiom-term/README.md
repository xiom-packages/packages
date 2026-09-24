# xiom.term

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** ANSI/VT escape handling: detect, strip, count, measure and
> truncate on visible bytes; parse SGR parameters.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.builder` and `xiom.string.compare` in tests). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.term` treats a `Str` as a byte buffer that may contain ANSI/VT escape
sequences and answers the questions terminal-aware code asks before printing,
logging, aligning or truncating styled text:

- **detect** (`term_has_escapes`, `term_is_plain`): is there any ESC byte?
- **strip** (`term_strip`): remove CSI, OSC and two-byte ESC sequences;
- **count** (`term_count_escapes`): how many sequences were removed?
- **measure** (`term_visible_len`): how many visible bytes remain?
- **truncate** (`term_truncate_visible`): keep the first `n` visible bytes
  and the escapes before the cut, re-applying `ESC [0m` when an SGR sequence
  was cut, so styling does not leak past the truncation point;
- **parse SGR** (`term_parse_sgr`): flatten the parameters of every
  `CSI ... m` sequence into a `Vec[Int]`.

Every function is infallible and byte-oriented; malformed input is handled
leniently (an unterminated CSI or OSC consumes to the end of the input). The
exact grammar and edge cases are pinned in `SPEC.md` and covered by the
20-check conformance suite.

## API

| Function | Returns | Description |
|---|---|---|
| `term_has_escapes(s)` | `Bool` | True when `s` contains any ESC byte (0x1B). |
| `term_is_plain(s)` | `Bool` | True when `s` contains no ESC byte; complement of `term_has_escapes`. |
| `term_strip(s)` | `Str` | Drop every escape unit: CSI (`ESC '['` ... final 0x40-0x7E), OSC (`ESC ']'` ... BEL or `ESC '\'`), any other `ESC` + one byte, and a trailing lone `ESC`. |
| `term_count_escapes(s)` | `Int` | Number of units `term_strip` removes (one per ESC-started unit). |
| `term_visible_len(s)` | `Int` | Byte length of `term_strip(s)`. |
| `term_truncate_visible(s, n)` | `Str` | First `n` visible bytes plus the escapes before the cut; appends `ESC [0m` when an SGR sequence was cut; `n <= 0` yields `""`. |
| `term_parse_sgr(s)` | `Vec[Int]` | Flattened parameters of every `CSI ... m` sequence; empty parameter => `0`; `;` and `:` both split. |

## Sequence grammar

`ESC` is byte `0x1B`. Each ESC starts exactly one unit:

| Unit | Start | Ends at |
|---|---|---|
| CSI | `ESC '['` | first following byte in `0x40..0x7E`, inclusive |
| OSC | `ESC ']'` | BEL (`0x07`) or ST (`ESC '\'`), inclusive |
| Two-byte | any other `ESC` | the ESC plus exactly one following byte |
| Lone ESC | `ESC` at end of input | dropped by itself |

An unterminated CSI or OSC consumes to the end of the input (documented,
lenient).

## Usage

```xi
use xiom.term;
use xiom.io;

fn main() -> Int {
  io.println(term_strip("\x1b[31mred\x1b[0m"));          // red
  io.println(term_visible_len("\x1b[31mred\x1b[0m"));    // 3
  io.println(term_truncate_visible("\x1b[31mabcdef\x1b[0m", 3)); // \x1b[31mabc\x1b[0m
  io.println(term_count_escapes("\x1b[2A\x1b[K"));        // 2
  return 0;
}
```

For SGR parameters:

```xi
var params = term_parse_sgr("\x1b[1;38:5:196mX\x1b[0m");
// params == [1, 38, 5, 196, 0]
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.term
```

Expected tail: 20 `[PASS]` lines, `xiom.term: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Byte-oriented visible length.** `term_visible_len` and the `n` budget of
  `term_truncate_visible` count bytes, not display columns; there is no
  wide-character handling (CJK, emoji), no combining-mark or grapheme-cluster
  awareness, and a cut may fall inside a multi-byte UTF-8 sequence.
- Only ESC-initiated units are removed; other control bytes (CR, BEL outside
  an OSC, other C0/C1 controls) pass through `term_strip`.
- `term_parse_sgr` is syntactic, not semantic: parameter meaning, clamping
  and extended-colour interpretation are left to the caller, and colon-form
  sub-parameters are flattened.
- No cursor state tracking, screen model, or Windows console VT enablement.
- No streaming API; the whole `Str` is processed in memory.

See `SPEC.md` for the full grammar, per-function rules and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
