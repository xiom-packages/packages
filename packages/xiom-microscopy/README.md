# xiom.microscopy

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.

Pure XIOM, deterministic, FFI-free microscopy image-set metadata. Everything
is fixed-point integer math: pixel calibration is an `Int` in units of
1e-4 um/px (a value of `1000` means `0.1000` um/px), z positions are physical
nanometres, and there is no floating point anywhere in the module.

## What it provides

- **Tile records** -- five mirrored `Vec[Int]` (row, col, channel, z-slice,
  tick) inside `MicroTileSet`, with validated construction and accessors
  (`mic_tiles_add`, `mic_tile_row`, ...).
- **Grid fill and ordering** -- `mic_grid_fill` appends a complete rectangle
  in row-major order, `mic_grid_fill_zstack` repeats it per z-slice, and
  `mic_tiles_row_major` proves a channel's tiles appear in exactly that order
  (q/r division of the running index by the column count).
- **Grid validation** -- `mic_grid_validate` detects the complete rectangle
  per channel (bounds, duplicates, first missing cell), `mic_grid_slice_validate`
  does the same for one (channel, z) plane, and `mic_grid_missing` returns the
  missing cells as row-major linear indices.
- **Neighbor queries** -- `mic_neighbor(t, i, dir)` resolves the up / down /
  left / right tile of the same channel and z-slice, with catalogued errors at
  edges, gaps and unknown tile indices.
- **Channel metadata** -- `MicroChannels` holds names in a single
  LF-terminated blob plus excitation/emission nanometres and 24-bit color
  codes; `mic_channel_add` validates the A-Z a-z 0-9 _ - name charset, unique
  names, wavelengths and the 64-channel cap.
- **Z-stacks** -- `mic_z_positions_nm` computes start + k*spacing physical
  positions, `mic_z_is_ascending` checks strict order and `mic_z_index_of`
  finds an exact plane.
- **Pixel calibration** -- `mic_calib_validate`, `mic_extent_fp` /
  `mic_extent_nm` (um and nm extents) and `mic_px_for_nm` with exact ceiling
  division for the smallest covering pixel count.
- **Canonical manifest codec** -- `mic_manifest_emit` / `mic_manifest_parse`
  with a strict line grammar, `mic_manifest_validate` and a documented error
  catalog.

## Manifest format

```
#microscopy manifest v1
grid 2 2
calib 0.1000
zspacing 250
channel 405 461 16711935 DAPI
tile 0 0 0 0 0
tile 0 1 0 0 1
tile 1 0 0 0 2
tile 1 1 0 0 3
```

## Tests

```
.\scripts\port.ps1 -Package xiom.microscopy -TimeoutSec 60
```

24 conformance checks cover tile records and guards, row-major fill and
ordering, complete-rectangle and per-plane grid validation, duplicate and
missing detection, neighbor queries, channel metadata and the 64 cap,
z positions and ordering, calibration extents and ceiling pixel counts, and
the manifest codec (exact emit, full/empty round-trip and the error catalog).
See `SPEC.md` for the rules, grammar and catalog.
