# xiom.chaincore -- specification

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.

Module: `xiom.chaincore` (source: `src/chaincore.xi`).
Dependencies: `xiom.std` (`xiom.convert` only). No FFI, crypto, I/O, clock or
global state.

## 1. Scope and purity contract

`xiom.chaincore` is a deterministic in-memory model of chain-shaped data:

- block headers, transaction records and a chain store;
- append validation (linkage, height monotonicity, work accumulation,
  duplicate detection);
- fork choice by cumulative work with a deterministic tie-break;
- branch reorgs with undo/redo of the recorded best-chain switch;
- an orphan pool with parent-arrival promotion;
- finality-depth tracking;
- structural invariants over the whole store.

Block tags, parent tags and state roots are opaque caller-supplied integers.
The module never computes or checks a hash; cryptographic validity is out of
scope. The caller owns the `ChainStore` and no function reads or writes
process state.

## 2. Conventions

| Name | Value | Meaning |
|---|---|---|
| genesis tag | `1` (`chain_genesis_tag`) | The only block created by `chain_new`. |
| genesis parent | `0` | Sentinel: no block. |
| genesis height | `0` | First height. |
| genesis own work | `1` | Fixed convention. |
| genesis cumulative work | `1` | Equals own work. |
| default finality depth | `6` (`chain_default_finality_depth`) | Fresh store. |

A valid child block declares `parent > 0`, `parent != tag`, `height > 0`,
`work > 0` and `height == parent.height + 1`. Its stored cumulative work is
`parent.works + header.work`. Child heights are therefore always parent
height + 1, so every chain rooted at genesis has strictly increasing heights.

All store lists are parallel `Vec[Int]` arrays addressed by the same index.
All data structures are value types owned by the caller; every store-taking
function takes `&mut ChainStore` so a single uniform borrow discipline is
emitted (no shared-then-mutable reborrow inside a function body).

## 3. Types

### 3.1 `BlockHeader`

```
pub type BlockHeader = {
  parent: Int;   // parent block tag; caller-supplied
  height: Int;   // declared height; validated against the parent
  work: Int;     // own work of this block; must be > 0
  root: Int;     // opaque state root tag; never interpreted
}
```

### 3.2 `ChainStore`

| Field group | Fields | Meaning |
|---|---|---|
| inserted blocks | `tags`, `parents`, `heights`, `own`, `works`, `roots` | Parallel arrays, index `0` is genesis. `works` is cumulative work. |
| orphan pool | `otags`, `oparents`, `oheights`, `oown`, `oroots` | Parallel arrays of parked blocks (declared values). |
| transactions | `tx_block`, `txids`, `txfees` | Flat records: block tag, globally unique id, non-negative fee. |
| fork choice | `best` | Best-tip tag. |
| finality | `finality` | Depth (>= 0). |
| bookkeeping | `last_promoted`, `reorg_events`, `reorg_state`, `reorg_old`, `reorg_new`, `reorg_common`, `undo`, `redo` | Last append promotions and last branch switch. |

Fields are public for inspection; only the `chain_*` functions maintain the
invariants of section 8.

## 4. API reference

All functions below take `&mut ChainStore` unless noted. `Ok`/`Err` results
are `Result[Int, Str]`.

### 4.1 Constants

| Function | Returns |
|---|---|
| `chain_genesis_tag()` | `1` |
| `chain_status_added()` | `2` |
| `chain_status_side()` | `1` |
| `chain_status_orphan()` | `0` |
| `chain_default_finality_depth()` | `6` |
| `chain_violation_genesis()` | `1` |
| `chain_violation_linkage()` | `2` |
| `chain_violation_work()` | `4` |
| `chain_violation_duplicate()` | `8` |
| `chain_violation_best()` | `16` |
| `chain_violation_best_chain()` | `32` |
| `chain_violation_orphans()` | `64` |
| `chain_violation_transactions()` | `128` |

### 4.2 Construction and headers

| Function | Returns | Notes |
|---|---|---|
| `chain_header(parent, height, work, root)` | `BlockHeader` | Pure value constructor; no validation. |
| `chain_new(genesis_root)` | `ChainStore` | Genesis only; `best = 1`; depth 6. O(1). |

### 4.3 Append

`chain_append(c, tag, h) -> Result[Int, Str]`

Validation is attempted in this exact order; the first failing rule rejects
the append and changes nothing:

| # | Condition | Result |
|---|---|---|
| 1 | `tag <= 0` | `Err("chaincore: tag must be positive")` |
| 2 | `tag == 1` | `Err("chaincore: genesis tag is reserved")` |
| 3 | `h.parent <= 0` | `Err("chaincore: parent tag must be positive")` |
| 4 | `h.parent == tag` | `Err("chaincore: block cannot parent itself")` |
| 5 | `h.height <= 0` | `Err("chaincore: height must be positive")` |
| 6 | `h.work <= 0` | `Err("chaincore: work must be positive")` |
| 7 | tag already inserted or parked | `Err("chaincore: duplicate block tag: <tag>")` |
| 8 | parent not inserted | park as orphan; `Ok(0)` |
| 9 | `h.height != parent.height + 1` | `Err("chaincore: height must be parent height + 1")` |

