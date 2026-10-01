// XIOM -- xiom.microscopy conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.microscopy image-set metadata model
// against its SPEC: mirrored tile tables (row, col, channel, z, tick),
// row-major fill and ordering, complete-rectangle grid validation, missing
// tile lists, neighbor queries, channel metadata (name, excitation/emission
// nm, color), z-stack positions in nanometres, fixed-point pixel calibration
// and extents, ceiling pixel counts, and the canonical manifest text codec
// (emit exact text, parse round-trip and the full error catalog).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected integer below is a pinned decimal result of the documented
// rules, recomputed by hand; there are no floating point values in this
// file. All Str comparisons go through xiom.string.compare.str_compare
// (BUG 17 discipline); direct calls only, no function tables, and every Vec
// element read is bound to a typed local.

module microscopy_tests
use xiom.io; use xiom.test;
use xiom.microscopy;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Fixtures and check helpers
// --------------------------------------------------

// Str equality via str_compare (BUG 17 discipline).
fn seq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// One-, two-, three- and six-element Int vectors.
fn v1(x: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  return v;
}

fn v2(x: Int, y: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  return v;
}

fn v3(x: Int, y: Int, z: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  v.push(z);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn int_ok(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn unit_ok(r: Result[Unit, Str]) -> Bool {
  return r.is_ok;
}

fn unit_err(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn vec_is(r: Result[Vec[Int], Str], want: Vec[Int]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[Int] = r.value;
  return vec_eq(&v, &want);
}

fn vec_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn str_ok(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return seq(s, want);
}

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn manifest_err(r: Result[MicroManifest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn empty_manifest() -> MicroManifest {
  return MicroManifest{
    grid_rows: 0;
    grid_cols: 0;
    um_per_px_fp: 0;
    z_spacing_nm: 0;
    ch_names: "";
    ch_ex_nm: Vec[Int].new();
    ch_em_nm: Vec[Int].new();
    ch_colors: Vec[Int].new();
    tile_rows: Vec[Int].new();
    tile_cols: Vec[Int].new();
    tile_channels: Vec[Int].new();
    tile_zs: Vec[Int].new();
    tile_ticks: Vec[Int].new();
  };
}

fn manifest_or_empty(r: Result[MicroManifest, Str]) -> MicroManifest {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return empty_manifest();
}

// One mirrored tile field of a manifest collected into a fresh vector
// (which: 0 = rows, 1 = cols, 2 = channels, 3 = zs, 4 = ticks).
fn manifest_field_vec(m: &MicroManifest, which: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < m.tile_rows.len() {
    var v = 0;
    if which == 0 {
      let x: Int = m.tile_rows[i];
      v = x;
    }
    if which == 1 {
      let x: Int = m.tile_cols[i];
      v = x;
    }
    if which == 2 {
      let x: Int = m.tile_channels[i];
      v = x;
    }
    if which == 3 {
      let x: Int = m.tile_zs[i];
      v = x;
    }
    if which == 4 {
      let x: Int = m.tile_ticks[i];
      v = x;
    }
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Fill a manifest with the full grid of one channel at one z, in row-major
// order, returning false on the first failed add.
fn manifest_fill(m: &mut MicroManifest, rows_n: Int, cols_n: Int, channel: Int,
                 z: Int, tick: Int) -> Bool {
  var r = 0;
  while r < rows_n {
    var c = 0;
    while c < cols_n {
      let a = mic_manifest_add_tile(m, r, c, channel, z, tick);
      if !a.is_ok {
        return false;
      }
      c = c + 1;
    }
    r = r + 1;
  }
  return true;
}

// --------------------------------------------------
//  t01-t06: tile records, fill, ordering
// --------------------------------------------------

fn t01_tiles_new_and_accessors() -> TestResult {
  var t = mic_tiles_new();
  var ok = mic_tiles_len(&t) == 0;
  let a1 = mic_tiles_add(&t, 0, 0, 0, 0, 7);
  if !a1.is_ok { ok = false; }
  let a2 = mic_tiles_add(&t, 1, 2, 3, 4, 5);
  if !a2.is_ok { ok = false; }
  if mic_tiles_len(&t) != 2 { ok = false; }
  if !int_ok(mic_tile_row(&t, 0), 0) { ok = false; }
  if !int_ok(mic_tile_col(&t, 0), 0) { ok = false; }
  if !int_ok(mic_tile_channel(&t, 0), 0) { ok = false; }
  if !int_ok(mic_tile_z(&t, 0), 0) { ok = false; }
  if !int_ok(mic_tile_tick(&t, 0), 7) { ok = false; }
  if !int_ok(mic_tile_row(&t, 1), 1) { ok = false; }
  if !int_ok(mic_tile_col(&t, 1), 2) { ok = false; }
  if !int_ok(mic_tile_channel(&t, 1), 3) { ok = false; }
  if !int_ok(mic_tile_z(&t, 1), 4) { ok = false; }
  if !int_ok(mic_tile_tick(&t, 1), 5) { ok = false; }
  if !int_err(mic_tile_row(&t, 2), "micro.tiles: index 2 out of range 0..1") { ok = false; }
  if !int_err(mic_tile_row(&t, -1), "micro.tiles: index -1 out of range 0..1") { ok = false; }
  return assert(ok, "tile set: add two records and read every field back");
}

fn t02_tiles_add_validation() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_err(mic_tiles_add(&t, -1, 0, 0, 0, 0), "micro.tiles: row out of range 0..999");
  if !unit_err(mic_tiles_add(&t, 1000, 0, 0, 0, 0), "micro.tiles: row out of range 0..999") { ok = false; }
  if !unit_err(mic_tiles_add(&t, 0, -1, 0, 0, 0), "micro.tiles: col out of range 0..999") { ok = false; }
  if !unit_err(mic_tiles_add(&t, 0, 999, 0, 0, 1000001), "micro.tiles: tick out of range 0..1000000") { ok = false; }
  if !unit_err(mic_tiles_add(&t, 0, 0, -1, 0, 0), "micro.tiles: channel out of range 0..1000000") { ok = false; }
  if !unit_err(mic_tiles_add(&t, 0, 0, 0, -1, 0), "micro.tiles: z out of range 0..1000000") { ok = false; }
  if !unit_err(mic_tiles_add(&t, 0, 0, 0, 0, 1000001), "micro.tiles: tick out of range 0..1000000") { ok = false; }
  if mic_tiles_len(&t) != 0 { ok = false; }
  return assert(ok, "tile add: every range guard rejects and leaves the set empty");
}

fn t03_grid_fill_row_major() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_grid_fill(&t, 2, 3, 0, 1, 9));
  if mic_tiles_len(&t) != 6 { ok = false; }
  var rows = Vec[Int].new();
  var cols = Vec[Int].new();
  var zs = Vec[Int].new();
  var ticks = Vec[Int].new();
  var i = 0;
  while i < 6 {
    let rr = mic_tile_row(&t, i);
    let cc = mic_tile_col(&t, i);
    let zz = mic_tile_z(&t, i);
    let tk = mic_tile_tick(&t, i);
    if !rr.is_ok { ok = false; } else { let v: Int = rr.value; rows.push(v); }
    if !cc.is_ok { ok = false; } else { let v: Int = cc.value; cols.push(v); }
    if !zz.is_ok { ok = false; } else { let v: Int = zz.value; zs.push(v); }
    if !tk.is_ok { ok = false; } else { let v: Int = tk.value; ticks.push(v); }
    i = i + 1;
  }
  let wr = v6(0, 0, 0, 1, 1, 1);
  let wc = v6(0, 1, 2, 0, 1, 2);
  let wz = v6(1, 1, 1, 1, 1, 1);
  let wt = v6(9, 9, 9, 9, 9, 9);
  if !vec_eq(&rows, &wr) { ok = false; }
  if !vec_eq(&cols, &wc) { ok = false; }
  if !vec_eq(&zs, &wz) { ok = false; }
  if !vec_eq(&ticks, &wt) { ok = false; }
  return assert(ok, "grid fill 2x3: row-major order (0,0)(0,1)(0,2)(1,0)(1,1)(1,2)");
}

fn t04_grid_fill_validation() -> TestResult {
  var t = mic_tiles_new();
  var ok = int_err(mic_grid_count(0, 3), "micro.grid: rows out of range 1..1000");
  if !int_err(mic_grid_count(1001, 3), "micro.grid: rows out of range 1..1000") { ok = false; }
  if !int_err(mic_grid_count(3, 0), "micro.grid: cols out of range 1..1000") { ok = false; }
  if !int_ok(mic_grid_count(1000, 1000), 1000000) { ok = false; }
  if !int_ok(mic_grid_count(2, 3), 6) { ok = false; }
  if !unit_err(mic_grid_fill(&t, 0, 1, 0, 0, 0), "micro.grid: rows out of range 1..1000") { ok = false; }
  if !unit_err(mic_grid_fill(&t, 1, 1, 1000001, 0, 0), "micro.grid: channel out of range 0..1000000") { ok = false; }
  if !unit_err(mic_grid_fill(&t, 1, 1, 0, -1, 0), "micro.grid: z out of range 0..1000000") { ok = false; }
  if !unit_err(mic_grid_fill(&t, 1, 1, 0, 0, 1000001), "micro.grid: tick out of range 0..1000000") { ok = false; }
  if !unit_ok(mic_tiles_add(&t, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_grid_fill(&t, 1000, 1000, 0, 0, 0), "micro.grid: tile count would exceed 1000000") { ok = false; }
  if mic_tiles_len(&t) != 1 { ok = false; }
  return assert(ok, "grid count/fill bounds: dims, fields and the 1000000 capacity guard");
}

fn t05_row_major_order_check() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_grid_fill(&t, 2, 3, 0, 0, 0));
  if !unit_ok(mic_tiles_row_major(&t, 2, 3, 0)) { ok = false; }
  var s = mic_tiles_new();
  if !unit_ok(mic_tiles_add(&s, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&s, 0, 2, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&s, 0, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&s, 1, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&s, 1, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&s, 1, 2, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_tiles_row_major(&s, 2, 3, 0),
               "micro.order: tile 1 is row 0 col 2, expected row 0 col 1") { ok = false; }
  var p = mic_tiles_new();
  if !unit_ok(mic_grid_fill(&p, 1, 3, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_tiles_row_major(&p, 2, 3, 0),
               "micro.order: channel 0 has 3 tiles, expected 6") { ok = false; }
  return assert(ok, "row-major check: fill passes, swapped and partial grids fail");
}

fn t06_grid_validate_complete() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_grid_fill(&t, 2, 3, 0, 0, 0));
  if !unit_ok(mic_grid_validate(&t, 2, 3, 0)) { ok = false; }
  if !mic_grid_is_complete(&t, 2, 3, 0) { ok = false; }
  var m = mic_tiles_new();
  if !unit_ok(mic_tiles_add(&m, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&m, 0, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&m, 0, 2, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&m, 1, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&m, 1, 1, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_grid_validate(&m, 2, 3, 0), "micro.grid: missing cell row 1 col 2 channel 0") { ok = false; }
  if mic_grid_is_complete(&m, 2, 3, 0) { ok = false; }
  return assert(ok, "grid validate: complete 2x3 passes; one missing cell is located");
}

// --------------------------------------------------
//  t07-t15: duplicates, missing list, neighbors, channels, z, calibration
// --------------------------------------------------

fn t07_grid_duplicate_detection() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_tiles_add(&t, 0, 0, 0, 0, 0));
  if !unit_ok(mic_tiles_add(&t, 0, 0, 0, 0, 1)) { ok = false; }
  if !unit_ok(mic_tiles_add(&t, 0, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&t, 1, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&t, 1, 1, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_grid_validate(&t, 2, 2, 0),
               "micro.grid: duplicate cell row 0 col 0 channel 0") { ok = false; }
  return assert(ok, "grid validate: a repeated cell is reported before any count check");
}

fn t08_grid_foreign_channel_ignored() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_grid_fill(&t, 2, 2, 0, 0, 0));
  if !unit_ok(mic_tiles_add(&t, 5, 5, 1, 0, 0)) { ok = false; }
  if !unit_ok(mic_grid_validate(&t, 2, 2, 0)) { ok = false; }
  let mr = mic_grid_missing(&t, 2, 2, 0);
  let empty = Vec[Int].new();
  if !vec_is(mr, empty) { ok = false; }
  if !unit_err(mic_grid_validate(&t, 2, 2, 1),
               "micro.grid: tile 4 row 5 out of range 0..1") { ok = false; }
  return assert(ok, "grid validate: tiles of other channels are ignored");
}

fn t09_grid_missing_list() -> TestResult {
  var t = mic_tiles_new();
  var ok = true;
  var r = 0;
  while r < 3 {
    var c = 0;
    while c < 3 {
      if !(r == 0 && c == 1) {
        if !(r == 2 && c == 2) {
          let a = mic_tiles_add(&t, r, c, 0, 0, 0);
          if !a.is_ok { ok = false; }
        }
      }
      c = c + 1;
    }
    r = r + 1;
  }
  let want = v2(1, 8);
  if !vec_is(mic_grid_missing(&t, 3, 3, 0), want) { ok = false; }
  if !vec_err(mic_grid_missing(&t, 0, 3, 0), "micro.grid: rows out of range 1..1000") { ok = false; }
  var full = mic_tiles_new();
  if !unit_ok(mic_grid_fill(&full, 2, 2, 0, 0, 0)) { ok = false; }
  let none = Vec[Int].new();
  if !vec_is(mic_grid_missing(&full, 2, 2, 0), none) { ok = false; }
  return assert(ok, "grid missing: (0,1) and (2,2) of 3x3 are indices 1 and 8");
}

fn t10_neighbors() -> TestResult {
  var t = mic_tiles_new();
  var ok = unit_ok(mic_grid_fill(&t, 3, 3, 0, 0, 0));
  if !int_ok(mic_neighbor(&t, 4, MICRO_DIR_UP), 1) { ok = false; }
  if !int_ok(mic_neighbor(&t, 4, MICRO_DIR_DOWN), 7) { ok = false; }
  if !int_ok(mic_neighbor(&t, 4, MICRO_DIR_LEFT), 3) { ok = false; }
  if !int_ok(mic_neighbor(&t, 4, MICRO_DIR_RIGHT), 5) { ok = false; }
  if !int_ok(mic_neighbor(&t, 0, MICRO_DIR_DOWN), 3) { ok = false; }
  if !int_ok(mic_neighbor(&t, 0, MICRO_DIR_RIGHT), 1) { ok = false; }
  if !int_err(mic_neighbor(&t, 0, MICRO_DIR_UP),
              "micro.neighbor: up neighbor of tile 0 missing") { ok = false; }
  if !int_err(mic_neighbor(&t, 0, MICRO_DIR_LEFT),
              "micro.neighbor: left neighbor of tile 0 missing") { ok = false; }
  if !int_err(mic_neighbor(&t, 9, MICRO_DIR_UP),
              "micro.neighbor: tile index 9 out of range 0..8") { ok = false; }
  if !int_err(mic_neighbor(&t, 4, 4),
              "micro.neighbor: direction 4 out of range 0..3 (0=up,1=down,2=left,3=right)") { ok = false; }
  var g = mic_tiles_new();
  if !unit_ok(mic_tiles_add(&g, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 0, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 0, 2, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 1, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 1, 2, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 2, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 2, 1, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 2, 2, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_tiles_add(&g, 1, 1, 1, 0, 0)) { ok = false; }
  if !int_err(mic_neighbor(&g, 3, MICRO_DIR_RIGHT),
              "micro.neighbor: right neighbor of tile 3 missing") { ok = false; }
  if !int_err(mic_neighbor(&g, 6, MICRO_DIR_UP),
              "micro.neighbor: up neighbor of tile 6 missing") { ok = false; }
  return assert(ok, "neighbors: centre/corner lookups, edges, gaps and wrong channel");
}

fn t11_grid_count_bounds() -> TestResult {
  var ok = int_ok(mic_grid_count(2, 3), 6);
  if !int_ok(mic_grid_count(1, 1), 1) { ok = false; }
  if !int_ok(mic_grid_count(1000, 1000), 1000000) { ok = false; }
  if !int_err(mic_grid_count(0, 1), "micro.grid: rows out of range 1..1000") { ok = false; }
  if !int_err(mic_grid_count(1001, 1), "micro.grid: rows out of range 1..1000") { ok = false; }
  if !int_err(mic_grid_count(1, 0), "micro.grid: cols out of range 1..1000") { ok = false; }
  if !int_err(mic_grid_count(1, 1001), "micro.grid: cols out of range 1..1000") { ok = false; }
  return assert(ok, "grid count: 2*3=6, 1000*1000=1000000, both dimensions bounded");
}

fn t12_channels_accessors() -> TestResult {
  var c = mic_channels_new();
  var ok = mic_channels_len(&c) == 0;
  if !unit_ok(mic_channel_add(&c, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_channel_add(&c, "GFP", 488, 507, 65280)) { ok = false; }
  if mic_channels_len(&c) != 2 { ok = false; }
  if !str_ok(mic_channel_name(&c, 0), "DAPI") { ok = false; }
  if !str_ok(mic_channel_name(&c, 1), "GFP") { ok = false; }
  if !int_ok(mic_channel_ex_nm(&c, 0), 405) { ok = false; }
  if !int_ok(mic_channel_em_nm(&c, 0), 461) { ok = false; }
  if !int_ok(mic_channel_color(&c, 0), 16711935) { ok = false; }
  if !int_ok(mic_channel_ex_nm(&c, 1), 488) { ok = false; }
  if !int_ok(mic_channel_em_nm(&c, 1), 507) { ok = false; }
  if !int_ok(mic_channel_color(&c, 1), 65280) { ok = false; }
  if !int_ok(mic_channel_index_of(&c, "GFP"), 1) { ok = false; }
  if !int_err(mic_channel_index_of(&c, "RFP"), "micro.channels: no channel named RFP") { ok = false; }
  if !str_err(mic_channel_name(&c, 2), "micro.channels: index 2 out of range 0..1") { ok = false; }
  if !int_err(mic_channel_ex_nm(&c, -1), "micro.channels: index -1 out of range 0..1") { ok = false; }
  return assert(ok, "channels: add DAPI/GFP, read name/ex/em/color, look up by name");
}

fn t13_channels_validation() -> TestResult {
  var c = mic_channels_new();
  var ok = unit_err(mic_channel_add(&c, "", 405, 461, 1), "micro.channels: name must not be empty");
  let long_name = "abcdefghijklmnopqrstuvwxyz0123456";
  if !unit_err(mic_channel_add(&c, long_name, 405, 461, 1),
               "micro.channels: name longer than 32 characters") { ok = false; }
  if !unit_err(mic_channel_add(&c, "a b", 405, 461, 1),
               "micro.channels: name has a character outside A-Z a-z 0-9 _ -") { ok = false; }
  if !unit_ok(mic_channel_add(&c, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_err(mic_channel_add(&c, "DAPI", 405, 461, 1),
               "micro.channels: duplicate name DAPI") { ok = false; }
  if !unit_err(mic_channel_add(&c, "GFP", 0, 507, 1),
               "micro.channels: excitation out of range 1..1000000000000") { ok = false; }
  if !unit_err(mic_channel_add(&c, "GFP", 488, 1000000000001, 1),
               "micro.channels: emission out of range 1..1000000000000") { ok = false; }
  if !unit_err(mic_channel_add(&c, "GFP", 488, 507, 16777216),
               "micro.channels: color out of range 0..16777215") { ok = false; }
  if mic_channels_len(&c) != 1 { ok = false; }
  var c2 = mic_channels_new();
  var all_ok = true;
  var i = 0;
  while i < 64 {
    let nm = "ch" + convert.int_to_string(i);
    let a = mic_channel_add(&c2, nm, 400, 500, 1);
    if !a.is_ok { all_ok = false; }
    i = i + 1;
  }
  if !all_ok { ok = false; }
  if mic_channels_len(&c2) != 64 { ok = false; }
  if !unit_err(mic_channel_add(&c2, "extra", 400, 500, 1),
               "micro.channels: too many channels (max 64)") { ok = false; }
  return assert(ok, "channel add: name charset/length, duplicates, ranges and the 64 cap");
}

fn t14_z_positions() -> TestResult {
  var ok = true;
  let w = v3(100, 350, 600);
  if !vec_is(mic_z_positions_nm(3, 100, 250), w) { ok = false; }
  let w1 = v1(0);
  if !vec_is(mic_z_positions_nm(1, 0, 5), w1) { ok = false; }
  if !vec_err(mic_z_positions_nm(0, 0, 1), "micro.z: count out of range 1..1000") { ok = false; }
  if !vec_err(mic_z_positions_nm(1001, 0, 1), "micro.z: count out of range 1..1000") { ok = false; }
  if !vec_err(mic_z_positions_nm(1, -1, 1), "micro.z: start out of range 0..1000000000000") { ok = false; }
  if !vec_err(mic_z_positions_nm(1, 0, 0), "micro.z: spacing out of range 1..1000000000000") { ok = false; }
  if !vec_err(mic_z_positions_nm(2, 1000000000000, 1000000000000),
              "micro.z: last position out of range 0..1000000000000") { ok = false; }
  return assert(ok, "z positions: start + k*spacing, single slice, all range guards");
}

fn t15_z_order() -> TestResult {
  var ok = true;
  let zs = v3(0, 10, 20);
  if !mic_z_is_ascending(&zs) { ok = false; }
  let bad = v2(0, 0);
  if mic_z_is_ascending(&bad) { ok = false; }
  let empty = Vec[Int].new();
  if !mic_z_is_ascending(&empty) { ok = false; }
  if !int_ok(mic_z_index_of(&zs, 10), 1) { ok = false; }
  if !int_err(mic_z_index_of(&zs, 15), "micro.z: position 15 not found among 3 slices") { ok = false; }
  if !int_err(mic_z_index_of(&empty, 0), "micro.z: no z slices") { ok = false; }
  return assert(ok, "z order: ascending test, exact index lookup, not-found and empty errors");
}

fn t16_calibration_extents() -> TestResult {
  var ok = unit_ok(mic_calib_validate(1000));
  if !unit_err(mic_calib_validate(0), "micro.calib: um/px out of range 1..1000000000") { ok = false; }
  if !unit_err(mic_calib_validate(1000000001), "micro.calib: um/px out of range 1..1000000000") { ok = false; }
  if !int_ok(mic_extent_fp(1000, 1000), 1000000) { ok = false; }
  if !int_ok(mic_extent_nm(1000, 1000), 100000) { ok = false; }
  if !int_ok(mic_extent_nm(1, 1000), 100) { ok = false; }
  if !int_ok(mic_extent_fp(0, 1000), 0) { ok = false; }
  if !int_err(mic_extent_fp(1000001, 1000), "micro.calib: pixel count out of range 0..1000000") { ok = false; }
  if !int_err(mic_extent_nm(-1, 1000), "micro.calib: pixel count out of range 0..1000000") { ok = false; }
  if !int_err(mic_extent_nm(10, 0), "micro.calib: um/px out of range 1..1000000000") { ok = false; }
  return assert(ok, "calibration: 1000 px at 0.1000 um/px is 100.0000 um = 100000 nm");
}

fn t17_px_ceiling() -> TestResult {
  var ok = int_ok(mic_px_for_nm(100, 1000), 1);
  if !int_ok(mic_px_for_nm(101, 1000), 2) { ok = false; }
  if !int_ok(mic_px_for_nm(1, 1000), 1) { ok = false; }
  if !int_ok(mic_px_for_nm(0, 1000), 0) { ok = false; }
  if !int_ok(mic_px_for_nm(200, 1000), 2) { ok = false; }
  if !int_ok(mic_px_for_nm(250, 1000), 3) { ok = false; }
  if !int_err(mic_px_for_nm(-1, 1000), "micro.calib: length out of range 0..1000000000000") { ok = false; }
  if !int_err(mic_px_for_nm(1, 1000000001), "micro.calib: um/px out of range 1..1000000000") { ok = false; }
  return assert(ok, "pixel count: exact ceiling division (100->1, 101->2, 250->3)");
}

// --------------------------------------------------
//  t18-t24: manifest construction, codec, validation, integration
// --------------------------------------------------

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn add_tile_is(t: &mut MicroTileSet, row: Int, col: Int, channel: Int,
               z: Int, tick: Int) -> Bool {
  let r = mic_tiles_add(t, row, col, channel, z, tick);
  return r.is_ok;
}

fn t18_manifest_new_and_add() -> TestResult {
  var ok = manifest_err(mic_manifest_new(0, 2, 1000, 0),
                        "micro.manifest: grid rows out of range 1..1000");
  if !manifest_err(mic_manifest_new(2, 0, 1000, 0),
                   "micro.manifest: grid cols out of range 1..1000") { ok = false; }
  if !manifest_err(mic_manifest_new(2, 2, 0, 0),
                   "micro.manifest: um/px out of range 1..1000000000") { ok = false; }
  if !manifest_err(mic_manifest_new(2, 2, 1000, -1),
                   "micro.manifest: z spacing out of range 0..1000000000000") { ok = false; }
  let nr = mic_manifest_new(2, 2, 1000, 250);
  if !nr.is_ok { return assert(false, "manifest new: valid construction"); }
  var m: MicroManifest = nr.value;
  if mic_manifest_channel_count(&m) != 0 { ok = false; }
  if mic_manifest_tile_count(&m) != 0 { ok = false; }
  if !unit_ok(mic_manifest_add_channel(&m, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 1, 0, 0, 1)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 0, 0, 0, 2)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 1, 0, 0, 3)) { ok = false; }
  if mic_manifest_channel_count(&m) != 1 { ok = false; }
  if mic_manifest_tile_count(&m) != 4 { ok = false; }
  if !str_ok(mic_manifest_channel_name(&m, 0), "DAPI") { ok = false; }
  if !str_err(mic_manifest_channel_name(&m, 1),
              "micro.manifest: channel index 1 out of range 0..0") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, 0, 0, 0, 0, 0),
               "micro.manifest: duplicate cell row 0 col 0 channel 0 z 0") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, -1, 0, 0, 0, 0),
               "micro.manifest: tile row out of range 0..999") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, 0, 1000, 0, 0, 0),
               "micro.manifest: tile col out of range 0..999") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, 0, 0, 1000001, 0, 0),
               "micro.manifest: tile channel out of range 0..1000000") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, 0, 0, 0, -1, 0),
               "micro.manifest: tile z out of range 0..1000000") { ok = false; }
  if !unit_err(mic_manifest_add_tile(&m, 0, 0, 0, 0, 1000001),
               "micro.manifest: tile tick out of range 0..1000000") { ok = false; }
  if !unit_err(mic_manifest_add_channel(&m, "DAPI", 405, 461, 1),
               "micro.channels: duplicate name DAPI") { ok = false; }
  if mic_manifest_tile_count(&m) != 4 { ok = false; }
  return assert(ok, "manifest: new plus add channel/tile, duplicate and range guards");
}

