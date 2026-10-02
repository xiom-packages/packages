# xiom.data -- Specification

Status: `incubating` (implemented, conformance-tested 24/24 on compiler
0.62.2, not published).
Package: `xiom.data` (`package.xi`, version `0.1.0`).
Modules / files:

| Module | File | Owns |
|---|---|---|
| `xiom.data` | `src/data.xi` | Dataset container, iterators, limits |
| `xiom.data.batch` | `src/batch.xi` | Batch assembly/collation, Loader |
| `xiom.data.order` | `src/order.xi` | Sampler, shuffle, Split |

Manifest deps: `xiom.std >=0.60.0 <1.0.0`. The library imports only
`xiom.convert` (decimal rendering in `batch_dump` / `split_dump`); the tests
additionally use `xiom.test`, `xiom.io`, `xiom.string` and
`xiom.string.compare`. Tests: `tests/test_conformance.xi` (24 checks).

## 1. Scope

Integer-only dataset utilities for deterministic ML/data pipelines:

- dataset container with validated construction and forward iterators;
- batch assembly from explicit index lists and contiguous windows;
- a batched loader over an explicit sample order with drop-last handling;
- sequential, explicit, shuffled and weighted samplers;
- deterministic MINSTD LCG Fisher-Yates shuffling;
- basis-point train/validation/test splitting, contiguous or shuffled.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no
global state, no threads, no allocation beyond the returned vectors and
copies.

## 2. Non-goals

- No `Float64` (and no `Vec[Float64]` on this toolchain): integers only.
- No file/network I/O, no serialization, no async prefetching, no threads.
- No views or zero-copy slicing: every accessor copies.
- No sampling with replacement, no class balancing, no stratification.
- No `Vec[StructType]`, methods, lambdas or generic callbacks (parallel
  `Vec[Int]` fields instead, per the porting conventions).

## 3. Data model

### 3.1 Dataset (`xiom.data`)

`pub type Dataset = { n: Int; width: Int; xs: Vec[Int]; ys: Vec[Int]; }`

| Field | Meaning |
|---|---|
| `n` | number of samples (`0 <= n <= 1000000`) |
| `width` | features per sample (`>= 0`; 0 means label-only) |
| `xs` | flat row-major feature buffer, length exactly `n * width` (`<= 1000000`) |
| `ys` | label vector, length exactly `n` |

Invariants are established by `dataset_from_flat` and never violated: the
accessors only read, and no function mutates a dataset. Sample `i` occupies
`xs[i*width .. i*width + width]`; label `i` is `ys[i]`.

### 3.2 DatasetIter (`xiom.data`)

`pub type DatasetIter = { pos: Int; n: Int; }`. A forward iterator over
sample indices `0 .. n-1`. `dataset_iter_next` returns `pos` and increments
it, or `-1` when `pos >= n`; `dataset_iter_reset` sets `pos = 0`;
`dataset_iter_remaining` returns `n - pos`.

### 3.3 Batch (`xiom.data.batch`)

`pub type Batch = { n: Int; width: Int; xs: Vec[Int]; ys: Vec[Int]; indices: Vec[Int]; }`

All five parallel quantities have length `n`: `indices[k]` is the source
sample of row `k`, `ys[k]` its label, and `xs[k*width .. k*width+width]` its
features. `batch_assemble` accepts duplicates and preserves order; `n`,
`width`, `xs`, `ys` and `indices` are always pushed in lockstep, so the
parallel vectors cannot drift.

### 3.4 Loader (`xiom.data.batch`)

`pub type Loader = { n: Int; width: Int; order: Vec[Int]; batch_size: Int; drop_last: Int; cursor: Int; }`

`order` is a permutation of `0 .. n-1` copied from the caller, `batch_size`
is positive, `drop_last` is 0 or 1 and `cursor` is the next order position
to consume (`0 <= cursor <= order.len()`). One pass yields
`loader_num_batches(l)` batches: `floor(n / batch_size)` plus one when
`n % batch_size != 0` and `drop_last == 0`. A partial final batch is
returned only when `drop_last == 0`; otherwise the loader reports exhausted
once fewer than `batch_size` entries remain.

### 3.5 Sampler (`xiom.data.order`)

