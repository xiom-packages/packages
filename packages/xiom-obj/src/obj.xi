// XIOM -- xiom.obj: Wavefront OBJ geometry parsing (vertices, polygon faces)
// Port task: greenfield pure-XIOM Wavefront OBJ subset parser (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Supported records: `v x y z` (an optional w and any further tokens are
//   ignored) and `f i j k...` polygons. Ignored records: vt, vn, vp, g, o, s,
//   usemtl, mtllib. `#` starts a comment that runs to the end of the line and
//   blank lines are ignored. Any other record keyword is an error.
// - Coordinates are never floats: a byte-wise decimal parser computes
//   trunc(value * scale) directly into Int (no Float64 vectors, which this
//   compiler does not support). At most 12 integer digits and 9 fraction
//   digits are accepted; truncation is toward zero.
// - A face reference may be written n, n/t, n//n or n/t/n; the texture and
//   normal parts are parsed for well-formedness and then discarded. Positive
//   indices are 1-based; negative indices are relative to the vertex count at
//   the time the face line is read (0-based result = count + n). Indices are
//   resolved when the face is read, so a face cannot reference later vertices.
// - Polygons keep their original vertex count (no triangulation) and are
//   packed flat: face f owns face_indices[face_starts[f]..face_ends[f]].
//
// v0.61.3 notes that shaped this module: free functions only (no self
// methods, no lambdas, no Vec[StructType], no Vec[fn]); Ok/Err for
// Result[ObjMesh, Str] are constructed only in the leaf helpers
// _obj_ok_mesh/_obj_err_mesh; Str values read from Vec[Str] elements are
// compared with xiom.string.compare.str_compare (BUG 17); bytes widen through
// (string.byte_at(s, i) as Int) & 0xFF; every Vec element read is bound with
// an explicit type; private helpers signal failure with an error message or
// "" (empty means success), so no Result plumbing is needed off the public
// boundary.

module xiom.obj

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Parsed OBJ geometry: one entry per v record plus one entry per f record.
/// Vertex i is (xs[i], ys[i], zs[i]) in scaled units. Face f spans
/// face_indices[face_starts[f]..face_ends[f]]; every stored index is 0-based
/// and was in range when the face line was read.
pub type ObjMesh = {
  xs: Vec[Int];
  ys: Vec[Int];
  zs: Vec[Int];
  face_starts: Vec[Int];
  face_ends: Vec[Int];
  face_indices: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[ObjMesh, Str].
fn _obj_ok_mesh(m: ObjMesh) -> Result[ObjMesh, Str] {
  return Ok(m);
}

// Err(m) for Result[ObjMesh, Str].
fn _obj_err_mesh(m: Str) -> Result[ObjMesh, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _OBJ_TAB: Int = 9;
const _OBJ_LF: Int = 10;
const _OBJ_CR: Int = 13;
const _OBJ_SPACE: Int = 32;
const _OBJ_HASH: Int = 35;
const _OBJ_PLUS: Int = 43;
const _OBJ_MINUS: Int = 45;
const _OBJ_DOT: Int = 46;
const _OBJ_SLASH: Int = 47;
const _OBJ_DIGIT0: Int = 48;
const _OBJ_DIGIT9: Int = 57;

// Coordinate digit limits (see SPEC.md section 4): 12 integer digits and 9
// fraction digits keep ipart * scale + fraction-term inside Int64 for any
// accepted scale.
const _OBJ_MAX_INT_DIGITS: Int = 12;
const _OBJ_MAX_FRAC_DIGITS: Int = 9;
// Face reference digit limit: values are compared against the vertex count.
const _OBJ_MAX_INDEX_DIGITS: Int = 9;
// Scale range: 1..=1000000.
const _OBJ_MAX_SCALE: Int = 1000000;

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _obj_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII decimal digit byte.
fn _obj_is_digit(b: Int) -> Bool {
  return b >= _OBJ_DIGIT0 && b <= _OBJ_DIGIT9;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse a Wavefront OBJ document into scaled integer geometry.
/// Params: text - the OBJ text; scale - integer units per coordinate unit
/// (e.g. 1000 for milli-units), in 1..=1000000, applied to x, y and z.
/// Returns: Ok(ObjMesh) with one entry per v record and one face per f record,
/// in source order. Coordinates are trunc(value * scale) with truncation
/// toward zero; faces keep their original vertex count (no triangulation) and
/// store 0-based resolved vertex indices.
/// Error case: Err("obj: scale out of range") when scale < 1 or > 1000000;
/// Err("obj: malformed vertex at line N"), Err("obj: malformed face at line
/// N"), Err("obj: index out of range at line N") or Err("obj: unknown record
/// at line N"), where N is the 1-based physical line number (blank and
/// comment lines count).
/// Complexity: O(text bytes).
pub fn obj_parse(text: Str, scale: Int) -> Result[ObjMesh, Str] {
  if scale < 1 || scale > _OBJ_MAX_SCALE {
    return _obj_err_mesh("obj: scale out of range");
  }
  var mesh = ObjMesh{
    xs: Vec[Int].new();
    ys: Vec[Int].new();
    zs: Vec[Int].new();
    face_starts: Vec[Int].new();
    face_ends: Vec[Int].new();
    face_indices: Vec[Int].new();
  };
  let n = text.len();
  var pos = 0;
  var line_no = 0;
  while pos < n {
    line_no = line_no + 1;
    var line_end = pos;
    while line_end < n {
      if _obj_byte(text, line_end) == _OBJ_LF {
        break;
      }
      line_end = line_end + 1;
    }
    var content_end = line_end;
    if content_end > pos && _obj_byte(text, content_end - 1) == _OBJ_CR {
      content_end = content_end - 1;
    }
    let err = _obj_line(text, pos, content_end, scale, line_no, &mut mesh);
    if err.len() > 0 {
      return _obj_err_mesh(err);
    }
    pos = line_end + 1;
  }
  return _obj_ok_mesh(mesh);
}

/// Number of vertices in `m` (one per v record).
/// Params: m - the mesh, read only.
/// Returns: xs.len(); 0 for an empty mesh.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_vertex_count(m: &ObjMesh) -> Int {
  return m.xs.len();
}

/// Number of faces in `m` (one per f record).
/// Params: m - the mesh, read only.
/// Returns: face_starts.len(); 0 for an empty mesh.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_face_count(m: &ObjMesh) -> Int {
  return m.face_starts.len();
}

/// X coordinate of vertex `i`, in scaled units.
/// Params: m - the mesh, read only; i - the zero-based vertex index.
/// Returns: the scaled x; 0 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_vertex_x(m: &ObjMesh, i: Int) -> Int {
  if i < 0 || i >= m.xs.len() {
    return 0;
  }
  let v: Int = m.xs[i];
  return v;
}

