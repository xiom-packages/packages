# axiom:postgres — PostgreSQL

libpq FFI bindings for AXIOM.

```axiom
use axiom.postgres;

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
