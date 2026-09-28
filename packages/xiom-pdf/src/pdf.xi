// XIOM -- xiom.pdf: PDF document structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM PDF document STRUCTURE parser: lexing (names with #xx escapes,
// literal/hex strings, numbers, arrays, dictionaries, keywords, indirect
// references), indirect objects with optional streams (Length direct or by
// indirect reference, endstream scan fallback), classic cross-reference
// tables, cross-reference streams (/W, /Index, FlateDecode via a local
// inflate port), hybrid /XRefStm files, trailer chains (/Prev walk with a
// loop guard), object lookup, root catalog, the page tree walk and the Info
// dictionary fields. No rendering, no fonts, no colour semantics.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every table is parallel Vec fields (no
//     Vec[StructType]);
//   * Ok/Err are constructed only in the _ok_*/_err_* leaf helpers;
//   * byte reads widen and mask: (data[i] as Int) & 0xFF;
//   * Vec[Int] element reads are bound to typed locals;
//   * no &struct.field expressions are passed to &Vec parameters;
//   * strings and names are stored in a byte pool with per-node spans, so a
//     Str is only materialized after a NUL-free check;
//   * the DEFLATE/zlib decoder is a local port (see _fl_*), so the module
//     depends on xiom.* base modules only.
//
// See SPEC.md for the grammar subset, error catalog and limits.

module xiom.pdf

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
//  Limits
// ---------------------------------------------------------------------------

// Maximum value nesting depth (arrays/dictionaries).
const _PDF_MAX_NEST: Int = 64;
// Maximum xref chain sections walked through /Prev.
const _PDF_MAX_XREF_SECTIONS: Int = 64;
// Maximum total xref entries accepted.
const _PDF_MAX_XREF_ENTRIES: Int = 1000000;
// Maximum tokens produced by pdf_lex.
const _PDF_MAX_TOKENS: Int = 1000000;
// Maximum page-tree recursion depth.
const _PDF_MAX_PAGE_DEPTH: Int = 64;
// Maximum pages recorded by the walk.
const _PDF_MAX_PAGES: Int = 100000;
// Maximum entries in one object stream.
const _PDF_MAX_OBJSTM_N: Int = 100000;
// Maximum compressed input fed to the inflate port.
const _PDF_MAX_INFLATE_IN: Int = 1048576;
// Maximum inflated output accepted.
const _PDF_MAX_INFLATE_OUT: Int = 16777216;

// ---------------------------------------------------------------------------
//  Byte constants (compared against masked Int byte reads)
// ---------------------------------------------------------------------------

const _C_NUL: Int = 0;
const _C_TAB: Int = 9;
const _C_LF: Int = 10;
const _C_FF: Int = 12;
const _C_CR: Int = 13;
const _C_SP: Int = 32;
const _C_HASH: Int = 35;
const _C_PERCENT: Int = 37;
const _C_LPAREN: Int = 40;
const _C_RPAREN: Int = 41;
const _C_PLUS: Int = 43;
const _C_MINUS: Int = 45;
const _C_DOT: Int = 46;
const _C_SLASH: Int = 47;
const _C_D0: Int = 48;
const _C_D9: Int = 57;
const _C_LT: Int = 60;
const _C_GT: Int = 62;
const _C_LBRACKET: Int = 91;
const _C_BACKSLASH: Int = 92;
const _C_RBRACKET: Int = 93;
const _C_LBRACE: Int = 123;
const _C_RBRACE: Int = 125;
const _C_LOWER_E: Int = 101;
const _C_UPPER_E: Int = 69;
const _C_LOWER_N: Int = 110;
const _C_LOWER_F: Int = 102;

// ---------------------------------------------------------------------------
//  Token kinds, keyword codes, node kinds, xref kinds, length sources
// ---------------------------------------------------------------------------

const _TK_INT: Int = 0;
const _TK_REAL: Int = 1;
const _TK_STR: Int = 2;
const _TK_HEX: Int = 3;
const _TK_NAME: Int = 4;
const _TK_ARR_OPEN: Int = 5;
const _TK_ARR_CLOSE: Int = 6;
const _TK_DICT_OPEN: Int = 7;
const _TK_DICT_CLOSE: Int = 8;
const _TK_KEYWORD: Int = 9;

const _KW_NONE: Int = 0;
const _KW_TRUE: Int = 1;
const _KW_FALSE: Int = 2;
const _KW_NULL: Int = 3;
const _KW_OBJ: Int = 4;
const _KW_ENDOBJ: Int = 5;
const _KW_STREAM: Int = 6;
const _KW_ENDSTREAM: Int = 7;
const _KW_XREF: Int = 8;
const _KW_TRAILER: Int = 9;
const _KW_STARTXREF: Int = 10;
const _KW_R: Int = 11;
const _KW_N: Int = 12;
const _KW_F: Int = 13;

const _NK_NULL: Int = 0;
const _NK_BOOL: Int = 1;
const _NK_INT: Int = 2;
const _NK_REAL: Int = 3;
const _NK_STRING: Int = 4;
const _NK_NAME: Int = 5;
const _NK_ARRAY: Int = 6;
const _NK_DICT: Int = 7;
const _NK_REF: Int = 8;

const _XK_FREE: Int = 0;
const _XK_INUSE: Int = 1;
const _XK_OBJSTM: Int = 2;

const _XT_NONE: Int = 0;
const _XT_TABLE: Int = 1;
const _XT_STREAM: Int = 2;
const _XT_HYBRID: Int = 3;

const _LS_NONE: Int = 0;
const _LS_DIRECT: Int = 1;
const _LS_INDIRECT: Int = 2;
const _LS_SCANNED: Int = 3;
const _LS_SCANNED_REF: Int = 4;

const _OS_OK: Int = 0;
const _OS_OBJSTM_MISSING: Int = 2;

// ---------------------------------------------------------------------------
//  Public token stream (pdf_lex)
// ---------------------------------------------------------------------------

/// Flat token stream produced by pdf_lex. Token i is described by:
///   * kind[i]    -- _TK_* constant;
///   * start[i] / end[i] -- byte span in the source buffer;
///   * num[i]     -- integer value (INT), or the keyword code (KEYWORD);
///   * gen[i]     -- unused at token level (0);
///   * kw[i]      -- keyword code for KEYWORD tokens, else _KW_NONE;
///   * sstart[i] / slen[i] -- span in `pool` of the decoded bytes of a name,
///     literal string or hex string, or of the raw text of a real number;
///     (0, 0) for every other token kind.
/// The token stream is flat: array/dictionary brackets are tokens of their
/// own; it is not a parse tree.
pub type PdfTokens = {
  kind: Vec[Int];
  start: Vec[Int];
  end: Vec[Int];
  num: Vec[Int];
  gen: Vec[Int];
  kw: Vec[Int];
  sstart: Vec[Int];
  slen: Vec[Int];
  pool: Vec[UInt8];
}

// ---------------------------------------------------------------------------
//  Public parsed document
// ---------------------------------------------------------------------------

/// A parsed PDF document. All tables are parallel Vec fields.
///
/// Value arena: node i has kind[i] (_NK_*), source span nstart[i]/nend[i],
/// integer value num[i] (INT), reference target num[i]/gen[i] (REF), boolean
/// value num[i] (BOOL), and decoded name/string bytes at pool span
/// span_start[i]/span_len[i]. Containers expose their DIRECT children through
/// kids[]: array children are kid_count[i] entries starting at kid_start[i];
/// dictionary entries are 2*kid_count[i] entries (key node, value node).
///
/// Cross-reference section: xref_type is one of _XT_*; one entry per in-use
/// or free object at xr_num[i]/xr_gen[i]/xr_off[i]/xr_kind[i] (_XK_*;
/// for _XK_OBJSTM, xr_off is the object-stream number and xr_gen the index
/// inside it); xref_sections lists the chain offsets from startxref through
/// /Prev, newest first.
///
/// Objects: one entry per parsed indirect object, parallel with the object
/// tables; obj_node[i] is the arena node of the object value (-1 when
/// unresolved), obj_status[i] is _OS_*. Stream fields are valid when
/// obj_stream[i] == 1: raw bytes live in spool at
/// obj_stream_pool_start[i]/obj_stream_pool_len[i], the effective bounds are
/// obj_stream_data_start[i]/obj_stream_data_len[i] and obj_stream_src[i] is
/// an _LS_* code (SCANNED/SCANNED_REF mean the bounds came from an endstream
/// scan rather than from /Length).
///
/// Pages: page_nodes/page_obj_nums hold the page-tree walk result.
/// Trailer fields: trailer_size, root_num, info_num, encrypt_num, has_id
/// with id0/id1 pool spans, info_span_start/info_span_len for the extracted
/// Info fields (0 Title, 1 Author, 2 Subject, 3 CreationDate).
pub type PdfDocument = {
  data: Vec[UInt8];
  version: Str;
  header_offset: Int;
  kind: Vec[Int];
  nstart: Vec[Int];
  nend: Vec[Int];
  num: Vec[Int];
  gen: Vec[Int];
  span_start: Vec[Int];
  span_len: Vec[Int];
  kid_start: Vec[Int];
  kid_count: Vec[Int];
  kids: Vec[Int];
  pool: Vec[UInt8];
  tkind: Int;
  tstart: Int;
  tend: Int;
  tnum: Int;
  tgen: Int;
  tkw: Int;
  tsstart: Int;
  tslen: Int;
  tnode: Int;
  xref_type: Int;
  xr_num: Vec[Int];
  xr_gen: Vec[Int];
  xr_off: Vec[Int];
  xr_kind: Vec[Int];
  xr_prio: Vec[Int];
  xref_sections: Vec[Int];
  startxref: Int;
  trailer_node: Int;
  trailer_size: Int;
  trailer_prev: Int;
  prev_scratch: Int;
  hybrid_scratch: Int;
  root_num: Int;
  root_gen: Int;
  info_num: Int;
  info_gen: Int;
  encrypt_num: Int;
  encrypt_gen: Int;
  has_encrypt: Int;
  has_id: Int;
  id0_start: Int;
  id0_len: Int;
  id1_start: Int;
  id1_len: Int;
  info_span_start: Vec[Int];
  info_span_len: Vec[Int];
  obj_num: Vec[Int];
  obj_gen: Vec[Int];
  obj_off: Vec[Int];
  obj_node: Vec[Int];
  obj_status: Vec[Int];
  in_objstm: Vec[Int];
  obj_stream: Vec[Int];
  obj_stream_data_start: Vec[Int];
  obj_stream_data_len: Vec[Int];
  obj_stream_declared: Vec[Int];
  obj_stream_len_num: Vec[Int];
  obj_stream_len_gen: Vec[Int];
  obj_stream_src: Vec[Int];
  obj_stream_dict: Vec[Int];
  obj_stream_pool_start: Vec[Int];
  obj_stream_pool_len: Vec[Int];
  spool: Vec[UInt8];
  page_nodes: Vec[Int];
  page_obj_nums: Vec[Int];
  page_seen: Vec[Int];
  pages_root_num: Int;
  declared_page_count: Int;
  pages_depth_capped: Int;
  xref_decode_error: Str;
  objstm_used: Int;
}

// ---------------------------------------------------------------------------
//  Leaf Result constructors (v0.61.3: Ok/Err only in fns returning a Result)
// ---------------------------------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[PdfDocument, Str].
fn _ok_doc(v: PdfDocument) -> Result[PdfDocument, Str] {
  return Ok(v);
}

// Err(m) for Result[PdfDocument, Str].
fn _err_doc(m: Str) -> Result[PdfDocument, Str] {
  return Err(m);
}

// Ok(v) for Result[PdfTokens, Str].
fn _ok_tokens(v: PdfTokens) -> Result[PdfTokens, Str] {
  return Ok(v);
}

