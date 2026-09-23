# xiom.collation

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** case-insensitive and natural (numeric-aware) string collation.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.str_len`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## Scope

`xiom.collation` provides deterministic, dependency-free ordering for `Str`
values:

- `collate_compare` / `collate_equal`: case-insensitive lexicographic order
  with a case-sensitive tie-break that puts lowercase first;
- `collate_natural_compare`: runs of ASCII digits compare by numeric value,
  then by run length, so `"file2" < "file10"` and `"x007" < "x7"`;
- `collate_sort` / `collate_natural_sort`: stable insertion sorts that return
  a fresh `Vec[Str]` and leave the input untouched;
- `collate_key`: an ASCII-case-folded copy for case-insensitive key equality.

Comparison is byte-wise over the UTF-8 representation with unsigned byte
values: ASCII letters are folded, bytes >= 0x80 pass through and compare by
value (code-point order for well-formed UTF-8). See `SPEC.md` for the exact
rules and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `collate_compare(a, b)` | `Int` | Case-insensitive order; ties broken case-sensitively (lowercase first). Exactly -1/0/1. |
| `collate_equal(a, b)` | `Bool` | True iff `collate_compare(a, b) == 0`; exact equality (case variants are ordered, not equal). |
| `collate_natural_compare(a, b)` | `Int` | Like `collate_compare`, but ASCII digit runs compare as numbers; when values are equal the longer run sorts first. |
| `collate_sort(words)` | `Vec[Str]` | Stable insertion sort by `collate_compare`; returns a fresh vector. |
| `collate_natural_sort(words)` | `Vec[Str]` | Stable insertion sort by `collate_natural_compare`; returns a fresh vector. |
| `collate_key(s)` | `Str` | ASCII-lowercased copy of `s` (length preserved). |

## Usage

```xi
use xiom.collation;
use xiom.io;

fn main() -> Int {
  io.println(collate_compare("apple", "Banana"));         // -1
  io.println(collate_natural_compare("file2", "file10")); // -1
  var words = Vec[Str].new();
  words.push("file10");
  words.push("file2");
  let sorted = collate_natural_sort(&words);
  io.println(sorted[0]);                                  // file2
  io.println(collate_key("Apple"));                       // apple
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.collation
```

Expected tail: 20 `[PASS]` lines, `xiom.collation: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- ASCII-oriented: only `A`-`Z` are folded; there is no Unicode case folding,
  no accent/diacritic handling, no locale tailoring.
- Non-ASCII text compares by unsigned UTF-8 byte value (code-point order for
  well-formed UTF-8), not by Unicode collation rules.
- `collate_equal` is exact equality; use `collate_key` plus `xiom.string.compare`
  for case-insensitive equality.
- Natural comparison recognizes ASCII digit runs only; signs, decimal points
  and thousands separators are ordinary characters.
- The sorts are insertion sorts, O(n^2) comparisons; intended for small and
  medium lists.
- No streaming, no locale/ICU integration; whole strings are held in memory.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
