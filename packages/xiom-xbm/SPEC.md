# xiom.xbm SPEC

## Scope

Pure-XIOM parsing and building of the X BitMap (XBM) C-source 1-bit raster
format used by X11, for the documented subset:

- the two dimension defines `#define <name>_width N` and
  `#define <name>_height N`, in either order;
- one `static char` / `static unsigned char` `<name>_bits[] = { ... };`
  array as the final construct;
- C `/* ... */` comments and any whitespace between tokens;
- hex byte lists with 1-2 digits per byte, upper or lower case.

Rasters live in a flat `Vec[UInt8]`; the module never allocates an image type,
never renders, and never touches the file system.

## Non-goals

XPM (`*.xpm`: colors, symbolic names, extensions), rendering or rasterizing,
image/file IO, multi-image or multi-bitplane files, `X10`/`X11` bitmap
utilities, `//` comments, preprocessor features beyond the two `#define`s
(macros, `#if`, includes), sized or non-empty array brackets, element types
other than `char`/`unsigned char`, compression, scaling.

## Grammar

```
xbm        := trivia* define+ array trivia*          ; both defines required,
                                                     ; either order; array last
define     := '#' trivia* "define" trivia+ dim-name trivia* decimal
dim-name   := ident "_width" | ident "_height"       ; ident non-empty
array      := "static" trivia+ ("unsigned" trivia+)? "char" trivia+
              arr-name trivia* '[' trivia* ']' trivia* '=' trivia*
              '{' bytes? '}' trivia* ';'
arr-name   := ident "_bits"                          ; ident non-empty
bytes      := byte ( trivia* ',' trivia* byte )* trivia* ','?
byte       := ('0' ('x'|'X') hexdigit hexdigit?)
decimal    := digit{1,9}                             ; value 1..1000000
ident      := [A-Za-z_][A-Za-z0-9_]*
trivia     := whitespace | comment
whitespace := SPACE | TAB | LF | CR | VT | FF        ; bytes 32, 9, 10, 13, 11, 12
comment    := '/*' <any bytes> '*/'                  ; no nesting; must be closed
digit      := '0'..'9'
hexdigit   := '0'..'9' | 'a'..'f' | 'A'..'F'
```

`"define"`, `"static"`, `"unsigned"` and `"char"` are matched as whole
keywords: the byte after them must not be an identifier character, so
`#definefoo` is rejected. `#` and `define` may be separated by trivia
(`# define`), and every token may be separated by comments.

The three base names -- `<ident>` in `<ident>_width`, `<ident>_height` and
`<ident>_bits` -- must be byte-for-byte identical, and each `<ident>` must be
non-empty. The array must be the last construct; only trivia may follow its
`;`.

## Bit order and padding

- Row stride is `xbm_row_bytes(width) = (width + 7) / 8` bytes.
- Pixel `(x, y)` lives in byte `y * stride + x / 8` at bit `x % 8`, counting
  from the least significant bit: bit 0 is the leftmost pixel (LSB first, the
  X11 convention). `0x01` therefore lights pixel 0 of the row.
- `1` is foreground, `0` is background. `xbm_bit` returns the pixel value.
- Every row is padded independently to a whole byte. The unused high bits of a
  row's final byte are padding: `xbm_parse` accepts any padding value and
  `xbm_bit` never reads beyond `x < width`; `xbm_pack` always writes padding
  as `0`.
- The raster must contain exactly `stride * height` bytes. Fewer or more are
  `xbm: byte count mismatch`.

## Canonical build layout

`xbm_build(name, bits, width, height)` emits, with LF (`0x0a`) line endings:

```
#define <name>_width <width>\n
#define <name>_height <height>\n
static char <name>_bits[] = {\n
   <12 bytes per line, 3-space indent, lowercase 0x%02x>\n
};\n
```

- Byte lines carry exactly 12 bytes, indented with three spaces and separated
  by `, `.
- When a line break falls between two bytes, the comma stays at the end of the
  earlier line (so continued lines end in `,`); the final byte of the array
  has no comma.
- The closing `};` is on its own line and the output ends with exactly one LF.
- A single-byte image emits one indented line, e.g.
  `   0x01\n};\n`.

## API

```xiom
pub type XbmImage = {
  width: Int;        // 1..1000000
  height: Int;       // 1..1000000
  name: Str;         // shared base name
  bits: Vec[UInt8];  // packed raster, LSB-first within each byte
}

pub fn xbm_row_bytes(width: Int) -> Int
pub fn xbm_width(img: &XbmImage) -> Int
pub fn xbm_height(img: &XbmImage) -> Int
pub fn xbm_name(img: &XbmImage) -> Str
pub fn xbm_byte_span(img: &XbmImage) -> Int
pub fn xbm_bit(img: &XbmImage, x: Int, y: Int) -> Int
pub fn xbm_parse(data: &Vec[UInt8]) -> Result[XbmImage, Str]
pub fn xbm_pack(pixels: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str]
pub fn xbm_build(name: Str, bits: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str]
```

## Semantics

- `xbm_parse` unclosed-comment check runs first over the whole buffer; then
  tokens are consumed left to right. A dimension define is validated where it
  appears (value, duplicate), so errors surface in file order.
- After the array's `;`, any non-trivia byte is `xbm: trailing tokens`.
- After the top-level scan: missing width, then missing height, then missing
  array, then both name comparisons, then the byte count.
- `xbm_parse` returns exactly the bytes between `{` and `}`; whitespace and
  comments inside the list are not part of `img.bits`.
