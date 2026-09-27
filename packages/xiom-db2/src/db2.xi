// XIOM -- xiom.db2: IBM Db2 DRDA / DSS wire structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) structural codec for
// the IBM Db2 DRDA (Distributed Relational Database Architecture) wire
// format: the DSS frame envelope, the DDM codepoint structures inside a
// frame, the documented codepoint tables, typed decoders for common
// parameter payloads, and the SQLCARD / SQLDTA reply structures. There is no
// transport, no EBCDIC conversion (non-ASCII payloads are preserved raw and
// flagged opaque), no authentication and no SQL text analysis. See SPEC.md
// for the byte-level layouts and the error catalog.
//
// Implemented:
//   * DSS frame: 2-byte big-endian length (including the 6-byte header),
//     1-byte magic 0xD0 validation, 1-byte format (chain flags in the high
//     nibble, DSS type in the low nibble), 2-byte correlation id, plus
//     db2_frames_assemble which concatenates chained frames into messages
//     and validates same-correlation chains.
//   * DDM structures: repeated DDMs inside a frame payload, each a 2-byte
//     length followed by a 2-byte codepoint (the verified Derby/pydrda
//     order). The high bit of the length signals the extended form (0x8008
//     = 4-byte length follows the codepoint, 0x800A = 6-byte, 0x800C =
//     8-byte, 0x8004 = layer-B streaming); the mandate's "four-byte-length
//     set" (SQLDTA-style) is exposed through the advisory table
//     db2_cp_is_long_length. Unknown codepoints are preserved raw.
//   * Codepoint tables: the exchange / server / security / access / SQL
//     commands and their parameters, with db2_cp_name / db2_cp_known and
//     category predicates. Where the porting mandate's numeric values
//     disagree with the two independent verified sources (Apache Derby's
//     DDMReader/CodePoint tables and pydrda), the verified values are
//     implemented and the deltas are recorded in SPEC.md.
//   * Typed parameter decoders: ASCII character data with the EBCDIC set
//     flagged opaque (db2_text_ascii / db2_text_nul_terminated), VCM
//     length-prefixed strings (db2_vcm_read), SECMEC u16 lists and the
//     TYPDEFNAM byte-order names.
//   * Reply structures: SQLCARD (SQLCA SQLCODE / SQLSTATE / SQLERRD update
//     count / SQLWARN and the VCM message text) and SQLDTA / SQLDTARD
//     FD:OCA descriptor + data rows with per-column null indicators.
//   * Every reader is bounds-checked and its errors carry the byte offset of
//     the failing read; bad magic, short lengths, overruns and truncated
//     codepoints are rejected with deterministic messages.
//
// Documented boundaries:
//   * character payloads are decoded only when they are printable ASCII
//     (0x20..0x7E); anything else keeps its raw bytes and is flagged opaque
//     (no EBCDIC conversion, per the package scope).
//   * SQLCODE and SQLERRD are "platform" data whose byte order follows the
//     negotiated TYPDEFNAM (QTDSQLX86 = little-endian x86; QTDSQL370 and
//     QTDSQL400 = big-endian); callers pass the order explicitly.
//   * the layer-B streaming length form (0x8004, used by EXTDTA/QRYDTA
//     larger than one DSS) and the DSS length-continuation bit (0x8000 in
//     the 2-byte DSS length) are recognized and rejected with dedicated
//     errors; the streaming payload itself is out of scope.
//   * SQLCARD's SQLDIAGGRP trailer is parsed for the SQLRDBNAM and
//     SQLERRMSGC / SQLERRMSGS VCM fields; any further diagnostic bytes are
//     preserved raw in diag_tail.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; flat and parallel vectors, never Vec[StructType];
//   * Ok/Err construction is confined to the leaf helpers below;
//   * every byte read is widened with `(b as Int) & 0xFF` before entering
//     Int arithmetic or comparisons;
//   * every vector element read is bound to an explicitly typed local;
//   * struct fields are never passed as `&struct.field` where a
//     `&Vec[UInt8]` parameter is expected (a local is bound first);
//   * big-endian fields are composed byte by byte with explicit
//     multiplication;
//   * Str output is collected in a Vec[UInt8] and materialized with
//     sb_to_str only after the bytes were validated NUL-free.

module xiom.db2

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Db2Frame, Str].
fn _ok_frame(v: Db2Frame) -> Result[Db2Frame, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2Frame, Str].
fn _err_frame(m: Str) -> Result[Db2Frame, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2Ddm, Str].
fn _ok_ddm(v: Db2Ddm) -> Result[Db2Ddm, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2Ddm, Str].
fn _err_ddm(m: Str) -> Result[Db2Ddm, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2DdmList, Str].
fn _ok_ddmlist(v: Db2DdmList) -> Result[Db2DdmList, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2DdmList, Str].
fn _err_ddmlist(m: Str) -> Result[Db2DdmList, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2Messages, Str].
fn _ok_messages(v: Db2Messages) -> Result[Db2Messages, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2Messages, Str].
fn _err_messages(m: Str) -> Result[Db2Messages, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2Text, Str].
fn _ok_text(v: Db2Text) -> Result[Db2Text, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2Text, Str].
fn _err_text(m: Str) -> Result[Db2Text, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2SqlCard, Str].
fn _ok_card(v: Db2SqlCard) -> Result[Db2SqlCard, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2SqlCard, Str].
fn _err_card(m: Str) -> Result[Db2SqlCard, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2Descriptor, Str].
fn _ok_desc(v: Db2Descriptor) -> Result[Db2Descriptor, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2Descriptor, Str].
fn _err_desc(m: Str) -> Result[Db2Descriptor, Str] {
  return Err(m);
}

// Ok(v) for Result[Db2DtaRow, Str].
fn _ok_row(v: Db2DtaRow) -> Result[Db2DtaRow, Str] {
  return Ok(v);
}