`pub type Sampler = { n: Int; order: Vec[Int]; }` where `order` is a
permutation of `0 .. n-1`. `sampler_get` returns `order[k]` or `-1` out of
range; `sampler_is_permutation` re-validates the order.

### 3.6 Split (`xiom.data.order`)

`pub type Split = { train: Vec[Int]; val: Vec[Int]; test: Vec[Int]; }`.
`split_indices` produces ascending, disjoint vectors whose union is exactly
`0 .. n-1`; `split_shuffled` produces a partition of a shuffled order.

## 4. Limits and fixed point

| Limit | Value | Applies to |
|---|---|---|
| `data_max_samples()` | 1000000 | dataset `n`, sampler/shuffle/split `n`, order length |
| `data_max_values()` | 1000000 | dataset `xs` length (`n * width`) |
| weighted sampler | 10000 | `sampler_weighted` `n` (O(n^2) selection) |
| `split_bps()` | 10000 | basis points; 10000 = 1.0 |

All arithmetic is `Int` (64-bit). The shape product `ys.len() * width` is
guarded with a division before multiplying (`ys.len() > INT_MAX / width`
fails with `flat length overflows`). Split sizes multiply `n * bps`
(`n <= 1000000`, `bps <= 10000`, so `<= 10^10`, far below `INT_MAX`) and
divide by 10000 with truncation toward zero; all operands are
non-negative, so the truncating `Int` division is the documented floor.
The LCG step `48271 * s` (`s < 2^31`) is at most `~1.04 * 10^14`, safe in
`Int`.

## 5. Shuffle algorithm (pinned)

The generator is the Park-Miller MINSTD linear congruential generator with
the classic constants:

```
M = 2147483647  (2^31 - 1, prime)      -- shuffle_lcg_modulus()
A = 48271                              -- shuffle_lcg_multiplier()
normalize(seed):  s = seed % 2147483646;  if s <= 0 { s = s + 2147483646 }
next(s):          (A * s) mod M
```

`normalize` maps any `Int` seed into the valid state range
`[1, 2147483646]` (state 0 and negative states are repaired; `next` can
never return 0 because M is prime and does not divide `A * s` for
`1 <= s < M`). The default seed is **12345** (`shuffle_seed_default()`);
`shuffle_seed_normalize` accepts `0` and negative seeds deterministically
(no time or entropy anywhere).

`shuffle_order(n, seed)` is Fisher-Yates from the back:

```
order = [0, 1, .., n-1];  state = normalize(seed)
for i = n-1 down to 1:
  state = next(state)
  j = state % (i + 1)
  swap order[i], order[j]
```

The bounded draw is the modulo `state % (i+1)`; the bias is at most
`(i+1)/M < 2^-31` per draw, which is documented and accepted (the order is
deterministic, reproducible and platform-independent). Scalar RNG state is
threaded through return values (`shuffle_next`, `shuffle_below`) because
`&mut Int` parameters are not reliable on compiler 0.62.2.

### 5.1 Pinned vectors (also asserted by the tests)

| Call | Result |
|---|---|
| `shuffle_seed_normalize(0)` | 2147483646 |
| `shuffle_seed_normalize(-1)` | 2147483645 |
| `shuffle_seed_normalize(2147483647)` | 1 |
| `shuffle_seed_normalize(1)` | 1 |
| `shuffle_next(1)` | 48271 |
| `shuffle_next(48271)` | 182605794 |
| `shuffle_below(48271, 4)` | 3 |
| `shuffle_below(48271, 0)` | 0 |
| `shuffle_order(8, 12345)` | 6,0,4,2,3,5,1,7 |
| `shuffle_order(5, 42)` | 0,1,4,3,2 |
| `shuffle_order(10, 12345)` | 8,7,1,2,3,6,0,9,4,5 |
| `shuffle_order(8, 12346)` | 5,2,7,0,3,4,1,6 |
| `shuffle_order(4, 7)` | 3,2,0,1 |
| `shuffle_order(1, 7)` | 0 |
| `shuffle_order(0, 7)` | (empty) |

## 6. Validation order and error catalog

`dataset_from_flat(width, xs, ys)` checks, in order: width negative; sample
count over the cap; the `n * width` multiplication overflow; `xs.len()` not
equal to the expected count; flat value count over the cap. It then copies
both vectors. `dataset_from_labels(ys)` is `dataset_from_flat(0, [], ys)`.

