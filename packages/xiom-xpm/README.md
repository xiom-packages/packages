# xiom.xpm

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (19/19); NOT published yet.
> **Scope:** X PixMap (XPM): the `static char * name[]` C-source color pixmap -- value line, color table, symbol lookup, pixel lookup, and a canonical builder.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Overview

`xiom.xpm` reads and writes the C-source color pixmap format used by X11:

```c
/* XPM */
static char * sample[] = {
"2 2 2 1",
"  c #ffffff",
"X c #000000",
" X",
"X ",
};
```

The parser accepts the documented subset of real-world XPM files: the optional
`/* XPM */` header comment (any C comment is accepted between tokens), the
`static char * <name>[] = { ... };` declaration, the value line
`w h ncolors cpp [x_hot y_hot]`, one color line per color
(`<cpp symbol chars> <ws> c <ws> <value>`), and `height` pixel rows of exactly
`width * cpp` symbol characters each. Inside string literals the C escapes
`\\`, `\"`, `\n` and `\t` are decoded; any other escape is an error. A color
value is either `#` plus six hex digits or a name token passed through
verbatim, so `None` and symbolic names survive round trips; bytes after the
value (XPM extension keys such as `m`, `s` and `g`) are accepted and ignored.

The payload is stored flat: a symbol-character pool, the color-value strings
with a parallel length vector, and one color index per pixel in row-major
order. Accessors expose the dimensions, cpp, the color table, symbol lookup
and `(x, y)` pixel lookup; `xpm_build` and `xpm_build_hotspot` emit canonical
XPM text.

## Install / use

```
xiom pkg install xiom.xpm@0.1.0     # consumer, once published
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xiom
use xiom.xpm;

match xpm_parse(file_bytes) {          // file IO is the caller's job
  Ok(img) => {
    // xpm_width(&img) == 2, xpm_height(&img) == 2,
    // xpm_ncolors(&img) == 2, xpm_cpp(&img) == 1
    let k: Int = xpm_pixel_index(&img, 1, 0);    // color index, or -1
    let c: Str = xpm_pixel_color(&img, 1, 0);    // "#000000", or ""
    let entry: Str = xpm_color_at(&img, 0);      // "#ffffff"
    let sym: Str = xpm_symbol_at(&img, 1);       // "X"
    let at: Int = xpm_symbol_index(&img, "X");   // 1, or -1
  },
  Err(e) => { /* "xpm: ..." */ },
}

// Build canonical XPM text from a parsed image
match xpm_build("sample", &img) {
  Ok(text) => { /* canonical XPM source bytes */ },
  Err(e) => { /* xpm: invalid name, ... */ },
}
```

## API summary

| Function | Description |
|----------|-------------|
| `xpm_parse(data)` | Parses comment + declaration + value line + color lines + rows; returns `XpmImage` |
| `xpm_width(img)` | Width, `1..1000000` |
| `xpm_height(img)` | Height, `1..1000000` |
| `xpm_ncolors(img)` | Number of color-table entries, `1..4096` |
| `xpm_cpp(img)` | Symbol characters per pixel, `1..4` |
| `xpm_has_hotspot(img)` | True when the value line carried `x_hot y_hot` |
| `xpm_hotspot_x(img)` / `xpm_hotspot_y(img)` | Hot spot coordinate, or `-1` when absent |
| `xpm_pixel_index(img, x, y)` | Color index of pixel `(x, y)`, or `-1` out of range / inconsistent |
| `xpm_pixel_color(img, x, y)` | Color value of pixel `(x, y)`, or `""` |
| `xpm_color_at(img, index)` | Color value of table entry `index`, or `""` |
| `xpm_symbol_index(img, symbol)` | Color index whose symbol is `symbol`, or `-1` |
| `xpm_symbol_at(img, index)` | The `cpp`-character symbol of entry `index`, or `""` |
| `xpm_build(name, img)` | Canonical XPM text, preserving the image's hot spot |
| `xpm_build_hotspot(name, img, x_hot, y_hot)` | Canonical XPM text with the given hot spot |

`XpmImage` fields: `width`, `height`, `cpp`, `has_hotspot`, `x_hot`, `y_hot`,
`symbols` (`Vec[UInt8]`, `ncolors * cpp` symbol characters in color order),
`colors` (`Vec[Str]`, source spelling preserved), `color_lens` (`Vec[Int]`,
the byte length of each color) and `pixels` (`Vec[Int]`, one color index per
pixel, row-major).

## Error model

Every fallible function returns `Result[..., Str]` with a deterministic,
`xpm: `-prefixed message.

