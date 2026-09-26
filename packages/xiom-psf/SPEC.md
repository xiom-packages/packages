# xiom.psf -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.psf`, version `0.1.0`).
Module: `src/psf.xi` (`module xiom.psf`).
Depends on `xiom.std`; the library module imports nothing (pure integer and
`Vec[UInt8]` code). The tests use `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex` from it.

## Scope

A pure-XIOM (no FFI) codec for the Linux console font formats PSF1 and PSF2:

- `psf_parse` validates a complete PSF1 or PSF2 buffer (magic dispatch,
  header fields, glyph area bounds, optional unicode table termination,
  strict trailing-byte policy) and returns a flat `PsfFont` index;
- header accessors (`version`, `char_count`, `charsize`, `height`, `width`,
  `has_unicode`);
- a per-character glyph byte-span accessor and a bounds-checked glyph byte
  copier;
- a per-character unicode accessor pair (`psf_unicode_count` +
  `psf_unicode_at`) over one shared codepoint pool, plus first-match
  `psf_char_for_unicode` lookup;
- `psf_build1` / `psf_build2` emit canonical PSF1/PSF2 byte streams from raw
  glyph bytes and optional per-glyph codepoint lists;
- deterministic `Err(Str)` messages for malformed fonts and invalid builder
  input.

All storage is flat: scalars plus parallel `Vec[Int]` slots per character
over a shared codepoint pool; there is no `Vec` of structs.

## Non-goals

- Rendering, rasterizing or any pixel-level interpretation of glyph bytes;
  glyph bytes are opaque.
- Font metrics (advance widths, baselines, line spacing), kerning, or
  cross-checking `charsize` against `height`/`width`.
- PSF3/PSFU and any other magic: only the two documented magics are
  recognised. Reserved mode/flag bits are rejected, not interpreted.
- Compression, file I/O, streaming, or multi-font containers.
- Codepoints above 0xFFFF (PSF unicode entries are u16 values).
- Building an all-terminator unicode table (see Pinned policies).
- BDF/PCF/other console font conversions.

## Byte-level layouts

### PSF1

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | magic | must be `0x36 0x04` |
| 2 | 1 | mode | bit 0: 512 glyphs when set, else 256; bit 1: unicode table present; bits 2..7 reserved, must be 0 |
| 3 | 1 | charsize | bytes per glyph, 1..32 |
| 4 | `char_count * charsize` | glyph data | glyph `g` occupies `[4 + g*charsize, 4 + (g+1)*charsize)` |
| `4 + char_count*charsize` | variable | unicode table | present iff mode bit 1 is set; see below |

PSF1 has no width or height field. The documented conventions are
`width == 8` columns and `height == charsize` rows; the accessors return
those constants.

### PSF2

Header, 32 bytes, every multi-byte field little-endian:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | magic | must be `0x72 0xB5 0x4A 0x86` |
| 4 | 4 | version | must be 0 |
| 8 | 4 | header size | must be 32 |
| 12 | 4 | flags | bit 0: unicode table present; bits 1..31 reserved, must be 0 |
| 16 | 4 | length | glyph count (any u32; 0 is structurally valid) |
| 20 | 4 | charsize | bytes per glyph, 1..256 |
| 24 | 4 | height | glyph height in rows, >= 1 |
| 28 | 4 | width | glyph width in columns, 1..64 |
| 32 | `length * charsize` | glyph data | glyph `g` occupies `[32 + g*charsize, 32 + (g+1)*charsize)` |
| `32 + length*charsize` | variable | unicode table | present iff flags bit 0 is set |

The header `length` field is a glyph count, not a file size; there is no
declared total length, so the trailing-bytes policy below defines the end of
the file.

### Unicode table (both versions)

For every glyph in character order, a run of zero or more little-endian u16
codepoints terminated by `0xFFFF`:

```
glyph 0 entries..., 0xFFFF, glyph 1 entries..., 0xFFFF, ...
```

