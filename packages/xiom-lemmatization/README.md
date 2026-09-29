# xiom.lemmatization

> **Status:** `incubating` -- conformance-tested (44/44); not yet published on the XIOM registry.
> **Scope:** deterministic rule-based English lemmatization: a curated
> irregular-form map, POS-tagged suffix rules (noun / verb / adjective), a
> small exception dictionary, and batch token-vector lemmatization.
> **Deps:** `xiom.std` only (the module uses `xiom.string`; the tests use
> `xiom.test`, `xiom.io` and `xiom.string.compare`).

## What it is

`xiom.lemmatization` reduces an inflected English token to its dictionary
lemma: `"children" -> "child"`, `"running" -> "run"`, `"happier" -> "happy"`,
`"studies" -> "study"`. It is a pure-XIOM, deterministic rule engine -- no
FFI, no data files, no state. Given the same input it always returns the same
output.

The pipeline is fixed and documented in `SPEC.md`:

1. **Guard** -- only ASCII-letter tokens are processed; anything containing a
   digit, punctuation or non-ASCII byte is returned unchanged.
2. **Irregular map** -- a curated, POS-scoped table (`men -> man`,
   `went -> go`, `better -> good`).
3. **Exception dictionary** -- forms the suffix rules would otherwise miss
   (`agreed -> agree`, `movies -> movie`, `larger -> large`).
4. **Suffix rules** -- ordered, longest-suffix-first tables selected by the
   POS tag `n`, `v` or `a`.
5. **Casing restoration** -- `"Cats" -> "Cat"` and `"CATS" -> "CAT"`.

## API

| Function | Returns | Description |
|---|---|---|
| `lemmatize(word, pos)` | `Str` | Lemma of one token; `pos` is `"n"`, `"v"` or `"a"` (anything else selects noun rules). Non-letter tokens are returned unchanged. |
| `lemmatize_all(words, tags)` | `Vec[Str]` | Lemmatizes a token vector against a parallel POS-tag vector; a missing tag defaults to `"n"`. |
| `lemmatize_is_irregular(word)` | `Bool` | True when the word is in any irregular table. |

```xi
use xiom.lemmatization;
lemmatize("children", "n");   // "child"
lemmatize("running", "v");    // "run"
lemmatize("happier", "a");    // "happy"
lemmatize("Cats", "n");       // "Cat"
lemmatize("don't", "v");      // "don't"  (non-letter token, unchanged)
```

## Tests

```
.\scripts\port.ps1 -Package xiom.lemmatization
```

From the package directory the suite is:

```
xiom --run tests/test_conformance.xi
```

Expected: 44 `[PASS]` lines, then `xiom.lemmatization: all tests passed`,
exit 0.

## Install / publish

```
xiom pkg install xiom.lemmatization@0.1.0     # consumer
xiom pkg publish                              # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations

- **ASCII English only.** Tokens with digits, punctuation or non-ASCII bytes
  are returned unchanged; there is no Unicode normalisation or tokenisation.
- **Rule-based, not a trained model.** It is deterministic and auditable, and
  it inherits the usual heuristic errors of suffix stripping. Ambiguous forms
  (`bases`, `axes`) and uncommon irregulars are not guaranteed.
- **Casing.** Only lowercase, `Capitalized` and ALL-CAPS inputs are handled;
  mixed-case tokens (`iPhone`) are returned unchanged.
- **No sentence context.** The POS tag is supplied by the caller; the
  lemmatizer does not tag, parse or disambiguate.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
