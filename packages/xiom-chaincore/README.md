# xiom.chaincore

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** one dependency-light module that models a blockchain core:
> block headers, transaction records, a chain store with append validation,
> cumulative-work fork choice, reorg undo/redo, an orphan pool with
> parent-arrival promotion and finality-depth tracking.
> **Deps:** `xiom.std` only (the library imports `xiom.convert` for decimal
> error messages; the tests use `xiom.test`, `xiom.io` and
> `xiom.string.compare`).

## What it is

`xiom.chaincore` is a pure, deterministic bookkeeping model for chain-shaped
data. It never hashes, signs, verifies, networks, reads a clock or touches a
file: block tags, parent tags and state roots are opaque caller-supplied
integers, and the caller owns the `ChainStore` and drives every insertion.
Hashes are opaque tags by design, so the model can sit under any consensus or
storage layer without pulling crypto or FFI into the package.

The model is:

- **append-validated** -- a block must reference a positive parent, declare
  `height == parent.height + 1` and `work > 0`; cumulative work is
  `parent.work + own work`; tags are unique across the store and the orphan
  pool;
- **fork-choosing** -- the best tip is the block with the greatest cumulative
  work, ties broken by the lower tag (deterministic);
- **reorg-aware** -- switching to a different branch records the common
  ancestor, the removed suffix (tip-first) and the added suffix
  (ancestor-first), and `chain_reorg_undo` / `chain_reorg_redo` replay the
  last switch;
- **orphan-friendly** -- a block whose parent is unknown is parked; when the
  parent arrives every attachable orphan is promoted in repeated passes, and
  an orphan that violates the height rule is dropped;
- **finality-tracking** -- `finalized height = max(0, best height - depth)`;
  genesis is always final;
- **self-checking** -- `chain_violations` returns a bitmask over genesis
  shape, linkage, work accumulation, duplicates, best-tip choice, best-chain
  reachability, orphan-pool shape and transaction records.

## API

| Function | Returns | Description |
|---|---|---|
| `chain_genesis_tag()` | `Int` | Reserved genesis tag (`1`). |
| `chain_status_added()` | `Int` | `chain_append` status `2`: block is on the best chain. |
| `chain_status_side()` | `Int` | `chain_append` status `1`: attached side branch. |
| `chain_status_orphan()` | `Int` | `chain_append` status `0`: parked as orphan. |
| `chain_default_finality_depth()` | `Int` | Default depth of a fresh store (`6`). |
| `chain_header(parent, height, work, root)` | `BlockHeader` | Build a header value (no validation). |
| `chain_new(genesis_root)` | `ChainStore` | Fresh store: genesis only, best = genesis, depth 6. |
| `chain_append(&mut c, tag, h)` | `Result[Int, Str]` | Validate and insert; promote orphans; recompute best. |
| `chain_add_tx(&mut c, block, id, fee)` | `Result[Int, Str]` | Record a unique transaction for an inserted block. |
| `chain_best_tag/height/work(&mut c)` | `Int` | Best tip tag, height and cumulative work. |
| `chain_best_chain_len(&mut c)` | `Int` | Blocks on the best chain, genesis included. |
| `chain_on_best(&mut c, tag)` | `Bool` | Is the tag on the current best chain? |
| `chain_known(&mut c, tag)` | `Bool` | Is the tag an inserted block? |
| `chain_block_count(&mut c)` | `Int` | Inserted block count, genesis included. |
| `chain_tag_at(&mut c, i)` | `Int` | Tag of inserted block `i`, or `-1`. |
| `chain_block_parent/height/work/own_work/root(&mut c, tag)` | `Int` | Header fields of an inserted block, or `-1`. |
| `chain_orphan_count(&mut c)` | `Int` | Parked orphan count. |
| `chain_orphan_tag/parent/height/work/root(&mut c, i)` | `Int` | Orphan fields, or `-1`. |
| `chain_last_promoted(&mut c)` | `Int` | Orphans promoted by the latest append. |
| `chain_tx_count(&mut c)` | `Int` | Recorded transactions. |
| `chain_tx_id/block/fee_at(&mut c, i)` | `Int` | Flat transaction record fields, or `-1`. |
| `chain_block_tx_count(&mut c, tag)` | `Int` | Transactions attributed to a block. |
| `chain_block_fees(&mut c, tag)` | `Int` | Fee sum attributed to a block. |
| `chain_total_fees(&mut c)` | `Int` | Fee sum over the store. |
| `chain_finality_depth(&mut c)` | `Int` | Current finality depth. |
| `chain_set_finality_depth(&mut c, d)` | `Bool` | Set the depth; negative values rejected. |
| `chain_finalized_height(&mut c)` | `Int` | `max(0, best height - depth)`. |
| `chain_is_final(&mut c, tag)` | `Bool` | Inserted and at/below the finalized height. |
| `chain_reorg_events(&mut c)` | `Int` | Branch switches recorded since `chain_new`. |
| `chain_reorg_state(&mut c)` | `Int` | `0` none, `1` applied, `2` undone. |
| `chain_reorg_common/old_tag/new_tag(&mut c)` | `Int` | Last switch: ancestor, old tip, new tip. |
| `chain_reorg_undo/redo_count(&mut c)` | `Int` | Removed / added suffix lengths. |
| `chain_reorg_undo/redo_tag(&mut c, i)` | `Int` | Removed (tip-first) / added (ancestor-first) tag, or `-1`. |
| `chain_reorg_undo(&mut c)` | `Bool` | Restore the old tip as best (once). |
| `chain_reorg_redo(&mut c)` | `Bool` | Restore the new tip as best (once). |
| `chain_violations(&mut c)` | `Int` | Invariant violation bitmask (`0` clean). |
| `chain_violations_*`-bit accessors | `Int` | `chain_violation_genesis/linkage/work/duplicate/best/best_chain/orphans/transactions`. |
| `chain_invariants(&mut c)` | `Bool` | `chain_violations == 0`. |

All store-taking functions use `&mut ChainStore` (uniform borrow discipline);
readers do not mutate. Full semantics, the exact error catalog and the
invariant bits are in `SPEC.md`.

## Determinism and termination

Fork choice is total (greatest work, then lowest tag). Every loop makes strict
progress: index walks advance, orphan promotion removes at least one entry per
pass, ancestor walks strictly decrease height, and best-chain walks are
bounded by the block count. The suite is fixture-driven and terminates in
milliseconds of model work.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 24 `[PASS]` lines, then `xiom.chaincore: all tests passed`, exit 0.
The run also gates through `scripts/port.ps1 -Package xiom.chaincore`.

## Install / publish

```
xiom pkg install xiom.chaincore@0.1.0   # consumer (once published)
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