All errors share the `data: ` prefix. Messages and their raise sites:

| Message | Raised by |
|---|---|
| `data: width must be non-negative` | `dataset_from_flat` |
| `data: sample count exceeds the limit` | `dataset_from_flat` (n > cap) |
| `data: flat length overflows` | `dataset_from_flat` (`n * width` guard) |
| `data: flat length does not match sample count` | `dataset_from_flat` |
| `data: value count exceeds the limit` | `dataset_from_flat` |
| `data: sample index out of bounds` | `dataset_get`, `dataset_label`, `dataset_row`, `batch_get`, `batch_label`, `batch_index`, `batch_row` |
| `data: feature index out of bounds` | `dataset_get`, `batch_get` |
| `data: batch index out of bounds` | `batch_assemble` |
| `data: batch slice out of bounds` | `batch_slice` |
| `data: batch size must be positive` | `loader_from_order` (and `loader_new` through it) |
| `data: drop_last must be 0 or 1` | `loader_from_order` |
| `data: order length must equal sample count` | `loader_from_order`, `sampler_from_order` |
| `data: order must be a permutation of 0..n-1` | `loader_from_order`, `sampler_from_order` |
| `data: dataset does not match loader` | `loader_next` (n or width differs) |
| `data: loader is exhausted` | `loader_next` (pass complete / dropped tail) |
| `data: sample count must be non-negative` | `sampler_sequential`, `sampler_from_order`, `sampler_weighted`, `shuffle_order` |
| `data: sample count exceeds the limit` | `sampler_sequential`, `sampler_from_order`, `shuffle_order` |
| `data: weighted sampler sample count exceeds the limit` | `sampler_weighted` (n > 10000) |
| `data: weight count must equal sample count` | `sampler_weighted` |
| `data: weight must be non-negative` | `sampler_weighted` |
| `data: split sample count must be non-negative` | `split_indices`, `split_shuffled` |
| `data: split sample count exceeds the limit` | `split_indices`, `split_shuffled` |
| `data: split ratios must be non-negative` | `split_indices`, `split_shuffled` |
| `data: split ratios must sum to at most 10000` | `split_indices`, `split_shuffled` |

Validation order inside each call is left to right; every error fails
closed: an `Err` never returns a partially built batch, loader, sampler or
split, and `batch_assemble` validates each index before copying its row.

## 7. Parallel Vec conventions (drift prevention)

1. `Vec[StructType]` is not used anywhere; records hold parallel
   `Vec[Int]` fields (`Dataset`, `Batch`, `Loader`, `Sampler`, `Split`).
2. Every push on one parallel vector is mirrored on all siblings in the
   same loop iteration (`batch_assemble` pushes `xs` row values and exactly
   one `ys` and one `indices` entry per index).
3. Lengths are validated at construction (`n * width == xs.len()`,
   `ys.len() == n`, order length `== n`) and guarded at every indexed
   access; accessors are range-safe (`-1` for `sampler_get` /
   `split_*_at`, `Err` elsewhere).
4. `loader_next` refuses a dataset whose `(n, width)` pair does not match
   the loader it was built for, so a loader can never assemble rows from a
   different dataset.
5. `batch_assemble` checks every index (including negative values) before
   it is dereferenced, so a bad index can never reach `d.xs` or `d.ys`.
6. The shared permutation test `_data_is_permutation` / `_bat_is_permutation`
   / `_ord_is_permutation` validates an order by marking each value once
   (`O(n)` time and space), rejecting out-of-range values and duplicates.
7. Copy semantics: every constructor and accessor copies; mutating a
   returned vector (values, labels, rows, orders, split parts) can never
   change a dataset, batch, sampler or split.

## 8. API signatures