// Err(m) for Result[PdfTokens, Str].
fn _err_tokens(m: Str) -> Result[PdfTokens, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
//  Bytes and messages
// ---------------------------------------------------------------------------

// Unsigned byte at i, widened and masked to 0..255 (callers bound-check).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// "pdf: <text> at <offset>"; the deterministic shape of every error.
fn _msg_at(text: Str, off: Int) -> Str {
  return "pdf: " + text + " at " + convert.int_to_string(off);
}

// "pdf: flate <text> at <offset>".
fn _fl_msg(text: Str, off: Int) -> Str {
  return "pdf: flate " + text + " at " + convert.int_to_string(off);
}

// PDF whitespace byte: NUL, TAB, LF, FF, CR, SP.
fn _is_ws(b: Int) -> Bool {
  if b == _C_SP || b == _C_LF || b == _C_CR || b == _C_TAB {
    return true;
  }
  return b == _C_NUL || b == _C_FF;
}

// PDF delimiter byte: ( ) < > [ ] { } / %.
fn _is_delim(b: Int) -> Bool {
  if b == _C_LPAREN || b == _C_RPAREN || b == _C_LT || b == _C_GT {
    return true;
  }
  if b == _C_LBRACKET || b == _C_RBRACKET || b == _C_LBRACE || b == _C_RBRACE {
    return true;
  }
  return b == _C_SLASH || b == _C_PERCENT;
}

// True when b is a regular (non-delimiter, non-whitespace) byte.
fn _is_regular(b: Int) -> Bool {
  if _is_ws(b) { return false; }
  return !_is_delim(b);
}

// Decimal digit.
fn _is_digit(b: Int) -> Bool {
  return b >= _C_D0 && b <= _C_D9;
}

// Hex digit value or -1.
fn _hex_val(b: Int) -> Int {
  if b >= _C_D0 && b <= _C_D9 { return b - _C_D0; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// Octal digit.
fn _is_octal(b: Int) -> Bool {
  return b >= _C_D0 && b <= _C_D0 + 7;
}

// True when lit occurs at pos (bounds-checked byte comparison).
fn _match(data: &Vec[UInt8], pos: Int, lit: Str) -> Bool {
  let n = data.len();
  let m = lit.len();
  if pos < 0 || pos + m > n { return false; }
  var i = 0;
  while i < m {
    if _b(data, pos + i) != ((string.byte_at(lit, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// First offset >= from where lit occurs, or -1.
fn _find(data: &Vec[UInt8], from: Int, lit: Str) -> Int {
  let n = data.len();
  let m = lit.len();
  if m == 0 { return from; }
  var i = from;
  while i + m <= n {
    if _match(data, i, lit) { return i; }
    i = i + 1;
  }
  return -1;
}

// Skip whitespace from pos (no comments); returns the new position.
fn _skip_ws(data: &Vec[UInt8], pos: Int) -> Int {
  let n = data.len();
  var i = pos;
  while i < n && _is_ws(_b(data, i)) {
    i = i + 1;
  }
  return i;
}

// Skip whitespace and % comments from pos; returns the new position.
fn _skip_ws_comments(data: &Vec[UInt8], pos: Int) -> Int {
  let n = data.len();
  var i = pos;
  loop {
    while i < n && _is_ws(_b(data, i)) {
      i = i + 1;
    }
    if i < n && _b(data, i) == _C_PERCENT {
      i = i + 1;
      while i < n && _b(data, i) != _C_LF && _b(data, i) != _C_CR {
        i = i + 1;
      }
    } else {
      break;
    }
  }
  return i;
}

// Build a Str from data[start, end) when the range is NUL-free; else "".
fn _span_str(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let n = data.len();
  if start < 0 || end > n || end < start { return ""; }
  var i = start;
  while i < end {
    if _b(data, i) == 0 { return ""; }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// Copy data[start, end) into a fresh Vec[UInt8] (clamped to bounds).
fn _copy_span(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = start;
  if i < 0 { i = 0; }
  var e = end;
  if e > n { e = n; }
  while i < e {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Copy a whole Vec[UInt8].
fn _copy_vec(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// New empty document shell.
fn _new_document(data: Vec[UInt8]) -> PdfDocument {
  return PdfDocument{
    data: data;
    version: "";
    header_offset: -1;
    kind: Vec[Int].new();
    nstart: Vec[Int].new();
    nend: Vec[Int].new();
    num: Vec[Int].new();
    gen: Vec[Int].new();
    span_start: Vec[Int].new();
    span_len: Vec[Int].new();
    kid_start: Vec[Int].new();
    kid_count: Vec[Int].new();
    kids: Vec[Int].new();
    pool: Vec[UInt8].new();
    tkind: -1;
    tstart: 0;
    tend: 0;
    tnum: 0;
    tgen: 0;
    tkw: 0;
    tsstart: 0;
    tslen: 0;
    tnode: -1;
    xref_type: _XT_NONE;
    xr_num: Vec[Int].new();
    xr_gen: Vec[Int].new();
    xr_off: Vec[Int].new();
    xr_kind: Vec[Int].new();
    xr_prio: Vec[Int].new();
    xref_sections: Vec[Int].new();
    startxref: -1;
    trailer_node: -1;
    trailer_size: -1;
    trailer_prev: -1;
    prev_scratch: -1;
    hybrid_scratch: -1;
    root_num: -1;
    root_gen: 0;
    info_num: -1;
    info_gen: 0;
    encrypt_num: -1;
    encrypt_gen: 0;
    has_encrypt: 0;
    has_id: 0;
    id0_start: 0;
    id0_len: 0;
    id1_start: 0;
    id1_len: 0;
    info_span_start: Vec[Int].new();
    info_span_len: Vec[Int].new();
    obj_num: Vec[Int].new();
    obj_gen: Vec[Int].new();
    obj_off: Vec[Int].new();
    obj_node: Vec[Int].new();
    obj_status: Vec[Int].new();
    in_objstm: Vec[Int].new();
    obj_stream: Vec[Int].new();
    obj_stream_data_start: Vec[Int].new();
    obj_stream_data_len: Vec[Int].new();
    obj_stream_declared: Vec[Int].new();
    obj_stream_len_num: Vec[Int].new();
    obj_stream_len_gen: Vec[Int].new();
    obj_stream_src: Vec[Int].new();
    obj_stream_dict: Vec[Int].new();
    obj_stream_pool_start: Vec[Int].new();
    obj_stream_pool_len: Vec[Int].new();
    spool: Vec[UInt8].new();
    page_nodes: Vec[Int].new();
    page_obj_nums: Vec[Int].new();
    page_seen: Vec[Int].new();
    pages_root_num: -1;
    declared_page_count: -1;
    pages_depth_capped: 0;
    xref_decode_error: "";
    objstm_used: 0;
  };
}

// ---------------------------------------------------------------------------
//  Names for token kinds, keywords, node kinds, xref codes
// ---------------------------------------------------------------------------

/// Stable name for a token kind.
/// Params: k - a _TK_* value.
/// Returns: "int", "real", "str", "hex", "name", "array_open", "array_close",
/// "dict_open", "dict_close" or "keyword"; "" for any other value.
pub fn pdf_token_kind_name(k: Int) -> Str {
  if k == _TK_INT { return "int"; }
  if k == _TK_REAL { return "real"; }
  if k == _TK_STR { return "str"; }
  if k == _TK_HEX { return "hex"; }
  if k == _TK_NAME { return "name"; }
  if k == _TK_ARR_OPEN { return "array_open"; }
  if k == _TK_ARR_CLOSE { return "array_close"; }
  if k == _TK_DICT_OPEN { return "dict_open"; }
  if k == _TK_DICT_CLOSE { return "dict_close"; }
  if k == _TK_KEYWORD { return "keyword"; }
  return "";
}

/// Stable name for a keyword code.
/// Params: code - a _KW_* value.
/// Returns: "true", "false", "null", "obj", "endobj", "stream", "endstream",
/// "xref", "trailer", "startxref", "R", "n", "f"; "" otherwise.
pub fn pdf_keyword_name(code: Int) -> Str {
  if code == _KW_TRUE { return "true"; }
  if code == _KW_FALSE { return "false"; }
  if code == _KW_NULL { return "null"; }
  if code == _KW_OBJ { return "obj"; }
  if code == _KW_ENDOBJ { return "endobj"; }
  if code == _KW_STREAM { return "stream"; }
  if code == _KW_ENDSTREAM { return "endstream"; }
  if code == _KW_XREF { return "xref"; }
  if code == _KW_TRAILER { return "trailer"; }
  if code == _KW_STARTXREF { return "startxref"; }
  if code == _KW_R { return "R"; }
  if code == _KW_N { return "n"; }
  if code == _KW_F { return "f"; }
  return "";
}

/// Keyword code for a bare word (exact match).
/// Params: name - the word text.
/// Returns: the _KW_* code, or _KW_NONE for an unknown word.
pub fn pdf_keyword_code(name: Str) -> Int {
  if compare.str_compare(name, "true") == 0 { return _KW_TRUE; }
  if compare.str_compare(name, "false") == 0 { return _KW_FALSE; }
  if compare.str_compare(name, "null") == 0 { return _KW_NULL; }
  if compare.str_compare(name, "obj") == 0 { return _KW_OBJ; }
  if compare.str_compare(name, "endobj") == 0 { return _KW_ENDOBJ; }
  if compare.str_compare(name, "stream") == 0 { return _KW_STREAM; }
  if compare.str_compare(name, "endstream") == 0 { return _KW_ENDSTREAM; }
  if compare.str_compare(name, "xref") == 0 { return _KW_XREF; }
  if compare.str_compare(name, "trailer") == 0 { return _KW_TRAILER; }
  if compare.str_compare(name, "startxref") == 0 { return _KW_STARTXREF; }
  if compare.str_compare(name, "R") == 0 { return _KW_R; }
  if compare.str_compare(name, "n") == 0 { return _KW_N; }
  if compare.str_compare(name, "f") == 0 { return _KW_F; }
  return _KW_NONE;
}

/// Stable name for a node kind.
/// Params: k - a _NK_* value.
/// Returns: "null", "bool", "int", "real", "string", "name", "array", "dict"
/// or "ref"; "" otherwise.
pub fn pdf_node_kind_name(k: Int) -> Str {
  if k == _NK_NULL { return "null"; }
  if k == _NK_BOOL { return "bool"; }
  if k == _NK_INT { return "int"; }
  if k == _NK_REAL { return "real"; }
  if k == _NK_STRING { return "string"; }
  if k == _NK_NAME { return "name"; }
  if k == _NK_ARRAY { return "array"; }
  if k == _NK_DICT { return "dict"; }
  if k == _NK_REF { return "ref"; }
  return "";
}

/// Stable name for an xref entry kind.
/// Params: k - an _XK_* value.
/// Returns: "free", "in-use" or "objstm"; "" otherwise.
pub fn pdf_xref_kind_name(k: Int) -> Str {
  if k == _XK_FREE { return "free"; }
  if k == _XK_INUSE { return "in-use"; }
  if k == _XK_OBJSTM { return "objstm"; }
  return "";
}

/// Stable name for the cross-reference container kind.
/// Params: k - an _XT_* value.
/// Returns: "none", "table", "stream" or "hybrid"; "" otherwise.
pub fn pdf_xref_type_name(k: Int) -> Str {
  if k == _XT_NONE { return "none"; }
  if k == _XT_TABLE { return "table"; }
  if k == _XT_STREAM { return "stream"; }
  if k == _XT_HYBRID { return "hybrid"; }
  return "";
}

// ---------------------------------------------------------------------------
//  Token scanners
// ---------------------------------------------------------------------------

// True when data[start, end) equals the literal `lit` exactly.
fn _word_is(data: &Vec[UInt8], start: Int, end: Int, lit: Str) -> Bool {
  if end - start != lit.len() { return false; }
  return _match(data, start, lit);
}

// Keyword code for the bare word data[start, end); _KW_NONE when unknown.
fn _keyword_code_bytes(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  if _word_is(data, start, end, "true") { return _KW_TRUE; }
  if _word_is(data, start, end, "false") { return _KW_FALSE; }
  if _word_is(data, start, end, "null") { return _KW_NULL; }
  if _word_is(data, start, end, "obj") { return _KW_OBJ; }
  if _word_is(data, start, end, "endobj") { return _KW_ENDOBJ; }
  if _word_is(data, start, end, "stream") { return _KW_STREAM; }
  if _word_is(data, start, end, "endstream") { return _KW_ENDSTREAM; }
  if _word_is(data, start, end, "xref") { return _KW_XREF; }
  if _word_is(data, start, end, "trailer") { return _KW_TRAILER; }
  if _word_is(data, start, end, "startxref") { return _KW_STARTXREF; }
  if _word_is(data, start, end, "R") { return _KW_R; }
  if _word_is(data, start, end, "n") { return _KW_N; }
  if _word_is(data, start, end, "f") { return _KW_F; }
  return _KW_NONE;
}

// Scan a name at the '/' at pos. `#xx` escapes decode one byte each; a
// decoded NUL and a name longer than 4096 bytes are errors. The decoded bytes
// are appended to doc.pool and recorded in the scratch span.
fn _scan_name(data: &Vec[UInt8], pos: Int, doc: &mut PdfDocument) -> Result[Int, Str] {
  let n = data.len();
  var i = pos + 1;
  let sstart = doc.pool.len();
  loop {
    if i >= n { break; }
    let b = _b(data, i);
    if _is_ws(b) || _is_delim(b) { break; }
    if b == _C_HASH {
      if i + 2 >= n { return _err_int(_msg_at("bad name escape", i)); }
      let h1 = _hex_val(_b(data, i + 1));
      let h2 = _hex_val(_b(data, i + 2));
      if h1 < 0 || h2 < 0 { return _err_int(_msg_at("bad name escape", i)); }
      let v = h1 * 16 + h2;
      if v == 0 { return _err_int(_msg_at("NUL in name", i)); }
      doc.pool.push(v as UInt8);
      i = i + 3;
    } else {
      doc.pool.push(b as UInt8);
      i = i + 1;
    }
    if doc.pool.len() - sstart > 4096 {
      return _err_int(_msg_at("name too long", pos));
    }
  }
  doc.tkind = _TK_NAME;
  doc.tend = i;
  doc.tsstart = sstart;
  doc.tslen = doc.pool.len() - sstart;
  return _ok_int(i);
}

// Scan a literal string at the '(' at pos: nested unescaped parentheses and
// the escapes \n \r \t \b \f \( \) \\ \ooo, a backslash before CR/LF is a
// line continuation, any other escaped byte drops the backslash. The decoded
// bytes (NULs allowed) go to doc.pool.
fn _scan_literal_string(data: &Vec[UInt8], pos: Int, doc: &mut PdfDocument) -> Result[Int, Str] {
  let n = data.len();
  var i = pos + 1;
  var depth = 1;
  let sstart = doc.pool.len();
  while i < n {
    let b = _b(data, i);
    if b == _C_BACKSLASH {
      i = i + 1;
      if i >= n { return _err_int(_msg_at("unterminated string", pos)); }
      let e = _b(data, i);
      if e == _C_LOWER_N {
        doc.pool.push(_C_LF as UInt8);
        i = i + 1;
      } elif e == 114 {
        doc.pool.push(_C_CR as UInt8);
        i = i + 1;
      } elif e == 116 {
        doc.pool.push(_C_TAB as UInt8);
        i = i + 1;
      } elif e == 98 {
        doc.pool.push(8 as UInt8);
        i = i + 1;
      } elif e == _C_LOWER_F {
        doc.pool.push(_C_FF as UInt8);
        i = i + 1;
      } elif e == _C_LPAREN {
        doc.pool.push(_C_LPAREN as UInt8);
        i = i + 1;
      } elif e == _C_RPAREN {
        doc.pool.push(_C_RPAREN as UInt8);
        i = i + 1;
      } elif e == _C_BACKSLASH {
        doc.pool.push(_C_BACKSLASH as UInt8);
        i = i + 1;
      } elif _is_octal(e) {
        var v = e - _C_D0;
        i = i + 1;
        var k = 1;
        while k < 3 && i < n && _is_octal(_b(data, i)) {
          v = v * 8 + (_b(data, i) - _C_D0);
          i = i + 1;
          k = k + 1;
        }
        doc.pool.push((v & 0xFF) as UInt8);
      } elif e == _C_CR {
        i = i + 1;
        if i < n && _b(data, i) == _C_LF { i = i + 1; }
      } elif e == _C_LF {
        i = i + 1;
      } else {
        doc.pool.push(e as UInt8);
        i = i + 1;
      }
    } elif b == _C_LPAREN {
      depth = depth + 1;
      doc.pool.push(b as UInt8);
      i = i + 1;
    } elif b == _C_RPAREN {
      depth = depth - 1;
      i = i + 1;
      if depth == 0 { break; }
      doc.pool.push(b as UInt8);
    } else {
      doc.pool.push(b as UInt8);
      i = i + 1;
    }
    if doc.pool.len() - sstart > 1048576 {
      return _err_int(_msg_at("string too long", pos));
    }
  }
  if depth != 0 { return _err_int(_msg_at("unterminated string", pos)); }
  doc.tkind = _TK_STR;
  doc.tend = i;
  doc.tsstart = sstart;
  doc.tslen = doc.pool.len() - sstart;
  return _ok_int(i);
}

// Scan a hex string at the '<' at pos. An odd final nibble is padded with 0.
fn _scan_hex_string(data: &Vec[UInt8], pos: Int, doc: &mut PdfDocument) -> Result[Int, Str] {
  let n = data.len();
  var i = pos + 1;
  let sstart = doc.pool.len();
  var hi = -1;
  var closed = false;
  while i < n {
    let b = _b(data, i);
    if b == _C_GT {
      i = i + 1;
      closed = true;
      break;
    }
    let hv = _hex_val(b);
    if _is_ws(b) {
      i = i + 1;
    } elif hv >= 0 {
      if hi < 0 {
        hi = hv;
      } else {
        doc.pool.push(((hi * 16 + hv) & 0xFF) as UInt8);
        hi = -1;
      }
      i = i + 1;
    } else {
      return _err_int(_msg_at("bad hex digit", i));
    }
  }
  if !closed { return _err_int(_msg_at("unterminated hex string", pos)); }
  if hi >= 0 { doc.pool.push(((hi * 16) & 0xFF) as UInt8); }
  doc.tkind = _TK_HEX;
  doc.tend = i;
  doc.tsstart = sstart;
  doc.tslen = doc.pool.len() - sstart;
  return _ok_int(i);
}

// Scan an integer or real number at pos (digit, sign or dot). Reals keep
// their raw token text in doc.pool (TS span); integers land in doc.tnum.
fn _scan_number(data: &Vec[UInt8], pos: Int, doc: &mut PdfDocument) -> Result[Int, Str] {
  let n = data.len();
  var i = pos;
  if i < n && (_b(data, i) == _C_PLUS || _b(data, i) == _C_MINUS) { i = i + 1; }
  var digits = 0;
  var is_real = false;
  while i < n && _is_digit(_b(data, i)) {
    digits = digits + 1;
    i = i + 1;
  }
  if i < n && _b(data, i) == _C_DOT {
    is_real = true;
    i = i + 1;
    while i < n && _is_digit(_b(data, i)) {
      digits = digits + 1;
      i = i + 1;
    }
  }
  if digits == 0 { return _err_int(_msg_at("bad number", pos)); }
  if i < n && (_b(data, i) == _C_LOWER_E || _b(data, i) == _C_UPPER_E) {
    is_real = true;
    var j = i + 1;
    if j < n && (_b(data, j) == _C_PLUS || _b(data, j) == _C_MINUS) { j = j + 1; }
    var edigits = 0;
    while j < n && _is_digit(_b(data, j)) {
      edigits = edigits + 1;
      j = j + 1;
    }
    if edigits == 0 { return _err_int(_msg_at("bad number", pos)); }
    i = j;
  }
  if i < n {
    let t = _b(data, i);
    if !_is_ws(t) && !_is_delim(t) { return _err_int(_msg_at("bad number", pos)); }
  }
  doc.tstart = pos;
  doc.tend = i;
  doc.tkw = _KW_NONE;
  doc.tgen = 0;
  if is_real {
    let span0 = doc.pool.len();
    var k = pos;
    while k < i {
      doc.pool.push(data[k]);
      k = k + 1;
    }
    doc.tsstart = span0;
    doc.tslen = doc.pool.len() - span0;
    doc.tnum = 0;
    doc.tkind = _TK_REAL;
    return _ok_int(i);
  }
  if digits > 18 { return _err_int(_msg_at("number too large", pos)); }
  var v = 0;
  var k = pos;
  if _b(data, k) == _C_MINUS { k = k + 1; }
  if k < i && _b(data, k) == _C_PLUS { k = k + 1; }
  while k < i {
    v = v * 10 + (_b(data, k) - _C_D0);
    k = k + 1;
  }
  if _b(data, pos) == _C_MINUS { v = 0 - v; }
  doc.tnum = v;
  doc.tsstart = 0;
  doc.tslen = 0;
  doc.tkind = _TK_INT;
  return _ok_int(i);
}

// Scan one token starting at or after pos (whitespace and % comments skipped).
// On success the scratch fields describe the token and the returned position
// is just past it.
fn _scan_token(data: &Vec[UInt8], pos: Int, doc: &mut PdfDocument) -> Result[Int, Str] {
  let n = data.len();
  let i = _skip_ws_comments(data, pos);
  if i >= n { return _err_int(_msg_at("unexpected end of input", i)); }
  doc.tkind = -1;
  doc.tstart = i;
  doc.tend = i;
  doc.tnum = 0;
  doc.tgen = 0;
  doc.tkw = _KW_NONE;
  doc.tsstart = 0;
  doc.tslen = 0;
  let b = _b(data, i);
  if b == _C_SLASH { return _scan_name(data, i, doc); }
  if b == _C_LPAREN { return _scan_literal_string(data, i, doc); }
  if b == _C_LT {
    if i + 1 < n && _b(data, i + 1) == _C_LT {
      doc.tkind = _TK_DICT_OPEN;
      doc.tend = i + 2;
      return _ok_int(i + 2);
    }
    return _scan_hex_string(data, i, doc);
  }
  if b == _C_GT {
    if i + 1 < n && _b(data, i + 1) == _C_GT {
      doc.tkind = _TK_DICT_CLOSE;
      doc.tend = i + 2;
      return _ok_int(i + 2);
    }
    return _err_int(_msg_at("unexpected token", i));
  }
  if b == _C_LBRACKET {
    doc.tkind = _TK_ARR_OPEN;
    doc.tend = i + 1;
    return _ok_int(i + 1);
  }
  if b == _C_RBRACKET {
    doc.tkind = _TK_ARR_CLOSE;
    doc.tend = i + 1;
    return _ok_int(i + 1);
  }
  if b == _C_PLUS || b == _C_MINUS || b == _C_DOT || _is_digit(b) {
    return _scan_number(data, i, doc);
  }
  if _is_regular(b) {
    var j = i;
    while j < n && _is_regular(_b(data, j)) {
      j = j + 1;
    }
    let code = _keyword_code_bytes(data, i, j);
    if code == _KW_NONE { return _err_int(_msg_at("unknown keyword", i)); }
    doc.tkind = _TK_KEYWORD;
    doc.tend = j;
    doc.tkw = code;
    doc.tnum = code;
    return _ok_int(j);
  }
  return _err_int(_msg_at("unexpected token", i));
}

// ---------------------------------------------------------------------------
//  Arena pushes and pool reads
// ---------------------------------------------------------------------------

// Append one value node (scalar or empty container); returns its index.
fn _push_scalar(doc: &mut PdfDocument, k: Int, start: Int, end: Int, numv: Int, genv: Int, sstart: Int, slen: Int) -> Int {
  let idx = doc.kind.len();
  doc.kind.push(k);
  doc.nstart.push(start);
  doc.nend.push(end);
  doc.num.push(numv);
  doc.gen.push(genv);
  doc.span_start.push(sstart);
  doc.span_len.push(slen);
  let ks = doc.kids.len();
  doc.kid_start.push(ks);
  doc.kid_count.push(0);
  return idx;
}

// Append one container node; `start`/`end` is its opening bracket span.
fn _push_container(doc: &mut PdfDocument, k: Int, start: Int, end: Int) -> Int {
  return _push_scalar(doc, k, start, end, 0, 0, 0, 0);
}

// Materialize pool[start, start+len) as a Str when it is NUL-free, else "".
fn _pool_str(doc: &PdfDocument, start: Int, len: Int) -> Str {
  if start < 0 || len < 0 { return ""; }
  if len == 0 { return ""; }
  if start + len > doc.pool.len() { return ""; }
  var i = start;
  while i < start + len {
    if ((doc.pool[i] as Int) & 0xFF) == 0 { return ""; }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = start;
  while i < start + len {
    out.push(doc.pool[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// Copy pool[start, start+len) into a fresh Vec[UInt8].
fn _pool_copy(doc: &PdfDocument, start: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if start < 0 || len <= 0 { return out; }
  let n = doc.pool.len();
  var i = start;
  while i < start + len && i < n {
    out.push(doc.pool[i]);
    i = i + 1;
  }
  return out;
}

// True when pool[start, start+len) equals the bytes of `s`.
fn _span_eq_str(doc: &PdfDocument, start: Int, len: Int, s: Str) -> Bool {
  if len != s.len() { return false; }
  if start < 0 || start + len > doc.pool.len() { return false; }
  var i = 0;
  while i < len {
    if (((doc.pool[start + i] as Int) & 0xFF) != ((string.byte_at(s, i) as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
//  Value parser (arena building)
// ---------------------------------------------------------------------------

// Parse one value at pos; doc.tnode receives the arena index. The returned
// position is just past the value.
fn _parse_value_at(doc: &mut PdfDocument, data: &Vec[UInt8], pos: Int, depth: Int) -> Result[Int, Str] {
  if depth > _PDF_MAX_NEST { return _err_int(_msg_at("nesting too deep", pos)); }
  let r = _scan_token(data, pos, doc);
  var p = 0;
  match r {
    Ok(v) => { p = v; },
    Err(e) => { return _err_int(e); },
  };
  return _parse_value_tok(doc, data, p, depth);
}

// Parse a value whose first token is already in the scratch (pos is just past
// it). Containers recurse through _parse_value_at.
fn _parse_value_tok(doc: &mut PdfDocument, data: &Vec[UInt8], pos: Int, depth: Int) -> Result[Int, Str] {
  let k: Int = doc.tkind;
  if k == _TK_INT {
    let v0: Int = doc.tnum;
    let s0: Int = doc.tstart;
    let e0: Int = doc.tend;
    let r2 = _scan_token(data, pos, doc);
    if r2.is_ok {
      if doc.tkind == _TK_INT {
        let v1: Int = doc.tnum;
        let e1: Int = doc.tend;
        let p2: Int = r2.value;
        let r3 = _scan_token(data, p2, doc);
        if r3.is_ok {
          if doc.tkind == _TK_KEYWORD && doc.tkw == _KW_R {
            let p3r: Int = r3.value;
            let idx = _push_scalar(doc, _NK_REF, s0, e1, v0, v1, 0, 0);
            doc.tnode = idx;
            return _ok_int(p3r);
          }
        }
      }
    }
    let idx2 = _push_scalar(doc, _NK_INT, s0, e0, v0, 0, 0, 0);
    doc.tnode = idx2;
    return _ok_int(pos);
  }
  if k == _TK_REAL {
    let idx = _push_scalar(doc, _NK_REAL, doc.tstart, doc.tend, 0, 0, doc.tsstart, doc.tslen);
    doc.tnode = idx;
    return _ok_int(pos);
  }
  if k == _TK_STR || k == _TK_HEX {
    let idx = _push_scalar(doc, _NK_STRING, doc.tstart, doc.tend, 0, 0, doc.tsstart, doc.tslen);
    doc.tnode = idx;
    return _ok_int(pos);
  }
  if k == _TK_NAME {
    let idx = _push_scalar(doc, _NK_NAME, doc.tstart, doc.tend, 0, 0, doc.tsstart, doc.tslen);
    doc.tnode = idx;
    return _ok_int(pos);
  }
  if k == _TK_KEYWORD {
    if doc.tkw == _KW_TRUE {
      let idx = _push_scalar(doc, _NK_BOOL, doc.tstart, doc.tend, 1, 0, 0, 0);
      doc.tnode = idx;
      return _ok_int(pos);
    }
    if doc.tkw == _KW_FALSE {
      let idx = _push_scalar(doc, _NK_BOOL, doc.tstart, doc.tend, 0, 0, 0, 0);
      doc.tnode = idx;
      return _ok_int(pos);
    }
    if doc.tkw == _KW_NULL {
      let idx = _push_scalar(doc, _NK_NULL, doc.tstart, doc.tend, 0, 0, 0, 0);
      doc.tnode = idx;
      return _ok_int(pos);
    }
    return _err_int(_msg_at("unexpected token", doc.tstart));
  }
  if k == _TK_ARR_OPEN {
    let ai = _push_container(doc, _NK_ARRAY, doc.tstart, doc.tend);
    var local = Vec[Int].new();
    var p2 = pos;
    loop {
      let sr = _scan_token(data, p2, doc);
      var q = 0;
      match sr {
        Ok(v) => { q = v; },
        Err(e) => { return _err_int(e); },
      };
      if doc.tkind == _TK_ARR_CLOSE {
        let ks: Int = doc.kids.len();
        var j = 0;
        while j < local.len() {
          let e: Int = local[j];
          doc.kids.push(e);
          j = j + 1;
        }
        doc.kid_start[ai] = ks;
        doc.kid_count[ai] = local.len();
        doc.tnode = ai;
        return _ok_int(q);
      }
      let vr = _parse_value_tok(doc, data, q, depth + 1);
      var q2 = 0;
      match vr {
        Ok(v) => { q2 = v; },
        Err(e) => { return _err_int(e); },
      };
      local.push(doc.tnode);
      p2 = q2;
    }
  }
  if k == _TK_DICT_OPEN {
    let ai = _push_container(doc, _NK_DICT, doc.tstart, doc.tend);
    var local2 = Vec[Int].new();
    var p2 = pos;
    loop {
      let sr = _scan_token(data, p2, doc);
      var q = 0;
      match sr {
        Ok(v) => { q = v; },
        Err(e) => { return _err_int(e); },
      };
      if doc.tkind == _TK_DICT_CLOSE {
        let ks2: Int = doc.kids.len();
        var j2 = 0;
        while j2 < local2.len() {
          let e2: Int = local2[j2];
          doc.kids.push(e2);
          j2 = j2 + 1;
        }
        doc.kid_start[ai] = ks2;
        doc.kid_count[ai] = local2.len();
        doc.tnode = ai;
        return _ok_int(q);
      }
      if doc.tkind != _TK_NAME {
        return _err_int(_msg_at("dictionary key is not a name", doc.tstart));
      }
      let ki = _push_scalar(doc, _NK_NAME, doc.tstart, doc.tend, 0, 0, doc.tsstart, doc.tslen);
      local2.push(ki);
      let vr = _parse_value_at(doc, data, q, depth + 1);
      var q2 = 0;
      match vr {
        Ok(v) => { q2 = v; },
        Err(e) => { return _err_int(e); },
      };
      local2.push(doc.tnode);
      p2 = q2;
    }
  }
  return _err_int(_msg_at("unexpected token", doc.tstart));
}

// ---------------------------------------------------------------------------
//  Dictionary helpers
// ---------------------------------------------------------------------------

// Value node for `key` in dictionary node `dict`, or -1. Keys are NAME nodes
// compared by decoded bytes (never by Str identity).
fn _dict_get(doc: &PdfDocument, dict: Int, key: Str) -> Int {
  if dict < 0 || dict >= doc.kind.len() { return -1; }
  let kd: Int = doc.kind[dict];
  if kd != _NK_DICT { return -1; }
  let ks: Int = doc.kid_start[dict];
  let kc: Int = doc.kid_count[dict];
  var k = 0;
  while k + 1 < kc {
    let ki: Int = doc.kids[ks + k];
    let kk: Int = doc.kind[ki];
    if kk == _NK_NAME {
      let ss: Int = doc.span_start[ki];
      let sl: Int = doc.span_len[ki];
      if _span_eq_str(doc, ss, sl, key) {
        let vi: Int = doc.kids[ks + k + 1];
        return vi;
      }
    }
    k = k + 2;
  }
  return -1;
}

// Integer value of `key` in `dict`, or -1 when absent or not an integer.
fn _dict_get_int(doc: &PdfDocument, dict: Int, key: Str) -> Int {
  let v = _dict_get(doc, dict, key);
  if v < 0 { return -1; }
  let kd: Int = doc.kind[v];
  if kd != _NK_INT { return -1; }
  let x: Int = doc.num[v];
  return x;
}

// NAME value of `key` in `dict` as a Str (NUL-free check), or "".
fn _dict_get_name(doc: &PdfDocument, dict: Int, key: Str) -> Str {
  let v = _dict_get(doc, dict, key);
  if v < 0 { return ""; }
  let kd: Int = doc.kind[v];
  if kd != _NK_NAME { return ""; }
  let ss: Int = doc.span_start[v];
  let sl: Int = doc.span_len[v];
  return _pool_str(doc, ss, sl);
}

// ---------------------------------------------------------------------------
//  Structural cursor helpers
// ---------------------------------------------------------------------------

// Read one or more decimal digits at pos into doc.tnum; returns the position
// just past the digits.
fn _read_uint(doc: &mut PdfDocument, data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let n = data.len();
  var i = pos;
  var v = 0;
  var digits = 0;
  while i < n {
    let b = _b(data, i);
    if !_is_digit(b) { break; }
    if digits >= 18 { return _err_int(_msg_at("number too large", pos)); }
    v = v * 10 + (b - _C_D0);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 { return _err_int(_msg_at("expected integer", pos)); }
  doc.tnum = v;
  return _ok_int(i);
}

// True when "endstream" follows at pos, allowing one optional CRLF/LF/CR.
fn _endstream_follows(data: &Vec[UInt8], pos: Int) -> Bool {
  let n = data.len();
  var i = pos;
  if i < n && _b(data, i) == _C_CR {
    i = i + 1;
    if i < n && _b(data, i) == _C_LF { i = i + 1; }
  } elif i < n && _b(data, i) == _C_LF {
    i = i + 1;
  }
  return _match(data, i, "endstream");
}

// Position just past "endstream" that starts at `data_end` (after the
// optional EOL), or -1 when it does not match.
fn _after_endstream(data: &Vec[UInt8], data_end: Int) -> Int {
  let n = data.len();
  var i = data_end;
  if i < n && _b(data, i) == _C_CR {
    i = i + 1;
    if i < n && _b(data, i) == _C_LF { i = i + 1; }
  } elif i < n && _b(data, i) == _C_LF {
    i = i + 1;
  }
  if !_match(data, i, "endstream") { return -1; }
  return i + 9;
}

// ---------------------------------------------------------------------------
//  Objects and streams
// ---------------------------------------------------------------------------

// Append one object entry with every parallel vector initialized; returns the
// entry index.
fn _push_object(doc: &mut PdfDocument, num: Int, gen: Int, off: Int, vn: Int) -> Int {
  let idx = doc.obj_num.len();
  doc.obj_num.push(num);
  doc.obj_gen.push(gen);
  doc.obj_off.push(off);
  doc.obj_node.push(vn);
  doc.obj_status.push(_OS_OK);
  doc.in_objstm.push(0);
  doc.obj_stream.push(0);
  doc.obj_stream_data_start.push(0);
  doc.obj_stream_data_len.push(0);
  doc.obj_stream_declared.push(-1);
  doc.obj_stream_len_num.push(-1);
  doc.obj_stream_len_gen.push(0);
  doc.obj_stream_src.push(_LS_NONE);
  doc.obj_stream_dict.push(vn);
  doc.obj_stream_pool_start.push(0);
  doc.obj_stream_pool_len.push(0);
  return idx;
}

// Append data[start, end) to the stream pool; returns the pool offset.
fn _spool_append(doc: &mut PdfDocument, data: &Vec[UInt8], start: Int, end: Int) -> Int {
  let at = doc.spool.len();
  var i = start;
  while i < end {
    doc.spool.push(data[i]);
    i = i + 1;
  }
  return at;
}

// Body of a stream: `p` is just past the "stream" keyword. Applies the
// CRLF/LF rule, resolves /Length (direct value or provisional endstream
// scan; indirect references are resolved later), copies the raw bytes into
// the stream pool and consumes the trailing "endobj".
fn _parse_stream_body(doc: &mut PdfDocument, data: &Vec[UInt8], p: Int, oi: Int, vn: Int) -> Result[Int, Str] {
  let n = data.len();
  if vn < 0 { return _err_int(_msg_at("stream value missing", p)); }
  let kd: Int = doc.kind[vn];
  if kd != _NK_DICT { return _err_int(_msg_at("stream value is not a dictionary", doc.nstart[vn])); }
  var i = p;
  if i >= n { return _err_int(_msg_at("unterminated stream", p)); }
  if _b(data, i) == _C_CR {
    if i + 1 < n && _b(data, i + 1) == _C_LF {
      i = i + 2;
    } else {
      return _err_int(_msg_at("stream keyword not followed by LF or CRLF", p));
    }
  } elif _b(data, i) == _C_LF {
    i = i + 1;
  } else {
    return _err_int(_msg_at("stream keyword not followed by LF or CRLF", p));
  }
  let data_start = i;
  let lv = _dict_get(doc, vn, "Length");
  if lv < 0 { return _err_int(_msg_at("stream dictionary missing /Length", data_start)); }
  let lk: Int = doc.kind[lv];
  var src = _LS_SCANNED;
  var declared = -1;
  var len_num = -1;
  var len_gen = 0;
  var data_end = -1;
  var after = -1;
  if lk == _NK_INT {
    let dl: Int = doc.num[lv];
    declared = dl;
    if dl >= 0 && data_start + dl <= n {
      let ap = _after_endstream(data, data_start + dl);
      if ap >= 0 {
        data_end = data_start + dl;
        after = ap;
        src = _LS_DIRECT;
      }
    }
  } elif lk == _NK_REF {
    len_num = doc.num[lv];
    len_gen = doc.gen[lv];
    src = _LS_SCANNED_REF;
  } else {
    return _err_int(_msg_at("bad /Length value", doc.nstart[lv]));
  }
  if data_end < 0 {
    let hit = _find(data, data_start, "endstream");
    if hit < 0 { return _err_int(_msg_at("unterminated stream", data_start)); }
    var e = hit;
    if e > data_start && _b(data, e - 1) == _C_LF { e = e - 1; }
    if e > data_start && _b(data, e - 1) == _C_CR { e = e - 1; }
    data_end = e;
    src = _LS_SCANNED;
    if len_num >= 0 { src = _LS_SCANNED_REF; }
    after = hit + 9;
  }
  let pstart = _spool_append(doc, data, data_start, data_end);
  doc.obj_stream[oi] = 1;
  doc.obj_stream_data_start[oi] = data_start;
  doc.obj_stream_data_len[oi] = data_end - data_start;
  doc.obj_stream_declared[oi] = declared;
  doc.obj_stream_len_num[oi] = len_num;
  doc.obj_stream_len_gen[oi] = len_gen;
  doc.obj_stream_src[oi] = src;
  doc.obj_stream_dict[oi] = vn;
  doc.obj_stream_pool_start[oi] = pstart;
  doc.obj_stream_pool_len[oi] = data_end - data_start;
  let er = _scan_token(data, after, doc);
  if er.is_ok {
    if doc.tkind == _TK_KEYWORD && doc.tkw == _KW_ENDOBJ {
      return _ok_int(after);
    }
  }
  return _err_int(_msg_at("missing endobj", after));
}

// Parse "N G obj", the value, an optional stream and "endobj" at off.
// expect_num >= 0 requires the header object number to match. Returns the new
// object-entry index.
fn _parse_indirect_at(doc: &mut PdfDocument, data: &Vec[UInt8], off: Int, expect_num: Int) -> Result[Int, Str] {
  let r1 = _scan_token(data, off, doc);
  var p1 = 0;
  match r1 {
    Ok(v) => { p1 = v; },
    Err(_) => { return _err_int(_msg_at("bad object header", off)); },
  };
  if doc.tkind != _TK_INT { return _err_int(_msg_at("bad object header", off)); }
  let num: Int = doc.tnum;
  let r2 = _scan_token(data, p1, doc);
  var p2 = 0;
  match r2 {
    Ok(v) => { p2 = v; },
    Err(_) => { return _err_int(_msg_at("bad object header", p1)); },
  };
  if doc.tkind != _TK_INT { return _err_int(_msg_at("bad object header", p1)); }
  let gen: Int = doc.tnum;
  let r3 = _scan_token(data, p2, doc);
  var p3 = 0;
  match r3 {
    Ok(v) => { p3 = v; },
    Err(_) => { return _err_int(_msg_at("bad object header", p2)); },
  };
  if doc.tkind != _TK_KEYWORD || doc.tkw != _KW_OBJ {
    return _err_int(_msg_at("bad object header", p2));
  }
  if expect_num >= 0 && num != expect_num {
    return _err_int(_msg_at("object header mismatch", off));
  }
  let vr = _parse_value_at(doc, data, p3, 0);
  var vp = 0;
  match vr {
    Ok(v) => { vp = v; },
    Err(e) => { return _err_int(e); },
  };
  let vn: Int = doc.tnode;
  let oi = _push_object(doc, num, gen, off, vn);
  let sr = _scan_token(data, vp, doc);
  var sp = 0;
  var got = false;
  match sr {
    Ok(v) => { sp = v; got = true; },
    Err(_) => { got = false; },
  };
  if got {
    if doc.tkind == _TK_KEYWORD && doc.tkw == _KW_STREAM {
      let br = _parse_stream_body(doc, data, sp, oi, vn);
      match br {
        Ok(_) => { return _ok_int(oi); },
        Err(e) => { return _err_int(e); },
      };
    }
    if doc.tkind == _TK_KEYWORD && doc.tkw == _KW_ENDOBJ {
      return _ok_int(oi);
    }
  }
  return _err_int(_msg_at("missing endobj", vp));
}

// ---------------------------------------------------------------------------
//  Cross-reference entries and trailer fields
// ---------------------------------------------------------------------------

// True when the xref chain already visited offset `off`.
fn _visited(doc: &PdfDocument, off: Int) -> Bool {
  var i = 0;
  while i < doc.xref_sections.len() {
    let v: Int = doc.xref_sections[i];
    if v == off { return true; }
    i = i + 1;
  }
  return false;
}

// Index of the merged xref entry for object `num`, or -1.
fn _xref_find(doc: &PdfDocument, num: Int) -> Int {
  var i = 0;
  while i < doc.xr_num.len() {
    let v: Int = doc.xr_num[i];
    if v == num { return i; }
    i = i + 1;
  }
  return -1;
}

// Merge one entry; a higher priority (newer section, or xref stream over the
// hybrid classic table) replaces an existing entry.
fn _xref_merge(doc: &mut PdfDocument, num: Int, gen: Int, off: Int, kindv: Int, prio: Int) {
  let ex = _xref_find(doc, num);
  if ex < 0 {
    doc.xr_num.push(num);
    doc.xr_gen.push(gen);
    doc.xr_off.push(off);
    doc.xr_kind.push(kindv);
    doc.xr_prio.push(prio);
    return;
  }
  let p: Int = doc.xr_prio[ex];
  if prio > p {
    doc.xr_gen[ex] = gen;
    doc.xr_off[ex] = off;
    doc.xr_kind[ex] = kindv;
    doc.xr_prio[ex] = prio;
  }
}

// One classic 20-byte entry at pos: 10-digit offset, space, 5-digit
// generation, space, n/f, 1-2 byte EOL (CR/LF/CRLF, optionally after one
// space). Returns the position just past the entry.
fn _parse_xref_entry(doc: &mut PdfDocument, data: &Vec[UInt8], pos: Int, objnum: Int, prio: Int) -> Result[Int, Str] {
  let n = data.len();
  var i = pos;
  var off = 0;
  var k = 0;
  while k < 10 {
    if i >= n { return _err_int(_msg_at("malformed xref entry", pos)); }
    let b = _b(data, i);
    if !_is_digit(b) { return _err_int(_msg_at("malformed xref entry", pos)); }
    off = off * 10 + (b - _C_D0);
    i = i + 1;
    k = k + 1;
  }
  if i >= n || _b(data, i) != _C_SP { return _err_int(_msg_at("malformed xref entry", pos)); }
  i = i + 1;
  var g = 0;
  k = 0;
  while k < 5 {
    if i >= n { return _err_int(_msg_at("malformed xref entry", pos)); }
    let b2 = _b(data, i);
    if !_is_digit(b2) { return _err_int(_msg_at("malformed xref entry", pos)); }
    g = g * 10 + (b2 - _C_D0);
    i = i + 1;
    k = k + 1;
  }
  if i >= n || _b(data, i) != _C_SP { return _err_int(_msg_at("malformed xref entry", pos)); }
  i = i + 1;
  if i >= n { return _err_int(_msg_at("malformed xref entry", pos)); }
  let t = _b(data, i);
  if t != _C_LOWER_N && t != _C_LOWER_F { return _err_int(_msg_at("malformed xref entry", pos)); }
  i = i + 1;
  if i < n && _b(data, i) == _C_SP { i = i + 1; }
  if i >= n { return _err_int(_msg_at("malformed xref entry", pos)); }
  let e = _b(data, i);
  if e == _C_CR {
    i = i + 1;
    if i < n && _b(data, i) == _C_LF { i = i + 1; }
  } elif e == _C_LF {
    i = i + 1;
  } else {
    return _err_int(_msg_at("malformed xref entry", pos));
  }
  var kindv = _XK_FREE;
  if t == _C_LOWER_N { kindv = _XK_INUSE; }
  _xref_merge(doc, objnum, g, off, kindv, prio);
  return _ok_int(i);
}

// Parse a classic xref table at the "xref" keyword; subsections of
// "start count" 20-byte entries followed by one trailer dictionary.
fn _load_classic_xref(doc: &mut PdfDocument, data: &Vec[UInt8], at: Int, prio: Int) -> Result[Int, Str] {
  var p = at + 4;
  let n = data.len();
  loop {
    p = _skip_ws(data, p);
    if p >= n { return _err_int(_msg_at("unterminated xref table", at)); }
    if _match(data, p, "trailer") {
      let tp = p + 7;
      let vr = _parse_value_at(doc, data, tp, 0);
      var vp = 0;
      match vr {
        Ok(v) => { vp = v; },
        Err(e) => { return _err_int(e); },
      };
      let tn: Int = doc.tnode;
      if tn < 0 { return _err_int(_msg_at("bad trailer dictionary", tp)); }
      let tk: Int = doc.kind[tn];
      if tk != _NK_DICT { return _err_int(_msg_at("bad trailer dictionary", tp)); }
      if doc.trailer_node < 0 { doc.trailer_node = tn; }
      if doc.xref_type == _XT_NONE { doc.xref_type = _XT_TABLE; }
      doc.hybrid_scratch = -1;
      let rr = _record_trailer_fields(doc, data, tn, 1, prio);
      match rr {
        Ok(_) => {},
        Err(e) => { return _err_int(e); },
      };
      let hx: Int = doc.hybrid_scratch;
      if hx >= 0 {
        let hr = _xref_stream_section(doc, data, hx, 1, prio + 1);
        match hr {
          Ok(_) => {},
          Err(e) => { return _err_int(e); },
        };
      }
      return _ok_int(vp);
    }
    let r1 = _read_uint(doc, data, p);
    var p1 = 0;
    match r1 {
      Ok(v) => { p1 = v; },
      Err(_) => { return _err_int(_msg_at("bad xref subsection header", p)); },
    };
    let start: Int = doc.tnum;
    let p1s = _skip_ws(data, p1);
    let r2 = _read_uint(doc, data, p1s);
    var p2 = 0;
    match r2 {
      Ok(v) => { p2 = v; },
      Err(_) => { return _err_int(_msg_at("bad xref subsection header", p1s)); },
    };
    let count: Int = doc.tnum;
    if count > _PDF_MAX_XREF_ENTRIES || doc.xr_num.len() + count > _PDF_MAX_XREF_ENTRIES {
      return _err_int(_msg_at("too many xref entries", p));
    }
    var q = _skip_ws(data, p2);
    var k = 0;
    while k < count {
      let er = _parse_xref_entry(doc, data, q, start + k, prio);
      match er {
        Ok(v) => { q = v; },
        Err(e) => { return _err_int(e); },
      };
      k = k + 1;
    }
    p = q;
  }
  return _ok_int(0);
}

// Record trailer dictionary fields; fields are first-wins, so walking the
// chain newest-first keeps the newest /Root, /Info, /Encrypt, /ID, /Size.
fn _record_trailer_fields(doc: &mut PdfDocument, data: &Vec[UInt8], tn: Int, allow_hybrid: Int, prio: Int) -> Result[Int, Str] {
  let v = _dict_get_int(doc, tn, "Size");
  if v >= 0 && doc.trailer_size < 0 { doc.trailer_size = v; }
  let rv = _dict_get(doc, tn, "Root");
  if rv >= 0 && doc.root_num < 0 {
    let rk: Int = doc.kind[rv];
    if rk == _NK_REF {
      doc.root_num = doc.num[rv];
      doc.root_gen = doc.gen[rv];
    }
  }
  let iv = _dict_get(doc, tn, "Info");
  if iv >= 0 && doc.info_num < 0 {
    let ik: Int = doc.kind[iv];
    if ik == _NK_REF {
      doc.info_num = doc.num[iv];
      doc.info_gen = doc.gen[iv];
    }
  }
  let ev = _dict_get(doc, tn, "Encrypt");
  if ev >= 0 && doc.has_encrypt == 0 {
    let ek: Int = doc.kind[ev];
    doc.has_encrypt = 1;
    if ek == _NK_REF {
      doc.encrypt_num = doc.num[ev];
      doc.encrypt_gen = doc.gen[ev];
    }
  }
  let pv = _dict_get_int(doc, tn, "Prev");
  if pv >= 0 {
    doc.prev_scratch = pv;
    if doc.trailer_prev < 0 { doc.trailer_prev = pv; }
  }
  let idv = _dict_get(doc, tn, "ID");
  if idv >= 0 && doc.has_id == 0 {
    let idk: Int = doc.kind[idv];
    if idk == _NK_ARRAY {
      let kc: Int = doc.kid_count[idv];
      if kc >= 2 {
        let ks: Int = doc.kid_start[idv];
        let a: Int = doc.kids[ks];
        let b: Int = doc.kids[ks + 1];
        let ak: Int = doc.kind[a];
        let bk: Int = doc.kind[b];
        if ak == _NK_STRING && bk == _NK_STRING {
          doc.id0_start = doc.span_start[a];
          doc.id0_len = doc.span_len[a];
          doc.id1_start = doc.span_start[b];
          doc.id1_len = doc.span_len[b];
          doc.has_id = 1;
        }
      }
    }
  }
  if allow_hybrid == 1 {
    let xs = _dict_get_int(doc, tn, "XRefStm");
    if xs >= 0 {
      doc.xref_type = _XT_HYBRID;
      doc.hybrid_scratch = xs;
    }
  }
  return _ok_int(0);
}

// ---------------------------------------------------------------------------
//  Stream decoding for xref streams and object streams
// ---------------------------------------------------------------------------

// True when the filter node is a single FlateDecode (name or one-element
// array).
fn _filter_is_flate(doc: &PdfDocument, fv: Int) -> Bool {
  if fv < 0 { return false; }
  let fk: Int = doc.kind[fv];
  if fk == _NK_NAME {
    let ss: Int = doc.span_start[fv];
    let sl: Int = doc.span_len[fv];
    if _span_eq_str(doc, ss, sl, "FlateDecode") { return true; }
    return _span_eq_str(doc, ss, sl, "Fl");
  }
  if fk == _NK_ARRAY {
    let kc: Int = doc.kid_count[fv];
    if kc != 1 { return false; }
    let ks: Int = doc.kid_start[fv];
    let a: Int = doc.kids[ks];
    let ak: Int = doc.kind[a];
    if ak != _NK_NAME { return false; }
    let ss2: Int = doc.span_start[a];
    let sl2: Int = doc.span_len[a];
    if _span_eq_str(doc, ss2, sl2, "FlateDecode") { return true; }
    return _span_eq_str(doc, ss2, sl2, "Fl");
  }
  return false;
}

// True when /DecodeParms asks for the default predictor (or none).
fn _decode_parms_ok(doc: &PdfDocument, dn: Int) -> Bool {
  let dv = _dict_get(doc, dn, "DecodeParms");
  if dv < 0 { return true; }
  let dk: Int = doc.kind[dv];
  if dk == _NK_NULL { return true; }
  if dk == _NK_DICT {
    let pv = _dict_get_int(doc, dv, "Predictor");
    if pv < 0 { return true; }
    return pv <= 1;
  }
  if dk == _NK_ARRAY {
    let kc: Int = doc.kid_count[dv];
    if kc == 0 { return true; }
    let ks: Int = doc.kid_start[dv];
    let a: Int = doc.kids[ks];
    let ak: Int = doc.kind[a];
    if ak == _NK_NULL { return true; }
    if ak == _NK_DICT {
      let pv2 = _dict_get_int(doc, a, "Predictor");
      if pv2 < 0 { return true; }
      return pv2 <= 1;
    }
    return false;
  }
  return false;
}

// Copy the raw stream bytes of object entry oi from the stream pool.
fn _raw_stream_copy(doc: &PdfDocument, oi: Int) -> Vec[UInt8] {
  let ps: Int = doc.obj_stream_pool_start[oi];
  let pl: Int = doc.obj_stream_pool_len[oi];
  var out = Vec[UInt8].new();
  if ps < 0 || pl <= 0 { return out; }
  let n = doc.spool.len();
  var i = ps;
  while i < ps + pl && i < n {
    out.push(doc.spool[i]);
    i = i + 1;
  }
  return out;
}

// Decoded payload of the stream of object entry oi: raw when unfiltered,
// inflated for one FlateDecode filter; other filters or predictors > 1 are
// reported as errors and the caller flags the document.
fn _stream_decoded(doc: &PdfDocument, oi: Int) -> Result[Vec[UInt8], Str] {
  let raw = _raw_stream_copy(doc, oi);
  let dn: Int = doc.obj_stream_dict[oi];
  let fv = _dict_get(doc, dn, "Filter");
  if fv < 0 { return _ok_bytes(raw); }
  if !_filter_is_flate(doc, fv) { return _err_bytes("pdf: unsupported stream filter"); }
  if !_decode_parms_ok(doc, dn) { return _err_bytes("pdf: unsupported filter predictor"); }
  if raw.len() > _PDF_MAX_INFLATE_IN { return _err_bytes("pdf: stream too large to inflate"); }
  return _flate_decode_stream(&raw);
}

// Big-endian unsigned field of w bytes at pos (callers bound-check).
fn _read_be_field(buf: &Vec[UInt8], pos: Int, w: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < w {
    v = v * 256 + _b(buf, pos + i);
    i = i + 1;
  }
  return v;
}

// Parse an xref stream section: an indirect object whose value is a
// dictionary with /Type /XRef, /W [w0 w1 w2] and /Index pairs. entries_only
// skips the trailer-field recording (used for hybrid /XRefStm).
fn _xref_stream_section(doc: &mut PdfDocument, data: &Vec[UInt8], off: Int, entries_only: Int, prio: Int) -> Result[Int, Str] {
  let n = data.len();
  if off < 0 || off >= n { return _err_int(_msg_at("xref stream offset out of range", off)); }
  let or_ = _parse_indirect_at(doc, data, off, -1);
  var oi = 0;
  match or_ {
    Ok(v) => { oi = v; },
    Err(e) => { return _err_int(e); },
  };
  let vn: Int = doc.obj_node[oi];
  if vn < 0 { return _err_int(_msg_at("bad xref stream object", off)); }
  let vk: Int = doc.kind[vn];
  if vk != _NK_DICT { return _err_int(_msg_at("xref stream object is not a dictionary", off)); }
  let tnm = _dict_get_name(doc, vn, "Type");
  if compare.str_compare(tnm, "XRef") != 0 {
    return _err_int(_msg_at("missing /Type /XRef", off));
  }
  if entries_only == 0 {
    if doc.trailer_node < 0 { doc.trailer_node = vn; }
    if doc.xref_type == _XT_NONE { doc.xref_type = _XT_STREAM; }
  }
  let rr = _record_trailer_fields(doc, data, vn, 0, prio + 1);
  match rr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  let wv = _dict_get(doc, vn, "W");
  if wv < 0 { return _err_int(_msg_at("xref stream missing /W", off)); }
  let wk: Int = doc.kind[wv];
  if wk != _NK_ARRAY { return _err_int(_msg_at("bad xref stream /W", off)); }
  let wc: Int = doc.kid_count[wv];
  if wc != 3 { return _err_int(_msg_at("bad xref stream /W", off)); }
  let ws: Int = doc.kid_start[wv];
  let w0n: Int = doc.kids[ws];
  let w1n: Int = doc.kids[ws + 1];
  let w2n: Int = doc.kids[ws + 2];
  var w0 = 0;
  var w1 = 0;
  var w2 = 0;
  let k0: Int = doc.kind[w0n];
  let k1: Int = doc.kind[w1n];
  let k2: Int = doc.kind[w2n];
  if k0 != _NK_INT || k1 != _NK_INT || k2 != _NK_INT {
    return _err_int(_msg_at("bad xref stream /W", off));
  }
  w0 = doc.num[w0n];
  w1 = doc.num[w1n];
  w2 = doc.num[w2n];
  if w0 < 0 || w1 < 0 || w2 < 0 || w0 > 8 || w1 > 8 || w2 > 8 {
    return _err_int(_msg_at("bad xref stream /W", off));
  }
  let dec_r = _stream_decoded(doc, oi);
  if !dec_r.is_ok {
    doc.xref_decode_error = "pdf: xref stream decode failed";
    return _ok_int(0);
  }
  let dec: Vec[UInt8] = dec_r.value;
  var rstart = Vec[Int].new();
  var rcount = Vec[Int].new();
  let iv = _dict_get(doc, vn, "Index");
  if iv < 0 {
    let size = _dict_get_int(doc, vn, "Size");
    if size < 0 { return _err_int(_msg_at("xref stream missing /Size", off)); }
    rstart.push(0);
    rcount.push(size);
  } else {
    let ik: Int = doc.kind[iv];
    if ik != _NK_ARRAY { return _err_int(_msg_at("bad xref stream /Index", off)); }
    let ic: Int = doc.kid_count[iv];
    if ic % 2 != 0 { return _err_int(_msg_at("bad xref stream /Index", off)); }
    let isx: Int = doc.kid_start[iv];
    var k = 0;
    while k < ic {
      let a: Int = doc.kids[isx + k];
      let b: Int = doc.kids[isx + k + 1];
      let ak: Int = doc.kind[a];
      let bk: Int = doc.kind[b];
      if ak != _NK_INT || bk != _NK_INT { return _err_int(_msg_at("bad xref stream /Index", off)); }
      let av: Int = doc.num[a];
      let bv: Int = doc.num[b];
      if av < 0 || bv < 0 { return _err_int(_msg_at("bad xref stream /Index", off)); }
      rstart.push(av);
      rcount.push(bv);
      k = k + 2;
    }
  }
  let elen = w0 + w1 + w2;
  if elen <= 0 { return _err_int(_msg_at("bad xref stream /W", off)); }
  var pos = 0;
  var ri = 0;
  while ri < rstart.len() {
    let s: Int = rstart[ri];
    let c: Int = rcount[ri];
    if c > _PDF_MAX_XREF_ENTRIES || doc.xr_num.len() + c > _PDF_MAX_XREF_ENTRIES {
      return _err_int(_msg_at("too many xref entries", off));
    }
    var kk = 0;
    while kk < c {
      if pos + elen > dec.len() {
        return _err_int(_msg_at("truncated xref stream data", off));
      }
      let f1 = _read_be_field(&dec, pos, w0);
      let f2 = _read_be_field(&dec, pos + w0, w1);
      let f3 = _read_be_field(&dec, pos + w0 + w1, w2);
      pos = pos + elen;
      if f1 < 0 || f2 < 0 || f3 < 0 {
        return _err_int(_msg_at("xref stream field overflow", off));
      }
      var tk = 1;
      if w0 > 0 { tk = f1; }
      if tk == 0 {
        _xref_merge(doc, s + kk, f3, 0, _XK_FREE, prio);
      } elif tk == 1 {
        _xref_merge(doc, s + kk, f3, f2, _XK_INUSE, prio);
      } elif tk == 2 {
        _xref_merge(doc, s + kk, f3, f2, _XK_OBJSTM, prio);
      }
      kk = kk + 1;
    }
    ri = ri + 1;
  }
  return _ok_int(0);
}

// Load one cross-reference section at `off` (classic table or stream).
fn _load_xref_section(doc: &mut PdfDocument, data: &Vec[UInt8], off: Int, prio: Int) -> Result[Int, Str] {
  let n = data.len();
  if off < 0 || off >= n { return _err_int(_msg_at("xref offset out of range", off)); }
  let p = _skip_ws(data, off);
  if _match(data, p, "xref") {
    return _load_classic_xref(doc, data, p, prio);
  }
  return _xref_stream_section(doc, data, p, 0, prio);
}

// Walk startxref -> /Prev chain with a visited guard and a section cap; the
// newest section is processed first (priority 0) so first-wins trailer
// fields and priority-based entry merges keep the newest data.
fn _load_xref_chain(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  var off = doc.startxref;
  var g = 0;
  while off >= 0 && g < _PDF_MAX_XREF_SECTIONS {
    if _visited(doc, off) { break; }
    doc.xref_sections.push(off);
    doc.prev_scratch = -1;
    let pr = (_PDF_MAX_XREF_SECTIONS - g) * 2;
    let r = _load_xref_section(doc, data, off, pr);
    match r {
      Ok(_) => {},
      Err(e) => { return _err_int(e); },
    };
    off = doc.prev_scratch;
    g = g + 1;
  }
  return _ok_int(0);
}

// ---------------------------------------------------------------------------
//  Header, startxref, object map, object streams
// ---------------------------------------------------------------------------

// Locate "%PDF-" within the first 1024 bytes and record the version token.
fn _read_header(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  let hit = _find(data, 0, "%PDF-");
  if hit < 0 || hit > 1024 { return _err_int(_msg_at("missing PDF header", 0)); }
  let n = data.len();
  var i = hit + 5;
  let vstart = i;
  while i < n && i < vstart + 16 {
    let b = _b(data, i);
    if _is_ws(b) || b == _C_PERCENT { break; }
    i = i + 1;
  }
  if i == vstart { return _err_int(_msg_at("bad PDF header version", hit)); }
  let c0 = _b(data, vstart);
  if !_is_digit(c0) { return _err_int(_msg_at("bad PDF header version", hit)); }
  var has_dot = false;
  var k = vstart;
  while k < i {
    if _b(data, k) == _C_DOT { has_dot = true; }
    k = k + 1;
  }
  if !has_dot { return _err_int(_msg_at("bad PDF header version", hit)); }
  doc.header_offset = hit;
  doc.version = _span_str(data, vstart, i);
  return _ok_int(i);
}

// Find the LAST "startxref" keyword and read its offset value.
fn _read_startxref(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  let n = data.len();
  var last = -1;
  var i = 0;
  while i + 9 <= n {
    if _match(data, i, "startxref") {
      last = i;
      i = i + 9;
    } else {
      i = i + 1;
    }
  }
  if last < 0 { return _err_int(_msg_at("missing startxref", n)); }
  let p = _skip_ws(data, last + 9);
  let r = _read_uint(doc, data, p);
  var q = 0;
  match r {
    Ok(v) => { q = v; },
    Err(_) => { return _err_int(_msg_at("bad startxref value", p)); },
  };
  doc.startxref = doc.tnum;
  return _ok_int(q);
}

// Index of the parsed object entry for object `num`, or -1.
fn _object_index_of(doc: &PdfDocument, num: Int) -> Int {
  var i = 0;
  while i < doc.obj_num.len() {
    let v: Int = doc.obj_num[i];
    if v == num { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `x` is present in the local vector v.
fn _int_seen(v: &Vec[Int], x: Int) -> Bool {
  var i = 0;
  while i < v.len() {
    let e: Int = v[i];
    if e == x { return true; }
    i = i + 1;
  }
  return false;
}

// Parse every in-use xref entry, then resolve object streams and indirect
// /Length references. Structural errors abort the open.
fn _build_object_map(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  var i = 0;
  while i < doc.xr_num.len() {
    let k: Int = doc.xr_kind[i];
    if k == _XK_INUSE {
      let num: Int = doc.xr_num[i];
      if _object_index_of(doc, num) < 0 {
        let off: Int = doc.xr_off[i];
        let r = _parse_indirect_at(doc, data, off, num);
        match r {
          Ok(_) => {},
          Err(e) => { return _err_int(e); },
        };
      }
    }
    i = i + 1;
  }
  let s = _load_object_streams(doc, data);
  match s {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  let l = _resolve_stream_lengths(doc, data);
  match l {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  return _ok_int(0);
}

// Decode every distinct object stream referenced by _XK_OBJSTM entries and
// extract the objects it carries.
fn _load_object_streams(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  var seen = Vec[Int].new();
  var si = 0;
  while si < doc.xr_num.len() {
    let k: Int = doc.xr_kind[si];
    if k == _XK_OBJSTM {
      let sn: Int = doc.xr_off[si];
      if !_int_seen(&seen, sn) {
        seen.push(sn);
        let oi = _object_index_of(doc, sn);
        if oi >= 0 {
          let is_stream: Int = doc.obj_stream[oi];
          if is_stream == 1 {
            let dr = _stream_decoded(doc, oi);
            if dr.is_ok {
              let dec: Vec[UInt8] = dr.value;
              doc.objstm_used = 1;
              let er = _extract_objstm(doc, &dec, oi, sn);
              match er {
                Ok(_) => {},
                Err(e) => { return _err_int(e); },
              };
            } else {
              doc.xref_decode_error = "pdf: object stream decode failed";
            }
          }
        }
      }
    }
    si = si + 1;
  }
  return _ok_int(0);
}

// Extract the objects of one decoded object stream: N pairs of
// (object number, relative offset), objects at First + offset.
fn _extract_objstm(doc: &mut PdfDocument, dec: &Vec[UInt8], oi: Int, sn: Int) -> Result[Int, Str] {
  let dn: Int = doc.obj_stream_dict[oi];
  let nv = _dict_get_int(doc, dn, "N");
  let fv = _dict_get_int(doc, dn, "First");
  if nv < 0 || fv < 0 {
    return _err_int(_msg_at("bad object stream header", doc.obj_stream_data_start[oi]));
  }
  if nv > _PDF_MAX_OBJSTM_N {
    return _err_int(_msg_at("object stream too large", doc.obj_stream_data_start[oi]));
  }
  var pnums = Vec[Int].new();
  var poffs = Vec[Int].new();
  var p = 0;
  let dn_len = dec.len();
  var k = 0;
  while k < nv {
    let r1 = _read_uint(doc, dec, p);
    var p1 = 0;
    match r1 {
      Ok(v) => { p1 = v; },
      Err(_) => { return _err_int(_msg_at("bad object stream entry", p)); },
    };
    pnums.push(doc.tnum);
    let p1s = _skip_ws(dec, p1);
    let r2 = _read_uint(doc, dec, p1s);
    var p2 = 0;
    match r2 {
      Ok(v) => { p2 = v; },
      Err(_) => { return _err_int(_msg_at("bad object stream entry", p1s)); },
    };
    poffs.push(doc.tnum);
    p = _skip_ws(dec, p2);
    k = k + 1;
  }
  k = 0;
  while k < nv {
    let onum: Int = pnums[k];
    let ooff: Int = poffs[k];
    let abs = fv + ooff;
    if abs >= 0 && abs < dn_len {
      if _object_index_of(doc, onum) < 0 {
        let vr = _parse_value_at(doc, dec, abs, 0);
        var vp = 0;
        match vr {
          Ok(v) => { vp = v; },
          Err(e) => { return _err_int(e); },
        };
        let vn: Int = doc.tnode;
        let base: Int = doc.obj_stream_data_start[oi];
        let no = _push_object(doc, onum, 0, base + abs, vn);
        doc.in_objstm[no] = 1;
      }
    }
    k = k + 1;
  }
  return _ok_int(0);
}

// Resolve indirect /Length references recorded as _LS_SCANNED_REF: when the
// referenced integer lands exactly on endstream, re-bound the stream bytes.
fn _resolve_stream_lengths(doc: &mut PdfDocument, data: &Vec[UInt8]) -> Result[Int, Str] {
  var i = 0;
  while i < doc.obj_num.len() {
    let st: Int = doc.obj_stream[i];
    if st == 1 {
      let src: Int = doc.obj_stream_src[i];
      let lnum: Int = doc.obj_stream_len_num[i];
      if src == _LS_SCANNED_REF && lnum >= 0 {
        let li = _object_index_of(doc, lnum);
        if li >= 0 {
          let ln: Int = doc.obj_node[li];
          if ln >= 0 {
            let lk: Int = doc.kind[ln];
            if lk == _NK_INT {
              let v: Int = doc.num[ln];
              let dstart: Int = doc.obj_stream_data_start[i];
              if v >= 0 && dstart + v <= data.len() && _endstream_follows(data, dstart + v) {
                let pstart = _spool_append(doc, data, dstart, dstart + v);
                doc.obj_stream_data_len[i] = v;
                doc.obj_stream_declared[i] = v;
                doc.obj_stream_src[i] = _LS_INDIRECT;
                doc.obj_stream_pool_start[i] = pstart;
                doc.obj_stream_pool_len[i] = v;
              }
            }
          }
        }
      }
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// ---------------------------------------------------------------------------
//  Page tree and Info dictionary
// ---------------------------------------------------------------------------

// Record one leaf page (node index and object number, -1 for a direct dict).
fn _add_page(doc: &mut PdfDocument, node: Int, objnum: Int) {
  if doc.page_nodes.len() >= _PDF_MAX_PAGES { return; }
  doc.page_nodes.push(node);
  doc.page_obj_nums.push(objnum);
}

// True when page-tree node `node` was already visited in this walk.
fn _seen_node(doc: &PdfDocument, node: Int) -> Bool {
  var i = 0;
  while i < doc.page_seen.len() {
    let e: Int = doc.page_seen[i];
    if e == node { return true; }
    i = i + 1;
  }
  return false;
}

// Walk one page-tree node: /Kids arrays recurse, anything else counts as a
// leaf page. Depth-capped and cycle-guarded.
fn _walk_pages_node(doc: &mut PdfDocument, node: Int, depth: Int) {
  if node < 0 { return; }
  if depth > _PDF_MAX_PAGE_DEPTH {
    doc.pages_depth_capped = 1;
    return;
  }
  if _seen_node(doc, node) { return; }
  doc.page_seen.push(node);
  let kids = _dict_get(doc, node, "Kids");
  if kids < 0 { return; }
  let kk: Int = doc.kind[kids];
  if kk != _NK_ARRAY { return; }
  let kc: Int = doc.kid_count[kids];
  let ks: Int = doc.kid_start[kids];
  var i = 0;
  while i < kc {
    let cn: Int = doc.kids[ks + i];
    let ck: Int = doc.kind[cn];
    if ck == _NK_REF {
      let onum: Int = doc.num[cn];
      let oi = _object_index_of(doc, onum);
      if oi >= 0 {
        let kn: Int = doc.obj_node[oi];
        if kn >= 0 {
          let kd: Int = doc.kind[kn];
          if kd == _NK_DICT {
            let kkids = _dict_get(doc, kn, "Kids");
            if kkids >= 0 {
              let kkk: Int = doc.kind[kkids];
              if kkk == _NK_ARRAY {
                _walk_pages_node(doc, kn, depth + 1);
              } else {
                _add_page(doc, kn, onum);
              }
            } else {
              _add_page(doc, kn, onum);
            }
          }
        }
      }
    } elif ck == _NK_DICT {
      let kkids2 = _dict_get(doc, cn, "Kids");
      if kkids2 >= 0 {
        let kkk2: Int = doc.kind[kkids2];
        if kkk2 == _NK_ARRAY {
          _walk_pages_node(doc, cn, depth + 1);
        } else {
          _add_page(doc, cn, -1);
        }
      } else {
        _add_page(doc, cn, -1);
      }
    }
    i = i + 1;
  }
}

// Resolve the catalog's /Pages reference, record /Count and walk the tree.
fn _collect_pages(doc: &mut PdfDocument) -> Result[Int, Str] {
  if doc.root_num < 0 { return _ok_int(0); }
  let ri = _object_index_of(doc, doc.root_num);
  if ri < 0 { return _ok_int(0); }
  let rn: Int = doc.obj_node[ri];
  if rn < 0 { return _ok_int(0); }
  let rk: Int = doc.kind[rn];
  if rk != _NK_DICT { return _ok_int(0); }
  let pv = _dict_get(doc, rn, "Pages");
  if pv < 0 { return _ok_int(0); }
  let pk: Int = doc.kind[pv];
  if pk != _NK_REF { return _ok_int(0); }
  let pnum: Int = doc.num[pv];
  doc.pages_root_num = pnum;
  let pi = _object_index_of(doc, pnum);
  if pi < 0 { return _ok_int(0); }
  let pn: Int = doc.obj_node[pi];
  if pn < 0 { return _ok_int(0); }
  let pnk: Int = doc.kind[pn];
  if pnk != _NK_DICT { return _ok_int(0); }
  doc.declared_page_count = _dict_get_int(doc, pn, "Count");
  _walk_pages_node(doc, pn, 0);
  return _ok_int(0);
}

// Store one Info field pool span (0 Title, 1 Author, 2 Subject, 3 Date).
fn _info_store(doc: &mut PdfDocument, dict: Int, slot: Int, key: Str) {
  let v = _dict_get(doc, dict, key);
  if v < 0 { return; }
  let vk: Int = doc.kind[v];
  if vk != _NK_STRING { return; }
  doc.info_span_start[slot] = doc.span_start[v];
  doc.info_span_len[slot] = doc.span_len[v];
}

// Extract Title/Author/Subject/CreationDate spans from the Info dictionary.
fn _collect_info(doc: &mut PdfDocument) {
  var k = 0;
  while k < 4 {
    doc.info_span_start.push(-1);
    doc.info_span_len.push(0);
    k = k + 1;
  }
  if doc.info_num < 0 { return; }
  let oi = _object_index_of(doc, doc.info_num);
  if oi < 0 { return; }
  let n: Int = doc.obj_node[oi];
  if n < 0 { return; }
  let nk: Int = doc.kind[n];
  if nk != _NK_DICT { return; }
  _info_store(doc, n, 0, "Title");
  _info_store(doc, n, 1, "Author");
  _info_store(doc, n, 2, "Subject");
  _info_store(doc, n, 3, "CreationDate");
}

// ---------------------------------------------------------------------------
//  Public: open
// ---------------------------------------------------------------------------

/// Parse a whole PDF document's structure: header, cross-reference chain
/// (classic tables, xref streams and hybrid files), trailer fields, every
/// in-use object with its optional stream, object streams and the page tree.
/// Params: data - the whole file as bytes.
/// Returns: Ok(PdfDocument) on success; Err("pdf: ... at <byte offset>") for
/// the first structural error (missing header/startxref, malformed xref
/// entry, bad object header, unterminated container/string, missing endobj).
/// Filter decode failures and unresolvable indirect /Length references are
/// NOT errors: they are flagged (xref_decode_error, stream length source) and
/// the raw stream bytes stay available.
/// Error case: structural errors listed above.
/// Complexity: O(file length).
pub fn pdf_open(data: &Vec[UInt8]) -> Result[PdfDocument, Str] {
  var doc = _new_document(_copy_vec(data));
  let h = _read_header(&mut doc, data);
  match h {
    Ok(_) => {},
    Err(e) => { return _err_doc(e); },
  };
  let s = _read_startxref(&mut doc, data);
  match s {
    Ok(_) => {},
    Err(e) => { return _err_doc(e); },
  };
  let x = _load_xref_chain(&mut doc, data);
  match x {
    Ok(_) => {},
    Err(e) => { return _err_doc(e); },
  };
  let o = _build_object_map(&mut doc, data);
  match o {
    Ok(_) => {},
    Err(e) => { return _err_doc(e); },
  };
  let p = _collect_pages(&mut doc);
  match p {
    Ok(_) => {},
    Err(e) => { return _err_doc(e); },
  };
  _collect_info(&mut doc);
  return _ok_doc(doc);
}

// ---------------------------------------------------------------------------
//  Local DEFLATE/zlib decoder (RFC 1951 / RFC 1950)
// ---------------------------------------------------------------------------

// LSB-first bit reader: `pos` is the current byte, `bit` (0..7) the next bit.
type _FlBits = {
  pos: Int;
  bit: Int;
}

// Canonical Huffman table: count[len] is the number of codes of that length
// (1..15) and symbol the symbols sorted by (length, symbol).
type _FlHuff = {
  count: Vec[Int];
  symbol: Vec[Int];
}

// New bit reader at byte pos, bit 0.
fn _fl_bits_new(pos: Int) -> _FlBits {
  return _FlBits{
    pos: pos;
    bit: 0;
  };
}

// Bits remaining from the reader position (>= 0).
fn _fl_bits_left(data: &Vec[UInt8], br: &mut _FlBits) -> Int {
  let n = data.len();
  return (n - br.pos) * 8 - br.bit;
}

// Read n (0..16) bits LSB-first; callers guarantee _fl_bits_left >= n.
fn _fl_bits_take(data: &Vec[UInt8], br: &mut _FlBits, n: Int) -> Int {
  var v = 0;
  var mult = 1;
  var i = 0;
  while i < n {
    let byte = _b(data, br.pos);
    var div = 1;
    var k = 0;
    while k < br.bit {
      div = div * 2;
      k = k + 1;
    }
    let bit = (byte / div) % 2;
    v = v + bit * mult;
    mult = mult * 2;
    br.bit = br.bit + 1;
    if br.bit == 8 {
      br.bit = 0;
      br.pos = br.pos + 1;
    }
    i = i + 1;
  }
  return v;
}

// Skip to the next byte boundary (stored-block alignment).
fn _fl_bits_align(br: &mut _FlBits) {
  if br.bit != 0 {
    br.bit = 0;
    br.pos = br.pos + 1;
  }
}

// New empty Huffman table.
fn _fl_huff_new() -> _FlHuff {
  var c = Vec[Int].new();
  var i = 0;
  while i < 16 {
    c.push(0);
    i = i + 1;
  }
  return _FlHuff{
    count: c;
    symbol: Vec[Int].new();
  };
}

// Build the canonical table from the first n entries of `lengths` (0..15).
// Returns "" on success or an offset-free message.
fn _fl_huff_build(h: &mut _FlHuff, lengths: &Vec[Int], n: Int) -> Str {
  var i = 0;
  while i < 16 {
    h.count[i] = 0;
    i = i + 1;
  }
  i = 0;
  while i < n {
    let l: Int = lengths[i];
    if l < 0 || l > 15 { return "invalid code length"; }
    h.count[l] = h.count[l] + 1;
    i = i + 1;
  }
  var offs = Vec[Int].new();
  offs.push(0);
  var s = 0;
  var lv = 1;
  while lv <= 15 {
    offs.push(s);
    s = s + h.count[lv];
    lv = lv + 1;
  }
  h.symbol = Vec[Int].new();
  i = 0;
  while i < n {
    h.symbol.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let l2: Int = lengths[i];
    if l2 != 0 {
      let o: Int = offs[l2];
      h.symbol[o] = i;
      offs[l2] = o + 1;
    }
    i = i + 1;
  }
  return "";
}

// Decode one symbol (>= 0), -1 for an invalid code or -2 when the input runs
// out mid-code.
fn _fl_huff_decode(data: &Vec[UInt8], br: &mut _FlBits, h: &_FlHuff) -> Int {
  var code = 0;
  var first = 0;
  var index = 0;
  var len = 1;
  while len <= 15 {
    if _fl_bits_left(data, br) < 1 { return -2; }
    let bit = _fl_bits_take(data, br, 1);
    code = code * 2 + bit;
    let cnt: Int = h.count[len];
    if code - first < cnt {
      let si = index + (code - first);
      let sym: Int = h.symbol[si];
      return sym;
    }
    index = index + cnt;
    first = first + cnt;
    first = first * 2;
    len = len + 1;
  }
  return -1;
}

// RFC 1951 literal/length base values for symbols 257..285.
fn _fl_length_bases() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(3);
  v.push(4);
  v.push(5);
  v.push(6);
  v.push(7);
  v.push(8);
  v.push(9);
  v.push(10);
  v.push(11);
  v.push(13);
  v.push(15);
  v.push(17);
  v.push(19);
  v.push(23);
  v.push(27);
  v.push(31);
  v.push(35);
  v.push(43);
  v.push(51);
  v.push(59);
  v.push(67);
  v.push(83);
  v.push(99);
  v.push(115);
  v.push(131);
  v.push(163);
  v.push(195);
  v.push(227);
  v.push(258);
  return v;
}

// RFC 1951 extra bits for length symbols 257..285.
fn _fl_length_extras() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(1);
  v.push(1);
  v.push(1);
  v.push(1);
  v.push(2);
  v.push(2);
  v.push(2);
  v.push(2);
  v.push(3);
  v.push(3);
  v.push(3);
  v.push(3);
  v.push(4);
  v.push(4);
  v.push(4);
  v.push(4);
  v.push(5);
  v.push(5);
  v.push(5);
  v.push(5);
  v.push(0);
  return v;
}

// RFC 1951 distance base values for symbols 0..29.
fn _fl_dist_bases() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(1);
  v.push(2);
  v.push(3);
  v.push(4);
  v.push(5);
  v.push(7);
  v.push(9);
  v.push(13);
  v.push(17);
  v.push(25);
  v.push(33);
  v.push(49);
  v.push(65);
  v.push(97);
  v.push(129);
  v.push(193);
  v.push(257);
  v.push(385);
  v.push(513);
  v.push(769);
  v.push(1025);
  v.push(1537);
  v.push(2049);
  v.push(3073);
  v.push(4097);
  v.push(6145);
  v.push(8193);
  v.push(12289);
  v.push(16385);
  v.push(24577);
  return v;
}

// RFC 1951 extra bits for distance symbols 0..29.
fn _fl_dist_extras() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(1);
  v.push(1);
  v.push(2);
  v.push(2);
  v.push(3);
  v.push(3);
  v.push(4);
  v.push(4);
  v.push(5);
  v.push(5);
  v.push(6);
  v.push(6);
  v.push(7);
  v.push(7);
  v.push(8);
  v.push(8);
  v.push(9);
  v.push(9);
  v.push(10);
  v.push(10);
  v.push(11);
  v.push(11);
  v.push(12);
  v.push(12);
  v.push(13);
  v.push(13);
  return v;
}

// RFC 1951 code-length-code transmission order.
fn _fl_cl_order() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(16);
  v.push(17);
  v.push(18);
  v.push(0);
  v.push(8);
  v.push(7);
  v.push(9);
  v.push(6);
  v.push(10);
  v.push(5);
  v.push(11);
  v.push(4);
  v.push(12);
  v.push(3);
  v.push(13);
  v.push(2);
  v.push(14);
  v.push(1);
  v.push(15);
  return v;
}

// Code lengths of the fixed literal/length alphabet (288 entries).
fn _fl_fixed_lit_lengths() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i <= 143 {
    v.push(8);
    i = i + 1;
  }
  i = 144;
  while i <= 255 {
    v.push(9);
    i = i + 1;
  }
  i = 256;
  while i <= 279 {
    v.push(7);
    i = i + 1;
  }
  i = 280;
  while i <= 287 {
    v.push(8);
    i = i + 1;
  }
  return v;
}

// Code lengths of the fixed distance alphabet (30 entries).
fn _fl_fixed_dist_lengths() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < 30 {
    v.push(5);
    i = i + 1;
  }
  return v;
}

// Append data[start, end) to out.
fn _fl_append_range(out: &mut Vec[UInt8], data: &Vec[UInt8], start: Int, end: Int) {
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
}

// Decode one stored (BTYPE 00) block; returns "" on success.
fn _fl_decode_stored(data: &Vec[UInt8], br: &mut _FlBits, out: &mut Vec[UInt8]) -> Str {
  _fl_bits_align(br);
  if br.pos + 4 > data.len() {
    return _fl_msg("truncated stored block", br.pos);
  }
  let len = _b(data, br.pos) + _b(data, br.pos + 1) * 256;
  let nlen = _b(data, br.pos + 2) + _b(data, br.pos + 3) * 256;
  if len + nlen != 65535 {
    return _fl_msg("stored block length check failed", br.pos);
  }
  if br.pos + 4 + len > data.len() {
    return _fl_msg("truncated stored block", br.pos);
  }
  if out.len() + len > _PDF_MAX_INFLATE_OUT {
    return _fl_msg("inflated output too large", br.pos);
  }
  _fl_append_range(out, data, br.pos + 4, br.pos + 4 + len);
  br.pos = br.pos + 4 + len;
  br.bit = 0;
  return "";
}

// Decode one Huffman (fixed or dynamic) block up to the end-of-block symbol.
fn _fl_decode_huffman_block(data: &Vec[UInt8], br: &mut _FlBits, out: &mut Vec[UInt8], lit: &_FlHuff, dist: &_FlHuff) -> Str {
  let lbases = _fl_length_bases();
  let lextras = _fl_length_extras();
  let dbases = _fl_dist_bases();
  let dextras = _fl_dist_extras();
  var keep = 1;
  while keep == 1 {
    if _fl_bits_left(data, br) < 1 {
      return _fl_msg("truncated huffman block", br.pos);
    }
    let sym = _fl_huff_decode(data, br, lit);
    if sym == -2 { return _fl_msg("truncated huffman block", br.pos); }
    if sym == -1 { return _fl_msg("invalid literal/length code", br.pos); }
    if sym < 256 {
      if out.len() >= _PDF_MAX_INFLATE_OUT {
        return _fl_msg("inflated output too large", br.pos);
      }
      out.push(sym as UInt8);
    } elif sym == 256 {
      return "";
    } else {
      if sym > 285 {
        return _fl_msg("invalid length symbol", br.pos);
      }
      let li = sym - 257;
      let lb: Int = lbases[li];
      let lx: Int = lextras[li];
      if _fl_bits_left(data, br) < lx {
        return _fl_msg("truncated length extra bits", br.pos);
      }
      let length = lb + _fl_bits_take(data, br, lx);
      if _fl_bits_left(data, br) < 1 {
        return _fl_msg("truncated huffman block", br.pos);
      }
      let dsym = _fl_huff_decode(data, br, dist);
      if dsym == -2 { return _fl_msg("truncated huffman block", br.pos); }
      if dsym == -1 || dsym > 29 {
        return _fl_msg("invalid distance code", br.pos);
      }
      let db: Int = dbases[dsym];
      let dx: Int = dextras[dsym];
      if _fl_bits_left(data, br) < dx {
        return _fl_msg("truncated distance extra bits", br.pos);
      }
      let distance = db + _fl_bits_take(data, br, dx);
      if distance < 1 || distance > out.len() {
        return _fl_msg("distance too far back", br.pos);
      }
      if out.len() + length > _PDF_MAX_INFLATE_OUT {
        return _fl_msg("inflated output too large", br.pos);
      }
      var src = out.len() - distance;
      var k = 0;
      while k < length {
        let b: UInt8 = out[src];
        out.push(b);
        src = src + 1;
        k = k + 1;
      }
    }
  }
  return "";
}

// Decode a fixed-Huffman (BTYPE 01) block.
fn _fl_decode_fixed(data: &Vec[UInt8], br: &mut _FlBits, out: &mut Vec[UInt8]) -> Str {
  var lit = _fl_huff_new();
  let ll = _fl_fixed_lit_lengths();
  let e1 = _fl_huff_build(&mut lit, &ll, 288);
  if e1.len() > 0 { return _fl_msg(e1, br.pos); }
  var dist = _fl_huff_new();
  let dl = _fl_fixed_dist_lengths();
  let e2 = _fl_huff_build(&mut dist, &dl, 30);
  if e2.len() > 0 { return _fl_msg(e2, br.pos); }
  return _fl_decode_huffman_block(data, br, out, &lit, &dist);
}

// Decode a dynamic-Huffman (BTYPE 10) block header and its symbols.
fn _fl_decode_dynamic(data: &Vec[UInt8], br: &mut _FlBits, out: &mut Vec[UInt8]) -> Str {
  if _fl_bits_left(data, br) < 14 {
    return _fl_msg("truncated dynamic header", br.pos);
  }
  let hlit = _fl_bits_take(data, br, 5) + 257;
  let hdist = _fl_bits_take(data, br, 5) + 1;
  let hclen = _fl_bits_take(data, br, 4) + 4;
  if hlit > 286 { return _fl_msg("too many literal/length codes", br.pos); }
  if hdist > 30 { return _fl_msg("too many distance codes", br.pos); }
  let order = _fl_cl_order();
  var cl = Vec[Int].new();
  var i = 0;
  while i < 19 {
    cl.push(0);
    i = i + 1;
  }
  i = 0;
  while i < hclen {
    if _fl_bits_left(data, br) < 3 {
      return _fl_msg("truncated dynamic header", br.pos);
    }
    let v = _fl_bits_take(data, br, 3);
    let oi: Int = order[i];
    cl[oi] = v;
    i = i + 1;
  }
  var clh = _fl_huff_new();
  let e1 = _fl_huff_build(&mut clh, &cl, 19);
  if e1.len() > 0 { return _fl_msg(e1, br.pos); }
  let total = hlit + hdist;
  var lengths = Vec[Int].new();
  i = 0;
  while i < total {
    lengths.push(0);
    i = i + 1;
  }
  var filled = 0;
  while filled < total {
    if _fl_bits_left(data, br) < 1 {
      return _fl_msg("truncated dynamic lengths", br.pos);
    }
    let sym = _fl_huff_decode(data, br, &clh);
    if sym == -2 { return _fl_msg("truncated dynamic lengths", br.pos); }
    if sym == -1 { return _fl_msg("invalid code length symbol", br.pos); }
    if sym <= 15 {
      lengths[filled] = sym;
      filled = filled + 1;
    } elif sym == 16 {
      if filled == 0 { return _fl_msg("repeat with no previous length", br.pos); }
      if _fl_bits_left(data, br) < 2 {
        return _fl_msg("truncated dynamic lengths", br.pos);
      }
      let rep = 3 + _fl_bits_take(data, br, 2);
      if filled + rep > total {
        return _fl_msg("code length repeat overflow", br.pos);
      }
      let prev: Int = lengths[filled - 1];
      var k = 0;
      while k < rep {
        lengths[filled] = prev;
        filled = filled + 1;
        k = k + 1;
      }
    } else {
      var rep2 = 0;
      if sym == 17 {
        if _fl_bits_left(data, br) < 3 {
          return _fl_msg("truncated dynamic lengths", br.pos);
        }
        rep2 = 3 + _fl_bits_take(data, br, 3);
      } else {
        if _fl_bits_left(data, br) < 7 {
          return _fl_msg("truncated dynamic lengths", br.pos);
        }
        rep2 = 11 + _fl_bits_take(data, br, 7);
      }
      if filled + rep2 > total {
        return _fl_msg("code length repeat overflow", br.pos);
      }
      var k2 = 0;
      while k2 < rep2 {
        lengths[filled] = 0;
        filled = filled + 1;
        k2 = k2 + 1;
      }
    }
  }
  let eob: Int = lengths[256];
  if eob == 0 { return _fl_msg("missing end-of-block code", br.pos); }
  var lit = _fl_huff_new();
  let e2 = _fl_huff_build(&mut lit, &lengths, hlit);
  if e2.len() > 0 { return _fl_msg(e2, br.pos); }
  var dl = Vec[Int].new();
  i = 0;
  while i < hdist {
    let lv: Int = lengths[hlit + i];
    dl.push(lv);
    i = i + 1;
  }
  var dist = _fl_huff_new();
  let e3 = _fl_huff_build(&mut dist, &dl, hdist);
  if e3.len() > 0 { return _fl_msg(e3, br.pos); }
  return _fl_decode_huffman_block(data, br, out, &lit, &dist);
}

// Raw DEFLATE block loop shared by the raw and zlib entry points; returns
// the offset just past the last byte carrying stream bits.
fn _fl_inflate_stream(data: &Vec[UInt8], start: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if start < 0 || start > data.len() {
    return _err_int(_fl_msg("bad deflate start", start));
  }
  var br = _fl_bits_new(start);
  var fin = 0;
  while fin == 0 {
    if _fl_bits_left(data, &mut br) < 3 {
      return _err_int(_fl_msg("truncated deflate block header", br.pos));
    }
    fin = _fl_bits_take(data, &mut br, 1);
    let btype = _fl_bits_take(data, &mut br, 2);
    var e = "";
    if btype == 0 {
      e = _fl_decode_stored(data, &mut br, out);
    } elif btype == 1 {
      e = _fl_decode_fixed(data, &mut br, out);
    } elif btype == 2 {
      e = _fl_decode_dynamic(data, &mut br, out);
    } else {
      return _err_int(_fl_msg("invalid deflate block type", br.pos));
    }
    if e.len() > 0 {
      return _err_int(e);
    }
  }
  var endpos = br.pos;
  if br.bit != 0 {
    endpos = br.pos + 1;
  }
  return _ok_int(endpos);
}

// Adler-32 of v[start, end): a starts at 1, b at 0, mod 65521.
fn _fl_adler_seg(v: &Vec[UInt8], start: Int, end: Int) -> Int {
  var a = 1;
  var b = 0;
  var i = start;
  while i < end {
    let x = _b(v, i);
    a = (a + x) % 65521;
    b = (b + a) % 65521;
    i = i + 1;
  }
  return b * 65536 + a;
}

// Inflate one zlib stream at `start`: header checks, DEFLATE payload and the
// Adler-32 trailer; returns the offset just past the trailer.
fn _fl_zlib_at(z: &Vec[UInt8], start: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if start < 0 || start + 2 > z.len() {
    return _err_int(_fl_msg("truncated zlib header", start));
  }
  let cmf = _b(z, start);
  let flg = _b(z, start + 1);
  if cmf % 16 != 8 {
    return _err_int(_fl_msg("unsupported zlib method", start));
  }
  if cmf / 16 > 7 {
    return _err_int(_fl_msg("invalid zlib window size", start));
  }
  if (cmf * 256 + flg) % 31 != 0 {
    return _err_int(_fl_msg("bad zlib fcheck", start));
  }
  if (flg / 32) % 2 == 1 {
    return _err_int(_fl_msg("zlib preset dictionary unsupported", start));
  }
  let out_start = out.len();
  let r = _fl_inflate_stream(z, start + 2, out);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let end: Int = r.value;
  if end + 4 > z.len() {
    return _err_int(_fl_msg("truncated zlib trailer", end));
  }
  let stored = _b(z, end) * 16777216 + _b(z, end + 1) * 65536 + _b(z, end + 2) * 256 + _b(z, end + 3);
  let computed = _fl_adler_seg(out, out_start, out.len());
  if stored != computed {
    return _err_int(_fl_msg("adler mismatch", end));
  }
  return _ok_int(end + 4);
}

// PDF FlateDecode payload: zlib first, then raw DEFLATE (some producers omit
// the zlib wrapper).
fn _flate_decode_stream(raw: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = _fl_zlib_at(raw, 0, &mut out);
  if r.is_ok {
    return _ok_bytes(out);
  }
  var out2 = Vec[UInt8].new();
  let d = _fl_inflate_stream(raw, 0, &mut out2);
  if d.is_ok {
    return _ok_bytes(out2);
  }
  return _err_bytes("pdf: flate decode failed");
}

/// Raw DEFLATE (RFC 1951) decoder for a whole buffer.
/// Params: data - the DEFLATE stream bytes.
/// Returns: Ok(inflated bytes) or Err("pdf: flate ... at <offset>").
/// Error case: truncated headers/codes, invalid codes, bad distances, output
/// larger than 16 MiB.
/// Complexity: O(input + output).
pub fn pdf_flate_decode(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = _fl_inflate_stream(data, 0, &mut out);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

/// zlib (RFC 1950) decoder for a whole buffer; the stream must fill `data`.
/// Params: data - the zlib stream bytes (CMF/FLG header and Adler-32 trailer).
/// Returns: Ok(inflated bytes) or Err("pdf: flate ... at <offset>").
/// Error case: bad header, preset dictionary, truncation, Adler mismatch,
/// trailing bytes, output larger than 16 MiB.
/// Complexity: O(input + output).
pub fn pdf_zlib_decode(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = _fl_zlib_at(data, 0, &mut out);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let end: Int = r.value;
  if end != data.len() {
    return _err_bytes(_msg_at("trailing bytes after zlib stream", end));
  }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
//  Source-span and token-pool string helpers
// ---------------------------------------------------------------------------

// Copy doc.data[start, end) into a fresh Vec[UInt8].
fn _src_copy(doc: &PdfDocument, start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = doc.data.len();
  var i = start;
  if i < 0 { i = 0; }
  var e = end;
  if e > n { e = n; }
  while i < e {
    out.push(doc.data[i]);
    i = i + 1;
  }
  return out;
}

// doc.data[start, end) as a Str when NUL-free, else "".
fn _src_str(doc: &PdfDocument, start: Int, end: Int) -> Str {
  let n = doc.data.len();
  if start < 0 || end > n || end < start { return ""; }
  var i = start;
  while i < end {
    if _b(doc.data, i) == 0 { return ""; }
    i = i + 1;
  }
  let copy = _src_copy(doc, start, end);
  return Str::from_utf8(copy);
}

// PdfTokens pool span as a Str when NUL-free, else "".
fn _tok_str(t: &PdfTokens, start: Int, len: Int) -> Str {
  if start < 0 || len <= 0 { return ""; }
  if start + len > t.pool.len() { return ""; }
  var i = start;
  while i < start + len {
    if ((t.pool[i] as Int) & 0xFF) == 0 { return ""; }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = start;
  while i < start + len {
    out.push(t.pool[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// PdfTokens pool span as raw bytes.
fn _tok_copy(t: &PdfTokens, start: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if start < 0 || len <= 0 { return out; }
  let n = t.pool.len();
  var i = start;
  while i < start + len && i < n {
    out.push(t.pool[i]);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
//  Public token API
// ---------------------------------------------------------------------------

/// Lex a byte buffer into a flat PDF token stream.
/// Params: data - any PDF-syntax fragment (a whole file is fine).
/// Returns: Ok(PdfTokens) with every token in source order; Err("pdf: ... at
/// <byte offset>") for the first lexical error (unterminated string, bad
/// escape/hex digit, unknown keyword, bad number, unexpected token).
/// Whitespace and % comments between tokens are skipped.
/// Error case: lexical errors listed above.
/// Complexity: O(data length).
pub fn pdf_lex(data: &Vec[UInt8]) -> Result[PdfTokens, Str] {
  var tk = PdfTokens{
    kind: Vec[Int].new();
    start: Vec[Int].new();
    end: Vec[Int].new();
    num: Vec[Int].new();
    gen: Vec[Int].new();
    kw: Vec[Int].new();
    sstart: Vec[Int].new();
    slen: Vec[Int].new();
    pool: Vec[UInt8].new();
  };
  var doc = _new_document(Vec[UInt8].new());
  let n = data.len();
  var pos = 0;
  var guard = 0;
  while pos < n && guard < _PDF_MAX_TOKENS {
    let q = _skip_ws_comments(data, pos);
    if q >= n { break; }
    let r = _scan_token(data, pos, &mut doc);
    var np = 0;
    match r {
      Ok(v) => { np = v; },
      Err(e) => { return _err_tokens(e); },
    };
    tk.kind.push(doc.tkind);
    tk.start.push(doc.tstart);
    tk.end.push(doc.tend);
    tk.num.push(doc.tnum);
    tk.gen.push(doc.tgen);
    tk.kw.push(doc.tkw);
    tk.sstart.push(doc.tsstart);
    tk.slen.push(doc.tslen);
    pos = np;
    guard = guard + 1;
  }
  var i = 0;
  while i < doc.pool.len() {
    tk.pool.push(doc.pool[i]);
    i = i + 1;
  }
  return _ok_tokens(tk);
}

/// Number of tokens.
/// Params: t - the token stream.
/// Returns: the token count.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_count(t: &PdfTokens) -> Int {
  return t.kind.len();
}

/// Kind of token i (a _TK_* code).
/// Params: t - the token stream; i - zero-based index.
/// Returns: the kind; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_kind(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.kind.len() { return -1; }
  let v: Int = t.kind[i];
  return v;
}

/// Start offset of token i in the source buffer.
/// Params: t - the token stream; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_start(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.start.len() { return -1; }
  let v: Int = t.start[i];
  return v;
}

/// End offset (exclusive) of token i in the source buffer.
/// Params: t - the token stream; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_end(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.end.len() { return -1; }
  let v: Int = t.end[i];
  return v;
}

/// Integer value of an INT token (0 for other kinds).
/// Params: t - the token stream; i - zero-based index.
/// Returns: the value; 0 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_int(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.num.len() { return 0; }
  let v: Int = t.num[i];
  return v;
}

/// Generation slot of a REF token (always 0: the lexer is token-level and
/// does not combine "N G R" sequences; the value parser does).
/// Params: t - the token stream; i - zero-based index.
/// Returns: 0, or -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_generation(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.gen.len() { return -1; }
  let v: Int = t.gen[i];
  return v;
}

/// Keyword code of a KEYWORD token (_KW_NONE for other kinds).
/// Params: t - the token stream; i - zero-based index.
/// Returns: the _KW_* code; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_keyword(t: &PdfTokens, i: Int) -> Int {
  if i < 0 || i >= t.kw.len() { return -1; }
  let v: Int = t.kw[i];
  return v;
}

/// Decoded bytes of a NAME/STR/HEX token, or the raw text of a REAL token.
/// Params: t - the token stream; i - zero-based index.
/// Returns: the bytes; empty when i is out of range or the token has none.
/// Error case: none. Complexity: O(token length).
pub fn pdf_token_bytes(t: &PdfTokens, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= t.sstart.len() { return Vec[UInt8].new(); }
  let ss: Int = t.sstart[i];
  let sl: Int = t.slen[i];
  return _tok_copy(t, ss, sl);
}

/// Decoded text of a NAME/STR/HEX token (or raw REAL text) when NUL-free,
/// else "". INT and bracket tokens have no text.
/// Params: t - the token stream; i - zero-based index.
/// Returns: the text; "" when i is out of range or the span carries a NUL.
/// Error case: none. Complexity: O(token length).
pub fn pdf_token_text(t: &PdfTokens, i: Int) -> Str {
  if i < 0 || i >= t.sstart.len() { return ""; }
  let ss: Int = t.sstart[i];
  let sl: Int = t.slen[i];
  return _tok_str(t, ss, sl);
}

/// Pool span [start, len] of token i (empty for tokens without a span).
/// Params: t - the token stream; i - zero-based index.
/// Returns: a two-element vector; empty when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_token_span(t: &PdfTokens, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if i < 0 || i >= t.sstart.len() { return out; }
  let ss: Int = t.sstart[i];
  let sl: Int = t.slen[i];
  out.push(ss);
  out.push(sl);
  return out;
}

// ---------------------------------------------------------------------------
//  Public document metadata API
// ---------------------------------------------------------------------------

/// PDF header version token, e.g. "1.4" ("" when absent).
/// Params: doc - a parsed document.
/// Returns: the version text.
/// Error case: none. Complexity: O(1).
pub fn pdf_version(doc: &PdfDocument) -> Str {
  return doc.version;
}

/// Byte offset of the "%PDF-" header (the header is accepted within the
/// first 1024 bytes, as the specification allows leading junk).
/// Params: doc - a parsed document.
/// Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn pdf_header_offset(doc: &PdfDocument) -> Int {
  return doc.header_offset;
}

/// Offset recorded by the last "startxref" keyword.
/// Params: doc - a parsed document.
/// Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn pdf_startxref(doc: &PdfDocument) -> Int {
  return doc.startxref;
}

/// Cross-reference container kind (_XT_* value; pdf_xref_type_name maps it).
/// Params: doc - a parsed document.
/// Returns: the kind.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_type(doc: &PdfDocument) -> Int {
  return doc.xref_type;
}

/// Number of merged cross-reference entries (free and in-use).
/// Params: doc - a parsed document.
/// Returns: the entry count.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_count(doc: &PdfDocument) -> Int {
  return doc.xr_num.len();
}

/// Object number of xref entry i.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the object number; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_object_number(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.xr_num.len() { return -1; }
  let v: Int = doc.xr_num[i];
  return v;
}

/// Offset field of xref entry i (0 for free entries; the object-stream
/// number for _XK_OBJSTM entries).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_offset(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.xr_off.len() { return -1; }
  let v: Int = doc.xr_off[i];
  return v;
}

/// Generation field of xref entry i (the index inside the object stream for
/// _XK_OBJSTM entries).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the generation; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_generation(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.xr_gen.len() { return -1; }
  let v: Int = doc.xr_gen[i];
  return v;
}

/// Kind of xref entry i (an _XK_* value; pdf_xref_kind_name maps it).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the kind; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_kind(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.xr_kind.len() { return -1; }
  let v: Int = doc.xr_kind[i];
  return v;
}

/// Index of the merged xref entry for object `num`, or -1.
/// Params: doc - a parsed document; num - the object number.
/// Returns: the entry index; -1 when absent.
/// Error case: none. Complexity: O(entries).
pub fn pdf_xref_find(doc: &PdfDocument, num: Int) -> Int {
  return _xref_find(doc, num);
}

/// Number of cross-reference sections walked through the /Prev chain
/// (newest first).
/// Params: doc - a parsed document.
/// Returns: the section count.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_section_count(doc: &PdfDocument) -> Int {
  return doc.xref_sections.len();
}

/// Offset of xref chain section i (0 is the newest, the startxref target).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the section offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_section_offset(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.xref_sections.len() { return -1; }
  let v: Int = doc.xref_sections[i];
  return v;
}

/// Arena node of the newest trailer dictionary (a classic trailer dict or an
/// xref stream dictionary), or -1.
/// Params: doc - a parsed document.
/// Returns: the node index; -1 when absent.
/// Error case: none. Complexity: O(1).
pub fn pdf_trailer_node(doc: &PdfDocument) -> Int {
  return doc.trailer_node;
}

/// /Size from the newest trailer, or -1 when absent.
/// Params: doc - a parsed document.
/// Returns: the size hint.
/// Error case: none. Complexity: O(1).
pub fn pdf_trailer_size(doc: &PdfDocument) -> Int {
  return doc.trailer_size;
}

/// /Prev from the newest trailer, or -1 when absent.
/// Params: doc - a parsed document.
/// Returns: the previous xref offset.
/// Error case: none. Complexity: O(1).
pub fn pdf_trailer_prev(doc: &PdfDocument) -> Int {
  return doc.trailer_prev;
}

/// Object number of /Root from the newest trailer that carries it, or -1.
/// Params: doc - a parsed document.
/// Returns: the catalog object number.
/// Error case: none. Complexity: O(1).
pub fn pdf_trailer_root_num(doc: &PdfDocument) -> Int {
  return doc.root_num;
}

/// Object number of /Info, or -1.
/// Params: doc - a parsed document.
/// Returns: the info object number.
/// Error case: none. Complexity: O(1).
pub fn pdf_trailer_info_num(doc: &PdfDocument) -> Int {
  return doc.info_num;
}

/// True when any trailer carries /Encrypt; encrypted documents are flagged,
/// never decrypted.
/// Params: doc - a parsed document.
/// Returns: the flag.
/// Error case: none. Complexity: O(1).
pub fn pdf_is_encrypted(doc: &PdfDocument) -> Bool {
  if doc.has_encrypt != 0 { return true; }
  return false;
}

/// Object number of /Encrypt when it is an indirect reference, else -1.
/// Params: doc - a parsed document.
/// Returns: the encrypt object number.
/// Error case: none. Complexity: O(1).
pub fn pdf_encrypt_num(doc: &PdfDocument) -> Int {
  return doc.encrypt_num;
}

/// True when the newest trailer carried an /ID array of two strings.
/// Params: doc - a parsed document.
/// Returns: the flag.
/// Error case: none. Complexity: O(1).
pub fn pdf_has_id(doc: &PdfDocument) -> Bool {
  if doc.has_id != 0 { return true; }
  return false;
}

/// The k-th /ID string (k is 0 or 1) as NUL-free text, or "".
/// Params: doc - a parsed document; k - 0 first ID, 1 second ID.
/// Returns: the ID text.
/// Error case: none. Complexity: O(ID length).
pub fn pdf_id(doc: &PdfDocument, k: Int) -> Str {
  if k == 0 { return _pool_str(doc, doc.id0_start, doc.id0_len); }
  if k == 1 { return _pool_str(doc, doc.id1_start, doc.id1_len); }
  return "";
}

/// Pool span [start, len] of the k-th /ID string (empty when absent).
/// Params: doc - a parsed document; k - 0 or 1.
/// Returns: a two-element vector.
/// Error case: none. Complexity: O(1).
pub fn pdf_id_span(doc: &PdfDocument, k: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if doc.has_id == 0 { return out; }
  if k == 0 {
    out.push(doc.id0_start);
    out.push(doc.id0_len);
  } elif k == 1 {
    out.push(doc.id1_start);
    out.push(doc.id1_len);
  }
  return out;
}

/// Non-empty when an xref stream or object stream could not be decoded (an
/// unsupported filter, predictor or corrupt stream); the raw bytes stay
/// available through pdf_stream_data / the document.
/// Params: doc - a parsed document.
/// Returns: the flag text, or "" when everything decoded.
/// Error case: none. Complexity: O(1).
pub fn pdf_xref_decode_error(doc: &PdfDocument) -> Str {
  return doc.xref_decode_error;
}

/// True when at least one object stream was decoded and its objects merged.
/// Params: doc - a parsed document.
/// Returns: the flag.
/// Error case: none. Complexity: O(1).
pub fn pdf_objstm_used(doc: &PdfDocument) -> Bool {
  if doc.objstm_used != 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
//  Public object API
// ---------------------------------------------------------------------------

/// Number of parsed indirect objects (xref-listed and object-stream ones).
/// Params: doc - a parsed document.
/// Returns: the object count.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_count(doc: &PdfDocument) -> Int {
  return doc.obj_num.len();
}

/// Object number of object entry i.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the number; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_number(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.obj_num.len() { return -1; }
  let v: Int = doc.obj_num[i];
  return v;
}

/// Generation of object entry i.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the generation; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_generation(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.obj_gen.len() { return -1; }
  let v: Int = doc.obj_gen[i];
  return v;
}

/// Byte offset of object entry i (for object-stream members this is the
/// best-effort file offset of the decoded payload byte).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_offset(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.obj_off.len() { return -1; }
  let v: Int = doc.obj_off[i];
  return v;
}

/// Arena node of the value of object entry i, or -1.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the node index; -1 when i is out of range or the value is
/// unresolved.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_node(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.obj_node.len() { return -1; }
  let v: Int = doc.obj_node[i];
  return v;
}

/// Status of object entry i (_OS_OK, or _OS_OBJSTM_MISSING when an entry is
/// known but its object stream could not be decoded).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the status; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_status(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.obj_status.len() { return -1; }
  let v: Int = doc.obj_status[i];
  return v;
}

/// True when object entry i came out of an object stream.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the flag; false when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_object_from_objstm(doc: &PdfDocument, i: Int) -> Bool {
  if i < 0 || i >= doc.in_objstm.len() { return false; }
  let v: Int = doc.in_objstm[i];
  if v != 0 { return true; }
  return false;
}

/// Object entry index for object `num`, or -1.
/// Params: doc - a parsed document; num - the object number.
/// Returns: the entry index; -1 when absent.
/// Error case: none. Complexity: O(objects).
pub fn pdf_find_object(doc: &PdfDocument, num: Int) -> Int {
  return _object_index_of(doc, num);
}

/// Resolve a reference node: REF nodes map to the target object's value
/// node; any other node maps to itself; -1 when the reference cannot be
/// resolved.
/// Params: doc - a parsed document; i - an arena node index.
/// Returns: the resolved node index; -1 on failure.
/// Error case: none. Complexity: O(objects).
pub fn pdf_deref(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return -1; }
  let k: Int = doc.kind[i];
  if k != _NK_REF { return i; }
  let num: Int = doc.num[i];
  let oi = _object_index_of(doc, num);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_node[oi];
  return v;
}

/// Catalog node: the value of the trailer /Root reference, or -1.
/// Params: doc - a parsed document.
/// Returns: the node index.
/// Error case: none. Complexity: O(objects).
pub fn pdf_root_node(doc: &PdfDocument) -> Int {
  if doc.root_num < 0 { return -1; }
  let oi = _object_index_of(doc, doc.root_num);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_node[oi];
  return v;
}

/// Info dictionary node: the value of the trailer /Info reference, or -1.
/// Params: doc - a parsed document.
/// Returns: the node index.
/// Error case: none. Complexity: O(objects).
pub fn pdf_info_node(doc: &PdfDocument) -> Int {
  if doc.info_num < 0 { return -1; }
  let oi = _object_index_of(doc, doc.info_num);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_node[oi];
  return v;
}

// ---------------------------------------------------------------------------
//  Public value-node API
// ---------------------------------------------------------------------------

/// Number of arena nodes.
/// Params: doc - a parsed document.
/// Returns: the node count.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_count(doc: &PdfDocument) -> Int {
  return doc.kind.len();
}

/// Kind of node i (an _NK_* value; pdf_node_kind_name maps it).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the kind; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_kind(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return -1; }
  let v: Int = doc.kind[i];
  return v;
}

/// Source start offset of node i.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_start(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.nstart.len() { return -1; }
  let v: Int = doc.nstart[i];
  return v;
}

/// Source end offset (exclusive) of node i.
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the offset; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_end(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.nend.len() { return -1; }
  let v: Int = doc.nend[i];
  return v;
}

/// Integer value of an INT node (0 for other kinds).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the value; 0 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_int(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.num.len() { return 0; }
  let v: Int = doc.num[i];
  return v;
}

/// Generation of a REF node (0 for other kinds).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the generation; -1 when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_generation(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.gen.len() { return -1; }
  let v: Int = doc.gen[i];
  return v;
}

/// Boolean value of a BOOL node (false for other kinds).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the value; false when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_bool(doc: &PdfDocument, i: Int) -> Bool {
  if i < 0 || i >= doc.num.len() { return false; }
  let v: Int = doc.num[i];
  if v != 0 { return true; }
  return false;
}

/// Numeric rendering of an INT node (decimal) or REAL node (raw token text).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the text; "" for other kinds or out-of-range indices.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_number(doc: &PdfDocument, i: Int) -> Str {
  if i < 0 || i >= doc.kind.len() { return ""; }
  let k: Int = doc.kind[i];
  if k == _NK_INT {
    let v: Int = doc.num[i];
    return convert.int_to_string(v);
  }
  if k == _NK_REAL {
    let ss: Int = doc.span_start[i];
    let sl: Int = doc.span_len[i];
    return _pool_str(doc, ss, sl);
  }
  return "";
}

/// Decoded bytes of a STRING or NAME node (a string may carry NULs).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the bytes; empty for other kinds or out-of-range indices.
/// Error case: none. Complexity: O(value length).
pub fn pdf_node_bytes(doc: &PdfDocument, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= doc.kind.len() { return Vec[UInt8].new(); }
  let k: Int = doc.kind[i];
  if k != _NK_STRING && k != _NK_NAME { return Vec[UInt8].new(); }
  let ss: Int = doc.span_start[i];
  let sl: Int = doc.span_len[i];
  return _pool_copy(doc, ss, sl);
}

/// Decoded text of a STRING or NAME node when NUL-free, else "".
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the text; "" when the span carries a NUL or i is out of range.
/// Error case: none. Complexity: O(value length).
pub fn pdf_node_text(doc: &PdfDocument, i: Int) -> Str {
  if i < 0 || i >= doc.kind.len() { return ""; }
  let k: Int = doc.kind[i];
  if k != _NK_STRING && k != _NK_NAME {
    if k == _NK_REAL {
      let ss0: Int = doc.span_start[i];
      let sl0: Int = doc.span_len[i];
      return _pool_str(doc, ss0, sl0);
    }
    return "";
  }
  let ss: Int = doc.span_start[i];
  let sl: Int = doc.span_len[i];
  return _pool_str(doc, ss, sl);
}

/// Pool span [start, len] of the decoded bytes of node i (empty for kinds
/// without a pool span).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: a two-element vector.
/// Error case: none. Complexity: O(1).
pub fn pdf_node_span(doc: &PdfDocument, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if i < 0 || i >= doc.span_start.len() { return out; }
  let ss: Int = doc.span_start[i];
  let sl: Int = doc.span_len[i];
  out.push(ss);
  out.push(sl);
  return out;
}

/// Raw source bytes of node i (the exact token span in the file).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the bytes; empty when i is out of range.
/// Error case: none. Complexity: O(node length).
pub fn pdf_node_raw_bytes(doc: &PdfDocument, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= doc.nstart.len() { return Vec[UInt8].new(); }
  let a: Int = doc.nstart[i];
  let b: Int = doc.nend[i];
  return _src_copy(doc, a, b);
}

/// Raw source text of node i when NUL-free, else "".
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the text.
/// Error case: none. Complexity: O(node length).
pub fn pdf_node_raw(doc: &PdfDocument, i: Int) -> Str {
  if i < 0 || i >= doc.nstart.len() { return ""; }
  let a: Int = doc.nstart[i];
  let b: Int = doc.nend[i];
  return _src_str(doc, a, b);
}

/// Number of DIRECT elements of an array node (0 for other kinds).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn pdf_array_len(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return 0; }
  let k: Int = doc.kind[i];
  if k != _NK_ARRAY { return 0; }
  let c: Int = doc.kid_count[i];
  return c;
}

/// Node index of array element k, or -1.
/// Params: doc - a parsed document; i - array node; k - zero-based element.
/// Returns: the element node index.
/// Error case: none. Complexity: O(1).
pub fn pdf_array_item(doc: &PdfDocument, i: Int, k: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return -1; }
  let kd: Int = doc.kind[i];
  if kd != _NK_ARRAY { return -1; }
  let c: Int = doc.kid_count[i];
  if k < 0 || k >= c { return -1; }
  let s: Int = doc.kid_start[i];
  let v: Int = doc.kids[s + k];
  return v;
}

