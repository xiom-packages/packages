# PROVENANCE: xiom.postgres

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).

This package is an **EXPLICITLY INDEPENDENT declaration**:

> No upstream implementation code was cloned, vendored, translated,
> generated from, or consulted: **no libpq source, no PostgreSQL server
> source, no third-party PostgreSQL client implementation.** The internals
> declared below are implemented from the protocol's public documentation
> and from openly published specification test vectors.

This is the OWN-READER/protocol lane: the reference for correctness is the
PostgreSQL project's public protocol documentation (protocol version 3,
the same version libpq speaks), and the crate carries no C library, no FFI,
and no bridge code. The 0.0.x stub's `libpq.xiom-bind` FFI placeholder and
its libpq-shaped stub source files were deleted as part of this work.

## 1. Reference documents (what the implementation was written against)

| Area | Reference | Use |
|---|---|---|
| Wire protocol v3 | PostgreSQL documentation, "Frontend/Backend Protocol" (`https://www.postgresql.org/docs/current/protocol.html` and its sub-pages `protocol-message-formats.html`, `protocol-message-flow.html`, `protocol-flow.html`), protocol version 3.0 | every message layout: StartupMessage, PasswordMessage (cleartext/MD5/SASL forms), Query, Terminate; backend Authentication (codes 0/3/5/10/11/12), ParameterStatus, BackendKeyData, ReadyForQuery, RowDescription, DataRow, CommandComplete, EmptyQueryResponse, ErrorResponse/NoticeResponse field letters, NotificationResponse |
| MD5 auth | PostgreSQL documentation, "Password Authentication" (the MD5 challenge construction: `"md5" + md5_hex(md5_hex(password + user) || salt)`) | `auth.pg_md5_password` |
| MD5 | RFC 1321 (MD5) -- algorithm constants and rounds | `auth.md5_digest` (own implementation, because `xiom.crypto.md5` in v0.64.5 is defective; see `AUDIT.md`) |
| SCRAM | RFC 5802 (SCRAM) and RFC 7677 (SCRAM-SHA-256) | `auth.scram_*` family: client-first/final construction, PBKDF2 usage, server-signature verification, nonce and saslname rules |
| SQL literals | PostgreSQL documentation, "SQL Syntax -- String Constants / Identifiers" | `pg_quote_literal` / `pg_quote_identifier` (quote-doubling semantics) |

URLs are recorded for reference identification only; the quoted facts are
the protocols' interoperable wire surface (message kinds, field order,
length conventions, auth exchanges), re-expressed in XIOM with no shared
identifiers or copied text.

## 2. Imported test vectors (openly published data, not upstream code)

These are the only external artifacts imported into the package, and they
live in `tests/test_conformance.xi` as literals:

| Vector | Source | Pinned value |
|---|---|---|
| SCRAM-SHA-256 exchange | RFC 7677 section 3 (the RFC's published example) | client nonce `rOprNGfwEbeRWgbNEkqO`, salt `W22ZaJ0SNY7soEsUEjb6gQ==`, i=4096, password `pencil`; expected client-final `c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=` and server signature `6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=` |
| MD5 | RFC 1321 appendix A.5 test suite | `md5("") = d41d8cd98f00b204e9800998ecf8427e`, `md5("abc") = 900150983cd24fb0d6963f7d28e17f72`, `md5("The quick brown fox jumps over the lazy dog") = 9e107d9d372bb6826bd81d3542a419d6` |
| PostgreSQL MD5 challenge | computed independently with .NET `System.Security.Cryptography.MD5` during the build session (script kept in the session log, not in the repo) | user `pguser`, password `s3cret`, salt `A1B2C3D4` -> `md549a34335002b87ce9bfd06e813246528` |

The RFC 7677 expected values were additionally re-derived from first
principles (PBKDF2-HMAC-SHA256 + HMAC + XOR over the RFC's auth_message in
an independent tool) before being pinned; the RFC strings and the
re-derivation agree exactly.

## 3. Fixture provenance (honest record)

- **No live PostgreSQL server produced any byte in the suite's offline
  section.** All loopback fixtures are scripted messages assembled inside
  `tests/test_conformance.xi` from the declared wire layout; expectations
  are the documented structure itself (lengths, field order, tag parsed to
  affected rows) plus hand-written literal byte arrays for the goldens.
- The codec goldens (frontend messages, backend decode) are literal byte
  arrays transcribed from the reference layout table in `SPEC.md` section 4
  -- not captured from any server or client output.
- The live section (`127.0.0.1:5432`) is environment-dependent and reports
  an explicit SKIP when unreachable or unusable; it makes no claim about a
  particular server version.

## 4. Clone / cleanup ledger

**No oracle repository was cloned or consulted for this package.** No
directory was created under `E:\repos` for this work item, and
`E:\repos\CLEANUP.md` therefore has no row for it and was not modified.
The reference material is documentation and RFCs (section 1) fetched as
text, plus the RFC-published vectors (section 2). If a future revision
wants a full client-vs-libpq parity harness, clone PostgreSQL at a pinned
tag purely as a test oracle at that time and add the ledger row then.

## 5. Re-carve procedure

Nothing to re-carve: there is no upstream code pin. When the protocol
documentation changes or a new protocol version appears, the declared
surface in `SPEC.md` section 4 is re-derived from the new documentation and
the codec goldens are rebuilt by hand -- same procedure as the initial
declaration. Behavior changes are recorded in `SPEC.md` and covered by new
suite entries before the version moves.

## 6. Tooling note

Developed against XIOM v0.64.5 (resolved by `scripts/xiom.ps1`) with
stdlib `E:\xiom-lang\stdlib` as a read-only consumer, inside the package
directory only. Toolchain defects observed and worked around (full record:
`AUDIT.md`):

- `xiom.crypto.md5` returns non-RFC digests -> the package carries its own
  MD5 (RFC 1321) with published vectors.
- A tuple-typed codegen collision at clang level -> module-boundary helpers
  use small structs instead of tuples.
- `xiom.thread.spawn` is simulated (inline execution) -> the deterministic
  loopback harness uses a pre-written server script plus the `attach` fd
  adoption entry instead of a concurrent thread.
- `socket_local_addr` is not exposed and `socket_bind` rejects port 0 ->
  the harness scans candidate ports 45440-45499.
