// XIOM -- xiom.photometrics: photometric profile import (IES LM-63 + .cube)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Two pure-XIOM readers for small, well-specified text formats:
//
//   * IESNA LM-63 photometric files -- the four in-use revisions (1986,
//     "IESNA91" = 1991, 1995, 2002): version/format tag, bracketed
//     luminaire metadata, TILT= handling (NONE / INCLUDE / file
//     reference), the lamp/lumen/wattage parameter lines, the vertical
//     and horizontal angle grids and the candela table, plus a bilinear
//     normalized lookup helper (`ies_sample`).
//   * Adobe ".cube" 3D-LUT files ("Cube LUT Specification 1.0"):
//     TITLE, LUT_1D_SIZE / LUT_3D_SIZE, DOMAIN_MIN / DOMAIN_MAX and the
//     RGB data triples (red channel varying fastest), with typed errors
//     for malformed or truncated input and 1D/3D sampling helpers.
//
// Storage is fully owned: every vector is built with push-growth (never
// Vec.with_len; B-28), no FFI and no pointer arithmetic anywhere. Str
// equality binds a typed local first and goes through str_compare (BUG 17);
// error propagation is explicit match/rewrap (no `?`: v0.64.4 corrupts
// error payloads crossing different Result payload types -- see xiom.vdb
// SPEC section 13); no Result[Option[T]] nesting and no `&mut` of a
// struct-return temp (B-21 / B-26).
//
// See SPEC.md for the exact grammar decisions, the error catalogs and the
// documented caps; PROVENANCE.md carries the independent-declaration
// format references.

module xiom.photometrics

use xiom.string;
use xiom.string.compare;
use xiom.math;

// ---------------------------------------------------------------------------
// Constants: IES revision codes, TILT kinds, enumerations, caps
// ---------------------------------------------------------------------------

/// Version code for the 1986 revision ("IESNA:LM-63-1986").
pub const IES_VERSION_1986: Int = 1986;
/// Version code for the 1991 revision (header token "IESNA91").
pub const IES_VERSION_1991: Int = 1991;
/// Version code for the 1995 revision ("IESNA:LM-63-1995").
pub const IES_VERSION_1995: Int = 1995;
/// Version code for the 2002 revision ("IESNA:LM-63-2002").
pub const IES_VERSION_2002: Int = 2002;

/// TILT kind: `TILT=NONE` (no tilt data).
pub const IES_TILT_NONE: Int = 0;
/// TILT kind: `TILT=INCLUDE` (tilt block follows the TILT line).
pub const IES_TILT_INCLUDE: Int = 1;
/// TILT kind: `TILT=<filename>` (external tilt file reference).
pub const IES_TILT_FILE: Int = 2;

/// Photometric type C (1). Angles are stored exactly as written.
pub const IES_TYPE_C: Int = 1;
/// Photometric type B (2).
pub const IES_TYPE_B: Int = 2;
/// Photometric type A (3).
pub const IES_TYPE_A: Int = 3;

/// Units type 1: luminous dimensions in feet.
pub const IES_UNITS_FEET: Int = 1;
/// Units type 2: luminous dimensions in meters.
pub const IES_UNITS_METERS: Int = 2;

/// Documented cap on the vertical/horizontal grid sizes (angles per axis).
pub const IES_MAX_ANGLES: Int = 10000;
/// Documented cap on the candela table size (vertical * horizontal).
pub const IES_MAX_CANDELA: Int = 1000000;
/// Documented cap on the TILT=INCLUDE pair count.
pub const IES_MAX_TILT_PAIRS: Int = 64;

/// IES error code: input has no non-blank line.
pub const IES_ERR_EMPTY: Int = 1;
/// IES error code: the first non-blank line is not an IESNA version header.
pub const IES_ERR_MISSING_VERSION: Int = 2;
/// IES error code: IESNA header does not name a supported revision.
pub const IES_ERR_UNSUPPORTED_VERSION: Int = 3;
/// IES error code: no TILT= line before end of input.
pub const IES_ERR_MISSING_TILT: Int = 4;
/// IES error code: TILT= line is malformed (no "=" or empty value).
pub const IES_ERR_BAD_TILT: Int = 5;
/// IES error code: TILT=INCLUDE data block is malformed or truncated.
pub const IES_ERR_BAD_TILT_BLOCK: Int = 6;
/// IES error code: a numeric line/field is malformed or non-numeric.
pub const IES_ERR_BAD_NUMBER: Int = 7;
/// IES error code: a count is out of its documented range.
pub const IES_ERR_BAD_COUNT: Int = 8;
/// IES error code: fewer angle/candela values than declared.
pub const IES_ERR_TRUNCATED: Int = 9;
/// IES error code: extra numeric data after the candela table.
pub const IES_ERR_TRAILING: Int = 10;
/// IES error code: photometric-type / units-type outside the declared set.
pub const IES_ERR_BAD_ENUM: Int = 11;
/// IES error code: declared candela table exceeds IES_MAX_CANDELA.
pub const IES_ERR_LIMIT: Int = 12;

/// Documented cap on a 3D LUT edge size (entries = size^3).
pub const CUBE_MAX_3D_SIZE: Int = 128;
/// Documented cap on a 1D LUT size (entries = size).
pub const CUBE_MAX_1D_SIZE: Int = 65536;