/// Number of key/value PAIRS of a dictionary node (0 for other kinds).
/// Params: doc - a parsed document; i - zero-based index.
/// Returns: the pair count.
/// Error case: none. Complexity: O(1).
pub fn pdf_dict_len(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return 0; }
  let k: Int = doc.kind[i];
  if k != _NK_DICT { return 0; }
  let c: Int = doc.kid_count[i];
  return c / 2;
}

/// Key NAME node of dictionary pair k, or -1.
/// Params: doc - a parsed document; i - dictionary node; k - pair index.
/// Returns: the key node index.
/// Error case: none. Complexity: O(1).
pub fn pdf_dict_key_node(doc: &PdfDocument, i: Int, k: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return -1; }
  let kd: Int = doc.kind[i];
  if kd != _NK_DICT { return -1; }
  let c: Int = doc.kid_count[i];
  if k < 0 || k * 2 + 1 >= c { return -1; }
  let s: Int = doc.kid_start[i];
  let v: Int = doc.kids[s + k * 2];
  return v;
}

/// Value node of dictionary pair k, or -1.
/// Params: doc - a parsed document; i - dictionary node; k - pair index.
/// Returns: the value node index.
/// Error case: none. Complexity: O(1).
pub fn pdf_dict_value_node(doc: &PdfDocument, i: Int, k: Int) -> Int {
  if i < 0 || i >= doc.kind.len() { return -1; }
  let kd: Int = doc.kind[i];
  if kd != _NK_DICT { return -1; }
  let c: Int = doc.kid_count[i];
  if k < 0 || k * 2 + 1 >= c { return -1; }
  let s: Int = doc.kid_start[i];
  let v: Int = doc.kids[s + k * 2 + 1];
  return v;
}

