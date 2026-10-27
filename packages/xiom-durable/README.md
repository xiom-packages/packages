# xiom.durable

> **Status:** `incubating` -- conformance **152/152 x2** on v0.65.2
> (2026-10-27; the `xiom.wal` 0.1.1 dep root resolves from the installed
> store). 0.1.0 was published in `eco-v0.1.183` (`9a5c9b4d...`); 0.1.1 is
> being published as the single tag `xiom-durable/v0.1.1`.
> **Deps:** `xiom.std`, `xiom.wal` `0.1.1` (single WAL home; real fsync).
> **Scope:** shared durable-systems substrate -- config, errors, IDs, limits,
> metrics, storage pages, and transaction bookkeeping -- for `xiom-db` and
> `xiom-vector`.

## Layout

| Path | Contents |
|------|----------|
| `src/` | foundation modules + `storage/` (page, checksum, pager, buffer_pool) + `txn/` (state, manager, snapshot) |
| `tests/test_conformance.xi` | 152 contract-guarded checks + explicit `main` harness (v0.64.2 `--run` needs `fn main`) |
| `xiom.toml` | compiler manifest: declares `xiom.wal` so the v0.64.2 dependency-root resolver adds the installed package's source roots |
| `package.xi` | lane manifest (name `xiom.durable`, deps `xiom.std` + `xiom.wal`, packaging/registry) |

## WAL reconciliation (2026-10-09)

`src/wal/*` was deleted; the WAL vocabulary and disk layer are consumed from
the published **`xiom.wal` 0.1.1** package (0.1.0 extracted `eco-v0.1.121`;
0.1.1 adds the real fsync), imported as `use xiom.wal;`. Types and names are
unchanged from the old `xiom.durable.wal.*` modules. `src/txn/*` and
`src/storage/*` are kept.

Durability (from the xiom.wal README): `wal_flush` performs a real fsync
(stdlib wave 115); appends stay path-based, so call `wal_flush` for the
stable-storage barrier. Torn-tail healing keeps the log crash-consistent
regardless of the flush.

## Consumer snippet

```xiom
use xiom.durable.ids;      // PageId, Lsn, TxnId, ...
use xiom.durable.storage.pager;
use xiom.durable.txn.txn_manager;
use xiom.wal;              // the single WAL home
```