- Every glyph has exactly one terminator, including glyphs with no
  codepoints (a bare `0xFFFF`).
- Codepoint values are 0..65534. `0xFFFF` is the terminator and can never be
  an entry.
- Entries are literal values: control "specials" such as `0x0008`
  (backspace) or `0x000A` (LF) are stored and returned as ordinary
  codepoints.
- The table must be terminated for every glyph and must end exactly at the
  end of the buffer; a truncated or unterminated run is an error.
- Lists may be empty, may repeat codepoints within one glyph, and may repeat
  codepoints across glyphs; lookup uses the first match (see Semantics).

## API signatures

All functions are free functions in module `xiom.psf` (no self methods):

```xi
pub type PsfFont = {
  version: Int;          // 1 or 2
  char_count: Int;       // 256/512 (PSF1) or the PSF2 length field
  charsize: Int;         // bytes per glyph
  height: Int;           // PSF2 height; PSF1 = charsize
  width: Int;            // PSF2 width; PSF1 = 8
  has_unicode: Bool;
  glyph_offset: Int;     // 4 (PSF1) or 32 (PSF2)
  uni_starts: Vec[Int];  // per glyph: index into uni_values
  uni_counts: Vec[Int];  // per glyph: codepoint count
  uni_values: Vec[Int];  // flat codepoint pool in glyph order
}

pub fn psf_version(p: &PsfFont) -> Int
pub fn psf_charcount(p: &PsfFont) -> Int
pub fn psf_charsize(p: &PsfFont) -> Int
pub fn psf_height(p: &PsfFont) -> Int
pub fn psf_width(p: &PsfFont) -> Int
pub fn psf_has_unicode(p: &PsfFont) -> Bool
pub fn psf_glyph_span(p: &PsfFont, ch: Int) -> Int
pub fn psf_unicode_count(p: &PsfFont, ch: Int) -> Int
pub fn psf_unicode_at(p: &PsfFont, ch: Int, i: Int) -> Int
pub fn psf_char_for_unicode(p: &PsfFont, cp: Int) -> Int
pub fn psf_parse(data: &Vec[UInt8]) -> Result[PsfFont, Str]
pub fn psf_glyph_bytes(data: &Vec[UInt8], p: &PsfFont, ch: Int) -> Result[Vec[UInt8], Str]
pub fn psf_build1(glyphs: &Vec[UInt8], charsize: Int, uni: &Vec[Vec[Int]]) -> Result[Vec[UInt8], Str]
pub fn psf_build2(glyphs: &Vec[UInt8], charsize: Int, height: Int, width: Int, uni: &Vec[Vec[Int]]) -> Result[Vec[UInt8], Str]
```

`PsfFont` field invariants: when `has_unicode` is true,
`uni_starts.len() == uni_counts.len() == char_count` and glyph `g`'s
codepoints are `uni_values[uni_starts[g] .. uni_starts[g] + uni_counts[g]]`;
when it is false, the three vectors are empty. Fields are implementation
details; callers should go through the free functions.

## Validation order (pinned)

`psf_parse(data)` with `n = data.len()` checks, in this exact order:

1. `n < 2` -> `psf: truncated header`;
2. first two bytes `0x36 0x04` -> PSF1 path:
   a. `n < 4` -> `psf: truncated header`;
   b. `mode > 3` -> `psf: reserved mode bits`;
   c. `charsize < 1 || charsize > 32` -> `psf: invalid charsize`;
   d. `char_count = 512` when mode bit 0, else `256`; unicode present when
      mode bit 1;
   e. `char_count > (n - 4) / charsize` -> `psf: glyph data out of bounds`;