/// Value node for NAME key `key` in dictionary node i, or -1.
/// Params: doc - a parsed document; i - dictionary node; key - the key text
/// (without the leading slash).
/// Returns: the value node index; -1 when absent.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_dict_get(doc: &PdfDocument, i: Int, key: Str) -> Int {
  return _dict_get(doc, i, key);
}

// ---------------------------------------------------------------------------
//  Public page-tree API
// ---------------------------------------------------------------------------

/// Object number of the catalog's /Pages node, or -1.
/// Params: doc - a parsed document.
/// Returns: the pages-root object number.
/// Error case: none. Complexity: O(1).
pub fn pdf_pages_root_num(doc: &PdfDocument) -> Int {
  return doc.pages_root_num;
}

/// /Count recorded on the pages root, or -1.
/// Params: doc - a parsed document.
/// Returns: the declared page count.
/// Error case: none. Complexity: O(1).
pub fn pdf_declared_page_count(doc: &PdfDocument) -> Int {
  return doc.declared_page_count;
}

/// Number of leaf pages found by the walk (Kids arrays recurse, anything
/// else under /Kids counts as a page).
/// Params: doc - a parsed document.
/// Returns: the page count.
/// Error case: none. Complexity: O(1).
pub fn pdf_page_count(doc: &PdfDocument) -> Int {
  return doc.page_nodes.len();
}

