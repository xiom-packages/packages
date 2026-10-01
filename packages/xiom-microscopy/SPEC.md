# xiom.microscopy -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.microscopy` (`src/microscopy.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only; the library imports `xiom.string`,
`xiom.string.compare` and `xiom.convert`; the tests additionally use
`xiom.test` and `xiom.io`.

## 1. Scope

A deterministic metadata model for tiled microscopy image sets:

- tile records (row, col, channel, z-slice, tick) as mirrored `Int` tables,
- row-major fill and ordering checks,
- complete-rectangle validation per channel and per (channel, z) plane,
- missing-tile detection and neighbor queries,
- channel metadata (name, excitation/emission nm, 24-bit color),
- z-stack ordering and physical positions in nanometres,
- fixed-point pixel calibration (um/px) and physical extents,
- a canonical line-based text manifest codec with an error catalog.

Everything is integer arithmetic in documented fixed-point units. No
`Float64` value appears anywhere; no `Vec[StructType]`, no methods, no
lambdas, no function tables.

## 2. Non-goals

- No pixel data: the module never reads or stores image samples; it is a
  metadata model and codec.
- No file formats: no TIFF/OME-XML/BigTIFF interop, no binary headers, no
  compression. The only wire format is the canonical text manifest below.
- No optics: no PSF, deconvolution, stitching transforms, registration,
  shading correction, focus metrics or illumination models.
- No float physics: all quantities are integers in documented units; no
  refractive index, wavelength-to-energy conversion or unit parsing.

## 3. Units and constants

| Constant | Value | Meaning |
|---|---|---|
| `MICRO_FP_SCALE` | `10000` | fixed-point scale for um/px: value = real * 10000 |
| `MICRO_FP_MAX` | `1000000000` | largest accepted um/px (100000.0000) |
| `MICRO_DIM_MAX` | `1000` | largest grid dimension (rows or cols) |
| `MICRO_INDEX_MAX` | `1000000` | largest tile field index (channel, z, tick) |
| `MICRO_NM_MAX` | `1000000000000` | largest physical position in nm (1e12) |
| `MICRO_PX_MAX` | `1000000` | largest pixel count on one axis |
| `MICRO_TILE_MAX` | `1000000` | largest total tile count |
| `MICRO_CH_MAX` | `64` | largest channel count |
| `MICRO_COLOR_MAX` | `16777215` | largest 24-bit RGB color (0xFFFFFF) |
| `MICRO_NAME_MAX` | `32` | largest channel-name length in bytes |
| `MICRO_DIR_UP`/`DOWN`/`LEFT`/`RIGHT` | `0`/`1`/`2`/`3` | neighbor direction codes |
| `MICRO_MANIFEST_HEADER` | `#microscopy manifest v1` | first line of the codec |

Unit rules:

- Pixel calibration is stored as an `Int` in 1e-4 um/px (1000 = 0.1000).
- Z positions and spacings are `Int` nanometres (1 fixed-point unit of
  calibration = 0.1 nm, so `px * um_per_px_fp` is the extent in 1e-4 um and
  `px * um_per_px_fp / 10` is the extent in nm).
- Grid coordinates are 0-based; channel and z indices are 0-based.

## 4. Data model

`MicroTileSet` is five parallel `Vec[Int]` (`rows`, `cols`, `channels`,
`zs`, `ticks`) with equal length; entry `i` is one tile. `ticks` is opaque
acquisition metadata and is never interpreted.

`MicroChannels` is a name blob (`names`: one LF-terminated name per channel;
names never contain LF) plus three parallel `Vec[Int]` (`ex_nm`, `em_nm`,
`colors`). A `Vec[Str]` is never used, so `Vec[Str].push` cannot mislower.

`MicroManifest` is the flat interchange record: `grid_rows`, `grid_cols`,
`um_per_px_fp`, `z_spacing_nm`, the channel tables (`ch_names`, `ch_ex_nm`,
`ch_em_nm`, `ch_colors`) and the tile tables (`tile_rows`, `tile_cols`,
`tile_channels`, `tile_zs`, `tile_ticks`).

## 5. Tile rules

### 5.1 Ranges

- tile row, col: 0..999 (`< MICRO_DIM_MAX`);
- tile channel, z, tick: 0..1000000 (`<= MICRO_INDEX_MAX`);
- a tile set holds at most 1000000 tiles.

### 5.2 Row-major fill

`mic_grid_fill(t, rows, cols, channel, z, tick)` appends a complete rectangle
in row-major order:

```
(0,0), (0,1), ..., (0,cols-1), (1,0), ..., (rows-1, cols-1)
```

`mic_grid_fill_zstack(t, rows, cols, channel, z_from, z_count, tick)` appends
`z_count` such rectangles with z = z_from..z_from+z_count-1, one full
rectangle per slice.

### 5.3 Row-major ordering check

`mic_tiles_row_major(t, rows, cols, channel)` walks the tiles of `channel` in
stored order; the k-th such tile must be `(k / cols, k % cols)` (q/r
division) and the count must be exactly `rows*cols`. Tiles of other channels
are ignored.

