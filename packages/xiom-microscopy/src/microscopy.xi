// XIOM -- xiom.microscopy: pure deterministic microscopy image-set metadata
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md carries the rules, rounding conventions, codec grammar and
// the full error catalog):
//   * fixed-point integers only, scale 1e-4 (MICRO_FP_SCALE = 10000): pixel
//     calibration (um/px) is an Int in those units. There is no Float64 and
//     no Vec[Float64];
//   * tile records are five mirrored Vec[Int] (rows, cols, channels, zs,
//     ticks) inside MicroTileSet; channel records are one LF-terminated name
//     per line in a single Str (never a Vec[Str]) plus three mirrored
//     Vec[Int] (excitation nm, emission nm, 24-bit color) inside
//     MicroChannels. There is no Vec[StructType];
//   * a MicroManifest is the flat interchange record of the canonical text
//     codec: grid dimensions, calibration, z spacing and the channel/tile
//     tables (grammar in SPEC.md section 8);
//   * z positions are physical nanometres; pixel extents are computed from
//     the calibration with truncating division and exact ceiling division;
//   * grid completeness is rectangle detection per (channel, z) plane: every
//     cell of a rows x cols grid must appear exactly once in that plane
//     (mic_grid_validate checks the union over z of one channel;
//     mic_grid_slice_validate checks one plane).
//
// v0.62.2 notes that shaped this module:
//   * free functions only: no methods, lambdas, fn tables or Vec[StructType];
//   * Ok/Err are constructed only in the tiny leaf helpers `_ok_*` / `_err_*`
//     below;
//   * every Str comparison goes through xiom.string.compare.str_compare; a Str
//     is never compared with `==` (BUG 17);
//   * every byte read is widened with `(string.byte_at(s, pos) as Int) & 0xFF`;
//   * `Vec[Str].push` is never used: channel names live in one newline
//     terminated blob and the parser scans line ranges in place;
//   * every Vec element read is bound to a typed local before use;
//   * every written Vec parameter is an explicit `&mut`;
//   * no `&mut Int` parameters: scalar updates flow through return values;
//   * division truncates toward zero; ceiling division is q + (r > 0 ? 1 : 0)
//     (never (a + b - 1) / b);
//   * products are guarded by documented input bounds (MICRO_NM_MAX,
//     MICRO_FP_MAX, MICRO_INDEX_MAX), so no Int multiplication overflows.

module xiom.microscopy

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Fixed-point scale for pixel calibration: um/px values are stored as Ints
/// in units of 1e-4 um/px (1000 means 0.1000 um/px).
pub const MICRO_FP_SCALE: Int = 10000;

/// Largest accepted fixed-point calibration value (100000.0000 um/px).
pub const MICRO_FP_MAX: Int = 1000000000;

/// Largest accepted grid dimension (rows or columns).
pub const MICRO_DIM_MAX: Int = 1000;

/// Largest accepted tile field index (channel, z-slice or tick).
pub const MICRO_INDEX_MAX: Int = 1000000;

/// Largest accepted physical position in nanometres (1e12 nm = 1000 m).
pub const MICRO_NM_MAX: Int = 1000000000000;

/// Largest accepted pixel count on one axis.
pub const MICRO_PX_MAX: Int = 1000000;

/// Largest accepted total tile count of a grid or manifest.
pub const MICRO_TILE_MAX: Int = 1000000;

/// Largest accepted channel count of a channel table or manifest.
pub const MICRO_CH_MAX: Int = 64;

/// Largest accepted 24-bit RGB color code (0xFFFFFF).
pub const MICRO_COLOR_MAX: Int = 16777215;

/// Largest accepted channel-name length in bytes.
pub const MICRO_NAME_MAX: Int = 32;

/// Neighbor direction: one row up (row - 1).
pub const MICRO_DIR_UP: Int = 0;

/// Neighbor direction: one row down (row + 1).
pub const MICRO_DIR_DOWN: Int = 1;

/// Neighbor direction: one column left (col - 1).
pub const MICRO_DIR_LEFT: Int = 2;

/// Neighbor direction: one column right (col + 1).
pub const MICRO_DIR_RIGHT: Int = 3;

/// Exact first non-blank line of the canonical manifest text codec.
pub const MICRO_MANIFEST_HEADER: Str = "#microscopy manifest v1";

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Mirrored tile table: five parallel Vec[Int] with equal length, one entry
/// per tile. rows/cols are 0-based grid coordinates, channels is a 0-based
/// channel-table index, zs is a 0-based z-slice index and ticks is opaque
/// acquisition metadata. Fields are implementation details; use the
/// mic_tiles_* / mic_tile_* / mic_grid_* free functions.
pub type MicroTileSet = {
  rows: Vec[Int];
  cols: Vec[Int];
  channels: Vec[Int];
  zs: Vec[Int];
  ticks: Vec[Int];
}

/// Channel table: one name per LF-terminated line in `names` (names never
/// contain LF), plus mirrored excitation/emission wavelengths in nanometres
/// and 24-bit color codes. Fields are implementation details; use the
/// mic_channel_* free functions.
pub type MicroChannels = {
  names: Str;
  ex_nm: Vec[Int];
  em_nm: Vec[Int];
  colors: Vec[Int];
}

