# xiom.spell -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.spell` (`src/spell.xi`). Manifest: `package.xi` (name
`xiom.spell`, version `0.1.0`). Depends on `xiom.std` (`xiom.string`,
`xiom.string.compare`).

## Scope

Dictionary-based spell checking over a caller-supplied word list
(`&Vec[Str]`):

- plain byte-wise Levenshtein distance (`spell_distance`);
- budgeted distance with an early-out contract (`spell_distance_bounded`);
- exact dictionary membership (`spell_contains`, `spell_is_correct`);
- ranked suggestions bounded by distance and result count (`spell_suggest`);
- unknown-word scan over free text (`spell_unknown_words`).

## Non-goals

- No FFI, no platform dictionaries, no file/network I/O: everything is pure
  XIOM and in-memory.
- No bundled word list; the dictionary is always an argument.
- No case folding, no stemming, no affix rules, no phonetic matching.
- No BK-tree / n-gram index / trie acceleration: suggestions score every
  dictionary entry.
- No Unicode character awareness: distance and scanning operate on the UTF-8
  bytes of `Str`.
- No generics in XIOM v0.61.x: the dictionary type is concrete `Vec[Str]`.
- Not thread-safe and not `async`.

## Distance definition

`spell_distance(a, b)` is the classic Levenshtein distance with unit costs:
one insertion, deletion or substitution costs 1; a match costs 0. It is
computed over the UTF-8 **bytes** of `a` and `b`, so a multi-byte character
counts as its encoded byte length (`spell_distance("café", "cafe") == 2`).

Flat DP table, row-major width `m+1` in a single `Vec[Int]` (no
`Vec[Vec[Int]]`, no `Vec[StructType]`):

```
dp[0][j] = j;  dp[i][0] = i
dp[i][j] = dp[i-1][j-1]                       if a[i-1] == b[j-1]
dp[i][j] = 1 + min(dp[i-1][j],                otherwise
                   dp[i][j-1],
                   dp[i-1][j-1])
```

`a[i-1] == b[j-1]` is byte equality (`UInt8`), never `Str ==` on Vec
elements (BUG 17: `Str ==` on such values lowers to a pointer comparison).

### Budgeted variant

`spell_distance_bounded(a, b, max_dist)` returns the exact distance when it
is `<= max_dist`, otherwise `max_dist + 1` (so the result is never mistaken
for a real distance beyond the budget):

- `max_dist < 0` clamps to 0;
- empty inputs short-circuit to the other length (capped by the contract);
- `|len(a) - len(b)| > max_dist` returns `max_dist + 1` immediately;
- otherwise the **full** `O(n*m)` DP runs with:
  - every cell clamped to `max_dist + 1`;
  - a per-row exit when no cell of the completed row is within budget.

This is deliberately **not** the banded (Ukkonen) `O(k * min(n, m))`
optimisation: the DP still materializes `(n+1)*(m+1)` cells in the worst
case. Row exit is sound because the minimum over a row of the true DP is a
lower bound on the final distance, and clamping preserves the
`> max_dist` predicate.

## Suggestion ordering

`spell_suggest(dict, word, max_dist, max_results)` returns at most
`max_results` dictionary entries, ordered by:

1. distance ascending (`spell_distance_bounded` with budget `max_dist`);
2. dictionary order for equal distances (stable, deterministic).

Degenerate arguments: `max_results <= 0` returns `[]`; `max_dist < 0`
returns `[]`; an empty dictionary returns `[]`; entries with distance
`> max_dist` are dropped. A word present in the dictionary therefore
suggests itself first (distance 0) when `max_results >= 1`.

Implementation: one scoring pass fills a flat `Vec[Int]` distance cache
(`-1` marks out-of-budget entries), then selection passes pick the smallest
remaining distance and emit every unused entry at that distance in
dictionary order until `max_results` is reached.

## Tokenization rules (unknown-word scan)

`spell_unknown_words(dict, text)` splits `text` into words and reports those
not exactly present in `dict`, in first-seen order, deduplicated:

- A word is a maximal run of ASCII word bytes `[A-Za-z0-9_]` (bytes 0-9,
  A-Z, a-z, `_`).
- An apostrophe (byte 39) is part of the run only when it sits **between**
  two word bytes: `"don't"` -> `don't`. Apostrophes at run edges and doubled
  apostrophes are separators: `"'quoted'"` -> `quoted`, `"rock''n"` ->
  `rock`, `n`.
- Every other byte is a separator: punctuation, whitespace, and each byte of
  a multi-byte UTF-8 sequence, so `"café naïve"` scans as `caf`, `na`, `ve`.
- Membership is exact and case-sensitive (via `str_compare`), so `"The"` is
  unknown even when `"the"` is in the dictionary.
- Deduplication compares through `str_compare`, never `Str ==` (BUG 17).