fn t19_manifest_emit_exact() -> TestResult {
  let nr = mic_manifest_new(2, 2, 1000, 250);
  var ok = nr.is_ok;
  var m: MicroManifest = nr.value;
  if !unit_ok(mic_manifest_add_channel(&m, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 1, 0, 0, 1)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 0, 0, 0, 2)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 1, 0, 0, 3)) { ok = false; }
  let want = "#microscopy manifest v1\ngrid 2 2\ncalib 0.1000\nzspacing 250\nchannel 405 461 16711935 DAPI\ntile 0 0 0 0 0\ntile 0 1 0 0 1\ntile 1 0 0 0 2\ntile 1 1 0 0 3\n";
  if !str_ok(mic_manifest_emit(&m), want) { ok = false; }
  if !seq(MICRO_MANIFEST_HEADER, "#microscopy manifest v1") { ok = false; }
  return assert(ok, "manifest emit: exact canonical text, fixed-point calib 0.1000");
}

fn t20_manifest_round_trip() -> TestResult {
  var ok = true;
  let nr = mic_manifest_new(2, 2, 1000, 250);
  var m: MicroManifest = nr.value;
  if !unit_ok(mic_manifest_add_channel(&m, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 0, 1, 0, 0, 1)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 0, 0, 0, 2)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m, 1, 1, 0, 0, 3)) { ok = false; }
  var text = "";
  match mic_manifest_emit(&m) {
    Ok(v) => { text = v; },
    Err(_) => { ok = false; },
  }
  var m2 = empty_manifest();
  if !unit_ok(mic_manifest_parse(text, &m2)) { ok = false; }
  if m2.grid_rows != 2 { ok = false; }
  if m2.grid_cols != 2 { ok = false; }
  if m2.um_per_px_fp != 1000 { ok = false; }
  if m2.z_spacing_nm != 250 { ok = false; }
  if mic_manifest_channel_count(&m2) != 1 { ok = false; }
  if mic_manifest_tile_count(&m2) != 4 { ok = false; }
  if !str_ok(mic_manifest_channel_name(&m2, 0), "DAPI") { ok = false; }
  if m2.ch_ex_nm.len() != 1 { ok = false; }
  let exv: Int = m2.ch_ex_nm[0];
  let emv: Int = m2.ch_em_nm[0];
  let colv: Int = m2.ch_colors[0];
  if exv != 405 { ok = false; }
  if emv != 461 { ok = false; }
  if colv != 16711935 { ok = false; }
  let wr = v4(0, 0, 1, 1);
  let wc = v4(0, 1, 0, 1);
  let wz = v4(0, 0, 0, 0);
  let wt = v4(0, 1, 2, 3);
  let got_r = manifest_field_vec(&m2, 0);
  let got_c = manifest_field_vec(&m2, 1);
  let got_z = manifest_field_vec(&m2, 3);
  let got_t = manifest_field_vec(&m2, 4);
  if !vec_eq(&got_r, &wr) { ok = false; }
  if !vec_eq(&got_c, &wc) { ok = false; }
  if !vec_eq(&got_z, &wz) { ok = false; }
  if !vec_eq(&got_t, &wt) { ok = false; }
  let er2 = mic_manifest_emit(&m2);
  if !str_ok(er2, text) { ok = false; }
  let e = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  var t2 = "";
  match mic_manifest_emit(&e) {
    Ok(v) => { t2 = v; },
    Err(_) => { ok = false; },
  }
  var e2 = empty_manifest();
  if !unit_ok(mic_manifest_parse(t2, &e2)) { ok = false; }
  if e2.grid_rows != 2 { ok = false; }
  if e2.z_spacing_nm != 0 { ok = false; }
  if mic_manifest_channel_count(&e2) != 0 { ok = false; }
  if mic_manifest_tile_count(&e2) != 0 { ok = false; }
  let er3 = mic_manifest_emit(&e2);
  if !str_ok(er3, t2) { ok = false; }
  return assert(ok, "manifest round trip: full and empty manifests re-emit identically");
}