### 5.4 Complete-rectangle validation

`mic_grid_validate(t, rows, cols, channel)` ignores tiles of other channels
and requires exactly `rows*cols` tiles of `channel`, each cell exactly once.
Checks run per tile in stored order: bounds, then duplicate against earlier
tiles, then (on count mismatch) the first missing cell in row-major order.

`mic_grid_slice_validate(t, rows, cols, channel, z)` applies the same rules
to one (channel, z) plane; a z-stack per channel is valid because each plane
is a complete rectangle. `mic_grid_slice_is_complete` wraps it.

`mic_grid_is_complete` wraps `mic_grid_validate`.

### 5.5 Missing-tile detection

`mic_grid_missing(t, rows, cols, channel)` returns the row-major linear
indices `row*cols + col` of cells with no tile of `channel` (union over z),
in ascending order; an empty vector means every cell has at least one tile.
Duplicates do not affect the result.

### 5.6 Neighbor queries

`mic_neighbor(t, i, dir)` returns the index of the first tile with the same
channel and z-slice at (row-1, col) / (row+1, col) / (row, col-1) /
(row, col+1) for `dir` = up / down / left / right. A missing neighbor
(including at any grid edge) is the error
`micro.neighbor: <dir> neighbor of tile I missing`. Directions are not
grid-aware: the caller chooses the dimensions.

## 6. Channel rules

`mic_channel_add` (and `mic_manifest_add_channel`) validate, in order:

1. channel count < 64;
2. name: 1..32 bytes, each in `A-Z a-z 0-9 _ -` (`\n` is therefore never a
   name byte and the blob format is unambiguous);
3. name uniqueness against the existing blob (linear scan);
4. excitation and emission nm in 1..1e12;
5. color in 0..0xFFFFFF.

A failed add leaves the table unchanged. `mic_channel_index_of` returns the
first index whose name matches; `mic_channel_name` reads line `i` of the
blob.

## 7. Z-stack rules

`mic_z_positions_nm(count, start_nm, spacing_nm)` returns
`start_nm + k*spacing_nm` for k = 0..count-1 (count 1..1000, start
0..1e12, spacing 1..1e12, last position <= 1e12), strictly ascending.
`mic_z_is_ascending` is a strict-increase test (an empty vector is
ascending); `mic_z_index_of` finds an exact position.

## 8. Calibration rules

Let `fp` be um/px in 1e-4 units and `px` a pixel count (0..1e6):

| Function | Result | Rounding |
|---|---|---|
| `mic_extent_fp(px, fp)` | `px * fp` (1e-4 um) | exact, no rounding |
| `mic_extent_nm(px, fp)` | `(px * fp) / 10` (nm) | truncates toward zero |
| `mic_px_for_nm(nm, fp)` | `ceil(nm * 10 / fp)` | q + (r > 0 ? 1 : 0) |

The products are bounded: `px * fp <= 1e15` and `nm * 10 <= 1e13`.
`mic_calib_validate` accepts `fp` in 1..1e9.

## 9. Canonical manifest codec

### 9.1 Grammar

```
manifest  := header LF record*
header    := "#microscopy manifest v1"
record    := grid | calib | zspacing | channel | tile
grid      := "grid" SP uint SP uint            ; rows, cols in 1..1000
calib     := "calib" SP fp                     ; fp = int[.frac{1,4}], 1..1e9
zspacing  := "zspacing" SP uint                ; 0..1e12 nm
channel   := "channel" SP uint SP uint SP uint SP name
                                                ; ex, em in 1..1e12; color <= 0xFFFFFF
tile      := "tile" SP uint SP uint SP uint SP uint SP uint
                                                ; row, col, channel, z, tick
name      := 1..32 bytes of A-Z a-z 0-9 _ -
uint      := digit+                            ; no sign
```

Rules as implemented:

- the first non-blank line must equal the header exactly;
- records appear in the canonical order grid, calib, zspacing, channels,
  tiles; each of grid/calib/zspacing appears exactly once; channel records
  precede tile records;
- leading/trailing spaces and tabs and a CR before LF are ignored; empty
  lines are skipped; the last line need not end with LF;
- tile `row`/`col` must lie inside the declared grid; tile `channel` must
  reference a declared channel; `(row, col, channel, z)` must be unique;
- after parsing, the assembled manifest is checked with
  `mic_manifest_validate`: every (channel, z) plane referenced by a tile must
  be the complete grid rectangle.

`mic_manifest_emit` validates first, then writes the canonical order with
every line LF-terminated (including the last); an empty table after the
header is valid. `mic_manifest_parse` clears `m` first and fills it only on
success; on error the tables stay empty.

### 9.2 Error catalog

Record-line errors are prefixed `micro.codec: line L: ` (L is 1-based over
physical lines):

