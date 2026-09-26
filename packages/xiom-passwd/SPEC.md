# xiom.passwd -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.passwd` (`src/passwd.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An `/etc/passwd` codec for in-memory `Str` documents:

- parsing a whole file into a flat `Passwd` document (`passwd_parse`),
- entry access (`passwd_entry_count`, `passwd_name`, `passwd_password`,
  `passwd_uid`, `passwd_gid`, `passwd_gecos`, `passwd_home`, `passwd_shell`,
  `passwd_line`),
- name lookups (`passwd_name_index`, `passwd_home_for_name`,
  `passwd_shell_for_name`, `passwd_uid_for_name`),
- uid lookups (`passwd_uid_count`, `passwd_names_for_uid`,
  `passwd_name_for_uid`),
- the documented system-user count (`passwd_system_user_count`),
- canonical emission (`passwd_emit`) and round-trips.

Nothing else: no `/etc/shadow`, no NSS, no file I/O and no allocation beyond
the `Vec`/`Str` values the API returns.

## 2. Non-goals

- `/etc/shadow`, `/etc/group`, `/etc/gshadow`, `master.passwd` or any other
  colon-file format.
- NSS, `nsswitch.conf`, LDAP/SSSD backing stores, caching or enumeration
  order beyond document order.
- Hashing, password verification, lock detection (`!`, `*` and `x` are opaque
  text) and any interpretation of the passwd field.
- Existence, ownership or permission checks on home directories and shells;
  `/etc/shells` membership.
- useradd/usermod semantics: no allocation of uids, no uniqueness enforcement
  and no cross-field consistency checks.
- Escapes, quoting, whitespace trimming or preserved comments: the emitter is
  canonical, not lossless.
- File locking, atomic replacement, concurrent-writer semantics or file I/O:
  the module never touches the filesystem.
- Sorting, dedup or merge of entries: document order is the model, duplicate
  names and duplicate uids are preserved.
- Unicode normalization or case folding: bytes are compared exactly as
  stored.

## 3. Line grammar

```
document  = *( blank / comment / entry )
blank     = EOL
comment   = "#" *( printable byte except LF )
entry     = name ":" passwd ":" uid ":" gid ":" gecos ":" home ":" shell EOL
EOL       = LF / CRLF / end of input
```

An `entry` is one physical line with exactly seven colon-separated fields.
There are no escapes and no quoting, and fields are never trimmed, so a colon
is always a separator and can never occur inside a field; a backslash is
ordinary data.

Decisions (each is covered by the conformance suite):

1. **Lines.** The input is split at LF; one trailing CR before the LF (or
   before end of input) is removed. A file without a final newline still has
   one final line. Empty input is a zero-entry document.
2. **Blank lines.** A line with no bytes after the CR strip is blank and
   contributes no entry. A line containing only spaces is *not* blank:
   whitespace is data, so it becomes an entry candidate and fails the field
   count. A line containing only a TAB is rejected earlier as a control byte.
3. **Comments.** A comment line starts with `#` in the very first column; the
   whole line is ignored (but its bytes are still subject to the control-byte
   rule). `#` anywhere else -- inside a field, after a field, at the end of a
   line -- is ordinary data, and a line whose first byte is not `#` can never
   be a comment (` # c` is an entry candidate).
4. **Line numbers.** `Passwd.lines[i]` is the 1-based physical line of entry
   i, counted including blank and comment lines.
5. **No trimming.** Fields are stored and emitted byte for byte; leading and
   trailing spaces belong to the field (a space is not a separator).
6. **Control bytes.** A byte 0x00..0x1F (TAB included) or DEL (0x7F) anywhere
   on a line -- entry lines and comments alike -- is
   `Err("passwd: control byte in line <n>")`. The CR of a CRLF pair is legal
   because it is removed in step 1; a CR anywhere else is a control byte.
7. **Field count.** A non-blank, non-comment line must contain exactly six
   colons (seven fields); any other count is
   `Err("passwd: wrong field count in line <n>")`.
8. **Field validation.** After splitting, the fields are checked left to
   right (section 4). The passwd and gecos fields have no rule of their own:
   once the control-byte rule has passed, every printable byte is accepted.
9. **Error order.** Within a line the checks run control byte, field count,
   then name, uid, gid, home, shell; across the document the first failing
   line wins. Every message is stable ASCII.
10. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise. Bytes >= 0x80 are legal in the passwd, gecos, home and shell
    fields and in comments and pass through untouched; they are not valid in
    a name, and uid/gid accept ASCII digits only.

## 4. Field rules