// Canonical codec fixtures for the error-catalog checks.
fn codec_base() -> Str {
  return MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0.1000\nzspacing 100\n";
}

fn codec_prefix() -> Str {
  return codec_base() + "channel 405 461 1 DAPI\n";
}

fn t21_codec_structure_errors() -> TestResult {
  var m = empty_manifest();
  var ok = unit_err(mic_manifest_parse("bogus\n", &m), "micro.codec: missing header");
  if !unit_err(mic_manifest_parse("", &m), "micro.codec: missing header") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\nbogus\n", &m),
               "micro.codec: line 3: unknown record 'bogus'") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ngrid 2 2\n", &m),
               "micro.codec: line 3: duplicate grid") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\nchannel 405 461 1 DAPI\n", &m),
               "micro.codec: line 3: calib must precede channel and tile records") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0.1000\nchannel 405 461 1 DAPI\n", &m),
               "micro.codec: line 4: zspacing must precede channel and tile records") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0.1000\nzspacing 100\ntile 0 0 0 0 0\n", &m),
               "micro.codec: line 5: channel must precede tile records") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\n", &m),
               "micro.codec: missing grid") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\n", &m),
               "micro.codec: missing calib") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0.1000\n", &m),
               "micro.codec: missing zspacing") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2 extra\n", &m),
               "micro.codec: line 2: trailing text after 2 fields") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 x\n", &m),
               "micro.codec: line 2: field 2: bad value") { ok = false; }
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 1001 2\n", &m),
               "micro.codec: line 2: field 1: value out of range 0..1000") { ok = false; }
  return assert(ok, "codec structure errors: header, unknown record, ordering, missing records");
}