On acceptance the block is inserted with cumulative work
`parent.works + h.work`; the orphan pool is then promoted (section 6); the
fork choice is recomputed (section 5); the returned status describes the
appended tag after all of that:

- `Ok(2)` (`chain_status_added`): the tag is on the best chain;
- `Ok(1)` (`chain_status_side`): inserted, not on the best chain;
- `Ok(0)` (`chain_status_orphan`): parked, parent still unknown.

`chain_last_promoted` reports how many orphans were promoted by this append
(0 when none). Complexity: O(n^2) worst case (fork-choice scan plus orphan
passes), O(n) for a single extension of the best chain.

### 4.4 Fork choice, best chain, reorg

| Function | Returns | Notes |
|---|---|---|
| `chain_best_tag(c)` | `Int` | Current best tip. O(1). |
| `chain_best_height(c)` | `Int` | Height of the best tip. O(n). |
| `chain_best_work(c)` | `Int` | Cumulative work of the best tip. O(n). |
| `chain_best_chain_len(c)` | `Int` | Blocks from best tip back to genesis, inclusive. O(n). |
| `chain_on_best(c, tag)` | `Bool` | True for an inserted tag on the best chain, genesis included. O(n). |
| `chain_reorg_events(c)` | `Int` | Branch switches recorded since `chain_new`. O(1). |
| `chain_reorg_state(c)` | `Int` | `0` none, `1` applied, `2` undone. O(1). |
| `chain_reorg_common(c)` / `chain_reorg_old_tag(c)` / `chain_reorg_new_tag(c)` | `Int` | Last switch: common ancestor, old tip, new tip (`0` when none). O(1). |
| `chain_reorg_undo_count(c)` / `chain_reorg_redo_count(c)` | `Int` | Suffix lengths of the last switch. O(1). |
| `chain_reorg_undo_tag(c, i)` | `Int` | Removed suffix, tip-first; `-1` out of range. O(1). |
| `chain_reorg_redo_tag(c, i)` | `Int` | Added suffix, ancestor-first; `-1` out of range. O(1). |
| `chain_reorg_undo(c)` | `Bool` | If state 1: `best = reorg_old`, state 2, true; else false. O(1). |
| `chain_reorg_redo(c)` | `Bool` | If state 2: `best = reorg_new`, state 1, true; else false. O(1). |

**Fork choice rule.** After every successful append, `best` is the block with
the greatest `works` value; equal values are resolved in favor of the lower
tag. The rule is total and deterministic.

**Reorg rule.** When the recomputed winner differs from the current `best`:

- if the old tip is an ancestor of the new tip (a plain extension), the tip
  changes silently and `reorg_events` does not increase;
- otherwise a branch switch is recorded: `reorg_events += 1`,
  `reorg_old`/`reorg_new` are the tips, `reorg_common` is their deepest
  common ancestor, `undo` lists the removed suffix from the old tip down to
  (exclusive) the ancestor, `redo` lists the added suffix from the common
  ancestor up to the new tip, `reorg_state = 1`.

**Undo/redo rule.** `chain_reorg_undo` restores the previously recorded old
tip and `chain_reorg_redo` re-applies the new tip; each succeeds at most once
per recorded state. An undo is a view: the next `chain_append` recomputes the
fork choice and may restore the heavier tip, recording a fresh switch.

### 4.5 Orphan pool

| Function | Returns | Notes |
|---|---|---|
| `chain_orphan_count(c)` | `Int` | Parked blocks. O(1). |
| `chain_orphan_tag/parent/height/work/root(c, i)` | `Int` | Declared fields; `-1` out of range. O(1). |
| `chain_last_promoted(c)` | `Int` | Promotions of the latest append. O(1). |

**Parking rule.** A block that passes rules 1-7 but names an unknown parent is
parked instead of rejected; its declared header is kept verbatim.

**Promotion rule.** After every append, the pool is scanned in index order in
repeated passes. An orphan is promoted when its parent is now inserted and its
`height == parent.height + 1`, using the declared own work; it is dropped when
the parent is inserted and the height rule fails. Each pass removes at least
one entry (promoted or dropped) or stops, so the pool shrinks monotonically.
Promotion inserts blocks without re-running fork choice per block; the caller's
append recomputes it once at the end. Orphans promoted in a cascade are
reported in `chain_last_promoted`.

### 4.6 Transactions

`chain_add_tx(c, block_tag, tx_id, fee) -> Result[Int, Str]`

| # | Condition | Result |
|---|---|---|
| 1 | `block_tag` not inserted | `Err("chaincore: unknown block: <tag>")` |
| 2 | `fee < 0` | `Err("chaincore: fee must be non-negative")` |
| 3 | `tx_id` already recorded | `Err("chaincore: duplicate transaction id: <id>")` |

On success a flat record is appended and `Ok(chain_block_tx_count(c, block_tag))`
is returned. Ids are globally unique across the whole store; fees are
attributed to the referenced inserted block. Orphans and unknown blocks cannot
receive transactions. Complexity: O(n) in recorded transactions.

