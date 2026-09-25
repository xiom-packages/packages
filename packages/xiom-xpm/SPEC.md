# xiom.xpm SPEC

## Scope

Pure-XIOM parsing and building of X PixMap (XPM) C-source color pixmaps, for
the documented subset:

- the optional `/* XPM */` header comment (any C comment is accepted between
  tokens);
- one `static char * <name>[] = { ... };` declaration with its string list;
- the value line `w h ncolors cpp [x_hot y_hot]`;
- `ncolors` color lines `<cpp symbol chars> <ws> c <ws> <value>`, with the
  value either `#` plus six hex digits or a named token passed through
  verbatim, and with bytes after the value accepted and ignored (XPM
  extension keys such as `m`, `s`, `g`);
- `height` pixel rows of exactly `width * cpp` symbol characters each;
- the C escapes `\\`, `\"`, `\n`, `\t` inside string literals.

The payload is stored flat (symbol-character pool, color-value strings plus a
parallel length vector, one color index per pixel); the module never renders,
never converts to another image format and never touches the file system.

## Non-goals

Rendering, rasterizing, image/file IO, conversion to other pixmap or image
formats, XPM1/XPM2 historical semantics, color-name resolution (names are
opaque), `None` transparency semantics beyond pass-through, XPM extensions
beyond accepting-and-ignoring trailing key bytes on color lines, multi-image
files, `//` comments, preprocessor constructs, sized array brackets, element
types other than `char`, compression.

## Grammar

```
document   := trivia* "static" trivia+ "char" trivia+ "*" trivia* ident
              trivia* '[' trivia* ']' trivia* '=' trivia* '{'
              string-list trivia* '}' trivia* ';' trivia*
string-list := string ( trivia* ',' trivia* string )* trivia* ','?
string     := '"' chars '"'
chars      := ( cbyte | escape )*
cbyte      := byte in 0x20..0xFF except 0x7F, or TAB (0x09)
escape     := '\' ( '\' | '"' | 'n' | 't' )     ; anything else is an error

header     := w ws+ h ws+ ncolors ws+ cpp ( ws+ x_hot ws+ y_hot )?
w h        := digit{1,9}                           ; value 1..1000000
ncolors    := digit{1,9}                           ; value 1..4096
cpp        := digit{1,9}                           ; value 1..4
x_hot, y_hot := digit{1,9}                         ; 0 <= x_hot <= w,
                                                   ; 0 <= y_hot <= h

color-line := symbol{cpp} ws+ 'c' ws+ value extra?
symbol     := byte in 0x20..0xFF except 0x7F
value      := '#' hexdigit{6} | name
name       := 1+ byte, none whitespace, control, '#' or '"'
extra      := ws+ <any bytes>                      ; accepted and ignored

row        := symbol{cpp} * w                      ; exactly w*cpp bytes

ident      := [A-Za-z_][A-Za-z0-9_]*
trivia     := whitespace | comment
whitespace := SPACE | TAB | LF | CR | VT | FF      ; bytes 32, 9, 10, 13, 11, 12
comment    := '/*' <any bytes> '*/'                ; no nesting; must be closed
digit      := '0'..'9'
hexdigit   := '0'..'9' | 'a'..'f' | 'A'..'F'
```

`"static"` and `"char"` are matched as whole keywords (the following byte
must not be an identifier character). Comments and whitespace may separate
any two tokens outside string literals; comments inside string literals are
data, not comments. `{` may contain an empty list only if the parse later
fails with `xpm: missing header`.

## Symbol and pixel rules

- A symbol is `cpp` bytes (cpp in 1..4). Symbols are stored in color order in
  a flat pool: the symbol of color entry `i` is `symbols[i*cpp .. (i+1)*cpp)`.
- Every symbol byte must be a printable byte: 0x20..0xFF except 0x7F. TAB can
  only appear as whitespace between fields, never as a symbol character.
- Every color line's symbol must be distinct from all earlier ones:
  `xpm: duplicate symbol` otherwise.
- A pixel row is exactly `width * cpp` decoded bytes: `width` consecutive
  symbols. A row whose decoded length differs is `xpm: row length mismatch`.
  A symbol that is not in the color table is `xpm: unknown symbol`.
