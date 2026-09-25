# xiom.pls -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pls` (`src/pls.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for the PLS playlist format:

- `pls_parse` -- document -> `Result[Pls, Str]`,
- `pls_emit` -- `Pls` -> canonical PLS text,
- entry accessors -- `pls_entry_count`, `pls_has_header`, `pls_file`,
  `pls_title`, `pls_length` (1-based indexes, `FileN` semantics),
- unknown-key accessors -- `pls_unknown_count`, `pls_unknown_key`,
  `pls_unknown_value` (0-based, document order).

The codec covers the documented subset used by Winamp-style PLS files:
optional `[playlist]` header, optional `Version=2`, optional
`NumberOfEntries=N`, and `FileN` / `TitleN` / `LengthN` entries. Everything
outside that subset is preserved as an unknown key or rejected -- it is never
interpreted.

## 2. Non-goals

- Playback, stream resolution, decoder or player semantics of any kind.
- File existence checks, filesystem access, path normalization, percent
  decoding or URL validation beyond a non-empty file string.
- Semantics for extended or vendor keys (`PlaylistName`, `Genre`, `Year`,
  `BPM`, comment fields, ...): they are opaque unknown keys.
- Multiple sections, nested sections, `[playlist]` semantics beyond "the one
  accepted header name".
- Fractional durations (`Float64`/`Vec[Float64]` is unused; lengths are whole
  seconds or `-1`), sub-second tick units and byte offsets.
- Editing operations on a parsed playlist (no add/remove/mutate API).
- Streaming/incremental parsing or emitting; whole `Str` in memory only.
- `Version=1` filename/title splitting; any `Version` other than 2 is
  rejected.
- Any FFI, file I/O or registry integration.

## 3. Document grammar

```
document = *line
line     = ws* ( section / pair / blank )
section  = "[" ws* name ws* "]"
pair     = key ws* "=" ws* value
key      = "Version" / "NumberOfEntries" / indexed / unknown
indexed  = ( "File" / "Title" / "Length" ) 1*18DIGIT
name     = 1*( byte except "[" / "]" / LF )
value    = *( byte except LF )
ws       = SP | TAB
blank    = ws*
```

(`ws` in the grammar is descriptive; the implementation trims with
`xiom.string.str_trim`, so LF/CR behave the same at line edges.)

### 3.1 Lines

- `text` is split on LF. A CR immediately before an LF is removed, and one
  trailing CR at the end of an unterminated final line is removed too, so
  CRLF documents produce the same lines as LF documents and no line ever ends
  with CR. A trailing LF does not produce a final empty line.
- Every line is then `str_trim`-ed. A line that becomes empty is skipped:
  blank and whitespace-only lines are ignored everywhere.
- A final line without a terminating LF is still a line.

### 3.2 Sections (documented decision)

- A trimmed line whose first byte is `[` must end with `]` and have a
  non-empty, trimmed inner name; otherwise
  `pls: malformed section header: <line>`.
- The only accepted section name is `playlist`, matched case-insensitively
  (`[PLAYLIST]`, `[Playlist]`, ...). Any other name is
  `pls: unknown section: <line>`.
- The `[playlist]` header is optional, may appear more than once, and is
  decorative: keys are classified identically before and after it. It only
  sets `has_header` for `pls_has_header`.

### 3.3 Pairs and keys

- A non-section line without `=` is `pls: missing '=' in line: <line>`.
- The key is the trimmed text before the first `=`; the value is the trimmed
  text after it. An empty (or whitespace-only) key is
  `pls: empty key in line: <line>`. The value is never required to be
  non-empty at this level (only `FileN` is, see 3.5).
- Key matching is case-insensitive over ASCII letters. `Version` and
  `NumberOfEntries` are recognized exactly (after case folding); duplicates
  use last-wins semantics, in parser and in emitted output.
- The namespaces `file*`, `title*` and `length*` (after ASCII case folding)
  are reserved: such a key MUST continue with an index (section 3.4).
  Consequently a vendor key like `Filesystem` is rejected, not preserved.
- Any other key is an unknown key: its original (trimmed) spelling and value
  are preserved in document order, duplicates included.

### 3.4 Indexed keys and index policy

- A reserved key is `file`, `title` or `length` followed by 1..18 ASCII
  digits forming an index. Leading zeros are accepted (`File01` = `File1`).