### 4.1 Name

1. 1..32 bytes.
2. The first byte is a lowercase ASCII letter (`a-z`) or underscore (`_`).
3. Every later byte is a lowercase ASCII letter, digit (`0-9`), underscore or
   hyphen (`-`). A trailing hyphen is allowed; there is no label rule.
4. Anything else is `Err("passwd: bad name: <field>")`: the empty field,
   uppercase, a leading digit or hyphen, a dot, a space, non-ASCII bytes and
   names longer than 32 bytes (`aaaaaaaa...` x 33).
5. The 32-byte cap is the classic shadow-utils / `useradd` login-name limit;
   it is deliberately stricter than the kernel's 255-byte `LOGIN_NAME_MAX`.
6. Names are stored as written and compared byte-exactly, so lookups are
   case-sensitive (an uppercase query cannot match the lowercase stored
   names).

### 4.2 Passwd

1. Opaque text stored and emitted verbatim. `x`, `*`, `!`, a crypt hash
   (`$6$...`), any other printable text and the empty field are all accepted;
   spaces are accepted too (they are printable), although real files never
   contain them.
2. No semantic interpretation of any kind: no shadow lookup, no lock or
   account-state detection, no hashing and no validation of the hash format.
3. The only check that can reject a passwd field is the line-level
   control-byte rule.

### 4.3 Uid and gid

1. 1..10 ASCII decimal digits (`0-9`), nothing else: no sign, no space, no
   decimal point, no hex.
2. The value must be at most 4294967295 (2^32 - 1). Values are stored as
   `Int` (64-bit), so the full unsigned 32-bit range is representable.
3. Leading zeros are accepted (`0007` is 7). `passwd_emit` writes the
   canonical decimal value, so `0007` round-trips to `7`; this is the one
   canonicalization the emitter performs.
4. 0 is a real value (root), so uid/gid accessors return `Option[Int]` and
   report out-of-range as `None` rather than 0.
5. Failures are `Err("passwd: bad uid: <field>")` /
   `Err("passwd: bad gid: <field>")` for the empty field, `+1`, `-1`, `1a`,
   ` 1`, `1.5`, `4294967296` and any field of 11+ digits.

### 4.4 Gecos

1. Opaque printable text, stored and emitted verbatim; it may be empty.
2. Spaces, commas, `#`, backslashes and non-ASCII bytes pass through; the
   traditional comma-separated gecos subfields are *not* split or
   interpreted.
3. The only rule is the line-level control-byte check, so a control byte in
   the gecos field is reported as `passwd: control byte in line <n>` (the
   same error as anywhere else on the line).

### 4.5 Home and shell

1. The field is either empty or starts with `/` (an absolute path).
2. Nothing else is checked: no normalization of `//`, trailing slashes or
   `..` segments, no existence or permission check, no `/etc/shells`
   membership test and no `nologin` special-casing. Spaces and non-ASCII
   bytes after the leading `/` are ordinary data.
3. A non-empty field that does not start with `/` is
   `Err("passwd: bad home: <field>")` or
   `Err("passwd: bad shell: <field>")`: `home`, `./x`, `~/x`, `x/y`, `..`,
   `sh`, `bin/sh`, `./sh`.
4. The empty field is a real value and is returned as `Some("")`, so callers
   can distinguish "no home recorded" from an out-of-range index.

## 5. Data model

```xi
pub type Passwd = {
  names: Vec[Str];      // entry i: login name, validated, as written
  passwords: Vec[Str];  // entry i: passwd field verbatim (may be empty)
  uids: Vec[Int];       // entry i: uid, 0..4294967295
  gids: Vec[Int];       // entry i: gid, 0..4294967295
  gecos: Vec[Str];      // entry i: gecos verbatim (may be empty)
  homes: Vec[Str];      // entry i: home, empty or absolute
  shells: Vec[Str];     // entry i: shell, empty or absolute
  lines: Vec[Int];      // entry i: 1-based physical line
}
```

Invariants for a parsed document: all eight vectors have the same length, in
document order, one element per entry. `Vec[StructType]` is not usable in
this compiler, so the model is deliberately flat (eight parallel vectors)
instead of a vector of entry structs. Duplicate names and duplicate uids are
preserved; there is no dedup and no last-wins merge.

Accessors and the emitter defensively clamp against a mismatched document:
`passwd_entry_count` reports the smallest of the eight parallel vectors and
every other accessor guards through it, so a corrupted document degrades to
`None`/0/empty results instead of reading out of range.

## 6. API signatures