This matches the `xiom.tokenizer` word rule; the scanner is re-implemented
here (about 30 lines) so `xiom.spell` has no dependency on that package.

## API signatures

All functions are free functions in module `xiom.spell`:

```xi
pub fn spell_distance(a: Str, b: Str) -> Int
pub fn spell_distance_bounded(a: Str, b: Str, max_dist: Int) -> Int
pub fn spell_contains(dict: &Vec[Str], word: Str) -> Bool
pub fn spell_is_correct(dict: &Vec[Str], word: Str) -> Bool
pub fn spell_suggest(dict: &Vec[Str], word: Str, max_dist: Int, max_results: Int) -> Vec[Str]
pub fn spell_unknown_words(dict: &Vec[Str], text: Str) -> Vec[Str]
```

No function has an error path: every input is accepted and negative budgets
are clamped or yield `[]` as documented above.

## Complexity

| Function | Time | Memory |
|---|---|---|
| `spell_distance` | O(n*m) | O(n*m) flat `Vec[Int]` |
| `spell_distance_bounded` | O(n*m) worst case; O(n) row exit | O(n*m) worst case |
| `spell_contains` / `spell_is_correct` | O(dict.len()) | O(1) |
| `spell_suggest` | O(dict.len() * n * L + k * dict.len()) | O(dict.len()) |
| `spell_unknown_words` | O(text.len() + words * dict.len()) | O(words) |

`n`/`m` are byte lengths, `L` the average dictionary word length, `k` the
number of returned suggestions. `spell_suggest` scoring dominates.

## Test plan

`tests/test_conformance.xi` (`module spell_tests`, 26 named checks, csv-style
`main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and returns
the failure count):

1. identical strings have distance 0;
2. one insertion costs 1;
3. one deletion costs 1;
4. one substitution costs 1;
5. `kitten` to `sitting` is 3;
6. empty-string distance is the other length (both directions);
7. distance is symmetric (`kitten/sitting`, `cat/dog`, `flaw/lawn`,
   `abcde/abxde`);
8. multi-edit distances: `flaw/lawn` 2, `sunday/saturday` 3, `cat/dog` 3;
9. bounded returns the exact distance within budget (budgets 0, 1, 2, 3, 5);
10. bounded returns `max_dist + 1` over budget (budgets 0, 1, 2);
11. bounded budget 0 and negative budget clamp;
12. `spell_contains` finds every exact entry;
13. `spell_contains` rejects absent, case-changed and empty words;
14. `spell_is_correct` mirrors `spell_contains`;
15. suggest orders by distance then dictionary order;
16. suggest honours `max_results` (cuts 2 and 3, full list of 4);
17. suggest with `max_dist` 0 returns exact matches only;
18. suggest degenerate arguments return empty (negative budget, zero
    results, empty dictionary, no candidate);
19. suggest ties keep dictionary order;
20. unknown words reports words absent from the dictionary;
21. unknown words dedups in first-seen order;
22. unknown words keeps interior apostrophes;
23. unknown words treats edge and doubled apostrophes as separators;
24. unknown words on empty dictionary and separator-only text;
25. non-ASCII bytes are separators and distance is byte-wise
    (`"café"` vs `"cafe"` is 2);
26. unknown words keeps digits and underscores.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.spell
```

Last verified: compiler 0.61.3, `port: PASS (passed=26 failed=0
program_exit=0 exit=0)`.

## Compiler / stdlib notes for v0.61.3

- `str_compare` lives in `xiom.string.compare`, not `xiom.string`
  (`use xiom.string;` does not export it); the module imports both.
- Vec-sourced `Str` elements are compared only via `str_compare` (BUG 17:
  `==` lowers to a pointer compare).
- Vec-element reads of an integer table are pinned with explicit types
  (`let dj: Int = dist[j];`) per the xiom.diff typed-let workaround for
  call-result `Vec[Int]` element reads.
- No `Vec[Vec[Int]]` and no `Vec[StructType]`: the DP table, the distance
  cache and the used flags are all flat `Vec[Int]`.
- No inline lambdas, no `self` methods, no `mut` match pattern bindings, no
  `Vec[fn]` dispatch; free functions and `while` loops only.
- Boolean scans that index `Vec`/`Str` use nested `if`s instead of relying
  on `&&` / `||` short-circuiting for bounds.

## Known limitations

- O(n*m) time and memory for both distance functions; no cap, no fallback.
- The budgeted function is a clamped full DP, not the banded optimisation;
  it saves time only via the length and row early exits.
- Suggestion quality is purely edit-distance based: no frequency ranking,
  no keyboard-layout cost model, no context.
- Byte-wise semantics: UTF-8 characters outside ASCII are counted per byte
  and split by the word scanner.
- The dictionary is a linear `Vec[Str]` scan for every membership test; a
  trie/set index is out of scope for this package.