/// Arena node of page i's dictionary, or -1.
/// Params: doc - a parsed document; i - zero-based page index.
/// Returns: the node index.
/// Error case: none. Complexity: O(1).
pub fn pdf_page_node(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.page_nodes.len() { return -1; }
  let v: Int = doc.page_nodes[i];
  return v;
}

/// Object number of page i (-1 when the kid was a direct dictionary).
/// Params: doc - a parsed document; i - zero-based page index.
/// Returns: the object number.
/// Error case: none. Complexity: O(1).
pub fn pdf_page_object_num(doc: &PdfDocument, i: Int) -> Int {
  if i < 0 || i >= doc.page_obj_nums.len() { return -1; }
  let v: Int = doc.page_obj_nums[i];
  return v;
}

/// /MediaBox node of page i (an array), or -1.
/// Params: doc - a parsed document; i - zero-based page index.
/// Returns: the array node index.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_page_mediabox_node(doc: &PdfDocument, i: Int) -> Int {
  let pn = pdf_page_node(doc, i);
  if pn < 0 { return -1; }
  return _dict_get(doc, pn, "MediaBox");
}

/// True when page i carries a /Resources entry.
/// Params: doc - a parsed document; i - zero-based page index.
/// Returns: the flag.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_page_resources_present(doc: &PdfDocument, i: Int) -> Bool {
  let pn = pdf_page_node(doc, i);
  if pn < 0 { return false; }
  if _dict_get(doc, pn, "Resources") >= 0 { return true; }
  return false;
}