/// Cube error code: input has no non-blank, non-comment line.
pub const CUBE_ERR_EMPTY: Int = 1;
/// Cube error code: no LUT_1D_SIZE / LUT_3D_SIZE declaration.
pub const CUBE_ERR_MISSING_SIZE: Int = 2;
/// Cube error code: size declared twice (or both dimensions).
pub const CUBE_ERR_DUPLICATE_SIZE: Int = 3;
/// Cube error code: malformed size or size outside the documented range.
pub const CUBE_ERR_BAD_SIZE: Int = 4;
/// Cube error code: malformed/degenerate DOMAIN_MIN/DOMAIN_MAX.
pub const CUBE_ERR_BAD_DOMAIN: Int = 5;
/// Cube error code: DOMAIN_MIN or DOMAIN_MAX repeated.
pub const CUBE_ERR_DUPLICATE_DOMAIN: Int = 6;
/// Cube error code: malformed or duplicate TITLE.
pub const CUBE_ERR_BAD_TITLE: Int = 7;
/// Cube error code: a data line does not hold exactly three numbers.
pub const CUBE_ERR_BAD_DATA: Int = 8;
/// Cube error code: fewer data triples than the declared LUT size.
pub const CUBE_ERR_TRUNCATED: Int = 9;
/// Cube error code: more data triples than the declared LUT size.
pub const CUBE_ERR_TRAILING: Int = 10;
/// Cube error code: unrecognized keyword line.
pub const CUBE_ERR_BAD_KEYWORD: Int = 11;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A parsed IES LM-63 photometric file. All vectors are owned copies in
/// file order. `candela` is plane-major: the value for horizontal index
/// `h` and vertical index `v` lives at `candela[h * num_vertical + v]`
/// (the LM-63 block order: all vertical angles at the first horizontal
/// angle, then all vertical angles at the second, ...). Angles and
/// candela values are stored exactly as read, in degrees and candelas;
/// `candela_multiplier` is kept separate so callers can apply it.
pub type IesDoc = {
  version: Int;                  // IES_VERSION_* code
  keywords: Vec[Str];            // bracketed metadata names (as written)
  keyword_values: Vec[Str];      // parallel values (as written)
  descriptions: Vec[Str];        // non-keyword metadata lines (as written)
  tilt_kind: Int;                // IES_TILT_* code
  tilt_ref: Str;                 // file reference when tilt_kind = FILE, else ""
  tilt_geometry: Int;            // lamp-to-luminaire geometry (INCLUDE only)
  tilt_angles: Vec[Float64];     // INCLUDE angle list
  tilt_factors: Vec[Float64];    // INCLUDE multiplying-factor list
  num_lamps: Int;
  lumens_per_lamp: Float64;
  candela_multiplier: Float64;
  photometric_type: Int;         // 1 = C, 2 = B, 3 = A
  units_type: Int;               // 1 = feet, 2 = meters
  width: Float64;                // luminous opening, file units
  length: Float64;
  height: Float64;
  ballast_factor: Float64;
  ballast_lamp_factor: Float64;  // "future use" in the 1986 revision
  input_watts: Float64;
  vertical_angles: Vec[Float64];
  horizontal_angles: Vec[Float64];
  candela: Vec[Float64];         // num_vertical * num_horizontal values
}

/// A typed IES read error: numeric `code` (IES_ERR_*) plus a message
/// carrying the offending token where useful.
pub type IesError = {
  code: Int;
  message: Str;
}

/// A parsed ".cube" LUT. `data` holds `size` (1D) or `size^3` (3D)
/// consecutive RGB triples in file order; for 3D LUTs the red channel
/// varies fastest, then green, then blue (spec ordering):
/// triple index = r + size * g + size * size * b.
pub type CubeLut = {
  title: Str;                    // "" when absent
  has_title: Bool;
  is_3d: Bool;
  size: Int;                     // 2 <= size <= documented cap
  domain_min: Vec[Float64];      // exactly 3 values (default 0,0,0)
  domain_max: Vec[Float64];      // exactly 3 values (default 1,1,1)
  data: Vec[Float64];            // 3 floats per entry, triple order
}

/// A typed cube read error: numeric `code` (CUBE_ERR_*) plus a message.
pub type CubeError = {
  code: Int;
  message: Str;
}

/// An RGB triple returned by the sampling helpers.
pub type CubeRgb = {
  r: Float64;
  g: Float64;
  b: Float64;
}