/// Y coordinate of vertex `i`, in scaled units.
/// Params: m - the mesh, read only; i - the zero-based vertex index.
/// Returns: the scaled y; 0 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_vertex_y(m: &ObjMesh, i: Int) -> Int {
  if i < 0 || i >= m.ys.len() {
    return 0;
  }
  let v: Int = m.ys[i];
  return v;
}

/// Z coordinate of vertex `i`, in scaled units.
/// Params: m - the mesh, read only; i - the zero-based vertex index.
/// Returns: the scaled z; 0 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_vertex_z(m: &ObjMesh, i: Int) -> Int {
  if i < 0 || i >= m.zs.len() {
    return 0;
  }
  let v: Int = m.zs[i];
  return v;
}

/// Number of vertices in face `f` (its original polygon length).
/// Params: m - the mesh, read only; f - the zero-based face index.
/// Returns: face_ends[f] - face_starts[f]; 0 when `f` is negative or out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_face_len(m: &ObjMesh, f: Int) -> Int {
  if f < 0 || f >= m.face_starts.len() {
    return 0;
  }
  if f >= m.face_ends.len() {
    return 0;
  }
  let s: Int = m.face_starts[f];
  let e: Int = m.face_ends[f];
  return e - s;
}

/// Resolved vertex index of slot `j` in face `f`.
/// Params: m - the mesh, read only; f - the zero-based face index; j - the
/// zero-based position inside the face.
/// Returns: the 0-based vertex index stored at face_indices[
/// face_starts[f] + j]; -1 when `f`, `j` or the packed storage is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn obj_face_index(m: &ObjMesh, f: Int, j: Int) -> Int {
  let len = obj_face_len(m, f);
  if j < 0 || j >= len {
    return -1;
  }
  let s: Int = m.face_starts[f];
  let at = s + j;
  if at < 0 || at >= m.face_indices.len() {
    return -1;
  }
  let idx: Int = m.face_indices[at];
  return idx;
}

// --------------------------------------------------
//  Private helpers
// --------------------------------------------------

// First '#' byte in text[start..end), or end when the line has no comment.
// Everything from that byte to the end of the line is a comment.
fn _obj_comment_start(text: Str, start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    if _obj_byte(text, i) == _OBJ_HASH {
      return i;
    }
    i = i + 1;
  }
  return end;
}