```xi
pub fn passwd_parse(text: Str) -> Result[Passwd, Str]
pub fn passwd_entry_count(d: &Passwd) -> Int
pub fn passwd_name(d: &Passwd, i: Int) -> Option[Str]
pub fn passwd_password(d: &Passwd, i: Int) -> Option[Str]
pub fn passwd_uid(d: &Passwd, i: Int) -> Option[Int]
pub fn passwd_gid(d: &Passwd, i: Int) -> Option[Int]
pub fn passwd_gecos(d: &Passwd, i: Int) -> Option[Str]
pub fn passwd_home(d: &Passwd, i: Int) -> Option[Str]
pub fn passwd_shell(d: &Passwd, i: Int) -> Option[Str]
pub fn passwd_line(d: &Passwd, i: Int) -> Int
pub fn passwd_name_index(d: &Passwd, name: Str) -> Int
pub fn passwd_home_for_name(d: &Passwd, name: Str) -> Option[Str]
pub fn passwd_shell_for_name(d: &Passwd, name: Str) -> Option[Str]
pub fn passwd_uid_for_name(d: &Passwd, name: Str) -> Option[Int]
pub fn passwd_uid_count(d: &Passwd, uid: Int) -> Int
pub fn passwd_names_for_uid(d: &Passwd, uid: Int) -> Vec[Str]
pub fn passwd_name_for_uid(d: &Passwd, uid: Int) -> Option[Str]
pub fn passwd_system_user_count(d: &Passwd) -> Int
pub fn passwd_emit(d: &Passwd) -> Str
```

Complexity: parsing is O(text length); `passwd_emit` is O(output length);
name lookups are O(entries * name length); uid lookups and
`passwd_system_user_count` are O(entries); the remaining accessors are O(1).

Contract details:

- `passwd_parse` returns `Ok` for any document in sections 3-4, including
  empty and comment-only files; all failures are `Err` per section 7.
- Entry indexes are zero-based. Out of range: `passwd_name`,
  `passwd_password`, `passwd_uid`, `passwd_gid`, `passwd_gecos`,
  `passwd_home` and `passwd_shell` return `None`; `passwd_line` returns 0;
  `passwd_name_index` returns -1; `passwd_home_for_name`,
  `passwd_shell_for_name`, `passwd_uid_for_name` and `passwd_name_for_uid`
  return `None`; `passwd_uid_count` and `passwd_system_user_count` return 0;
  `passwd_names_for_uid` returns a fresh empty `Vec`.
- Duplicate names are preserved by the parser. `passwd_name_index` and the
  `*_for_name` lookups use a documented first-match policy in document order.
- Duplicate uids are preserved. `passwd_uid_count` counts every matching
  entry, `passwd_names_for_uid` returns every matching name in document order
  (duplicates included, one element per entry) and `passwd_name_for_uid`
  returns the first match.
- `passwd_names_for_uid` returns a fresh vector: mutating it never changes
  the document.
- `passwd_home_for_name`, `passwd_shell_for_name` and `passwd_uid_for_name`
  return the empty string as `Some("")` when the matched entry has an empty
  home/shell; only an absent name (or out-of-range index) is `None`.
- `passwd_system_user_count` counts entries with uid < 1000. The predicate is
  the conventional `login.defs` UID_MIN boundary, documented, advisory and
  purely numeric: no name, shell or gecos inspection, uid 0 counts, and each
  duplicate entry counts once.
- `passwd_emit` writes one line per entry as
  `name:passwd:uid:gid:gecos:home:shell\n` with single colons and a trailing
  LF; an empty document emits `""`. Text fields are written verbatim; uid/gid
  are written in canonical decimal (leading zeros dropped). For a document
  produced by `passwd_parse`, `emit(parse(x))` is a fixed point: parsing the
  emitted text yields the same entries and emitting that result reproduces
  the text byte for byte.

## 7. Error catalog

All parse failures are `Err(msg)` with an exact ASCII message:

| Message | Trigger |
|---|---|
| `passwd: control byte in line <n>` | byte 0x00..0x1F (TAB included) or DEL anywhere on line `<n>`, in any field and in comments (the CR of a CRLF pair is legal) |
| `passwd: wrong field count in line <n>` | non-blank, non-comment line that does not have exactly seven colon-separated fields |
| `passwd: bad name: <field>` | empty name, name longer than 32 bytes, or a byte outside `[a-z_][a-z0-9_-]*` |
| `passwd: bad uid: <field>` | uid empty, not 1..10 ASCII digits, or greater than 4294967295 |
| `passwd: bad gid: <field>` | same, for the gid field |
| `passwd: bad home: <field>` | non-empty home that does not start with `/` |
| `passwd: bad shell: <field>` | non-empty shell that does not start with `/` |

