# xiom.translation

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** message catalogs: key/value translation entries with locale
> fallback and `{name}` placeholder interpolation.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.translation` is a small, dependency-free message-catalog layer for
in-memory `Str` documents. A catalog is a flat grid of `(locale, key) ->
value` entries held as three parallel vectors; the API can parse documents,
look entries up, enumerate locales and keys, add entries functionally, report
coverage gaps and resolve a key through the `locale -> fallback -> key`
chain with `{name}` interpolation.

There is no FFI, no file I/O and no global state: every function is a pure
`Str` / `Vec[Str]` operation. `SPEC.md` has the full grammar, fallback and
interpolation rules, error catalog and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `catalog_parse(locale, text)` | `Result[Catalog, Str]` | Parse an in-memory document (`key = value` or `key: value` lines, `;`/`#` comments) into entries tagged with `locale`. |
| `catalog_get(c, locale, key)` | `Option[Str]` | Exact lookup of one `(locale, key)` pair; `None` when absent. |
| `catalog_locales(c)` | `Vec[Str]` | Locales with at least one entry, first-seen order. |
| `catalog_keys(c, locale)` | `Vec[Str]` | Keys stored for `locale`, entry order (a fresh copy). |
| `catalog_add(c, locale, key, value)` | `Catalog` | New catalog with the pair written (existing pair replaced in place, new pair appended). The input is unchanged. |
| `catalog_missing(c, locale, fallback)` | `Vec[Str]` | Keys translated in `fallback` but absent from `locale`, in fallback order. |
| `catalog_translate(c, locale, fallback, key, names, values)` | `Str` | Resolve `key` through the fallback chain, then interpolate `{name}` from the parallel `names`/`values`. |

All lookups are linear scans (`O(entries)` per lookup); interpolation is a
single pass over the resolved text.

## The fallback chain

```
catalog_translate(locale, fallback, key, names, values)
  |
  |  1. entry (locale, key) exists?
  +---- yes ----> value -----------------------------+
  |   no                                              |
  |  2. entry (fallback, key) exists?                 |
  +---- yes ----> value ------------------------------+
  |   no                                              |
  |  3. use the key text itself (always resolves)     |
  |                                                   |
  +---------------------> single-pass {name} interpolation
                          (names/values, first match wins)
```

Rules pinned by the conformance suite:

- locales and keys match byte-exact (`str_compare`); no case folding, no
  region truncation (`en-US` does not fall back to `en` unless configured);
- the resolved text -- including the last-resort key -- is scanned once:
  `{name}` is replaced by the first matching value; an unknown name renders
  empty; a `{` with no later `}` is literal; `{{` is not special (the first
  `}` closes, so the placeholder name starts with `{`);
- substituted values are copied byte-exact and never re-scanned.

## Usage

```xi
use xiom.translation;
use xiom.io;

fn main() -> Int {
  let r = catalog_parse("en", "greeting=Hello, {name}!\nbye=Bye");
  match r {
    Ok(en) => {
      let cat = catalog_add(&en, "fr", "greeting", "Bonjour, {name}!");
      var names = Vec[Str].new();
      var values = Vec[Str].new();
      names.push("name");
      values.push("Ada");
      io.println(catalog_translate(&cat, "fr", "en", "greeting", &names, &values)); // Bonjour, Ada!
      io.println(catalog_translate(&cat, "de", "en", "bye", &names, &values));      // Bye
      io.println(catalog_translate(&cat, "de", "en", "nope", &names, &values));     // nope
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.translation
```

Expected tail: 22 `[PASS]` lines, `xiom.translation: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Flat keys only:** the catalog is a flat `(locale, key)` grid; dots and
  dashes are ordinary characters and there is no nesting or dotted-path
  traversal.
- **No plural rules:** one string per key; no `one`/`other` category
  selection, no plural arithmetic, no `count` context.
- **No ICU syntax:** `{name}` is the only recognized construct. There are no
  `{count, plural, ...}` / `{gender, select, ...}` forms, no nesting, no
  brace escaping and no `{{` escape (`{{` opens a placeholder whose name
  starts with `{`).
- No locale negotiation or matching: locale tags are byte-exact,
  case-sensitive strings (`en-US` and `en-us` are different catalogs).
- No file loading or serialization: documents are parsed from an in-memory
  `Str`; there is no `.po`/`.mo`/JSON/TOML loader or emitter.
- No formatting: numbers, dates, currencies and similar values must be
  pre-formatted by the caller.
- Linear lookups: every `catalog_get` / `catalog_translate` scans the entry
  list; very large catalogs want an external index.
- Values cannot span lines; one trailing CR per line is stripped (CRLF
  input), and a UTF-8 BOM is not stripped.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
