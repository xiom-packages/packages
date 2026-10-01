# xiom.metadata -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.metadata` (`src/metadata.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A deterministic in-memory model for ordered metadata blocks:

- `md_new` / `md_set` / `md_append` -- construction and assignment,
- `md_len` / `md_entry_*` / `md_index` / `md_has` / `md_get` / `md_origin` --
  entry access and folded-pair lookup,
- `md_scoped` / `md_subblock` -- block scoping and nesting,
- `md_merge` -- two-source merge with over-wins precedence and provenance,
- `md_diff` / `md_diff_*` / `md_diff_render` -- block diff,
- `md_serialize` / `md_serialize_sorted` / `md_parse` -- canonical text and
  round-trip,
- `md_section_valid` / `md_key_valid` / `md_value_valid` /
  `md_validate_code` / `md_validate_message` / `md_validate` /
  `md_first_duplicate` -- validation and the error catalog,
- `md_dup_*` / `md_origin_*` / `md_kind_*` / `md_val_*` -- enum-by-code
  accessors and human names.

## 2. Data model

```xi
pub type MetaBlock = {
  sec_data: Str;  sec_end: Vec[Int];   // section pool: entry i = [sec_end[i-1] or 0, sec_end[i])
  key_data: Str;  key_end: Vec[Int];   // key pool, same shape
  val_data: Str;  val_end: Vec[Int];   // value pool, same shape
  origin: Vec[Int];                    // provenance code per entry
}

pub type MetaDiff = {
  added: MetaBlock;        // pairs only in the right block
  removed: MetaBlock;      // pairs only in the left block
  changed: MetaBlock;      // pairs in both, value = old (left) value
  changed_new: MetaBlock;  // index-aligned with changed; value = new (right) value
}
```

Invariants: `sec_end.len() == key_end.len() == val_end.len() ==
origin.len()`; each pool's `ends[i]` is strictly increasing (entry 0 starts
at 0), so entry `i`'s string is
`str_slice(data, if i == 0 { 0 } else { ends[i-1] }, ends[i])`.

`Vec[StructType]` is unusable on this compiler and `Vec[Str].push`
mis-lowers, so a string list is a `Str` pool plus a parallel `Vec[Int]` of
end offsets; `_mb_push` grows all four tracks together, so they cannot
drift. `md_append` is the only public constructor without a duplicate check.

## 3. Identity, folding and ordering

1. **Folded identity.** Entry identity is the pair `(fold(section),
   fold(key))`, where `fold` (public as `md_fold_key`) lowercases bytes
   `A-Z` only and keeps every other byte verbatim. Folding is deterministic
   and table-free; non-ASCII bytes are case-exact.
2. **Str equality.** Every string comparison goes through
   `xiom.string.compare.str_compare` (BUG 17: `==` on `Str` values read from
   `Vec[Str]` elements lowers to a pointer comparison).
3. **Order.** Entries keep first-seen insertion order. A replacement under
   the last policy keeps the entry's position. `md_append` always appends.
4. **Spelling.** The stored section/key text is the spelling of the first
   occurrence; later case variants address the same entry but do not rewrite
   it (see merge, section 6).
5. **Duplicates.** `md_set` and `md_parse` always apply an explicit policy,
   so they never create duplicates. `md_append` can; use
   `md_first_duplicate` to detect the later occurrence.

Duplicate policy codes (`md_dup_*`):

| Code | Name | Rule |
|---|---|---|
| 0 | `first` | Assignment to an existing pair is a no-op: first value, position and origin win. |
| 1 | `last` | Assignment replaces the value in place; position kept, current origin kept. |
| 2 | `error` | Assignment fails: `metadata: duplicate key: <section.key>`. |

An unknown policy code fails with
`metadata: unknown duplicate policy: <n>` in both `md_set` and `md_parse`.

## 4. Scoping and nesting

- A section path is the dotted scope an entry lives in; `""` is the root
  scope. Nesting is expressed by dotted paths, e.g. `server.tls.mode`
  belongs to section `server.tls` under key `mode`.
