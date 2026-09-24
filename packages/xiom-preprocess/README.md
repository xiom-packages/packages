# xiom.preprocess

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a configurable text-normalization pipeline: ASCII case folding,
> punctuation stripping, whitespace collapsing, stopword removal, word count.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.string.builder`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.preprocess` turns raw text into a cleaner, more comparable form. Every
function is a free function and infallible; no step reports an error and no
output is validated as a word, sentence or language. The four steps are, in
the fixed order used by `pp_pipeline`:

1. **fold** (`pp_fold_ascii`) -- ASCII `A-Z` to `a-z` only; every other byte,
   including every non-ASCII byte, passes through byte-exact.
2. **punct** (`pp_strip_punct`) -- drop every byte that is not an ASCII
   letter, ASCII digit or space. Bytes are removed, not replaced: `"a-b"`
   becomes `"ab"`.
3. **ws** (`pp_collapse_ws`) -- every run of space, tab, LF or CR becomes one
   space; both ends are trimmed.
4. **stopwords** (`pp_remove_stopwords`) -- whitespace-separated tokens whose
   ASCII-folded copy equals an ASCII-folded stopword exactly are dropped;
   kept tokens are rejoined with single spaces.

`pp_pipeline(s, stop, fold, punct, ws, stopw)` applies the enabled steps in
exactly that order; `pp_normalize_default(s)` is the fold + punct + ws preset
(no stopwords). `pp_word_count(s)` counts the tokens of `pp_collapse_ws(s)`.

## API

| Function | Returns | Description |
|---|---|---|
| `pp_fold_ascii(s)` | `Str` | Fold ASCII `A-Z` to `a-z`; all other bytes pass through (same length). |
| `pp_strip_punct(s)` | `Str` | Keep only `[A-Za-z0-9]` and space; drop marks, tabs, newlines and bytes >= 0x80. |
| `pp_collapse_ws(s)` | `Str` | Collapse space/tab/LF/CR runs to one space; trim both ends. |
| `pp_remove_stopwords(s, stop)` | `Str` | Drop tokens matching a stopword case-insensitively (exact match); rejoin with single spaces. |
| `pp_word_count(s)` | `Int` | Number of tokens after `pp_collapse_ws`; 0 for empty/whitespace-only input. |
| `pp_pipeline(s, stop, fold, punct, ws, stopw)` | `Str` | Apply the enabled steps in the fixed order fold -> punct -> ws -> stopwords. |
| `pp_normalize_default(s)` | `Str` | The fold + punct + ws preset; equivalent to the pipeline with the stopwords step off. |

## Usage

```xi
use xiom.preprocess;
use xiom.io;

fn main() -> Int {
  io.println(pp_fold_ascii("HELLO World"));            // hello world
  io.println(pp_strip_punct("v1.2.3!"));               // v123
  io.println(pp_collapse_ws("  a \t b \n c  "));       // a b c
  io.println(pp_normalize_default("  The FOX!!  "));   // the fox
  io.println(pp_word_count("  one  two\tthree "));     // 3

  var stops = Vec[Str].new();
  stops.push("the");
  stops.push("fox");
  io.println(pp_remove_stopwords("The quick brown FOX", &stops)); // quick brown
  io.println(pp_pipeline("The FOX ran", &stops, true, true, true, true)); // ran
  return 0;
}
```

A stopword never matches a substring: with `"the"` in the list, `"theater"`
is kept because matching is exact (on folded copies).

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.preprocess
```

Expected tail: 21 `[PASS]` lines, `xiom.preprocess: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ASCII-oriented.** Case folding is `A-Z -> a-z` only; `"Ä"` is not folded
  to `"ä"`, so a stopword with non-ASCII letters must match byte-exact.
  Digits are `[0-9]`; no Unicode classes, no locale rules, no normalization
  (NFC/NFD).
- **Whitespace tokenization only.** Words are runs of non-whitespace bytes
  separated by space, tab, LF or CR; punctuation is not a word boundary for
  `pp_remove_stopwords` (it is dropped by the punct step first in the
  pipeline). There is no sentence splitting or linguistic tokenization --
  see `xiom.tokenizer` for that.
- **No stemming or lemmatization.** `running`/`run` and `foxes`/`fox` are
  different tokens; this package only folds case and removes exact stopwords.
- **No corpus statistics.** Stopword lists are caller-supplied; no built-in
  language lists, TF-IDF, or frequency filtering.
- **Destructive stripping.** `pp_strip_punct` drops bytes rather than
  replacing them, so `"a-b"` fuses to `"ab"` and non-ASCII text loses those
  bytes (`"café"` -> `"caf"`).
- **Idempotent steps, not a linguistic guarantee.** Each step is safe to
  re-run, but preprocessing does not make outputs equal under any linguistic
  equivalence beyond ASCII case.

See `SPEC.md` for the exact per-step semantics, the fixed order and the test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