```xi
// xiom.data (src/data.xi)
pub fn data_max_samples() -> Int
pub fn data_max_values() -> Int
pub fn dataset_from_flat(width: Int, xs: &Vec[Int], ys: &Vec[Int]) -> Result[Dataset, Str]
pub fn dataset_from_labels(ys: &Vec[Int]) -> Result[Dataset, Str]
pub fn dataset_num_samples(d: &Dataset) -> Int
pub fn dataset_width(d: &Dataset) -> Int
pub fn dataset_num_values(d: &Dataset) -> Int
pub fn dataset_get(d: &Dataset, i: Int, j: Int) -> Result[Int, Str]
pub fn dataset_label(d: &Dataset, i: Int) -> Result[Int, Str]
pub fn dataset_row(d: &Dataset, i: Int) -> Result[Vec[Int], Str]
pub fn dataset_labels(d: &Dataset) -> Vec[Int]
pub fn dataset_values(d: &Dataset) -> Vec[Int]
pub fn dataset_iter(d: &Dataset) -> DatasetIter
pub fn dataset_iter_next(it: &mut DatasetIter) -> Int
pub fn dataset_iter_reset(it: &mut DatasetIter)
pub fn dataset_iter_remaining(it: &DatasetIter) -> Int

// xiom.data.batch (src/batch.xi)
pub fn batch_assemble(d: &Dataset, indices: &Vec[Int]) -> Result[Batch, Str]
pub fn batch_slice(d: &Dataset, start: Int, count: Int) -> Result[Batch, Str]
pub fn batch_size(b: &Batch) -> Int
pub fn batch_width(b: &Batch) -> Int
pub fn batch_get(b: &Batch, i: Int, j: Int) -> Result[Int, Str]
pub fn batch_label(b: &Batch, i: Int) -> Result[Int, Str]
pub fn batch_index(b: &Batch, i: Int) -> Result[Int, Str]
pub fn batch_row(b: &Batch, i: Int) -> Result[Vec[Int], Str]
pub fn batch_labels(b: &Batch) -> Vec[Int]
pub fn batch_indices(b: &Batch) -> Vec[Int]
pub fn batch_dump(b: &Batch) -> Str
pub fn loader_new(d: &Dataset, batch_size: Int, drop_last: Int) -> Result[Loader, Str]
pub fn loader_from_order(d: &Dataset, order: &Vec[Int], batch_size: Int, drop_last: Int) -> Result[Loader, Str]
pub fn loader_batch_size(l: &Loader) -> Int
pub fn loader_num_batches(l: &Loader) -> Int
pub fn loader_position(l: &Loader) -> Int
pub fn loader_has_next(l: &Loader) -> Bool
pub fn loader_next(d: &Dataset, l: &mut Loader) -> Result[Batch, Str]
pub fn loader_reset(l: &mut Loader)

// xiom.data.order (src/order.xi)
pub fn sampler_sequential(n: Int) -> Result[Sampler, Str]
pub fn sampler_from_order(n: Int, order: &Vec[Int]) -> Result[Sampler, Str]
pub fn sampler_shuffled(n: Int, seed: Int) -> Result[Sampler, Str]
pub fn sampler_weighted(n: Int, weights: &Vec[Int]) -> Result[Sampler, Str]
pub fn sampler_len(s: &Sampler) -> Int
pub fn sampler_get(s: &Sampler, k: Int) -> Int
pub fn sampler_order(s: &Sampler) -> Vec[Int]
pub fn sampler_is_permutation(s: &Sampler) -> Bool
pub fn shuffle_seed_default() -> Int
pub fn shuffle_lcg_modulus() -> Int
pub fn shuffle_lcg_multiplier() -> Int
pub fn shuffle_seed_normalize(seed: Int) -> Int
pub fn shuffle_next(state: Int) -> Int
pub fn shuffle_below(state: Int, bound: Int) -> Int
pub fn shuffle_order(n: Int, seed: Int) -> Result[Vec[Int], Str]
pub fn split_bps() -> Int
pub fn split_indices(n: Int, train_bps: Int, val_bps: Int) -> Result[Split, Str]
pub fn split_shuffled(n: Int, train_bps: Int, val_bps: Int, seed: Int) -> Result[Split, Str]
pub fn split_train_len(s: &Split) -> Int
pub fn split_val_len(s: &Split) -> Int
pub fn split_test_len(s: &Split) -> Int
pub fn split_train_at(s: &Split, k: Int) -> Int
pub fn split_val_at(s: &Split, k: Int) -> Int
pub fn split_test_at(s: &Split, k: Int) -> Int
pub fn split_train_indices(s: &Split) -> Vec[Int]
pub fn split_val_indices(s: &Split) -> Vec[Int]
pub fn split_test_indices(s: &Split) -> Vec[Int]
pub fn split_dump(s: &Split) -> Str
```

