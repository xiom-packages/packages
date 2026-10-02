# xiom.data

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-integer dataset utilities: a dataset container with
> iterators, batch assembly/collation, a batched data loader,
> sequential/shuffled/weighted samplers, deterministic MINSTD LCG
> Fisher-Yates shuffling and train/validation/test splitting.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.convert`;
> tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`).

## What it is

`xiom.data` is an integer dataset library with **no floating point, no FFI,
no file I/O, no threads and no global state**. Every value is an `Int`; every
order, batch and split is deterministic and reproducible.

- **Dataset** (`xiom.data`, `src/data.xi`): `{ n, width, xs, ys }` -- `n`
  samples of `width` integer features, `xs` the flat row-major feature
  buffer of exactly `n * width` values, `ys` the parallel label vector of
  exactly `n` labels. Validated construction (`dataset_from_flat`,
  `dataset_from_labels`), accessors (`dataset_get`, `dataset_label`,
  `dataset_row`), copies (`dataset_values`, `dataset_labels`) and a forward
  index iterator (`dataset_iter` / `dataset_iter_next` / `dataset_iter_reset`).
- **Batch** (`xiom.data.batch`, `src/batch.xi`): `{ n, width, xs, ys,
  indices }` assembled from a dataset by an explicit index list
  (`batch_assemble`) or a contiguous window (`batch_slice`); duplicates are
  allowed and preserved, and a canonical single-line dump
  (`batch_dump`) renders the whole batch.
- **Loader** (`xiom.data.batch`): fixed-size batches over an explicit order
  (a permutation of `0..n-1`), with `drop_last` handling for the final
  partial batch (`loader_new`, `loader_from_order`, `loader_next`,
  `loader_has_next`, `loader_num_batches`, `loader_reset`).
- **Sampler** (`xiom.data.order`, `src/order.xi`): a sample order
  (`sampler_sequential`, `sampler_from_order`, `sampler_shuffled`,
  `sampler_weighted` for descending stable weighting) with range-safe
  accessors and permutation validation.
- **Shuffle** (`xiom.data.order`): the Park-Miller MINSTD LCG
  `s = (48271 * s) mod 2147483647`, seed normalized into `[1, 2147483646]`,
  driving Fisher-Yates from the back (`shuffle_order`). The same `(n, seed)`
  always yields the same order; the default seed is 12345.
- **Split** (`xiom.data.order`): basis-point train/validation/test splitting
  (`split_indices` for ascending contiguous splits, `split_shuffled` for a
  deterministic shuffled split), plus copies and a canonical dump.

**Parallel Vec conventions throughout.** A dataset and a batch are records
of parallel `Vec[Int]` fields (`Vec[StructType]` is not used); every push
is mirrored on all sibling vectors, lengths are validated at construction
and guarded at every access, and `loader_next` refuses a dataset whose
`(n, width)` does not match the loader it was built for. There are no views
and no aliasing: constructors copy, accessors return fresh vectors, and the
only mutations are explicit loader cursor updates and label/value writes
through the API's own copies. See `SPEC.md` for the exact rules, validation
order and error catalog.

## Libs inventory

| Lib | Module | Description |
|-----|--------|-------------|
| `dataset` | `xiom.data` | Dataset container, validation, accessors and iterators. |
| `batch` | `xiom.data.batch` | Batch assembly/collation, row copies and canonical dump. |
| `loader` | `xiom.data.batch` | Batched iteration over an explicit order with drop-last. |
| `sampler` | `xiom.data.order` | Sequential, explicit, shuffled and weighted sample orders. |
| `shuffle` | `xiom.data.order` | Deterministic MINSTD LCG + Fisher-Yates shuffling. |
| `split` | `xiom.data.order` | Basis-point train/validation/test splitting. |

## Units and conventions

| Quantity | Unit | Notes |
|---|---|---|
| features, labels, indices | `Int` | no floats anywhere |
| split ratios | basis points (`10000` = 1.0) | truncated toward zero, non-negative |
| shuffle seed | `Int` | normalized into `[1, 2147483646]`; `0` is a valid seed |
| capacity | 1000000 | samples per dataset/order, values per flat buffer |
| weighted sampler | 10000 samples | O(n^2) stable selection, documented cap |

## API