| Function | Returns | Notes |
|---|---|---|
| `chain_tx_count(c)` | `Int` | Recorded transactions. O(1). |
| `chain_tx_id_at(c, i)` / `chain_tx_block_at(c, i)` / `chain_tx_fee_at(c, i)` | `Int` | Record fields; `-1` out of range. O(1). |
| `chain_block_tx_count(c, tag)` | `Int` | Transactions attributed to a block (0 when unknown). O(n). |
| `chain_block_fees(c, tag)` | `Int` | Fee sum attributed to a block. O(n). |
| `chain_total_fees(c)` | `Int` | Fee sum over the store. O(n). |

### 4.7 Finality

| Function | Returns | Notes |
|---|---|---|
| `chain_finality_depth(c)` | `Int` | Current depth. O(1). |
| `chain_set_finality_depth(c, d)` | `Bool` | `false` when `d < 0`; otherwise set and true. O(1). |
| `chain_finalized_height(c)` | `Int` | `max(0, best.height - depth)`. O(n). |
| `chain_is_final(c, tag)` | `Bool` | Inserted block with `height <= finalized height`. O(n). |

Genesis (height 0) is final at every depth. Finality is tracking only: the
model does not refuse reorgs that cross the finalized height.

### 4.8 Inserted-block queries

| Function | Returns | Notes |
|---|---|---|
| `chain_known(c, tag)` | `Bool` | Inserted (genesis included). O(n). |
| `chain_block_count(c)` | `Int` | Inserted count. O(1). |
| `chain_tag_at(c, i)` | `Int` | Tag at index, `-1` out of range. O(1). |
| `chain_block_height/parent/work/own_work/root(c, tag)` | `Int` | Field of an inserted block, `-1` when unknown. O(n). |

The `-1` sentinel collides with a caller root of `-1`; caller roots are
expected non-negative (documented limitation).

## 5. Fork choice (normative summary)

1. `best` is initialized to genesis.
2. After every append (including promotions), the winner is recomputed from
   the inserted parallel arrays: maximum `works`, minimum `tags` on ties.
3. Tip changes through ancestors are extensions, not reorgs; all other
   changes are recorded branch switches with undo/redo suffixes.

## 6. Orphan promotion (normative summary)

1. A block with an unknown parent is parked with its declared header.
2. After every append, repeated passes promote attachable orphans and drop
   orphans whose height rule fails against the now-inserted parent.
3. Promotion preserves declared own work and recomputes cumulative work from
   the parent; fork choice runs once at the end of the append.

## 7. Error catalog (exact strings)

```
chaincore: tag must be positive
chaincore: genesis tag is reserved
chaincore: parent tag must be positive
chaincore: block cannot parent itself
chaincore: height must be positive
chaincore: work must be positive
chaincore: duplicate block tag: <tag>
chaincore: height must be parent height + 1
chaincore: unknown block: <tag>
chaincore: fee must be non-negative
chaincore: duplicate transaction id: <id>
```

`<tag>` / `<id>` are decimal strings produced by `xiom.convert.int_to_string`
(exact for the full `Int` range).

## 8. Structural invariants

`chain_violations(c)` returns the OR of the violated bits; `chain_invariants(c)`
is `chain_violations(c) == 0`.

| Bit | Value | Check |
|---|---|---|
| genesis | 1 | Index 0 is tag 1, parent 0, height 0. |
| linkage | 2 | Every non-genesis block's parent is inserted and its height is parent height + 1. |
| work | 4 | Genesis `works == own > 0`; every block `works == parent.works + own` and `own > 0`. |
| duplicate | 8 | No two inserted blocks share a tag. |
| best | 16 | `best` is inserted, has maximal `works`, and no other maximal block has a lower tag. |
| best chain | 32 | Walking parents from `best` reaches tag 0 (genesis) within the block count. |
| orphans | 64 | Every orphan tag is not inserted, its parent is still unknown, `height > 0`, `own > 0`, and orphan tags are unique. |
| transactions | 128 | Every record references an inserted block, `fee >= 0`, and ids are unique. |

The checker is read-only and is exercised by the suite with injected
corruptions (work, duplicate, best).

## 9. Termination

Every loop in the module makes strict progress:

- index scans advance by one and are bounded by a list length;
- orphan promotion removes at least one pool entry per pass;
- the common-ancestor walk strictly lowers the height of the deeper side;
- best-chain and ancestor walks are bounded by the inserted block count.

Therefore every call returns, and the fixture-driven suite runs in
milliseconds of model work.

## 10. Documented limitations

- No cryptographic validation: tags and roots are opaque integers.
- Linear scans: `chain_known`, `chain_on_best`, fork choice and invariant
  checks are O(n); the store targets model-sized data.
- `chain_reorg_undo` is a view; a later append recomputes the winner.
- Finality is not enforced against reorgs.
- `-1` sentinels cannot distinguish an out-of-range query from a stored root
  of `-1`.