| Message (suffix after the prefix) | Cause |
|---|---|
| `missing header` | first non-blank line is not the header (or no lines) |
| `unknown record '<kw>'` | keyword is not grid/calib/zspacing/channel/tile |
| `duplicate grid` / `duplicate calib` / `duplicate zspacing` | record repeated |
| `grid must precede channel and tile records` | grid seen after a channel/tile (defensive) |
| `calib must precede channel and tile records` | channel/tile before calib |
| `zspacing must precede channel and tile records` | channel/tile before zspacing |
| `channel must precede tile records` | tile before any channel |
| `expected N fields, got K` | too few tokens |
| `trailing text after N fields` | extra tokens |
| `field F: <value error>` | uint token invalid (`empty value`, `bad value`, `value out of range 0..MAX`) |
| `calib: <value error>` / `calib: um/px out of range 1..1000000000` | fixed-point token |
| `grid rows out of range 1..1000` / `grid cols out of range 1..1000` | zero dimension |
| `channel excitation out of range 1..1000000000000` | ex = 0 |
| `channel emission out of range 1..1000000000000` | em = 0 |
| `channel name: <name error>` | name empty/too long/bad charset |
| `channel: duplicate name NAME` | repeated name |
| `channel: too many channels (max 64)` | 65th channel |
| `tile row R out of range 0..rows-1` / `tile col C ..` / `tile channel C ..` | outside declared grid/channels |
| `duplicate cell row R col C channel CH z Z` | tile cell already present |

End-of-input errors: `micro.codec: missing grid`, `missing calib`,
`missing zspacing`.

Semantic errors from validation keep their own prefixes:

| Prefix | Examples |
|---|---|
| `micro.tiles:` | `row/col out of range 0..999`, `channel/z/tick out of range 0..1000000`, `index I out of range 0..N-1` |
| `micro.grid:` | `rows/cols out of range 1..1000`, `cell count exceeds 1000000`, `tile count would exceed 1000000`, `tile I row/col ... out of range`, `duplicate cell ...`, `missing cell ...` |
| `micro.order:` | `tile K is row R col C, expected row ER col EC`, `channel CH has N tiles, expected M` |
| `micro.neighbor:` | `tile index I out of range 0..N-1`, `direction D out of range 0..3 (0=up,1=down,2=left,3=right)`, `<dir> neighbor of tile I missing` |
| `micro.channels:` | name/duplicate/range errors, `index I out of range 0..N-1`, `no channel named NAME`, table mismatches |
| `micro.z:` | count/start/spacing/last-position ranges, `no z slices`, `position Z not found among N slices` |
| `micro.calib:` | `um/px out of range 1..1000000000`, `pixel count out of range 0..1000000`, `length out of range 0..1000000000000` |
| `micro.manifest:` | grid/calib/zspacing ranges, tile table length mismatches, tile bounds/channel/duplicate, `channel index I out of range 0..N-1` |

## 10. Test plan

Suite: `tests/test_conformance.xi`, module `microscopy_tests`, 24 checks run
explicitly from `main` (no `Vec[fn]` dispatch). Exit code is the number of
failed checks, so a green run exits 0.

| Check | Proves |
|---|---|
| `t01` | tile set construction and every field accessor (plus index errors) |
| `t02` | tile add range guards for row/col/channel/z/tick leave the set empty |
| `t03` | `mic_grid_fill` 2x3 produces exactly the row-major sequence |
| `t04` | `mic_grid_count` bounds (0/1001), 1000x1000 = 1000000, fill guards and capacity |
| `t05` | row-major check passes a fill, rejects a swap and a partial grid |
| `t06` | complete 2x3 validates; one missing cell is located; is_complete agrees |
| `t07` | duplicate cell reported before the count check |
| `t08` | tiles of other channels are ignored; a foreign out-of-range tile is caught per channel |
| `t09` | missing list 3x3 = [1, 8] for (0,1) and (2,2); complete grid = [] |
| `t10` | neighbour centre/corner lookups, edges, gap and wrong-channel misses |
| `t11` | grid count pinned values |
| `t12` | channel add/read DAPI+GFP, name lookup, index/name errors |
| `t13` | channel guards: empty/long/bad name, duplicate, ranges, 64 cap |
| `t14` | z positions start+k*spacing, single slice, all range guards |
| `t15` | z ascending/strict, exact index, not-found, empty |
| `t16` | calibration guards and extents (1000 px @ 0.1000 = 100 um = 100000 nm) |
| `t17` | ceiling pixel counts 100->1, 101->2, 250->3, 0->0, plus guards |
| `t18` | manifest new/add channel+tile, duplicate and range guards |
| `t19` | exact canonical emit text and header constant |
| `t20` | full and empty manifest emit->parse->emit identity, field-by-field |
| `t21` | codec structure errors: header, unknown, duplicates, ordering, missing |
| `t22` | codec value errors: calib, names, duplicates, bounds, incomplete grid |
| `t23` | manifest validate: empty grid, channel-less tile, table/grid bounds |
| `t24` | 3x3 two-channel two-slice integration: fill, slice validation, neighbours, codec |

## 11. Verification

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.microscopy -TimeoutSec 60
```

Green iff the tail is
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)` and the suite prints
`xiom.microscopy: all tests passed`.