| Message | Trigger |
|---|---|
| `xpm: unclosed comment` | a skipped `/*` has no matching `*/` (inside strings, `/*` is data) |
| `xpm: malformed declaration` | not `static char * <ident>[] = { ... };` (missing `*`/`[`/`]`/`=`/`{`/`;`, missing comma between strings) |
| `xpm: unclosed string list` | EOF before the list closes with `}` |
| `xpm: unterminated string` | EOF inside a string literal |
| `xpm: invalid escape` | an escape other than `\\` `\"` `\n` `\t`, or a trailing `\` |
| `xpm: invalid character` | a raw control byte (below 0x20 other than TAB, or DEL) inside a string |
| `xpm: missing header` | the string list contains no strings |
| `xpm: malformed header` | value line is not exactly 4 or 6 whitespace-separated decimal tokens |
| `xpm: invalid width` / `xpm: invalid height` | `<= 0`, `> 1000000`, or 10+ digits |
| `xpm: invalid ncolors` | `<= 0`, `> 4096`, or 10+ digits |
| `xpm: invalid cpp` | outside `1..4`, or 10+ digits |
| `xpm: invalid hotspot` | `x_hot > width`, `y_hot > height`, or 10+ digits |
| `xpm: missing color lines` | fewer strings than `1 + ncolors` |
| `xpm: missing pixel rows` | fewer strings than `1 + ncolors + height` |
| `xpm: trailing strings` | more strings than `1 + ncolors + height` |
| `xpm: malformed color line` | not `<cpp symbols> <ws> c <ws> value [keys]` |
| `xpm: invalid symbol` | a symbol byte is a control byte or DEL |
| `xpm: malformed color value` | value is not `#`+6 hex digits, or a name with whitespace, `#` or `"` |
| `xpm: duplicate symbol` | two color lines share a symbol (also builder input) |
| `xpm: row length mismatch` | a pixel row is not `width * cpp` bytes |
| `xpm: unknown symbol` | a row symbol is not in the color table |
| `xpm: trailing tokens` | non-trivia bytes after the declaration's `;` |
| `xpm: invalid name` | builder name is not a C identifier |
| `xpm: color table size mismatch` | `color_lens.len() != ncolors` |
| `xpm: symbol pool size mismatch` | `symbols.len() != ncolors * cpp` |
| `xpm: pixel buffer size mismatch` | `pixels.len() != width * height` |
| `xpm: invalid pixel index` | a pixel index is outside `0..ncolors-1` |

Accessors never return error strings: they use `-1`/`""`/`false` sentinels;
`xpm_parse` is how callers distinguish "out of range" from "malformed".

## Format notes

- Whitespace is SPACE, TAB, LF, CR, VT, FF. C comments may separate any two
  tokens outside string literals; `/*` inside a quoted string is ordinary
  data.
- A string literal decodes `\\`, `\"`, `\n` and `\t`; any other escape is an
  error. Raw control bytes (except TAB) and DEL are rejected inside strings.
- A symbol is `cpp` bytes (1..4), each in `0x20..0xFF` except `0x7F`; symbols
  must be distinct. Pixel rows are `width` consecutive symbols, so exactly
  `width * cpp` bytes.
- A color value is `#` + exactly 6 hex digits (spelling preserved) or a name
  token (`red`, `None`, symbolic names) passed through. Bytes after the value
  are extension keys and are accepted and ignored.
- The hot spot is optional; when present it must satisfy `0 <= x_hot <= width`
  and `0 <= y_hot <= height`, and it survives `xpm_build`.
- Canonical build: `/* XPM */`, `static char * <name>[] = {`, the value line,
  one `"<symbols>\tc <color>",` line per color, one `"<row>",` line per pixel
  row (last row without a comma), then `};`. Output uses LF endings, ends
  with one LF, and escapes `\` and `"` inside emitted strings.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.xpm
```

Expected: 19 `[PASS]` lines, then `xiom.xpm: all tests passed`, exit 0.

The suite covers the canonical 2x2 parse with every accessor and sentinel;
optional/interspersed comments and `/*` as string data; named colors, `None`,
hex-case preservation and ignored extension keys; a cpp=2 image with a hot
spot and a byte-exact build/parse/rebuild round trip; hot spot addition,
preservation and bounds; all four escapes and every escape error; the full
value-line validation matrix; string-count mismatches; row length and unknown
symbols; duplicate symbols; malformed color lines and values; declaration,
list and trailing-token structure; the builder error catalog; canonical
byte-exact literals for cpp=1 and escaped symbols; inconsistent-image
sentinels; CRLF and spacing tolerance; cpp=4; and the 1,000,000 width cap.

## Limitations

- One XPM subset only: no XPM1/XPM2 semantics, no rendering, no file IO, no
  conversion to other image formats, no multi-image files.
- Color names are never resolved and `None` carries no transparency
  semantics; extension keys are accepted but not stored, so a rebuild drops
  them.
- Dimensions are capped at 1,000,000 per axis and ncolors at 4096; the whole
  source and payload are in memory (no streaming).
- Symbol lookup is linear in the number of colors, and duplicate detection is
  O(ncolors^2) -- deliberately simple, adequate for ordinary pixmaps.
- `xpm_build` always emits the pinned canonical layout; other valid
  spellings parse but are not reproduced.