// Split text[start..end) into whitespace-separated tokens (space and TAB
// separate; every other byte is token data). An empty range yields no tokens.
fn _obj_tokens(text: Str, start: Int, end: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = start;
  while i < end {
    let b = _obj_byte(text, i);
    if b == _OBJ_SPACE || b == _OBJ_TAB {
      i = i + 1;
    } else {
      var j = i;
      while j < end {
        let c = _obj_byte(text, j);
        if c == _OBJ_SPACE || c == _OBJ_TAB {
          break;
        }
        j = j + 1;
      }
      out.push(string.str_slice(text, i, j));
      i = j;
    }
  }
  return out;
}

// True for the record keywords whose payload is skipped verbatim.
fn _obj_ignored(kw: Str) -> Bool {
  if compare.str_compare(kw, "vt") == 0 { return true; }
  if compare.str_compare(kw, "vn") == 0 { return true; }
  if compare.str_compare(kw, "vp") == 0 { return true; }
  if compare.str_compare(kw, "g") == 0 { return true; }
  if compare.str_compare(kw, "o") == 0 { return true; }
  if compare.str_compare(kw, "s") == 0 { return true; }
  if compare.str_compare(kw, "usemtl") == 0 { return true; }
  if compare.str_compare(kw, "mtllib") == 0 { return true; }
  return false;
}

// 10^k for 0 <= k <= _OBJ_MAX_FRAC_DIGITS.
fn _obj_pow10(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 10;
    i = i + 1;
  }
  return p;
}

// Parse one coordinate token into trunc(value * scale), or None when the
// token is not a decimal with at most _OBJ_MAX_INT_DIGITS integer digits and
// at most _OBJ_MAX_FRAC_DIGITS fraction digits. Grammar:
//   sign   = "+" | "-" | ""
//   number = sign, 0..12 integer digits, optional ".", 0..9 fraction digits,
//            with at least one digit overall.
// The fraction is folded in as (fraction * scale) / 10^digits, an integer
// division that truncates the discarded tail toward zero; the sign is applied
// afterwards, so truncation is symmetric about zero.
fn _obj_parse_scaled(tok: Str, scale: Int) -> Option[Int] {
  let n = tok.len();
  if n == 0 {
    return None;
  }
  var i = 0;
  var neg = false;
  let b0 = _obj_byte(tok, 0);
  if b0 == _OBJ_MINUS {
    neg = true;
    i = 1;
  } elif b0 == _OBJ_PLUS {
    i = 1;
  }
  var ipart = 0;
  var idigits = 0;
  while i < n {
    let b = _obj_byte(tok, i);
    if !_obj_is_digit(b) {
      break;
    }
    idigits = idigits + 1;
    if idigits > _OBJ_MAX_INT_DIGITS {
      return None;
    }
    ipart = ipart * 10 + (b - _OBJ_DIGIT0);
    i = i + 1;
  }
  var fpart = 0;
  var fdigits = 0;
  if i < n && _obj_byte(tok, i) == _OBJ_DOT {
    i = i + 1;
    while i < n {
      let b = _obj_byte(tok, i);
      if !_obj_is_digit(b) {
        break;
      }
      fdigits = fdigits + 1;
      if fdigits > _OBJ_MAX_FRAC_DIGITS {
        return None;
      }
      fpart = fpart * 10 + (b - _OBJ_DIGIT0);
      i = i + 1;
    }
  }
  if i != n {
    return None;
  }
  if idigits == 0 && fdigits == 0 {
    return None;
  }
  var scaled = ipart * scale;
  if fdigits > 0 {
    scaled = scaled + (fpart * scale) / _obj_pow10(fdigits);
  }
  if neg {
    return Some(0 - scaled);
  }
  return Some(scaled);
}

// Index of the first byte after a run of 1.._OBJ_MAX_INDEX_DIGITS digits
// starting at `from`, or -1 when there is no digit or the run is too long.
fn _obj_skip_index_digits(tok: Str, from: Int) -> Int {
  let n = tok.len();
  var i = from;
  var digits = 0;
  while i < n {
    if !_obj_is_digit(_obj_byte(tok, i)) {
      break;
    }
    digits = digits + 1;
    if digits > _OBJ_MAX_INDEX_DIGITS {
      return -1;
    }
    i = i + 1;
  }
  if digits == 0 {
    return -1;
  }
  return i;
}