/// Number of /Contents entries of page i: 1 for a single reference, the
/// array length for an array, 0 when absent.
/// Params: doc - a parsed document; i - zero-based page index.
/// Returns: the content count.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_page_contents_count(doc: &PdfDocument, i: Int) -> Int {
  let pn = pdf_page_node(doc, i);
  if pn < 0 { return 0; }
  let cv = _dict_get(doc, pn, "Contents");
  if cv < 0 { return 0; }
  let ck: Int = doc.kind[cv];
  if ck == _NK_REF { return 1; }
  if ck == _NK_ARRAY {
    let c: Int = doc.kid_count[cv];
    return c;
  }
  return 0;
}

/// Node of /Contents entry k of page i (a REF node for single-content pages
/// with k == 0, or an array element).
/// Params: doc - a parsed document; i - zero-based page index; k - entry.
/// Returns: the node index; -1 when absent.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_page_contents_node(doc: &PdfDocument, i: Int, k: Int) -> Int {
  let pn = pdf_page_node(doc, i);
  if pn < 0 { return -1; }
  let cv = _dict_get(doc, pn, "Contents");
  if cv < 0 { return -1; }
  let ck: Int = doc.kind[cv];
  if ck == _NK_REF {
    if k == 0 { return cv; }
    return -1;
  }
  if ck == _NK_ARRAY {
    return pdf_array_item(doc, cv, k);
  }
  return -1;
}

