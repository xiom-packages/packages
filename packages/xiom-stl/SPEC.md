<!-- XIOM -- xiom.stl SPEC -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.stl SPEC

## Scope

Pure-XIOM parsing of the binary STL structure: kind classification (binary vs ASCII), the declared triangle count, and raw access to every normal/vertex component and attribute value. IEEE-754 f32 fields are exposed as their little-endian u32 bit patterns; no float interpretation happens in this package.

## Non-goals

ASCII geometry parsing, vertex dedup, normal validation/normalization, units, colors, material names, colored/`SOLID` extensions, and any float decoding (see `README.md` limitations).

## Binary layout

| Offset | Size | Field |
|--------|------|-------|
| `0` | 80 | Header bytes (opaque; not interpreted) |
| `80` | 4 | Triangle count `n`, little-endian u32 |
| `84 + 50*i` | 12 | Normal: 3 x little-endian f32 (x, y, z) |
| `96 + 50*i` | 36 | Vertex 0..2: 3 x (x, y, z) little-endian f32 |
| `132 + 50*i` | 2 | Attribute byte count, little-endian u16 |

- `i` is the zero-based triangle index, `0 <= i < n`.
- Total size is `84 + 50*n` bytes (`stl_binary_size`).
- All multi-byte fields are little-endian; every read assembles bytes arithmetically (`b0 + b1*256 + ...`) with `& 0xFF` masking.

## API

```xiom
pub fn stl_kind(data: &Vec[UInt8]) -> Int
pub fn stl_triangle_count(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn stl_float_bits(data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
pub fn stl_normal_bits(data: &Vec[UInt8], tri: Int, axis: Int) -> Result[Int, Str]
pub fn stl_vertex_bits(data: &Vec[UInt8], tri: Int, vertex: Int, axis: Int) -> Result[Int, Str]
pub fn stl_attribute(data: &Vec[UInt8], tri: Int) -> Result[Int, Str]
pub fn stl_binary_size(triangles: Int) -> Int
```

## Kind heuristic

`stl_kind` evaluates in this order:

1. **Binary (1)** when `len >= 84` and `len == 84 + LE_u32(80) * 50` exactly. This check wins even if the header starts with `solid`.
2. **ASCII (2)** when the buffer starts with optional ASCII whitespace (space `0x20`, TAB `0x09`, LF `0x0A`, CR `0x0D`) followed by the bytes `solid`.
3. **Unknown/short (0)** otherwise. An empty buffer is `0`; the 5-byte word `solid` alone is `2`.

The heuristic is size-based; it does not validate that the 80-byte header is non-ASCII.

## Semantics

- `stl_triangle_count` requires the exact binary size: shorter buffers yield `truncated triangle data`, longer ones `trailing bytes`. It accepts a zero-triangle (84-byte) file.
- `stl_float_bits` accepts any non-negative absolute offset with at least 4 bytes remaining, aligned or not.
- Component reads validate in order: triangle -> vertex -> axis.
- Negative input counts to `stl_binary_size` return `0` (documented sentinel, not an error).

## Error catalog

| Function | Condition | Message |
|---|---|---|
| `stl_triangle_count` | `len < 84` | `stl: truncated header` |
| `stl_triangle_count` | declared count needs more than `len` bytes | `stl: truncated triangle data` |
| `stl_triangle_count` | declared count needs fewer than `len` bytes | `stl: trailing bytes` |
| `stl_float_bits` | `offset < 0` or `offset + 4 > len` | `stl: offset out of range` |
| `stl_normal_bits`, `stl_vertex_bits`, `stl_attribute` | triangle count read fails | propagated (see above) |
| `stl_normal_bits`, `stl_vertex_bits`, `stl_attribute` | `tri < 0` or `tri >= n` | `stl: triangle out of range` |
| `stl_vertex_bits` | `vertex` not in 0..2 | `stl: vertex out of range` |
| `stl_normal_bits`, `stl_vertex_bits` | `axis` not in 0..2 | `stl: axis out of range` |

## Test plan

17 checks (`tests/test_conformance.xi`):

1. one- and zero-triangle fixtures: `stl_kind` and counts, sizes 134/84;
2. `stl_float_bits` at absolute offsets 0, 80, 84, 88, 92, 128;
3. `stl_float_bits` offset bounds, including a non-aligned final word (`0x12344110`);
4. normal bits pinned per axis on the 1-triangle fixture;
5. all nine vertex components pinned;
6. attributes `0x1234`, `1`, `0xFFFF`;
7. two-triangle fixture with NaN, +inf, -inf, -0.0, denormal and 1.2f bit patterns;
8. ASCII detection: `solid test`, leading whitespace, non-solid text rejected, count Err;
9. 100-byte `solid` ASCII file: kind 2 and `truncated triangle data`;
10. size mismatches both directions: kind 0, `trailing bytes` / `truncated triangle data`;
11. 133-byte truncated triangle: kind 0, `truncated triangle data`;
12. empty and 83-byte buffers: kind 0, `truncated header`; short `solid` is kind 2;
13. triangle index out of range (`1`, `-1`) for all three accessors;
14. axis out of range (3, -1);
15. vertex out of range (3, -1);
16. `stl_binary_size` for 0, 1, 2, 10, 100 and -1;
17. precedence: a `solid`-prefixed buffer of exact binary size is kind 1.

## Known limitations

- Raw bits only: no f32 decode helper (`Vec[Float64]` and f32 bitcasts are unavailable in v0.61.3).
- ASCII files are detected, never parsed.
- No vertex dedup/normalization; repeated vertices are returned as stored.
- The 80-byte header is opaque; title strings are not surfaced.
