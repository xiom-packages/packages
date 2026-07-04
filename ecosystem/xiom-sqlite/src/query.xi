module xiom.sqlite.query

pub type QueryBuilder = {
  table: Str;
  columns: Vec[Str];
  conditions: Vec[Str];
  order_by: Vec[Str];
  limit_val: Int;
  offset_val: Int;
} derive[Clone]

pub fn QueryBuilder.select(table: Str) -> QueryBuilder {
  var cols = Vec[Str].new();
  var conds = Vec[Str].new();
  var orders = Vec[Str].new();
  return QueryBuilder{
    table: table,
    columns: cols,
    conditions: conds,
    order_by: orders,
    limit_val: -1,
    offset_val: -1,
  };
}

pub fn QueryBuilder.column(qb: &mut QueryBuilder, col: Str) {
  qb.columns.push(col);
}

pub fn QueryBuilder.where_eq(qb: &mut QueryBuilder, col: Str, val: Str) {
  var cond = col;
  cond = cond + " = '";
  cond = cond + val;
  cond = cond + "'";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_neq(qb: &mut QueryBuilder, col: Str, val: Str) {
  var cond = col;
  cond = cond + " != '";
  cond = cond + val;
  cond = cond + "'";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_gt(qb: &mut QueryBuilder, col: Str, val: Str) {
  var cond = col;
  cond = cond + " > '";
  cond = cond + val;
  cond = cond + "'";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_lt(qb: &mut QueryBuilder, col: Str, val: Str) {
  var cond = col;
  cond = cond + " < '";
  cond = cond + val;
  cond = cond + "'";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_like(qb: &mut QueryBuilder, col: Str, pattern: Str) {
  var cond = col;
  cond = cond + " LIKE '";
  cond = cond + pattern;
  cond = cond + "'";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_in(qb: &mut QueryBuilder, col: Str, values: &Vec[Str]) {
  var cond = col;
  cond = cond + " IN (";
  var i = 0;
  while i < values.len() {
    if i > 0 {
      cond = cond + ", ";
    }
    cond = cond + "'";
    cond = cond + values[i];
    cond = cond + "'";
    i = i + 1;
  }
  cond = cond + ")";
  qb.conditions.push(cond);
}

pub fn QueryBuilder.where_raw(qb: &mut QueryBuilder, condition: Str) {
  qb.conditions.push(condition);
}

pub fn QueryBuilder.order_by(qb: &mut QueryBuilder, col: Str, desc: Bool) {
  var clause = col;
  if desc {
    clause = clause + " DESC";
  } else {
    clause = clause + " ASC";
  }
  qb.order_by.push(clause);
}

pub fn QueryBuilder.limit(qb: &mut QueryBuilder, limit: Int) {
  qb.limit_val = limit;
}

pub fn QueryBuilder.offset(qb: &mut QueryBuilder, offset: Int) {
  qb.offset_val = offset;
}

pub fn QueryBuilder.to_sql(qb: &QueryBuilder) -> Str {
  var sql = "SELECT ";
  if qb.columns.len() == 0 {
    sql = sql + "*";
  } else {
    var i = 0;
    while i < qb.columns.len() {
      if i > 0 {
        sql = sql + ", ";
      }
      sql = sql + qb.columns[i];
      i = i + 1;
    }
  }
  sql = sql + " FROM ";
  sql = sql + qb.table;
  if qb.conditions.len() > 0 {
    sql = sql + " WHERE ";
    var j = 0;
    while j < qb.conditions.len() {
      if j > 0 {
        sql = sql + " AND ";
      }
      sql = sql + qb.conditions[j];
      j = j + 1;
    }
  }
  if qb.order_by.len() > 0 {
    sql = sql + " ORDER BY ";
    var k = 0;
    while k < qb.order_by.len() {
      if k > 0 {
        sql = sql + ", ";
      }
      sql = sql + qb.order_by[k];
      k = k + 1;
    }
  }
  if qb.limit_val >= 0 {
    sql = sql + " LIMIT ";
    sql = sql + int_to_str(qb.limit_val);
  }
  if qb.offset_val >= 0 {
    sql = sql + " OFFSET ";
    sql = sql + int_to_str(qb.offset_val);
  }
  sql = sql + ";";
  return sql;
}

fn int_to_str(value: Int) -> Str {
  if value == 0 { return "0"; }
  var neg: Bool = value < 0;
  var val = value;
  if neg { val = -val; }
  var chars = Vec[Str].new();
  while val > 0 {
    var digit = val % 10;
    var ch = digit + ('0' as Int);
    chars.push("");
    var i = chars.len() - 1;
    while i > 0 {
      chars[i] = chars[i - 1];
      i = i - 1;
    }
    chars[0] = "";
    val = val / 10;
  }
  var result = "";
  var j = 0;
  while j < chars.len() {
    result = result + chars[j];
    j = j + 1;
  }
  if neg {
    var r2 = "-";
    r2 = r2 + result;
    return r2;
  }
  return result;
}

pub fn query_select(table: Str) -> QueryBuilder {
  return QueryBuilder.select(table);
}

pub fn query_column(qb: &mut QueryBuilder, col: Str) {
  QueryBuilder.column(qb, col);
}

pub fn query_where_eq(qb: &mut QueryBuilder, col: Str, val: Str) {
  QueryBuilder.where_eq(qb, col, val);
}

pub fn query_order_by(qb: &mut QueryBuilder, col: Str, desc: Bool) {
  QueryBuilder.order_by(qb, col, desc);
}

pub fn query_limit(qb: &mut QueryBuilder, limit: Int) {
  QueryBuilder.limit(qb, limit);
}

pub fn query_offset(qb: &mut QueryBuilder, offset: Int) {
  QueryBuilder.offset(qb, offset);
}

pub fn query_to_sql(qb: &QueryBuilder) -> Str {
  return QueryBuilder.to_sql(qb);
}

pub fn query_insert_sql(table: Str, columns: &Vec[Str]) -> Str {
  var sql = "INSERT INTO ";
  sql = sql + table;
  sql = sql + " (";
  var i = 0;
  while i < columns.len() {
    if i > 0 {
      sql = sql + ", ";
    }
    sql = sql + columns[i];
    i = i + 1;
  }
  sql = sql + ") VALUES (";
  var j = 0;
  while j < columns.len() {
    if j > 0 {
      sql = sql + ", ";
    }
    sql = sql + "?";
    j = j + 1;
  }
  sql = sql + ");";
  return sql;
}

pub fn query_update_sql(table: Str, sets: &Vec[Str], where_clause: Str) -> Str {
  var sql = "UPDATE ";
  sql = sql + table;
  sql = sql + " SET ";
  var i = 0;
  while i < sets.len() {
    if i > 0 {
      sql = sql + ", ";
    }
    sql = sql + sets[i];
    sql = sql + " = ?";
    i = i + 1;
  }
  if where_clause != "" {
    sql = sql + " WHERE ";
    sql = sql + where_clause;
  }
  sql = sql + ";";
  return sql;
}

pub fn query_delete_sql(table: Str, where_clause: Str) -> Str {
  var sql = "DELETE FROM ";
  sql = sql + table;
  if where_clause != "" {
    sql = sql + " WHERE ";
    sql = sql + where_clause;
  }
  sql = sql + ";";
  return sql;
}
