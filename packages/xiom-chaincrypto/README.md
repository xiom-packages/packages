# xiom.chaincrypto

> **Status:** `incubating` -- conformance-tested (19/19); published at `v0.1.0` on the XIOM registry.
> **Scope:** commitment and proof structures over caller-supplied opaque
> integer hashes: append-only accumulator with root history, membership
> proofs, m-of-n threshold gates, commit-reveal records with timelock ticks.
> **Deps:** `xiom.std` (library: `xiom.convert`; tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare`). Pure XIOM, no FFI.

## What it is

`xiom.chaincrypto` models the **structure** of common blockchain commitments
without implementing any cryptography. Hash values are opaque `Int`s in
`0..2147483646` supplied by the caller (who may hash off-module with any
algorithm); this module never hashes and never touches keys, curves or
signatures.

- **Append-only accumulator.** `chaincrypto_accumulator_append` adds one
  opaque leaf hash and returns a new accumulator with updated leaf count,
  root and a `(leaf_count, root)` record appended to the root history.
  Internal nodes use the deterministic, order-sensitive mix
  `combine(l, r) = (l + 31 * r + 7) % 2147483647`, exported as
  `chaincrypto_node_combine`.
- **Membership proofs.** `chaincrypto_accumulator_proof` returns the sibling
  values on the path to the root plus one direction bit per sibling
  (`0` = sibling on the left, `1` = sibling on the right), bottom level
  first. Promoted (unpaired) nodes contribute no entry.
  `chaincrypto_proof_verify` folds a caller-supplied leaf hash up the path and
  compares against a claimed root: `Ok(false)` for any mismatch, `Err` only
  for a malformed proof.
- **m-of-n threshold gate.** `chaincrypto_threshold_new(m, n)` tracks member
  approvals `0..n-1`; duplicate approvals are rejected, the approval set is
  preserved in order, and execution is gated on `m` approvals, a nonce equal
  to `execution_nonce + 1`, and runs at most once. The receipt carries the
  execution nonce, approval count, tick and an opaque digest.
- **Commit-reveal.** `chaincrypto_commit_reveal_new` records an opaque
  commitment with `reveal_tick`/`expiry_tick`; reveals are accepted only in
  `[reveal_tick, expiry_tick)` and only for the committed value, refunds only
  at or after expiry, and each action runs at most once (replay rejected).

The empty accumulator has `leaf_count == 0` and root `-1`
(`chaincrypto_empty_root`), which cannot collide with a real hash.

## Non-goals (honest scope)

- No cryptography: no hashing, keys, signatures, Merkle-Patricia layout or
  wire encoding. The node mix is opaque bookkeeping, not a compression
  function.
- No persistence or serialization of accumulators, proofs or records.
- No network, storage, I/O or global state; all state is in memory.
- No consistency proofs or batch proof generation.
- Not constant-time; do not use as a side-channel hardened primitive.

## API

| Function | Returns | Description |
|---|---|---|
| `chaincrypto_node_combine(l, r)` | `Result[Int, Str]` | Opaque node mix; both inputs must be in `0..2147483646`. |
| `chaincrypto_empty_root()` | `Int` | `-1`, the root of the empty accumulator. |
| `chaincrypto_accumulator_new()` | `ChainAccumulator` | Empty accumulator. |
| `chaincrypto_accumulator_append(acc, h)` | `Result[ChainAccumulator, Str]` | Append one opaque leaf hash; records root history. |
| `chaincrypto_accumulator_leaf_count(acc)` | `Int` | Number of leaves. |
| `chaincrypto_accumulator_root(acc)` | `Int` | Current root. |
| `chaincrypto_accumulator_record(acc)` | `ChainRootRecord` | Leaf count / root pair. |
| `chaincrypto_accumulator_leaf(acc, i)` | `Result[Int, Str]` | Leaf hash `i`. |
| `chaincrypto_accumulator_history_len(acc)` | `Int` | Number of root-history records. |
| `chaincrypto_accumulator_history_count(acc, i)` | `Result[Int, Str]` | Leaf count after append `i + 1`. |
| `chaincrypto_accumulator_history_root(acc, i)` | `Result[Int, Str]` | Root after append `i + 1`. |
| `chaincrypto_accumulator_proof(acc, i)` | `Result[ChainProof, Str]` | Membership proof for leaf `i`. |
| `chaincrypto_proof_verify(p, leaf, root)` | `Result[Bool, Str]` | `Ok(true)` valid; `Ok(false)` mismatch; `Err` malformed. |
| `chaincrypto_proof_leaf_index(p)` | `Int` | Index the proof was generated for. |
| `chaincrypto_proof_leaf_count(p)` | `Int` | Leaf count of the source accumulator. |
| `chaincrypto_proof_root(p)` | `Int` | Root the proof was generated against. |
| `chaincrypto_proof_sibling_count(p)` | `Int` | Number of siblings. |
| `chaincrypto_proof_sibling(p, i)` | `Result[Int, Str]` | Sibling `i`, bottom level first. |
| `chaincrypto_proof_direction(p, i)` | `Result[Int, Str]` | Direction bit of sibling `i` (`0` left, `1` right). |
| `chaincrypto_threshold_new(m, n)` | `Result[ChainThresholdGate, Str]` | Fresh m-of-n gate. |
| `chaincrypto_threshold_is_approved(g, member)` | `Bool` | Whether the member approved. |
| `chaincrypto_threshold_approval_count(g)` | `Int` | Recorded approvals. |
| `chaincrypto_threshold_approvals(g)` | `Vec[Int]` | Copy of approved member indices in order. |
| `chaincrypto_threshold_met(g)` | `Bool` | Whether approvals reached the threshold. |
| `chaincrypto_threshold_approve(g, member)` | `Result[ChainThresholdGate, Str]` | Record one approval (duplicates rejected). |
| `chaincrypto_threshold_execute(g, now, nonce)` | `Result[ChainThresholdGate, Str]` | Run the gate once; requires threshold + next nonce. |
| `chaincrypto_threshold_receipt(g)` | `Result[ChainExecutionReceipt, Str]` | Receipt of an executed gate. |
| `chaincrypto_commit_reveal_new(hash, c, r, e)` | `Result[ChainCommitReveal, Str]` | Commit-phase record (`c < r < e`). |
| `chaincrypto_commit_reveal_phase(cr, now)` | `Int` | `0` waiting, `1` reveal, `2` expired. |
| `chaincrypto_commit_reveal_expired(cr, now)` | `Bool` | `now >= expiry_tick`. |
| `chaincrypto_commit_reveal_reveal(cr, now, value)` | `Result[ChainCommitReveal, Str]` | Reveal in-window with the committed value. |
| `chaincrypto_commit_reveal_refund(cr, now)` | `Result[ChainCommitReveal, Str]` | Refund at/after expiry. |
| `chaincrypto_commit_reveal_commit_hash(cr)` | `Int` | Committed opaque hash. |
| `chaincrypto_commit_reveal_revealed(cr)` | `Bool` | Revealed flag. |
| `chaincrypto_commit_reveal_refunded(cr)` | `Bool` | Refunded flag. |
| `chaincrypto_commit_reveal_value(cr)` | `Result[Int, Str]` | Revealed value, `Err` when never revealed. |

Struct fields are documented in `src/chaincrypto.xi` and `SPEC.md`; build
values through the functions above.

## Usage

```xi
use xiom.io;
use xiom.chaincrypto;

fn demo() -> Bool {
  // 1. Append opaque leaves (hashing happens off-module).
  var acc = chaincrypto_accumulator_new();
  var i = 0;
  while i < 4 {
    let hash = 1000 + i * 37;
    let step = chaincrypto_accumulator_append(&acc, hash);
    if !step.is_ok {
      return false;
    }
    acc = step.value;
    i = i + 1;
  }
  let root = chaincrypto_accumulator_root(&acc);   // 1134343

  // 2. Prove and verify membership of leaf 2.
  let proof_res = chaincrypto_accumulator_proof(&acc, 2);
  if !proof_res.is_ok {
    return false;
  }
  let leaf = chaincrypto_accumulator_leaf(&acc, 2);
  if !leaf.is_ok {
    return false;
  }
  let checked = chaincrypto_proof_verify(&proof_res.value, leaf.value, root);
  if !checked.is_ok {
    return false;
  }
  io.println("membership holds");                 // checked.value == true

  // 3. 2-of-3 threshold gate.
  let gate_res = chaincrypto_threshold_new(2, 3);
  if !gate_res.is_ok {
    return false;
  }
  let g1 = chaincrypto_threshold_approve(&gate_res.value, 0);
  if !g1.is_ok {
    return false;
  }
  let g2 = chaincrypto_threshold_approve(&g1.value, 2);
  if !g2.is_ok {
    return false;
  }
  let done = chaincrypto_threshold_execute(&g2.value, 50, 1);
  if !done.is_ok {
    return false;
  }
  return done.value.executed;
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 19 `[PASS]` lines, then `xiom.chaincrypto: all tests passed`,
exit 0. From the repository root:

```
& .\scripts\port.ps1 -Package xiom.chaincrypto -TimeoutSec 60
```

Last verified: compiler 0.62.2 (stdlib `E:\xiom-lang\stdlib`),
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Implementation notes

- Pure XIOM, free functions only, no FFI, no `Vec[StructType]`: each
  accumulator stores all node values in one flat `Vec[Int]` plus parallel
  level metadata and mirror-pushed history vectors.
- The internal node mix is `(l + 31 * r + 7) % 2147483647`; it is applied
  only to validated hashes, so every derived node stays in range.
- The tree uses iterative odd-node promotion (a lone last node is carried up
  unchanged), the same shape family as `xiom.merkle`, but over opaque `Int`
  hashes instead of bytes.
- Duplicate-approval and replay rejection are explicit error paths with
  pinned messages (see `SPEC.md` section 9).
- See `SPEC.md` for the exact proof format, threshold/timelock rules, error
  catalog and pinned roots.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