/// Internal per-channel interpolation position (not part of the surface).
type LutPos = {
  i0: Int;
  i1: Int;
  t: Float64;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// Strips a UTF-8 BOM (EF BB BF) from the start of `s`.
fn _strip_bom(s: Str) -> Str {
  if s.len() >= 3 {
    if string.byte_at(s, 0) == 239u8 && string.byte_at(s, 1) == 187u8 && string.byte_at(s, 2) == 191u8 {
      return string.str_slice(s, 3, s.len());
    }
  }
  return s;
}

// Parses an Int token; None on any malformed input.
fn _parse_int(s: Str) -> Option[Int] {
  let r = string.str_to_int(s);
  match r {
    Ok(v) => { return Some(v); },
    Err(_) => { return None; },
  }
  return None;
}

// Parses a Float64 token; None on any malformed input.
fn _parse_f64(s: Str) -> Option[Float64] {
  let r = string.str_to_float(s);
  match r {
    Ok(v) => { return Some(v); },
    Err(_) => { return None; },
  }
  return None;
}

// Clamps x into [0, 1].
fn _clamp01(x: Float64) -> Float64 {
  if x < 0.0 { return 0.0; }
  if x > 1.0 { return 1.0; }
  return x;
}

// Linear interpolation between a and b at t (t is expected in [0, 1]).
fn _lerp(a: Float64, b: Float64, t: Float64) -> Float64 {
  return a + (b - a) * t;
}

// ---------------------------------------------------------------------------
// IES LM-63 reader
// ---------------------------------------------------------------------------

fn _err_ies(code: Int, message: Str) -> Result[IesDoc, IesError] {
  return Err(IesError{ code: code; message: message; });
}

/// Parses an IES LM-63 photometric document.
///
/// Accepted revisions (recognized from the first non-blank line, an
/// optional UTF-8 BOM is skipped): "IESNA:LM-63-1986", "IESNA91",
/// "IESNA:LM-63-1995" and "IESNA:LM-63-2002".
///
/// Structure: metadata lines (bracketed `[KEYWORD] value` pairs and free
/// descriptive lines) up to the required `TILT=` line; an optional
/// TILT=INCLUDE block (geometry, pair count, angles, multiplying
/// factors); the 10-value photometric parameter line; the 3-value
/// ballast/watts line; the vertical angle list, the horizontal angle
/// list and the candela table (the last three may continue across any
/// number of lines). Blank lines are ignored everywhere; line endings
/// may be LF or CRLF. The two parameter lines must each hold exactly
/// their value count on one line. Values are stored exactly as read.
///
/// Errors: typed IesError with the IES_ERR_* codes (SPEC.md section 5).
pub fn ies_parse(text: Str) -> Result[IesDoc, IesError] {
  let raw: Vec[Str] = string.lines(text);

  // -- first non-blank line (BOM-tolerant) --------------------------------
  var first_line = "";
  var first_i = -1;
  var i = 0;
  while i < raw.len() {
    let rl0: Str = raw[i];
    var ln0 = string.str_trim(rl0);
    if i == 0 { ln0 = _strip_bom(ln0); }
    if ln0.len() > 0 {
      first_line = ln0;
      first_i = i;
      break;
    }
    i = i + 1;
  }
  if first_i < 0 {
    return _err_ies(IES_ERR_EMPTY, "ies: input has no non-blank line");
  }

  // -- version tag --------------------------------------------------------
  if !string.str_starts_with(first_line, "IESNA") {
    return _err_ies(IES_ERR_MISSING_VERSION, "ies: missing IESNA version header: " + first_line);
  }
  var version = 0;
  if string.str_contains(first_line, "1986") { version = IES_VERSION_1986; }
  elif string.str_contains(first_line, "1991") { version = IES_VERSION_1991; }
  elif string.str_contains(first_line, "1995") { version = IES_VERSION_1995; }
  elif string.str_contains(first_line, "2002") { version = IES_VERSION_2002; }
  elif compare.str_compare(first_line, "IESNA91") == 0 { version = IES_VERSION_1991; }
  if version == 0 {
    return _err_ies(IES_ERR_UNSUPPORTED_VERSION, "ies: unsupported version header: " + first_line);
  }

  // -- metadata up to the TILT= line --------------------------------------
  var kw_names = Vec[Str].new();
  var kw_values = Vec[Str].new();
  var descs = Vec[Str].new();
  var tilt_found = false;
  var tilt_kind = IES_TILT_NONE;
  var tilt_ref = "";
  var scan = first_i + 1;
  while scan < raw.len() {
    let rl: Str = raw[scan];
    let ln = string.str_trim(rl);
    if ln.len() == 0 { scan = scan + 1; continue; }
    let up = string.str_upper(ln);
    var is_tilt_line = false;
    if string.str_starts_with(up, "TILT") {
      if up.len() == 4 {
        is_tilt_line = true;
      } else {
        let nb: UInt8 = string.byte_at(up, 4);
        if nb == 61u8 || nb == 32u8 || nb == 9u8 {
          is_tilt_line = true;
        }
      }
    }
    if is_tilt_line {
      let eq = string.index_of(ln, "=");
      match eq {
        Some(ei) => {
          let val = string.str_trim(string.str_slice(ln, ei + 1, ln.len()));
          let vup = string.str_upper(val);
          if compare.str_compare(vup, "NONE") == 0 {
            tilt_kind = IES_TILT_NONE;
          } elif compare.str_compare(vup, "INCLUDE") == 0 {
            tilt_kind = IES_TILT_INCLUDE;
          } elif val.len() == 0 {
            return _err_ies(IES_ERR_BAD_TILT, "ies: empty TILT= value");
          } else {
            tilt_kind = IES_TILT_FILE;
            tilt_ref = val;
          }
        },
        None => {
          return _err_ies(IES_ERR_BAD_TILT, "ies: TILT line without '='");
        },
      }
      tilt_found = true;
      scan = scan + 1;
      break;
    }
    if string.str_starts_with(ln, "[") {
      let rb = string.index_of(ln, "]");
      match rb {
        Some(bi) => {
          let name = string.str_trim(string.str_slice(ln, 1, bi));
          let val = string.str_trim(string.str_slice(ln, bi + 1, ln.len()));
          kw_names.push(name);
          kw_values.push(val);
        },
        None => {
          descs.push(ln);
        },
      }
    } else {
      descs.push(ln);
    }
    scan = scan + 1;
  }
  if !tilt_found {
    return _err_ies(IES_ERR_MISSING_TILT, "ies: no TILT= line before end of input");
  }

  // -- tokenize the remainder (numeric section) ---------------------------
  var toks = Vec[Str].new();
  var tok_lines = Vec[Int].new();
  var tl = scan;
  while tl < raw.len() {
    let rl2: Str = raw[tl];
    let ln2 = string.str_trim(rl2);
    if ln2.len() > 0 {
      let ws: Vec[Str] = string.words(ln2);
      var wi = 0;
      while wi < ws.len() {
        let wt: Str = ws[wi];
        toks.push(wt);
        tok_lines.push(tl);
        wi = wi + 1;
      }
    }
    tl = tl + 1;
  }

  // -- optional TILT=INCLUDE block ----------------------------------------
  var ti = 0;
  var tilt_geometry = 0;
  var tilt_angles = Vec[Float64].new();
  var tilt_factors = Vec[Float64].new();
  if tilt_kind == IES_TILT_INCLUDE {
    if toks.len() - ti < 2 {
      return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: truncated TILT=INCLUDE block");
    }
    let gtok: Str = toks[ti];
    let pg = _parse_int(gtok);
    match pg {
      Some(g) => { tilt_geometry = g; },
      None => { return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: bad tilt geometry: " + gtok); },
    }
    ti = ti + 1;
    let ctok: Str = toks[ti];
    let pc = _parse_int(ctok);
    var tcount = 0;
    match pc {
      Some(c) => { tcount = c; },
      None => { return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: bad tilt pair count: " + ctok); },
    }
    ti = ti + 1;
    if tilt_geometry < 1 || tilt_geometry > 5 {
      return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: tilt geometry outside 1..5");
    }
    if tcount < 1 || tcount > IES_MAX_TILT_PAIRS {
      return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: tilt pair count outside 1..64");
    }
    if toks.len() - ti < 2 * tcount {
      return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: truncated tilt angle/factor data");
    }
    var ta = 0;
    while ta < tcount {
      let at: Str = toks[ti];
      let pav = _parse_f64(at);
      match pav {
        Some(v) => { tilt_angles.push(v); },
        None => { return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: bad tilt angle: " + at); },
      }
      ti = ti + 1;
      ta = ta + 1;
    }
    var tf = 0;
    while tf < tcount {
      let ft: Str = toks[ti];
      let pfv = _parse_f64(ft);
      match pfv {
        Some(v) => { tilt_factors.push(v); },
        None => { return _err_ies(IES_ERR_BAD_TILT_BLOCK, "ies: bad tilt factor: " + ft); },
      }
      ti = ti + 1;
      tf = tf + 1;
    }
  }

  // -- 10-value photometric parameter line --------------------------------
  if toks.len() - ti < 10 {
    return _err_ies(IES_ERR_TRUNCATED, "ies: truncated photometric parameter line");
  }
  let l_a: Int = tok_lines[ti];
  let l_b: Int = tok_lines[ti + 9];
  if l_a != l_b {
    return _err_ies(IES_ERR_BAD_NUMBER, "ies: photometric parameter line must hold 10 values");
  }
  let t_num_lamps: Str = toks[ti];
  let t_lumens: Str = toks[ti + 1];
  let t_mult: Str = toks[ti + 2];
  let t_nv: Str = toks[ti + 3];
  let t_nh: Str = toks[ti + 4];
  let t_ptype: Str = toks[ti + 5];
  let t_units: Str = toks[ti + 6];
  let t_width: Str = toks[ti + 7];
  let t_len: Str = toks[ti + 8];
  let t_height: Str = toks[ti + 9];
  var num_lamps = 0;
  var lumens_per_lamp = 0.0;
  var candela_multiplier = 0.0;
  var num_vertical = 0;
  var num_horizontal = 0;
  var photometric_type = 0;
  var units_type = 0;
  var width = 0.0;
  var length = 0.0;
  var height = 0.0;
  let p_nl = _parse_int(t_num_lamps);
  match p_nl {
    Some(v) => { num_lamps = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid number of lamps: " + t_num_lamps); },
  }
  let p_lm = _parse_f64(t_lumens);
  match p_lm {
    Some(v) => { lumens_per_lamp = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid lumens/lamp: " + t_lumens); },
  }
  let p_mu = _parse_f64(t_mult);
  match p_mu {
    Some(v) => { candela_multiplier = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid candela multiplier: " + t_mult); },
  }
  let p_nv = _parse_int(t_nv);
  match p_nv {
    Some(v) => { num_vertical = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid vertical-angle count: " + t_nv); },
  }
  let p_nh = _parse_int(t_nh);
  match p_nh {
    Some(v) => { num_horizontal = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid horizontal-angle count: " + t_nh); },
  }
  let p_pt = _parse_int(t_ptype);
  match p_pt {
    Some(v) => { photometric_type = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid photometric type: " + t_ptype); },
  }
  let p_un = _parse_int(t_units);
  match p_un {
    Some(v) => { units_type = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid units type: " + t_units); },
  }
  let p_w = _parse_f64(t_width);
  match p_w {
    Some(v) => { width = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid width: " + t_width); },
  }
  let p_le = _parse_f64(t_len);
  match p_le {
    Some(v) => { length = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid length: " + t_len); },
  }
  let p_he = _parse_f64(t_height);
  match p_he {
    Some(v) => { height = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid height: " + t_height); },
  }
  if num_lamps < 1 {
    return _err_ies(IES_ERR_BAD_COUNT, "ies: number of lamps must be >= 1");
  }
  if num_vertical < 1 || num_vertical > IES_MAX_ANGLES {
    return _err_ies(IES_ERR_BAD_COUNT, "ies: vertical-angle count outside 1..10000");
  }
  if num_horizontal < 1 || num_horizontal > IES_MAX_ANGLES {
    return _err_ies(IES_ERR_BAD_COUNT, "ies: horizontal-angle count outside 1..10000");
  }
  if num_vertical * num_horizontal > IES_MAX_CANDELA {
    return _err_ies(IES_ERR_LIMIT, "ies: candela table exceeds the 1000000-value cap");
  }
  if photometric_type < 1 || photometric_type > 3 {
    return _err_ies(IES_ERR_BAD_ENUM, "ies: photometric type must be 1, 2 or 3");
  }
  if units_type < 1 || units_type > 2 {
    return _err_ies(IES_ERR_BAD_ENUM, "ies: units type must be 1 or 2");
  }
  ti = ti + 10;

  // -- 3-value ballast/watts line -----------------------------------------
  if toks.len() - ti < 3 {
    return _err_ies(IES_ERR_TRUNCATED, "ies: truncated ballast/watts line");
  }
  let l_c: Int = tok_lines[ti];
  let l_d: Int = tok_lines[ti + 2];
  if l_c != l_d {
    return _err_ies(IES_ERR_BAD_NUMBER, "ies: ballast/watts line must hold 3 values");
  }
  let t_bf: Str = toks[ti];
  let t_blf: Str = toks[ti + 1];
  let t_watts: Str = toks[ti + 2];
  var ballast_factor = 0.0;
  var ballast_lamp_factor = 0.0;
  var input_watts = 0.0;
  let p_bf = _parse_f64(t_bf);
  match p_bf {
    Some(v) => { ballast_factor = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid ballast factor: " + t_bf); },
  }
  let p_blf = _parse_f64(t_blf);
  match p_blf {
    Some(v) => { ballast_lamp_factor = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid ballast-lamp factor: " + t_blf); },
  }
  let p_wt = _parse_f64(t_watts);
  match p_wt {
    Some(v) => { input_watts = v; },
    None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid input watts: " + t_watts); },
  }
  ti = ti + 3;

  // -- vertical angles ----------------------------------------------------
  var vert = Vec[Float64].new();
  var vi = 0;
  while vi < num_vertical {
    if ti >= toks.len() {
      return _err_ies(IES_ERR_TRUNCATED, "ies: truncated vertical angle list");
    }
    let vt: Str = toks[ti];
    let pv = _parse_f64(vt);
    match pv {
      Some(v) => { vert.push(v); },
      None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid vertical angle: " + vt); },
    }
    ti = ti + 1;
    vi = vi + 1;
  }

  // -- horizontal angles --------------------------------------------------
  var horiz = Vec[Float64].new();
  var hi = 0;
  while hi < num_horizontal {
    if ti >= toks.len() {
      return _err_ies(IES_ERR_TRUNCATED, "ies: truncated horizontal angle list");
    }
    let ht: Str = toks[ti];
    let ph = _parse_f64(ht);
    match ph {
      Some(v) => { horiz.push(v); },
      None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid horizontal angle: " + ht); },
    }
    ti = ti + 1;
    hi = hi + 1;
  }

  // -- candela table ------------------------------------------------------
  var cvals = Vec[Float64].new();
  var cwant = num_vertical * num_horizontal;
  var ci = 0;
  while ci < cwant {
    if ti >= toks.len() {
      return _err_ies(IES_ERR_TRUNCATED, "ies: truncated candela table");
    }
    let ct: Str = toks[ti];
    let pcv = _parse_f64(ct);
    match pcv {
      Some(v) => { cvals.push(v); },
      None => { return _err_ies(IES_ERR_BAD_NUMBER, "ies: invalid candela value: " + ct); },
    }
    ti = ti + 1;
    ci = ci + 1;
  }
  if ti < toks.len() {
    return _err_ies(IES_ERR_TRAILING, "ies: trailing data after the candela table");
  }

  return Ok(IesDoc{
    version: version;
    keywords: kw_names;
    keyword_values: kw_values;
    descriptions: descs;
    tilt_kind: tilt_kind;
    tilt_ref: tilt_ref;
    tilt_geometry: tilt_geometry;
    tilt_angles: tilt_angles;
    tilt_factors: tilt_factors;
    num_lamps: num_lamps;
    lumens_per_lamp: lumens_per_lamp;
    candela_multiplier: candela_multiplier;
    photometric_type: photometric_type;
    units_type: units_type;
    width: width;
    length: length;
    height: height;
    ballast_factor: ballast_factor;
    ballast_lamp_factor: ballast_lamp_factor;
    input_watts: input_watts;
    vertical_angles: vert;
    horizontal_angles: horiz;
    candela: cvals;
  });
}

// ---------------------------------------------------------------------------
// IES accessors (out-of-range reads return documented defaults, never crash)
// ---------------------------------------------------------------------------

pub fn ies_version(d: &IesDoc) -> Int {
  return d.version;
}

/// Canonical revision label: "IESNA:LM-63-1986", "IESNA91",
/// "IESNA:LM-63-1995" or "IESNA:LM-63-2002".
pub fn ies_version_label(d: &IesDoc) -> Str {
  if d.version == IES_VERSION_1986 { return "IESNA:LM-63-1986"; }
  if d.version == IES_VERSION_1991 { return "IESNA91"; }
  if d.version == IES_VERSION_1995 { return "IESNA:LM-63-1995"; }
  if d.version == IES_VERSION_2002 { return "IESNA:LM-63-2002"; }
  return "";
}

pub fn ies_keyword_count(d: &IesDoc) -> Int {
  return d.keywords.len();
}

pub fn ies_keyword_name(d: &IesDoc, i: Int) -> Str {
  if i < 0 || i >= d.keywords.len() { return ""; }
  let s: Str = d.keywords[i];
  return s;
}

pub fn ies_keyword_value(d: &IesDoc, i: Int) -> Str {
  if i < 0 || i >= d.keyword_values.len() { return ""; }
  let s: Str = d.keyword_values[i];
  return s;
}

/// First keyword whose name matches `name` case-insensitively, or None.
pub fn ies_get_keyword(d: &IesDoc, name: Str) -> Option[Str] {
  var i = 0;
  while i < d.keywords.len() {
    let kn: Str = d.keywords[i];
    if compare.str_compare_ignore_case(kn, name) == 0 {
      let kv: Str = d.keyword_values[i];
      return Some(kv);
    }
    i = i + 1;
  }
  return None;
}

pub fn ies_description_count(d: &IesDoc) -> Int {
  return d.descriptions.len();
}

pub fn ies_description(d: &IesDoc, i: Int) -> Str {
  if i < 0 || i >= d.descriptions.len() { return ""; }
  let s: Str = d.descriptions[i];
  return s;
}

pub fn ies_tilt_kind(d: &IesDoc) -> Int {
  return d.tilt_kind;
}

pub fn ies_tilt_ref(d: &IesDoc) -> Str {
  return d.tilt_ref;
}

pub fn ies_tilt_geometry(d: &IesDoc) -> Int {
  return d.tilt_geometry;
}

pub fn ies_tilt_pair_count(d: &IesDoc) -> Int {
  return d.tilt_angles.len();
}

pub fn ies_tilt_angle(d: &IesDoc, i: Int) -> Float64 {
  if i < 0 || i >= d.tilt_angles.len() { return 0.0; }
  let v: Float64 = d.tilt_angles[i];
  return v;
}

pub fn ies_tilt_factor(d: &IesDoc, i: Int) -> Float64 {
  if i < 0 || i >= d.tilt_factors.len() { return 0.0; }
  let v: Float64 = d.tilt_factors[i];
  return v;
}

pub fn ies_num_lamps(d: &IesDoc) -> Int {
  return d.num_lamps;
}

pub fn ies_lumens_per_lamp(d: &IesDoc) -> Float64 {
  return d.lumens_per_lamp;
}

pub fn ies_candela_multiplier(d: &IesDoc) -> Float64 {
  return d.candela_multiplier;
}

pub fn ies_photometric_type(d: &IesDoc) -> Int {
  return d.photometric_type;
}

pub fn ies_units_type(d: &IesDoc) -> Int {
  return d.units_type;
}

pub fn ies_width(d: &IesDoc) -> Float64 {
  return d.width;
}

pub fn ies_length(d: &IesDoc) -> Float64 {
  return d.length;
}

pub fn ies_height(d: &IesDoc) -> Float64 {
  return d.height;
}

pub fn ies_ballast_factor(d: &IesDoc) -> Float64 {
  return d.ballast_factor;
}

pub fn ies_ballast_lamp_factor(d: &IesDoc) -> Float64 {
  return d.ballast_lamp_factor;
}

pub fn ies_input_watts(d: &IesDoc) -> Float64 {
  return d.input_watts;
}

pub fn ies_vertical_count(d: &IesDoc) -> Int {
  return d.vertical_angles.len();
}

pub fn ies_horizontal_count(d: &IesDoc) -> Int {
  return d.horizontal_angles.len();
}

pub fn ies_vertical_angle(d: &IesDoc, i: Int) -> Float64 {
  if i < 0 || i >= d.vertical_angles.len() { return 0.0; }
  let v: Float64 = d.vertical_angles[i];
  return v;
}

pub fn ies_horizontal_angle(d: &IesDoc, i: Int) -> Float64 {
  if i < 0 || i >= d.horizontal_angles.len() { return 0.0; }
  let v: Float64 = d.horizontal_angles[i];
  return v;
}

pub fn ies_candela_count(d: &IesDoc) -> Int {
  return d.candela.len();
}

/// Raw candela value for horizontal index `h` (file order) and vertical
/// index `v` (file order); 0.0 when either index is out of range.
pub fn ies_candela(d: &IesDoc, h: Int, v: Int) -> Float64 {
  let nv = d.vertical_angles.len();
  let nh = d.horizontal_angles.len();
  if h < 0 || h >= nh || v < 0 || v >= nv { return 0.0; }
  let vv: Float64 = d.candela[h * nv + v];
  return vv;
}

/// Raw candela value multiplied by the file's candela multiplier.
pub fn ies_candela_scaled(d: &IesDoc, h: Int, v: Int) -> Float64 {
  return ies_candela(d, h, v) * d.candela_multiplier;
}

/// Bilinearly interpolated raw candela value for a (vertical angle,
/// horizontal angle) pair in degrees, on the stored grids.
///
/// Vertical axis: clamped to the first/last stored angle. Horizontal
/// axis: when the grid is a closed ring (first angle 0 and last angle
/// 360) it wraps modulo 360, with the duplicate 360 plane excluded from
/// interpolation; otherwise it is clamped. A one-point axis selects that
/// plane. Returns the requested value without the candela multiplier
/// (use `ies_sample_scaled` for measured candelas).
pub fn ies_sample(d: &IesDoc, vert_deg: Float64, horiz_deg: Float64) -> Float64 {
  let nv = d.vertical_angles.len();
  let nh = d.horizontal_angles.len();
  if nv < 1 || nh < 1 { return 0.0; }

  // vertical segment: j0/tv
  var j0 = 0;
  var tv = 0.0;
  if nv == 1 {
    j0 = 0;
    tv = 0.0;
  } else {
    let v0: Float64 = d.vertical_angles[0];
    let v1: Float64 = d.vertical_angles[nv - 1];
    if vert_deg <= v0 {
      j0 = 0;
      tv = 0.0;
    } elif vert_deg >= v1 {
      j0 = nv - 2;
      tv = 1.0;
    } else {
      var j = 0;
      while j < nv - 1 {
        let a: Float64 = d.vertical_angles[j];
        let b: Float64 = d.vertical_angles[j + 1];
        if vert_deg >= a && vert_deg <= b {
          j0 = j;
          if b > a { tv = (vert_deg - a) / (b - a); } else { tv = 0.0; }
          break;
        }
        j = j + 1;
      }
    }
  }

  // horizontal segment: k0/th, ring-aware
  var nh_eff = nh;
  let h_first: Float64 = d.horizontal_angles[0];
  let h_last: Float64 = d.horizontal_angles[nh - 1];
  var ring = false;
  if nh >= 2 && h_first == 0.0 && h_last >= 359.999 {
    ring = true;
    nh_eff = nh - 1;
  }
  var k0 = 0;
  var th = 0.0;
  if nh_eff <= 1 {
    k0 = 0;
    th = 0.0;
  } else {
    var hx = horiz_deg;
    if ring {
      while hx < 0.0 { hx = hx + 360.0; }
      while hx >= 360.0 { hx = hx - 360.0; }
    }
    let h0e: Float64 = d.horizontal_angles[0];
    let hle: Float64 = d.horizontal_angles[nh_eff - 1];
    if hx <= h0e {
      k0 = 0;
      th = 0.0;
    } elif hx >= hle && !ring {
      k0 = nh_eff - 2;
      th = 1.0;
    } else {
      var k = 0;
      while k < nh_eff {
        let a: Float64 = d.horizontal_angles[k];
        let kn = (k + 1) % nh_eff;
        var b: Float64 = d.horizontal_angles[kn];
        if kn == 0 { b = b + 360.0; }
        var xx = hx;
        if b > 360.0 && xx < a { xx = xx + 360.0; }
        if xx >= a && xx <= b {
          k0 = k;
          if b > a { th = (xx - a) / (b - a); } else { th = 0.0; }
          break;
        }
        k = k + 1;
      }
    }
  }

  var j1 = j0;
  if nv > 1 { j1 = j0 + 1; }
  var k1 = k0;
  if nh_eff > 1 { k1 = (k0 + 1) % nh_eff; }
  let c00: Float64 = d.candela[k0 * nv + j0];
  let c01: Float64 = d.candela[k0 * nv + j1];
  let c10: Float64 = d.candela[k1 * nv + j0];
  let c11: Float64 = d.candela[k1 * nv + j1];
  let r0 = _lerp(c00, c01, tv);
  let r1 = _lerp(c10, c11, tv);
  return _lerp(r0, r1, th);
}

/// `ies_sample` multiplied by the file's candela multiplier.
pub fn ies_sample_scaled(d: &IesDoc, vert_deg: Float64, horiz_deg: Float64) -> Float64 {
  return ies_sample(d, vert_deg, horiz_deg) * d.candela_multiplier;
}

// ---------------------------------------------------------------------------
// .cube LUT reader
// ---------------------------------------------------------------------------

fn _err_cube(code: Int, message: Str) -> Result[CubeLut, CubeError] {
  return Err(CubeError{ code: code; message: message; });
}

/// Parses an Adobe ".cube" 1D/3D LUT document.
///
/// Grammar: `#` comment lines and blank lines are ignored; `TITLE "<text>"`
/// (optional, single); exactly one of `LUT_1D_SIZE <n>` / `LUT_3D_SIZE <n>`
/// (required, n >= 2); optional `DOMAIN_MIN <r> <g> <b>` and
/// `DOMAIN_MAX <r> <g> <b>` (each at most once, default 0 0 0 / 1 1 1);
/// then exactly `n` (1D) or `n^3` (3D) RGB data triples, three floats per
/// line. For 3D LUTs the red channel varies fastest, then green, then
/// blue. A UTF-8 BOM is skipped. Values are stored exactly as read.
///
/// Errors: typed CubeError with the CUBE_ERR_* codes (SPEC.md section 5).
pub fn cube_parse(text: Str) -> Result[CubeLut, CubeError] {
  let raw: Vec[Str] = string.lines(text);

  var title = "";
  var has_title = false;
  var dim = 0;
  var size = 0;
  var have_size = false;
  var dmn0 = 0.0;
  var dmn1 = 0.0;
  var dmn2 = 0.0;
  var dmx0 = 1.0;
  var dmx1 = 1.0;
  var dmx2 = 1.0;
  var have_dmin = false;
  var have_dmax = false;
  var data = Vec[Float64].new();
  var saw_content = false;

  var li = 0;
  while li < raw.len() {
    let rl: Str = raw[li];
    var ln = string.str_trim(rl);
    if li == 0 { ln = _strip_bom(ln); }
    if ln.len() == 0 { li = li + 1; continue; }
    if string.str_starts_with(ln, "#") { li = li + 1; continue; }
    saw_content = true;
    let ws: Vec[Str] = string.words(ln);
    let kw: Str = ws[0];
    let kup = string.str_upper(kw);

    if compare.str_compare(kup, "TITLE") == 0 {
      if has_title {
        return _err_cube(CUBE_ERR_BAD_TITLE, "cube: duplicate TITLE");
      }
      let q1 = string.index_of(ln, "\"");
      match q1 {
        Some(a) => {
          let q2 = string.last_index_of(ln, "\"");
          match q2 {
            Some(b) => {
              if b <= a {
                return _err_cube(CUBE_ERR_BAD_TITLE, "cube: TITLE needs a quoted string");
              }
              title = string.str_slice(ln, a + 1, b);
              has_title = true;
            },
            None => {
              return _err_cube(CUBE_ERR_BAD_TITLE, "cube: unterminated TITLE quote");
            },
          }
        },
        None => {
          return _err_cube(CUBE_ERR_BAD_TITLE, "cube: TITLE needs a quoted string");
        },
      }
    } elif compare.str_compare(kup, "LUT_1D_SIZE") == 0 || compare.str_compare(kup, "LUT_3D_SIZE") == 0 {
      if have_size {
        return _err_cube(CUBE_ERR_DUPLICATE_SIZE, "cube: LUT size declared more than once");
      }
      if ws.len() != 2 {
        return _err_cube(CUBE_ERR_BAD_SIZE, "cube: LUT size declaration needs one integer");
      }
      let st: Str = ws[1];
      let ps = _parse_int(st);
      match ps {
        Some(sz) => { size = sz; },
        None => { return _err_cube(CUBE_ERR_BAD_SIZE, "cube: invalid LUT size: " + st); },
      }
      if compare.str_compare(kup, "LUT_3D_SIZE") == 0 { dim = 3; } else { dim = 1; }
      if dim == 3 {
        if size < 2 || size > CUBE_MAX_3D_SIZE {
          return _err_cube(CUBE_ERR_BAD_SIZE, "cube: 3D LUT size outside 2..128");
        }
      } else {
        if size < 2 || size > CUBE_MAX_1D_SIZE {
          return _err_cube(CUBE_ERR_BAD_SIZE, "cube: 1D LUT size outside 2..65536");
        }
      }
      have_size = true;
    } elif compare.str_compare(kup, "DOMAIN_MIN") == 0 || compare.str_compare(kup, "DOMAIN_MAX") == 0 {
      if compare.str_compare(kup, "DOMAIN_MIN") == 0 && have_dmin {
        return _err_cube(CUBE_ERR_DUPLICATE_DOMAIN, "cube: duplicate DOMAIN_MIN");
      }
      if compare.str_compare(kup, "DOMAIN_MAX") == 0 && have_dmax {
        return _err_cube(CUBE_ERR_DUPLICATE_DOMAIN, "cube: duplicate DOMAIN_MAX");
      }
      if ws.len() != 4 {
        return _err_cube(CUBE_ERR_BAD_DOMAIN, "cube: DOMAIN_MIN/DOMAIN_MAX need three values");
      }
      let dt0: Str = ws[1];
      let dt1: Str = ws[2];
      let dt2: Str = ws[3];
      let p0 = _parse_f64(dt0);
      let p1 = _parse_f64(dt1);
      let p2 = _parse_f64(dt2);
      var v0 = 0.0;
      var v1 = 0.0;
      var v2 = 0.0;
      match p0 {
        Some(v) => { v0 = v; },
        None => { return _err_cube(CUBE_ERR_BAD_DOMAIN, "cube: invalid domain value: " + dt0); },
      }
      match p1 {
        Some(v) => { v1 = v; },
        None => { return _err_cube(CUBE_ERR_BAD_DOMAIN, "cube: invalid domain value: " + dt1); },
      }
      match p2 {
        Some(v) => { v2 = v; },
        None => { return _err_cube(CUBE_ERR_BAD_DOMAIN, "cube: invalid domain value: " + dt2); },
      }
      if compare.str_compare(kup, "DOMAIN_MIN") == 0 {
        dmn0 = v0; dmn1 = v1; dmn2 = v2;
        have_dmin = true;
      } else {
        dmx0 = v0; dmx1 = v1; dmx2 = v2;
        have_dmax = true;
      }
    } else {
      let pf = _parse_f64(kw);
      match pf {
        Some(v0) => {
          if ws.len() != 3 {
            return _err_cube(CUBE_ERR_BAD_DATA, "cube: data line must hold three values");
          }
          let dt1: Str = ws[1];
          let dt2: Str = ws[2];
          let p1 = _parse_f64(dt1);
          let p2 = _parse_f64(dt2);
          var v1 = 0.0;
          var v2 = 0.0;
          match p1 {
            Some(v) => { v1 = v; },
            None => { return _err_cube(CUBE_ERR_BAD_DATA, "cube: invalid data value: " + dt1); },
          }
          match p2 {
            Some(v) => { v2 = v; },
            None => { return _err_cube(CUBE_ERR_BAD_DATA, "cube: invalid data value: " + dt2); },
          }
          data.push(v0);
          data.push(v1);
          data.push(v2);
        },
        None => {
          return _err_cube(CUBE_ERR_BAD_KEYWORD, "cube: unknown keyword or invalid data: " + kw);
        },
      }
    }
    li = li + 1;
  }

  if !saw_content {
    return _err_cube(CUBE_ERR_EMPTY, "cube: input has no non-blank, non-comment line");
  }
  if !have_size {
    return _err_cube(CUBE_ERR_MISSING_SIZE, "cube: no LUT_1D_SIZE or LUT_3D_SIZE declaration");
  }
  if dmn0 >= dmx0 || dmn1 >= dmx1 || dmn2 >= dmx2 {
    return _err_cube(CUBE_ERR_BAD_DOMAIN, "cube: DOMAIN_MIN must be below DOMAIN_MAX");
  }
  var want = size;
  if dim == 3 { want = size * size * size; }
  let entries = data.len() / 3;
  if entries < want {
    return _err_cube(CUBE_ERR_TRUNCATED, "cube: fewer data triples than the declared LUT size");
  }
  if entries > want {
    return _err_cube(CUBE_ERR_TRAILING, "cube: more data triples than the declared LUT size");
  }

  var dmin_v = Vec[Float64].new();
  dmin_v.push(dmn0); dmin_v.push(dmn1); dmin_v.push(dmn2);
  var dmax_v = Vec[Float64].new();
  dmax_v.push(dmx0); dmax_v.push(dmx1); dmax_v.push(dmx2);
  let is3d = dim == 3;
  return Ok(CubeLut{
    title: title;
    has_title: has_title;
    is_3d: is3d;
    size: size;
    domain_min: dmin_v;
    domain_max: dmax_v;
    data: data;
  });
}

// ---------------------------------------------------------------------------
// .cube accessors and sampling
// ---------------------------------------------------------------------------

pub fn cube_title(d: &CubeLut) -> Str {
  return d.title;
}

pub fn cube_has_title(d: &CubeLut) -> Bool {
  return d.has_title;
}

pub fn cube_is_3d(d: &CubeLut) -> Bool {
  return d.is_3d;
}

pub fn cube_dim(d: &CubeLut) -> Int {
  if d.is_3d { return 3; }
  return 1;
}

pub fn cube_size(d: &CubeLut) -> Int {
  return d.size;
}

pub fn cube_domain_min(d: &CubeLut, c: Int) -> Float64 {
  if c < 0 || c >= 3 { return 0.0; }
  let v: Float64 = d.domain_min[c];
  return v;
}

pub fn cube_domain_max(d: &CubeLut, c: Int) -> Float64 {
  if c < 0 || c >= 3 { return 0.0; }
  let v: Float64 = d.domain_max[c];
  return v;
}

/// Number of RGB triples stored (size for 1D LUTs, size^3 for 3D).
pub fn cube_entry_count(d: &CubeLut) -> Int {
  return d.data.len() / 3;
}

/// One float of triple `i` (channel 0..2); 0.0 when out of range.
pub fn cube_value(d: &CubeLut, i: Int, c: Int) -> Float64 {
  if i < 0 || c < 0 || c >= 3 { return 0.0; }
  if i >= cube_entry_count(d) { return 0.0; }
  let v: Float64 = d.data[i * 3 + c];
  return v;
}

/// Triple `i` as an RGB struct; (0,0,0) when out of range.
pub fn cube_entry(d: &CubeLut, i: Int) -> CubeRgb {
  if i < 0 || i >= cube_entry_count(d) {
    return CubeRgb{ r: 0.0; g: 0.0; b: 0.0; };
  }
  let r: Float64 = d.data[i * 3];
  let g: Float64 = d.data[i * 3 + 1];
  let b: Float64 = d.data[i * 3 + 2];
  return CubeRgb{ r: r; g: g; b: b; };
}

/// Flat triple index of grid corner (r, g, b) for a 3D LUT
/// (index = r + size * g + size^2 * b); -1 when out of range or 1D.
pub fn cube_3d_index(d: &CubeLut, r: Int, g: Int, b: Int) -> Int {
  if !d.is_3d { return -1; }
  let n = d.size;
  if r < 0 || r >= n || g < 0 || g >= n || b < 0 || b >= n { return -1; }
  return r + n * g + n * n * b;
}

// Position of x on a channel's uniform grid (domain mapped to [0, 1],
// clamped; none of the results are ever out of range).
fn _lut_pos(d: &CubeLut, c: Int, x: Float64) -> LutPos {
  let lo: Float64 = d.domain_min[c];
  let hi: Float64 = d.domain_max[c];
  var u = 0.0;
  if hi > lo { u = (x - lo) / (hi - lo); }
  u = _clamp01(u);
  let n = d.size;
  let nm1: Float64 = (n - 1) as Float64;
  let p = u * nm1;
  let f = math.floor(p);
  var i0 = f as Int;
  if i0 < 0 { i0 = 0; }
  if i0 > n - 1 { i0 = n - 1; }
  var i1 = i0 + 1;
  if i1 > n - 1 { i1 = n - 1; }
  let t = p - f;
  return LutPos{ i0: i0; i1: i1; t: t; };
}

fn _cube_at(d: &CubeLut, i: Int, j: Int, k: Int, c: Int) -> Float64 {
  let n = d.size;
  let idx = i + n * j + n * n * k;
  let v: Float64 = d.data[idx * 3 + c];
  return v;
}

// Trilinear interpolation for channel c over the corner cube
// (i0/i1, j0/j1, k0/k1) with fractions tr/tg/tb.
fn _tri(d: &CubeLut, i0: Int, i1: Int, j0: Int, j1: Int, k0: Int, k1: Int, tr: Float64, tg: Float64, tb: Float64, c: Int) -> Float64 {
  let v000 = _cube_at(d, i0, j0, k0, c);
  let v100 = _cube_at(d, i1, j0, k0, c);
  let v010 = _cube_at(d, i0, j1, k0, c);
  let v110 = _cube_at(d, i1, j1, k0, c);
  let v001 = _cube_at(d, i0, j0, k1, c);
  let v101 = _cube_at(d, i1, j0, k1, c);
  let v011 = _cube_at(d, i0, j1, k1, c);
  let v111 = _cube_at(d, i1, j1, k1, c);
  let x00 = _lerp(v000, v100, tr);
  let x10 = _lerp(v010, v110, tr);
  let x01 = _lerp(v001, v101, tr);
  let x11 = _lerp(v011, v111, tr);
  let y0 = _lerp(x00, x10, tg);
  let y1 = _lerp(x01, x11, tg);
  return _lerp(y0, y1, tb);
}

// Linear (per-channel) interpolation for a 1D LUT channel c at x.
fn _cube_1d(d: &CubeLut, c: Int, x: Float64) -> Float64 {
  let pos = _lut_pos(d, c, x);
  let a: Float64 = d.data[pos.i0 * 3 + c];
  let b: Float64 = d.data[pos.i1 * 3 + c];
  return _lerp(a, b, pos.t);
}

/// Trilinearly interpolated output triple of a 3D LUT for input (r, g, b)
/// in the LUT's declared domain. Inputs are clamped to the domain; a 1D
/// LUT or an out-of-range channel yields (0, 0, 0).
pub fn cube_sample_3d(d: &CubeLut, r: Float64, g: Float64, b: Float64) -> CubeRgb {
  if !d.is_3d {
    return CubeRgb{ r: 0.0; g: 0.0; b: 0.0; };
  }
  let pr = _lut_pos(d, 0, r);
  let pg = _lut_pos(d, 1, g);
  let pb = _lut_pos(d, 2, b);
  let cr = _tri(d, pr.i0, pr.i1, pg.i0, pg.i1, pb.i0, pb.i1, pr.t, pg.t, pb.t, 0);
  let cg = _tri(d, pr.i0, pr.i1, pg.i0, pg.i1, pb.i0, pb.i1, pr.t, pg.t, pb.t, 1);
  let cb = _tri(d, pr.i0, pr.i1, pg.i0, pg.i1, pb.i0, pb.i1, pr.t, pg.t, pb.t, 2);
  return CubeRgb{ r: cr; g: cg; b: cb; };
}

/// Linearly interpolated output of a 1D LUT channel `c` (0..2) at x,
/// with x mapped through the channel's declared domain and clamped.
/// Returns 0.0 for a 3D LUT or an out-of-range channel.
pub fn cube_sample_1d(d: &CubeLut, c: Int, x: Float64) -> Float64 {
  if d.is_3d { return 0.0; }
  if c < 0 || c >= 3 { return 0.0; }
  return _cube_1d(d, c, x);
}