- An empty suffix, a non-digit suffix, an index of 0, and a 19+-digit suffix
  are all `pls: bad index in key: <key>`.
- An index above 1000000 is `pls: index out of range: <key>` (documented
  codec cap; the index spaces of `FileN`/`TitleN`/`LengthN` are shared, so
  `Title2000000` is rejected even when no `File2000000` exists).
- `Version` is optional. When present its value must be 1..18 ASCII digits
  (leading zeros accepted) and equal 2; otherwise
  `pls: bad version: <value>` or `pls: unsupported version: <value>`.
- `NumberOfEntries` is optional. When present its value must be 1..18 ASCII
  digits (0 is valid, leading zeros accepted) and at most 1000000; otherwise
  `pls: bad NumberOfEntries: <value>` or `pls: too many entries: <value>`.
- When `NumberOfEntries` is present it bounds every indexed key: any indexed
  key with index greater than the declared value is
  `pls: index out of range: <key>`. This check runs **after** the whole
  document is scanned, so it does not depend on whether `NumberOfEntries`
  appears before or after the offending key. Duplicate `NumberOfEntries`
  declarations use last-wins before this check.

### 3.5 Entry assembly

Let `count` be the declared `NumberOfEntries` when present, otherwise the
highest index seen among indexed keys (0 when there are no indexed keys).

- Entries are numbered 1..`count`, stored 0-based as `files[i - 1]`,
  `titles[i - 1]`, `lengths[i - 1]`.
- `FileN` is required and must be non-empty. For the first index `i` in
  1..`count` without a non-empty `FileN` the parse fails with
  `pls: missing File<i>` (an explicit empty `FileN=`, a missing key and a
  `FileN` shadowed by a later empty assignment all hit this).
- `TitleN` is optional; absent means `""`.
- `LengthN` is optional; absent means `-1`. An explicit `-1` means the same
  as absent: unknown duration / live stream. Otherwise the value must be a
  non-negative 1..18-digit integer (leading zeros accepted); any other value
  is `pls: bad length in key <key>: <value>`. The 18-digit cap keeps the
  accumulation exact within `Int`.

### 3.6 Duplicate policy (documented decision)

For `FileN`, `TitleN`, `LengthN`, `Version` and `NumberOfEntries`, a repeated
assignment overwrites the previous one: the **last assignment wins**. For
unknown keys every occurrence is kept, in document order. On emit every key
is written exactly once (unknown keys once per occurrence).

## 4. Data model

```xi
pub type Pls = {
  has_header: Bool;          // a [playlist] line was present
  files: Vec[Str];           // per entry: FileN value, non-empty
  titles: Vec[Str];          // per entry: TitleN value, "" when absent
  lengths: Vec[Int];         // per entry: seconds, -1 = absent/-1/stream
  unknown_keys: Vec[Str];    // unknown key names, document order
  unknown_values: Vec[Str];  // values, index-aligned with unknown_keys
}
```

Invariants for a value produced by `pls_parse`:

- `files.len() == titles.len() == lengths.len() == pls_entry_count(p)`;
- every `files[i]` is non-empty;
- every `lengths[i]` is either `-1` or in `0..=999999999999999999`;
- `unknown_keys.len() == unknown_values.len()`.

`Vec[StructType]` is not usable in this compiler, so entries are three
parallel Vecs instead of a list of entry structs, and unknown keys are two
more parallel Vecs.

## 5. API contract

```xi
pub type Pls = {
  has_header: Bool;
  files: Vec[Str]; titles: Vec[Str]; lengths: Vec[Int];
  unknown_keys: Vec[Str]; unknown_values: Vec[Str];
}

pub fn pls_parse(text: Str) -> Result[Pls, Str]
pub fn pls_emit(p: &Pls) -> Str
pub fn pls_entry_count(p: &Pls) -> Int
pub fn pls_has_header(p: &Pls) -> Bool
pub fn pls_file(p: &Pls, i: Int) -> Str
pub fn pls_title(p: &Pls, i: Int) -> Str
pub fn pls_length(p: &Pls, i: Int) -> Int
pub fn pls_unknown_count(p: &Pls) -> Int
pub fn pls_unknown_key(p: &Pls, j: Int) -> Str
pub fn pls_unknown_value(p: &Pls, j: Int) -> Str
```

Details:

- Entry indexes for `pls_file`/`pls_title`/`pls_length` are 1-based
  (`File1` = 1). `j` for the unknown-key accessors is 0-based.
