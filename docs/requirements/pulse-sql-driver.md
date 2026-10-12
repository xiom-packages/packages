<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Requirements: PULSE SQL driver (sqlite first)

Status: REQUIREMENTS (2026-10-12, packages lane). Sources: PULSE relay
`REL-20261012-1946-pulse-2` (high), PULSE `docs/DESIGN-SQL-MIGRATIONS.md`
(contract + test plan), `REL-20261010-1548-bindings-11` (consumer build-hook,
with compiler). Owner-requested production ask; PULSE consumes the driver.

## 1. Consumer contract (from the PULSE design doc, sec. 3)

The runner (`pulse_app migrate ...`) needs exactly:

1. **Open/close** from a DSN string (`PULSE_SQL_DSN`; sqlite = file path or
   `:memory:`, optional options e.g. WAL/busy-timeout);
2. **execute** (non-query, returns rows-affected / error) and **query**
   (SELECT -> typed rows by index and by name);
3. **transaction** with explicit begin/commit/rollback and a
   rollback-on-error discipline;
4. a **transactional-DDL capability flag** (sqlite: true, with the
   `-- no-transaction` escape documented);
5. **error mapping** that never loses the sqlite code/message (the runner
   writes audit output);
6. the runner owns lock tables/batches/backup-fence; the driver owns none of
   the migrations policy.

Co-verify: PULSE co-verifies driver + runner together before their 0.3 SQL
unit starts (their test plan sec. 4 exercises ordering/locking/atomicity on
the runner side and needs only 1-5 from the driver).

## 2. Current state (xiom.sqlite 0.3.0, live)

Present: `open`/`close`/`exec`/`prepare`/`step`/bind/column readback,
`SqliteValue` typing, `SqliteRow`/`SqliteResult`, `QueryBuilder`,
`TableDef`/`CreateIndexDef` schema builders, `MigrationManager` (PULSE does
NOT use this -- its runner owns migrations), FFI error codes/messages.

Missing against the contract:
- typed transaction API (today only `exec("BEGIN")` raw);
- DSN parsing/normalization helper;
- capability flags (transactional DDL + journal-mode notes);
- consumer ergonomics: the vendored-C build hook (`-1548-bindings-11`,
  compiler) so a consumer builds xiom.sqlite without the manual
  `--c-source` recipe (documented workaround applies today).

## 3. Deliverable options

- **A (recommended): extend `xiom.sqlite` with a `driver` module** --
  `sql_driver.xi` exposing `SqlDriver` (open_from_dsn, execute, query,
  query_one, transaction_begin/commit/rollback, capability flags,
  last_error) as pure XIOM over the existing FFI surface; ship as 0.4.0.
  Same artifact the consumer already depends on; PULSE needs no new dep.
- B: new native package `xiom.sql` overlaying xiom.sqlite (extra dep +
  duplicated surface; only wins if non-sqlite engines share the facade).
- C: stdlib `xiom.sql` (deferred; the design doc leaves the shape to us,
  but stdlib is the wrong home while the C bridge is package-local).

Recommendation: **A now, B/C when a second engine class (postgres) is
targeted** -- at that point the facade can be extracted without breaking
consumers.

## 4. Ownership + verification

- The package is bindings-lane owned; the proposal to bindings is the
  driver module in `xiom.sqlite` (0.4.0), with the packages lane verifying
  x2 + publishing (normal batch flow).
- Driver-level tests: txn commit/rollback visible state; rollback on
  error; DSN parse cases (path, `:memory:`, opts); capability flags;
  error mapping preserves code+message; `:memory:` + file roundtrips.
- Consumer acceptance: PULSE co-verify + their sec. 4 suite subset.

## 5. Out of scope

- Migrations policy/locks/batches (PULSE runner), schema diffing, ORM
  features, postgres/mysql classes (later engines), connection pooling.