| Function | Returns | Description |
|---|---|---|
| `data_max_samples()` / `data_max_values()` | `Int` | Documented limits (1000000). |
| `dataset_from_flat(width, &xs, &ys)` | `Result[Dataset, Str]` | Validated construction, vectors copied. |
| `dataset_from_labels(&ys)` | `Result[Dataset, Str]` | Label-only dataset (width 0). |
| `dataset_num_samples(&d)` / `dataset_width(&d)` / `dataset_num_values(&d)` | `Int` | Shape accessors. |
| `dataset_get(&d, i, j)` | `Result[Int, Str]` | Feature `j` of sample `i`. |
| `dataset_label(&d, i)` | `Result[Int, Str]` | Label of sample `i`. |
| `dataset_row(&d, i)` | `Result[Vec[Int], Str]` | Row copy (length `width`). |
| `dataset_labels(&d)` / `dataset_values(&d)` | `Vec[Int]` | Independent copies. |
| `dataset_iter(&d)` | `DatasetIter` | Forward index iterator. |
| `dataset_iter_next(&mut it)` | `Int` | Next index, `-1` when exhausted. |
| `dataset_iter_reset(&mut it)` | - | Rewind. |
| `dataset_iter_remaining(&it)` | `Int` | Samples not yet returned. |
| `batch_assemble(&d, &indices)` | `Result[Batch, Str]` | Copy the named rows in order. |
| `batch_slice(&d, start, count)` | `Result[Batch, Str]` | Contiguous window. |
| `batch_size(&b)` / `batch_width(&b)` | `Int` | Batch shape. |
| `batch_get(&b, i, j)` / `batch_label(&b, i)` / `batch_index(&b, i)` | `Result[Int, Str]` | Range-safe element access. |
| `batch_row(&b, i)` | `Result[Vec[Int], Str]` | Row copy. |
| `batch_labels(&b)` / `batch_indices(&b)` | `Vec[Int]` | Copies. |
| `batch_dump(&b)` | `Str` | Canonical single-line rendering. |
| `loader_new(&d, batch_size, drop_last)` | `Result[Loader, Str]` | Identity-order loader. |
| `loader_from_order(&d, &order, batch_size, drop_last)` | `Result[Loader, Str]` | Loader over a validated permutation. |
| `loader_num_batches(&l)` / `loader_batch_size(&l)` / `loader_position(&l)` | `Int` | Loader shape and progress. |
| `loader_has_next(&l)` | `Bool` | Another batch available? |
| `loader_next(&d, &mut l)` | `Result[Batch, Str]` | Assemble the next batch and advance. |
| `loader_reset(&mut l)` | - | Rewind to the first order entry. |
| `sampler_sequential(n)` / `sampler_from_order(n, &order)` / `sampler_shuffled(n, seed)` | `Result[Sampler, Str]` | Order construction. |
| `sampler_weighted(n, &weights)` | `Result[Sampler, Str]` | Descending stable weight order. |
| `sampler_len(&s)` / `sampler_get(&s, k)` / `sampler_is_permutation(&s)` | `Int` / `Int` / `Bool` | Order inspection (`-1` out of range). |
| `sampler_order(&s)` | `Vec[Int]` | Order copy. |
| `shuffle_order(n, seed)` | `Result[Vec[Int], Str]` | Deterministic Fisher-Yates order. |
| `shuffle_seed_default()` / `shuffle_lcg_modulus()` / `shuffle_lcg_multiplier()` | `Int` | 12345 / 2147483647 / 48271. |
| `shuffle_seed_normalize(seed)` / `shuffle_next(state)` / `shuffle_below(state, bound)` | `Int` | LCG primitives (state threaded by return). |
| `split_bps()` | `Int` | 10000. |
| `split_indices(n, train_bps, val_bps)` / `split_shuffled(n, train_bps, val_bps, seed)` | `Result[Split, Str]` | Train/validation/test splits. |
| `split_train_len(&s)` / `split_val_len(&s)` / `split_test_len(&s)` | `Int` | Part sizes. |
| `split_train_at(&s, k)` / `split_val_at(&s, k)` / `split_test_at(&s, k)` | `Int` | Index at position `k`, `-1` out of range. |
| `split_train_indices(&s)` / `split_val_indices(&s)` / `split_test_indices(&s)` | `Vec[Int]` | Part copies. |
| `split_dump(&s)` | `Str` | Canonical single-line rendering. |

The complete error catalog and the pinned shuffle vectors are in `SPEC.md`.

## Usage

```xi
use xiom.io;
use xiom.data; use xiom.data.batch; use xiom.data.order;
use xiom.convert;

fn main() -> Int {
  // 4 samples, 2 features each: rows [1,2] [3,4] [5,6] [7,8], labels 0/1.
  var xs = Vec[Int].new();
  xs.push(1); xs.push(2); xs.push(3); xs.push(4);
  xs.push(5); xs.push(6); xs.push(7); xs.push(8);
  var ys = Vec[Int].new();
  ys.push(0); ys.push(1); ys.push(0); ys.push(1);
  let ds = dataset_from_flat(2, &xs, &ys);
  if !ds.is_ok { return 1; }
  let d = ds.value;

  // Deterministic shuffled order, then two batches of two.
  let sm = sampler_shuffled(4, 7);
  if !sm.is_ok { return 1; }
  let lr = loader_from_order(&d, &sampler_order(&sm.value), 2, 0);
  if !lr.is_ok { return 1; }
  var l = lr.value;
  while loader_has_next(&l) {
    let br = loader_next(&d, &mut l);
    if !br.is_ok { return 1; }
    io.println(batch_dump(&br.value));
  }
  // batch n=2 width=2 indices=[3,2] labels=[1,0] data=[7,8,5,6]
  // batch n=2 width=2 indices=[0,1] labels=[0,1] data=[1,2,3,4]

  // 60/20/20 split of a shuffled index space.
  let sp = split_shuffled(10, 6000, 2000, 12345);
  if sp.is_ok {
    io.println(convert.int_to_string(split_train_len(&sp.value))); // 6
    io.println(split_dump(&sp.value));
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-data -TimeoutSec 60
```

Expected tail: 24 `[PASS]` lines, `xiom.data: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`. Verified on the
pinned compiler 0.62.2 (installed) with the repo stdlib.

## Limitations

- **Integers only.** There is no `Float64` path; callers scale floats to
  fixed point themselves.
- **Copy semantics.** Constructors and accessors copy; there are no views,
  no zero-copy slicing and no iterators that borrow dataset rows.
- **Sampling without replacement.** Samplers are permutations; weighted
  sampling reorders samples, it does not draw with replacement.
- **Weighted sampler cap.** `sampler_weighted` uses an O(n^2) stable
  selection and is capped at 10000 samples.
- **Basis-point ratios.** Splits truncate `n * bps / 10000` toward zero, so
  tiny datasets can yield empty parts; the test vector always takes the
  remainder.
- **Capacity guards.** 1000000 samples per dataset/order and 1000000 flat
  values per dataset.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