- `md_scoped(m, prefix)`: root entries move to `prefix`, entries under `s`
  move to `prefix + "." + s`. An empty prefix is the identity (a rebuild of
  the same entries).
- `md_subblock(m, path)`: entries whose folded section equals `fold(path)`
  exactly, re-rooted to `""`, order/value/origin preserved. An unknown path
  yields an empty block. No recursive descent: the exact level only.

## 5. Assignment (`md_set`) and unchecked append (`md_append`)

`md_set(b, section, key, value, policy) -> Result[MetaBlock, Str]` returns a
new block and never mutates `b`:

- new folded pair: appended with origin `primary`;
- existing pair: per policy (section 3);
- unknown policy: `Err("metadata: unknown duplicate policy: <n>")`;
- arguments are stored verbatim; validation is a separate, explicit step.

`md_append(b, section, key, value) -> MetaBlock` appends unconditionally in
insertion order with origin `primary`; it is total and unsupported values are
stored verbatim.

## 6. Merge (`md_merge`)

`md_merge(base, over)` resolves `over` onto `base`, over-wins per folded
`(section, key)` pair:

1. All base entries are copied first, in base order, with origin `primary`
   (`0`), resetting any older provenance.
2. Each over entry in over order:
   - pair absent: appended with origin `override` (`1`);
   - pair present: the base entry's value is replaced in place with the over
     value and its origin set to `override`.
3. Result order: base entries in base order, then over-only entries in over
   order. For a shared pair the first-seen spelling (base section/key text)
   is kept; the over spelling is discarded. Section and key text of over-only
   entries is kept as written.
4. Provenance describes this merge only: `primary` = value supplied by
   `base`, `override` = value supplied by `over`. Folding merge results does
   not stack older origins.

Both inputs are untouched. An empty side is allowed: `md_merge(empty, over)`
is all `override`, `md_merge(base, empty)` is all `primary`.
`md_origin_name` maps codes to `"primary"`, `"override"`, `"unknown"`.

## 7. Diff (`md_diff`)

`md_diff(left, right)` compares folded `(section, key)` identity (a section
change is not a key match) and compares values byte-exact, case-sensitive:

- `added`: pairs only in `right`, in right order, right spelling and value;
- `removed`: pairs only in `left`, in left order, left spelling and value;
- `changed`: pairs in both with `str_compare(old, new) != 0`, in left order;
  `changed` holds the old (left) value, `changed_new` is index-aligned and
  holds the new (right) value.

There is no "isn't this the same" value coercion: `1` and `1 ` differ.

Accessors take a kind code: `md_kind_added()` = 0, `md_kind_removed()` = 1,
`md_kind_changed()` = 2; unknown kinds return `0`/`""` rather than failing.
`md_diff_render` writes one line per entry, added first, then removed, then
changed, LF separated, no trailing LF, and `""` for an empty diff:

```
+ section.key = value          (added)
- section.key = value          (removed)
~ section.key = old -> new     (changed)
```

## 8. Canonical serialization and parsing

### 8.1 Text form

- One entry per line: `key = value` for a root entry, `section.key = value`
  otherwise, where `section` is the full dotted path.
- Lines are LF separated; there is no trailing LF. An empty block emits `""`.
- Keys, sections and values are written verbatim (no escaping, no quoting).
- `md_serialize` writes insertion order -- this is the canonical form.
- `md_serialize_sorted` writes the same lines ordered by folded section,
  then folded key; ties keep insertion order (stable selection). It is a
  presentation variant; it is deterministic but not the canonical form.

### 8.2 Grammar

```
document   = *( line )                      ; LF or CRLF terminated
line       = ws* ( pair / comment / blank )
pair       = path [ ws* "=" ws* value ]
comment    = ( "#" / ";" ) *( byte except LF )     ; full line only
path       = [ section "." ] key
section    = segment *( "." segment )
segment    = 1*( byte except ws*, "." / "=" / "[" / "]" / "#" / ";" )
value      = *( byte except NUL / CR / LF )         ; trimmed
ws         = SP | TAB
```

