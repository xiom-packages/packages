// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.catalog.schema_row

use xiom.db.catalog.schema;
use xiom.db.storage.tuple;

// Local error type for schema-row operations -- mirrors xiom.db.error.DbError.
enum DbError {
  NotFound,
  DuplicateKey,
  ConstraintViolation,
  SchemaMismatch,
  StorageError,
  Corruption,
}

pub type DbResult[T] = Result[T, DbError];

// Stable error codes so consumers can compare without pattern-matching an
// imported enum (m225/C-ORBIT-07 hygiene): 1 NotFound .. 6 Corruption.
pub fn schema_row_error_code(e: DbError) -> Int {
  match e {
    NotFound => { return 1; }
    DuplicateKey => { return 2; }
    ConstraintViolation => { return 3; }
    SchemaMismatch => { return 4; }
    StorageError => { return 5; }
    Corruption => { return 6; }
  }
}

// Schema-driven rows (M5.2): the bridge between the catalog's `ColumnType`
// model and the storage codec's `TValue` model. Pure layer -- no persistence
// (the engine integration and the container decision are documented in
// docs/TYPED-VALUES-STORAGE.md).
//
// Kind mapping (one way, total):
//   IntType    -> VInt
//   FloatType  -> VFloat
//   BoolType   -> VInt restricted to 0/1
//   StringType -> VText
//   BytesType  -> VBlob
//
// Validation rules: arity must equal the column count; the primary-key
// column must carry VInt (the storage key path is int-keyed); non-nullable
// columns may not be VNull; each non-null value must match its column kind;
// bool columns accept exactly 0/1. Error taxonomy: SchemaMismatch for
// shape/kind/pk violations, ConstraintViolation for nullability and bool
// range, Corruption for codec failures and id/pk mismatches on decode.
//
// The encoded row is the tuple codec v2 row (FORMATS 5A) with the row id set
// from the primary-key value; the pk column stays inside the values, so the
// encoding is self-contained. Consumers should use the accessors
// (`tuple2_*`) rather than pattern-matching `TValue` (m225/C-ORBIT-07).

// Kind code expected on disk for a column-type code (see column_type_code).
fn sr_expected_kind(type_code: Int) -> Int {
  if type_code == 1 { return 0x01; } // VInt
  if type_code == 2 { return 0x02; } // VFloat
  if type_code == 3 { return 0x01; } // VInt (bool domain)
  if type_code == 4 { return 0x03; } // VText
  if type_code == 5 { return 0x04; } // VBlob
  return 0;
}

// Value admissibility for one column, INCLUDING nullability: null is allowed
// exactly when the column is nullable; otherwise the value's kind must match
// the column type (bool additionally restricted to 0/1).
pub fn schema_row_value_ok(col: &ColumnDef, v: TValue) -> Bool {
  if tuple2_is_null(v) { return col.nullable; }
  let code = column_type_code(col.col_type);
  let k = tuple2_kind(v);
  if k != sr_expected_kind(code) { return false; }
  if code == 3 {
    match tuple2_int_value(v) {
      None => { return false; }
      Some(b) => {
        if b == 0 { return true; }
        if b == 1 { return true; }
        return false;
      }
    }
  }
  return true;
}

// Validate a full row against the schema.
pub fn schema_row_validate(schema: &Schema, values: &Vec[TValue]) -> DbResult[Bool] {
  if values.len() != schema.columns.len() { return Err(DbError.SchemaMismatch); }
  if schema.primary_key < 0 { return Err(DbError.SchemaMismatch); }
  if schema.primary_key >= schema.columns.len() { return Err(DbError.SchemaMismatch); }
  var i = 0;
  while i < values.len() {
    let col = schema.columns[i];
    let v = values[i];
    if tuple2_is_null(v) {
      if !col.nullable { return Err(DbError.ConstraintViolation); }
    } else {
      let code = column_type_code(col.col_type);
      let k = tuple2_kind(v);
      if k != sr_expected_kind(code) { return Err(DbError.SchemaMismatch); }
      if code == 3 {
        match tuple2_int_value(v) {
          None => { return Err(DbError.SchemaMismatch); }
          Some(b) => {
            if b != 0 && b != 1 { return Err(DbError.ConstraintViolation); }
          }
        }
      }
    }
    i = i + 1;
  }
  let pkv = values[schema.primary_key];
  match tuple2_int_value(pkv) {
    None => { return Err(DbError.SchemaMismatch); }
    Some(_) => {}
  }
  return Ok(true);
}

// The row key: the primary-key column's int value (the int-keyed storage
// path). Validates the whole row first.
pub fn schema_row_key(schema: &Schema, values: &Vec[TValue]) -> DbResult[Int] {
  match schema_row_validate(schema, values) {
    Err(e) => { return Err(e); }
    Ok(_) => {}
  }
  let pkv = values[schema.primary_key];
  match tuple2_int_value(pkv) {
    None => { return Err(DbError.SchemaMismatch); }
    Some(k) => { return Ok(k); }
  }
}

// Validate + encode into a tuple v2 row (id = primary-key value).
pub fn schema_row_encode(schema: &Schema, values: &Vec[TValue]) -> DbResult[Vec[Int]] {
  match schema_row_key(schema, values) {
    Err(e) => { return Err(e); }
    Ok(pk) => {
      match tuple2_encode_row_checked(pk, values) {
        Err(_) => { return Err(DbError.ConstraintViolation); }
        Ok(buf) => { return Ok(buf); }
      }
    }
  }
}

// Decode a stored row and check it against the schema: shape/kind rules must
// hold (schema drift surfaces as SchemaMismatch/ConstraintViolation) and the
// stored id must equal the pk value (else Corruption -- written under a
// different schema).
pub fn schema_row_decode(schema: &Schema, buf: &Vec[Int]) -> DbResult[TypedRow] {
  match tuple2_decode_row(buf) {
    Err(_) => { return Err(DbError.Corruption); }
    Ok(row) => {
      let r: TypedRow = row;
      match schema_row_validate(schema, &r.values) {
        Err(e) => { return Err(e); }
        Ok(_) => {}
      }
      let pkv = r.values[schema.primary_key];
      match tuple2_int_value(pkv) {
        None => { return Err(DbError.Corruption); }
        Some(k) => {
          if k != r.id { return Err(DbError.Corruption); }
        }
      }
      return Ok(r);
    }
  }
}
