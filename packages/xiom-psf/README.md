# xiom.psf

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM codec for the PSF1 and PSF2 Linux console font
> formats: header validation, glyph bytes, optional unicode tables, and
> canonical PSF1/PSF2 builders.
> **Deps:** `xiom.std` only (the library module imports nothing; the tests
> add `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.psf` reads and writes the two console font containers used by Linux:

```
PSF1: 36 04 <mode> <charsize> <glyphs...> [unicode table]
PSF2: 72 B5 4A 86 <version> <hdrsize> <flags> <count>
      <charsize> <height> <width> <glyphs...> [unicode table]
```

`psf_parse` validates a complete buffer and returns a flat `PsfFont` index:
header scalars plus, when a unicode table is present, one codepoint range
per character over a shared codepoint pool (no `Vec` of structs). The
accessors expose `version`, glyph count, `charsize`, `height`, `width` and
table presence; `psf_glyph_span` and `psf_glyph_bytes` reach the glyph bytes;
`psf_unicode_count` / `psf_unicode_at` read a character's codepoints and
`psf_char_for_unicode` finds the first character containing a codepoint.
`psf_build1` and `psf_build2` emit canonical fonts from raw glyph bytes plus
optional per-glyph codepoint lists.

Glyph bytes are opaque: there is no rendering, no font metrics, and no
relation imposed between `charsize` and `height * ceil(width / 8)`.

## Quick start

```xi
use xiom.psf;

// Parse a console font read by the caller (file IO is not this package's job).
let r = psf_parse(&font_bytes);
if r.is_ok {
  let f: PsfFont = r.value;
  let n = psf_charcount(&f);        // 256/512 for PSF1, header length for PSF2
  let cs = psf_charsize(&f);        // bytes per glyph
  let g = psf_glyph_bytes(&font_bytes, &f, 65);  // glyph for character 65
  if g.is_ok {
    let bytes: Vec[UInt8] = g.value; // exactly cs opaque glyph bytes
  }
  if psf_has_unicode(&f) {
    let k = psf_unicode_count(&f, 65);           // codepoints of char 65
    let cp = psf_unicode_at(&f, 65, 0);          // first one, or -1
    let who = psf_char_for_unicode(&f, 0x20AC);  // first char with the euro sign
  }
}

// Build a PSF2 font: raw glyph bytes, charsize, height, width, per-glyph
// codepoint lists (exactly char_count of them; empty lists are allowed).
var uni = Vec[Vec[Int]].new();
var list = Vec[Int].new();
list.push(65);              // glyph 0 maps to 'A'
uni.push(list);
let built = psf_build2(&glyph_bytes, 16, 16, 8, &uni);
```

## API

| Function | Returns | Description |
|---|---|---|
| `psf_parse(data)` | `Result[PsfFont, Str]` | Validate a PSF1/PSF2 buffer and index it. |
| `psf_version(p)` | `Int` | 1 for PSF1, 2 for PSF2. |
| `psf_charcount(p)` | `Int` | Glyph count: 256/512 (PSF1) or the header length (PSF2). |
| `psf_charsize(p)` | `Int` | Bytes per glyph: 1..32 (PSF1) or 1..256 (PSF2). |
| `psf_height(p)` | `Int` | PSF2 height; PSF1 returns `charsize` (documented). |
| `psf_width(p)` | `Int` | PSF2 width 1..64; PSF1 returns 8 (documented). |
| `psf_has_unicode(p)` | `Bool` | Whether the source carried a unicode table. |
| `psf_glyph_span(p, ch)` | `Int` | `charsize`, or `-1` when `ch` is out of range. |
| `psf_glyph_bytes(data, p, ch)` | `Result[Vec[UInt8], Str]` | Copy one glyph's bytes verbatim. |
| `psf_unicode_count(p, ch)` | `Int` | Codepoints of `ch` (0 without a table); `-1` out of range. |
| `psf_unicode_at(p, ch, i)` | `Int` | The `i`-th codepoint, or `-1` out of range. |
| `psf_char_for_unicode(p, cp)` | `Int` | First character containing `cp` (0..65534), else `-1`. |
| `psf_build1(glyphs, charsize, uni)` | `Result[Vec[UInt8], Str]` | Canonical PSF1: 256 or 512 glyphs from `glyphs.len()`. |
| `psf_build2(glyphs, charsize, height, width, uni)` | `Result[Vec[UInt8], Str]` | Canonical PSF2 from glyph bytes. |

Both builders take `uni` as exactly `char_count` per-glyph codepoint lists
(`Vec[Vec[Int]]`). When every list is empty no unicode table is emitted (the
mode/flag bit stays clear); otherwise the table is emitted for all glyphs,
with empty lists contributing a bare `0xFFFF` terminator.

## Format notes

- **PSF1 header** is 4 bytes: magic `0x36 0x04`, a mode byte (bit 0 selects
  512 glyphs, bit 1 marks a unicode table, bits 2..7 are reserved and
  rejected) and a charsize byte (1..32).
- **PSF2 header** is 32 little-endian bytes: magic, version (must be 0),
  header size (must be 32), flags (bit 0 marks the table, bits 1..31
  reserved), glyph count, charsize (1..256), height (>= 1), width (1..64).
- **Unicode tables** are per glyph runs of little-endian u16 codepoints
  (0..65534) ended by `0xFFFF`, one terminator per glyph. Control "specials"
  such as `0x0008` (backspace) are ordinary entries; duplicates are allowed
  and `psf_char_for_unicode` returns the first match.
- **Glyph data** is `char_count * charsize` opaque bytes in character order;
  glyph `g` starts at offset 4 (PSF1) or 32 (PSF2) plus `g * charsize`.
- **PSF1 width/height:** PSF1 has no such fields; the documented conventions
  are width 8 and height == charsize, which the accessors return.
- **Trailing bytes are rejected** (strict policy): the buffer must end
  exactly after the glyph area, or after the last terminator when a table is
  present. Padding is not ignored.

## Error model

Every fallible function returns `Result[..., Str]` with a deterministic,
`psf: `-prefixed message. `psf_glyph_span`, `psf_unicode_count`,
`psf_unicode_at` and `psf_char_for_unicode` use `-1` sentinels instead
(`psf_unicode_count` returns `0` for a valid character with no table).

| Message | Trigger |
|---|---|
| `psf: truncated header` | buffer shorter than 2 bytes; PSF1 shorter than 4; PSF2 with 4..31 bytes |
| `psf: bad signature` | 4+ bytes matching neither magic |
| `psf: reserved mode bits` | PSF1 mode byte above 3 |
| `psf: unsupported version` | PSF2 version field nonzero |
| `psf: bad header size` | PSF2 header size not 32 |
| `psf: reserved flag bits` | PSF2 flags above 1 |
| `psf: invalid charsize` | PSF1 charsize 0/33+; PSF2 charsize 0/257+; also builder input |
| `psf: invalid width` | PSF2 width 0 or above 64 |
| `psf: invalid height` | PSF2 height 0 |
| `psf: glyph data out of bounds` | glyph area past the buffer end (parse) or recorded span not in `data` (copier) |
| `psf: unicode table out of bounds` | a u16 read in the table runs past the end |
| `psf: trailing bytes` | bytes remain after the glyph area or the last terminator |
| `psf: index out of range` | `psf_glyph_bytes` character index out of range |
| `psf: bad glyph byte count` | build1: `glyphs.len()` not `256*charsize`/`512*charsize`; build2: not a multiple of `charsize` |
| `psf: unicode entry count mismatch` | `uni.len() != char_count` |
| `psf: invalid codepoint` | a codepoint outside 0..65534 |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.psf
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The suite covers hand-built PSF1 (256 and 512 glyphs) and PSF2 fixtures,
unicode tables with terminators, empty lists, duplicates and control-byte
specials, first-match lookup, every parse error in its documented order,
glyph-copier and accessor guards, canonical builders for both versions with
and without tables, and build -> parse -> build byte-exact round trips.

## Limitations

- Opaque glyphs: no rendering, no font metrics, no `charsize` vs
  `height * ceil(width / 8)` check.
- PSF1 and PSF2 only; PSF3/PSFU or future mode/flag bits are rejected.
- Strict trailing-byte policy: padded or concatenated files do not parse.
- The index points into the parsed buffer; `psf_glyph_bytes` needs a buffer
  that still contains the recorded span.
- Whole font in memory; no streaming.
- Codepoints are u16; no UCS-4 or UTF-8 mapping.
- Builders never emit an all-terminator table (an all-empty `uni` collapses
  to "no table").

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
