# xiom.ngram

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** word and character n-grams, set-similarity scores (Jaccard,
> Dice) and MinHash signatures.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_lower`,
> `xiom.string.compare.str_compare` and `xiom.convert.int.int_to_string`).
> Tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

`xiom.ngram` turns text into n-gram shingles and compares them as sets:

- `ngram_words(text)` scans text into lowercase ASCII word tokens
  (`[A-Za-z0-9]` runs; every other byte, including every non-ASCII byte, is a
  separator).
- `ngram_shingles(words, n)` joins each contiguous window of `n` words with
  single spaces.
- `ngram_char_shingles(text, n)` slices the raw bytes of the text into
  length-`n` shingles (verbatim, so UTF-8 passes through byte-exact).
- `ngram_unique(shingles)` de-duplicates, keeping first-seen order.
- `ngram_jaccard` / `ngram_dice` score two shingle sets in permille
  (0..1000, truncated).
- `ngram_minhash_signature(shingles, hashes, seed)` builds a `hashes`-slot
  MinHash signature from an in-module 32-bit FNV-1a hash; equal-length
  signatures compare with `ngram_signature_similarity` (permille).

Every entry point is infallible: functions return `Vec`/`Int`, never a
`Result`, and empty input yields an empty vector or a zero score.

## API

| Function | Returns | Description |
|---|---|---|
| `ngram_words(text)` | `Vec[Str]` | Maximal runs of `[A-Za-z0-9]` lowercased; all other bytes (punctuation, whitespace, underscore, non-ASCII) separate. |
| `ngram_shingles(words, n)` | `Vec[Str]` | Contiguous `n`-word windows joined with single spaces, in order; `[]` when `n < 1` or fewer than `n` words. |
| `ngram_char_shingles(text, n)` | `Vec[Str]` | Verbatim byte windows of length `n`, in order; `[]` when `n < 1` or the text is shorter. |
| `ngram_unique(shingles)` | `Vec[Str]` | Distinct shingles in first-seen order (str_compare). |
| `ngram_jaccard(a, b)` | `Int` | `|A∩B|/|A∪B|` on the distinct shingle sets, in permille (0..1000, truncated); `0` for empty sets. |
| `ngram_dice(a, b)` | `Int` | `2|A∩B|/(|A|+|B|)` on the distinct shingle sets, in permille (0..1000, truncated); `0` for empty sets. |
| `ngram_minhash_signature(shingles, hashes, seed)` | `Vec[Int]` | One minimum per slot of `fnv1a32(seed:slot:shingle)`; length `hashes`, zeros for empty shingles, `[]` when `hashes < 1`. |
| `ngram_signature_similarity(a, b)` | `Int` | Fraction of equal slots in permille (0..1000, truncated); `0` on length mismatch or two empty signatures. |

## Usage

```xi
use xiom.ngram;
use xiom.io;

fn main() -> Int {
  var words = ngram_words("The quick brown fox");
  io.println(words.len());                       // 4
  var shingles = ngram_shingles(&words, 2);
  io.println(shingles.len());                    // 3

  var a = ngram_words("the quick brown fox jumps over the lazy dog");
  var b = ngram_words("the quick brown fox sleeps over the lazy dog");
  var sa = ngram_shingles(&a, 2);
  var sb = ngram_shingles(&b, 2);
  io.println(ngram_jaccard(&sa, &sb));           // 600 (6 of 10 bigrams shared)

  var ma = ngram_minhash_signature(&sa, 32, 42);
  var mb = ngram_minhash_signature(&sb, 32, 42);
  io.println(ngram_signature_similarity(&ma, &mb));  // ~600
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ngram
```

Expected tail: 22 `[PASS]` lines, `xiom.ngram: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Hash quality.** The MinHash signature uses an in-module 32-bit FNV-1a
  hash. It is deterministic and fast but not cryptographic and only 32 bits
  wide, so collisions are possible and `ngram_signature_similarity` is an
  estimate of set Jaccard, not an exact score.
- **Similarity is set-based.** Jaccard and Dice collapse duplicates and
  ignore order and multiplicity; `ngram_unique` is applied internally.
- **Truncated permille.** Scores are integer permille (`floor`), so a
  1000 score means exact equality on the underlying sets, and small overlaps
  can round down to 0.
- **ASCII words only.** `ngram_words` keeps `[A-Za-z0-9]`; accents, CJK and
  em dashes are separators (`café` -> `["caf"]`), and underscores split.
- **Character shingles are byte shingles.** `n` counts bytes, not
  characters; a multi-byte UTF-8 character can be split across two shingles.
- **No streaming.** Whole inputs are in memory; set operations are O(n*m)
  `str_compare` scans with no hashing index.

See `SPEC.md` for the full semantics, formulas, hash recipe and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