- Pixel `(x, y)` uses a top-left origin and stores a color-table index;
  `xpm_pixel_index` returns it, `xpm_pixel_color` returns the stored color
  value.

## Canonical build layout

`xpm_build(name, img)` and `xpm_build_hotspot(name, img, x_hot, y_hot)`
emit, with LF (`0x0a`) line endings:

```
/* XPM */\n
static char * <name>[] = {\n
"<w> <h> <ncolors> <cpp>[ <x_hot> <y_hot>]",\n
"<symbols>\tc <color>",\n          (one line per color entry)
"<row>",\n                          (one line per pixel row)
"<last row>"\n
};\n
```

- Every string line carries a trailing comma except the last pixel row; the
  header line and every color line therefore always end in `",`.
- The color line separator between the symbol, the `c` key and the value is a
  single TAB, and the value follows one space after `c`.
- Symbol characters and color values are emitted inside the C string with
  `\` escaped as `\\`, `"` as `\"`, TAB as `\t` and LF as `\n`; all other
  bytes are written verbatim.
- The stored spelling of a color value is preserved (`#AbCdEf` stays
  `#AbCdEf`), extension keys are not reproduced, and a source that carried a
  hot spot keeps it through `xpm_build`.
- The output is deterministic: `build(parse(text))` is byte-identical for any
  canonical text, and `build(parse(build(x))) == build(x)`.

## API

```xiom
pub type XpmImage = {
  width: Int;           // 1..1000000
  height: Int;          // 1..1000000
  cpp: Int;             // 1..4
  has_hotspot: Bool;
  x_hot: Int;           // 0..width when has_hotspot, -1 otherwise
  y_hot: Int;           // 0..height when has_hotspot, -1 otherwise
  symbols: Vec[UInt8];  // ncolors * cpp symbol characters, color order
  colors: Vec[Str];     // ncolors values, source spelling preserved
  color_lens: Vec[Int]; // ncolors; byte length of colors[i]
  pixels: Vec[Int];     // width * height color indices, row-major
}

pub fn xpm_width(img: &XpmImage) -> Int
pub fn xpm_height(img: &XpmImage) -> Int
pub fn xpm_ncolors(img: &XpmImage) -> Int
pub fn xpm_cpp(img: &XpmImage) -> Int
pub fn xpm_has_hotspot(img: &XpmImage) -> Bool
pub fn xpm_hotspot_x(img: &XpmImage) -> Int
pub fn xpm_hotspot_y(img: &XpmImage) -> Int
pub fn xpm_pixel_index(img: &XpmImage, x: Int, y: Int) -> Int
pub fn xpm_pixel_color(img: &XpmImage, x: Int, y: Int) -> Str
pub fn xpm_color_at(img: &XpmImage, index: Int) -> Str
pub fn xpm_symbol_index(img: &XpmImage, symbol: Str) -> Int
pub fn xpm_symbol_at(img: &XpmImage, index: Int) -> Str
pub fn xpm_parse(data: &Vec[UInt8]) -> Result[XpmImage, Str]
pub fn xpm_build(name: Str, img: &XpmImage) -> Result[Vec[UInt8], Str]
pub fn xpm_build_hotspot(name: Str, img: &XpmImage, x_hot: Int, y_hot: Int) -> Result[Vec[UInt8], Str]
```

`color_lens` is a public bookkeeping field: it is `ncolors` long and holds
the byte length of each `colors[i]`. The module never measures a `Vec[Str]`
element (a v0.61.3 miscompile risk), so builder validation reads lengths from
`color_lens` instead. Consumers building an `XpmImage` literal must fill it
consistently; parsed and built images always are.

## Semantics

- `xpm_parse` scans tokens left to right. Comments are validated where they
  are skipped, so an unclosed `/*` outside a string literal is
  `xpm: unclosed comment`. Inside string literals the text is data.
- The full string list is decoded first; then the header is parsed, then the
  string count is checked against `1 + ncolors + height`, then color lines,
  then pixel rows. Errors therefore surface in file order within each phase.
