# xiom.postgres

> **Status:** `incubating` -- conformance-tested (38/38), recorded x2 green
> on the pinned toolchain (XIOM v0.64.5); not yet published
> (registry/allowlist gate).
> **Scope:** PostgreSQL wire-protocol (v3) client in pure XIOM: TCP via
> `xiom.net.socket`, StartupMessage, cleartext / MD5 / SCRAM-SHA-256 auth,
> simple Query, typed result sets and typed errors. No FFI, no libpq,
> no bridge C -- the libpq placeholder path is removed.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.net.socket`,
> `xiom.string`, `xiom.convert`, `xiom.crypto`, `xiom.encoding`,
> `xiom.rand`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.postgres` speaks the PostgreSQL v3 frontend/backend protocol directly
over a TCP socket, with the byte codec and the authentication math written
from scratch in XIOM against the public protocol documentation (see
`PROVENANCE.md`):

- `connect(host, port, user, password, database)` -- TCP + StartupMessage +
  authentication negotiation through ReadyForQuery. Cleartext, MD5 and
  SCRAM-SHA-256 (RFC 5802/7677) are implemented; GSSAPI/SSPI and other
  mechanisms return a typed `PG_ERR_UNSUPPORTED_AUTH`.
- `query(conn, sql)` -- one simple Query ('Q') round trip; rows are
  text-format values with NULL as `None`; the result carries column names,
  field descriptors (OIDs, sizes, formats), the command tag and the parsed
  affected-row count (`SELECT 5` -> 5, `INSERT 0 3` -> 3). `exec` is the
  statement-intent alias.
- `disconnect(conn)` -- Terminate ('X') + socket close; idempotent.
- `pg_quote_literal` / `pg_quote_identifier` -- documented safe quoting
  helpers for building SQL text (see the injection caveat in `SPEC.md`).
- Typed errors everywhere: connection, protocol/decode (with the byte
  offset), timeout, auth, unsupported auth, and server errors with SQLSTATE
  and the full server field list preserved.
- Notices ('N') are captured on the connection and on each result.
  ParameterStatus and BackendKeyData are decoded and kept.

No global state, no internal wall clock: the only time-driven behavior is
the receive timeout passed to `socket_recv_timeout`.

## Install / use

Until the package is published to the registry, build against this
checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.postgres
```

Once published:

```
xiom pkg install xiom.postgres@0.1.0
```

## Quick start

```xi
use xiom.postgres;
use xiom.io;

fn main() -> Int {
  let r = connect("127.0.0.1", 5432, "postgres", "secret", "postgres");
  match r {
    Ok(conn) => {
      let q = query(&mut conn, "SELECT id, name FROM users WHERE id = " + pg_quote_literal("7"));
      match q {
        Ok(res) => {
          io.println(res.tag);              // e.g. SELECT 1
          io.println(res.affected);         // 1
          if res.row_count > 0 {
            match res.rows[0][1] {
              Some(name) => { io.println(name); },
              None => { io.println("<null>"); },
            }
          }
        },
        Err(e) => { io.println(e.code + ": " + e.message); },
      }
      disconnect(&mut conn);
    },
    Err(e) => { io.println("connect failed: " + e.message); },
  }
  return 0;
}
```

## Boundaries

`SPEC.md` declares the exact function/type surface, the wire message
layouts, the auth matrix, the error taxonomy and the non-goals (TLS,
extended protocol / `$1` parameters, COPY, notification listening, SASLprep
-- all 0.2 territory, see `ROADMAP.md`). `PROVENANCE.md` records the
independent-declaration basis and the imported public test vectors.
`AUDIT.md` records the verification state and the toolchain defects that
shaped the design.
