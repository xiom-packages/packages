# xiom.spell

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** dictionary-based spell checking over caller-supplied word lists:
> byte-wise Levenshtein distance (plain and budgeted), exact dictionary
> membership, ranked suggestions, and an unknown-word scan over free text.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`). Pure
> XIOM, no FFI.

## What it is

`xiom.spell` is a small, dependency-free spelling toolkit. The caller owns
the dictionary (a `Vec[Str]`); the module never loads word lists, does no
I/O, and is case-sensitive and byte-exact. Distance is classic Levenshtein
with unit insert/delete/substitute costs, computed over the UTF-8 bytes of
`Str`, so a non-ASCII character counts as its encoded byte length.

The plain distance uses a single flat `Vec[Int]` DP table (no
`Vec[Vec[Int]]`, no `Vec[StructType]`); the budgeted variant runs the same
DP with every cell clamped to `max_dist + 1` and exits a row early once the
whole row is over budget. `spell_suggest` ranks candidates by
(distance ascending, dictionary order), and `spell_unknown_words` scans
text with the same word rule as `xiom.tokenizer` (re-implemented here so the
package has no dependency on it).

All comparisons of `Str` values read from `Vec` elements go through
`xiom.string.compare.str_compare` (the compiler lowers `==` on such values to
a pointer comparison, BUG 17).

## API

| Function | Returns | Description |
|---|---|---|
| `spell_distance(a, b)` | `Int` | Byte-wise Levenshtein distance, unit costs; O(n*m) flat DP. |
| `spell_distance_bounded(a, b, max_dist)` | `Int` | Exact distance when `<= max_dist`, else `max_dist + 1`. |
| `spell_contains(dict, word)` | `Bool` | Exact, case-sensitive dictionary membership via `str_compare`. |
| `spell_is_correct(dict, word)` | `Bool` | Alias of `spell_contains`. |
| `spell_suggest(dict, word, max_dist, max_results)` | `Vec[Str]` | Candidates by (distance asc, dictionary order), capped. |
| `spell_unknown_words(dict, text)` | `Vec[Str]` | Words of `text` absent from `dict`, first-seen order, deduped. |

## Usage

```xi
use xiom.spell;
use xiom.convert.int;
use xiom.io;

var dict = Vec[Str].new();
dict.push("kitten");
dict.push("sitting");
dict.push("cat");

// Byte-wise Levenshtein distance.
io.println(int_to_string(spell_distance("kitten", "sitting")));  // 3

// Ranked suggestions: distance 1 from "kiten" is "kitten".
let hits = spell_suggest(&dict, "kiten", 2, 3);                  // ["kitten"]

// Unknown words, first-seen order, deduplicated.
let unknown = spell_unknown_words(&dict, "the kitten sat on a mat");
// ["the", "sat", "on", "a", "mat"]
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.spell
```

Expected: the namespaced module passes the section-4 namespace rule, 26
`[PASS]` lines, and a final `port: PASS (passed=26 failed=0 program_exit=0
exit=0)`.

## Limitations

- The caller supplies the dictionary: there is no bundled word list, no
  file loading, no compression, no case folding and no affix/stemming rules.
- `spell_distance` and `spell_distance_bounded` are O(n*m) time and memory:
  inputs with thousands of bytes allocate a large flat `Vec[Int]`. The
  budgeted entry point is a clamped full DP with a per-row early exit, not
  the banded (Ukkonen) O(k * min(n, m)) optimisation.
- `spell_suggest` scores every dictionary entry (`O(dict * |word| *
  avg word length)`) and then selects in passes; there is no BK-tree, no
  n-gram index and no phonetic fallback.
- Matching is case-sensitive and byte-exact; distances count UTF-8 bytes,
  not characters.
- The unknown-word scan is ASCII-only by design: every non-ASCII byte is a
  separator, so non-ASCII words are split at their multi-byte characters.
- Single-threaded and synchronous; no streaming dictionary and no `async`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