- `pls_file` returns `""` for a non-positive or out-of-range `i`;
  `pls_title` returns `""` for an out-of-range `i` or an absent title;
  `pls_length` returns `-1` for an out-of-range `i` or an unknown length
  (the format defines `-1` as unknown, so the sentinel is lossless);
  `pls_unknown_key`/`pls_unknown_value` return `""` out of range.
- `pls_emit` is total for any `Pls`, including hand-built ones with drifted
  parallel lengths (it guards each read). It always writes the
  `[playlist]` header, `Version=2`, `NumberOfEntries=<pls_entry_count>`, and
  then per entry `FileN=<file>`, `TitleN=<title>` only when non-empty and
  `LengthN=<seconds>` only when `>= 0`; unknown keys follow with their
  values. Every line is LF-terminated, so the output always ends with LF and
  an empty playlist emits `"[playlist]\nVersion=2\nNumberOfEntries=0\n"`.
- `pls_parse` is O(input length) plus O(entry count + indexed key count);
  `pls_emit` is O(total output length); accessors are O(1).

## 6. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"pls: "`:

| Message | Trigger |
|---|---|
| `pls: malformed section header: <line>` | `[playlist`, `[]`, `[playlist]x`, `[  ]` |
| `pls: unknown section: <line>` | `[other]`, `[playlist2]` |
| `pls: missing '=' in line: <line>` | `plain text`, `justakey`, `File1` |
| `pls: empty key in line: <line>` | `=value`, `  =  ` |
| `pls: bad index in key: <key>` | `FileX=1`, `File=1`, `Title1x=1`, `Length-1=1`, `File0=x`, 19-digit suffix |
| `pls: index out of range: <key>` | `File3=x` with `NumberOfEntries=2`; `File2000000=x` |
| `pls: bad NumberOfEntries: <value>` | `NumberOfEntries=abc`, `-1`, empty, 19+ digits |
| `pls: too many entries: <value>` | `NumberOfEntries=1000001` |
| `pls: bad version: <value>` | `Version=abc`, `Version=` |
| `pls: unsupported version: <value>` | `Version=3`, `Version=1` |
| `pls: bad length in key <key>: <value>` | `Length1=abc`, `-2`, `-0`, `1.5`, `+1`, empty, 19+ digits |
| `pls: missing File<index>` | `NumberOfEntries=2` with only `File1`; `File1=`; `Title1=x` with no `File1` |

Structural per-line errors fire in document order (the first offending line
wins). The two cross-line checks -- index range against `NumberOfEntries` and
missing `FileN` -- run after the scan: index range is checked first over all
indexed records in document order, then missing `FileN` in increasing index
order.

`pls_emit` and all accessors are total: they never return errors and use
sentinels (`-1` for lengths, `""` for strings, `0` for counts) out of range.

## 7. Round-trip rules

For any `p` obtained from `pls_parse`, `pls_parse(pls_emit(p))` yields a
playlist equal to `p` on the whole observable surface: entry count, every
file/title/length, and every unknown key/value pair in order. Emission is
idempotent: `pls_emit(pls_parse(pls_emit(p))) == pls_emit(p)`.

Normalizations performed by the round trip:

- `has_header` becomes `true` (the header is always emitted);
- `Version=2` is always emitted (an absent `Version` is normalized to 2);
- `NumberOfEntries` is recomputed from the actual entry count;
- key spelling is canonicalized (`fIlE01` emits as `File1`) and values are
  trimmed on both parse and emit;
- an empty `TitleN` and an explicit `LengthN=-1` are dropped on emit and
  reparse to the same `""` / `-1`;
- unknown keys keep their order but move after all entries;
- CRLF, blank-line layout, the position of `Version`/`NumberOfEntries`
  relative to entries, and leading zeros in numeric values are not preserved.

No semantic information is lost: files, titles (including embedded spaces and
`=`), lengths, unknown keys and unknown values survive the round trip.

## 8. Test matrix