3. otherwise `n < 4` -> `psf: truncated header`;
4. magic not `0x72 0xB5 0x4A 0x86` -> `psf: bad signature`;
5. PSF2 path:
   a. `n < 32` -> `psf: truncated header`;
   b. `version != 0` -> `psf: unsupported version`;
   c. `header size != 32` -> `psf: bad header size`;
   d. `flags > 1` -> `psf: reserved flag bits`;
   e. `charsize < 1 || charsize > 256` -> `psf: invalid charsize`;
   f. `width < 1 || width > 64` -> `psf: invalid width`;
   g. `height < 1` -> `psf: invalid height`;
   h. `char_count > (n - 32) / charsize` -> `psf: glyph data out of bounds`;
6. no unicode table: `glyph_end != n` -> `psf: trailing bytes`
   (`glyph_end` is 4 or 32 plus `char_count * charsize`); done;
7. unicode table: for each glyph in order, read u16 values until `0xFFFF`;
   when fewer than two bytes remain -> `psf: unicode table out of bounds`;
   after the last terminator `pos != n` -> `psf: trailing bytes`.

The glyph-area check uses the division form, so no
`char_count * charsize` overflow can occur. On `Err` no partial index is
returned.

## Semantics

`psf_version(p)` / `psf_charcount(p)` / `psf_charsize(p)` / `psf_height(p)` /
`psf_width(p)` / `psf_has_unicode(p)`
: Return the parsed header fields. PSF1 reports `version == 1`,
  `char_count` 256 or 512, `charsize` 1..32, `height == charsize`,
  `width == 8` (documented conventions for the fields PSF1 lacks). PSF2
  reports `version == 2`, the header `length`/`charsize`/`height`/`width`,
  with `charsize` 1..256, `width` 1..64, `height` >= 1.

`psf_glyph_span(p, ch)`
: `charsize` for `0 <= ch < char_count`, else `-1`. The span is the exact
  number of glyph bytes in the source buffer.

`psf_glyph_bytes(data, p, ch)`
: `Err("psf: index out of range")` for a bad `ch`; the recorded span is
  bounds-checked against `data` (`Err("psf: glyph data out of bounds")` when
  it does not fit) and exactly `charsize` bytes are copied verbatim, in file
  order. For a font parsed from the same buffer this succeeds for every `ch`.

`psf_unicode_count(p, ch)`
: The number of codepoints of `ch`: `0` for a valid character when no
  unicode table is present, `-1` when `ch` is outside
  `0..charcount-1`.

`psf_unicode_at(p, ch, i)`
: The `i`-th codepoint of `ch` (0..65534), or `-1` when `ch` or `i` is out
  of range or no unicode table is present. The sentinel is unambiguous
  because every stored codepoint is non-negative.

`psf_char_for_unicode(p, cp)`
: The first character whose codepoint list contains `cp`; characters are
  scanned 0..charcount-1 and each list in order, so the smallest matching
  character index wins, including when a later glyph repeats the codepoint.
  `-1` when no character matches, when no unicode table is present, or when
  `cp` is outside 0..65534 (in particular `0xFFFF`, the terminator, and
  negative values). Duplicate codepoints are tolerated.

`psf_parse(data)`
: On success `version` is 1 or 2, `char_count`/`charsize`/`height`/`width`
  are the validated values, `glyph_offset` is 4 or 32, and the unicode
  vectors follow the invariant above. A zero-glyph PSF2 header
  (`length == 0`) is valid: it parses to `char_count == 0` with the glyph
  area empty and every character accessor out of range. PSF1 always has 256
  or 512 glyphs.

`psf_build1(glyphs, charsize, uni)`
: Validation order: `charsize` 1..32; `glyphs.len()` must equal
  `256 * charsize` or `512 * charsize` (which selects mode bit 0); `uni.len()`
  must equal `char_count`; every codepoint must be 0..65534. Emit: magic
  `0x36 0x04`, mode byte (bit 0 = 512 glyphs, bit 1 = table emitted),
  charsize byte, the glyph bytes verbatim, then the unicode table when
  emitted. Mode bit 1 is set exactly when at least one glyph list is
  non-empty (see Pinned policies). Nothing is emitted unless every check
  passes.

