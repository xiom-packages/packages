# xiom.diff -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.diff` (`src/diff.xi`). Manifest: `package.xi` (name `xiom.diff`,
version `0.1.0`). Depends on `xiom.std` (`xiom.string`,
`xiom.string.compare`, `xiom.convert.int`).

## Scope

Line-oriented diffing between two line slices (`&Vec[Str]`):

- element-wise line equality (`diff_equal`);
- longest-common-subsequence length via an O(n*m) dynamic program
  (`diff_lcs_len`);
- a full shortest edit script with keep/delete/insert prefixes
  (`diff_lines`);
- insertion and deletion counts (`diff_insertions`, `diff_deletions`);
- unified-style hunks with a configurable context (`diff_unified`);
- a `\n`-splitting convenience wrapper over two texts (`diff_text`).

## Non-goals

- No FFI and no external `diff` binary; everything is pure XIOM.
- No intra-line refinement: lines are compared as whole byte strings (no
  word-level or character-level diff).
- No Myers / histogram / patience algorithms; only the LCS DP.
- No rename detection, no binary-file detection, no file-system access,
  no patch application.
- No generics in XIOM v0.61.x: the API is line slices (`Vec[Str]`); there is
  no generic sequence diff.
- No streaming or constant-memory mode; the full DP table is materialized.
- Not thread-safe and not `async`.

## Algorithms

### LCS table (`_lcs_table`, internal)

`dp[i*(m+1)+j]` is the LCS length of `a[0..i)` and `b[0..j)`, stored flat in
a single `Vec[Int]` (no `Vec[Vec[Int]]`, no `Vec[StructType]`):

```
dp[0][*] = dp[*][0] = 0
dp[i][j] = dp[i-1][j-1] + 1                     if a[i-1] == b[j-1]
dp[i][j] = max(dp[i-1][j], dp[i][j-1])          otherwise
```

Line equality uses `xiom.string.compare.str_compare(a, b) == 0`; `==` on
`Str` values read from `Vec` elements is never used (BUG 17: it lowers to a
pointer comparison).

### Edit script (`_op_kinds`, internal)

The table is backtracked from `(n, m)` to `(0, 0)`; each step emits
`0 = keep`, `1 = delete`, `2 = insert` into a reverse buffer which is then
reversed. On a mismatch, the insert branch is taken when
`dp[i][j-1] >= dp[i-1][j]` (and always when `i == 0`); otherwise the delete
branch. Ties therefore produce deletions before insertions for a replaced
line (GNU `diff` convention), e.g. `a = [A,B,C]`, `b = [A,X,C]` yields
`- B`, `+ X`.

Every array access is guarded by nested `if`s instead of relying on `&&` /
`||` short-circuiting (the compiler's evaluation order for boolean operators
is not part of the language contract), so no out-of-range index is ever
formed.

### Hunks (`diff_unified`)

1. Collect maximal runs of consecutive non-keep ops ("changes").
2. Extend each run by `context` ops on both sides (clamped);
   `context < 0` clamps to 0.
3. Merge two runs into one hunk when the number of kept ops between them is
   `<= 2*context`; with `context = 0` only directly adjacent changes merge.
4. Emit `@@ -oldStart,oldCount +newStart,newCount @@` followed by the
   prefixed lines, each terminated with `\n`.

`old_start`/`new_start` are 1-based line numbers. When a side's count is 0
(pure insertion or deletion), the start on that side is the number of lines
of that side before the insertion point, so an insertion at the very
beginning is `-0,0` (GNU unified diff convention).

## Output format

### `diff_lines`

One `Str` per operation, prefix `+` content:

| Prefix | Meaning | Content source |
|---|---|---|
| `"  "` | unchanged line | `a[i]` (also `b[j]`) |
| `"- "` | deleted line | `a[i]` |
| `"+ "` | inserted line | `b[j]` |

Example: `a = ["alpha","beta","gamma"]`, `b = ["alpha","delta","gamma"]`:

```
  alpha
- beta
+ delta
  gamma
```

### `diff_unified`

Hunk header `@@ -oldStart,oldCount +newStart,newCount @@`, then lines with a
one-character prefix (`" "`, `"-"`, `"+"`) and a trailing `"\n"` on every
emitted line (header included). Identical inputs return `""`.

Example: `a = ["A","B","C"]`, `b = ["A","X","C"]`, `context = 1`:

```
@@ -1,3 +1,3 @@
 A
-B
+X
 C
```

Example: `a = []`, `b = ["x"]`, `context = 0`:

```
@@ -0,0 +1,1 @@
+x
```

Example: `a = ["x"]`, `b = []`, `context = 0`:

```
@@ -1,1 +0,0 @@
-x
```

Example: two distant changes with `context = 1` produce two hunks:

```
@@ -1,3 +1,3 @@
 A
-B
+X
 C
@@ -6,3 +6,3 @@
 F
-G
+Y
 H
```

### `diff_text`

Splits on `"\n"` (byte 10): a final newline terminates the last line without
creating an extra empty line, and the empty text is zero lines. The two line
vectors are then passed to `diff_lines`.

| Text | Lines |
|---|---|
| `""` | `[]` |
| `"\n"` | `[""]` |
| `"a"` | `["a"]` |
| `"a\n"` | `["a"]` |
| `"a\nb"` | `["a","b"]` |
| `"a\n\nb"` | `["a","","b"]` |

## API signatures

All functions are free functions in module `xiom.diff`:

```xi
pub fn diff_equal(a: &Vec[Str], b: &Vec[Str]) -> Bool
pub fn diff_lcs_len(a: &Vec[Str], b: &Vec[Str]) -> Int
pub fn diff_lines(a: &Vec[Str], b: &Vec[Str]) -> Vec[Str]
pub fn diff_insertions(a: &Vec[Str], b: &Vec[Str]) -> Int
pub fn diff_deletions(a: &Vec[Str], b: &Vec[Str]) -> Int
pub fn diff_unified(a: &Vec[Str], b: &Vec[Str], context: Int) -> Str
pub fn diff_text(a: Str, b: Str) -> Vec[Str]
```

No function has an error path: every input is accepted, negative context
clamps to 0, and counts are always `>= 0`.

## Complexity

| Function | Time | Memory |
|---|---|---|
| `diff_equal` | O(min(n, m)) | O(1) |
| `diff_lcs_len` | O(n*m) | O(n*m) flat `Vec[Int]` |
| `diff_lines` | O(n*m) | O(n*m) + O(n+m) output |
| `diff_insertions` / `diff_deletions` | O(n*m) | O(n*m) |
| `diff_unified` | O(n*m) | O(n*m) + O(payload²) string building |
| `diff_text` | O(n*m) | O(n*m) + O(n+m) |

`n`/`m` are the line counts. The DP table is the dominant term; there is no
two-row optimization because the edit script needs the full table.

## Test plan

`tests/test_conformance.xi` (`module diff_tests`, 16 named checks, lru-style
`main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and returns
the failure count):

1. `diff_equal` true for identical vectors and empty vectors;
2. `diff_equal` false on element or length mismatch;
3. one insertion: script, counts and LCS length;
4. one deletion: script, counts and LCS length;
5. replacement emits deletion before insertion;
6. LCS known values: 4 for `ABCBDAB`/`BDCABA`, plus 1, 0 and empty;
7. insertion/deletion counts on a mixed edit;
8. every script line carries exactly one of the three prefixes;
9. unified hunk has `@@` header with correct `1,3` counts;
10. identical inputs produce an empty unified diff;
11. `context = 1` keeps exactly one unchanged line per side;
12. `context = 0` narrows hunks and nearby changes merge into one hunk;
13. empty vs non-empty in both directions with `0,0` hunk starts;
14. `diff_text` splits on newlines without a trailing empty line;
15. single element vs empty deletes exactly that line;
16. two distant changes yield two separate hunks.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.diff
```

Last verified: compiler 0.61.3, `port: PASS (passed=16 failed=0
program_exit=0 exit=0)`.

## Known limitations

- O(n*m) time and memory: large inputs allocate one flat `Vec[Int]` of
  `(n+1)*(m+1)` cells; there is no cap and no fallback algorithm.
- Line-oriented only: no word/character refinement inside a changed line.
- The unified format follows GNU conventions for hunk ranges and prefixes
  but is not guaranteed byte-identical to `diff -u` for ambiguous scripts
  (multiple LCS-optimal scripts exist; the backtrack is deterministic but the
  tie rule is delete-before-insert per changed group).
- Output hunk line endings are always `\n` and a trailing `\n` is always
  emitted; input lines are never modified.
- `diff_unified` builds the result by repeated concatenation, so very large
  payloads cost more than the O(n*m) DP itself.
- `diff_text` only recognizes `\n` (LF); classic-Mac `\r` and Windows `\r\n`
  are not split or normalized (a `\r\n` file yields lines ending in `\r`).

## Compiler / stdlib notes for v0.61.3

- `str_compare` lives in `xiom.string.compare`, not `xiom.string`
  (`use xiom.string;` does not export it); the module imports both.
- `int_to_string` is taken from `xiom.convert.int` (the local exact
  implementation), not from `xiom.convert`'s `to_string` delegate.
- Vec-sourced `Str` elements are compared only via `str_compare` (BUG 17:
  `==` lowers to a pointer compare).
- **Call-result `Vec[Int]` element reads are mis-typed by inference (crash).**
  When a function takes `&Vec[Str]` parameters and returns a `Vec[Int]`
  (`_lcs_table`, `_op_kinds`), an untyped element read of that result in the
  caller (`let kind = kinds[k]; if kind == 0 { ... }`) is lowered as if the
  element were a `Str`: the IR does `inttoptr <element> to i8*`, then
  `strcmp` against the address `1` for `kind == 1`, which dereferences
  address 0x1 and aborts with an access violation (exit `-1073741819`). The
  same mis-typing applied to `diff_lcs_len`'s bare `return dp[...]` lowers to
  `inttoptr`+`ptrtoint`, which happens to round-trip the value but is still
  wrong IR. **Workaround:** pin every read with an explicit type,
  `let kind: Int = kinds[k];` (and `let lcs: Int = dp[...]`), which restores
  a plain i64 element load. Minimal reproduction during porting: a callee
  `f(a: &Vec[Str], b: &Vec[Str]) -> Vec[Int]` whose caller reads `v[i]` into
  an untyped `let` and compares it; identical code with a typed `let`, or
  with a callee that has no `Vec[Str]` parameter, is green.
- **Nested-`elif` comparison of two flat-table index reads** (`elif dp[x] >=
  dp[y]` inside an `if kind == -1` sentinel block) mis-lowers the same way
  (the Int operands become pointers that are then byte-loaded). The
  backtrack decision is therefore isolated in `_choose_kind` with flat `if`s
  and early returns, which emits correct IR.
- Boolean operators are assumed non-short-circuiting: guards are written as
  nested `if`s so out-of-range `Vec` indexes are never evaluated.
- No `Vec[Vec[Int]]` and no `Vec[StructType]`: the DP table and the op/line
  side tables are flat `Vec[Int]`; line payloads stay in the caller's
  `Vec[Str]`.
- No inline lambdas, no `self` methods, no `mut` match pattern bindings; the
  module is written entirely with free functions and `while` loops, matching
  xiom.lru idioms.