Complexity: dataset construction and copies `O(n * width)`;
`dataset_get` / `dataset_label` / batch scalar accessors `O(1)`;
`batch_assemble` `O(k * width)` for `k` indices; `batch_slice`
`O(count * width)`; loader construction `O(n)` and `loader_next`
`O(batch_size * width)`; samplers `O(n)` (`sampler_weighted` `O(n^2)`);
`shuffle_order` `O(n)`; split functions `O(n)`; dumps `O(total values)`
plus string assembly.

## 9. Canonical dumps

`batch_dump(b)` returns one line, no trailing newline:

```
batch n=2 width=2 indices=[3,1] labels=[1,1] data=[7,8,3,4]
```

`split_dump(s)` returns one line, no trailing newline:

```
split train=[0,1,2,3,4,5] val=[6,7] test=[8,9]
```

Empty vectors render as `[]`.

## 10. Test plan

`tests/test_conformance.xi` (module `data_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` comparisons go through
`string.compare.str_compare` (BUG 17).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | dataset shape | n/width/num_values, get/label/row, copies |
| t2 | dataset errors | width, length mismatch, product overflow, sample/value caps |
| t3 | dataset range errors | get/label/row bounds; label-only dataset |
| t4 | iterator | forward order, remaining, reset, exhaustion, empty |
| t5 | copy semantics | constructor, values, labels and rows independent |
| t6 | batch assembly | order, index/label/feature mapping, canonical dump |
| t7 | batch duplicates/errors | duplicates preserved; all range errors |
| t8 | batch window | contents, empty window, slice bounds |
| t9 | loader identity | batch count, order, progress, exhaustion |
| t10 | loader drop_last | dropped vs returned partial tail |
| t11 | loader edges | empty dataset; batch size > n |
| t12 | loader order | custom order, permutation/size validation |
| t13 | loader reset/mismatch | replay; foreign dataset refused |
| t14 | sampler basics | sequential/explicit orders, accessors, permutation |
| t15 | sampler/shuffle errors | size, length, duplicate/out-of-range orders |
| t16 | weighted sampler | descending stable order; weight errors |
| t17 | sampler_shuffled | same seed reproduces, different seed diverges |
| t18 | pinned shuffle vectors | n = 0, 1, 5, 8, 10 seeds 42/12345 |
| t19 | LCG primitives | normalization, steps, bounded draw |
| t20 | split_indices | contiguous partition, accessors, dump |
| t21 | split edges | pure splits, truncation, n = 0 |
| t22 | split errors | range, capacity, ratio validation |
| t23 | split_shuffled | partition of the shuffle; determinism; union |
| t24 | integration | loader over a shuffled order covers each sample once |

## 11. Compiler / stdlib notes

- v0.62.2 traps handled: typed locals on every `Vec[Int]` read; no
  `&struct.field` passed to a reference parameter; no `&mut Vec` and no
  `&mut Int` parameters (`&mut DatasetIter` / `&mut Loader` structs only,
  with explicit `&mut` at every call site); Ok/Err construction only in
  leaf helpers; no `Vec[Str]`, no `Vec[StructType]`, no generics, no
  lambdas, no indexed `Vec[fn]` dispatch; every division acts on
  non-negative operands; loops are bounded by validated lengths.
- Mixed brackets: all four `.xi` files were grepped clean for `Vec<` /
  `Result<` after the final edit.
- Stdlib reuse: only `xiom.convert.int_to_string` is needed (dumps). The
  INTEGER shuffle layer is implemented in-package on purpose: `xiom.rand`
  is `Float64`-based for its public surface and must not be the source of
  a documented, pinned deterministic order. No `Vec[Float64]` is used.
- Multi-module packaging: `xiom.data` core plus the `xiom.data.batch` and
  `xiom.data.order` companions (three files, each under 600 lines) resolve
  through `src/<last-segment>.xi`; the tests import all three modules.

## 12. Known limitations

- Integer-only; there is no floating-point path.
- Copy semantics: no views, no zero-copy slicing, no borrowed row
  iteration.
- Samplers are permutations (without replacement); weighted sampling
  reorders, it does not draw with replacement.
- `sampler_weighted` is O(n^2) and capped at 10000 samples.
- Split sizes truncate toward zero, so small datasets can produce empty
  parts; the test vector always absorbs the remainder.
- Modulo-based bounded draws carry a documented bias below `2^-31`.
