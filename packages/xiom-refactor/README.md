# xiom.refactor

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** text-level identifier renaming with configurable word boundaries,
> dry-run counts and line reporting.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.refactor` renames identifiers in in-memory text without parsing it. A
*whole-word occurrence* of `old_name` is a byte-exact match whose neighboring
bytes are not word characters, where the word-character set is passed in by
the caller (`refactor_word_chars_default()` returns the usual `[A-Za-z0-9_]`).
The module counts occurrences, replaces them, applies ordered `"old=new"`
pair lists with per-pair dry-run reports, and reports which 1-based lines
contain an occurrence. Every entry point is infallible: it returns `Str`,
`Int` or `Vec`, never a `Result`, and malformed pair input is reported or
skipped instead of erroring. There is no FFI and no dependency beyond the
`xiom.std` helpers named above.

## API

| Function | Returns | Description |
|---|---|---|
| `refactor_word_chars_default()` | `Str` | The default word alphabet `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_` (63 bytes). |
| `refactor_is_word_char(byte, word_chars)` | `Bool` | True when the Int `byte` is in `0..255` and occurs in `word_chars`; false otherwise, including for an empty set. |
| `refactor_count(text, old_name, word_chars)` | `Int` | Number of whole-word occurrences, scanned left to right without overlap; `0` for an empty `old_name`. |
| `refactor_rename(text, old_name, new_name, word_chars)` | `Str` | `text` with every whole-word occurrence replaced; unchanged when `old_name` is empty or absent; UTF-8 passes through byte-exact. |
| `refactor_rename_dry_run(text, renames, word_chars)` | `Vec[Str]` | One line per pair, in order: `old -> new: N replacement(s)` where `N` is counted in the text as produced by the preceding pairs; a pair without `=` yields `old -> ?: invalid` and is skipped. |
| `refactor_rename_batch(text, renames, word_chars)` | `Str` | Applies the same pairs in order (a later pair sees earlier replacements) and returns the final text; malformed pairs are skipped. |
| `refactor_occurrence_lines(text, name, word_chars)` | `Vec[Int]` | 1-based line numbers (LF-delimited, CRLF tolerated) with at least one whole-word occurrence, in increasing order; `[]` for empty text or empty name. |

## Usage

```xi
use xiom.refactor;
use xiom.io;

fn main() -> Int {
  let d = refactor_word_chars_default();
  io.println(refactor_count("let foo = foo_bar;", "foo", d));   // 1
  io.println(refactor_rename("let foo = 1;", "foo", "bar", d)); // let bar = 1;

  var pairs = Vec[Str].new();
  pairs.push("foo=bar");
  pairs.push("bar=baz");
  var reports = refactor_rename_dry_run("foo foo_bar", &pairs, d);
  let first: Str = reports[0];
  let second: Str = reports[1];
  io.println(first);   // foo -> bar: 1 replacement(s)
  io.println(second);  // bar -> baz: 1 replacement(s)

  io.println(refactor_rename_batch("foo foo_bar", &pairs, d));  // baz foo_bar
  io.println(refactor_occurrence_lines("foo\nbar\nfoo", "foo", d).len()); // 2
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.refactor
```

Expected tail: 20 `[PASS]` lines, `xiom.refactor: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Text-level only, no parse awareness:** there is no lexer or symbol table,
  so occurrences inside string literals, comments and documentation are
  renamed exactly like code (`foo` in `"foo"` or `// foo` changes too). Scope
  correctness is the caller's responsibility.
- **Byte-oriented:** matching is byte-exact over UTF-8; word characters are
  single bytes, so with the default alphabet every non-ASCII byte separates.
  `café` is not a word character; `foo` next to `é` counts as whole-word.
  There are no Unicode identifier rules.
- **Case-sensitive:** `Foo` and `foo` are different names.
- **Non-overlapping scan:** matches are found left to right with no overlap,
  so `aaaa` with `aa` is one replacement (`Xa`), and the dry-run count always
  equals the number of replacements `refactor_rename` performs.
- **Pairs split at the first `=`:** `a=b=c` renames `a` to `b=c`; an empty old
  name (a pair starting with `=`) never matches and reports 0.
- Lines are reported as numbers only: no columns, no byte offsets, whole `Str`
  in memory, no streaming API.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