// Parse one face reference token into its signed 1-based vertex number, or
// None when the token is malformed. Accepted forms: n, n/t, n//n, n/t/n where
// every part is an optional sign plus 1.._OBJ_MAX_INDEX_DIGITS digits; the
// texture and normal parts are validated but discarded.
fn _obj_index_core(tok: Str) -> Option[Int] {
  let n = tok.len();
  if n == 0 {
    return None;
  }
  var i = 0;
  var neg = false;
  let b0 = _obj_byte(tok, 0);
  if b0 == _OBJ_MINUS {
    neg = true;
    i = 1;
  } elif b0 == _OBJ_PLUS {
    i = 1;
  }
  let dstart = i;
  var value = 0;
  var digits = 0;
  while i < n {
    let b = _obj_byte(tok, i);
    if !_obj_is_digit(b) {
      break;
    }
    digits = digits + 1;
    if digits > _OBJ_MAX_INDEX_DIGITS {
      return None;
    }
    value = value * 10 + (b - _OBJ_DIGIT0);
    i = i + 1;
  }
  if i == dstart {
    return None;
  }
  if i < n {
    if _obj_byte(tok, i) != _OBJ_SLASH {
      return None;
    }
    i = i + 1;
    if i < n && _obj_byte(tok, i) == _OBJ_SLASH {
      // n//n: the normal part is required after the doubled slash.
      i = i + 1;
      let after = _obj_skip_index_digits(tok, i);
      if after < 0 {
        return None;
      }
      i = after;
    } else {
      // n/t with an optional /n suffix.
      let after = _obj_skip_index_digits(tok, i);
      if after < 0 {
        return None;
      }
      i = after;
      if i < n && _obj_byte(tok, i) == _OBJ_SLASH {
        i = i + 1;
        let after2 = _obj_skip_index_digits(tok, i);
        if after2 < 0 {
          return None;
        }
        i = after2;
      }
    }
  }
  if i != n {
    return None;
  }
  if neg {
    return Some(0 - value);
  }
  return Some(value);
}

// Append one vertex from a "v x y z ..." token list; further tokens (the
// optional w, vertex colors) are ignored. Returns "" or the error message.
fn _obj_vertex(tokens: &Vec[Str], scale: Int, line_no: Int, mesh: &mut ObjMesh) -> Str {
  if tokens.len() < 4 {
    return "obj: malformed vertex at line " + int_to_string(line_no);
  }
  let tx: Str = tokens[1];
  let x = _obj_parse_scaled(tx, scale);
  match x {
    Some(v) => { mesh.xs.push(v); },
    None => { return "obj: malformed vertex at line " + int_to_string(line_no); },
  }
  let ty: Str = tokens[2];
  let y = _obj_parse_scaled(ty, scale);
  match y {
    Some(v) => { mesh.ys.push(v); },
    None => { return "obj: malformed vertex at line " + int_to_string(line_no); },
  }
  let tz: Str = tokens[3];
  let z = _obj_parse_scaled(tz, scale);
  match z {
    Some(v) => { mesh.zs.push(v); },
    None => { return "obj: malformed vertex at line " + int_to_string(line_no); },
  }
  return "";
}

// Append one polygon from a "f i j k..." token list; every token after "f"
// must be a well-formed reference to an existing vertex. The polygon keeps
// its vertex count (no triangulation). Negative references are relative to
// the current vertex count. Returns "" or the error message.
fn _obj_face(tokens: &Vec[Str], line_no: Int, mesh: &mut ObjMesh) -> Str {
  if tokens.len() < 4 {
    return "obj: malformed face at line " + int_to_string(line_no);
  }
  let vcount = mesh.xs.len();
  let start = mesh.face_indices.len();
  var j = 1;
  while j < tokens.len() {
    let tok: Str = tokens[j];
    let core = _obj_index_core(tok);
    match core {
      Some(raw) => {
        var resolved = raw - 1;
        if raw < 0 {
          resolved = vcount + raw;
        }
        if resolved < 0 || resolved >= vcount {
          return "obj: index out of range at line " + int_to_string(line_no);
        }
        mesh.face_indices.push(resolved);
      },
      None => {
        return "obj: malformed face at line " + int_to_string(line_no);
      },
    }
    j = j + 1;
  }
  mesh.face_starts.push(start);
  mesh.face_ends.push(mesh.face_indices.len());
  return "";
}

// Process one physical line: skip blank and comment-only lines, dispatch v and
// f, ignore the known payload records and reject anything else. Returns "" or
// the error message.
fn _obj_line(text: Str, start: Int, end: Int, scale: Int, line_no: Int, mesh: &mut ObjMesh) -> Str {
  let stop = _obj_comment_start(text, start, end);
  let tokens = _obj_tokens(text, start, stop);
  if tokens.len() == 0 {
    return "";
  }
  let kw: Str = tokens[0];
  if compare.str_compare(kw, "v") == 0 {
    return _obj_vertex(&tokens, scale, line_no, mesh);
  }
  if compare.str_compare(kw, "f") == 0 {
    return _obj_face(&tokens, line_no, mesh);
  }
  if _obj_ignored(kw) {
    return "";
  }
  return "obj: unknown record at line " + int_to_string(line_no);
}
