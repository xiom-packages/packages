// XIOM -- xiom.postgres PostgreSQL client (wire protocol v3, pure XIOM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM PostgreSQL client over TCP: StartupMessage authentication
// (cleartext / MD5 / SCRAM-SHA-256), simple Query, Terminate, typed result
// sets and typed errors. Transport is the stdlib socket module; the byte
// codec lives in xiom.postgres.wire and the authentication math in
// xiom.postgres.auth. No FFI, no libpq, no global state, no wall clock:
// the only time-driven behavior is the receive timeout passed through
// socket_recv_timeout. Protocol layout: PostgreSQL "Frontend/Backend
// Protocol" documentation (see PROVENANCE.md).

module xiom.postgres

use xiom.net.socket;
use xiom.string;
use xiom.convert;
use xiom.postgres.wire;
use xiom.postgres.auth;

/// Default receive timeout for connect and query traffic, milliseconds.
pub const PG_DEFAULT_TIMEOUT_MS: Int = 10000;

/// One ParameterStatus ('S') entry reported by the server.
pub type PgParam = {
  name: Str;
  value: Str;
}

/// One NoticeResponse ('N') summary retained on the connection/result.
pub type PgNotice = {
  severity: Str;
  code: Str;
  message: Str;
}

/// A live connection. Holding a PgConn does not own OS resources beyond
/// the socket fd; call `disconnect` to send Terminate and release it.
pub type PgConn = {
  fd: Int;
  host: Str;
  port: Int;
  user: Str;
  database: Str;
  pid: Int;
  secret: Int;
  timeout_ms: Int;
  params: Vec[PgParam];
  notices: Vec[PgNotice];
  rbuf: Vec[UInt8];
}

/// The result of one simple-query round trip. `rows` holds text-format
/// values; NULL is None. For multi-statement query strings the rows of
/// every result set are concatenated, `columns`/`fields` come from the
/// first RowDescription, and `tag`/`affected` reflect the last
/// CommandComplete. Use one statement per call for well-defined results.
pub type QueryResult = {
  columns: Vec[Str];
  fields: Vec[PgField];
  rows: Vec[Vec[Option[Str]]];
  row_count: Int;
  col_count: Int;
  tag: Str;
  affected: Int;
  notices: Vec[PgNotice];
}

fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn bytes_to_str(b: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn drop_front(buf: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = n;
  while i < buf.len() {
    out.push(buf[i]);
    i = i + 1;
  }
  return out;
}

fn notice_from(m: &PgMsg) -> PgNotice {
  return PgNotice{ severity: m.severity; code: m.code; message: m.message };
}

fn send_bytes(fd: Int, bytes: &Vec[UInt8]) -> Result[Unit, PgError] {
  if fd < 0 {
    return Err(err_connection("connection is closed"));
  }
  let sr = socket.socket_send_all(fd, bytes);
  match sr {
    Ok(_) => {
      return Ok(());
    },
    Err(e) => {
      return Err(err_connection(string.str_concat("send failed: ", e)));
    },
  }
}

fn pg_read_message(conn: &mut PgConn) -> Result[PgMsg, PgError] {
  if conn.fd < 0 {
    return Err(err_connection("connection is closed"));
  }
  loop {
    if conn.rbuf.len() >= 5 {
      let lenr = read_i32(&conn.rbuf, 1, conn.rbuf.len());
      var len = 0;
      match lenr {
        Ok(v) => {
          len = v;
        },
        Err(_) => {
          return Err(err_protocol("truncated message header", conn.rbuf.len()));
        },
      }
      if len < 4 {
        return Err(err_protocol("message length below 4", 1));
      }
      if len > PG_MAX_MESSAGE_BYTES {
        return Err(err_protocol("message length above decode cap", 1));
      }
      if conn.rbuf.len() >= 1 + len {
        let dr = wire_decode(&conn.rbuf, 0);
        match dr {
          Ok(msg) => {
            let rest = drop_front(&conn.rbuf, 1 + len);
            conn.rbuf = rest;
            return Ok(msg);
          },
          Err(e) => {
            return Err(e);
          },
        }
      }
    }
    let rr = socket.socket_recv_timeout(conn.fd, 65536, conn.timeout_ms);
    match rr {
      Ok(chunk) => {
        if chunk.len() == 0 {
          if conn.rbuf.len() == 0 {
            return Err(err_connection("server closed the connection"));
          }
          return Err(err_protocol("connection closed in the middle of a message", conn.rbuf.len()));
        }
        var i = 0;
        while i < chunk.len() {
          conn.rbuf.push(chunk[i]);
          i = i + 1;
        }
      },
      Err(e) => {
        return Err(err_timeout(string.str_concat("receive failed or timed out: ", e)));
      },
    }
  }
  return Err(err_timeout("receive loop exited"));
}

fn scram_exchange(conn: &mut PgConn, password: Str, first: PgMsg, client_nonce: Str) -> Result[Unit, PgError] {
  var has_mech = false;
  var mi = 0;
  while mi < first.mechanisms.len() {
    if streq(first.mechanisms[mi], "SCRAM-SHA-256") {
      has_mech = true;
    }
    mi = mi + 1;
  }
  if !has_mech {
    return Err(err_unsupported_auth("server offered no supported SASL mechanism (SCRAM-SHA-256 required)"));
  }
  if password.len() == 0 {
    return Err(err_auth("server requested SCRAM-SHA-256 but no password was supplied"));
  }
  var nonce = client_nonce;
  if nonce.len() == 0 {
    nonce = auth.scram_client_nonce();
  }
  let first_bare = auth.scram_client_first_bare(conn.user, nonce);
  let s1 = send_bytes(conn.fd, &build_sasl_initial("SCRAM-SHA-256", first_bare));
  match s1 {
    Ok(_) => {},
    Err(e) => {
      return Err(e);
    },
  }
  let m1r = pg_read_message(conn);
  match m1r {
    Err(e) => {
      return Err(e);
    },
    Ok(m1) => {
      if !streq(m1.msg_type, "R") {
        return Err(err_protocol("expected SASL continue from server", m1.start));
      }
      if m1.auth_code != AUTH_SASL_CONTINUE {
        return Err(err_auth("unexpected authentication message during SCRAM exchange"));
      }
      let finr = auth.scram_client_final(password, first_bare, nonce, bytes_to_str(&m1.sasl_data));
      var fin_msg = "";
      var sig = "";
      match finr {
        Ok(f) => {
          fin_msg = f.message;
          sig = f.server_sig_b64;
        },
        Err(e) => {
          return Err(e);
        },
      }
      let s2 = send_bytes(conn.fd, &build_sasl_response(fin_msg));
      match s2 {
        Ok(_) => {},
        Err(e) => {
          return Err(e);
        },
      }
      let m2r = pg_read_message(conn);
      match m2r {
        Err(e) => {
          return Err(e);
        },
        Ok(m2) => {
          if !streq(m2.msg_type, "R") {
            return Err(err_protocol("expected SASL final from server", m2.start));
          }
          if m2.auth_code != AUTH_SASL_FINAL {
            return Err(err_auth("unexpected authentication message during SCRAM exchange"));
          }
          let vr = auth.scram_verify_server_final(bytes_to_str(&m2.sasl_data), sig);
          match vr {
            Ok(_) => {
              return Ok(());
            },
            Err(e) => {
              return Err(e);
            },
          }
        },
      }
    },
  }
  return Err(err_protocol("SCRAM exchange exited", -1));
}

fn startup_loop(conn: &mut PgConn, password: Str, client_nonce: Str) -> Result[Unit, PgError] {
  let sr = send_bytes(conn.fd, &build_startup(conn.user, conn.database));
  match sr {
    Ok(_) => {},
    Err(e) => {
      return Err(e);
    },
  }
  var auth_done = false;
  loop {
    let mr = pg_read_message(conn);
    match mr {
      Err(e) => {
        return Err(e);
      },
      Ok(msg) => {
        let t = msg.msg_type;
        if streq(t, "R") {
          let code = msg.auth_code;
          if code == AUTH_OK {
            auth_done = true;
          } elif code == AUTH_CLEARTEXT {
            if password.len() == 0 {
              return Err(err_auth("server requested a cleartext password but none was supplied"));
            }
            let spr = send_bytes(conn.fd, &build_password(password));
            match spr {
              Ok(_) => {},
              Err(e) => {
                return Err(e);
              },
            }
          } elif code == AUTH_MD5 {
            if password.len() == 0 {
              return Err(err_auth("server requested an MD5 password but none was supplied"));
            }
            let resp = auth.pg_md5_password(password, conn.user, &msg.salt);
            let spr = send_bytes(conn.fd, &build_password(resp));
            match spr {
              Ok(_) => {},
              Err(e) => {
                return Err(e);
              },
            }
          } elif code == AUTH_SASL {
            let xr = scram_exchange(conn, password, msg, client_nonce);
            match xr {
              Ok(_) => {},
              Err(e) => {
                return Err(e);
              },
            }
          } elif code == AUTH_SASL_CONTINUE || code == AUTH_SASL_FINAL {
            return Err(err_protocol("unexpected SASL message outside the SCRAM exchange", msg.start));
          } else {
            return Err(err_unsupported_auth(string.str_concat(
              "unsupported authentication request (protocol code ",
              string.str_concat(convert.to_string(code), "); supported: cleartext, MD5, SCRAM-SHA-256"))));
          }
        } elif streq(t, "S") {
          conn.params.push(PgParam{ name: msg.param_name; value: msg.param_value });
        } elif streq(t, "K") {
          conn.pid = msg.pid;
          conn.secret = msg.secret;
        } elif streq(t, "N") {
          conn.notices.push(notice_from(&msg));
        } elif streq(t, "E") {
          return Err(server_error_from(&msg));
        } elif streq(t, "A") {
          // Asynchronous notification during startup needs no action here.
        } elif streq(t, "Z") {
          if !auth_done {
            return Err(err_auth("server completed startup without AuthenticationOk"));
          }
          return Ok(());
        } else {
          return Err(err_protocol("unexpected backend message during startup", msg.start));
        }
      },
    }
  }
  return Err(err_protocol("startup loop exited", -1));
}

fn empty_conn(fd: Int, host: Str, port: Int, user: Str, database: Str, timeout_ms: Int) -> PgConn {
  return PgConn{
    fd: fd;
    host: host;
    port: port;
    user: user;
    database: database;
    pid: -1;
    secret: -1;
    timeout_ms: timeout_ms;
    params: Vec[PgParam].new();
    notices: Vec[PgNotice].new();
    rbuf: Vec[UInt8].new();
  };
}

fn validate_target(host: Str, port: Int, user: Str, timeout_ms: Int) -> Result[Unit, PgError] {
  if host.len() == 0 {
    return Err(err_connection("empty host"));
  }
  if port < 1 || port > 65535 {
    return Err(err_connection("port out of range"));
  }
  if user.len() == 0 {
    return Err(err_connection("empty user"));
  }
  if timeout_ms < 1 {
    return Err(err_connection("non-positive timeout"));
  }
  return Ok(());
}

/// Open a connection: TCP + StartupMessage + authentication negotiation
/// (cleartext, MD5, or SCRAM-SHA-256) through ReadyForQuery. Uses the
/// default receive timeout. On failure the socket is released.
pub fn connect(host: Str, port: Int, user: Str, password: Str, database: Str) -> Result[PgConn, PgError] {
  return connect_with_options(host, port, user, password, database, PG_DEFAULT_TIMEOUT_MS, "");
}

/// `connect` with an explicit receive timeout in milliseconds.
pub fn connect_with_timeout(host: Str, port: Int, user: Str, password: Str, database: Str, timeout_ms: Int) -> Result[PgConn, PgError] {
  return connect_with_options(host, port, user, password, database, timeout_ms, "");
}

/// `connect` with every knob explicit. `client_nonce` ("" = generate a
/// fresh CSPRNG nonce) lets callers pin the SCRAM client nonce; production
/// callers should pass "".
pub fn connect_with_options(host: Str, port: Int, user: Str, password: Str, database: Str, timeout_ms: Int, client_nonce: Str) -> Result[PgConn, PgError] {
  let vr = validate_target(host, port, user, timeout_ms);
  match vr {
    Ok(_) => {},
    Err(e) => {
      return Err(e);
    },
  }
  let tcp = socket.socket_tcp();
  var fd = 0;
  match tcp {
    Ok(v) => {
      fd = v;
    },
    Err(_) => {
      return Err(err_connection("socket create failed"));
    },
  }
  let con = socket.socket_connect(fd, host, port);
  match con {
    Ok(_) => {},
    Err(_) => {
      socket.socket_close(fd);
      return Err(err_connection(string.str_concat("connect failed: ", host)));
    },
  }
  return attach(fd, host, port, user, password, database, timeout_ms, client_nonce);
}

/// Take over an already-connected TCP socket fd and run the startup
/// handshake on it (StartupMessage through ReadyForQuery). On success the
/// returned PgConn owns the fd; on failure the fd is closed and must not be
/// used again. This is the transport-injection entry point: callers with an
/// established socket (proxy, reconnect loop, and the deterministic offline
/// conformance harness) use it directly; `connect` is the socket-creating
/// wrapper.
pub fn attach(fd: Int, host: Str, port: Int, user: Str, password: Str, database: Str, timeout_ms: Int, client_nonce: Str) -> Result[PgConn, PgError] {
  if fd < 0 {
    return Err(err_connection("invalid socket fd"));
  }
  let vr = validate_target(host, port, user, timeout_ms);
  match vr {
    Ok(_) => {},
    Err(e) => {
      socket.socket_close(fd);
      return Err(e);
    },
  }
  var conn = empty_conn(fd, host, port, user, database, timeout_ms);
  let sr = startup_loop(&mut conn, password, client_nonce);
  match sr {
    Ok(_) => {},
    Err(e) => {
      socket.socket_close(conn.fd);
      conn.fd = -1;
      return Err(e);
    },
  }
  return Ok(conn);
}

/// Send Terminate and close the socket. Idempotent: a closed connection is
/// left untouched. Send failures are ignored because the socket is being
/// released anyway.
pub fn disconnect(conn: &mut PgConn) {
  if conn.fd >= 0 {
    let term = build_terminate();
    let _ = socket.socket_send_all(conn.fd, &term);
    socket.socket_close(conn.fd);
    conn.fd = -1;
  }
}

/// True while the connection has an open fd.
pub fn pg_is_connected(conn: &PgConn) -> Bool {
  return conn.fd >= 0;
}

/// ParameterStatus value by name ("" when the server never reported it).
pub fn pg_conn_param(conn: &PgConn, name: Str) -> Str {
  var i = 0;
  while i < conn.params.len() {
    if streq(conn.params[i].name, name) {
      return conn.params[i].value;
    }
    i = i + 1;
  }
  return "";
}

/// Run one simple Query ('Q') and collect the full result. Rows are text
/// format; NULLs are None. Errors are typed: server error (kind
/// PG_ERR_SERVER with SQLSTATE and fields), protocol/decode, timeout, or
/// connection. Requires an open connection.
pub fn query(conn: &mut PgConn, text: Str) -> Result[QueryResult, PgError] {
  if conn.fd < 0 {
    return Err(err_connection("connection is closed"));
  }
  let sr = send_bytes(conn.fd, &build_query(text));
  match sr {
    Ok(_) => {},
    Err(e) => {
      return Err(e);
    },
  }
  var columns: Vec[Str] = Vec[Str].new();
  var fields: Vec[PgField] = Vec[PgField].new();
  var rows: Vec[Vec[Option[Str]]] = Vec[Vec[Option[Str]]].new();
  var tag = "";
  var affected = 0;
  var notices: Vec[PgNotice] = Vec[PgNotice].new();
  var got_desc = false;
  var ready = false;
  while !ready {
    let mr = pg_read_message(conn);
    match mr {
      Err(e) => {
        return Err(e);
      },
      Ok(msg) => {
        let t = msg.msg_type;
        if streq(t, "T") {
          if !got_desc {
            got_desc = true;
            var fi = 0;
            while fi < msg.fields.len() {
              let fld = msg.fields[fi];
              columns.push(fld.name);
              fields.push(fld);
              fi = fi + 1;
            }
          }
        } elif streq(t, "D") {
          var vi = 0;
          var row: Vec[Option[Str]] = Vec[Option[Str]].new();
          while vi < msg.values.len() {
            row.push(msg.values[vi]);
            vi = vi + 1;
          }
          rows.push(row);
        } elif streq(t, "C") {
          tag = msg.tag;
          affected = msg.affected;
        } elif streq(t, "I") {
          tag = "";
          affected = 0;
        } elif streq(t, "N") {
          notices.push(notice_from(&msg));
        } elif streq(t, "E") {
          return Err(server_error_from(&msg));
        } elif streq(t, "A") {
          // Asynchronous notification; not part of the query result here.
        } elif streq(t, "Z") {
          ready = true;
        } else {
          return Err(err_protocol("unexpected backend message during query", msg.start));
        }
      },
    }
  }
  let rc = rows.len();
  let cc = columns.len();
  return Ok(QueryResult{
    columns: columns;
    fields: fields;
    rows: rows;
    row_count: rc;
    col_count: cc;
    tag: tag;
    affected: affected;
    notices: notices;
  });
}

/// `query` under a statement-intent name; identical semantics. Rows are
/// still returned for statements that produce them.
pub fn exec(conn: &mut PgConn, text: Str) -> Result[QueryResult, PgError] {
  return query(conn, text);
}

/// Quote a value as a PostgreSQL string literal: wraps in single quotes and
/// doubles embedded single quotes and backslashes, so it is safe with both
/// standard_conforming_strings=on and =off.
///
/// SAFETY: this is a value-literal helper for building SQL text. It cannot
/// make untrusted input safe in every context (identifiers need
/// `pg_quote_identifier`; numbers should be formatted as numbers). Prefer
/// server-side parameters ($1) -- extended-protocol support is declared for
/// 0.2.0; until then this is the documented way to embed values in a simple
/// query.
pub fn pg_quote_literal(value: Str) -> Str {
  var out = Vec[UInt8].new();
  out.push(39);
  var i = 0;
  while i < value.len() {
    let c = value.byte_at(i);
    if c == (39 as UInt8) {
      out.push(39);
      out.push(39);
    } elif c == (92 as UInt8) {
      out.push(92);
      out.push(92);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
  out.push(39);
  return Str::from_utf8(out);
}

/// Quote a name as a PostgreSQL identifier: wraps in double quotes and
/// doubles embedded double quotes. Empty names still round-trip as `""`.
pub fn pg_quote_identifier(name: Str) -> Str {
  var out = Vec[UInt8].new();
  out.push(34);
  var i = 0;
  while i < name.len() {
    let c = name.byte_at(i);
    if c == (34 as UInt8) {
      out.push(34);
      out.push(34);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
  out.push(34);
  return Str::from_utf8(out);
}
