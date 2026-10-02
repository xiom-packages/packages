// XIOM -- xiom.gcp.bigquery: BigQuery model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the BigQuery surface: dataset/table/field identifier
// rules, qualified names, schema field validation over caller-owned parallel
// vectors, deterministic row-page framing (offset/count/has_more/page token)
// and the job type/state machine. No network, no FFI, no SQL execution.
//
// Documented subset:
//   * dataset/table ids: 1..1024 characters, ASCII letter or '_' first, then
//     ASCII letters/digits/'_'.
//   * field names: 1..300 characters with the same alphabet; duplicate names
//     are detected case-insensitively.
//   * types: STRING, BYTES, INTEGER, FLOAT, NUMERIC, BIGNUMERIC, BOOL,
//     TIMESTAMP, DATE, TIME, DATETIME, GEOGRAPHY, JSON, RECORD.
//   * modes: NULLABLE, REQUIRED, REPEATED.
//   * paging: page_size 1..100000 rows; offset 0..total; the frame reports the
//     row count and "has more" for the page; the token is "offset=N".
//   * jobs: PENDING -> RUNNING -> DONE, with PENDING -> DONE for fast jobs;
//     types QUERY, LOAD, EXTRACT, COPY.
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; no Vec[StructType] (parallel vectors instead); bounded
// loops.

module xiom.gcp.bigquery

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Schema type STRING (1).
pub const BQ_TYPE_STRING: Int = 1;

/// Schema type BYTES (2).
pub const BQ_TYPE_BYTES: Int = 2;

/// Schema type INTEGER (3).
pub const BQ_TYPE_INTEGER: Int = 3;

/// Schema type FLOAT (4).
pub const BQ_TYPE_FLOAT: Int = 4;

/// Schema type NUMERIC (5).
pub const BQ_TYPE_NUMERIC: Int = 5;

/// Schema type BIGNUMERIC (6).
pub const BQ_TYPE_BIGNUMERIC: Int = 6;

/// Schema type BOOL (7).
pub const BQ_TYPE_BOOL: Int = 7;

/// Schema type TIMESTAMP (8).
pub const BQ_TYPE_TIMESTAMP: Int = 8;

/// Schema type DATE (9).
pub const BQ_TYPE_DATE: Int = 9;

/// Schema type TIME (10).
pub const BQ_TYPE_TIME: Int = 10;

/// Schema type DATETIME (11).
pub const BQ_TYPE_DATETIME: Int = 11;

/// Schema type GEOGRAPHY (12).
pub const BQ_TYPE_GEOGRAPHY: Int = 12;

/// Schema type JSON (13).
pub const BQ_TYPE_JSON: Int = 13;

/// Schema type RECORD (14).
pub const BQ_TYPE_RECORD: Int = 14;

/// Highest modeled schema type code (14).
pub const BQ_TYPE_MAX: Int = 14;

/// Field mode NULLABLE (1).
pub const BQ_MODE_NULLABLE: Int = 1;

/// Field mode REQUIRED (2).
pub const BQ_MODE_REQUIRED: Int = 2;

/// Field mode REPEATED (3).
pub const BQ_MODE_REPEATED: Int = 3;

/// Maximum rows per page accepted by the framing model (100000).
pub const BQ_MAX_ROWS_PER_PAGE: Int = 100000;

/// Maximum columns accepted by the schema validator (10000).
pub const BQ_MAX_SCHEMA_FIELDS: Int = 10000;

/// Job type QUERY (1).
pub const BQ_JOB_QUERY: Int = 1;

/// Job type LOAD (2).
pub const BQ_JOB_LOAD: Int = 2;

/// Job type EXTRACT (3).
pub const BQ_JOB_EXTRACT: Int = 3;

/// Job type COPY (4).
pub const BQ_JOB_COPY: Int = 4;

/// Job state PENDING (1).
pub const BQ_JOB_STATE_PENDING: Int = 1;

/// Job state RUNNING (2).
pub const BQ_JOB_STATE_RUNNING: Int = 2;