### 8.3 Parse rules

1. Lines are split on LF; one trailing CR is removed (CRLF input parses
   identically); a final line without LF is still a line.
2. The whole line is trimmed first (`str_trim`). Blank lines are skipped; a
   line whose first non-whitespace byte is `#` or `;` is a full-line comment
   and is skipped. There are no inline comments: `#`/`;` after the first
   byte are ordinary data.
3. The first `=` splits the line. A non-blank, non-comment line without `=`
   is `Err("metadata: expected '=' in line: <line>")`.
4. The left side is trimmed. It is split at its **last** dot: everything
   before is the section, everything after is the key; no dot means root
   scope. Because keys are dot-free by rule, this recovers nested section
   paths exactly. Consequence: a malformed left side such as `a..b` is read
   as section `a.` (invalid) + key `b`, and the error reports the section it
   derived: `metadata: invalid section: a.`.
5. An empty left side is `Err("metadata: empty key in line: <line>")`; an
   empty key after the dot (`a. = 1`) is the same error; a non-empty but
   invalid key is `Err("metadata: invalid key: <key>")`.
6. The right side is trimmed into the value; the value may be empty. Invalid
   values (section 9) are `Err("metadata: invalid value: <value>")`.
7. Valid lines are stored in file order; duplicates follow the selected
   policy: `first` keeps the first, `last` replaces in place, `error` fails
   with `Err("metadata: duplicate key: <section.key>")` (the spelling of the
   line being parsed).
8. Parsed entries all have origin `primary`.
9. Round-trip: for a valid block, `md_parse(md_serialize(b))` restores the
   same entry sequence byte-exact and `md_serialize` is idempotent. This is
   guaranteed because validation excludes the only ways parse could change
   bytes (edge whitespace, CR/LF/NUL, malformed paths).

### 8.4 Complexity

Parsing is O(lines x entries x line length) because duplicate detection
scans the block per line (O(total input length) with a hash index);
`md_set`, `md_append`, `md_scoped`, `md_subblock`, `md_merge`, `md_serialize`
and `md_diff` are O(entries x entry length) or O(entries^2 x entry length)
for the patch paths; `md_serialize_sorted` is O(entries^2).

## 9. Validation rules and error catalog

Segment byte rule (`_key_byte_ok`): a byte is valid in a key or section
segment when it is greater than space (32) and is not `.`, `=`, `[`, `]`,
`#` or `;`. Bytes >= 128 (UTF-8) are allowed and never split.

- `md_section_valid`: `""` (root) is valid; otherwise one or more non-empty
  segments separated by single dots, i.e. no leading, trailing or doubled
  dot, and every byte passes the segment rule.
- `md_key_valid`: non-empty and every byte passes the segment rule (a key is
  one segment, so it never contains a dot).
- `md_value_valid`: empty is valid; otherwise no NUL, CR or LF byte, and the
  first and last bytes are neither space nor TAB (interior space/TAB and
  interior `=`, `#`, `;` are fine). These restrictions make every valid
  value survive the canonical round trip byte-exact.

`md_validate_code` returns the first failing code in the order section, key,
value; `md_validate_message` returns the pinned message; `md_validate`
applies it to every entry in insertion order and returns the first failure
or `""`.

| Code | `md_val_name` | Message |
|---|---|---|
| 0 | `ok` | `""` |
| 1 | `invalid-section` | `metadata: invalid section: <section>` |
| 2 | `invalid-key` | `metadata: invalid key: <key>` |
| 3 | `invalid-value` | `metadata: invalid value: <value>` |

Full error catalog (all start with `metadata: `):