`psf_build2(glyphs, charsize, height, width, uni)`
: Validation order: `charsize` 1..256; `height >= 1`; `width` 1..64;
  `glyphs.len() % charsize == 0` (`char_count = glyphs.len() / charsize`);
  `uni.len() == char_count`; every codepoint 0..65534. Emit: the 32-byte
  little-endian header (magic, version 0, header size 32, flags bit 0 when a
  table is emitted, glyph count, charsize, height, width), the glyph bytes
  verbatim, then the unicode table when emitted. Flags bit 0 is set exactly
  when at least one glyph list is non-empty. Nothing is emitted unless every
  check passes.

## Pinned policies

- **Trailing bytes (strict).** The buffer must end exactly after the glyph
  area when no unicode table is present, and exactly after the last `0xFFFF`
  terminator when one is present. Real-world padding after a PSF file is
  rejected, not ignored. Both a shorter and a longer buffer than the
  validated structure fail; the failure for a short glyph area is
  `glyph data out of bounds`, for a short table `unicode table out of
  bounds`, and for extra bytes `trailing bytes`.
- **Magic dispatch.** Any buffer whose first two bytes are `0x36 0x04` is
  treated as PSF1 even if the rest is garbage; any other buffer shorter than
  4 bytes is `truncated header`; with 4+ bytes, neither magic is
  `bad signature`. The PSF2 magic is checked before its 32-byte minimum, so
  a 4..31-byte PSF2 prefix is `truncated header`, not `bad signature`.
- **Reserved bits (reject).** PSF1 mode bits 2..7 and PSF2 flags bits 1..31
  must be zero. The codec never interprets them.
- **Charsize bounds (reject).** PSF1 charsize 1..32 (the format's byte
  field and the documented console maximum); PSF2 charsize 1..256
  (documented cap; the field itself is 32-bit).
- **Width/height.** PSF2 width 1..64; PSF2 height >= 1 with no upper cap
  (height never affects the layout). PSF1 width 8 and height == charsize are
  documented constants, not parsed fields. `charsize` is not cross-checked
  against `height * ceil(width / 8)`; that metric relation is out of scope.
- **Zero-glyph PSF2 (accept).** `length == 0` is structurally valid with or
  without the unicode flag; the glyph area and the table are empty. PSF1
  cannot express zero glyphs.
- **Codepoint domain.** Entries are 0..65534; `0xFFFF` terminates. The
  builders reject negative and > 65534 codepoints; the lookup rejects the
  same, plus `cp` outside u16 range.
- **First-match lookup.** Codepoint lists need not be unique across glyphs;
  `psf_char_for_unicode` returns the smallest glyph index containing `cp`.
- **Builder canonical form.** `psf_build1` emits mode bit 1 and
  `psf_build2` emits flags bit 0 only when at least one glyph list is
  non-empty; an all-empty `uni` argument therefore produces a font with no
  unicode table, and an all-terminator table cannot be produced by the
  builders (it can still be parsed). Version is always 0, header size always
  32, and glyph bytes are emitted verbatim in glyph order.
- **`uni` input shape.** Both builders require exactly `char_count`
  per-glyph lists (one empty list per character when only some characters
  have codepoints); there is no shorter "no table" spelling.

## Error string catalog

