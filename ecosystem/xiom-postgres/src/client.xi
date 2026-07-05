module xiom.postgres.client

pub type PgConnection = {
  handle: Int;
  connected: Bool;
} derive[Clone]

pub type PgResult = {
  columns: Vec[Str];
  rows: Vec[Vec[Option[Str]]];
  row_count: Int;
  col_count: Int;
} derive[Clone]

fn pg_connect(conn_str: Str) -> Result[PgConnection, Str]
  requires: conn_str.len() > 0
  ensures: result.is_ok() implies result.unwrap().handle != 0
  ensures: result.is_ok() implies result.unwrap().connected
{
  let raw = connect(conn_str);
  match raw {
    Ok(handle) => Ok(PgConnection { handle: handle; connected: true; }),
    Err(e) => Err(e),
  }
}

fn pg_disconnect(conn: &mut PgConnection)
  requires: conn.handle != 0
{
  disconnect(conn.handle);
  conn.handle = 0;
  conn.connected = false;
}

fn pg_is_connected(conn: &PgConnection) -> Bool
  requires: conn.handle != 0
{
  is_connected(conn.handle) && conn.connected
}

fn pg_error_message(conn: &PgConnection) -> Str
  requires: conn.handle != 0
{
  error_message(conn.handle)
}

fn pg_query(conn: &PgConnection, sql: Str) -> Result[PgResult, Str]
  requires: conn.handle != 0
  requires: sql.len() > 0
{
  let raw = execute(conn.handle, sql);
  match raw {
    Ok(result) => {
      let mut rows = Vec[Vec[Option[Str]]].with_capacity(result.row_count);
      let mut i = 0;
      while i < result.row_count {
        let mut row = Vec[Option[Str]].with_capacity(result.col_count);
        let mut j = 0;
        while j < result.col_count {
          row.push(result.rows[i].values[j].clone());
          j = j + 1;
        };
        rows.push(row);
        i = i + 1;
      };
      Ok(PgResult {
        columns: result.columns;
        rows: rows;
        row_count: result.row_count;
        col_count: result.col_count;
      })
    }
    Err(e) => Err(e),
  }
}

fn pg_execute_params(conn: &PgConnection, sql: Str, params: &Vec[Str]) -> Result[PgResult, Str]
  requires: conn.handle != 0
  requires: sql.len() > 0
{
  let raw = execute_params(conn.handle, sql, params);
  match raw {
    Ok(result) => {
      let mut rows = Vec[Vec[Option[Str]]].with_capacity(result.row_count);
      let mut i = 0;
      while i < result.row_count {
        let mut row = Vec[Option[Str]].with_capacity(result.col_count);
        let mut j = 0;
        while j < result.col_count {
          row.push(result.rows[i].values[j].clone());
          j = j + 1;
        };
        rows.push(row);
        i = i + 1;
      };
      Ok(PgResult {
        columns: result.columns;
        rows: rows;
        row_count: result.row_count;
        col_count: result.col_count;
      })
    }
    Err(e) => Err(e),
  }
}

fn pg_execute_batch(conn: &PgConnection, queries: &Vec[Str]) -> Result[Vec[PgResult], Str]
  requires: conn.handle != 0
{
  let raw = execute_batch(conn.handle, queries);
  match raw {
    Ok(results) => {
      let mut wrapped = Vec[PgResult].with_capacity(results.len());
      let mut i = 0;
      while i < results.len() {
        let result = &results[i];
        let mut rows = Vec[Vec[Option[Str]]].with_capacity(result.row_count);
        let mut r = 0;
        while r < result.row_count {
          let mut row = Vec[Option[Str]].with_capacity(result.col_count);
          let mut c = 0;
          while c < result.col_count {
            row.push(result.rows[r].values[c].clone());
            c = c + 1;
          };
          rows.push(row);
          r = r + 1;
        };
        wrapped.push(PgResult {
          columns: result.columns.clone();
          rows: rows;
          row_count: result.row_count;
          col_count: result.col_count;
        });
        i = i + 1;
      };
      Ok(wrapped)
    }
    Err(e) => Err(e),
  }
}

fn pg_escape_literal(conn: &PgConnection, value: Str) -> Str
  requires: conn.handle != 0
{
  escape_literal(conn.handle, value)
}

fn pg_escape_identifier(conn: &PgConnection, name: Str) -> Str
  requires: conn.handle != 0
{
  escape_identifier(conn.handle, name)
}

fn pg_begin(conn: &PgConnection) -> Result[Unit, Str]
  requires: conn.handle != 0
{
  begin_transaction(conn.handle)
}

fn pg_commit(conn: &PgConnection) -> Result[Unit, Str]
  requires: conn.handle != 0
{
  commit(conn.handle)
}

fn pg_rollback(conn: &PgConnection) -> Result[Unit, Str]
  requires: conn.handle != 0
{
  rollback(conn.handle)
}