| Message | Trigger |
|---|---|
| `metadata: unknown duplicate policy: <n>` | `md_set`/`md_parse` with a code other than 0/1/2 |
| `metadata: duplicate key: <section.key>` | policy `error` on an existing folded pair |
| `metadata: expected '=' in line: <line>` | non-blank, non-comment line without `=` |
| `metadata: empty key in line: <line>` | empty left side, or empty key after the last dot |
| `metadata: invalid section: <section>` | section fails `md_section_valid` |
| `metadata: invalid key: <key>` | key fails `md_key_valid` |
| `metadata: invalid value: <value>` | value fails `md_value_valid` |

## 10. API signatures

```xi
pub type MetaBlock = { sec_data: Str; sec_end: Vec[Int]; key_data: Str; key_end: Vec[Int]; val_data: Str; val_end: Vec[Int]; origin: Vec[Int]; }
pub type MetaDiff  = { added: MetaBlock; removed: MetaBlock; changed: MetaBlock; changed_new: MetaBlock; }

pub fn md_new() -> MetaBlock
pub fn md_len(m: &MetaBlock) -> Int
pub fn md_entry_section(m: &MetaBlock, i: Int) -> Str
pub fn md_entry_key(m: &MetaBlock, i: Int) -> Str
pub fn md_entry_value(m: &MetaBlock, i: Int) -> Str
pub fn md_entry_origin(m: &MetaBlock, i: Int) -> Int
pub fn md_index(m: &MetaBlock, section: Str, key: Str) -> Int
pub fn md_has(m: &MetaBlock, section: Str, key: Str) -> Bool
pub fn md_get(m: &MetaBlock, section: Str, key: Str) -> Option[Str]
pub fn md_origin(m: &MetaBlock, section: Str, key: Str) -> Option[Int]
pub fn md_set(m: &MetaBlock, section: Str, key: Str, value: Str, policy: Int) -> Result[MetaBlock, Str]
pub fn md_append(m: &MetaBlock, section: Str, key: Str, value: Str) -> MetaBlock
pub fn md_scoped(m: &MetaBlock, prefix: Str) -> MetaBlock
pub fn md_subblock(m: &MetaBlock, path: Str) -> MetaBlock
pub fn md_merge(base: &MetaBlock, over: &MetaBlock) -> MetaBlock
pub fn md_serialize(m: &MetaBlock) -> Str
pub fn md_serialize_sorted(m: &MetaBlock) -> Str
pub fn md_parse(text: Str, policy: Int) -> Result[MetaBlock, Str]
pub fn md_diff(left: &MetaBlock, right: &MetaBlock) -> MetaDiff
pub fn md_diff_len(d: &MetaDiff, kind: Int) -> Int
pub fn md_diff_section(d: &MetaDiff, kind: Int, i: Int) -> Str
pub fn md_diff_key(d: &MetaDiff, kind: Int, i: Int) -> Str
pub fn md_diff_value(d: &MetaDiff, kind: Int, i: Int) -> Str
pub fn md_diff_new_value(d: &MetaDiff, i: Int) -> Str
pub fn md_diff_render(d: &MetaDiff) -> Str
pub fn md_fold_key(k: Str) -> Str
pub fn md_key_valid(k: Str) -> Bool
pub fn md_section_valid(s: Str) -> Bool
pub fn md_value_valid(v: Str) -> Bool
pub fn md_validate_code(section: Str, key: Str, value: Str) -> Int
pub fn md_validate_message(section: Str, key: Str, value: Str) -> Str
pub fn md_validate(m: &MetaBlock) -> Str
pub fn md_first_duplicate(m: &MetaBlock) -> Int
pub fn md_dup_first() -> Int
pub fn md_dup_last() -> Int
pub fn md_dup_error() -> Int
pub fn md_dup_name(policy: Int) -> Str
pub fn md_origin_primary() -> Int
pub fn md_origin_override() -> Int
pub fn md_origin_name(origin: Int) -> Str
pub fn md_kind_added() -> Int
pub fn md_kind_removed() -> Int
pub fn md_kind_changed() -> Int
pub fn md_kind_name(kind: Int) -> Str
pub fn md_val_ok() -> Int
pub fn md_val_bad_section() -> Int
pub fn md_val_bad_key() -> Int
pub fn md_val_bad_value() -> Int
pub fn md_val_name(code: Int) -> Str
```

