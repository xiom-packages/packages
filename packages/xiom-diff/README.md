# xiom.diff

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** line-oriented diffing over `Vec[Str]` line slices: element-wise
> equality, LCS length, full edit scripts, insertion/deletion counts, and
> unified-style hunks.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert.int`). Pure XIOM, no FFI.

## What it is

`xiom.diff` implements the classic LCS dynamic program over two line slices.
The `(n+1) x (m+1)` DP table is stored flat in a `Vec[Int]` (no
`Vec[Vec[Int]]`, no `Vec[StructType]`); `diff_lines` and `diff_unified`
backtrack that table to emit a shortest edit script, and `diff_unified`
groups changes into GNU-style `@@` hunks with a configurable amount of
context. `diff_text` is the convenience wrapper that splits two `Str`
payloads on `\n` and diffs the resulting lines.

All comparisons of `Str` values read from `Vec` elements go through
`xiom.string.compare.str_compare` (the compiler lowers `==` on such values to
a pointer comparison, BUG 17).

## API

| Function | Returns | Description |
|---|---|---|
| `diff_equal(a, b)` | `Bool` | Element-wise line equality; length mismatch is false. |
| `diff_lcs_len(a, b)` | `Int` | Longest common subsequence length (`0` when either side is empty). |
| `diff_lines(a, b)` | `Vec[Str]` | Full edit script; every line is prefixed `"  "`, `"- "` or `"+ "`. |
| `diff_insertions(a, b)` | `Int` | `b.len() - diff_lcs_len(a, b)`. |
| `diff_deletions(a, b)` | `Int` | `a.len() - diff_lcs_len(a, b)`. |
| `diff_unified(a, b, context)` | `Str` | Unified-style `@@` hunks; `""` when `a` and `b` are equal. |
| `diff_text(a, b)` | `Vec[Str]` | Splits two texts on `\n`, then `diff_lines`. |

## Usage

```xi
use xiom.diff;
use xiom.string;
use xiom.io;

// Full edit script, one prefixed line per operation.
let script = diff_text("alpha\nbeta\ngamma", "alpha\ndelta\ngamma");
//   alpha
// - beta
// + delta
//   gamma

// Unified hunks with one line of context around the change.
let a = str_split("alpha\nbeta\ngamma", "\n");
let b = str_split("alpha\ndelta\ngamma", "\n");
io.println(diff_unified(&a, &b, 1));
// @@ -1,3 +1,3 @@
//  alpha
// -beta
// +delta
//  gamma
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.diff
```

Expected: the namespaced module passes the section-4 namespace rule, 16
`[PASS]` lines, and a final `port: PASS (passed=16 failed=0 program_exit=0
exit=0)`.

## Limitations

- O(n*m) time and memory for the DP table: a file pair with thousands of
  lines each allocates a large flat `Vec[Int]`. There is no Myers/histogram
  fallback and no memory cap.
- Line-oriented only: lines are compared as whole byte strings; there is no
  intra-line (word/character) refinement.
- No rename detection, no binary detection, no file-system integration; the
  package diffs in-memory line slices only.
- Unified output is GNU-style but not byte-identical to `diff -u` for every
  input (see SPEC.md for the exact contract).
- Not thread-safe; no async variants.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