| Condition | Error text |
|---|---|
| `psf_parse`: fewer than 2 bytes, PSF1 with fewer than 4 bytes, PSF2 with 4..31 bytes | `psf: truncated header` |
| `psf_parse`: 4+ bytes with neither magic | `psf: bad signature` |
| `psf_parse`: PSF1 mode byte above 3 | `psf: reserved mode bits` |
| `psf_parse`: PSF2 `version` nonzero | `psf: unsupported version` |
| `psf_parse`: PSF2 `header size` not 32 | `psf: bad header size` |
| `psf_parse`: PSF2 `flags` above 1 | `psf: reserved flag bits` |
| `psf_parse`: PSF1 charsize 0 or > 32; PSF2 charsize 0 or > 256 | `psf: invalid charsize` |
| `psf_parse`: PSF2 width 0 or > 64 | `psf: invalid width` |
| `psf_parse`: PSF2 height 0 | `psf: invalid height` |
| `psf_parse`: `char_count * charsize` does not fit after the header | `psf: glyph data out of bounds` |
| `psf_parse`: a u16 read in the unicode table runs past the buffer end | `psf: unicode table out of bounds` |
| `psf_parse`: bytes remain after the glyph area or after the last terminator | `psf: trailing bytes` |
| `psf_glyph_bytes`: `ch` outside `0..charcount-1` | `psf: index out of range` |
| `psf_glyph_bytes`: the recorded span does not fit `data` | `psf: glyph data out of bounds` |
| `psf_build1`: charsize < 1 or > 32; `psf_build2`: charsize < 1 or > 256 | `psf: invalid charsize` |
| `psf_build2`: height < 1 | `psf: invalid height` |
| `psf_build2`: width < 1 or > 64 | `psf: invalid width` |
| `psf_build1`: `glyphs.len()` neither `256*charsize` nor `512*charsize`; `psf_build2`: `glyphs.len() % charsize != 0` | `psf: bad glyph byte count` |
| either builder: `uni.len() != char_count` | `psf: unicode entry count mismatch` |
| either builder: a codepoint outside 0..65534 | `psf: invalid codepoint` |

The accessors `psf_glyph_span`, `psf_unicode_count`, `psf_unicode_at` and
`psf_char_for_unicode` never return error strings; they use `-1` sentinels
(and `psf_unicode_count` returns `0` for a valid character with no table), as
documented in Semantics.

## Complexity

| Operation | Complexity |
|---|---|
| `psf_parse` | O(n) time, O(glyphs + codepoints) storage |
| header accessors / `psf_glyph_span` | O(1) |
| `psf_unicode_count` / `psf_unicode_at` | O(1) |
| `psf_char_for_unicode` | O(charcount + total codepoints) |
| `psf_glyph_bytes` | O(charsize) |
| `psf_build1` / `psf_build2` | O(glyph bytes + table bytes) |

The parsed `PsfFont` does not copy the source buffer: `psf_glyph_bytes` is
how callers read glyphs, and it requires a buffer that still contains the
recorded span.

## Test plan

