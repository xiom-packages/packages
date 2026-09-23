# xiom.property

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** deterministic property-based testing: seeds, generators, runners
> and shrinking for Int and Str properties.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `Str::from_utf8`). Tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`.

## Scope

`xiom.property` runs a predicate over many generated inputs and reports the
first counterexample, then shrinks it toward zero for a minimal failing input.
Everything is deterministic: a seed plus a generation rule always produce the
same value, so any failure is replayable from the recorded `first_seed`. There
is no clock, environment or OS randomness anywhere in the module.

| Type | Fields | Meaning |
|---|---|---|
| `Rng` | `state: Int` | Generator state; always in `[1, 2^31 - 1]`. |
| `PropReport` | `passed, failed, first_seed, first_value: Int` | Run outcome; see below. |

## API

| Function | Returns | Description |
|---|---|---|
| `prop_rng_new(seed)` | `Rng` | Fresh generator; any Int seed (sign included). |
| `prop_rng_next(r)` | `Int` | Next draw in `[0, 2^31 - 1]`; advances `r`. |
| `prop_rng_bool(r)` | `Bool` | One balanced bit from the mixed stream. |
| `prop_rng_range(r, lo, hi)` | `Int` | Uniform draw in inclusive `[lo, hi]`; `hi < lo` returns `lo` and consumes nothing. |
| `prop_rng_string(r, len, alphabet)` | `Str` | Up to `len` characters drawn from `alphabet`; empty alphabet or `len <= 0` yields `""`. |
| `prop_seeds(count, base)` | `Vec[Int]` | `count` deterministic, spread-out non-negative seeds derived from `base`. |
| `prop_run_int(f, seeds)` | `PropReport` | Runs `f` on draws in `[-1000, 1000]`; stops at the first failure. |
| `prop_run_range(f, seeds, lo, hi)` | `PropReport` | Same, with explicit inclusive bounds. |
| `prop_run_str(f, seeds, max_len, alphabet)` | `PropReport` | Same for Str inputs; `first_value` records the counterexample's **byte length**. |
| `prop_report_ok(r)` | `Bool` | True when no seed failed (`failed == 0`). |
| `prop_shrink_int(value, f)` | `Int` | Halves a failing input toward zero and returns the last chain value that still fails. |

Runners stop at the first failure; `passed` counts the seeds executed before
the stop. On a green run `failed == 0` and `first_seed == first_value == 0`.
On a red run `failed == 1`, `first_seed` is the failing seed and `first_value`
is the failing draw (for `prop_run_str`: the failing string's byte length --
`PropReport` has no Str channel; rebuild the string with
`prop_rng_new(first_seed)` + `prop_rng_string`).

## Usage

```xi
use xiom.property;
use xiom.io; use xiom.core;

// Callbacks must be NAMED top-level functions: the compiler's
// function-pointer codegen rejects inline lambdas.
fn below_100(x: &Int) -> Bool { return *x < 100; }

fn main() -> Int {
  let seeds = prop_seeds(64, 20260923);
  let rep = prop_run_int(below_100, &seeds);
  if prop_report_ok(&rep) {
    io.println("property held over 64 seeds");
  } else {
    let minimal = prop_shrink_int(rep.first_value, below_100);
    io.println("counterexample shrank to: " + core.to_string(minimal));
    io.println("replay seed: " + core.to_string(rep.first_seed));
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.property
```

Expected tail: 26 `[PASS]` lines, `xiom.property: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No integrated test-framework hooks.** The module exposes runners; wiring
  them into a suite (or `xiom.test`) is the caller's job. There is no
  `#[property]`-style attribute and no auto-discovery.
- **Int and Str only.** No Float64, Bool or collection generators (the
  compiler rejects `Vec[Float64]`, and generic callbacks are not supported).
- **Deterministic, not cryptographic.** The 31-bit xorshift-style mixer is
  meant for reproducible tests, not for secrets or statistical simulation.
  Seeds are not pairwise-distinct for arbitrary inputs (the suite checks a
  representative sample only).
- **String length.** `prop_rng_string` draws a character count in `[0, len]`
  (so the result is at most `len` characters). `alphabet` must be valid UTF-8;
  malformed input is copied conservatively, never validated.
- **Range precondition.** `hi - lo + 1` must fit in an `Int`; overflow is not
  checked.
- **Shrinking is a halving chain.** No list/vector shrinking, no integrated
  shrinking, no re-generation; `prop_shrink_int` only reasons about the
  `value`, `value/2`, `value/4`, ... chain of the same predicate.
- **Str counterexamples.** `PropReport` carries Ints only, so a failing
  `prop_run_str` records the counterexample's byte length, not its content.

See `SPEC.md` for the pinned PRNG recipe, seed derivation, shrink algorithm
and the full test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
