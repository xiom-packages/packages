# xiom.osrelease -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.osrelease` (`src/osrelease.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for `os-release` documents (the format of
`/etc/os-release` and `/usr/lib/os-release`, systemd spec):

- `osrelease_parse` -- document -> `Result[OsRelease, Str]`,
- `osrelease_len` / `osrelease_key_at` / `osrelease_value_at` -- flat access,
- `osrelease_first` / `osrelease_last` / `osrelease_has` -- key lookup,
- `osrelease_id` / `osrelease_id_like` / `osrelease_version_id` -- conveniences,
- `osrelease_emit` -- `OsRelease` -> canonical document.

The file is a newline-separated list of environment-like assignments. This
package reads and writes *one in-memory document*; it deliberately does not
merge `/etc/os-release` with `/usr/lib/os-release`, does not evaluate a shell,
and does not expand variables. Unknown keys are preserved.

The accepted language is a strict subset of what systemd's lenient reader
(`parse_env_file`) tolerates: every accepted document has exactly one
decoding, and every error is reported. See section 6 for the divergences.

## 2. Data model

```xi
pub type OsRelease = {
  keys: Vec[Str];    // assignment names, document order
  values: Vec[Str];  // decoded values, index-aligned with keys
}
```

Invariants: `keys.len() == values.len()`; entries appear in document order;
repeated keys are preserved as separate entries (the spec forbids repeating
keys but tells readers to prefer the later entry). `Vec[StructType]` is not
usable in this compiler, so the file is deliberately flat (two homogeneous
vectors) instead of a list of entry structs.

## 3. Line grammar

```
document   = *( line )                         ; LF or CRLF terminated
line       = blank / comment / assignment
blank      = SP*                               ; empty or spaces only
comment    = "#" *( byte except LF )           ; "#" must be byte 0
assignment = key "=" value
key        = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
value      = dquoted / squoted / unquoted
dquoted    = '"' *( escaped / byte-except-'"'-and-'\' ) '"'
escaped    = "\"" / "\\" / "\$" / "\`"
squoted    = "'" *( byte-except-"'" ) "'"
unquoted   = 1 *( byte-except-SP )
ALPHA      = "A".."Z" / "a".."z"
SP         = 0x20
```

Every byte with value 0x00-0x1F or 0x7F is a *control byte* and is rejected
anywhere in a line, before any of the rules above apply. LF is the line
separator; one trailing CR is removed from each line, so CRLF input parses
identically. There is no TAB anywhere in the language.

## 4. Decisions (each is covered by the conformance suite)

1. **Lines.** LF terminates a line; one trailing CR is removed (CRLF input
   parses the same). A final line without LF is still a line. A lone CR or a
   second CR is a control byte error. A UTF-8 BOM is NOT stripped and makes
   the first line an invalid key.
2. **Blank lines.** A line that is empty or contains only space bytes (0x20)
   is ignored.
3. **Comments.** A line whose first byte is `#` is a comment and is ignored
   entirely. `#` elsewhere is data; there are no trailing comments.
   `#comment=1` is a comment; `  # x` is NOT (an indented `#` is an invalid
   key), because a line's non-blank content must start at byte 0.