/// True when the page-tree walk stopped at the depth cap.
/// Params: doc - a parsed document.
/// Returns: the flag.
/// Error case: none. Complexity: O(1).
pub fn pdf_pages_depth_capped(doc: &PdfDocument) -> Bool {
  if doc.pages_depth_capped != 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
//  Public Info dictionary API
// ---------------------------------------------------------------------------

/// Pool span [start, len] of extracted Info field `which`
/// (0 Title, 1 Author, 2 Subject, 3 CreationDate); empty when absent.
/// Params: doc - a parsed document; which - field selector.
/// Returns: a two-element vector.
/// Error case: none. Complexity: O(1).
pub fn pdf_info_span(doc: &PdfDocument, which: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if which < 0 || which >= doc.info_span_start.len() { return out; }
  let ss: Int = doc.info_span_start[which];
  let sl: Int = doc.info_span_len[which];
  if ss < 0 { return out; }
  out.push(ss);
  out.push(sl);
  return out;
}

/// Extracted Info field `which` as NUL-free text ("" when absent).
/// Params: doc - a parsed document; which - 0 Title, 1 Author, 2 Subject,
/// 3 CreationDate.
/// Returns: the field text.
/// Error case: none. Complexity: O(field length).
pub fn pdf_info_text(doc: &PdfDocument, which: Int) -> Str {
  if which < 0 || which >= doc.info_span_start.len() { return ""; }
  let ss: Int = doc.info_span_start[which];
  let sl: Int = doc.info_span_len[which];
  return _pool_str(doc, ss, sl);
}

/// Arbitrary Info dictionary field by NAME key (e.g. "Producer"), decoded
/// when the value is a string or name and NUL-free, else "".
/// Params: doc - a parsed document; key - the key without the leading slash.
/// Returns: the field text.
/// Error case: none. Complexity: O(pairs).
pub fn pdf_info_field(doc: &PdfDocument, key: Str) -> Str {
  let inode = pdf_info_node(doc);
  if inode < 0 { return ""; }
  let v = _dict_get(doc, inode, key);
  if v < 0 { return ""; }
  let vk: Int = doc.kind[v];
  if vk != _NK_STRING && vk != _NK_NAME { return ""; }
  let ss: Int = doc.span_start[v];
  let sl: Int = doc.span_len[v];
  return _pool_str(doc, ss, sl);
}

/// Info /Title text.
/// Params: doc - a parsed document.
/// Returns: the title, or "".
/// Error case: none. Complexity: O(field length).
pub fn pdf_info_title(doc: &PdfDocument) -> Str {
  return pdf_info_text(doc, 0);
}

/// Info /Author text.
/// Params: doc - a parsed document.
/// Returns: the author, or "".
/// Error case: none. Complexity: O(field length).
pub fn pdf_info_author(doc: &PdfDocument) -> Str {
  return pdf_info_text(doc, 1);
}

/// Info /Subject text.
/// Params: doc - a parsed document.
/// Returns: the subject, or "".
/// Error case: none. Complexity: O(field length).
pub fn pdf_info_subject(doc: &PdfDocument) -> Str {
  return pdf_info_text(doc, 2);
}

/// Info /CreationDate text (raw, e.g. "D:20260927230000Z").
/// Params: doc - a parsed document.
/// Returns: the date text, or "".
/// Error case: none. Complexity: O(field length).
pub fn pdf_info_creation_date(doc: &PdfDocument) -> Str {
  return pdf_info_text(doc, 3);
}

// ---------------------------------------------------------------------------
//  Public stream API
// ---------------------------------------------------------------------------

// Object entry index of the k-th object that carries a stream, or -1.
fn _stream_obj_at(doc: &PdfDocument, k: Int) -> Int {
  if k < 0 { return -1; }
  var seen = 0;
  var i = 0;
  while i < doc.obj_stream.len() {
    let st: Int = doc.obj_stream[i];
    if st == 1 {
      if seen == k { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Number of parsed objects that carry a stream.
/// Params: doc - a parsed document.
/// Returns: the stream count.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_count(doc: &PdfDocument) -> Int {
  var c = 0;
  var i = 0;
  while i < doc.obj_stream.len() {
    let st: Int = doc.obj_stream[i];
    if st == 1 { c = c + 1; }
    i = i + 1;
  }
  return c;
}

/// Object number of stream k, or -1.
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the object number.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_object(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_num[oi];
  return v;
}

/// Stream dictionary node of stream k, or -1.
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the dictionary node index.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_dict(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_stream_dict[oi];
  return v;
}

/// Raw stream bytes of stream k (never decoded here; use pdf_flate_decode or
/// pdf_zlib_decode for FlateDecode payloads).
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the raw bytes.
/// Error case: none. Complexity: O(stream length).
pub fn pdf_stream_data(doc: &PdfDocument, k: Int) -> Vec[UInt8] {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return Vec[UInt8].new(); }
  return _raw_stream_copy(doc, oi);
}

/// File offset of the first stream data byte of stream k.
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the offset; -1 when k is out of range.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_data_start(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_stream_data_start[oi];
  return v;
}

/// Effective data length of stream k (from /Length when verified, else the
/// endstream scan).
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the length; -1 when k is out of range.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_data_len(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_stream_data_len[oi];
  return v;
}

/// /Length value recorded from the stream dictionary (-1 when /Length is an
/// indirect reference or absent).
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the declared length; -1 when unavailable.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_declared_length(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_stream_declared[oi];
  return v;
}

/// How the bounds of stream k were established: 0 none, 1 direct /Length,
/// 2 indirect /Length resolved, 3 scanned (direct /Length mismatched),
/// 4 scanned because the indirect /Length could not be resolved.
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the source code; -1 when k is out of range.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_length_source(doc: &PdfDocument, k: Int) -> Int {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return -1; }
  let v: Int = doc.obj_stream_src[oi];
  return v;
}

/// True when stream k declared its length through an indirect reference
/// (resolved or not).
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the flag.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_length_indirect(doc: &PdfDocument, k: Int) -> Bool {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return false; }
  let v: Int = doc.obj_stream_src[oi];
  if v == _LS_INDIRECT || v == _LS_SCANNED_REF { return true; }
  return false;
}

/// True when the bounds of stream k came from an endstream scan instead of a
/// verified /Length value.
/// Params: doc - a parsed document; k - zero-based stream index.
/// Returns: the flag.
/// Error case: none. Complexity: O(objects).
pub fn pdf_stream_bounds_scanned(doc: &PdfDocument, k: Int) -> Bool {
  let oi = _stream_obj_at(doc, k);
  if oi < 0 { return false; }
  let v: Int = doc.obj_stream_src[oi];
  if v == _LS_SCANNED || v == _LS_SCANNED_REF { return true; }
  return false;
}
