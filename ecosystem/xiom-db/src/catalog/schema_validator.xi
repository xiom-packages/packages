module xiom.db.catalog.schema_validator
use xiom.db.catalog.schema;
use xiom.db.error;

// Validation for table and index definitions. Kept separate from `schema` so
// the data dictionary stays pure metadata and every write path shares one set
// of rules. All checks return `DbResult[Bool]`, surfacing `SchemaMismatch` /
// `ConstraintViolation` on the first violated rule.

// A schema is well-formed when it names at least one column, the primary key
// index is in range, and every column name is unique.
pub fn validate_schema(schema: &Schema) -> DbResult[Bool] {
  if schema.columns.len() < 1 {
    return Err(DbError.SchemaMismatch);
  }
  if schema.primary_key < 0 {
    return Err(DbError.SchemaMismatch);
  }
  if schema.primary_key >= schema.columns.len() {
    return Err(DbError.SchemaMismatch);
  }
  if !unique_column_names(schema) {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(true);
}

// True when no two columns share a name.
fn unique_column_names(schema: &Schema) -> Bool {
  var i = 0;
  while i < schema.columns.len() {
    var j = i + 1;
    while j < schema.columns.len() {
      if schema.columns[i].name == schema.columns[j].name {
        return false;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// A column is valid when it is named. Type-specific default-value compatibility
// (e.g. a String column may not carry an Int default) is a Phase 4 concern once
// value typing is richer than the current Int-only representation.
pub fn validate_column(col: &ColumnDef) -> DbResult[Bool] {
  if col.name.len() < 1 {
    return Err(DbError.SchemaMismatch);
  }
  // TODO(Phase 4): enforce default_value/col_type compatibility and NOT NULL.
  return Ok(true);
}

// An index definition is valid when it references an in-range column of the
// given schema and its declared table matches.
pub fn validate_index(idx: &IndexDef, schema: &Schema) -> DbResult[Bool] {
  if idx.table != schema.table_name {
    return Err(DbError.SchemaMismatch);
  }
  if idx.column < 0 {
    return Err(DbError.SchemaMismatch);
  }
  if idx.column >= schema.columns.len() {
    return Err(DbError.SchemaMismatch);
  }
  return Ok(true);
}
