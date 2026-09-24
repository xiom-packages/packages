<!-- XIOM -- xiom.stl README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.stl

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (17/17); NOT published yet.
> **Scope:** Binary STL structure parsing: kind classification, triangle counts, and raw normal/vertex/attribute access. ASCII files are detected only (no geometry parsing).
> **Deps:** `xiom.std` only. No FFI in v0.1.

## API

| Function | Description |
|----------|-------------|
| `stl_kind(data)` | `1` binary (length exactly `84 + 50*n`), `2` ASCII (optional whitespace then `solid`), `0` unknown/short. Binary wins when the size matches. |
| `stl_triangle_count(data)` | Declared LE u32 triangle count; requires the buffer to be exactly `84 + 50*n` bytes |
| `stl_float_bits(data, offset)` | LE u32 at an absolute offset, returned as the raw IEEE-754 bit pattern (`0..2^32-1`) |
| `stl_normal_bits(data, tri, axis)` | Raw bits of the normal component (`axis`: 0 = x, 1 = y, 2 = z) |
| `stl_vertex_bits(data, tri, vertex, axis)` | Raw bits of vertex `vertex` (0..2), component `axis` (0..2) |
| `stl_attribute(data, tri)` | Trailing LE u16 attribute byte count (`0..65535`) |
| `stl_binary_size(triangles)` | Exact binary size `84 + 50*n`; negative counts return `0` |

Errors are `Result[Int, Str]` with `stl: `-prefixed messages (see SPEC.md for the catalog).

## Binary layout

| Offset | Size | Field |
|--------|------|-------|
| `0` | 80 | Header (free-form; not interpreted) |
| `80` | 4 | Triangle count, little-endian u32 |
| `84 + 50*i` | 12 | Normal: x, y, z as little-endian f32 |
| `96 + 50*i` | 36 | Vertices 0..2, each x, y, z as little-endian f32 |
| `132 + 50*i` | 2 | Attribute byte count, little-endian u16 |

Each triangle is 50 bytes; a file is exactly `84 + 50*n` bytes.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.stl
```

17 conformance tests build fixtures with pinned bit patterns (`1.0f = 0x3F800000`, plus NaN, +/-inf, -0.0, a denormal and `1.2f`), cover every accessor and error class, exercise ASCII detection with leading whitespace, and pin the binary-wins precedence rule.

## Limitations

- Values are raw IEEE-754 bits: decoding to floats is caller-side.
- ASCII geometry parsing is not provided; `stl_kind` reports ASCII but no ASCII reader exists in v0.1.
- No vertex dedup, no normal normalization, no units interpretation.
- The 80-byte header is not interpreted (real-world writers may store a title there).