/// Job state DONE (3).
pub const BQ_JOB_STATE_DONE: Int = 3;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One row page frame: the requested offset, the row count in this page, the
/// total row count and whether another page follows.
pub type BqPage = {
  offset: Int;
  count: Int;
  total: Int;
  has_more: Bool;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_page(v: BqPage) -> Result[BqPage, Str] {
  return Ok(v);
}

fn _err_page(m: Str) -> Result[BqPage, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Identifiers
// --------------------------------------------------

// Shared identifier leaf: 1..max characters, letter or '_' first, then
// letters/digits/'_'.
fn _bq_ident_is_valid(v: Str, max_len: Int) -> Bool {
  let n = v.len();
  if n < 1 {
    return false;
  }
  if n > max_len {
    return false;
  }
  let first = core.gcp_byte(v, 0);
  if !core.gcp_is_alpha(first) {
    if first != 95 {
      return false;
    }
  }
  var i = 1;
  while i < n {
    let c = core.gcp_byte(v, i);
    if !core.gcp_is_alnum(c) {
      if c != 95 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// True for a documented-subset dataset id. Params: dataset_id - the
/// candidate. Complexity O(dataset_id.len()).
pub fn bq_dataset_id_is_valid(dataset_id: Str) -> Bool {
  return _bq_ident_is_valid(dataset_id, 1024);
}

/// True for a documented-subset table id. Params: table_id - the candidate.
/// Complexity O(table_id.len()).
pub fn bq_table_id_is_valid(table_id: Str) -> Bool {
  return _bq_ident_is_valid(table_id, 1024);
}

/// True for a documented-subset field name. Params: name - the candidate.
/// Complexity O(name.len()).
pub fn bq_field_name_is_valid(name: Str) -> Bool {
  return _bq_ident_is_valid(name, 300);
}

/// `project.dataset.table` qualified name. Params: project - the project id;
/// dataset - the dataset id; table - the table id. Returns the qualified name
/// or the first validation error. Complexity O(total length).
pub fn bq_qualified_name(project: Str, dataset: Str, table: Str) -> Result[Str, Str] {
  let pn = project.len();
  if pn < 1 || pn > 63 {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !bq_dataset_id_is_valid(dataset) {
    return _err_str("gcp: invalid dataset id: " + dataset);
  }
  if !bq_table_id_is_valid(table) {
    return _err_str("gcp: invalid table id: " + table);
  }
  return _ok_str(project + "." + dataset + "." + table);
}

// --------------------------------------------------
//  Schema
// --------------------------------------------------

/// Map a schema type name to its BQ_TYPE_* code (0 = unknown). Params: name -
/// the type name. Complexity O(name.len()).
pub fn bq_type_code(name: Str) -> Int {
  if core.gcp_str_eq(name, "STRING") {
    return BQ_TYPE_STRING;
  }
  if core.gcp_str_eq(name, "BYTES") {
    return BQ_TYPE_BYTES;
  }
  if core.gcp_str_eq(name, "INTEGER") {
    return BQ_TYPE_INTEGER;
  }
  if core.gcp_str_eq(name, "FLOAT") {
    return BQ_TYPE_FLOAT;
  }
  if core.gcp_str_eq(name, "NUMERIC") {
    return BQ_TYPE_NUMERIC;
  }
  if core.gcp_str_eq(name, "BIGNUMERIC") {
    return BQ_TYPE_BIGNUMERIC;
  }
  if core.gcp_str_eq(name, "BOOL") {
    return BQ_TYPE_BOOL;
  }
  if core.gcp_str_eq(name, "TIMESTAMP") {
    return BQ_TYPE_TIMESTAMP;
  }
  if core.gcp_str_eq(name, "DATE") {
    return BQ_TYPE_DATE;
  }
  if core.gcp_str_eq(name, "TIME") {
    return BQ_TYPE_TIME;
  }
  if core.gcp_str_eq(name, "DATETIME") {
    return BQ_TYPE_DATETIME;
  }
  if core.gcp_str_eq(name, "GEOGRAPHY") {
    return BQ_TYPE_GEOGRAPHY;
  }
  if core.gcp_str_eq(name, "JSON") {
    return BQ_TYPE_JSON;
  }
  if core.gcp_str_eq(name, "RECORD") {
    return BQ_TYPE_RECORD;
  }
  return 0;
}

/// Canonical schema type name for a code. Params: code - a BQ_TYPE_* code.
/// Returns the name or an "unknown schema type" error. Complexity O(1).
pub fn bq_type_name(code: Int) -> Result[Str, Str] {
  if code == BQ_TYPE_STRING {
    return _ok_str("STRING");
  }
  if code == BQ_TYPE_BYTES {
    return _ok_str("BYTES");
  }
  if code == BQ_TYPE_INTEGER {
    return _ok_str("INTEGER");
  }
  if code == BQ_TYPE_FLOAT {
    return _ok_str("FLOAT");
  }
  if code == BQ_TYPE_NUMERIC {
    return _ok_str("NUMERIC");
  }
  if code == BQ_TYPE_BIGNUMERIC {
    return _ok_str("BIGNUMERIC");
  }
  if code == BQ_TYPE_BOOL {
    return _ok_str("BOOL");
  }
  if code == BQ_TYPE_TIMESTAMP {
    return _ok_str("TIMESTAMP");
  }
  if code == BQ_TYPE_DATE {
    return _ok_str("DATE");
  }
  if code == BQ_TYPE_TIME {
    return _ok_str("TIME");
  }
  if code == BQ_TYPE_DATETIME {
    return _ok_str("DATETIME");
  }
  if code == BQ_TYPE_GEOGRAPHY {
    return _ok_str("GEOGRAPHY");
  }
  if code == BQ_TYPE_JSON {
    return _ok_str("JSON");
  }
  if code == BQ_TYPE_RECORD {
    return _ok_str("RECORD");
  }
  return _err_str("gcp: unknown schema type code: " + core.gcp_int_str(code));
}

/// Validate one schema field triple. Params: name - the field name; type_code
/// - a BQ_TYPE_* code; mode_code - a BQ_MODE_* code. Returns Ok("") or the
/// first error. Complexity O(name.len()).
pub fn bq_field_validate(name: Str, type_code: Int, mode_code: Int) -> Result[Str, Str] {
  if !bq_field_name_is_valid(name) {
    return _err_str("gcp: invalid field name: " + name);
  }
  if type_code < BQ_TYPE_STRING || type_code > BQ_TYPE_MAX {
    return _err_str("gcp: invalid field type code: " + core.gcp_int_str(type_code));
  }
  if mode_code < BQ_MODE_NULLABLE || mode_code > BQ_MODE_REPEATED {
    return _err_str("gcp: invalid field mode code: " + core.gcp_int_str(mode_code));
  }
  return _ok_str("");
}

/// Validate a whole schema given as caller-owned parallel vectors: names,
/// type codes and mode codes must have equal lengths, 1..10000 fields, valid
/// triples and case-insensitively unique names. Params: names - field names;
/// types - BQ_TYPE_* codes; modes - BQ_MODE_* codes. Returns Ok("") or the
/// first error. Complexity O(n^2) in the field count.
pub fn bq_schema_validate(names: &Vec[Str], types: &Vec[Int], modes: &Vec[Int]) -> Result[Str, Str] {
  if names.len() != types.len() {
    return _err_str("gcp: schema names/types length mismatch");
  }
  if names.len() != modes.len() {
    return _err_str("gcp: schema names/modes length mismatch");
  }
  let n = names.len();
  if n < 1 {
    return _err_str("gcp: empty schema");
  }
  if n > BQ_MAX_SCHEMA_FIELDS {
    return _err_str("gcp: schema above 10000 fields");
  }
  var i = 0;
  while i < n {
    let nm: Str = names[i];
    let tc: Int = types[i];
    let mc: Int = modes[i];
    let fv = bq_field_validate(nm, tc, mc);
    if !fv.is_ok {
      let m: Str = fv.error;
      return _err_str(m);
    }
    var j = 0;
    while j < i {
      let prev: Str = names[j];
      if compare.str_compare_ignore_case(prev, nm) == 0 {
        return _err_str("gcp: duplicate field name: " + nm);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return _ok_str("");
}

// --------------------------------------------------
//  Row-page framing
// --------------------------------------------------

/// Frame one page over a result of `total` rows. Params: offset - the first
/// row (0..total); page_size - rows per page (1..100000); total - the total
/// row count (>=0). Returns the BqPage or a validation error. Complexity O(1).
pub fn bq_page_frame(offset: Int, page_size: Int, total: Int) -> Result[BqPage, Str] {
  if total < 0 {
    return _err_page("gcp: negative row total");
  }
  if offset < 0 {
    return _err_page("gcp: negative page offset");
  }
  if offset > total {
    return _err_page("gcp: page offset beyond row total");
  }
  if page_size < 1 {
    return _err_page("gcp: page size below 1");
  }
  if page_size > BQ_MAX_ROWS_PER_PAGE {
    return _err_page("gcp: page size above 100000");
  }
  let remaining = total - offset;
  var count = page_size;
  if count > remaining {
    count = remaining;
  }
  var more = false;
  if offset + count < total {
    more = true;
  }
  let p = BqPage{ offset: offset; count: count; total: total; has_more: more; };
  return _ok_page(p);
}

/// Page token for the next page: "offset=N" when another page follows, else
/// "". Params: p - the frame. Complexity O(digits).
pub fn bq_page_token(p: &BqPage) -> Str {
  if !p.has_more {
    return "";
  }
  let next = p.offset + p.count;
  return "offset=" + core.gcp_int_str(next);
}

// --------------------------------------------------
//  Jobs
// --------------------------------------------------

/// Map a job type name to its BQ_JOB_* code (0 = unknown). Params: name - the
/// type name. Complexity O(name.len()).
pub fn bq_job_type_code(name: Str) -> Int {
  if core.gcp_str_eq(name, "QUERY") {
    return BQ_JOB_QUERY;
  }
  if core.gcp_str_eq(name, "LOAD") {
    return BQ_JOB_LOAD;
  }
  if core.gcp_str_eq(name, "EXTRACT") {
    return BQ_JOB_EXTRACT;
  }
  if core.gcp_str_eq(name, "COPY") {
    return BQ_JOB_COPY;
  }
  return 0;
}

/// Canonical job type name for a code. Params: code - a BQ_JOB_* code.
/// Complexity O(1).
pub fn bq_job_type_name(code: Int) -> Result[Str, Str] {
  if code == BQ_JOB_QUERY {
    return _ok_str("QUERY");
  }
  if code == BQ_JOB_LOAD {
    return _ok_str("LOAD");
  }
  if code == BQ_JOB_EXTRACT {
    return _ok_str("EXTRACT");
  }
  if code == BQ_JOB_COPY {
    return _ok_str("COPY");
  }
  return _err_str("gcp: unknown job type code: " + core.gcp_int_str(code));
}

/// Map a job state name to its BQ_JOB_STATE_* code (0 = unknown). Params: name
/// - the state name. Complexity O(name.len()).
pub fn bq_job_state_code(name: Str) -> Int {
  if core.gcp_str_eq(name, "PENDING") {
    return BQ_JOB_STATE_PENDING;
  }
  if core.gcp_str_eq(name, "RUNNING") {
    return BQ_JOB_STATE_RUNNING;
  }
  if core.gcp_str_eq(name, "DONE") {
    return BQ_JOB_STATE_DONE;
  }
  return 0;
}

/// Canonical job state name for a code. Params: code - a BQ_JOB_STATE_* code.
/// Complexity O(1).
pub fn bq_job_state_name(code: Int) -> Result[Str, Str] {
  if code == BQ_JOB_STATE_PENDING {
    return _ok_str("PENDING");
  }
  if code == BQ_JOB_STATE_RUNNING {
    return _ok_str("RUNNING");
  }
  if code == BQ_JOB_STATE_DONE {
    return _ok_str("DONE");
  }
  return _err_str("gcp: unknown job state code: " + core.gcp_int_str(code));
}

/// True when the modeled job state machine allows `from -> to`. Params: from,
/// to - BQ_JOB_STATE_* codes. Complexity O(1).
pub fn bq_job_transition_allowed(from: Int, to: Int) -> Bool {
  if from == BQ_JOB_STATE_PENDING && to == BQ_JOB_STATE_RUNNING {
    return true;
  }
  if from == BQ_JOB_STATE_PENDING && to == BQ_JOB_STATE_DONE {
    return true;
  }
  if from == BQ_JOB_STATE_RUNNING && to == BQ_JOB_STATE_DONE {
    return true;
  }
  return false;
}

/// True for a documented-subset job id. Params: job_id - the candidate.
/// Complexity O(job_id.len()).
pub fn bq_job_id_is_valid(job_id: Str) -> Bool {
  return _bq_ident_is_valid(job_id, 1024);
}

/// `projects/{project}/jobs/{job_id}`. Params: project - the project id;
/// job_id - the job id. Returns the path or the first validation error.
/// Complexity O(total length).
pub fn bq_job_path(project: Str, job_id: Str) -> Result[Str, Str] {
  let pn = project.len();
  if pn < 1 || pn > 63 {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !bq_job_id_is_valid(job_id) {
    return _err_str("gcp: invalid job id: " + job_id);
  }
  return _ok_str("projects/" + project + "/jobs/" + job_id);
}
