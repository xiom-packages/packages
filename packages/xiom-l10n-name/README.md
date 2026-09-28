# xiom.l10n.name

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Personal-name display ordering, list formatting, initials and
> caller-supplied honorifics over a five-field `Str` model.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (module header imports `xiom.string`,
> `xiom.convert` and `xiom.string.compare`; v0.1.0 calls
> `xiom.string.byte_at`, `xiom.string.str_slice`, `xiom.string.str_lower`,
> `xiom.string.str_upper` and `compare.str_compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

A personal name is five independent `Str` fields:

| Field | Holds | Example |
|---|---|---|
| `prefix` | honorific or pre-name particle | `"Dr."` |
| `given` | given name(s) | `"John"` |
| `middle` | middle name(s) | `"Paul"` |
| `family` | family name | `"Smith"` |
| `suffix` | post-name marker | `"Jr."` |

`""` is the documented **absent** sentinel; parts are used verbatim (never
trimmed) and only non-empty parts are placed. There is no name parser and no
locale database: the caller supplies already-split fields and a locale tag.
The module covers:

- display ordering: `zh`, `ja`, `ko` and `hu` are family-first, everything
  else (including unknown tags) is the given-first default;
- list formatting with locale-style joins and `max_items` truncation;
- initials in the `"J. P."` style, Unicode-aware for the first character;
- honorific lookup from a caller-supplied `(key, title)` pair table;
- a family-first sort key for byte-wise ordering.

Transliteration and script conversion are **explicitly out of scope**; see
Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `name_display(locale, name)` | `Str` | Family-first locales render `prefix family given suffix`; the default renders `prefix given middle family suffix`. Non-empty parts joined with single spaces. Family-first does not place `middle` (v0.1.0). |
| `name_display_list(locale, names, max_items)` | `Str` | Renders each name with `name_display`, skips names that render `""`. Default style: `", "` joins with `" and "` before the last item; `zh`: `"、"`; `ja`/`ko`: `"・"`. `max_items > 0` and more names than that: first `max_items` names plus `"…"` (and no `" and "`). |
| `name_initials(name)` | `Str` | Initials of `given` then `middle`: first Unicode character of each non-empty part, uppercased when possible, plus `"."`, space-joined. |
| `name_initials_of(given, middle)` | `Str` | The same rule from two plain strings. |
| `name_honorific(table, key)` | `Str` | First `title` whose `key` matches byte-wise; `""` for an empty key or a miss. Titles are caller-supplied. |
| `name_sort_key(locale, name)` | `Str` | Non-empty parts joined as `family given middle prefix suffix`; byte-wise sorting on the key orders by family. Same key for every locale (locale reserved). |
| `name_is_family_first_locale(locale)` | `Bool` | Primary subtag (before `-`/`_`), ASCII case-insensitive: true for `zh`, `ja`, `ko`, `hu`; false otherwise. |
| `name_list_new()` | `NameList` | Empty name list (five parallel `Vec[Str]`). |
| `name_list_push(list, name)` | `void` | Append one name to all five vectors in lockstep. |
| `name_list_len(list)` | `Int` | Number of names (the shared vector length). |
| `honorific_table_new()` | `HonorificTable` | Empty `(key, title)` table. |
| `honorific_table_push(table, key, title)` | `void` | Append one pair to both parallel vectors. |

No function returns `Result`: every entry point is total and the documented
fallbacks (unknown locale, empty key, missing title, empty name, truncation)
are in `SPEC.md`.

## Usage

```xi
use xiom.l10n.name;
use xiom.io;

fn main() -> Int {
  let n = PersonName{ prefix: "Dr."; given: "John"; middle: "Paul"; family: "Smith"; suffix: "Jr." };
  io.println(name_display("en", &n));          // Dr. John Paul Smith Jr.
  io.println(name_display("zh", &n));          // Dr. Smith John Jr.
  io.println(name_initials(&n));               // J. P.

  let a = PersonName{ prefix: ""; given: "Alice"; middle: ""; family: "Smith"; suffix: "" };
  var l = name_list_new();
  name_list_push(&mut l, &a);
  name_list_push(&mut l, &n);
  io.println(name_display_list("en", &l, 0));  // Alice Smith and Dr. John Paul Smith Jr.
  io.println(name_display_list("zh", &l, 1));  // Smith Alice…

  var t = honorific_table_new();
  honorific_table_push(&mut t, "dr", "Dr.");
  io.println(name_honorific(&t, "dr"));        // Dr.

  io.println(name_sort_key("en", &n));         // Smith John Paul Dr. Jr.
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.l10n.name
```

Expected tail: 21 `[PASS]` lines, `xiom.l10n.name: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No transliteration or script conversion -- explicitly out of scope.**
  Names are never converted between scripts; supply the fields in the script
  you want to display. Initials likewise copy the first character.
- **No name parsing**: free text ("Dr. John Smith Jr.") is not split into
  fields; the caller owns tokenization and field assignment.
- **No locale databases**: only the fixed family-first set `{zh, ja, ko, hu}`
  is recognized, matched on the primary subtag; everything else falls back to
  the given-first order. Hungarian (`hu`) uses the default English-style list
  conjunction (`" and "`), not `"és"`.
- **Family-first order does not place `middle`** (v0.1.0 rule): a middle part
  is omitted from `zh`/`ja`/`ko`/`hu` display; append it to `given` if needed.
- **No built-in honorifics**: `name_honorific` only reads the caller's
  `(key, title)` table; no language detection, no automatic title selection.
- Lists: only the three documented join styles; truncation is prefix + `"…"`
  (never a middle ellipsis) and drops the `" and "` conjunction.
- Sort keys are byte-wise (`str_compare`), not locale collation: no accent,
  case or width folding.
- Initials use exactly one character per part, uppercased via
  `xiom.string.str_upper`; `"Jean-Luc"` yields `"J."`, not `"J.-L."`.
- Compiler note: `Ok`/`Err`-free by design; `Str` equality never uses `==`
  (BUG 17 family) -- string decisions go through `str_compare` on typed
  locals; `UInt8` bytes at or above 128 are widened to `Int` with `% 256`
  before any comparison; the `xiom.convert` import is part of the pinned
  module header and is not called in v0.1.0.

See `SPEC.md` for the exact semantics, fallback catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