- Header validation order is: token count, width, height, ncolors, cpp,
  hotspot bounds. A 10+ digit token in a field is that field's invalid-value
  error.
- Accessor sentinels: `xpm_pixel_index` returns `-1` for out-of-range
  coordinates or an internally inconsistent image; `xpm_pixel_color` and
  `xpm_color_at` return `""`; `xpm_symbol_index` returns `-1`;
  `xpm_symbol_at` returns `""`; `xpm_hotspot_x`/`y` return `-1` when the
  image has no hot spot.
- `_consistent` requires: 1..4096 colors, cpp 1..4, `color_lens.len()` ==
  ncolors, `symbols.len()` == ncolors*cpp, dimensions 1..1000000, and
  `pixels.len()` == width*height.
- `xpm_build` validates the whole image before emitting and preserves the
  image's hot spot when `has_hotspot` is true. `xpm_build_hotspot` always
  emits the given hot spot and ignores `has_hotspot`; the coordinates must
  satisfy `0 <= x_hot <= width` and `0 <= y_hot <= height`.
- Building validates: name is a C identifier; dimensions; cpp; ncolors;
  `color_lens` size; symbol pool size; pixel buffer size; symbol bytes;
  symbol distinctness; color-value syntax; pixel indices in
  `0..ncolors-1`; hot spot bounds.

## Validation and errors

All fallible functions return `Result[..., Str]` with deterministic
`xpm: `-prefixed messages.

| Condition | Message |
|---|---|
| a skipped `/*` has no matching `*/` | `xpm: unclosed comment` |
| declaration is not `static char * <ident>[] = { ... };` (including missing `;`, missing comma between strings, a comma before the first string) | `xpm: malformed declaration` |
| EOF before the string list closes with `}` | `xpm: unclosed string list` |
| EOF inside a string literal | `xpm: unterminated string` |
| escape other than `\\` `\"` `\n` `\t`, or a trailing `\` | `xpm: invalid escape` |
| raw control byte (below 0x20 other than TAB, or DEL) inside a string | `xpm: invalid character` |
| the list has no strings at all | `xpm: missing header` |
| value line is not exactly 4 or 6 whitespace-separated decimal tokens | `xpm: malformed header` |
| width `<= 0`, `> 1000000`, or 10+ digits | `xpm: invalid width` |
| height `<= 0`, `> 1000000`, or 10+ digits | `xpm: invalid height` |
| ncolors `<= 0`, `> 4096`, or 10+ digits | `xpm: invalid ncolors` |
| cpp outside 1..4, or 10+ digits | `xpm: invalid cpp` |
| `x_hot > width` or `y_hot > height` (or 10+ digit hotspot) | `xpm: invalid hotspot` |
| fewer strings than `1 + ncolors` | `xpm: missing color lines` |
| fewer strings than `1 + ncolors + height` | `xpm: missing pixel rows` |
| more strings than `1 + ncolors + height` | `xpm: trailing strings` |
| color line is not `<cpp symbols> <ws> c <ws> value [keys]` (no separator, no `c`, no value) | `xpm: malformed color line` |
| a symbol byte is a control byte or DEL | `xpm: invalid symbol` |
| value is not `#`+6 hex digits, or a name containing whitespace, `#` or `"` | `xpm: malformed color value` |
| two color lines share a symbol | `xpm: duplicate symbol` |
| pixel row length != `width * cpp` | `xpm: row length mismatch` |
| a row symbol is not in the color table | `xpm: unknown symbol` |
| non-trivia bytes after the declaration's `;` | `xpm: trailing tokens` |
| `xpm_build`/`xpm_build_hotspot` name is not a C identifier | `xpm: invalid name` |
| builder width/height `<= 0` or `> 1000000` | `xpm: invalid width` / `xpm: invalid height` |
| builder cpp outside 1..4 | `xpm: invalid cpp` |
| builder ncolors outside 1..4096 | `xpm: invalid ncolors` |
| `color_lens.len()` != ncolors | `xpm: color table size mismatch` |
| `symbols.len()` != ncolors*cpp | `xpm: symbol pool size mismatch` |
| `pixels.len()` != width*height | `xpm: pixel buffer size mismatch` |
| builder symbol byte is a control byte or DEL | `xpm: invalid symbol` |
| builder has duplicate symbols | `xpm: duplicate symbol` |
| builder color is not `#rrggbb` or a valid name token | `xpm: malformed color value` |
| a pixel index is outside `0..ncolors-1` | `xpm: invalid pixel index` |
| hot spot outside `0..width` / `0..height` | `xpm: invalid hotspot` |