fn t22_codec_value_errors() -> TestResult {
  var m = empty_manifest();
  var ok = unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0.10000\n", &m),
                    "micro.codec: line 3: calib: more than 4 decimal places");
  if !unit_err(mic_manifest_parse(MICRO_MANIFEST_HEADER + "\ngrid 2 2\ncalib 0\n", &m),
               "micro.codec: line 3: calib: um/px out of range 1..1000000000") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_base() + "channel 405 461 1 DA.PI\n", &m),
               "micro.codec: line 5: channel name: name has a character outside A-Z a-z 0-9 _ -") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_base() + "channel 405 461 1 DAPI\nchannel 405 461 1 DAPI\n", &m),
               "micro.codec: line 6: channel: duplicate name DAPI") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_base() + "channel 0 461 1 DAPI\n", &m),
               "micro.codec: line 5: channel excitation out of range 1..1000000000000") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_base() + "channel 405 461 16777216 DAPI\n", &m),
               "micro.codec: line 5: field 3: value out of range 0..16777215") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_prefix() + "tile 0 0 1 0 0\n", &m),
               "micro.codec: line 6: tile channel 1 out of range 0..0") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_prefix() + "tile 2 0 0 0 0\n", &m),
               "micro.codec: line 6: tile row 2 out of range 0..1") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_prefix() + "tile 0 0 0 0 0\ntile 0 0 0 0 0\n", &m),
               "micro.codec: line 7: duplicate cell row 0 col 0 channel 0 z 0") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_prefix() + "tile 0 0 0 0 0\ntile 0 1 0 0 0\ntile 1 0 0 0 0\n", &m),
               "micro.grid: missing cell row 1 col 1 channel 0 z 0") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_base() + "channel 405 461 1\n", &m),
               "micro.codec: line 5: expected 4 fields, got 3") { ok = false; }
  if !unit_err(mic_manifest_parse(codec_prefix() + "tile 0 0 0 0\n", &m),
               "micro.codec: line 6: expected 5 fields, got 4") { ok = false; }
  return assert(ok, "codec value errors: calib, names, duplicates, bounds, incomplete grid");
}