/// Flat interchange record of the canonical manifest codec: grid dimensions,
/// pixel calibration in fixed point, z spacing in nanometres, channel tables
/// (name blob plus mirrored Int vectors) and mirrored tile tables. Fields are
/// readable by callers; mutation goes through mic_manifest_add_channel /
/// mic_manifest_add_tile.
pub type MicroManifest = {
  grid_rows: Int;
  grid_cols: Int;
  um_per_px_fp: Int;
  z_spacing_nm: Int;
  ch_names: Str;
  ch_ex_nm: Vec[Int];
  ch_em_nm: Vec[Int];
  ch_colors: Vec[Int];
  tile_rows: Vec[Int];
  tile_cols: Vec[Int];
  tile_channels: Vec[Int];
  tile_zs: Vec[Int];
  tile_ticks: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_vec_int(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_vec_int(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[MicroManifest, Str].
fn _ok_manifest(v: MicroManifest) -> Result[MicroManifest, Str] {
  return Ok(v);
}

// Err(m) for Result[MicroManifest, Str].
fn _err_manifest(m: Str) -> Result[MicroManifest, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Byte `pos` of `s` widened to 0..255 (0 when out of bounds).
fn _m_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// First position at or after `from` in [from, to) that is not a space or tab.
fn _m_skip_ws(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    let b: Int = _m_byte(s, i);
    if b == 32 || b == 9 {
      i = i + 1;
    } else {
      break;
    }
  }
  return i;
}

// First position at or after `from` in [from, to) that is a space or tab, or
// `to` when the token runs to the end of the range.
fn _m_token_end(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    let b: Int = _m_byte(s, i);
    if b == 32 || b == 9 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// True when s[from, to) equals `want` (BUG 17 discipline: str_compare).
fn _m_range_equals(s: Str, from: Int, to: Int, want: Str) -> Bool {
  return compare.str_compare(string.str_slice(s, from, to), want) == 0;
}

// Parse one unsigned decimal token (digit+, no sign, no dot) into 0..max.
// Errors: "empty value" | "bad value" | "value out of range 0..MAX".
// The running value never exceeds 10*max+9, so no overflow occurs.
fn _m_parse_uint(tok: Str, max: Int) -> Result[Int, Str] {
  let n = tok.len();
  if n == 0 {
    return _err_int("empty value");
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b: Int = _m_byte(tok, i);
    if b < 48 || b > 57 {
      return _err_int("bad value");
    }
    v = v * 10 + (b - 48);
    if v > max {
      return _err_int("value out of range 0.." + convert.int_to_string(max));
    }
    i = i + 1;
  }
  return _ok_int(v);
}

// Parse one fixed-point token: ["-"] digit+ ["." digit{1,4}], exact decimal,
// no float: value = int_part*10000 + frac_padded.
// Errors: "empty value" | "bad value" | "more than 4 decimal places" |
// "value out of range 0..1000000000".
fn _m_parse_fp(tok: Str) -> Result[Int, Str] {
  let n = tok.len();
  if n == 0 {
    return _err_int("empty value");
  }
  var i = 0;
  var neg = false;
  let b0: Int = _m_byte(tok, 0);
  if b0 == 45 {
    neg = true;
    i = 1;
  }
  var ip = 0;
  var idig = 0;
  while i < n {
    let b: Int = _m_byte(tok, i);
    if b < 48 || b > 57 {
      break;
    }
    ip = ip * 10 + (b - 48);
    if ip > 1000000 {
      return _err_int("value out of range 0..1000000000");
    }
    idig = idig + 1;
    i = i + 1;
  }
  if idig == 0 {
    return _err_int("bad value");
  }
  var frac = 0;
  var fdig = 0;
  if i < n {
    let bdot: Int = _m_byte(tok, i);
    if bdot != 46 {
      return _err_int("bad value");
    }
    i = i + 1;
    while i < n {
      let b2: Int = _m_byte(tok, i);
      if b2 < 48 || b2 > 57 {
        return _err_int("bad value");
      }
      if fdig == 4 {
        return _err_int("more than 4 decimal places");
      }
      frac = frac * 10 + (b2 - 48);
      fdig = fdig + 1;
      i = i + 1;
    }
    if fdig == 0 {
      return _err_int("bad value");
    }
    while fdig < 4 {
      frac = frac * 10;
      fdig = fdig + 1;
    }
  }
  var v = ip * MICRO_FP_SCALE + frac;
  if v > MICRO_FP_MAX {
    return _err_int("value out of range 0..1000000000");
  }
  if neg {
    v = 0 - v;
  }
  return _ok_int(v);
}

// Canonical fixed-point text for a non-negative value: int part, dot, exactly
// four fraction digits (zero padded); e.g. 1000 -> "0.1000", 12345 ->
// "1.2345".
fn _m_emit_fp(v: Int) -> Str {
  let ip = v / MICRO_FP_SCALE;
  let fr = v % MICRO_FP_SCALE;
  return convert.int_to_string(ip) + "." + _m_pad4(fr);
}

// Decimal digits of n (0..9999) zero padded to exactly four characters.
fn _m_pad4(n: Int) -> Str {
  if n < 10 {
    return "000" + convert.int_to_string(n);
  }
  if n < 100 {
    return "00" + convert.int_to_string(n);
  }
  if n < 1000 {
    return "0" + convert.int_to_string(n);
  }
  return convert.int_to_string(n);
}

// Name of a neighbor direction code (unknown codes return "unknown").
fn _m_dir_name(d: Int) -> Str {
  if d == MICRO_DIR_UP {
    return "up";
  }
  if d == MICRO_DIR_DOWN {
    return "down";
  }
  if d == MICRO_DIR_LEFT {
    return "left";
  }
  if d == MICRO_DIR_RIGHT {
    return "right";
  }
  return "unknown";
}

// LF-terminated line `index` of the name blob ("" when absent).
fn _m_blob_line(blob: Str, index: Int) -> Str {
  if index < 0 {
    return "";
  }
  let n = blob.len();
  var pos = 0;
  var line = 0;
  var start = 0;
  while pos <= n {
    var end_line = pos == n;
    if !end_line {
      if _m_byte(blob, pos) == 10 {
        end_line = true;
      }
    }
    if end_line {
      if line == index {
        return string.str_slice(blob, start, pos);
      }
      line = line + 1;
      start = pos + 1;
    }
    pos = pos + 1;
  }
  return "";
}

// Number of LF bytes in the name blob (one per stored name).
fn _m_blob_line_count(blob: Str) -> Int {
  let n = blob.len();
  var count = 0;
  var i = 0;
  while i < n {
    if _m_byte(blob, i) == 10 {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// True when some LF-terminated line of the blob equals `name`.
fn _m_blob_has_line(blob: Str, name: Str) -> Bool {
  let n = blob.len();
  var pos = 0;
  var start = 0;
  while pos <= n {
    var end_line = pos == n;
    if !end_line {
      if _m_byte(blob, pos) == 10 {
        end_line = true;
      }
    }
    if end_line {
      if _m_range_equals(blob, start, pos, name) {
        return true;
      }
      start = pos + 1;
    }
    pos = pos + 1;
  }
  return false;
}

// Validate one channel name: 1..MICRO_NAME_MAX bytes, each in
// A-Z a-z 0-9 _ -.
// Errors: "name must not be empty" | "name longer than 32 characters" |
// "name has a character outside A-Z a-z 0-9 _ -".
fn _m_name_ok(name: Str) -> Result[Unit, Str] {
  let n = name.len();
  if n == 0 {
    return _err_unit("name must not be empty");
  }
  if n > MICRO_NAME_MAX {
    return _err_unit("name longer than 32 characters");
  }
  var i = 0;
  while i < n {
    let b: Int = _m_byte(name, i);
    var ok = false;
    if b >= 65 && b <= 90 {
      ok = true;
    }
    if b >= 97 && b <= 122 {
      ok = true;
    }
    if b >= 48 && b <= 57 {
      ok = true;
    }
    if b == 95 || b == 45 {
      ok = true;
    }
    if !ok {
      return _err_unit("name has a character outside A-Z a-z 0-9 _ -");
    }
    i = i + 1;
  }
  return _ok_unit();
}

// First index at or after `from` with rows[i] == r, cols[i] == c and
// channels[i] == channel; -1 when no such cell exists.
fn _m_find_cell(t: &MicroTileSet, r: Int, c: Int, channel: Int, from: Int) -> Int {
  let n = t.rows.len();
  var i = from;
  while i < n {
    let ch: Int = t.channels[i];
    if ch == channel {
      let rr: Int = t.rows[i];
      let cc: Int = t.cols[i];
      if rr == r && cc == c {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when cell (r, c) of `channel` exists in the tile set.
fn _m_has_cell(t: &MicroTileSet, r: Int, c: Int, channel: Int) -> Bool {
  return _m_find_cell(t, r, c, channel, 0) >= 0;
}

// True when cell (r, c) of the (channel, z) plane exists in the tile set.
fn _m_has_cell_z(t: &MicroTileSet, r: Int, c: Int, channel: Int, z: Int) -> Bool {
  let n = t.rows.len();
  var i = 0;
  while i < n {
    let ch: Int = t.channels[i];
    let zz: Int = t.zs[i];
    if ch == channel && zz == z {
      let rr: Int = t.rows[i];
      let cc: Int = t.cols[i];
      if rr == r && cc == c {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

// Number of tiles of `channel` in the tile set.
fn _m_count_channel(t: &MicroTileSet, channel: Int) -> Int {
  let n = t.rows.len();
  var count = 0;
  var i = 0;
  while i < n {
    let ch: Int = t.channels[i];
    if ch == channel {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// Validate a channel table given as a name blob plus three parallel Int
// vectors. Emits the micro.channels: catalog (see SPEC.md section 7).
fn _m_channels_validate(n: Int, names: Str, ex: &Vec[Int], em: &Vec[Int],
                        colors: &Vec[Int]) -> Result[Unit, Str] {
  if n > MICRO_CH_MAX {
    return _err_unit("micro.channels: too many channels (max 64)");
  }
  if em.len() != n {
    return _err_unit("micro.channels: table length mismatch excitation=" +
                     convert.int_to_string(n) + " emission=" + convert.int_to_string(em.len()));
  }
  if colors.len() != n {
    return _err_unit("micro.channels: table length mismatch excitation=" +
                     convert.int_to_string(n) + " colors=" + convert.int_to_string(colors.len()));
  }
  if _m_blob_line_count(names) != n {
    return _err_unit("micro.channels: name table has " +
                     convert.int_to_string(_m_blob_line_count(names)) +
                     " names, expected " + convert.int_to_string(n));
  }
  var i = 0;
  while i < n {
    let exv: Int = ex[i];
    let emv: Int = em[i];
    let colv: Int = colors[i];
    if exv < 1 || exv > MICRO_NM_MAX {
      return _err_unit("micro.channels: channel " + convert.int_to_string(i) +
                       " excitation out of range 1..1000000000000");
    }
    if emv < 1 || emv > MICRO_NM_MAX {
      return _err_unit("micro.channels: channel " + convert.int_to_string(i) +
                       " emission out of range 1..1000000000000");
    }
    if colv < 0 || colv > MICRO_COLOR_MAX {
      return _err_unit("micro.channels: channel " + convert.int_to_string(i) +
                       " color out of range 0..16777215");
    }
    let name = _m_blob_line(names, i);
    let nr = _m_name_ok(name);
    if !nr.is_ok {
      return _err_unit("micro.channels: channel " + convert.int_to_string(i) +
                       " name: " + nr.error);
    }
    var j = 0;
    while j < i {
      let prev = _m_blob_line(names, j);
      if compare.str_compare(prev, name) == 0 {
        return _err_unit("micro.channels: duplicate name " + name);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Tile set: construction, accessors and validation
// --------------------------------------------------

/// Create an empty tile set.
/// Complexity: O(1).
pub fn mic_tiles_new() -> MicroTileSet {
  return MicroTileSet{
    rows: Vec[Int].new();
    cols: Vec[Int].new();
    channels: Vec[Int].new();
    zs: Vec[Int].new();
    ticks: Vec[Int].new();
  };
}

/// Number of tiles in the set.
/// Errors: none (total).
/// Complexity: O(1).
pub fn mic_tiles_len(t: &MicroTileSet) -> Int {
  return t.rows.len();
}

/// Append one tile record (row, col, channel, z, tick) to the mirrored
/// tables. row and col must lie in 0..MICRO_DIM_MAX-1; channel, z and tick
/// must lie in 0..MICRO_INDEX_MAX; the set may hold at most MICRO_TILE_MAX
/// tiles.
///
/// Errors: "micro.tiles: row out of range 0..999",
/// "micro.tiles: col out of range 0..999",
/// "micro.tiles: channel out of range 0..1000000",
/// "micro.tiles: z out of range 0..1000000",
/// "micro.tiles: tick out of range 0..1000000",
/// "micro.tiles: tile count would exceed 1000000".
/// Complexity: O(1) amortized.
pub fn mic_tiles_add(t: &mut MicroTileSet, row: Int, col: Int, channel: Int,
                     z: Int, tick: Int) -> Result[Unit, Str] {
  if row < 0 || row >= MICRO_DIM_MAX {
    return _err_unit("micro.tiles: row out of range 0..999");
  }
  if col < 0 || col >= MICRO_DIM_MAX {
    return _err_unit("micro.tiles: col out of range 0..999");
  }
  if channel < 0 || channel > MICRO_INDEX_MAX {
    return _err_unit("micro.tiles: channel out of range 0..1000000");
  }
  if z < 0 || z > MICRO_INDEX_MAX {
    return _err_unit("micro.tiles: z out of range 0..1000000");
  }
  if tick < 0 || tick > MICRO_INDEX_MAX {
    return _err_unit("micro.tiles: tick out of range 0..1000000");
  }
  if t.rows.len() >= MICRO_TILE_MAX {
    return _err_unit("micro.tiles: tile count would exceed 1000000");
  }
  t.rows.push(row);
  t.cols.push(col);
  t.channels.push(channel);
  t.zs.push(z);
  t.ticks.push(tick);
  return _ok_unit();
}

// Field `which` of tile `i`: 0 = row, 1 = col, 2 = channel, 3 = z, 4 = tick.
fn _m_tile_field(t: &MicroTileSet, i: Int, which: Int) -> Result[Int, Str] {
  if i < 0 || i >= t.rows.len() {
    return _err_int("micro.tiles: index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(t.rows.len() - 1));
  }
  if which == 0 {
    let v: Int = t.rows[i];
    return _ok_int(v);
  }
  if which == 1 {
    let v: Int = t.cols[i];
    return _ok_int(v);
  }
  if which == 2 {
    let v: Int = t.channels[i];
    return _ok_int(v);
  }
  if which == 3 {
    let v: Int = t.zs[i];
    return _ok_int(v);
  }
  if which == 4 {
    let v: Int = t.ticks[i];
    return _ok_int(v);
  }
  return _err_int("micro.tiles: unknown field code " + convert.int_to_string(which));
}

/// Row of tile `i`.
/// Errors: "micro.tiles: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_tile_row(t: &MicroTileSet, i: Int) -> Result[Int, Str] {
  return _m_tile_field(t, i, 0);
}

/// Column of tile `i`.
/// Errors: "micro.tiles: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_tile_col(t: &MicroTileSet, i: Int) -> Result[Int, Str] {
  return _m_tile_field(t, i, 1);
}

/// Channel index of tile `i`.
/// Errors: "micro.tiles: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_tile_channel(t: &MicroTileSet, i: Int) -> Result[Int, Str] {
  return _m_tile_field(t, i, 2);
}

/// Z-slice index of tile `i`.
/// Errors: "micro.tiles: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_tile_z(t: &MicroTileSet, i: Int) -> Result[Int, Str] {
  return _m_tile_field(t, i, 3);
}

/// Tick metadata of tile `i`.
/// Errors: "micro.tiles: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_tile_tick(t: &MicroTileSet, i: Int) -> Result[Int, Str] {
  return _m_tile_field(t, i, 4);
}

/// Cell count of a rows x cols grid (rows*cols, up to MICRO_TILE_MAX).
/// Errors: "micro.grid: rows out of range 1..1000",
/// "micro.grid: cols out of range 1..1000",
/// "micro.grid: cell count exceeds 1000000".
/// Complexity: O(1).
pub fn mic_grid_count(rows_n: Int, cols_n: Int) -> Result[Int, Str] {
  if rows_n < 1 || rows_n > MICRO_DIM_MAX {
    return _err_int("micro.grid: rows out of range 1..1000");
  }
  if cols_n < 1 || cols_n > MICRO_DIM_MAX {
    return _err_int("micro.grid: cols out of range 1..1000");
  }
  if rows_n * cols_n > MICRO_TILE_MAX {
    return _err_int("micro.grid: cell count exceeds 1000000");
  }
  return _ok_int(rows_n * cols_n);
}

/// Append a complete rows_n x cols_n rectangle for `channel` at z-slice `z`
/// in row-major order: (0,0), (0,1), ..., (0,cols-1), (1,0), ... Each tile
/// carries the same `z` and `tick`. New tiles are appended after existing
/// ones.
///
/// Errors: the mic_grid_count dimension messages, then
/// "micro.grid: channel out of range 0..1000000",
/// "micro.grid: z out of range 0..1000000",
/// "micro.grid: tick out of range 0..1000000",
/// "micro.grid: tile count would exceed 1000000".
/// Complexity: O(rows*cols).
pub fn mic_grid_fill(t: &mut MicroTileSet, rows_n: Int, cols_n: Int, channel: Int,
                     z: Int, tick: Int) -> Result[Unit, Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  let cells: Int = cr.value;
  if channel < 0 || channel > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: channel out of range 0..1000000");
  }
  if z < 0 || z > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: z out of range 0..1000000");
  }
  if tick < 0 || tick > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: tick out of range 0..1000000");
  }
  if t.rows.len() + cells > MICRO_TILE_MAX {
    return _err_unit("micro.grid: tile count would exceed 1000000");
  }
  var r = 0;
  while r < rows_n {
    var c = 0;
    while c < cols_n {
      t.rows.push(r);
      t.cols.push(c);
      t.channels.push(channel);
      t.zs.push(z);
      t.ticks.push(tick);
      c = c + 1;
    }
    r = r + 1;
  }
  return _ok_unit();
}

/// Append a z-stack of `z_count` complete rows_n x cols_n rectangles for
/// `channel`, z-slices z_from..z_from+z_count-1, each in row-major order.
///
/// Errors: the mic_grid_count dimension messages, then
/// "micro.grid: channel out of range 0..1000000",
/// "micro.grid: z from out of range 0..1000000",
/// "micro.grid: z count out of range 1..1000",
/// "micro.grid: z range ends above 1000000",
/// "micro.grid: tick out of range 0..1000000",
/// "micro.grid: tile count would exceed 1000000".
/// Complexity: O(rows*cols*z_count).
pub fn mic_grid_fill_zstack(t: &mut MicroTileSet, rows_n: Int, cols_n: Int,
                            channel: Int, z_from: Int, z_count: Int,
                            tick: Int) -> Result[Unit, Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  let cells: Int = cr.value;
  if channel < 0 || channel > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: channel out of range 0..1000000");
  }
  if z_from < 0 || z_from > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: z from out of range 0..1000000");
  }
  if z_count < 1 || z_count > MICRO_DIM_MAX {
    return _err_unit("micro.grid: z count out of range 1..1000");
  }
  if z_from + z_count - 1 > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: z range ends above 1000000");
  }
  if tick < 0 || tick > MICRO_INDEX_MAX {
    return _err_unit("micro.grid: tick out of range 0..1000000");
  }
  if t.rows.len() + cells * z_count > MICRO_TILE_MAX {
    return _err_unit("micro.grid: tile count would exceed 1000000");
  }
  var zi = 0;
  while zi < z_count {
    var r = 0;
    while r < rows_n {
      var c = 0;
      while c < cols_n {
        t.rows.push(r);
        t.cols.push(c);
        t.channels.push(channel);
        t.zs.push(z_from + zi);
        t.ticks.push(tick);
        c = c + 1;
      }
      r = r + 1;
    }
    zi = zi + 1;
  }
  return _ok_unit();
}

/// Validate that the tiles of `channel` form the complete rows_n x cols_n
/// rectangle: exactly rows_n*cols_n tiles, every cell in 0..rows_n-1 x
/// 0..cols_n-1 appears exactly once, and no duplicate cell exists (tiles of
/// other channels are ignored).
///
/// Errors: the mic_grid_count dimension messages, then
/// "micro.grid: tile I row R out of range 0..rows_n-1",
/// "micro.grid: tile I col C out of range 0..cols_n-1",
/// "micro.grid: duplicate cell row R col C channel CH",
/// "micro.grid: missing cell row R col C channel CH" (first missing cell in
/// row-major order).
/// Complexity: O(n^2) worst case for n tiles of the channel.
pub fn mic_grid_validate(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                         channel: Int) -> Result[Unit, Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  let want: Int = cr.value;
  var count = 0;
  var i = 0;
  while i < t.rows.len() {
    let ch: Int = t.channels[i];
    if ch == channel {
      let r: Int = t.rows[i];
      let c: Int = t.cols[i];
      if r < 0 || r >= rows_n {
        return _err_unit("micro.grid: tile " + convert.int_to_string(i) +
                         " row " + convert.int_to_string(r) + " out of range 0.." +
                         convert.int_to_string(rows_n - 1));
      }
      if c < 0 || c >= cols_n {
        return _err_unit("micro.grid: tile " + convert.int_to_string(i) +
                         " col " + convert.int_to_string(c) + " out of range 0.." +
                         convert.int_to_string(cols_n - 1));
      }
      var j = 0;
      while j < i {
        let chj: Int = t.channels[j];
        if chj == channel {
          let rj: Int = t.rows[j];
          let cj: Int = t.cols[j];
          if rj == r && cj == c {
            return _err_unit("micro.grid: duplicate cell row " + convert.int_to_string(r) +
                             " col " + convert.int_to_string(c) + " channel " +
                             convert.int_to_string(channel));
          }
        }
        j = j + 1;
      }
      count = count + 1;
    }
    i = i + 1;
  }
  if count != want {
    var rr = 0;
    while rr < rows_n {
      var cc = 0;
      while cc < cols_n {
        if !_m_has_cell(t, rr, cc, channel) {
          return _err_unit("micro.grid: missing cell row " + convert.int_to_string(rr) +
                           " col " + convert.int_to_string(cc) + " channel " +
                           convert.int_to_string(channel));
        }
        cc = cc + 1;
      }
      rr = rr + 1;
    }
    return _err_unit("micro.grid: channel " + convert.int_to_string(channel) +
                     " has " + convert.int_to_string(count) + " tiles, expected " +
                     convert.int_to_string(want));
  }
  return _ok_unit();
}

/// True when mic_grid_validate succeeds for the same arguments.
/// Complexity: O(n^2) worst case.
pub fn mic_grid_is_complete(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                            channel: Int) -> Bool {
  let vr = mic_grid_validate(t, rows_n, cols_n, channel);
  return vr.is_ok;
}

/// Validate one (channel, z) plane of a z-stack: exactly rows_n*cols_n tiles
/// with this channel and z-slice, every cell in 0..rows_n-1 x 0..cols_n-1
/// appearing exactly once; tiles of other channels or other z-slices are
/// ignored. Use this (not mic_grid_validate) for sets that hold more than one
/// z-slice per channel.
///
/// Errors: the mic_grid_count dimension messages, then
/// "micro.grid: tile I row R out of range 0..rows_n-1",
/// "micro.grid: tile I col C out of range 0..cols_n-1",
/// "micro.grid: duplicate cell row R col C channel CH z Z",
/// "micro.grid: missing cell row R col C channel CH z Z".
/// Complexity: O(n^2) worst case for n tiles of the plane.
pub fn mic_grid_slice_validate(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                               channel: Int, z: Int) -> Result[Unit, Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  let want: Int = cr.value;
  var count = 0;
  var i = 0;
  while i < t.rows.len() {
    let ch: Int = t.channels[i];
    let zz: Int = t.zs[i];
    if ch == channel && zz == z {
      let r: Int = t.rows[i];
      let c: Int = t.cols[i];
      if r < 0 || r >= rows_n {
        return _err_unit("micro.grid: tile " + convert.int_to_string(i) +
                         " row " + convert.int_to_string(r) + " out of range 0.." +
                         convert.int_to_string(rows_n - 1));
      }
      if c < 0 || c >= cols_n {
        return _err_unit("micro.grid: tile " + convert.int_to_string(i) +
                         " col " + convert.int_to_string(c) + " out of range 0.." +
                         convert.int_to_string(cols_n - 1));
      }
      var j = 0;
      while j < i {
        let chj: Int = t.channels[j];
        let zj: Int = t.zs[j];
        if chj == channel && zj == z {
          let rj: Int = t.rows[j];
          let cj: Int = t.cols[j];
          if rj == r && cj == c {
            return _err_unit("micro.grid: duplicate cell row " + convert.int_to_string(r) +
                             " col " + convert.int_to_string(c) + " channel " +
                             convert.int_to_string(channel) + " z " + convert.int_to_string(z));
          }
        }
        j = j + 1;
      }
      count = count + 1;
    }
    i = i + 1;
  }
  if count != want {
    var rr = 0;
    while rr < rows_n {
      var cc = 0;
      while cc < cols_n {
        if !_m_has_cell_z(t, rr, cc, channel, z) {
          return _err_unit("micro.grid: missing cell row " + convert.int_to_string(rr) +
                           " col " + convert.int_to_string(cc) + " channel " +
                           convert.int_to_string(channel) + " z " + convert.int_to_string(z));
        }
        cc = cc + 1;
      }
      rr = rr + 1;
    }
    return _err_unit("micro.grid: channel " + convert.int_to_string(channel) + " z " +
                     convert.int_to_string(z) + " has " + convert.int_to_string(count) +
                     " tiles, expected " + convert.int_to_string(want));
  }
  return _ok_unit();
}

/// True when mic_grid_slice_validate succeeds for the same arguments.
/// Complexity: O(n^2) worst case.
pub fn mic_grid_slice_is_complete(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                                  channel: Int, z: Int) -> Bool {
  let vr = mic_grid_slice_validate(t, rows_n, cols_n, channel, z);
  return vr.is_ok;
}

/// Linear indices (row*cols_n + col) of the cells missing from the
/// rows_n x cols_n grid of `channel`, in row-major order; an empty vector
/// means complete. Duplicate cells do not affect the result.
///
/// Errors: the mic_grid_count dimension messages.
/// Complexity: O(rows*cols*n) for n tiles.
pub fn mic_grid_missing(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                        channel: Int) -> Result[Vec[Int], Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_vec_int(cr.error);
  }
  var out = Vec[Int].new();
  var r = 0;
  while r < rows_n {
    var c = 0;
    while c < cols_n {
      if !_m_has_cell(t, r, c, channel) {
        out.push(r * cols_n + c);
      }
      c = c + 1;
    }
    r = r + 1;
  }
  return _ok_vec_int(out);
}

/// Validate that the tiles of `channel` appear in exactly row-major order:
/// the k-th tile of the channel must be row k/cols_n, col k%cols_n (q/r
/// division), and there must be exactly rows_n*cols_n of them.
///
/// Errors: the mic_grid_count dimension messages, then
/// "micro.order: tile K is row R col C, expected row ER col EC",
/// "micro.order: channel CH has N tiles, expected M".
/// Complexity: O(n).
pub fn mic_tiles_row_major(t: &MicroTileSet, rows_n: Int, cols_n: Int,
                           channel: Int) -> Result[Unit, Str] {
  let cr = mic_grid_count(rows_n, cols_n);
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  let want: Int = cr.value;
  var k = 0;
  var i = 0;
  while i < t.rows.len() {
    let ch: Int = t.channels[i];
    if ch == channel {
      let r: Int = t.rows[i];
      let c: Int = t.cols[i];
      let er = k / cols_n;
      let ec = k % cols_n;
      if r != er || c != ec {
        return _err_unit("micro.order: tile " + convert.int_to_string(k) +
                         " is row " + convert.int_to_string(r) + " col " +
                         convert.int_to_string(c) + ", expected row " +
                         convert.int_to_string(er) + " col " + convert.int_to_string(ec));
      }
      k = k + 1;
    }
    i = i + 1;
  }
  if k != want {
    return _err_unit("micro.order: channel " + convert.int_to_string(channel) +
                     " has " + convert.int_to_string(k) + " tiles, expected " +
                     convert.int_to_string(want));
  }
  return _ok_unit();
}

/// Index of the tile adjacent to tile `i` in direction `dir` (MICRO_DIR_UP,
/// MICRO_DIR_DOWN, MICRO_DIR_LEFT or MICRO_DIR_RIGHT) with the same channel
/// and z-slice; the first match wins.
///
/// Errors: "micro.neighbor: tile index I out of range 0..N-1",
/// "micro.neighbor: direction D out of range 0..3 (0=up,1=down,2=left,3=right)",
/// "micro.neighbor: <dir> neighbor of tile I missing" (also at grid edges).
/// Complexity: O(n).
pub fn mic_neighbor(t: &MicroTileSet, i: Int, dir: Int) -> Result[Int, Str] {
  let n = t.rows.len();
  if i < 0 || i >= n {
    return _err_int("micro.neighbor: tile index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(n - 1));
  }
  if dir < 0 || dir > MICRO_DIR_RIGHT {
    return _err_int("micro.neighbor: direction " + convert.int_to_string(dir) +
                    " out of range 0..3 (0=up,1=down,2=left,3=right)");
  }
  let r: Int = t.rows[i];
  let c: Int = t.cols[i];
  let ch: Int = t.channels[i];
  let z: Int = t.zs[i];
  var tr = r;
  var tc = c;
  if dir == MICRO_DIR_UP {
    tr = r - 1;
  }
  if dir == MICRO_DIR_DOWN {
    tr = r + 1;
  }
  if dir == MICRO_DIR_LEFT {
    tc = c - 1;
  }
  if dir == MICRO_DIR_RIGHT {
    tc = c + 1;
  }
  var k = 0;
  while k < n {
    let chk: Int = t.channels[k];
    let zk: Int = t.zs[k];
    let rk: Int = t.rows[k];
    let ck: Int = t.cols[k];
    if chk == ch && zk == z && rk == tr && ck == tc {
      return _ok_int(k);
    }
    k = k + 1;
  }
  return _err_int("micro.neighbor: " + _m_dir_name(dir) + " neighbor of tile " +
                  convert.int_to_string(i) + " missing");
}

// --------------------------------------------------
//  Channel table
// --------------------------------------------------

/// Create an empty channel table.
/// Complexity: O(1).
pub fn mic_channels_new() -> MicroChannels {
  return MicroChannels{
    names: "";
    ex_nm: Vec[Int].new();
    em_nm: Vec[Int].new();
    colors: Vec[Int].new();
  };
}

/// Number of channels in the table.
/// Errors: none (total).
/// Complexity: O(1).
pub fn mic_channels_len(c: &MicroChannels) -> Int {
  return c.ex_nm.len();
}

/// Append one channel record: `name` (1..32 bytes of A-Z a-z 0-9 _ -),
/// excitation and emission wavelengths in nanometres (1..MICRO_NM_MAX) and a
/// 24-bit RGB color code (0..MICRO_COLOR_MAX). The name must be unique.
///
/// Errors: "micro.channels: too many channels (max 64)",
/// "micro.channels: <name error>", "micro.channels: duplicate name NAME",
/// "micro.channels: excitation out of range 1..1000000000000",
/// "micro.channels: emission out of range 1..1000000000000",
/// "micro.channels: color out of range 0..16777215".
/// Complexity: O(n) for the duplicate scan.
pub fn mic_channel_add(c: &mut MicroChannels, name: Str, ex_nm: Int, em_nm: Int,
                       color: Int) -> Result[Unit, Str] {
  if c.ex_nm.len() >= MICRO_CH_MAX {
    return _err_unit("micro.channels: too many channels (max 64)");
  }
  let nr = _m_name_ok(name);
  if !nr.is_ok {
    return _err_unit("micro.channels: " + nr.error);
  }
  if _m_blob_has_line(c.names, name) {
    return _err_unit("micro.channels: duplicate name " + name);
  }
  if ex_nm < 1 || ex_nm > MICRO_NM_MAX {
    return _err_unit("micro.channels: excitation out of range 1..1000000000000");
  }
  if em_nm < 1 || em_nm > MICRO_NM_MAX {
    return _err_unit("micro.channels: emission out of range 1..1000000000000");
  }
  if color < 0 || color > MICRO_COLOR_MAX {
    return _err_unit("micro.channels: color out of range 0..16777215");
  }
  c.names = c.names + name + "\n";
  c.ex_nm.push(ex_nm);
  c.em_nm.push(em_nm);
  c.colors.push(color);
  return _ok_unit();
}

/// Name of channel `i`.
/// Errors: "micro.channels: index I out of range 0..N-1".
/// Complexity: O(name table length).
pub fn mic_channel_name(c: &MicroChannels, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= c.ex_nm.len() {
    return _err_str("micro.channels: index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(c.ex_nm.len() - 1));
  }
  let name = _m_blob_line(c.names, i);
  if name.len() == 0 {
    return _err_str("micro.channels: malformed name table at index " +
                    convert.int_to_string(i));
  }
  return _ok_str(name);
}

/// Excitation wavelength of channel `i` in nanometres.
/// Errors: "micro.channels: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_channel_ex_nm(c: &MicroChannels, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.ex_nm.len() {
    return _err_int("micro.channels: index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(c.ex_nm.len() - 1));
  }
  let v: Int = c.ex_nm[i];
  return _ok_int(v);
}

/// Emission wavelength of channel `i` in nanometres.
/// Errors: "micro.channels: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_channel_em_nm(c: &MicroChannels, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.em_nm.len() {
    return _err_int("micro.channels: index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(c.em_nm.len() - 1));
  }
  let v: Int = c.em_nm[i];
  return _ok_int(v);
}

/// 24-bit color code of channel `i`.
/// Errors: "micro.channels: index I out of range 0..N-1".
/// Complexity: O(1).
pub fn mic_channel_color(c: &MicroChannels, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.colors.len() {
    return _err_int("micro.channels: index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(c.colors.len() - 1));
  }
  let v: Int = c.colors[i];
  return _ok_int(v);
}

/// Index of the first channel named `name`.
/// Errors: "micro.channels: no channel named NAME".
/// Complexity: O(n * name length).
pub fn mic_channel_index_of(c: &MicroChannels, name: Str) -> Result[Int, Str] {
  let n = c.ex_nm.len();
  var i = 0;
  while i < n {
    let nm = _m_blob_line(c.names, i);
    if compare.str_compare(nm, name) == 0 {
      return _ok_int(i);
    }
    i = i + 1;
  }
  return _err_int("micro.channels: no channel named " + name);
}

// --------------------------------------------------
//  Z-stack ordering and positions
// --------------------------------------------------

/// Physical z positions of `count` slices: start_nm + k*spacing_nm for
/// k = 0..count-1, in nanometres, strictly ascending.
///
/// Errors: "micro.z: count out of range 1..1000",
/// "micro.z: start out of range 0..1000000000000",
/// "micro.z: spacing out of range 1..1000000000000",
/// "micro.z: last position out of range 0..1000000000000".
/// Complexity: O(count).
pub fn mic_z_positions_nm(count: Int, start_nm: Int,
                          spacing_nm: Int) -> Result[Vec[Int], Str] {
  if count < 1 || count > MICRO_DIM_MAX {
    return _err_vec_int("micro.z: count out of range 1..1000");
  }
  if start_nm < 0 || start_nm > MICRO_NM_MAX {
    return _err_vec_int("micro.z: start out of range 0..1000000000000");
  }
  if spacing_nm < 1 || spacing_nm > MICRO_NM_MAX {
    return _err_vec_int("micro.z: spacing out of range 1..1000000000000");
  }
  let last = start_nm + (count - 1) * spacing_nm;
  if last > MICRO_NM_MAX {
    return _err_vec_int("micro.z: last position out of range 0..1000000000000");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    out.push(start_nm + i * spacing_nm);
    i = i + 1;
  }
  return _ok_vec_int(out);
}

/// True when the z positions are strictly increasing (an empty vector is
/// trivially ascending).
/// Complexity: O(n).
pub fn mic_z_is_ascending(zs: &Vec[Int]) -> Bool {
  let n = zs.len();
  var i = 1;
  while i < n {
    let a: Int = zs[i - 1];
    let b: Int = zs[i];
    if b <= a {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Index of the slice at exactly `z_nm`.
/// Errors: "micro.z: no z slices",
/// "micro.z: position Z not found among N slices".
/// Complexity: O(n).
pub fn mic_z_index_of(zs: &Vec[Int], z_nm: Int) -> Result[Int, Str] {
  let n = zs.len();
  if n == 0 {
    return _err_int("micro.z: no z slices");
  }
  var i = 0;
  while i < n {
    let z: Int = zs[i];
    if z == z_nm {
      return _ok_int(i);
    }
    i = i + 1;
  }
  return _err_int("micro.z: position " + convert.int_to_string(z_nm) +
                  " not found among " + convert.int_to_string(n) + " slices");
}

// --------------------------------------------------
//  Pixel calibration and physical extents
// --------------------------------------------------

/// Validate a fixed-point pixel calibration (um/px in 1e-4 units):
/// 1..MICRO_FP_MAX.
///
/// Errors: "micro.calib: um/px out of range 1..1000000000".
/// Complexity: O(1).
pub fn mic_calib_validate(um_per_px_fp: Int) -> Result[Unit, Str] {
  if um_per_px_fp < 1 || um_per_px_fp > MICRO_FP_MAX {
    return _err_unit("micro.calib: um/px out of range 1..1000000000");
  }
  return _ok_unit();
}

/// Physical extent of `px_count` pixels in fixed-point micrometres:
/// px_count * um_per_px_fp (exact, no rounding). px_count may be 0.
///
/// Errors: "micro.calib: pixel count out of range 0..1000000",
/// "micro.calib: um/px out of range 1..1000000000".
/// Complexity: O(1).
pub fn mic_extent_fp(px_count: Int, um_per_px_fp: Int) -> Result[Int, Str] {
  if px_count < 0 || px_count > MICRO_PX_MAX {
    return _err_int("micro.calib: pixel count out of range 0..1000000");
  }
  if um_per_px_fp < 1 || um_per_px_fp > MICRO_FP_MAX {
    return _err_int("micro.calib: um/px out of range 1..1000000000");
  }
  return _ok_int(px_count * um_per_px_fp);
}

/// Physical extent of `px_count` pixels in nanometres:
/// px_count * um_per_px_fp / 10, one division that truncates toward zero
/// (1 fixed-point unit = 0.1 nm). px_count may be 0.
///
/// Errors: "micro.calib: pixel count out of range 0..1000000",
/// "micro.calib: um/px out of range 1..1000000000".
/// Complexity: O(1).
pub fn mic_extent_nm(px_count: Int, um_per_px_fp: Int) -> Result[Int, Str] {
  let er = mic_extent_fp(px_count, um_per_px_fp);
  if !er.is_ok {
    return _err_int(er.error);
  }
  let fp_extent: Int = er.value;
  return _ok_int(fp_extent / 10);
}

/// Smallest pixel count covering `nm` nanometres at the given calibration,
/// using exact ceiling division q + (r > 0 ? 1 : 0). A length of 0 needs 0
/// pixels.
///
/// Errors: "micro.calib: length out of range 0..1000000000000",
/// "micro.calib: um/px out of range 1..1000000000".
/// Complexity: O(1).
pub fn mic_px_for_nm(nm: Int, um_per_px_fp: Int) -> Result[Int, Str] {
  if nm < 0 || nm > MICRO_NM_MAX {
    return _err_int("micro.calib: length out of range 0..1000000000000");
  }
  if um_per_px_fp < 1 || um_per_px_fp > MICRO_FP_MAX {
    return _err_int("micro.calib: um/px out of range 1..1000000000");
  }
  let num = nm * 10;
  let q = num / um_per_px_fp;
  let r = num % um_per_px_fp;
  if r > 0 {
    return _ok_int(q + 1);
  }
  return _ok_int(q);
}

// --------------------------------------------------
//  Manifest: construction and mutation
// --------------------------------------------------

/// Create an empty manifest for a rows x cols grid with the given fixed-point
/// calibration and z spacing (0 for a single slice).
///
/// Errors: "micro.manifest: grid rows out of range 1..1000",
/// "micro.manifest: grid cols out of range 1..1000",
/// "micro.manifest: grid cell count exceeds 1000000",
/// "micro.manifest: um/px out of range 1..1000000000",
/// "micro.manifest: z spacing out of range 0..1000000000000".
/// Complexity: O(1).
pub fn mic_manifest_new(grid_rows: Int, grid_cols: Int, um_per_px_fp: Int,
                        z_spacing_nm: Int) -> Result[MicroManifest, Str] {
  if grid_rows < 1 || grid_rows > MICRO_DIM_MAX {
    return _err_manifest("micro.manifest: grid rows out of range 1..1000");
  }
  if grid_cols < 1 || grid_cols > MICRO_DIM_MAX {
    return _err_manifest("micro.manifest: grid cols out of range 1..1000");
  }
  if grid_rows * grid_cols > MICRO_TILE_MAX {
    return _err_manifest("micro.manifest: grid cell count exceeds 1000000");
  }
  if um_per_px_fp < 1 || um_per_px_fp > MICRO_FP_MAX {
    return _err_manifest("micro.manifest: um/px out of range 1..1000000000");
  }
  if z_spacing_nm < 0 || z_spacing_nm > MICRO_NM_MAX {
    return _err_manifest("micro.manifest: z spacing out of range 0..1000000000000");
  }
  return _ok_manifest(MicroManifest{
    grid_rows: grid_rows;
    grid_cols: grid_cols;
    um_per_px_fp: um_per_px_fp;
    z_spacing_nm: z_spacing_nm;
    ch_names: "";
    ch_ex_nm: Vec[Int].new();
    ch_em_nm: Vec[Int].new();
    ch_colors: Vec[Int].new();
    tile_rows: Vec[Int].new();
    tile_cols: Vec[Int].new();
    tile_channels: Vec[Int].new();
    tile_zs: Vec[Int].new();
    tile_ticks: Vec[Int].new();
  });
}

/// Number of channels in the manifest channel tables.
/// Complexity: O(1).
pub fn mic_manifest_channel_count(m: &MicroManifest) -> Int {
  return m.ch_ex_nm.len();
}

/// Number of tiles in the manifest tile tables.
/// Complexity: O(1).
pub fn mic_manifest_tile_count(m: &MicroManifest) -> Int {
  return m.tile_rows.len();
}

/// Name of manifest channel `i`.
/// Errors: "micro.manifest: channel index I out of range 0..N-1".
/// Complexity: O(name table length).
pub fn mic_manifest_channel_name(m: &MicroManifest, i: Int) -> Result[Str, Str] {
  let n = m.ch_ex_nm.len();
  if i < 0 || i >= n {
    return _err_str("micro.manifest: channel index " + convert.int_to_string(i) +
                    " out of range 0.." + convert.int_to_string(n - 1));
  }
  let name = _m_blob_line(m.ch_names, i);
  if name.len() == 0 {
    return _err_str("micro.manifest: malformed name table at index " +
                    convert.int_to_string(i));
  }
  return _ok_str(name);
}

/// Append one channel record to the manifest (same validation as
/// mic_channel_add).
///
/// Errors: "micro.channels: too many channels (max 64)",
/// "micro.channels: <name error>", "micro.channels: duplicate name NAME",
/// "micro.channels: excitation out of range 1..1000000000000",
/// "micro.channels: emission out of range 1..1000000000000",
/// "micro.channels: color out of range 0..16777215".
/// Complexity: O(n) for the duplicate scan.
pub fn mic_manifest_add_channel(m: &mut MicroManifest, name: Str, ex_nm: Int,
                                em_nm: Int, color: Int) -> Result[Unit, Str] {
  if m.ch_ex_nm.len() >= MICRO_CH_MAX {
    return _err_unit("micro.channels: too many channels (max 64)");
  }
  let nr = _m_name_ok(name);
  if !nr.is_ok {
    return _err_unit("micro.channels: " + nr.error);
  }
  if _m_blob_has_line(m.ch_names, name) {
    return _err_unit("micro.channels: duplicate name " + name);
  }
  if ex_nm < 1 || ex_nm > MICRO_NM_MAX {
    return _err_unit("micro.channels: excitation out of range 1..1000000000000");
  }
  if em_nm < 1 || em_nm > MICRO_NM_MAX {
    return _err_unit("micro.channels: emission out of range 1..1000000000000");
  }
  if color < 0 || color > MICRO_COLOR_MAX {
    return _err_unit("micro.channels: color out of range 0..16777215");
  }
  m.ch_names = m.ch_names + name + "\n";
  m.ch_ex_nm.push(ex_nm);
  m.ch_em_nm.push(em_nm);
  m.ch_colors.push(color);
  return _ok_unit();
}

/// Append one tile record to the manifest. row and col must lie in
/// 0..MICRO_DIM_MAX-1; channel, z and tick must lie in 0..MICRO_INDEX_MAX,
/// and (row, col, channel, z) must not already exist in the tile tables.
///
/// Errors: "micro.manifest: tile row out of range 0..999",
/// "micro.manifest: tile col out of range 0..999",
/// "micro.manifest: tile channel out of range 0..1000000",
/// "micro.manifest: tile z out of range 0..1000000",
/// "micro.manifest: tile tick out of range 0..1000000",
/// "micro.manifest: duplicate cell row R col C channel CH z Z",
/// "micro.manifest: tile count would exceed 1000000".
/// Complexity: O(n) for the duplicate scan.
pub fn mic_manifest_add_tile(m: &mut MicroManifest, row: Int, col: Int,
                             channel: Int, z: Int, tick: Int) -> Result[Unit, Str] {
  if row < 0 || row >= MICRO_DIM_MAX {
    return _err_unit("micro.manifest: tile row out of range 0..999");
  }
  if col < 0 || col >= MICRO_DIM_MAX {
    return _err_unit("micro.manifest: tile col out of range 0..999");
  }
  if channel < 0 || channel > MICRO_INDEX_MAX {
    return _err_unit("micro.manifest: tile channel out of range 0..1000000");
  }
  if z < 0 || z > MICRO_INDEX_MAX {
    return _err_unit("micro.manifest: tile z out of range 0..1000000");
  }
  if tick < 0 || tick > MICRO_INDEX_MAX {
    return _err_unit("micro.manifest: tile tick out of range 0..1000000");
  }
  if m.tile_rows.len() >= MICRO_TILE_MAX {
    return _err_unit("micro.manifest: tile count would exceed 1000000");
  }
  let n = m.tile_rows.len();
  var i = 0;
  while i < n {
    let r: Int = m.tile_rows[i];
    let c: Int = m.tile_cols[i];
    let ch: Int = m.tile_channels[i];
    let zz: Int = m.tile_zs[i];
    if r == row && c == col && ch == channel && zz == z {
      return _err_unit("micro.manifest: duplicate cell row " + convert.int_to_string(row) +
                       " col " + convert.int_to_string(col) + " channel " +
                       convert.int_to_string(channel) + " z " + convert.int_to_string(z));
    }
    i = i + 1;
  }
  m.tile_rows.push(row);
  m.tile_cols.push(col);
  m.tile_channels.push(channel);
  m.tile_zs.push(z);
  m.tile_ticks.push(tick);
  return _ok_unit();
}

// --------------------------------------------------
//  Manifest validation
// --------------------------------------------------

// Validate the raw manifest tables (see mic_manifest_validate).
fn _m_manifest_validate_raw(gr: Int, gc: Int, fp: Int, zsp: Int, names: Str,
                            ex: &Vec[Int], em: &Vec[Int], colors: &Vec[Int],
                            tr: &Vec[Int], tc: &Vec[Int], tch: &Vec[Int],
                            tz: &Vec[Int], tt: &Vec[Int]) -> Result[Unit, Str] {
  if gr < 1 || gr > MICRO_DIM_MAX {
    return _err_unit("micro.manifest: grid rows out of range 1..1000");
  }
  if gc < 1 || gc > MICRO_DIM_MAX {
    return _err_unit("micro.manifest: grid cols out of range 1..1000");
  }
  if gr * gc > MICRO_TILE_MAX {
    return _err_unit("micro.manifest: grid cell count exceeds 1000000");
  }
  if fp < 1 || fp > MICRO_FP_MAX {
    return _err_unit("micro.manifest: um/px out of range 1..1000000000");
  }
  if zsp < 0 || zsp > MICRO_NM_MAX {
    return _err_unit("micro.manifest: z spacing out of range 0..1000000000000");
  }
  let chn = ex.len();
  let cvr = _m_channels_validate(chn, names, ex, em, colors);
  if !cvr.is_ok {
    return _err_unit(cvr.error);
  }
  let n = tr.len();
  if tc.len() != n {
    return _err_unit("micro.manifest: tile tables length mismatch rows=" +
                     convert.int_to_string(n) + " cols=" + convert.int_to_string(tc.len()));
  }
  if tch.len() != n {
    return _err_unit("micro.manifest: tile tables length mismatch rows=" +
                     convert.int_to_string(n) + " channels=" +
                     convert.int_to_string(tch.len()));
  }
  if tz.len() != n {
    return _err_unit("micro.manifest: tile tables length mismatch rows=" +
                     convert.int_to_string(n) + " zs=" + convert.int_to_string(tz.len()));
  }
  if tt.len() != n {
    return _err_unit("micro.manifest: tile tables length mismatch rows=" +
                     convert.int_to_string(n) + " ticks=" + convert.int_to_string(tt.len()));
  }
  var i = 0;
  while i < n {
    let r: Int = tr[i];
    let c: Int = tc[i];
    let ch: Int = tch[i];
    let z: Int = tz[i];
    let tk: Int = tt[i];
    if r < 0 || r >= gr {
      return _err_unit("micro.manifest: tile " + convert.int_to_string(i) + " row " +
                       convert.int_to_string(r) + " out of range 0.." +
                       convert.int_to_string(gr - 1));
    }
    if c < 0 || c >= gc {
      return _err_unit("micro.manifest: tile " + convert.int_to_string(i) + " col " +
                       convert.int_to_string(c) + " out of range 0.." +
                       convert.int_to_string(gc - 1));
    }
    if ch < 0 || ch >= chn {
      return _err_unit("micro.manifest: tile " + convert.int_to_string(i) + " channel " +
                       convert.int_to_string(ch) + " but manifest has " +
                       convert.int_to_string(chn) + " channels");
    }
    if z < 0 || z > MICRO_INDEX_MAX {
      return _err_unit("micro.manifest: tile " + convert.int_to_string(i) +
                       " z out of range 0..1000000");
    }
    if tk < 0 || tk > MICRO_INDEX_MAX {
      return _err_unit("micro.manifest: tile " + convert.int_to_string(i) +
                       " tick out of range 0..1000000");
    }
    var j = 0;
    while j < i {
      let rj: Int = tr[j];
      let cj: Int = tc[j];
      let chj: Int = tch[j];
      let zj: Int = tz[j];
      if rj == r && cj == c && chj == ch && zj == z {
        return _err_unit("micro.manifest: duplicate cell row " + convert.int_to_string(r) +
                         " col " + convert.int_to_string(c) + " channel " +
                         convert.int_to_string(ch) + " z " + convert.int_to_string(z));
      }
      j = j + 1;
    }
    i = i + 1;
  }
  let ts = MicroTileSet{
    rows: Vec[Int].new();
    cols: Vec[Int].new();
    channels: Vec[Int].new();
    zs: Vec[Int].new();
    ticks: Vec[Int].new();
  };
  i = 0;
  while i < n {
    let r2: Int = tr[i];
    let c2: Int = tc[i];
    let ch2: Int = tch[i];
    let z2: Int = tz[i];
    let tk2: Int = tt[i];
    ts.rows.push(r2);
    ts.cols.push(c2);
    ts.channels.push(ch2);
    ts.zs.push(z2);
    ts.ticks.push(tk2);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let ch3: Int = ts.channels[i];
    let z3: Int = ts.zs[i];
    var seen = false;
    var j2 = 0;
    while j2 < i {
      let chp: Int = ts.channels[j2];
      let zp: Int = ts.zs[j2];
      if chp == ch3 && zp == z3 {
        seen = true;
      }
      j2 = j2 + 1;
    }
    if !seen {
      let vr = mic_grid_slice_validate(&ts, gr, gc, ch3, z3);
      if !vr.is_ok {
        return _err_unit(vr.error);
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Validate a manifest as a whole: grid dimensions, calibration, z spacing,
/// channel tables (names, uniqueness, ranges) and tile tables (parallel
/// lengths, bounds, no duplicate (row, col, channel, z) cell, complete
/// rectangle per referenced (channel, z) plane). An empty channel or tile
/// table is valid; every (channel, z) plane referenced by a tile must cover
/// the full grid.
///
/// Errors: the micro.manifest:, micro.channels: and micro.grid: catalogs.
/// Complexity: O(n^2) worst case for n tiles.
pub fn mic_manifest_validate(m: &MicroManifest) -> Result[Unit, Str] {
  return _m_manifest_validate_raw(m.grid_rows, m.grid_cols, m.um_per_px_fp,
                                  m.z_spacing_nm, m.ch_names, &m.ch_ex_nm,
                                  &m.ch_em_nm, &m.ch_colors, &m.tile_rows,
                                  &m.tile_cols, &m.tile_channels, &m.tile_zs,
                                  &m.tile_ticks);
}

// --------------------------------------------------
//  Canonical text codec
// --------------------------------------------------

/// Emit the canonical manifest text:
///   header line MICRO_MANIFEST_HEADER
///   "grid <rows> <cols>"
///   "calib <um_per_px_fp as int.4dec>"
///   "zspacing <spacing_nm>"
///   one "channel <ex> <em> <color> <name>" line per channel
///   one "tile <row> <col> <channel> <z> <tick>" line per tile
/// Every line, the last included, ends with LF. The manifest is validated
/// first and a validation error is returned unchanged.
///
/// Errors: the mic_manifest_validate catalog.
/// Complexity: O(total output length).
pub fn mic_manifest_emit(m: &MicroManifest) -> Result[Str, Str] {
  let vr = mic_manifest_validate(m);
  if !vr.is_ok {
    return _err_str(vr.error);
  }
  var out = MICRO_MANIFEST_HEADER + "\n";
  out = out + "grid " + convert.int_to_string(m.grid_rows) + " " +
        convert.int_to_string(m.grid_cols) + "\n";
  out = out + "calib " + _m_emit_fp(m.um_per_px_fp) + "\n";
  out = out + "zspacing " + convert.int_to_string(m.z_spacing_nm) + "\n";
  let nc = m.ch_ex_nm.len();
  var i = 0;
  while i < nc {
    let ex: Int = m.ch_ex_nm[i];
    let em: Int = m.ch_em_nm[i];
    let colr: Int = m.ch_colors[i];
    let name = _m_blob_line(m.ch_names, i);
    out = out + "channel " + convert.int_to_string(ex) + " " +
          convert.int_to_string(em) + " " + convert.int_to_string(colr) + " " +
          name + "\n";
    i = i + 1;
  }
  let nt = m.tile_rows.len();
  i = 0;
  while i < nt {
    let r: Int = m.tile_rows[i];
    let c: Int = m.tile_cols[i];
    let ch: Int = m.tile_channels[i];
    let z: Int = m.tile_zs[i];
    let tk: Int = m.tile_ticks[i];
    out = out + "tile " + convert.int_to_string(r) + " " + convert.int_to_string(c) +
          " " + convert.int_to_string(ch) + " " + convert.int_to_string(z) + " " +
          convert.int_to_string(tk) + "\n";
    i = i + 1;
  }
  return _ok_str(out);
}

/// Parse canonical manifest text into `m`. The output tables are cleared
/// first and filled only on success (on Err they stay empty).
///
/// Grammar (SPEC.md section 8): the first non-blank line must equal
/// MICRO_MANIFEST_HEADER exactly; the following non-blank lines are records
/// in canonical order - grid, calib, zspacing, channels, tiles - with
/// leading/trailing spaces and tabs and a CR before LF ignored and empty
/// lines skipped. Integer tokens are unsigned decimals; the calib token is
/// fixed point with at most four fraction digits. Names are single tokens of
/// 1..32 bytes from A-Z a-z 0-9 _ -. The parsed manifest is validated with
/// mic_manifest_validate before it is stored.
///
/// Errors: "micro.codec: missing header" | "micro.codec: line L: ..."
/// (unknown record, duplicate grid/calib/zspacing, ordering, field count,
/// trailing text, value errors, name errors, duplicate name, duplicate
/// cell, bounds) | "micro.codec: missing grid" / "missing calib" /
/// "missing zspacing" | then the mic_manifest_validate catalog.
/// Complexity: O(total input length + n^2).
pub fn mic_manifest_parse(text: Str, m: &mut MicroManifest) -> Result[Unit, Str] {
  m.grid_rows = 0;
  m.grid_cols = 0;
  m.um_per_px_fp = 0;
  m.z_spacing_nm = 0;
  m.ch_names = "";
  m.ch_ex_nm.clear();
  m.ch_em_nm.clear();
  m.ch_colors.clear();
  m.tile_rows.clear();
  m.tile_cols.clear();
  m.tile_channels.clear();
  m.tile_zs.clear();
  m.tile_ticks.clear();
  var names = "";
  var ex = Vec[Int].new();
  var em = Vec[Int].new();
  var colors = Vec[Int].new();
  var tr = Vec[Int].new();
  var tc = Vec[Int].new();
  var tch = Vec[Int].new();
  var tz = Vec[Int].new();
  var tt = Vec[Int].new();
  var gr = 0;
  var gc = 0;
  var fp = 0;
  var zsp = 0;
  var seen_header = false;
  var seen_grid = false;
  var seen_calib = false;
  var seen_zspacing = false;
  var seen_channel = false;
  var seen_tile = false;
  let n = text.len();
  var start = 0;
  var i = 0;
  var line_no = 0;
  while i <= n {
    var at_end = i == n;
    var at_lf = false;
    if !at_end {
      if _m_byte(text, i) == 10 {
        at_lf = true;
      }
    }
    if at_end || at_lf {
      var end = i;
      if end > start {
        if _m_byte(text, end - 1) == 13 {
          end = end - 1;
        }
      }
      line_no = line_no + 1;
      let a = _m_skip_ws(text, start, end);
      var b = end;
      while b > a {
        let bb: Int = _m_byte(text, b - 1);
        if bb == 32 || bb == 9 {
          b = b - 1;
        } else {
          break;
        }
      }
      if a < b {
        if !seen_header {
          if _m_range_equals(text, a, b, MICRO_MANIFEST_HEADER) {
            seen_header = true;
          } else {
            return _err_unit("micro.codec: missing header");
          }
        } else {
          let head = "micro.codec: line " + convert.int_to_string(line_no) + ": ";
          let e1 = _m_token_end(text, a, b);
          let kw = string.str_slice(text, a, e1);
          var pos = e1;
          if compare.str_compare(kw, "grid") == 0 {
            if seen_grid {
              return _err_unit(head + "duplicate grid");
            }
            if seen_channel || seen_tile {
              return _err_unit(head + "grid must precede channel and tile records");
            }
            pos = _m_skip_ws(text, pos, b);
            var e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 2 fields, got 0");
            }
            let r1 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_DIM_MAX);
            if !r1.is_ok {
              return _err_unit(head + "field 1: " + r1.error);
            }
            let v1: Int = r1.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 2 fields, got 1");
            }
            let r2 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_DIM_MAX);
            if !r2.is_ok {
              return _err_unit(head + "field 2: " + r2.error);
            }
            let v2: Int = r2.value;
            pos = _m_skip_ws(text, e, b);
            if pos < b {
              return _err_unit(head + "trailing text after 2 fields");
            }
            if v1 < 1 {
              return _err_unit(head + "grid rows out of range 1..1000");
            }
            if v2 < 1 {
              return _err_unit(head + "grid cols out of range 1..1000");
            }
            gr = v1;
            gc = v2;
            seen_grid = true;
          } elif compare.str_compare(kw, "calib") == 0 {
            if seen_calib {
              return _err_unit(head + "duplicate calib");
            }
            if seen_channel || seen_tile {
              return _err_unit(head + "calib must precede channel and tile records");
            }
            pos = _m_skip_ws(text, pos, b);
            let e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 1 field, got 0");
            }
            let pr = _m_parse_fp(string.str_slice(text, pos, e));
            if !pr.is_ok {
              return _err_unit(head + "calib: " + pr.error);
            }
            let v: Int = pr.value;
            pos = _m_skip_ws(text, e, b);
            if pos < b {
              return _err_unit(head + "trailing text after 1 field");
            }
            if v < 1 || v > MICRO_FP_MAX {
              return _err_unit(head + "calib: um/px out of range 1..1000000000");
            }
            fp = v;
            seen_calib = true;
          } elif compare.str_compare(kw, "zspacing") == 0 {
            if seen_zspacing {
              return _err_unit(head + "duplicate zspacing");
            }
            if seen_channel || seen_tile {
              return _err_unit(head + "zspacing must precede channel and tile records");
            }
            pos = _m_skip_ws(text, pos, b);
            let e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 1 field, got 0");
            }
            let zr = _m_parse_uint(string.str_slice(text, pos, e), MICRO_NM_MAX);
            if !zr.is_ok {
              return _err_unit(head + "zspacing: " + zr.error);
            }
            let v: Int = zr.value;
            pos = _m_skip_ws(text, e, b);
            if pos < b {
              return _err_unit(head + "trailing text after 1 field");
            }
            zsp = v;
            seen_zspacing = true;
          } elif compare.str_compare(kw, "channel") == 0 {
            if !seen_grid {
              return _err_unit(head + "grid must precede channel and tile records");
            }
            if !seen_calib {
              return _err_unit(head + "calib must precede channel and tile records");
            }
            if !seen_zspacing {
              return _err_unit(head + "zspacing must precede channel and tile records");
            }
            if seen_tile {
              return _err_unit(head + "channel must precede tile records");
            }
            pos = _m_skip_ws(text, pos, b);
            var e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 4 fields, got 0");
            }
            let ar = _m_parse_uint(string.str_slice(text, pos, e), MICRO_NM_MAX);
            if !ar.is_ok {
              return _err_unit(head + "field 1: " + ar.error);
            }
            let v_ex: Int = ar.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 4 fields, got 1");
            }
            let br = _m_parse_uint(string.str_slice(text, pos, e), MICRO_NM_MAX);
            if !br.is_ok {
              return _err_unit(head + "field 2: " + br.error);
            }
            let v_em: Int = br.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 4 fields, got 2");
            }
            let cr2 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_COLOR_MAX);
            if !cr2.is_ok {
              return _err_unit(head + "field 3: " + cr2.error);
            }
            let v_col: Int = cr2.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 4 fields, got 3");
            }
            let name = string.str_slice(text, pos, e);
            pos = _m_skip_ws(text, e, b);
            if pos < b {
              return _err_unit(head + "trailing text after 4 fields");
            }
            if v_ex < 1 {
              return _err_unit(head + "channel excitation out of range 1..1000000000000");
            }
            if v_em < 1 {
              return _err_unit(head + "channel emission out of range 1..1000000000000");
            }
            let nr = _m_name_ok(name);
            if !nr.is_ok {
              return _err_unit(head + "channel name: " + nr.error);
            }
            if _m_blob_has_line(names, name) {
              return _err_unit(head + "channel: duplicate name " + name);
            }
            if ex.len() >= MICRO_CH_MAX {
              return _err_unit(head + "channel: too many channels (max 64)");
            }
            names = names + name + "\n";
            ex.push(v_ex);
            em.push(v_em);
            colors.push(v_col);
            seen_channel = true;
          } elif compare.str_compare(kw, "tile") == 0 {
            if !seen_grid {
              return _err_unit(head + "grid must precede channel and tile records");
            }
            if !seen_calib {
              return _err_unit(head + "calib must precede channel and tile records");
            }
            if !seen_zspacing {
              return _err_unit(head + "zspacing must precede channel and tile records");
            }
            if !seen_channel {
              return _err_unit(head + "channel must precede tile records");
            }
            pos = _m_skip_ws(text, pos, b);
            var e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 5 fields, got 0");
            }
            let f1 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_INDEX_MAX);
            if !f1.is_ok {
              return _err_unit(head + "field 1: " + f1.error);
            }
            let v_row: Int = f1.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 5 fields, got 1");
            }
            let f2 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_INDEX_MAX);
            if !f2.is_ok {
              return _err_unit(head + "field 2: " + f2.error);
            }
            let v_col: Int = f2.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 5 fields, got 2");
            }
            let f3 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_INDEX_MAX);
            if !f3.is_ok {
              return _err_unit(head + "field 3: " + f3.error);
            }
            let v_ch: Int = f3.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 5 fields, got 3");
            }
            let f4 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_INDEX_MAX);
            if !f4.is_ok {
              return _err_unit(head + "field 4: " + f4.error);
            }
            let v_z: Int = f4.value;
            pos = _m_skip_ws(text, e, b);
            e = _m_token_end(text, pos, b);
            if e == pos {
              return _err_unit(head + "expected 5 fields, got 4");
            }
            let f5 = _m_parse_uint(string.str_slice(text, pos, e), MICRO_INDEX_MAX);
            if !f5.is_ok {
              return _err_unit(head + "field 5: " + f5.error);
            }
            let v_tk: Int = f5.value;
            pos = _m_skip_ws(text, e, b);
            if pos < b {
              return _err_unit(head + "trailing text after 5 fields");
            }
            if v_row < 0 || v_row >= gr {
              return _err_unit(head + "tile row " + convert.int_to_string(v_row) +
                               " out of range 0.." + convert.int_to_string(gr - 1));
            }
            if v_col < 0 || v_col >= gc {
              return _err_unit(head + "tile col " + convert.int_to_string(v_col) +
                               " out of range 0.." + convert.int_to_string(gc - 1));
            }
            if v_ch < 0 || v_ch >= ex.len() {
              return _err_unit(head + "tile channel " + convert.int_to_string(v_ch) +
                               " out of range 0.." + convert.int_to_string(ex.len() - 1));
            }
            var dup = false;
            var j = 0;
            while j < tr.len() {
              let rj: Int = tr[j];
              let cj: Int = tc[j];
              let chj: Int = tch[j];
              let zj: Int = tz[j];
              if rj == v_row && cj == v_col && chj == v_ch && zj == v_z {
                dup = true;
              }
              j = j + 1;
            }
            if dup {
              return _err_unit(head + "duplicate cell row " + convert.int_to_string(v_row) +
                               " col " + convert.int_to_string(v_col) + " channel " +
                               convert.int_to_string(v_ch) + " z " + convert.int_to_string(v_z));
            }
            tr.push(v_row);
            tc.push(v_col);
            tch.push(v_ch);
            tz.push(v_z);
            tt.push(v_tk);
            seen_tile = true;
          } else {
            return _err_unit(head + "unknown record '" + kw + "'");
          }
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  if !seen_header {
    return _err_unit("micro.codec: missing header");
  }
  if !seen_grid {
    return _err_unit("micro.codec: missing grid");
  }
  if !seen_calib {
    return _err_unit("micro.codec: missing calib");
  }
  if !seen_zspacing {
    return _err_unit("micro.codec: missing zspacing");
  }
  let vr = _m_manifest_validate_raw(gr, gc, fp, zsp, names, &ex, &em, &colors,
                                    &tr, &tc, &tch, &tz, &tt);
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  m.grid_rows = gr;
  m.grid_cols = gc;
  m.um_per_px_fp = fp;
  m.z_spacing_nm = zsp;
  m.ch_names = names;
  m.ch_ex_nm = ex;
  m.ch_em_nm = em;
  m.ch_colors = colors;
  m.tile_rows = tr;
  m.tile_cols = tc;
  m.tile_channels = tch;
  m.tile_zs = tz;
  m.tile_ticks = tt;
  return _ok_unit();
}