The passwd and gecos fields have no message of their own: once the
control-byte rule has passed, every printable byte is accepted, so a control
byte in the gecos field is reported as `passwd: control byte in line <n>`.
Check order within a line: control byte, field count, name, uid, gid, home,
shell. Across lines: the first failing line is reported. `<n>` is the 1-based
physical line; `<field>` is the offending field exactly as written.

Examples pinned by the tests:

```
passwd_parse("root:x:0:0:root:/root\n")        -> Err("passwd: wrong field count in line 1")
passwd_parse(":x:1:1:g:/h:/s\n")               -> Err("passwd: bad name: ")
passwd_parse("a:x:4294967296:1::/:/bin/sh\n")  -> Err("passwd: bad uid: 4294967296")
passwd_parse("a:x:1::g:/h:/s\n")               -> Err("passwd: bad gid: ")
passwd_parse("a:x:1:1:g:home:/bin/sh\n")       -> Err("passwd: bad home: home")
passwd_parse("a:x:1:1:g:/h:sh\n")              -> Err("passwd: bad shell: sh")
```

## 8. Test plan

`tests/test_conformance.xi` (module `passwd_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single entry | all seven fields and the line number |
| t2 | multiple entries | CRLF, missing final newline, line numbers |
| t3 | comments and blanks | column-1 `#`, blank lines, line numbering, empty docs |
| t4 | wrong field count | 5, 7 and 8 fields, line numbers, blank-only Ok |
| t5 | name rules | `[a-z_][a-z0-9_-]*`, empty/uppercase/digit/hyphen/dot/space/33-byte rejected |
| t6 | uid/gid | 0 and 4294967295 accepted, leading zeros normalized, 9 exact errors |
| t7 | empty fields | empty passwd/gecos/home/shell are `Some("")` and re-emitted |
| t8 | home/shell | empty or leading `/`; relative/`./`/`~/` rejected |
| t9 | control bytes | byte 1, TAB, DEL, comment byte, line 2 numbering; CRLF ok |
| t10 | opacity | `x`, `*`, `!`, empty, `$6$...` passwd; gecos with spaces/UTF-8 |
| t11 | duplicate names | both entries kept; first-match name/home/shell/uid lookups |
| t12 | duplicate uids | count, ordered name list, first-name lookup |
| t13 | accessor guards | out-of-range `None`/0, absent lookups, fresh `Vec` copy |
| t14 | system users | uid < 1000 predicate: 0 and 999 count, 1000 and 65534 do not |
| t15 | canonical emit | single colons, LF, leading-zero normalization, spaces kept, empty docs |
| t16 | round-trip | fixture with empty gecos and `x` passwd; emit fixed point |
| t17 | non-ASCII | UTF-8 gecos/home pass through and re-emit identically |
| t18 | strict blanks | space-only and ` #` lines are wrong field count; TAB-only is a control byte |
| t19 | `#` as data | `#` in gecos/home/shell is preserved |
| t20 | error order | control byte before field count before field checks; first line wins |

The suite uses no `Vec[fn]` dispatch and no `==` on `Str` values read from
`Vec[Str]` elements: element reads bind a typed local first and every string
comparison uses `xiom.string.compare.str_compare` (BUG 17). Control-byte
inputs are built with a `mk_ctrl` helper; byte 0x00 is never used because a
`Str` cannot carry a NUL, and bytes 1..31 plus DEL cover the same class.

## 9. Compiler / stdlib notes

- v0.61.3: free functions only; no methods, lambdas, `match` arms with `mut`
  bindings, or `Vec[StructType]` are used. `Passwd` is a plain struct of
  eight homogeneous vectors.
- Every byte read goes through `_pw_byte_at`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no `UInt8` is ever compared
  against an integer literal (including literals >= 128); the uid/gid range
  check stays in Int space (values fit easily in 64 bits).
- `Ok`/`Err` for the struct-payload `Result[Passwd, Str]` are constructed
  only in the leaf helpers `_pw_ok`/`_pw_err`.
- All pushes on the index-aligned vectors happen in `_pw_push_entry`, so the
  eight vectors cannot drift; accessors and the emitter clamp defensively.
- Only `xiom.string`, `xiom.string.compare` and `xiom.convert` are imported
  from `xiom.std` (`byte_at`, `str_slice`, `str_compare`, `int_to_string`).
  No FFI, no new dependencies.