- `xbm_pack` maps pixel `(x, y)` to bit `x % 8` of byte `y * stride + x / 8`;
  padding bits are zero. Input values other than `0`/`1` are rejected.
- `xbm_bit` returns `1`/`0` for in-range coordinates of a well-formed image,
  and the documented sentinel `-1` for negative or overflowing coordinates or
  an internally inconsistent image (non-positive dimensions, truncated
  `bits`).
- `xbm_byte_span` is `img.bits.len()`, which equals
  `xbm_row_bytes(width) * height` for parsed and built images.

## Validation and errors

| Condition | Message |
|---|---|
| a `/*` has no matching `*/` | `xbm: unclosed comment` |
| no `_width` define before end of input | `xbm: missing width define` |
| no `_height` define before end of input | `xbm: missing height define` |
| no `_bits` array before end of input | `xbm: missing array` |
| a second `_width` define | `xbm: duplicate width define` |
| a second `_height` define | `xbm: duplicate height define` |
| define value `<= 0`, `> 1000000`, or 10+ digits | `xbm: invalid width` / `xbm: invalid height` |
| `#define` without an `<ident>_width`/`<ident>_height` name and 1-9 digit value | `xbm: malformed define` |
| the three base names differ | `xbm: name mismatch` |
| declaration is not `static [unsigned] char <ident>_bits[] = { ... };` (including a missing `;`) | `xbm: malformed array declaration` |
| byte token is not `0x`/`0X` + 1-2 hex digits | `xbm: non-hex byte` |
| missing comma between bytes, or the list does not close with `}` | `xbm: malformed byte list` |
| parsed byte count != `xbm_row_bytes(width) * height` | `xbm: byte count mismatch` |
| non-trivia bytes after the array's `;` | `xbm: trailing tokens` |
| `xbm_pack` width/height `<= 0` or `> 1000000` | `xbm: invalid width` / `xbm: invalid height` |
| `xbm_pack` pixel count != `width * height` | `xbm: pixel buffer size mismatch` |
| `xbm_pack` pixel value above 1 | `xbm: non-binary pixel` |
| `xbm_build` name not a C identifier | `xbm: invalid name` |
| `xbm_build` width/height `<= 0` or `> 1000000` | `xbm: invalid width` / `xbm: invalid height` |
| `xbm_build` `bits` length != `xbm_row_bytes(width) * height` | `xbm: byte count mismatch` |

`xbm_bit` never returns an error string; it uses `-1` (see Semantics).

## Test plan

20 checks in `tests/test_conformance.xi`:

1. canonical 2x2 parse: name, width 2, height 2, byte span 2, all four bits,
   the out-of-range sentinel and `xbm_row_bytes(2)`.
2. comments between every token, `# define`, `unsigned char`, `0X` prefix,
   1-digit hex and a trailing comma.
3. LSB-first pinning (`0x01`/`0x80`), a 3-pixel row with `0xff` padding
   ignored, and independent 8x2 rows.
4. `xbm_pack` pins for 2x2 (0x01, 0x02) and the canonical 2x2 `xbm_build`
   literal.
5. canonical wrapping of a 100x1 image: 13 bytes as 12 + 1 with the line-end
   comma, then parse back.
6. `xbm_pack` boundaries for 1/8/9/16 pixels, size mismatch, non-binary pixel
   and non-positive dimensions.
7. 7x3 non-byte-aligned pack-build-parse round trip with pinned bytes
   (0x2d, 0x76, 0x40), full raster read-back and a byte-exact rebuild.
8. missing width, missing height and missing array.
9. duplicate width and duplicate height defines.
10. zero, oversized and 10-digit dimensions; malformed defines (no suffix,
    empty base, missing value, `#definefoo`).
11. name mismatch (array vs defines, width vs height) and malformed array
    declarations (no `_bits`, sized brackets, no `static`, wrong element type,
    empty base).
12. non-hex bytes (`0x`, `0xg1`, `0x123`, `0xzz`, bare digits), missing comma,
    unterminated list, missing `;`, `{`, `=` and `]`.
13. byte count mismatches: 2x2 with 1 and 3 bytes, empty list, 9x1 with 1 byte.
14. unclosed comments at the start, after a define, inside a define and bare;
    a balanced empty comment is not an error.
15. trailing tokens after `};` (garbage, a define, a second array); trailing
    trivia alone is accepted.
16. `0xFF`, `0X80` and mixed-case `0xaA` read the expected bytes.
17. `xbm_row_bytes` for 0/-3/1/7/8/9/1000000 and the span relation.
18. `xbm_build` name validation, non-positive and oversized dimensions, byte
    count mismatch, and a valid build prefix.
19. height-before-width order, CRLF line endings, `# define` and a trailing
    comma.
20. the exact 1,000,000 width cap is accepted (125,000 bytes, last pixel,
    one-past sentinel) and 1,000,001 is rejected.

## Known limitations

- Only the documented subset is parsed; `//` comments, sized brackets,
  `static const`, other element types, and constructs after the array are
  rejected rather than ignored.
- Dimensions are capped at 1,000,000 per axis and the whole buffer and raster
  are held in memory; there is no streaming and no multi-image support.
- Padding bits are not validated (any value is accepted); `xbm_pack` writes
  zeros, so round trips through `xbm_pack`/`xbm_build` are canonical.
- `xbm_build` always emits `static char`, lowercase hex and 12 bytes per line;
  these choices are the pinned canonical form.
- There is no XPM, no rendering, no file IO, and no conversion to packed
  binary formats; callers move pixels through `xbm_bit` and `xbm_pack`.