`tests/test_conformance.xi` (module `pls_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | canonical document | header, `Version`, `NumberOfEntries`, 1-based file/title/length accessors |
| t2 | minimal document | inferred count, `""`/`-1` defaults, no header |
| t3 | case-insensitivity | `[PLAYLIST]`, `vErSiOn`, `numberOFentries`, `fIlE1` |
| t4 | CRLF + no final LF | line splitting and CR stripping |
| t5 | blanks and trimming | whitespace-only lines skipped; keys/values/section trimmed |
| t6 | `-1` vs `0` | unknown/stream sentinel is distinct from a real zero |
| t7 | leading zeros | `File01`, `Length01=007`, `NumberOfEntries=01` |
| t8 | unknown keys | verbatim values, document order, duplicates kept |
| t9 | duplicates | last assignment wins for File/Title/Length |
| t10 | non-numeric indexes | `FileX`, `File`, `Title1x`, `Length-1`, `lengthabc`, `File 1` |
| t11 | index bounds | `File0`, 19-digit index, index above the 1000000 cap |
| t12 | missing FileN | declared count with a gap; explicit empty `FileN=`; index inferred from `Title1` |
| t13 | bad lengths | alpha, `< -1`, `-0`, float, signed, empty, 19 digits |
| t14 | missing `=` | plain text, bare word, `File1` |
| t15 | empty keys | leading `=`, whitespace key |
| t16 | sections | `[other]` and malformed headers Err; `[PLAYLIST]` accepted |
| t17 | Version | `3`/`abc`/empty Err; absent and `02` accepted |
| t18 | NumberOfEntries | bounds indexes after the scan, duplicate last-wins, `0` is empty, cap and non-numeric errors |
| t19 | canonical emit | exact LF text: header/Version/count, entries, unknown keys last |
| t20 | count recomputation | actual entries drive `NumberOfEntries`; empty Title/Length omitted |
| t21 | round trip | parse -> emit -> parse deep equality; emit idempotence |
| t22 | empty documents | `""` and header-only parse to zero entries and emit the canonical empty text |
| t23 | accessor sentinels | out-of-range `""`/`-1` for every accessor |

Every Str comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17 discipline), and element reads bind typed locals first.

## 9. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.m3u` and
`xiom.ini`:

- **Ok/Err confinement.** `Ok`/`Err` for `Result[Pls, Str]` are constructed
  only in the leaf helpers `_ok_pls`/`_err_pls`; the `Pls` literal itself is
  built only by `_make_pls`.
- **Bytes as Int.** Every `string.byte_at` result goes through
  `_byte(s, pos) -> Int` (with a `& 0xFF` mask) before comparison, so no
  `UInt8` constant >= 128 is ever involved.
- **No Str `==`.** The module never compares `Str` with `==`; it uses
  `compare.str_compare`, and every `Vec[Str]`/`Vec[Int]` element read binds a
  typed local first.
- **No `Vec[StructType]`.** Entries live in three parallel Vecs; unknown keys
  in two more.
- **No `match` and no lambdas** in the library module; parsing is
  `if`/`elif`/`while` only. Test functions are called directly from `main`
  (no indexed `Vec[fn]` dispatch).
- **Explicit `&mut`.** Every `xiom.string.builder` call site passes
  `&mut out` explicitly.
- **Bounded numeric parsing.** The 18-digit cap keeps digit accumulation
  exact without a big-integer dependency; the 1000000-entry cap bounds
  materialization and error-message work.
- **NUL is unrepresentable.** `Str` values are NUL-terminated C strings, so
  a parsed `Str` can never carry an embedded 0x00 byte and
  `sb_to_str` cannot abort on this module's output; no NUL scan is needed.
- **Cross-line validation is deferred** so error selection is documented and
  order-independent with respect to `NumberOfEntries`.

## 10. Known limitations

- Reserved `file*`/`title*`/`length*` namespaces: unrelated keys such as
  `Filesystem` or `Titlebar` are rejected, not preserved.
- Only the `[playlist]` section name is accepted; other sections (even
  real-world Winamp `[playlist]`-only files are unaffected, but exotic
  multi-section files are) are errors.
- `Version` other than 2 is rejected outright.
- At most 1,000,000 entries; at most 18 significant digits per numeric
  value.
- `LengthN` values below `-1`, floats, signs and whitespace inside the number
  are rejected; `-1` and absence are indistinguishable after parse.
- Values cannot contain LF (the line model), and leading/trailing SP/TAB are
  trimmed; there is no escaping or quoting.
- No file existence checks, no URL validation beyond non-empty, no path
  normalization, no playback semantics.
- Whole-document only; no streaming and no editing API.
- Errors carry the offending line or key text but no line/column numbers.