`tests/test_conformance.xi` (`module psf_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

| # | Check |
|---|---|
| 1 | hand-built PSF1 256x8 parse: version/char_count/charsize/height/width, no table, glyph spans (including the `-1` guards), glyph 0 and 255 bytes, absent-table accessors. |
| 2 | PSF1 mode bit 0: 512x4 parse, mode byte pinned, last glyph bytes read back. |
| 3 | PSF1 unicode table: per-glyph counts and `at` values, empty lists, duplicate codepoints, literal special `0x0008` before its own glyph, first-match lookup for present/absent/invalid codepoints, out-of-range guards. |
| 4 | PSF1 errors: truncation at 0/1/2/3 bytes, bad second magic byte, reserved mode bits (4 and 0x80), charsize 0/33, glyph area one byte short, trailing bytes, unterminated table (one byte and one terminator short), trailing bytes after a table. |
| 5 | hand-built PSF2 4x16 parse: all 32 header bytes' semantics, glyph spans, glyph 3 bytes, absent-table accessors. |
| 6 | PSF2 boundary acceptance: width 1/64, charsize 1/256, height 1/1000, single glyph byte pinned. |
| 7 | PSF2 unicode table: raw table bytes pinned (four glyphs, one empty), counts, `at` values, first-match lookup. |
| 8 | PSF2 errors in order: 4-byte and 31-byte truncation, bad signature, version 1, header size 28/64, flags 2/0x80000000, charsize 0/257, width 0/65, height 0, glyph bounds, trailing bytes, missing/unterminated/extra table bytes, and an accepted bare-terminator table. |
| 9 | zero-glyph PSF2 parses with and without the unicode flag; one trailing byte is rejected. |
| 10 | `psf_build1` canonical 256x4: header bytes, glyph bytes, parse round-trip, copier reconstruction, byte-exact rebuild. |
| 11 | `psf_build1` 512 glyphs chosen by buffer length; mode byte 1; last glyph bytes; round-trip. |
| 12 | `psf_build1` with a unicode table: mode byte 2, table bytes at pinned offsets, parse accessors and lookup, byte-exact round trip. |
| 13 | `psf_build1` errors: charsize 0/33, bad glyph byte count, unicode count mismatch, codepoints `0xFFFF` and `-1`, and `0xFFFE` accepted. |
| 14 | `psf_build2` canonical header: every field pinned little-endian, glyph bytes, parse round-trip and byte-exact rebuild. |
| 15 | `psf_build2` with a unicode table: flags 1, table bytes pinned, counts/lookup, byte-exact round trip. |
| 16 | `psf_build2` errors: charsize 0/257, height 0, width 0/65, non-multiple glyph bytes, unicode count mismatch, codepoints 70000 and -2. |
| 17 | glyph copier guards: bad `ch`, stale span against a shorter buffer; absent-table and out-of-range unicode accessors. |
| 18 | magic dispatch boundaries: 0/1/2/3-byte buffers, a 4-byte PSF2 magic prefix, wrong magics at 4 bytes. |
| 19 | all-terminator tables parse for PSF1 and PSF2; the builder collapses all-empty lists to no table (flag clear). |
| 20 | PSF1 charsize 1 and 32 accepted; a 512-glyph charsize-1 font with a full unicode table parses, pins first-match, and round-trips byte-exactly. |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.psf
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No rendering and no pixel interpretation: glyph bytes are opaque; the codec
  never relates `charsize` to `height * ceil(width / 8)`.
- Only PSF1 and PSF2 magics; PSF3/PSFU and anything else are
  `psf: bad signature`.
- Strict trailing-byte policy: padded or concatenated real-world files are
  rejected rather than trimmed.
- The index references the source buffer; `psf_glyph_bytes` needs a buffer
  that still contains the recorded span, and a parsed font is not portable
  across buffers without re-parsing.
- Whole-font in memory; no streaming or incremental parsing.
- Codepoints are u16: there is no UCS-4/UTF-8 handling.
- The builders cannot emit an all-terminator unicode table; an all-empty
  `uni` argument collapses to "no table".
- Reserved mode/flag bits are rejected, so a future PSF extension using them
  does not parse.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_font`/`_err_font`/`_ok_bytes`/`_err_bytes` (constructing a `Result`
  with a struct payload in another function miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering `Int` arithmetic; multi-byte fields are read/written
  arithmetically in little-endian order (`% 256`, `/ 256`, ...).
- Mode/flag bits are tested arithmetically (`mode > 3`, `mode % 2`,
  `mode / 2`, `flags > 1`), never with shifts or masks on 32-bit values.
- The glyph-area bound uses `char_count > (n - offset) / charsize` (exact for
  the non-negative operands, and `charsize >= 1` is guaranteed before it),
  so the check cannot overflow.
- The per-glyph unicode vectors `uni_starts` and `uni_counts` are appended
  only in lockstep, one pair per glyph; `uni_values` receives one push per
  codepoint. When no table is present all three stay empty.
- `Str` values are compared through `string.str_compare` in the tests; `==`
  on a `Str` read from a `Vec` lowers to a pointer comparison (BUG 17).
- The package declares no `extern "C"` blocks (no FFI) and no new
  dependencies; `deps` stays `{ "xiom.std": ">=0.60.0 <1.0.0" }`.