## 11. Test plan

`tests/test_conformance.xi` (module `metadata_tests`) runs 28 named checks
through `assert(cond, "name")`, one `fn` per check; `main` returns the
failure count (0 = green). Fixtures are literal texts fed through `md_parse`
or explicit `md_set` chains.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | empty block | zero entries, empty text, valid, no duplicates |
| t2 | set/append order | insertion order, accessors, out-of-range defaults, origin |
| t3 | case-insensitive lookup | `Server.Host` found as `server`/`HOST`, spelling preserved |
| t4 | absent pairs | `false` / `-1` / `None` |
| t5 | policy first | first value and position win via parse and set |
| t6 | policy last | last value wins in the first position |
| t7 | policy error | exact duplicate message, input untouched |
| t8 | unknown policy | fails closed in `md_set` and `md_parse` |
| t9 | key/section rules | dot-free key; empty/dotted/doubled-dot sections |
| t10 | value rules | empty/interior bytes ok; edge space/TAB and CR/LF rejected |
| t11 | validation catalog | codes, names and pinned messages |
| t12 | md_validate | first failure in insertion order, else `""` |
| t13 | duplicates | `md_append` builds them; `md_first_duplicate` locates the later entry |
| t14 | scoping | `md_scoped` re-parents root and nested entries; `""` identity |
| t15 | sub-block | exact level extracted, case-insensitive path, unknown empty |
| t16 | merge precedence | over wins, base order, over-only appended, exact text |
| t17 | merge provenance | primary/override incl. empty sides |
| t18 | merge spelling | first-seen spelling kept while over value wins |
| t19 | diff | added/removed/changed with old and new values, render exact |
| t20 | diff edges | self-diff empty, section-aware identity, unknown-kind safe |
| t21 | serialize order | insertion order and qualified dotted paths |
| t22 | serialize sorted | folded section then folded key |
| t23 | round trip | comments/CRLF/trim/empty value survive parse/serialize/parse |
| t24 | parse leniency | blank/comment lines, trimming, embedded `=` and TAB |
| t25 | parse errors | eight pinned catalog messages |
| t26 | parse duplicate policies | first/last/error through text |
| t27 | empty/embedded values | `k =`, `a = x = y`, interior TAB round-trip |
| t28 | provenance defaults | `md_append` and `md_parse` stamp `primary` |

Element comparisons use `str_compare`, never `==` on `Str` values read from
vectors.

## 12. Compiler notes (v0.62.2)

- No `Vec[Str]` anywhere: pools are `Str` + `Vec[Int]` end offsets, the
  proven workaround for the `Vec[Str].push` lowering defect (also used by
  `xiom.consensus`).
- No `&mut Int` / `&mut Str` parameters (writes are dropped on this
  compiler); scalar state is threaded through returns and pools are mutated
  through `&mut MetaBlock` fields.
- `Ok`/`Err` for `Result[MetaBlock, Str]` are constructed only in the leaf
  helpers `_mb_ok`/`_mb_err`.
- Every `Vec` element read is bound with a typed `let` first.
- `byte_at` results are compared directly against `UInt8` literals (the
  v0.62.2 fix); no widen/mask copies.
- No lambdas, no function tables, no `self`, no generic-named helpers, no
  indexed `Vec[fn]` dispatch; the suite calls `t1()` ... `t28()` explicitly.

## 13. Known limitations

- No interpolation, includes, inheritance or type coercion; values are byte
  runs.
- Comments are not preserved; serialization writes none.
- No quoting/escaping: a value containing CR/LF/NUL or edge whitespace is
  invalid, and an out-of-band key containing `=` or a dot cannot re-parse.
- `md_merge` keeps first-seen spelling, so it cannot rename a key.
- Provenance is per-merge, not cumulative.
- All structures are linear; no hash index, no streaming, no file I/O.
- Errors carry no line/column positions (messages include the offending
  line, key, section or value text).
