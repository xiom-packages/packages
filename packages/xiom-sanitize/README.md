# xiom.sanitize

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** byte-oriented input sanitization: control characters, whitespace,
> ASCII, filenames, digits and slugs.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.sanitize` turns untrusted text into safer text for a specific context.
Every function is a free function `Str -> Str`, scans the input byte-wise and
is infallible -- dropped or replaced bytes are never reported, and no output is
ever validated (these are sanitizers, not validators):

- **control characters** (`sanitize_control_chars`): replace C0 controls and
  DEL with a caller-chosen replacement, preserving LF and TAB;
- **ASCII** (`sanitize_ascii`): drop every byte >= 0x80;
- **whitespace** (`sanitize_whitespace`): collapse space/tab runs, strip
  spaces before LF, trim the ends, preserve LF;
- **allow lists** (`sanitize_keep`): keep `[A-Za-z0-9]` plus a caller byte set;
- **filenames** (`sanitize_filename`): replace `< > : " / \ | ? *` and control
  bytes with `_`, strip leading/trailing spaces and dots, fall back to `_`;
- **digits** (`sanitize_numeric`): keep ASCII digits only;
- **slugs** (`sanitize_slug`): lowercase ASCII, non-alphanumeric runs -> `-`,
  trim `-` at both ends.

The exact rules and edge cases are pinned in `SPEC.md` and covered by the
20-check conformance suite.

## API

| Function | Returns | Description |
|---|---|---|
| `sanitize_control_chars(s, replacement)` | `Str` | Replace C0 controls (0x00-0x1F) and DEL (0x7F) with `replacement` verbatim; LF and TAB pass through. |
| `sanitize_ascii(s)` | `Str` | Drop every byte >= 0x80; ASCII (including controls) passes through. |
| `sanitize_whitespace(s)` | `Str` | Collapse space/tab runs to one space; strip spaces/tabs before LF; trim the ends; LF preserved. |
| `sanitize_keep(s, allow)` | `Str` | Keep `[A-Za-z0-9]` plus every byte occurring in `allow`; drop everything else. |
| `sanitize_filename(s)` | `Str` | Replace `< > : " / \ | ? *` and control bytes with `_`; strip leading/trailing spaces and dots; empty result becomes `_`. |
| `sanitize_numeric(s)` | `Str` | Keep ASCII digits 0-9 only; signs, dots and separators are dropped. |
| `sanitize_slug(s)` | `Str` | Lowercase ASCII; non-alphanumeric runs become one `-`; leading/trailing `-` trimmed; empty result is `""`. |

## Usage

```xi
use xiom.sanitize;
use xiom.io;

fn main() -> Int {
  io.println(sanitize_filename("..\\etc/passwd"));   // _etc_passwd
  io.println(sanitize_slug("Merci, Beaucoup!"));     // merci-beaucoup
  io.println(sanitize_numeric("Order #A-1024"));     // 1024
  io.println(sanitize_whitespace("  a   b \n c  ")); // a b\n c
  return 0;
}
```

For an injected control byte, build the input byte-wise (source literals
cannot spell every control byte; note that `Str::from_utf8` truncates at the
first NUL byte, so build strings without `0x00`):

```xi
var raw = Vec[UInt8].new();
raw.push(65u8);    // 'A'
raw.push(1u8);     // SOH
raw.push(66u8);    // 'B'
io.println(sanitize_control_chars(Str::from_utf8(raw), "_")); // A_B
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.sanitize
```

Expected tail: 20 `[PASS]` lines, `xiom.sanitize: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Byte-oriented.** All scanning is over UTF-8 bytes. Non-ASCII input is
  dropped byte-wise, so a result may truncate a multi-byte character and be
  invalid UTF-8 (`sanitize_ascii`, `sanitize_keep`, `sanitize_numeric`,
  `sanitize_slug`); `sanitize_control_chars` and `sanitize_filename` pass
  non-ASCII bytes through intact.
- **ASCII-centric.** Case folding is ASCII-only (no locale); "whitespace"
  means space and tab only (not CR, VT, FF, NBSP); digits are `[0-9]` only.
- No Unicode normalization or NFC/NFD handling, no locale awareness.
- `sanitize_filename` is not a path validator: reserved device names
  (`CON`, `NUL`, ...), length limits, and `..` traversal sequences are not
  handled -- it only cleans one filename component.
- Sanitizers are not validators: none of the functions report errors, and no
  function validates that its output is non-empty (only `sanitize_filename`
  falls back to `_`).
- No HTML/SQL/URL escaping or validation (those are separate contexts, see
  `xiom.escape`).

See `SPEC.md` for the full per-function rules and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
