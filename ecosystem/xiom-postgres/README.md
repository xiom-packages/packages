# xiom:postgres — PostgreSQL

libpq FFI bindings for XIOM.

```xiom
use xiom.postgres;

fn main() -> Int {
  let conn = connect("host=localhost dbname=mydb")?;
  let result = execute(conn, "SELECT id, name FROM users")?;
  for row in result.rows {
    print(row.values[0].unwrap_or("NULL"));
  }
  disconnect(conn);
  return 0;
}
```