fn t23_manifest_validate_errors() -> TestResult {
  var m = empty_manifest();
  var ok = unit_err(mic_manifest_validate(&m), "micro.manifest: grid rows out of range 1..1000");
  var v = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  if !unit_ok(mic_manifest_validate(&v)) { ok = false; }
  var m2 = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  if !unit_ok(mic_manifest_add_channel(&m2, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m2, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m2, 0, 1, 0, 0, 1)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m2, 1, 0, 0, 0, 2)) { ok = false; }
  if !unit_err(mic_manifest_validate(&m2), "micro.grid: missing cell row 1 col 1 channel 0 z 0") { ok = false; }
  var m3 = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  if !unit_ok(mic_manifest_add_tile(&m3, 0, 0, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_manifest_validate(&m3),
               "micro.manifest: tile 0 channel 0 but manifest has 0 channels") { ok = false; }
  var m4 = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  m4.tile_rows.push(0);
  if !unit_err(mic_manifest_validate(&m4),
               "micro.manifest: tile tables length mismatch rows=1 cols=0") { ok = false; }
  var m5 = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  m5.ch_names = "A\nB\n";
  m5.ch_ex_nm.push(400);
  if !unit_err(mic_manifest_validate(&m5),
               "micro.channels: table length mismatch excitation=1 emission=0") { ok = false; }
  var m6 = manifest_or_empty(mic_manifest_new(2, 2, 1000, 0));
  if !unit_ok(mic_manifest_add_channel(&m6, "DAPI", 405, 461, 1)) { ok = false; }
  if !unit_ok(mic_manifest_add_tile(&m6, 2, 0, 0, 0, 0)) { ok = false; }
  if !unit_err(mic_manifest_validate(&m6),
               "micro.manifest: tile 0 row 2 out of range 0..1") { ok = false; }
  return assert(ok, "manifest validate: empty grid, channel-less tile, table and grid bounds");
}

