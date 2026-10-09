# xiom.durable

> **Status:** `incubating` -- conformance green on the pin (v0.64.2):
> **PASS 152/152 x2** via `scripts/port.ps1 -Package xiom-durable -TimeoutSec 120`
> (2026-10-09); not yet published to the XIOM registry.
> **Deps:** `xiom.std`, `xiom.wal` `0.1.0` (single WAL home).
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
the published **`xiom.wal` 0.1.0** package (extracted `eco-v0.1.121`), imported
as `use xiom.wal;`. Types and names are unchanged from the old
`xiom.durable.wal.*` modules. `src/txn/*` and `src/storage/*` are kept.

Durability honesty (from the xiom.wal README): `wal_flush` is an honest no-op
until the stdlib fsync row lands -- crash-consistent (torn-tail healing,
malformed lines skipped on replay), not yet power-loss durable.

## Consumer snippet

```xiom
use xiom.durable.ids;      // PageId, Lsn, TxnId, ...
use xiom.durable.storage.pager;
use xiom.durable.txn.txn_manager;
use xiom.wal;              // the single WAL home
```