4. **Keys.** `[A-Za-z_][A-Za-z0-9_]*`, starting at byte 0. Both cases are
   accepted (the spec's own files use uppercase); keys are stored and
   compared byte-exactly (case-sensitive).
5. **No whitespace around `=`.** The key must be followed immediately by `=`.
   `KEY = x` is `Err` (`invalid key`: the space ends the key run and is not
   `=`); `KEY= x` is `Err` (`whitespace in unquoted value`). `KEY=` alone is
   the empty value.
6. **Empty values.** `KEY=`, `KEY=""` and `KEY=''` all store `""`.
7. **Double-quoted values.** The only valid escapes are `\"` (quote), `\\`
   (backslash), `\$` (dollar) and `` \` `` (backtick) -- the shell-style set
   from os-release(5). Any other escape (`\n`, `\t`, `\0`, `\q`, ...) is
   `Err("osrelease: invalid escape ...")`. A missing closing quote, or a
   trailing `\` at end of line, is
   `Err("osrelease: unterminated double quote ...")`. Quoted strings are not
   concatenated: any byte after the closing quote is
   `Err("osrelease: unexpected text after quoted value ...")`.
8. **Single-quoted values.** Taken byte-for-byte until the next `'`;
   backslash and `"` are literal and there is no escape mechanism. A missing
   closing quote is `Err("osrelease: unterminated single quote ...")`; bytes
   after the closing quote are the "unexpected text" error.
9. **Unquoted values.** Run from the first byte after `=` to end of line and
   may not contain a space byte. (`#`, `=`, `"`, `'`, `&`, `$`, UTF-8, ... are
   all data when the value does not begin with a quote.) A space anywhere in
   the range -- including immediately after `=` -- is
   `Err("osrelease: whitespace in unquoted value ...")`.
10. **Control bytes.** Any byte in 0x00-0x1F or 0x7F is
    `Err("osrelease: control byte ...")`, whether bare or inside quotes.
    In particular TAB is not representable in this codec, and there is no
    `\t` escape to encode it.
11. **Duplicates.** Not an error: every assignment becomes an entry, in
    document order. `osrelease_first` returns the earliest value,
    `osrelease_last` the latest, and `osrelease_has` is true if any exists.
    The spec's reader rule ("pick the entries later in the file") is what the
    `ID`/`ID_LIKE`/`VERSION_ID` conveniences implement.
12. **Accessors.** `osrelease_key_at`/`osrelease_value_at` return `None` for
    indexes outside `[0, osrelease_len)`. Lookups are byte-exact,
    case-sensitive, and never fail: absent keys yield `None`/false.
13. **Emission.** One `KEY=VALUE` line per entry, LF separated, no trailing
    LF. A value is written bare only when every byte is in the bare alphabet
    `[A-Za-z0-9./:-_]` (so `ID=fedora`,
    `VERSION_ID=40.1`, `HOME_URL=https://fedoraproject.org/` and the empty
    value `KEY=` stay bare); otherwise it is double-quoted with `\` -> `\\`,
    `"` -> `\"`, `$` -> `\$` and backtick -> `` \` `` re-applied. Space,
    single quote, `#`, `&`, `?`, `=`, `;`, `~`, `^`, `+` and every byte >=
    0x80 (UTF-8 included) therefore appear inside double quotes, which is
    shell-safe for os-release consumers. Keys are written verbatim.
14. **Round trip.** `osrelease_parse(osrelease_emit(r))` yields exactly the
    entries of `r` (order, keys, values) for every `r` produced by
    `osrelease_parse`, and for any hand-built `r` whose values contain no
    control bytes. A value carrying a control byte is outside the accepted
    domain: the emitter writes it verbatim inside quotes, but the parser
    rejects such output (section 4.10).
15. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning never
    rewrites bytes, so non-ASCII values (e.g. `Ünïcödé`, `日本語`)
    round-trip byte-exact and are emitted double-quoted.
16. **No expansion, no evaluation.** `$VAR`, `${VAR}` and `` `cmd` `` are
    literal value text; nothing is shell-evaluated or interpolated.

## 5. API signatures

```xi
pub fn osrelease_parse(text: Str) -> Result[OsRelease, Str]
pub fn osrelease_len(r: &OsRelease) -> Int
pub fn osrelease_key_at(r: &OsRelease, index: Int) -> Option[Str]
pub fn osrelease_value_at(r: &OsRelease, index: Int) -> Option[Str]
pub fn osrelease_first(r: &OsRelease, key: Str) -> Option[Str]
pub fn osrelease_last(r: &OsRelease, key: Str) -> Option[Str]
pub fn osrelease_has(r: &OsRelease, key: Str) -> Bool
pub fn osrelease_id(r: &OsRelease) -> Option[Str]
pub fn osrelease_id_like(r: &OsRelease) -> Option[Str]
pub fn osrelease_version_id(r: &OsRelease) -> Option[Str]
pub fn osrelease_emit(r: &OsRelease) -> Str
```

Complexity: parsing is O(total input length) (no duplicate scan: repeats are
kept); by-index access is O(1); first/last/has and the conveniences are
O(entry count); emitting is O(total output length).

## 6. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"osrelease: "`
and ends with the offending line text (`<line>`, without its LF):

| Message | Trigger |
|---|---|
| `osrelease: control byte in line: <line>` | any byte 0x00-0x1F or 0x7F (TAB, NUL, DEL, lone CR, ...), inside quotes included |
| `osrelease: invalid key in line: <line>` | first byte not a letter/underscore; key not followed immediately by `=` (`1BAD=x`, `BAD-KEY=x`, `NAME foo`, `=x`, `  # x`) |
| `osrelease: missing '=' in line: <line>` | key-shaped line with no `=` at all (`NOEQ`) |
| `osrelease: unterminated double quote in line: <line>` | `A="abc`, `C="abc\` |
| `osrelease: unterminated single quote in line: <line>` | `B='abc` |
| `osrelease: invalid escape in line: <line>` | `\q`, `\z`, `\n`, `\0` or any escape outside `" \ $ ` + backtick |
| `osrelease: unexpected text after quoted value in line: <line>` | `A="x"junk`, `B='x' y`, `C="x" # c` |
| `osrelease: whitespace in unquoted value in line: <line>` | `D=x y`, `E=  `, `F= x` |

Within one line the checks run in this order: CRLF strip, control-byte scan,
blank/comment test, key scan, `=`, then value decoding. So `ID=a<TAB>b`
reports a control byte, not whitespace.

Divergences from systemd's lenient `parse_env_file`, all in the strict
direction:

- systemd skips whitespace around keys and `=` and chomps trailing
  whitespace; this codec rejects it (section 4.5, 4.9).
- systemd keeps an unknown escape such as `\n` as backslash + `n`; this codec
  rejects it so that every accepted document has exactly one decoding
  (section 4.7).
- systemd treats a backslash before LF as a line continuation (and keeps
  `\r`); this codec has no continuation lines (section 4.1, 4.7).
- systemd tolerates non-printable bytes; this codec rejects all control
  bytes (section 4.10).

## 7. Test plan

`tests/test_conformance.xi` (module `osrelease_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | Fedora example | the full os-release(5) Fedora Workstation document: 19 entries, values, `first`/`last`, `has` |
| t2 | value forms | bare, single-quoted, double-quoted, `#` as data, `KEY=`, quotes mid-value |
| t3 | escapes | `\"` `\\` `\$` `` \` `` decode |
| t4 | empty values | `KEY=`, `KEY=""`, `KEY=''` all store `""` |
| t5 | duplicates | preserved in order; `first`/`last`/`id` semantics |
| t6 | comments/blanks | `#` at byte 0, `#` mid-value, blank and spaces-only lines, indented `#` is Err |
| t7 | CRLF | `\r\n` parses; trailing CR at EOF; lone CR is a control byte |
| t8 | control bytes | TAB, `\u{0001}`, DEL, quoted TAB all Err |
| t9 | key grammar | letters/digits/underscore; case accepted; bad starts and `NOEQ` Err |
| t10 | unterminated quotes | double, single, trailing backslash |
| t11 | invalid escapes | `\q`, `\n`, `\0` Err |
| t12 | junk and whitespace | text after quotes, `x y`, `E=  `, `F= x` Err |
| t13 | lookup | `first`/`last`/`has` byte-exact and case-sensitive; `None` when absent |
| t14 | by index | `key_at`/`value_at` and out-of-range `None`; empty document |
| t15 | conveniences | `ID`/`ID_LIKE`/`VERSION_ID` last entry; `None` when unset |
| t16 | emitter bare | bare alphabet; empty value; canonicalizes redundant quotes |
| t17 | emitter quoting | space, quotes, backslash, `$`, backtick, non-ASCII, `#`, `=`, `;`, `~^+` and their escapes |
| t18 | round trip | Fedora doc and a mixed-quoting doc survive emit + reparse byte-for-byte in meaning |
| t19 | empty docs | `""`, comment-only and blank-only documents -> zero entries, emit `""` |
| t20 | UTF-8 | `Ünïcödé` unquoted and a quoted Japanese string survive parse/emit |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); error checks compare full `"osrelease: ..."` messages.

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.dotenv`/`xiom.ini` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the file is two parallel homogeneous
  vectors (no `Vec[OsRelease]`).
- `Ok`/`Err` for `Result[OsRelease, Str]` are constructed only in the leaf
  helpers `_ok_rel`/`_err_rel`; the value decoder returns `Result[Str, Str]`
  built only in `_ok_str`/`_err_str`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Tests dispatch directly (`t1()` ... `t20()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, and every `match` is exhaustive.
- `osrelease_parse` owns the line loop and mutates `OsRelease` through a
  local; `&OsRelease` is used by the read-only API, and `&mut Vec[UInt8]`
  by the emit helpers with explicit re-passing.

## 9. Known limitations

- No `/etc` vs `/usr/lib` merging, no `/run/host/os-release`, no file I/O.
- No shell evaluation, no variable/command expansion, no concatenation of
  quoted strings, no line continuation.
- No control characters, no TAB, therefore no multi-line values.
- No trailing comments (`#` after a value is data, or an error if it follows
  a quoted value).
- The emitter does not validate keys: a hand-built `OsRelease` with an
  invalid key produces text this parser rejects.
- Errors carry the offending line text but no line/column numbers.