fn t24_integration_zstack() -> TestResult {
  var ok = true;
  var t = mic_tiles_new();
  if !unit_ok(mic_grid_fill_zstack(&t, 3, 3, 0, 0, 2, 5)) { ok = false; }
  if mic_tiles_len(&t) != 18 { ok = false; }
  if !int_ok(mic_tile_z(&t, 9), 1) { ok = false; }
  if !int_ok(mic_tile_row(&t, 9), 0) { ok = false; }
  if !int_ok(mic_tile_row(&t, 17), 2) { ok = false; }
  if !int_ok(mic_tile_col(&t, 17), 2) { ok = false; }
  if !unit_ok(mic_grid_slice_validate(&t, 3, 3, 0, 0)) { ok = false; }
  if !unit_ok(mic_grid_slice_validate(&t, 3, 3, 0, 1)) { ok = false; }
  if !mic_grid_slice_is_complete(&t, 3, 3, 0, 1) { ok = false; }
  if !unit_err(mic_grid_slice_validate(&t, 3, 3, 0, 2),
               "micro.grid: missing cell row 0 col 0 channel 0 z 2") { ok = false; }
  if !int_ok(mic_neighbor(&t, 4, MICRO_DIR_DOWN), 7) { ok = false; }
  if !int_ok(mic_neighbor(&t, 13, MICRO_DIR_UP), 10) { ok = false; }
  if !int_ok(mic_neighbor(&t, 13, MICRO_DIR_DOWN), 16) { ok = false; }
  let zp = v2(0, 500);
  if !vec_is(mic_z_positions_nm(2, 0, 500), zp) { ok = false; }
  let nr = mic_manifest_new(3, 3, 250, 500);
  if !nr.is_ok { return assert(false, "integration: manifest construction"); }
  var m: MicroManifest = nr.value;
  if !unit_ok(mic_manifest_add_channel(&m, "DAPI", 405, 461, 16711935)) { ok = false; }
  if !unit_ok(mic_manifest_add_channel(&m, "GFP", 488, 507, 65280)) { ok = false; }
  var z = 0;
  while z < 2 {
    var r = 0;
    while r < 3 {
      var c = 0;
      while c < 3 {
        let tk = z * 9 + r * 3 + c;
        let a1 = mic_manifest_add_tile(&m, r, c, 0, z, tk);
        let a2 = mic_manifest_add_tile(&m, r, c, 1, z, tk);
        if !a1.is_ok { ok = false; }
        if !a2.is_ok { ok = false; }
        c = c + 1;
      }
      r = r + 1;
    }
    z = z + 1;
  }
  if mic_manifest_tile_count(&m) != 36 { ok = false; }
  if !unit_ok(mic_manifest_validate(&m)) { ok = false; }
  var text = "";
  match mic_manifest_emit(&m) {
    Ok(vv) => { text = vv; },
    Err(_) => { ok = false; },
  }
  var m2 = empty_manifest();
  if !unit_ok(mic_manifest_parse(text, &m2)) { ok = false; }
  if m2.grid_rows != 3 { ok = false; }
  if m2.grid_cols != 3 { ok = false; }
  if m2.um_per_px_fp != 250 { ok = false; }
  if m2.z_spacing_nm != 500 { ok = false; }
  if mic_manifest_channel_count(&m2) != 2 { ok = false; }
  if mic_manifest_tile_count(&m2) != 36 { ok = false; }
  if !str_ok(mic_manifest_channel_name(&m2, 1), "GFP") { ok = false; }
  let er2 = mic_manifest_emit(&m2);
  if !str_ok(er2, text) { ok = false; }
  return assert(ok, "integration: 3x3 two-channel two-slice manifest, emit/parse identity");
}

fn main() -> Int {
  io.println("=== xiom.microscopy conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_tiles_new_and_accessors();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_tiles_add_validation();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_grid_fill_row_major();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_grid_fill_validation();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_row_major_order_check();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_grid_validate_complete();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_grid_duplicate_detection();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_grid_foreign_channel_ignored();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_grid_missing_list();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_neighbors();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_grid_count_bounds();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_channels_accessors();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_channels_validation();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_z_positions();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_z_order();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_calibration_extents();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_px_ceiling();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_manifest_new_and_add();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_manifest_emit_exact();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_manifest_round_trip();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_codec_structure_errors();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_codec_value_errors();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_manifest_validate_errors();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_integration_zstack();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.microscopy: all tests passed");
  } else {
    io.println("xiom.microscopy: tests failed");
  }
  return failed;
}



