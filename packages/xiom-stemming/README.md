# xiom.stemming

> **Status:** INCUBATING -- pure-XIOM implementation, tested against the
> classic Porter fixtures.
> **Scope:** Porter stemming for lowercase ASCII English words (steps 1a, 1b,
> 1c, 2, 3, 4, 5a, 5b of Porter's 1980 algorithm).
> **Deps:** `xiom.std` only (the module uses `xiom.string`; the tests use
> `xiom.test`, `xiom.io` and `xiom.string.compare`).

## What it is

`xiom.stemming` reduces an English word to its stem: the part of the word
that remains after inflectional and derivational suffixes are removed, so
that related forms collapse together ("caresses", "caress" -> "caress";
"relational", "relation" -> "relat"). It is the classic Porter (1980)
algorithm, implemented entirely in XIOM over byte vectors -- no FFI, no
tables loaded from data files.

The input contract is deliberately narrow: words are assumed to be lowercase
ASCII `a-z`. A word containing any other byte (uppercase, digit, punctuation,
non-ASCII UTF-8) and a word shorter than three bytes are returned unchanged.

## API

| Function | Returns | Description |
|---|---|---|
| `stem(word)` | `Str` | The Porter stem of one word; invalid input and words shorter than 3 bytes are returned unchanged. |
| `stem_all(words)` | `Vec[Str]` | Stems every word, preserving order and length. |
| `stem_measure(word)` | `Int` | Porter's `m`: the number of VC sequences in the word (0 for `"tr"` and `"tree"`, 1 for `"trouble"`). |

```xi
use xiom.stemming;
stem("caresses");      // "caress"
stem("ponies");        // "poni"
stem("relational");    // "relat"
stem("sky");           // "sky"      (no vowel before the y)
stem("café");          // "café"     (non-ASCII is returned unchanged)
stem_measure("trouble");   // 1
```

## Tests

```
.\scripts\port.ps1 -Package xiom.stemming
```

From the package directory, the suite is:

```
xiom --run tests/test_conformance.xi
```

Expected: 34 `[PASS]` lines, then `xiom.stemming: all tests passed`, exit 0.

## Limitations

- **Lowercase ASCII only.** Uppercase words, digits, punctuation and non-ASCII
  text are returned unchanged (no Unicode-aware or case-folding behaviour).
- **English only, one language.** This is the original Porter algorithm; it is
  not Porter2/Snowball and not a multi-language stemmer.
- **Over-stemming and under-stemming are inherited.** Porter's algorithm is a
  heuristic: unrelated words can collide ("university", "universal" ->
  "univers") and related words can disagree ("machine" -> "machin" but
  "machinery" -> "machineri"). This is expected for the classic algorithm and
  is not treated as a bug.
- **No caching or batching policy.** `stem_all` maps one word at a time;
  callers that need a cache should build one around it.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
