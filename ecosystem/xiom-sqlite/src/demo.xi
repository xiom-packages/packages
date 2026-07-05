module xiom.sqlite.demo

pub fn demo_in_memory() -> Result[Unit, Str] {
  var conn = sqlite_open(":memory:")?;

  sqlite_execute(&conn, "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, age INTEGER, email TEXT);")?;

  sqlite_execute(&conn, "INSERT INTO users (name, age, email) VALUES ('Alice', 30, 'alice@example.com');")?;

  var alice_id = sqlite_last_insert_rowid(&conn);

  var changes = sqlite_changes(&conn);

  sqlite_execute(&conn, "INSERT INTO users (name, age, email) VALUES ('Bob', 25, 'bob@example.com');")?;

  sqlite_execute(&conn, "INSERT INTO users (name, age, email) VALUES ('Charlie', 35, 'charlie@example.com');")?;

  sqlite_execute(&conn, "INSERT INTO users (name, age, email) VALUES ('Diana', NULL, NULL);")?;

  var rows = sqlite_query(&conn, "SELECT id, name, age, email FROM users ORDER BY id;")?;

  var i: Int = 0;
  while i < rows.len() {
    var row = rows[i];
    var j: Int = 0;
    while j < row.columns.len() {
      var val = row.columns[j];
      var str_val = sqlite_value_to_display(&val);
      j = j + 1;
    };
    i = i + 1;
  };

  var young_users = sqlite_query(&conn, "SELECT name, age FROM users WHERE age < 30 ORDER BY age;")?;

  var updated = sqlite_execute(&conn, "UPDATE users SET age = 31 WHERE name = 'Alice';")?;

  var alice_rows = sqlite_query(&conn, "SELECT name, age FROM users WHERE name = 'Alice';")?;

  sqlite_execute(&conn, "DELETE FROM users WHERE name = 'Diana';")?;

  var final_rows = sqlite_query(&conn, "SELECT id, name, age FROM users ORDER BY id;")?;

  var count_rows = sqlite_query(&conn, "SELECT COUNT(*) AS cnt FROM users;")?;

  sqlite_close(conn)?;
  return Ok({});
}

fn sqlite_value_to_display(val: &SqliteValue) -> Str {
  match val.value {
    SqliteValueKind.Null => "NULL",
    SqliteValueKind.Integer(value) => int_to_display(value),
    SqliteValueKind.Real(value) => float_to_display(value),
    SqliteValueKind.Text(value) => "'" + value + "'",
    SqliteValueKind.Blob(value) => "(blob:" + int_to_display(value.len()) + "bytes)",
  }
}

fn int_to_display(value: Int) -> Str {
  if value == 0 { return "0"; };
  var neg: Bool = value < 0;
  var val = value;
  if neg { val = -val; };
  var chars = Vec[Int].new();
  while val > 0 {
    var digit = val % 10;
    chars.push(digit);
    val = val / 10;
  };
  var result = "";
  if neg { result = "-"; };
  var k = chars.len();
  while k > 0 {
    k = k - 1;
    var d = chars[k];
    var ch = native.codepoint_to_char(48 + d);
    result = result + ch;
  };
  return result;
}

fn float_to_display(value: Float64) -> Str {
  var int_part = value as Int;
  var result = int_to_display(int_part);
  result = result + ".";
  var f = value - (int_part as Float64);
  if f < 0.0 { f = -f; };
  var digits: Int = 0;
  while digits < 6 {
    f = f * 10.0;
    var d = f as Int;
    var ch = native.codepoint_to_char(48 + (d % 10));
    result = result + ch;
    f = f - (d as Float64);
    digits = digits + 1;
  };
  return result;
}

pub fn demo_file(path: Str) -> Result[Unit, Str] {
  var conn = sqlite_open(path)?;

  sqlite_execute(&conn, "CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0);")?;

  sqlite_execute(&conn, "INSERT OR IGNORE INTO counters (name, value) VALUES ('visits', 0);")?;

  sqlite_execute(&conn, "UPDATE counters SET value = value + 1 WHERE name = 'visits';")?;

  var rows = sqlite_query(&conn, "SELECT name, value FROM counters;")?;

  sqlite_close(conn)?;
  return Ok({});
}

pub fn demo_prepared_steps() -> Result[Unit, Str] {
  var conn = sqlite_open(":memory:")?;

  sqlite_execute(&conn, "CREATE TABLE numbers (n INTEGER);")?;

  var stmt = sqlite_prepare(&conn, "INSERT INTO numbers (n) VALUES (?);")?;
  sqlite_finalize(stmt)?;

  sqlite_execute(&conn, "INSERT INTO numbers (n) VALUES (10), (20), (30), (40), (50);")?;

  var query_stmt = sqlite_prepare(&conn, "SELECT n FROM numbers WHERE n > ?;")?;

  var rows = sqlite_query(&conn, "SELECT n FROM numbers WHERE n > 25 ORDER BY n;")?;

  var i: Int = 0;
  while i < rows.len() {
    var val = rows[i].columns[0];
    i = i + 1;
  };

  sqlite_finalize(query_stmt)?;

  sqlite_close(conn)?;
  return Ok({});
}

pub fn demo_transaction() -> Result[Unit, Str] {
  var conn = sqlite_open(":memory:")?;

  sqlite_execute(&conn, "CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance REAL NOT NULL);")?;

  sqlite_execute(&conn, "INSERT INTO accounts (id, balance) VALUES (1, 1000.0);")?;
  sqlite_execute(&conn, "INSERT INTO accounts (id, balance) VALUES (2, 500.0);")?;

  sqlite_execute(&conn, "BEGIN TRANSACTION;")?;

  sqlite_execute(&conn, "UPDATE accounts SET balance = balance - 100.0 WHERE id = 1;")?;

  sqlite_execute(&conn, "UPDATE accounts SET balance = balance + 100.0 WHERE id = 2;")?;

  sqlite_execute(&conn, "COMMIT;")?;

  var results = sqlite_query(&conn, "SELECT id, balance FROM accounts ORDER BY id;")?;

  sqlite_close(conn)?;
  return Ok({});
}
