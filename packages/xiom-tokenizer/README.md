# xiom.tokenizer

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** text tokenization into words, sentences, lines, and n-grams.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.str_trim`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.tokenizer` is a byte-wise tokenizer for UTF-8 `Str` text. It turns
text into ASCII word tokens (`[A-Za-z0-9_]` runs, with apostrophes kept
inside words), splits sentences at `.` `!` `?` followed by whitespace or
end of text, splits lines on `LF`/`CRLF`, and builds word n-grams. Every
entry point is infallible: functions return `Vec[Str]` (or `Int`), never a
`Result`, and empty input yields an empty vector. There is no FFI and no
dependency beyond `xiom.string` helpers.

## API

| Function | Returns | Description |
|---|---|---|
| `tokenize_words(text)` | `Vec[Str]` | Maximal runs of `[A-Za-z0-9_]`; an apostrophe between two word bytes is kept (`don't`, `isn't`); every other byte, including every non-ASCII byte, is a separator. |
| `tokenize_sentences(text)` | `Vec[Str]` | Split after `.` `!` `?` when followed by whitespace or end; each sentence is trimmed of outer whitespace; interior punctuation is kept; empty/whitespace-only text yields `[]`. |
| `tokenize_lines(text)` | `Vec[Str]` | Split on `LF` (a trailing `CR` is stripped, so CRLF works); one trailing newline adds no empty line; empty text yields `[]`. |
| `tokenize_ngrams(words, n)` | `Vec[Str]` | Contiguous n-word windows joined with single spaces; `[]` when `n < 1` or there are fewer than `n` words. |
| `tokenize_count_words(text)` | `Int` | Number of `tokenize_words` tokens in `text`. |

## Usage

```xi
use xiom.tokenizer;
use xiom.io;

fn main() -> Int {
  var words = tokenize_words("It's a small, small world.");
  io.println(words.len());              // 5
  var sentences = tokenize_sentences("One. Two! Three?");
  io.println(sentences.len());          // 3
  var lines = tokenize_lines("a\r\nb\n");
  io.println(lines.len());              // 2
  var grams = tokenize_ngrams(&words, 2);
  io.println(grams.len());              // 4
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tokenizer
```

Expected tail: 24 `[PASS]` lines, `xiom.tokenizer: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- ASCII word alphabet only: bytes outside `[A-Za-z0-9_]` separate words, so
  `café` tokenizes as `["caf"]` and CJK text yields `[]`. There is no
  Unicode-aware word/sentence segmentation.
- Apostrophes are kept only strictly between two word bytes; `'tis`, `cats'`
  and `don''t` split.
- Sentence splitting is terminator + whitespace only: abbreviations (`Dr.`),
  ellipses, decimals (`3.14`) and quotes after terminators are not special.
- `tokenize_ngrams` joins with a single space; token content is not escaped,
  so a token containing a space (n-grams built from arbitrary strings) is
  ambiguous when re-tokenized.
- No stemming, stop words, casing, or character offsets; whole `Str` in
  memory only, no streaming API.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