Accessors never return error strings; they use the sentinels documented in
Semantics.

## Test plan

19 checks in `tests/test_conformance.xi`:

1. canonical 2x2 parse: dimensions, cpp, ncolors, colors, symbols, all four
   pixel indices and colors, both sentinel families and the hotspot
   accessors.
2. the `/* XPM */` comment is optional; comments between every token parse;
   `/*` inside a pixel-row string is data.
3. named colors and `None` pass through, hex case is preserved and extension
   keys (`m white s solid`, `g red`) are accepted and ignored.
4. cpp=2 with hotspot: all indices, symbol lookup, canonical byte-exact
   build, parse of the build, and a byte-exact rebuild.
5. `xpm_build_hotspot` adds a hot spot, `xpm_build` preserves one, and
   negative/past-the-edge coordinates are rejected; `x_hot == width` and
   `y_hot == height` are accepted.
6. `\\`, `\"`, `\n` and `\t` decode as symbols, separators and row bytes;
   unknown escapes, a trailing backslash, raw control bytes and an
   unterminated literal are rejected.
7. value-line validation: token counts 3/5/7, non-digits, empty line, zero
   and oversized width/height, zero and oversized ncolors, cpp 0 and 5,
   hotspot bounds, plus whitespace tolerance and an accepted hotspot.
8. string-count validation: fewer colors than ncolors, fewer rows than
   height, extra strings, and an exact-count parse.
9. pixel-row validation: too short, too long and unknown symbol.
10. duplicate symbols for cpp 1 and cpp 2.
11. malformed color lines and values: missing `c`, missing separator, missing
    value, bad hex, short/five-digit hex, trailing hex junk, `#` in a name,
    and a control byte as the symbol.
12. declaration and list structure: missing `static`, wrong element type,
    missing `*`/`[`/`]`/`=`/`{`, missing `;`, EOF in the list, empty list,
    missing comma, leading comma, trailing tokens, unclosed comments and
    accepted trailing trivia.
13. builder validation: name, dimensions, cpp, ncolors, all three array-size
    mismatches, pixel index bounds, duplicate and invalid symbols, malformed
    colors, and stored/argument hotspot bounds.
14. canonical cpp-1 build literal is byte-exact and reparses.
15. `"` and `\` symbols are escaped on build and decoded on parse, with a
    byte-exact canonical literal.
16. accessor sentinels for inconsistent images and out-of-range indices.
17. CRLF line endings, spaces around commas, wide gaps in color lines and a
    trailing comma before `}`.
18. cpp=4 with one color parses, looks up symbols of the right length only,
    builds and round-trips.
19. the exact 1000000 width cap parses (last pixel and one-past sentinel) and
    1000001 is rejected.

## Known limitations

- Only the documented subset is parsed; XPM1/XPM2 semantics, `//` comments,
  sized brackets, non-`char` element types and constructs after the
  declaration are rejected rather than interpreted.
- Dimensions are capped at 1,000,000 per axis and ncolors at 4096; the whole
  source and payload are held in memory (no streaming) and multi-image files
  are not supported. A 10+ digit field is rejected even before the value
  would be checked.
- Symbol lookup is linear in the number of colors (O(ncolors) per pixel and
  O(ncolors^2) for duplicate detection at parse/build time); fine for
  ordinary pixmaps, deliberately simple.
- Color names are opaque and never resolved; `None` is stored as the string
  `"None"` with no transparency semantics, and no rendering happens.
- Extension key bytes on color lines are accepted but not stored, so a
  build-parse-build round trip intentionally drops them; hex color spelling,
  by contrast, is preserved.
- `xpm_build` always emits the canonical layout above (`/* XPM */`, one TAB
  separator, one line per color and row); other valid spellings parse but
  are not reproduced.