// Err(m) for Result[Db2DtaRow, Str].
fn _err_row(m: Str) -> Result[Db2DtaRow, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A bounds-checked cursor reader over an immutable byte buffer. Create with
/// db2_reader_new; all db2_read_* functions advance pos and reject reads
/// past the end.
pub type Db2Reader = {
  data: Vec[UInt8];
  pos: Int;
}

/// A decoded DSS frame header plus its raw payload. `length` is the wire
/// length and includes the 6-byte header, so `length == payload.len() + 6`
/// and db2_frame_consumed is exactly `length`.
pub type Db2Frame = {
  length: Int;
  format: Int;
  dss_type: Int;
  chained: Bool;
  continue_on_error: Bool;
  same_correlation: Bool;
  correlation: Int;
  payload: Vec[UInt8];
}

/// A decoded DDM structure: the 2-byte codepoint, the total wire length
/// (including the header), whether the extended length form was used and
/// how many extended length bytes carried it (0, 4, 6 or 8), and the raw
/// payload (length minus the header). On the wire the length precedes the
/// codepoint: `[length:2][codepoint:2][extended length:0/4/6/8][payload]`.
pub type Db2Ddm = {
  code: Int;
  length: Int;
  long_form: Bool;
  ext_bytes: Int;
  payload: Vec[UInt8];
}

/// A flat sequence of DDMs as found in one DSS payload: parallel vectors of
/// the same length.
pub type Db2DdmList = {
  codes: Vec[Int];
  long_forms: Vec[Bool];
  lengths: Vec[Int];
  payloads: Vec[Vec[UInt8]];
}

/// Assembled DSS messages: `payloads[i]` concatenates the payloads of the
/// `frame_counts[i]` chained frames that form message i; `correlations[i]`
/// and `types[i]` come from the message's first frame. `frame_total` counts
/// every consumed frame and `consumed` is the number of input bytes used.
pub type Db2Messages = {
  payloads: Vec[Vec[UInt8]];
  frame_counts: Vec[Int];
  correlations: Vec[Int];
  types: Vec[Int];
  frame_total: Int;
  consumed: Int;
}

/// Character data decoded from a parameter payload. `ascii` is true only
/// when every byte was printable ASCII (0x20..0x7E) or NUL padding that was
/// trimmed; `bytes` always preserves the raw payload (EBCDIC stays opaque).
pub type Db2Text = {
  text: Str;
  ascii: Bool;
  bytes: Vec[UInt8];
}

/// A decoded SQLCARD. When `present` is false the card was the single 0xFF
/// "no SQLCA" form and every other field keeps its default. `sqlcode` and
/// `errd` are interpreted in the negotiated platform byte order; `errd`
/// holds the six SQLERRD integers (update count is `update_count`, i.e.
/// SQLERRD[2]); `sqlwarn` is the 11-byte SQLWARN area. `message` is the
/// SQLERRMSGC text (falling back to SQLERRMSGS) when it was printable
/// ASCII, `message_bytes` preserves it raw and `diag_tail` preserves any
/// remaining SQLDIAGGRP bytes.
pub type Db2SqlCard = {
  present: Bool;
  sqlcode: Int;
  sqlstate: Str;
  sqlstate_ascii: Bool;
  errproc: Vec[UInt8];
  update_count: Int;
  errd: Vec[Int];
  sqlwarn: Vec[UInt8];
  sqlwarn_present: Bool;
  rdbnam: Str;
  rdbnam_ascii: Bool;
  message: Str;
  message_ascii: Bool;
  message_bytes: Vec[UInt8];
  diag_tail: Vec[UInt8];
}

/// An FD:OCA descriptor (FDODSC payload). `types[i]` is the 1-byte triplet
/// type, `lengths[i]` the 2-byte big-endian triplet length (0x3FFF marks a
/// variable-length column); `trailer` preserves any bytes after the
/// descriptor block.
pub type Db2Descriptor = {
  count: Int;
  types: Vec[Int];
  lengths: Vec[Int];
  trailer: Vec[UInt8];
}

/// One FD:OCA data row (FDODTA payload). The three vectors are parallel and
/// have `col_count` entries; a null column has null_flags[i] true and an
/// empty value.
pub type Db2DtaRow = {
  col_count: Int;
  null_flags: Vec[Bool];
  values: Vec[Vec[UInt8]];
  consumed: Int;
}

// --------------------------------------------------
//  Private constants
// --------------------------------------------------

const _DSS_HEADER: Int = 6;          // DSS header size in bytes
const _DSS_MAGIC: Int = 208;         // 0xD0
const _DSS_MAX: Int = 32767;         // 0x7FFF largest single-DSS length
const _DSS_LEN_CONT: Int = 32768;    // 0x8000 length continuation bit
const _DSS_FLAG_CHAIN: Int = 64;     // 0x40 chained to next DSS
const _DSS_FLAG_CONT_ERR: Int = 32;  // 0x20 continue on error
const _DSS_FLAG_SAME_ID: Int = 16;   // 0x10 next DSS same correlation
const _DSS_TYPE_MASK: Int = 15;      // 0x0F DSS type nibble
const _DSS_HIGH_BIT: Int = 128;      // 0x80 reserved format bit

const _DDM_MIN: Int = 4;             // 2-byte length + 2-byte codepoint
const _DDM_EXT_FLAG: Int = 32768;    // 0x8000 extended length marker
const _DDM_EXT_MASK: Int = 32767;    // 0x7FFF low 15 bits of the marker
const _DDM_STREAM: Int = 32772;      // 0x8004 layer-B streaming form
const _DDM_EXT4: Int = 32776;        // 0x8008 4-byte extended length
const _DDM_EXT6: Int = 32778;        // 0x800A 6-byte extended length
const _DDM_EXT8: Int = 32780;        // 0x800C 8-byte extended length

const _VARIABLE_LEN: Int = 16383;    // 0x3FFF FDODSC variable-length marker

const _SQLCA_FLAG_OFF: Int = 0;
const _SQLCODE_OFF: Int = 1;
const _SQLSTATE_OFF: Int = 5;
const _SQLERRPROC_OFF: Int = 10;
const _SQLCAXGRP_OFF: Int = 18;
const _SQLERRD_OFF: Int = 19;
const _SQLERRD_COUNT: Int = 6;
const _SQLWARN_OFF: Int = 43;
const _SQLWARN_LEN: Int = 11;
const _SQLCA_MIN: Int = 19;          // flag + code + state + errproc + xgrp
const _SQLCA_FULL: Int = 54;         // ... + SQLERRD(24) + SQLWARN(11)

const _FDODSC_MARKER_HI: Int = 118;  // 0x76
const _FDODSC_MARKER_LO: Int = 208;  // 0xD0
const _TRIPLET_LEN: Int = 3;
const _FDODSC_FIXED: Int = 3;        // count byte + 2 marker bytes

// --------------------------------------------------
//  Codec metadata
// --------------------------------------------------

/// The protocol family implemented by this module ("DRDA").
/// Complexity: O(1).
pub fn db2_protocol_name() -> Str {
  return "DRDA";
}

/// The DSS magic byte (0xD0). Complexity: O(1).
pub fn db2_dss_magic() -> Int {
  return 208;
}

/// The DSS header size in bytes (6). Complexity: O(1).
pub fn db2_dss_header_len() -> Int {
  return 6;
}

/// The largest single-DSS length (32767, 0x7FFF). Complexity: O(1).
pub fn db2_dss_max_len() -> Int {
  return 32767;
}

/// The DSS length continuation bit (0x8000): the 2-byte length is a segment
/// marker and the DSS continues. Complexity: O(1).
pub fn db2_dss_len_continuation_bit() -> Int {
  return 32768;
}

/// DSS format flag: this DSS is chained to the next one (0x40).
/// Complexity: O(1).
pub fn db2_dss_flag_chained() -> Int {
  return 64;
}

/// DSS format flag: continue the chain even if this DSS fails (0x20).
/// Complexity: O(1).
pub fn db2_dss_flag_continue_on_error() -> Int {
  return 32;
}

/// DSS format flag: the next chained DSS has the same correlation id (0x10).
/// Complexity: O(1).
pub fn db2_dss_flag_same_correlation() -> Int {
  return 16;
}

/// DSS format mask for the DSS type nibble (0x0F). Complexity: O(1).
pub fn db2_dss_type_mask() -> Int {
  return 15;
}

/// DSS type 1: request. Complexity: O(1).
pub fn db2_dss_type_request() -> Int {
  return 1;
}

/// DSS type 2: reply. Complexity: O(1).
pub fn db2_dss_type_reply() -> Int {
  return 2;
}

/// DSS type 3: object data (SQLSTT, SQLDTA, EXTDTA, ...). Complexity: O(1).
pub fn db2_dss_type_object() -> Int {
  return 3;
}

/// DSS type 4: communications. Complexity: O(1).
pub fn db2_dss_type_communications() -> Int {
  return 4;
}

/// DSS type 5: request for which no reply is expected. Complexity: O(1).
pub fn db2_dss_type_request_no_reply() -> Int {
  return 5;
}

/// True for the five defined DSS type nibbles (1..5). Complexity: O(1).
pub fn db2_dss_type_known(t: Int) -> Bool {
  return t >= 1 && t <= 5;
}

/// A display name for a DSS type nibble (REQUEST, REPLY, OBJECT,
/// COMMUNICATION, REQUEST_NOREPLY, or UNKNOWN). Complexity: O(1).
pub fn db2_dss_type_name(t: Int) -> Str {
  if t == 1 {
    return "REQUEST";
  }
  if t == 2 {
    return "REPLY";
  }
  if t == 3 {
    return "OBJECT";
  }
  if t == 4 {
    return "COMMUNICATION";
  }
  if t == 5 {
    return "REQUEST_NOREPLY";
  }
  return "UNKNOWN";
}

/// The minimum DDM wire length (4: 2-byte codepoint + 2-byte length).
/// Complexity: O(1).
pub fn db2_ddm_min_len() -> Int {
  return 4;
}

/// The DDM extended length marker bit (0x8000). Complexity: O(1).
pub fn db2_ddm_ext_flag() -> Int {
  return 32768;
}

/// The layer-B streaming DDM length marker (0x8004). Complexity: O(1).
pub fn db2_ddm_streaming_marker() -> Int {
  return 32772;
}

/// The 4-byte extended DDM length marker (0x8008). Complexity: O(1).
pub fn db2_ddm_ext4_marker() -> Int {
  return 32776;
}

/// The 6-byte extended DDM length marker (0x800A). Complexity: O(1).
pub fn db2_ddm_ext6_marker() -> Int {
  return 32778;
}

/// The 8-byte extended DDM length marker (0x800C). Complexity: O(1).
pub fn db2_ddm_ext8_marker() -> Int {
  return 32780;
}

/// ADVISORY table for the porting mandate: true for codepoints whose
/// FD:OCA-bearing structures are the ones peers commonly write in the
/// extended (4-byte length) form: SQLCARD, SQLDARD, SQLDTA, SQLDTARD,
/// SQLSTT, QRYDSC, QRYDTA, SQLATTR and EXTDTA. The wire always signals the
/// form in the high bit of the 2-byte length, so db2_ddm_read never needs
/// this table; db2_ddm_read_as lets a caller enforce the expectation.
/// Complexity: O(1).
pub fn db2_cp_is_long_length(code: Int) -> Bool {
  if code == 9224 || code == 9233 || code == 9234 {
    return true;
  }
  if code == 9235 || code == 9236 || code == 9242 {
    return true;
  }
  if code == 9243 || code == 9296 {
    return true;
  }
  return code == 5228;
}

/// Big-endian ("network") platform byte order (0). Complexity: O(1).
pub fn db2_byteorder_big() -> Int {
  return 0;
}

/// Little-endian (x86 "QTDSQLX86") platform byte order (1). Complexity: O(1).
pub fn db2_byteorder_little() -> Int {
  return 1;
}

/// Unknown platform byte order (-1). Complexity: O(1).
pub fn db2_byteorder_unknown() -> Int {
  return -1;
}

/// The platform byte order named by a TYPDEFNAM value: QTDSQLX86 is
/// little-endian (1), QTDSQL370 and QTDSQL400 are big-endian (0), anything
/// else is unknown (-1). Comparison is case-sensitive via str_compare.
/// Complexity: O(name).
pub fn db2_tydefnam_byteorder(name: Str) -> Int {
  if str_compare(name, "QTDSQLX86") == 0 {
    return 1;
  }
  if str_compare(name, "QTDSQL370") == 0 {
    return 0;
  }
  if str_compare(name, "QTDSQL400") == 0 {
    return 0;
  }
  return -1;
}

// --------------------------------------------------
//  Codepoint accessors -- commands
// --------------------------------------------------

/// EXCSAT (0x1041) exchange server attributes. Complexity: O(1).
pub fn db2_cp_excsat() -> Int {
  return 4161;
}

/// ACCSEC (0x106D) access security. Complexity: O(1).
pub fn db2_cp_accsec() -> Int {
  return 4205;
}

/// SECCHK (0x106E) security check. Complexity: O(1).
pub fn db2_cp_secchk() -> Int {
  return 4206;
}

/// ACCRDB (0x2001) access relational database. Complexity: O(1).
pub fn db2_cp_accrdb() -> Int {
  return 8193;
}

/// BGNBND (0x2002) begin package bind. Complexity: O(1).
pub fn db2_cp_bgnbnd() -> Int {
  return 8194;
}

/// BNDSQLSTT (0x2004) bind SQL statement. Complexity: O(1).
pub fn db2_cp_bndsqlstt() -> Int {
  return 8196;
}

/// CLSQRY (0x2005) close query. Complexity: O(1).
pub fn db2_cp_clsqry() -> Int {
  return 8197;
}

/// CNTQRY (0x2006) continue query. Complexity: O(1).
pub fn db2_cp_cntqry() -> Int {
  return 8198;
}

/// DRPPKG (0x2007) drop package. Complexity: O(1).
pub fn db2_cp_drppkg() -> Int {
  return 8199;
}

/// DSCSQLSTT (0x2008) describe SQL statement. Complexity: O(1).
pub fn db2_cp_dscsqlstt() -> Int {
  return 8200;
}

/// ENDBND (0x2009) end package bind. Complexity: O(1).
pub fn db2_cp_endbnd() -> Int {
  return 8201;
}

/// EXCSQLIMM (0x200A) execute SQL immediately. Complexity: O(1).
pub fn db2_cp_excsqlimm() -> Int {
  return 8202;
}

/// EXCSQLSTT (0x200B) execute SQL statement. Complexity: O(1).
pub fn db2_cp_excsqlstt() -> Int {
  return 8203;
}

/// OPNQRY (0x200C) open query. Complexity: O(1).
pub fn db2_cp_opnqry() -> Int {
  return 8204;
}

/// PRPSQLSTT (0x200D) prepare SQL statement. Complexity: O(1).
pub fn db2_cp_prpsqlstt() -> Int {
  return 8205;
}

/// RDBCMM (0x200E) relational database commit. Complexity: O(1).
pub fn db2_cp_rdbcmm() -> Int {
  return 8206;
}

/// RDBRLLBCK (0x200F) relational database rollback. Complexity: O(1).
pub fn db2_cp_rdbrllbck() -> Int {
  return 8207;
}

/// REBIND (0x2010) rebind package. Complexity: O(1).
pub fn db2_cp_rebind() -> Int {
  return 8208;
}

/// DSCRDBTBL (0x2012) describe relational database table. Complexity: O(1).
pub fn db2_cp_dscrdbtbl() -> Int {
  return 8210;
}

/// EXCSQLSET (0x2014) execute SQL set. Complexity: O(1).
pub fn db2_cp_excsqlset() -> Int {
  return 8212;
}

// --------------------------------------------------
//  Codepoint accessors -- SQL / FD:OCA data
// --------------------------------------------------

/// FDODSC (0x0010) FD:OCA data descriptor. NOTE: the porting mandate lists
/// FDODSC as 0x002C; Apache Derby's CodePoint.FDODSC and pydrda's
/// cp.FDODSC both define 0x0010 and 0x002C is not a defined DDM codepoint,
/// so the verified value is implemented (see SPEC.md).
/// Complexity: O(1).
pub fn db2_cp_fdodsc() -> Int {
  return 16;
}

/// SQLCARD (0x2408) SQL communications area reply data. Complexity: O(1).
pub fn db2_cp_sqlcard() -> Int {
  return 9224;
}

/// SQLCINRD (0x240B) SQLCIN reply data. Complexity: O(1).
pub fn db2_cp_sqlcinrd() -> Int {
  return 9227;
}

/// SQLRSLRD (0x240E) SQL result set reply data. Complexity: O(1).
pub fn db2_cp_sqlrslrd() -> Int {
  return 9230;
}

/// SQLDARD (0x2411) SQLDA reply data. NOTE: the mandate lists SQLDTARD as
/// 0x2411; Derby and pydrda both reserve 0x2411 for SQLDARD and give
/// SQLDTARD 0x2413. Complexity: O(1).
pub fn db2_cp_sqldard() -> Int {
  return 9233;
}

/// SQLDTA (0x2412) SQL data (input host variables). Complexity: O(1).
pub fn db2_cp_sqldta() -> Int {
  return 9234;
}

/// SQLDTARD (0x2413) SQL data reply. Complexity: O(1).
pub fn db2_cp_sqldtard() -> Int {
  return 9235;
}

/// SQLSTT (0x2414) SQL statement text / SQL statement data. Complexity: O(1).
pub fn db2_cp_sqlstt() -> Int {
  return 9236;
}

/// SQLSTTVRB (0x2419) SQL statement variable text. Complexity: O(1).
pub fn db2_cp_sqlsttvrb() -> Int {
  return 9241;
}

/// QRYDSC (0x241A) query descriptor. Complexity: O(1).
pub fn db2_cp_qrydsc() -> Int {
  return 9242;
}

/// QRYDTA (0x241B) query data. Complexity: O(1).
pub fn db2_cp_qrydta() -> Int {
  return 9243;
}

/// SQLATTR (0x2450) SQL attributes. Complexity: O(1).
pub fn db2_cp_sqlattr() -> Int {
  return 9296;
}

/// EXTDTA (0x146C) externalized FD:OCA data. Complexity: O(1).
pub fn db2_cp_extdta() -> Int {
  return 5228;
}

/// FDODTA (0x147A) FD:OCA data. Complexity: O(1).
pub fn db2_cp_fdodta() -> Int {
  return 5242;
}

// --------------------------------------------------
//  Codepoint accessors -- parameters
// --------------------------------------------------

/// TYPDEFNAM (0x002F) data type definition name. Complexity: O(1).
pub fn db2_cp_typdefnam() -> Int {
  return 47;
}

/// TYPDEFOVR (0x0035) data type definition overrides. Complexity: O(1).
pub fn db2_cp_typdefovr() -> Int {
  return 53;
}

/// PRDID (0x112E) product specific identifier. Complexity: O(1).
pub fn db2_cp_prdid() -> Int {
  return 4398;
}

/// SRVCLSNM (0x1147) server class name. Complexity: O(1).
pub fn db2_cp_srvclsnm() -> Int {
  return 4423;
}

/// SRVRLSLV (0x115A) server product release level. Complexity: O(1).
pub fn db2_cp_srvrlslv() -> Int {
  return 4442;
}

/// EXTNAM (0x115E) external name. Complexity: O(1).
pub fn db2_cp_extnam() -> Int {
  return 4446;
}

/// SRVNAM (0x116D) server name. Complexity: O(1).
pub fn db2_cp_srvnam() -> Int {
  return 4461;
}

/// USRID (0x11A0) user identifier. The mandate spells it USERID; Derby and
/// pydrda name the same codepoint USRID. Complexity: O(1).
pub fn db2_cp_usrid() -> Int {
  return 4512;
}

/// PASSWORD (0x11A1) password. Complexity: O(1).
pub fn db2_cp_password() -> Int {
  return 4513;
}

/// SECMEC (0x11A2) security mechanism. Complexity: O(1).
pub fn db2_cp_secmec() -> Int {
  return 4514;
}

/// SECCHKCD (0x11A4) security check code. Complexity: O(1).
pub fn db2_cp_secchkcd() -> Int {
  return 4516;
}

/// SECTKN (0x11DC) security token. Complexity: O(1).
pub fn db2_cp_sectkn() -> Int {
  return 4572;
}

/// MGRLVLLS (0x1404) manager level list. Complexity: O(1).
pub fn db2_cp_mgrlvlls() -> Int {
  return 5124;
}

/// RDBCMTOK (0x2105) RDB commit allowed. Complexity: O(1).
pub fn db2_cp_rdbcmtok() -> Int {
  return 8453;
}

/// PKGID (0x2109) package identifier. Complexity: O(1).
pub fn db2_cp_pkgid() -> Int {
  return 8457;
}

/// PKGCNSTKN (0x210D) package consistency token. Complexity: O(1).
pub fn db2_cp_pkgcnstkn() -> Int {
  return 8461;
}

/// RDBACCCL (0x210F) RDB access manager class. NOTE: the mandate lists
/// 0x2114 for RDBACCCL; Derby and pydrda give RDBACCCL 0x210F and QRYBLKSZ
/// 0x2114. The verified value is implemented; the ambiguity is documented
/// in SPEC.md. Complexity: O(1).
pub fn db2_cp_rdbacccl() -> Int {
  return 8463;
}

/// RDBNAM (0x2110) relational database name. Complexity: O(1).
pub fn db2_cp_rdbnam() -> Int {
  return 8464;
}

/// PKGNAMCSN (0x2113) package name, consistency token and section number.
/// Complexity: O(1).
pub fn db2_cp_pkgnamcsn() -> Int {
  return 8467;
}

/// QRYBLKSZ (0x2114) query block size. NOTE: the mandate flags 0x2114 as
/// ambiguous; Derby CodePoint.QRYBLKSZ and pydrda cp.QRYBLKSZ both define
/// it as 0x2114 (pydrda writes a 4-byte block size under this code).
/// Complexity: O(1).
pub fn db2_cp_qryblksz() -> Int {
  return 8468;
}

/// RTNSQLDA (0x2116) return SQLDA. Complexity: O(1).
pub fn db2_cp_rtnsqlda() -> Int {
  return 8470;
}

/// STTSTRDEL (0x2120) statement string delimiter. Complexity: O(1).
pub fn db2_cp_sttstrdel() -> Int {
  return 8480;
}

/// STTDECDEL (0x2121) statement decimal delimiter. Complexity: O(1).
pub fn db2_cp_sttdecdel() -> Int {
  return 8481;
}

/// The mandate-listed "SQLSTT parameter" codepoint 0x2124. Neither Derby's
/// CodePoint table nor pydrda define 0x2124; the SQL statement text itself
/// travels as the SQLSTT DDM (0x2414). The value is exposed for callers
/// that must name it and is otherwise treated as an unknown parameter.
/// Complexity: O(1).
pub fn db2_cp_sqlstt_parameter() -> Int {
  return 8484;
}

/// MAXRSLCNT (0x2140) maximum result set count. Complexity: O(1).
pub fn db2_cp_maxrslcnt() -> Int {
  return 8512;
}

/// MAXBLKEXT (0x2141) maximum number of extra query blocks. Complexity: O(1).
pub fn db2_cp_maxblkext() -> Int {
  return 8513;
}

/// TYPSQLDA (0x2146) type of SQLDA. Complexity: O(1).
pub fn db2_cp_typsqlda() -> Int {
  return 8518;
}

/// RTNEXTDTA (0x2148) return of EXTDTA option. Complexity: O(1).
pub fn db2_cp_rtnextdta() -> Int {
  return 8520;
}

/// CRRTKN (0x2135) correlation token. Complexity: O(1).
pub fn db2_cp_crrtkn() -> Int {
  return 8501;
}

/// QRYINSID (0x215B) query instance identifier. Complexity: O(1).
pub fn db2_cp_qryinsid() -> Int {
  return 8539;
}

/// QRYCLSIMP (0x215D) query close implicit. Complexity: O(1).
pub fn db2_cp_qryclsimp() -> Int {
  return 8541;
}

/// DYNDTAFMT (0x214B) dynamic data format. Complexity: O(1).
pub fn db2_cp_dyndtafmt() -> Int {
  return 8523;
}

// --------------------------------------------------
//  Codepoint accessors -- reply messages
// --------------------------------------------------

/// EXCSATRD (0x1443) server attributes reply data. Complexity: O(1).
pub fn db2_cp_excsatrd() -> Int {
  return 5187;
}

/// ACCSECRD (0x14AC) access security reply data. Complexity: O(1).
pub fn db2_cp_accsecrd() -> Int {
  return 5292;
}

/// SECCHKRM (0x1219) security check reply message. Complexity: O(1).
pub fn db2_cp_secchkrm() -> Int {
  return 4633;
}

/// ACCRDBRM (0x2201) access RDB completed. Complexity: O(1).
pub fn db2_cp_accrdbrm() -> Int {
  return 8705;
}

/// OPNQRYRM (0x2205) open query reply message. Complexity: O(1).
pub fn db2_cp_opnqryrm() -> Int {
  return 8709;
}

/// ENDQRYRM (0x220B) end of query reply message. Complexity: O(1).
pub fn db2_cp_endqryrm() -> Int {
  return 8715;
}

/// ENDUOWRM (0x220C) end of unit of work reply message. Complexity: O(1).
pub fn db2_cp_enduowrm() -> Int {
  return 8716;
}

/// RDBNFNRM (0x2211) RDB not found reply message. Complexity: O(1).
pub fn db2_cp_rdbnfnrm() -> Int {
  return 8721;
}

/// SQLERRRM (0x2213) SQL error reply message. Complexity: O(1).
pub fn db2_cp_sqlerrrm() -> Int {
  return 8723;
}

/// RDBUPDRM (0x2218) RDB update reply message. Complexity: O(1).
pub fn db2_cp_rdbupdrm() -> Int {
  return 8728;
}

/// RDBAFLRM (0x221A) RDB access failed reply message. Complexity: O(1).
pub fn db2_cp_rdbaflrm() -> Int {
  return 8730;
}

/// SYNTAXRM (0x124C) data stream syntax error reply message. Complexity: O(1).
pub fn db2_cp_syntaxrm() -> Int {
  return 4684;
}

/// CMDCHKRM (0x1254) command check reply message. Complexity: O(1).
pub fn db2_cp_cmdchkrm() -> Int {
  return 4692;
}

// --------------------------------------------------
//  Codepoint names and categories
// --------------------------------------------------

/// A display name for a codepoint, or "" when it is not in the implemented
/// table. Unknown codepoints are preserved raw by the decoders; this helper
/// only names the documented subset. Complexity: O(1).
pub fn db2_cp_name(code: Int) -> Str {
  if code == 4161 {
    return "EXCSAT";
  }
  if code == 4205 {
    return "ACCSEC";
  }
  if code == 4206 {
    return "SECCHK";
  }
  if code == 4181 {
    return "SYNCCTL";
  }
  if code == 4201 {
    return "SYNCRSY";
  }
  if code == 4207 {
    return "SYNCLOG";
  }
  if code == 8193 {
    return "ACCRDB";
  }
  if code == 8194 {
    return "BGNBND";
  }
  if code == 8196 {
    return "BNDSQLSTT";
  }
  if code == 8197 {
    return "CLSQRY";
  }
  if code == 8198 {
    return "CNTQRY";
  }
  if code == 8199 {
    return "DRPPKG";
  }
  if code == 8200 {
    return "DSCSQLSTT";
  }
  if code == 8201 {
    return "ENDBND";
  }
  if code == 8202 {
    return "EXCSQLIMM";
  }
  if code == 8203 {
    return "EXCSQLSTT";
  }
  if code == 8204 {
    return "OPNQRY";
  }
  if code == 8205 {
    return "PRPSQLSTT";
  }
  if code == 8206 {
    return "RDBCMM";
  }
  if code == 8207 {
    return "RDBRLLBCK";
  }
  if code == 8208 {
    return "REBIND";
  }
  if code == 8210 {
    return "DSCRDBTBL";
  }
  if code == 8212 {
    return "EXCSQLSET";
  }
  if code == 16 {
    return "FDODSC";
  }
  if code == 9224 {
    return "SQLCARD";
  }
  if code == 9227 {
    return "SQLCINRD";
  }
  if code == 9230 {
    return "SQLRSLRD";
  }
  if code == 9233 {
    return "SQLDARD";
  }
  if code == 9234 {
    return "SQLDTA";
  }
  if code == 9235 {
    return "SQLDTARD";
  }
  if code == 9236 {
    return "SQLSTT";
  }
  if code == 9241 {
    return "SQLSTTVRB";
  }
  if code == 9242 {
    return "QRYDSC";
  }
  if code == 9243 {
    return "QRYDTA";
  }
  if code == 9296 {
    return "SQLATTR";
  }
  if code == 5228 {
    return "EXTDTA";
  }
  if code == 5242 {
    return "FDODTA";
  }
  if code == 47 {
    return "TYPDEFNAM";
  }
  if code == 53 {
    return "TYPDEFOVR";
  }
  if code == 4398 {
    return "PRDID";
  }
  if code == 4423 {
    return "SRVCLSNM";
  }
  if code == 4442 {
    return "SRVRLSLV";
  }
  if code == 4446 {
    return "EXTNAM";
  }
  if code == 4461 {
    return "SRVNAM";
  }
  if code == 4512 {
    return "USRID";
  }
  if code == 4513 {
    return "PASSWORD";
  }
  if code == 4514 {
    return "SECMEC";
  }
  if code == 4516 {
    return "SECCHKCD";
  }
  if code == 4572 {
    return "SECTKN";
  }
  if code == 5124 {
    return "MGRLVLLS";
  }
  if code == 8453 {
    return "RDBCMTOK";
  }
  if code == 8457 {
    return "PKGID";
  }
  if code == 8461 {
    return "PKGCNSTKN";
  }
  if code == 8463 {
    return "RDBACCCL";
  }
  if code == 8464 {
    return "RDBNAM";
  }
  if code == 8467 {
    return "PKGNAMCSN";
  }
  if code == 8468 {
    return "QRYBLKSZ";
  }
  if code == 8470 {
    return "RTNSQLDA";
  }
  if code == 8480 {
    return "STTSTRDEL";
  }
  if code == 8481 {
    return "STTDECDEL";
  }
  if code == 8484 {
    return "SQLSTT(?)";
  }
  if code == 8501 {
    return "CRRTKN";
  }
  if code == 8512 {
    return "MAXRSLCNT";
  }
  if code == 8513 {
    return "MAXBLKEXT";
  }
  if code == 8518 {
    return "TYPSQLDA";
  }
  if code == 8520 {
    return "RTNEXTDTA";
  }
  if code == 8523 {
    return "DYNDTAFMT";
  }
  if code == 8539 {
    return "QRYINSID";
  }
  if code == 8541 {
    return "QRYCLSIMP";
  }
  if code == 5187 {
    return "EXCSATRD";
  }
  if code == 5292 {
    return "ACCSECRD";
  }
  if code == 4633 {
    return "SECCHKRM";
  }
  if code == 8705 {
    return "ACCRDBRM";
  }
  if code == 8709 {
    return "OPNQRYRM";
  }
  if code == 8715 {
    return "ENDQRYRM";
  }
  if code == 8716 {
    return "ENDUOWRM";
  }
  if code == 8721 {
    return "RDBNFNRM";
  }
  if code == 8723 {
    return "SQLERRRM";
  }
  if code == 8728 {
    return "RDBUPDRM";
  }
  if code == 8730 {
    return "RDBAFLRM";
  }
  if code == 4684 {
    return "SYNTAXRM";
  }
  if code == 4692 {
    return "CMDCHKRM";
  }
  return "";
}

/// True when db2_cp_name names the codepoint. Complexity: O(1).
pub fn db2_cp_known(code: Int) -> Bool {
  let n: Str = db2_cp_name(code);
  return n.len() > 0;
}

/// True for the implemented command codepoints (exchange, security, access,
/// bind, SQL execution and transaction). Complexity: O(1).
pub fn db2_cp_is_command(code: Int) -> Bool {
  if code == 4161 || code == 4205 || code == 4206 {
    return true;
  }
  if code == 4181 || code == 4201 || code == 4207 {
    return true;
  }
  if code == 8193 || code == 8194 || code == 8196 || code == 8197 {
    return true;
  }
  if code == 8198 || code == 8199 || code == 8200 || code == 8201 {
    return true;
  }
  if code == 8202 || code == 8203 || code == 8204 || code == 8205 {
    return true;
  }
  return code == 8206 || code == 8207 || code == 8208 || code == 8210 || code == 8212;
}

/// True for the implemented parameter codepoints. Complexity: O(1).
pub fn db2_cp_is_parameter(code: Int) -> Bool {
  if code == 47 || code == 53 || code == 4398 {
    return true;
  }
  if code == 4423 || code == 4442 || code == 4446 || code == 4461 {
    return true;
  }
  if code == 4512 || code == 4513 || code == 4514 || code == 4516 || code == 4572 {
    return true;
  }
  if code == 5124 {
    return true;
  }
  if code == 8453 || code == 8457 || code == 8461 || code == 8463 {
    return true;
  }
  if code == 8464 || code == 8467 || code == 8468 || code == 8470 {
    return true;
  }
  if code == 8480 || code == 8481 || code == 8484 {
    return true;
  }
  if code == 8501 || code == 8512 || code == 8513 || code == 8518 {
    return true;
  }
  return code == 8520 || code == 8523 || code == 8539 || code == 8541;
}

/// True for the implemented SQL / FD:OCA data codepoints (including the
/// FDODSC and FDODTA descriptors nested inside SQLDTA). Complexity: O(1).
pub fn db2_cp_is_sql_data(code: Int) -> Bool {
  if code == 16 || code == 5228 || code == 5242 {
    return true;
  }
  if code == 9224 || code == 9227 || code == 9230 || code == 9233 {
    return true;
  }
  if code == 9234 || code == 9235 || code == 9236 || code == 9241 {
    return true;
  }
  return code == 9242 || code == 9243 || code == 9296;
}

/// True for the implemented reply-message codepoints. Complexity: O(1).
pub fn db2_cp_is_reply_message(code: Int) -> Bool {
  if code == 5187 || code == 5292 || code == 4633 {
    return true;
  }
  if code == 8705 || code == 8709 || code == 8715 || code == 8716 {
    return true;
  }
  if code == 8721 || code == 8723 || code == 8728 || code == 8730 {
    return true;
  }
  return code == 4684 || code == 4692;
}

// --------------------------------------------------
//  SECMEC names
// --------------------------------------------------

/// True for the Security Mechanism values named by this codec (1, 3..10).
/// Complexity: O(1).
pub fn db2_secmec_known(v: Int) -> Bool {
  if v == 1 {
    return true;
  }
  return v >= 3 && v <= 10;
}

/// A display name for a Security Mechanism value (DCESEC, USRIDPWD,
/// USRIDONL, USRIDNWPWD, USRSBSPWD, USRENCPWD, USRSSBPWD, EUSRIDPWD,
/// EUSRIDNWPWD, or UNKNOWN). Complexity: O(1).
pub fn db2_secmec_name(v: Int) -> Str {
  if v == 1 {
    return "DCESEC";
  }
  if v == 3 {
    return "USRIDPWD";
  }
  if v == 4 {
    return "USRIDONL";
  }
  if v == 5 {
    return "USRIDNWPWD";
  }
  if v == 6 {
    return "USRSBSPWD";
  }
  if v == 7 {
    return "USRENCPWD";
  }
  if v == 8 {
    return "USRSSBPWD";
  }
  if v == 9 {
    return "EUSRIDPWD";
  }
  if v == 10 {
    return "EUSRIDNWPWD";
  }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Byte and message helpers
// --------------------------------------------------

// One uppercase hex digit for 0..15.
fn _hex_digit(v: Int) -> UInt8 {
  let tbl: Str = "0123456789ABCDEF";
  return string.byte_at(tbl, v);
}

// The low byte of `v` as two uppercase hex digits.
fn _hex2(v: Int) -> Str {
  var x = v % 256;
  if x < 0 {
    x = x + 256;
  }
  var sb = Vec[UInt8].new();
  sb.push(_hex_digit((x / 16) % 16));
  sb.push(_hex_digit(x % 16));
  return builder.sb_to_str(&sb);
}

// The low 16 bits of `v` as four uppercase hex digits.
fn _hex4(v: Int) -> Str {
  var x = v % 65536;
  if x < 0 {
    x = x + 65536;
  }
  var sb = Vec[UInt8].new();
  sb.push(_hex_digit((x / 4096) % 16));
  sb.push(_hex_digit((x / 256) % 16));
  sb.push(_hex_digit((x / 16) % 16));
  sb.push(_hex_digit(x % 16));
  return builder.sb_to_str(&sb);
}

// The standard truncation error for a failing read at `pos`.
fn _trunc_at(pos: Int) -> Str {
  return "db2: truncated input at offset " + convert.int_to_string(pos);
}

// Byte at `pos` widened to 0..255. The caller guarantees the index is in
// bounds.
fn _r_byte(r: &Db2Reader, pos: Int) -> Int {
  return (r.data[pos] as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut Db2Reader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// A fresh copy of `src` (used where a returned vector must not alias).
fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Append every byte of `src` to `dst`.
fn _append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// 2^k for 0 <= k <= 62 (the largest value is 2^62).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extend the unsigned value `v` (0 <= v < 2^bits) to a signed Int.
// bits is 8, 16 or 32.
fn _sign_extend(v: Int, bits: Int) -> Int {
  let half = _pow2(bits - 1);
  if v >= half {
    let full = _pow2(bits);
    return v - full;
  }
  return v;
}

// The display text of an Int (delegates to xio2; kept as a local leaf so
// message construction stays uniform).
fn _dec(n: Int) -> Str {
  return convert.int_to_string(n);
}

// --------------------------------------------------
//  Reader lifecycle and primitives
// --------------------------------------------------

/// A reader positioned at offset 0 of `data`. Complexity: O(1).
pub fn db2_reader_new(data: Vec[UInt8]) -> Db2Reader {
  return Db2Reader{ data: data; pos: 0; };
}

/// Current cursor offset. Complexity: O(1).
pub fn db2_reader_pos(r: &Db2Reader) -> Int {
  return r.pos;
}

/// Current cursor offset, taking &mut so a caller that also mutates the
/// reader never mixes a `&` accessor before a `&mut` call on the same local
/// (advisory E001). Complexity: O(1).
pub fn db2_reader_pos_mut(r: &mut Db2Reader) -> Int {
  return r.pos;
}

/// Bytes left before the end of the buffer. Complexity: O(1).
pub fn db2_reader_remaining(r: &Db2Reader) -> Int {
  return r.data.len() - r.pos;
}

// Read `size` (1..4) bytes big-endian into an unsigned Int, advancing the
// cursor. Err(truncation with the starting offset) when fewer bytes remain.
fn _read_unsigned(r: &mut Db2Reader, size: Int) -> Result[Int, Str] {
  let total: Int = r.data.len();
  let start: Int = r.pos;
  if start + size > total {
    return _err_int(_trunc_at(start));
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b: Int = _r_byte_mut(r, start + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = start + size;
  return _ok_int(v);
}

// Read `n` bytes into a fresh vector, advancing the cursor. Err(truncation)
// when fewer than `n` bytes remain.
fn _read_n(r: &mut Db2Reader, n: Int) -> Result[Vec[UInt8], Str] {
  let total: Int = r.data.len();
  let start: Int = r.pos;
  if n < 0 {
    return _err_bytes("db2: negative read length " + _dec(n) + " at offset " + _dec(start));
  }
  if start + n > total {
    return _err_bytes(_trunc_at(start));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(r.data[start + i]);
    i = i + 1;
  }
  r.pos = start + n;
  return _ok_bytes(out);
}

/// Read one unsigned byte (0..255). Err(truncation) when empty.
/// Complexity: O(1).
pub fn db2_read_u8(r: &mut Db2Reader) -> Result[Int, Str] {
  return _read_unsigned(r, 1);
}

/// Read one unsigned 16-bit big-endian integer (0..65535). Err(truncation)
/// when fewer than 2 bytes remain. Complexity: O(1).
pub fn db2_read_u16(r: &mut Db2Reader) -> Result[Int, Str] {
  return _read_unsigned(r, 2);
}

/// Read one unsigned 32-bit big-endian integer. Err(truncation) when fewer
/// than 4 bytes remain. Complexity: O(1).
pub fn db2_read_u32(r: &mut Db2Reader) -> Result[Int, Str] {
  return _read_unsigned(r, 4);
}

// --------------------------------------------------
//  DSS frame layer
// --------------------------------------------------

/// Number of bytes one frame occupies on the wire: `length` (the DSS length
/// already includes the 6-byte header). Complexity: O(1).
pub fn db2_frame_consumed(f: &Db2Frame) -> Int {
  return f.length;
}

/// Parse one DSS frame from `r`, advancing the cursor past it. Validates the
/// 2-byte length (>= 6, no overrun, no 0x8000 length continuation), the
/// 0xD0 magic, the format byte (bit 0x80 clear; an unchained DSS may not
/// carry the same-correlation or continue-on-error flags) and returns the
/// frame header plus its raw payload. Every error carries a byte offset.
/// Complexity: O(payload).
pub fn db2_frame_parse(r: &mut Db2Reader) -> Result[Db2Frame, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + 6 > total {
    return _err_frame(_trunc_at(start));
  }
  let b0: Int = _r_byte_mut(r, start);
  let b1: Int = _r_byte_mut(r, start + 1);
  let raw_len: Int = b0 * 256 + b1;
  if (raw_len & 32768) != 0 {
    return _err_frame("db2: continued (large) DSS length 0x" + _hex4(raw_len) + " not supported by db2_frame_parse at offset " + _dec(start));
  }
  if raw_len < 6 {
    return _err_frame("db2: DSS length " + _dec(raw_len) + " below minimum 6 at offset " + _dec(start));
  }
  if start + raw_len > total {
    return _err_frame("db2: DSS length " + _dec(raw_len) + " overruns buffer (" + _dec(total - start) + " bytes remain) at offset " + _dec(start));
  }
  let magic: Int = _r_byte_mut(r, start + 2);
  if magic != 208 {
    return _err_frame("db2: bad DSS magic 0x" + _hex2(magic) + " at offset " + _dec(start + 2) + " (expected 0xD0)");
  }
  let fmt: Int = _r_byte_mut(r, start + 3);
  if (fmt & 128) != 0 {
    return _err_frame("db2: DSS format bit 0x80 set at offset " + _dec(start + 3));
  }
  let chained: Bool = (fmt & 64) != 0;
  let cont_err: Bool = (fmt & 32) != 0;
  let same_id: Bool = (fmt & 16) != 0;
  if !chained && same_id {
    return _err_frame("db2: same-correlation bit set on unchained DSS at offset " + _dec(start + 3));
  }
  if !chained && cont_err {
    return _err_frame("db2: continue-on-error bit set on unchained DSS at offset " + _dec(start + 3));
  }
  let b4: Int = _r_byte_mut(r, start + 4);
  let b5: Int = _r_byte_mut(r, start + 5);
  let corr: Int = b4 * 256 + b5;
  r.pos = start + 6;
  let br = _read_n(r, raw_len - 6);
  if !br.is_ok {
    return _err_frame(br.error);
  }
  let payload: Vec[UInt8] = br.value;
  return _ok_frame(Db2Frame{ length: raw_len; format: fmt; dss_type: fmt & 15; chained: chained; continue_on_error: cont_err; same_correlation: same_id; correlation: corr; payload: payload; });
}

/// Parse every DSS frame in `data` and assemble chained frames into
/// messages: consecutive frames whose chained flag (0x40) is set are
/// concatenated into one message payload; the message ends at the first
/// frame without the flag. When a chained frame also carries the
/// same-correlation flag (0x10), the next frame must repeat its correlation
/// id, otherwise the assembly fails. A final chained frame without a
/// successor is an error. Complexity: O(data).
pub fn db2_frames_assemble(data: Vec[UInt8]) -> Result[Db2Messages, Str] {
  var r = Db2Reader{ data: data; pos: 0; };
  var payloads = Vec[Vec[UInt8]].new();
  var counts = Vec[Int].new();
  var corrs = Vec[Int].new();
  var types = Vec[Int].new();
  var frame_total = 0;
  var cur = Vec[UInt8].new();
  var cur_count = 0;
  var first_corr = 0;
  var first_type = 0;
  var first = true;
  var expect_corr = 0;
  var have_expect = false;
  while r.pos < r.data.len() {
    let fstart: Int = r.pos;
    let fr = db2_frame_parse(&mut r);
    if !fr.is_ok {
      return _err_messages(fr.error);
    }
    let f: Db2Frame = fr.value;
    frame_total = frame_total + 1;
    if have_expect && f.correlation != expect_corr {
      return _err_messages("db2: correlation id " + _dec(f.correlation) + " changed mid-chain (expected " + _dec(expect_corr) + ") at offset " + _dec(fstart));
    }
    if first {
      first_corr = f.correlation;
      first_type = f.dss_type;
      first = false;
    }
    let p: Vec[UInt8] = f.payload;
    _append_bytes(&mut cur, &p);
    cur_count = cur_count + 1;
    if f.chained && f.same_correlation {
      expect_corr = f.correlation;
      have_expect = true;
    } else {
      have_expect = false;
    }
    if !f.chained {
      payloads.push(cur);
      counts.push(cur_count);
      corrs.push(first_corr);
      types.push(first_type);
      cur = Vec[UInt8].new();
      cur_count = 0;
      first = true;
    }
  }
  if cur_count > 0 {
    return _err_messages("db2: chained DSS has no following frame at offset " + _dec(r.pos));
  }
  return _ok_messages(Db2Messages{ payloads: payloads; frame_counts: counts; correlations: corrs; types: types; frame_total: frame_total; consumed: r.pos; });
}

// --------------------------------------------------
//  DDM layer
// --------------------------------------------------

/// Total wire length of a DDM (already includes its header).
/// Complexity: O(1).
pub fn db2_ddm_consumed(d: &Db2Ddm) -> Int {
  return d.length;
}

/// Number of DDMs in a flat list. Complexity: O(1).
pub fn db2_ddm_list_count(l: &Db2DdmList) -> Int {
  return l.codes.len();
}

/// Index of the first DDM with `code`, or -1. Complexity: O(count).
pub fn db2_ddm_list_find(l: &Db2DdmList, code: Int) -> Int {
  var i = 0;
  while i < l.codes.len() {
    let c: Int = l.codes[i];
    if c == code {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Read one DDM using the wire's length form. `want` is -1 (accept either
// form), 1 (require the extended form) or 0 (require the short form).
fn _ddm_read_form(r: &mut Db2Reader, want: Int) -> Result[Db2Ddm, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + 2 > total {
    return _err_ddm("db2: truncated DDM length at offset " + _dec(start));
  }
  let l0: Int = _r_byte_mut(r, start);
  let l1: Int = _r_byte_mut(r, start + 1);
  let raw: Int = l0 * 256 + l1;
  let cstart: Int = start + 2;
  if cstart + 2 > total {
    return _err_ddm("db2: truncated DDM codepoint at offset " + _dec(cstart));
  }
  let c0: Int = _r_byte_mut(r, cstart);
  let c1: Int = _r_byte_mut(r, cstart + 1);
  let code: Int = c0 * 256 + c1;
  var length: Int = 0;
  var ext_bytes: Int = 0;
  var long_form: Bool = false;
  if (raw & 32768) == 0 {
    if want == 1 {
      return _err_ddm("db2: DDM 0x" + _hex4(code) + " is not in extended length form at offset " + _dec(start));
    }
    if raw < 4 {
      return _err_ddm("db2: DDM length " + _dec(raw) + " below minimum 4 at offset " + _dec(start));
    }
    length = raw;
  } else {
    let n: Int = (raw & 32767) - 4;
    if n == 0 {
      return _err_ddm("db2: layer-B streaming DDM length 0x8004 not supported for codepoint 0x" + _hex4(code) + " at offset " + _dec(start));
    }
    if n != 4 && n != 6 && n != 8 {
      return _err_ddm("db2: invalid extended DDM length marker 0x" + _hex4(raw) + " at offset " + _dec(start));
    }
    let estart: Int = cstart + 2;
    if estart + n > total {
      return _err_ddm("db2: truncated extended DDM length at offset " + _dec(estart));
    }
    if n == 8 {
      let top: Int = _r_byte_mut(r, estart);
      if top >= 128 {
        return _err_ddm("db2: extended DDM length exceeds signed range at offset " + _dec(estart));
      }
    }
    var v: Int = 0;
    var i = 0;
    while i < n {
      let bb: Int = _r_byte_mut(r, estart + i);
      v = v * 256 + bb;
      i = i + 1;
    }
    let header: Int = 4 + n;
    if v < header {
      return _err_ddm("db2: extended DDM length " + _dec(v) + " below header size " + _dec(header) + " at offset " + _dec(start));
    }
    length = v;
    ext_bytes = n;
    long_form = true;
  }
  if want == 0 && long_form {
    return _err_ddm("db2: DDM 0x" + _hex4(code) + " is unexpectedly in extended length form at offset " + _dec(start));
  }
  if start + length > total {
    return _err_ddm("db2: DDM length " + _dec(length) + " overruns buffer (" + _dec(total - start) + " bytes remain) at offset " + _dec(start));
  }
  let header_size: Int = 4 + ext_bytes;
  r.pos = start + header_size;
  let br = _read_n(r, length - header_size);
  if !br.is_ok {
    return _err_ddm(br.error);
  }
  let payload: Vec[UInt8] = br.value;
  return _ok_ddm(Db2Ddm{ code: code; length: length; long_form: long_form; ext_bytes: ext_bytes; payload: payload; });
}

/// Parse one DDM from `r`, advancing the cursor. The 2-byte length is used
/// as-is when its high bit is clear; when the high bit is set the marker is
/// 0x8008/0x800A/0x800C for a 4/6/8-byte extended length that follows the
/// codepoint (0x8004 is the layer-B streaming form and is rejected here).
/// Unknown codepoints are preserved raw. Every error carries a byte offset.
/// Complexity: O(length).
pub fn db2_ddm_read(r: &mut Db2Reader) -> Result[Db2Ddm, Str] {
  return _ddm_read_form(r, -1);
}

/// Like db2_ddm_read but enforces the caller's expectation of the length
/// form: `long_form` true requires the extended (4-byte) length and false
/// requires the 2-byte length. The advisory db2_cp_is_long_length table
/// names the codepoints peers commonly write in the extended form.
/// Complexity: O(length).
pub fn db2_ddm_read_as(r: &mut Db2Reader, long_form: Bool) -> Result[Db2Ddm, Str] {
  if long_form {
    return _ddm_read_form(r, 1);
  }
  return _ddm_read_form(r, 0);
}

/// Parse a flat sequence of DDMs (a DSS payload). An empty payload yields
/// an empty list. Errors keep the offsets of the underlying DDM reader.
/// Complexity: O(payload).
pub fn db2_ddms_parse(payload: Vec[UInt8]) -> Result[Db2DdmList, Str] {
  var codes = Vec[Int].new();
  var longs = Vec[Bool].new();
  var lens = Vec[Int].new();
  var pls = Vec[Vec[UInt8]].new();
  var r = Db2Reader{ data: payload; pos: 0; };
  while r.pos < r.data.len() {
    let dr = db2_ddm_read(&mut r);
    if !dr.is_ok {
      return _err_ddmlist(dr.error);
    }
    let d: Db2Ddm = dr.value;
    codes.push(d.code);
    longs.push(d.long_form);
    lens.push(d.length);
    let p: Vec[UInt8] = d.payload;
    pls.push(p);
  }
  return _ok_ddmlist(Db2DdmList{ codes: codes; long_forms: longs; lengths: lens; payloads: pls; });
}

// --------------------------------------------------
//  Character data
// --------------------------------------------------

// Scan `bytes` for printable ASCII. With `nul_pad` the first 0x00 ends the
// text (NUL terminated) and the remaining bytes are ignored; without it a
// NUL makes the payload opaque. Returns the decoded text (empty when
// opaque) plus the always-preserved raw bytes.
fn _scan_ascii(bytes: &Vec[UInt8], nul_pad: Bool) -> Db2Text {
  var sb = Vec[UInt8].new();
  var ascii = true;
  var done = false;
  var i = 0;
  while i < bytes.len() && !done {
    let x: Int = (bytes[i] as Int) & 0xFF;
    if nul_pad && x == 0 {
      done = true;
    } else {
      if x < 32 || x > 126 {
        ascii = false;
      } else {
        if ascii {
          sb.push(bytes[i]);
        }
      }
      i = i + 1;
    }
  }
  var text = "";
  if ascii {
    text = builder.sb_to_str(&sb);
  }
  let raw: Vec[UInt8] = _copy_bytes(bytes);
  return Db2Text{ text: text; ascii: ascii; bytes: raw; };
}

/// Decode a parameter payload as printable-ASCII character data. When any
/// byte falls outside 0x20..0x7E (EBCDIC and friends) the result is flagged
/// opaque with text "" and the raw bytes preserved. Complexity: O(payload).
pub fn db2_text_ascii(payload: Vec[UInt8]) -> Db2Text {
  return _scan_ascii(&payload, false);
}

/// Like db2_text_ascii but treats the first 0x00 as a terminator, for the
/// NUL-padded string convention some peers use (e.g. TYPDEFNAM).
/// Complexity: O(payload).
pub fn db2_text_nul_terminated(payload: Vec[UInt8]) -> Db2Text {
  return _scan_ascii(&payload, true);
}

/// The text of a decoded payload with trailing spaces removed. An opaque
/// text is returned unchanged (it is already ""). Complexity: O(text).
pub fn db2_text_trimmed(t: &Db2Text) -> Str {
  let s: Str = t.text;
  let n: Int = s.len();
  var e = n;
  var go = true;
  while go && e > 0 {
    let b: Int = (string.byte_at(s, e - 1) as Int) & 0xFF;
    if b == 32 {
      e = e - 1;
    } else {
      go = false;
    }
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < e {
    sb.push(string.byte_at(s, i));
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// Read one VCM (variable-length character string): a 2-byte big-endian
/// length then that many bytes, decoded as ASCII with the EBCDIC set flagged
/// opaque. Err("db2: truncated VCM at offset N") when the length overruns.
/// Complexity: O(payload).
pub fn db2_vcm_read(r: &mut Db2Reader) -> Result[Db2Text, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + 2 > total {
    return _err_text("db2: truncated VCM at offset " + _dec(start));
  }
  let b0: Int = _r_byte_mut(r, start);
  let b1: Int = _r_byte_mut(r, start + 1);
  let n: Int = b0 * 256 + b1;
  if start + 2 + n > total {
    return _err_text("db2: truncated VCM at offset " + _dec(start));
  }
  r.pos = start + 2;
  let br = _read_n(r, n);
  if !br.is_ok {
    return _err_text(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  return _ok_text(_scan_ascii(&bytes, false));
}

/// Parse a SECMEC parameter payload: one or more 2-byte big-endian security
/// mechanism values. Err("db2: odd SECMEC payload length N at offset 0")
/// when the payload is not a whole number of u16 values.
/// Complexity: O(payload).
pub fn db2_secmec_parse(payload: Vec[UInt8]) -> Result[Vec[Int], Str] {
  let n: Int = payload.len();
  if n % 2 != 0 {
    return _err_ints("db2: odd SECMEC payload length " + _dec(n) + " at offset 0");
  }
  var out = Vec[Int].new();
  var r = Db2Reader{ data: payload; pos: 0; };
  while r.pos < r.data.len() {
    let ur = db2_read_u16(&mut r);
    if !ur.is_ok {
      return _err_ints(ur.error);
    }
    let v: Int = ur.value;
    out.push(v);
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  FD:OCA descriptors and row data
// --------------------------------------------------

/// Parse an FDODSC payload: descriptor block length byte, the 0x76 0xD0
/// marker, then `count` 3-byte triplets (1-byte type + 2-byte big-endian
/// length); a triplet length of 0x3FFF marks a variable-length column.
/// Bytes after the descriptor block are preserved in `trailer`. Errors:
/// too short, bad length, bad marker, or a triplet byte count that is not a
/// multiple of 3, each with its offset. Complexity: O(payload).
pub fn db2_fdodsc_parse(payload: Vec[UInt8]) -> Result[Db2Descriptor, Str] {
  let n: Int = payload.len();
  if n < 3 {
    return _err_desc("db2: FDODSC descriptor too short (" + _dec(n) + " bytes) at offset 0");
  }
  let desc_len: Int = (payload[0] as Int) & 0xFF;
  if desc_len < 3 || desc_len > n {
    return _err_desc("db2: FDODSC descriptor length " + _dec(desc_len) + " invalid at offset 0");
  }
  let hi: Int = (payload[1] as Int) & 0xFF;
  let lo: Int = (payload[2] as Int) & 0xFF;
  if hi != 118 || lo != 208 {
    return _err_desc("db2: FDODSC marker 0x" + _hex2(hi) + _hex2(lo) + " (expected 0x76D0) at offset 1");
  }
  let body: Int = desc_len - 3;
  if body % 3 != 0 {
    return _err_desc("db2: FDODSC triplet bytes " + _dec(body) + " not a multiple of 3 at offset 0");
  }
  let count: Int = body / 3;
  var types = Vec[Int].new();
  var lens = Vec[Int].new();
  var i = 0;
  while i < count {
    let o: Int = 3 + i * 3;
    let t: Int = (payload[o] as Int) & 0xFF;
    let h: Int = (payload[o + 1] as Int) & 0xFF;
    let l: Int = (payload[o + 2] as Int) & 0xFF;
    types.push(t);
    lens.push(h * 256 + l);
    i = i + 1;
  }
  var trailer = Vec[UInt8].new();
  var j = desc_len;
  while j < n {
    trailer.push(payload[j]);
    j = j + 1;
  }
  return _ok_desc(Db2Descriptor{ count: count; types: types; lengths: lens; trailer: trailer; });
}

/// Parse an FDODTA payload against a descriptor: for every column a 1-byte
/// null indicator (0x00 present, 0xFF null) followed by the column value --
/// a fixed number of bytes for a fixed-length triplet, or a 2-byte
/// big-endian length plus that many bytes when the triplet length is 0x3FFF.
/// Returns the null flags and values (parallel, `count` entries) plus the
/// consumed byte count. Errors: truncation and invalid null indicators with
/// offsets. Complexity: O(payload).
pub fn db2_fdodta_parse(payload: Vec[UInt8], d: &Db2Descriptor) -> Result[Db2DtaRow, Str] {
  let n: Int = payload.len();
  let count: Int = d.count;
  var nulls = Vec[Bool].new();
  var vals = Vec[Vec[UInt8]].new();
  var r = Db2Reader{ data: payload; pos: 0; };
  var i = 0;
  while i < count {
    let start: Int = r.pos;
    let nr = db2_read_u8(&mut r);
    if !nr.is_ok {
      return _err_row(nr.error);
    }
    let ind: Int = nr.value;
    if ind == 255 {
      nulls.push(true);
      vals.push(Vec[UInt8].new());
    } else if ind == 0 {
      let dl: Int = d.lengths[i];
      nulls.push(false);
      if dl == 16383 {
        let vr = db2_read_u16(&mut r);
        if !vr.is_ok {
          return _err_row(vr.error);
        }
        let vlen: Int = vr.value;
        let br = _read_n(&mut r, vlen);
        if !br.is_ok {
          return _err_row(br.error);
        }
        let v: Vec[UInt8] = br.value;
        vals.push(v);
      } else {
        if r.pos + dl > n {
          return _err_row("db2: truncated FDODTA value at offset " + _dec(r.pos));
        }
        let br = _read_n(&mut r, dl);
        if !br.is_ok {
          return _err_row(br.error);
        }
        let v: Vec[UInt8] = br.value;
        vals.push(v);
      }
    } else {
      return _err_row("db2: invalid FDODTA null indicator " + _dec(ind) + " at offset " + _dec(start));
    }
    i = i + 1;
  }
  return _ok_row(Db2DtaRow{ col_count: count; null_flags: nulls; values: vals; consumed: r.pos; });
}

/// Parse an SQLDTA / SQLDTARD payload: the FD:OCA descriptor (FDODSC 0x0010)
/// and data (FDODTA 0x147A) nested codepoints are located in the flat DDM
/// list and the row is decoded with db2_fdodta_parse. Errors: missing
/// FDODSC or FDODTA, plus every descriptor/data error. Complexity: O(payload).
pub fn db2_sqldta_parse(payload: Vec[UInt8]) -> Result[Db2DtaRow, Str] {
  let lr = db2_ddms_parse(payload);
  if !lr.is_ok {
    return _err_row(lr.error);
  }
  let list: Db2DdmList = lr.value;
  let di: Int = db2_ddm_list_find(&list, 16);
  if di < 0 {
    return _err_row("db2: SQLDTA missing FDODSC at offset 0");
  }
  let ti: Int = db2_ddm_list_find(&list, 5242);
  if ti < 0 {
    return _err_row("db2: SQLDTA missing FDODTA at offset 0");
  }
  let dsc: Vec[UInt8] = list.payloads[di];
  let dta: Vec[UInt8] = list.payloads[ti];
  let dr = db2_fdodsc_parse(dsc);
  if !dr.is_ok {
    return _err_row(dr.error);
  }
  let d: Db2Descriptor = dr.value;
  return db2_fdodta_parse(dta, &d);
}

// --------------------------------------------------
//  SQLCARD (SQLCA reply data)
// --------------------------------------------------

// A platform-order signed 32-bit value at `off`. order 1 is little-endian
// (QTDSQLX86), anything else is big-endian (network / QTDSQL370).
fn _i32_order(b: &Vec[UInt8], off: Int, order: Int) -> Int {
  let b0: Int = (b[off] as Int) & 0xFF;
  let b1: Int = (b[off + 1] as Int) & 0xFF;
  let b2: Int = (b[off + 2] as Int) & 0xFF;
  let b3: Int = (b[off + 3] as Int) & 0xFF;
  if order == 1 {
    return _sign_extend(b0 + b1 * 256 + b2 * 65536 + b3 * 16777216, 32);
  }
  return _sign_extend(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3, 32);
}

// The default text value used before a VCM field has been read.
fn _empty_text() -> Db2Text {
  return Db2Text{ text: ""; ascii: false; bytes: Vec[UInt8].new() };
}

// The card returned for the single-byte 0xFF "no SQLCA" SQLCARD form.
fn _empty_card() -> Db2SqlCard {
  return Db2SqlCard{ present: false; sqlcode: 0; sqlstate: ""; sqlstate_ascii: false; errproc: Vec[UInt8].new(); update_count: 0; errd: Vec[Int].new(); sqlwarn: Vec[UInt8].new(); sqlwarn_present: false; rdbnam: ""; rdbnam_ascii: false; message: ""; message_ascii: false; message_bytes: Vec[UInt8].new(); diag_tail: Vec[UInt8].new() };
}

/// Parse an SQLCARD payload. The single byte 0xFF is the "no SQLCA" form
/// (present = false). Otherwise the fixed SQLCAGRP is read (group flag,
/// SQLCODE, SQLSTATE, SQLERRPROC, the SQLCAXGRP flag and, when the extended
/// group is present, SQLERRD and SQLWARN) followed by the SQLDIAGGRP VCM
/// fields SQLRDBNAM, SQLERRMSGC and SQLERRMSGS; remaining bytes are kept in
/// diag_tail. `byteorder` is db2_byteorder_big or db2_byteorder_little for
/// the platform fields SQLCODE and SQLERRD. Errors: empty, short and
/// malformed cards plus truncated VCM fields, each with offsets.
/// Complexity: O(payload).
pub fn db2_sqlcard_parse(payload: Vec[UInt8], byteorder: Int) -> Result[Db2SqlCard, Str] {
  let n: Int = payload.len();
  if n < 1 {
    return _err_card("db2: empty SQLCARD at offset 0");
  }
  let f0: Int = (payload[0] as Int) & 0xFF;
  if f0 == 255 {
    return _ok_card(_empty_card());
  }
  if f0 != 0 {
    return _err_card("db2: SQLCARD group flag 0x" + _hex2(f0) + " invalid at offset 0");
  }
  if n < 19 {
    return _err_card("db2: SQLCARD too short (" + _dec(n) + " bytes, need 19) at offset 0");
  }
  let sqlcode: Int = _i32_order(&payload, 1, byteorder);
  var st_state = Vec[UInt8].new();
  var st_ascii = true;
  var i = 0;
  while i < 5 {
    let x: Int = (payload[5 + i] as Int) & 0xFF;
    if x < 32 || x > 126 {
      st_ascii = false;
    } else {
      st_state.push(payload[5 + i]);
    }
    i = i + 1;
  }
  var state = "";
  if st_ascii {
    state = builder.sb_to_str(&st_state);
  }
  var errproc = Vec[UInt8].new();
  var j = 10;
  while j < 18 {
    errproc.push(payload[j]);
    j = j + 1;
  }
  let xflag: Int = (payload[18] as Int) & 0xFF;
  var errd = Vec[Int].new();
  var warn = Vec[UInt8].new();
  var warn_present = false;
  var pos = 19;
  if xflag == 0 {
    if n < 54 {
      return _err_card("db2: SQLCARD too short (" + _dec(n) + " bytes, need 54) at offset 0");
    }
    var e = 0;
    while e < 6 {
      errd.push(_i32_order(&payload, 19 + e * 4, byteorder));
      e = e + 1;
    }
    var w = 0;
    while w < 11 {
      warn.push(payload[43 + w]);
      w = w + 1;
    }
    warn_present = true;
    pos = 54;
  } else if xflag == 255 {
    pos = 19;
  } else {
    return _err_card("db2: SQLCARD extended group flag 0x" + _hex2(xflag) + " invalid at offset 18");
  }
  var update_count = 0;
  if errd.len() >= 3 {
    let uc: Int = errd[2];
    update_count = uc;
  }
  var r = Db2Reader{ data: _copy_bytes(&payload); pos: pos; };
  var rdbnam_text: Db2Text = _empty_text();
  var msgc: Db2Text = _empty_text();
  var msgs: Db2Text = _empty_text();
  if r.pos < r.data.len() {
    let tr = db2_vcm_read(&mut r);
    if !tr.is_ok {
      return _err_card(tr.error);
    }
    rdbnam_text = tr.value;
  }
  if r.pos < r.data.len() {
    let tr2 = db2_vcm_read(&mut r);
    if !tr2.is_ok {
      return _err_card(tr2.error);
    }
    msgc = tr2.value;
  }
  if r.pos < r.data.len() {
    let tr3 = db2_vcm_read(&mut r);
    if !tr3.is_ok {
      return _err_card(tr3.error);
    }
    msgs = tr3.value;
  }
  var message = "";
  var message_ascii = false;
  var message_bytes = Vec[UInt8].new();
  let mc_text: Str = msgc.text;
  if mc_text.len() > 0 {
    message = mc_text;
    message_ascii = msgc.ascii;
    message_bytes = _copy_bytes(&msgc.bytes);
  } else {
    let ms_text: Str = msgs.text;
    if ms_text.len() > 0 {
      message = ms_text;
      message_ascii = msgs.ascii;
      message_bytes = _copy_bytes(&msgs.bytes);
    }
  }
  var tail = Vec[UInt8].new();
  while r.pos < r.data.len() {
    tail.push(r.data[r.pos]);
    r.pos = r.pos + 1;
  }
  let rdbnam_str: Str = rdbnam_text.text;
  let rdbnam_ok: Bool = rdbnam_text.ascii;
  return _ok_card(Db2SqlCard{ present: true; sqlcode: sqlcode; sqlstate: state; sqlstate_ascii: st_ascii; errproc: errproc; update_count: update_count; errd: errd; sqlwarn: warn; sqlwarn_present: warn_present; rdbnam: rdbnam_str; rdbnam_ascii: rdbnam_ok; message: message; message_ascii: message_ascii; message_bytes: message_bytes; diag_tail: tail; });
}
