# xiom.fstab -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.fstab` (`src/fstab.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An `/etc/fstab` codec for in-memory `Str` documents:

- parsing a whole file into a flat `Fstab` document (`fstab_parse`),
- entry access (`fstab_entry_count`, `fstab_device`, `fstab_mountpoint`,
  `fstab_fstype`, `fstab_line`),
- options access (`fstab_options_string`, `fstab_option_count`,
  `fstab_option`, `fstab_options`, `fstab_has_option`),
- dump/pass access (`fstab_dump`, `fstab_pass`),
- duplicate-mountpoint access (`fstab_mountpoint_index`,
  `fstab_entries_for_mountpoint`),
- canonical emission (`fstab_emit`) and round-trips.

Nothing else: no mount execution, no UUID/LABEL resolution, no
`/proc/mounts`, no systemd generator syntax, no `/etc/mtab`, no file I/O and no
allocation beyond the `Vec`/`Str` values the API returns.

## 2. Non-goals

- Running `mount`/`umount`, checking that a device or mountpoint exists, or
  touching the filesystem in any way.
- Resolving `UUID=`, `LABEL=`, `PARTUUID=` or `PARTLABEL=` device spellings:
  devices are opaque text.
- `/proc/mounts`, `/etc/mtab`, `mount(8)` command lines, or `systemd` unit and
  generator semantics (no `x-systemd.*` interpretation beyond storing the
  option string).
- Quotes, backslash-everything escaping, or preserved comments: the emitter is
  canonical, not lossless.
- Option semantics of any kind: no `defaults` expansion, no mount-flag
  validation, no `rw`/`ro` enforcement or exclusivity.
- Sorting, dedup or merge of entries: document order is the model, duplicate
  mountpoints are preserved.
- Unicode normalization or case folding: bytes are compared exactly as stored.

## 3. Line grammar

```
document  = *( blank / comment / entry )
blank     = ws*
comment   = ws* "#" *( byte except LF )
entry     = word ws+ word ws+ word ws+ options ws+ dump ws+ pass [ ws* ]
ws        = 1*( SP / TAB )
word      = wordbyte *( wordbyte )
wordbyte  = byte except SP / TAB / CR / LF / "#" / "\"
          | escape
options   = optname *( "," optname )
optname   = byte except SP / TAB / CR / LF / "#" / ","
dump      = "0" / "1" / "2"
pass      = "0" / "1" / "2"
EOL       = LF / CRLF / end of input
```

An `entry` is one physical line with exactly six whitespace-separated fields:
device, mountpoint, fstype, options, dump, pass. The three `word` fields are
decoded before storage (section 4.1).

Decisions (each is covered by the conformance suite):

1. **Lines.** The input is split at LF; one trailing CR before the LF (or
   before end of input) is removed. A file without a final newline still has
   one final line. Empty input is a zero-entry document.
2. **Blank and comment lines.** A line with no tokens before the comment cut
   (blank, whitespace-only, comment-only) contributes no entry but still counts
   for line numbering.
3. **Comment cut.** The first `#` on a line starts a comment that runs to the
   end of the line, wherever it appears: a `#` in the middle of a token cuts
   the token (`dev#x ...` leaves the token `dev`). `#` can therefore never
   occur inside a field, not even escaped.
4. **Line numbers.** `Fstab.lines[i]` is the 1-based physical line of entry i,
   counted including blank and comment lines.
5. **Whitespace.** SP and TAB runs separate fields; leading and trailing runs
   are ignored and any run collapses to one separator on emit.
6. **Control bytes.** A byte 0x00..0x1F other than TAB, or DEL (0x7F), is
   rejected anywhere on the line -- comments included. The CR of a CRLF pair is
   legal because it is removed in step 1; a CR anywhere else is a control byte.
7. **Field count.** After the comment cut a line has 0, 1..5, exactly 6, or 7+
   tokens: 0 is a blank line (skipped), 1..5 is `too few fields`, 7+ is `too
   many fields`, exactly 6 is an entry.
8. **Word fields.** device, mountpoint and fstype decode the four escaped
   bytes of section 4.1 and are then validated: a decoded field that contains
   no byte other than SP, TAB or LF is `empty <field>`. This is how a bare
   `\040` (a single escaped space) is rejected.
9. **Options.** The options token is split on commas; every element must be
   non-empty, so a leading, trailing or doubled comma is `empty option`. The
   element list keeps written order, duplicates stay, and the text is stored
   verbatim (no decoding, no trimming, no case folding, no interpretation).
10. **Dump/pass.** Each field is exactly one byte, `0`, `1` or `2`; any other
    token (including `00`, `10`, `-1`, empty) is `bad dump` / `bad pass`. Both
    values are stored as `Int`.
11. **Error order.** Within a line the checks run control byte, field count,
    device, mountpoint, fstype, options, dump, pass; across the document the
    first failing line wins. Every message is stable ASCII.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise. Bytes >= 0x80 are legal in fields and comments and pass through
    untouched; they are not whitespace and never trigger a control-byte error.
13. **Duplicates.** Duplicate mountpoints (and duplicate devices or options)
    are preserved in document order. There is no dedup and no last-wins merge;
    `fstab_mountpoint_index` documents first-match lookup, and
    `fstab_entries_for_mountpoint` returns every match.

## 4. Field grammar

### 4.1 Word fields and escapes

device, mountpoint and fstype accept the four documented escape sequences and
nothing else:

| Written | Byte | Meaning |
|---|---|---|
| `\040` | 0x20 | SP (space) |
| `\011` | 0x09 | TAB |
| `\012` | 0x0A | LF (newline) |
| `\134` | 0x5C | `\` (backslash) |

Rules:

1. A backslash must begin one of exactly these four-byte sequences. `\`, `\4`,
   `\077`, `\0`, `\\`, `\x` and any other sequence are `bad escape`; there is
   no variable-length or alternate octal spelling.
2. Decoding is greedy left to right and produces the byte for the sequence;
   text around escapes is copied byte for byte. `\0400` is the escaped space
   followed by the literal byte `0`.
3. After decoding, a word field is valid only if it contains at least one byte
   that is not SP, TAB or LF; otherwise it is `empty device`, `empty
   mountpoint` or `empty fstype`. A field such as `/mnt/my\040disk` is fine; a
   field consisting only of `\040`/`\011`/`\012` escapes is rejected.
4. Stored device, mountpoint and fstype values are the decoded text; `\134`
   followed by digits decodes to a literal backslash plus those digits.
5. `fstab_emit` re-encodes the four bytes in these fields: a stored backslash,
   space, TAB or LF is written `\134`, `\040`, `\011` or `\012`; every other
   byte is written verbatim.

### 4.2 Options

The options field is one whitespace-free token that is split on commas:

1. Exactly one option name per element; empty elements are rejected (leading,
   trailing and doubled commas).
2. Order is preserved; `fstab_options` and `fstab_option_count`/`fstab_option`
   report the written order.
3. Names are byte-exact and case-sensitive; `fstab_has_option` compares with
   `str_compare` and attaches no meaning.
4. `rw` and `ro` are not enforced, not mutually exclusive, not implied by any
   other option, and not implied when the field is `defaults`; a line may carry
   `rw`, `ro` or `rw,ro` and all parse successfully.
5. Duplicate option names are preserved (`rw,rw` has two options).
6. The options text is emitted verbatim; it is never escape-decoded, and a
   comma can never appear inside an option name.

### 4.3 Dump and pass

Each is the single ASCII digit `0`, `1` or `2`. The values are opaque to this
module: no pass ordering, no dump policy and no cross-field consistency is
checked (any dump with any pass is accepted).

## 5. Data model

```xi
pub type Fstab = {
  devices: Vec[Str];        // entry i: decoded device
  mountpoints: Vec[Str];    // entry i: decoded mountpoint
  fstypes: Vec[Str];        // entry i: decoded fstype
  options_text: Vec[Str];   // entry i: options field exactly as written
  option_starts: Vec[Int];  // entry i: first index of its slice in option_pool
  option_counts: Vec[Int];  // entry i: option count (>= 1)
  option_pool: Vec[Str];    // flat option-name pool, document order
  dumps: Vec[Int];          // entry i: 0, 1 or 2
  passes: Vec[Int];         // entry i: 0, 1 or 2
  lines: Vec[Int];          // entry i: 1-based physical line
}
```

Invariants for a parsed document: the nine index-aligned vectors have the same
length; entry i owns
`option_pool[option_starts[i] .. option_starts[i] + option_counts[i]]`;
`option_counts[i] >= 1`; slices are contiguous, in order, and cover exactly the
first `sum(option_counts)` elements of `option_pool`. `Vec[StructType]` is not
usable in this compiler, so the model is deliberately flat (nine per-entry
parallel vectors plus one shared pool) instead of a vector of entry structs.

Accessors and the emitter defensively clamp against a mismatched document:
`fstab_entry_count` reports the smallest of the nine parallel vectors and
`fstab_option_count` clamps its slice to `option_pool.len()`, so a corrupted
document degrades to empty results instead of reading out of range.

## 6. API signatures

```xi
pub fn fstab_parse(text: Str) -> Result[Fstab, Str]
pub fn fstab_entry_count(d: &Fstab) -> Int
pub fn fstab_device(d: &Fstab, i: Int) -> Option[Str]
pub fn fstab_mountpoint(d: &Fstab, i: Int) -> Option[Str]
pub fn fstab_fstype(d: &Fstab, i: Int) -> Option[Str]
pub fn fstab_options_string(d: &Fstab, i: Int) -> Option[Str]
pub fn fstab_option_count(d: &Fstab, i: Int) -> Int
pub fn fstab_option(d: &Fstab, i: Int, j: Int) -> Option[Str]
pub fn fstab_options(d: &Fstab, i: Int) -> Vec[Str]
pub fn fstab_has_option(d: &Fstab, i: Int, name: Str) -> Bool
pub fn fstab_dump(d: &Fstab, i: Int) -> Option[Int]
pub fn fstab_pass(d: &Fstab, i: Int) -> Option[Int]
pub fn fstab_line(d: &Fstab, i: Int) -> Int
pub fn fstab_mountpoint_index(d: &Fstab, mountpoint: Str) -> Int
pub fn fstab_entries_for_mountpoint(d: &Fstab, mountpoint: Str) -> Vec[Int]
pub fn fstab_emit(d: &Fstab) -> Str
```

Complexity: parsing is O(text length); `fstab_emit` is O(output length);
`fstab_mountpoint_index` and `fstab_entries_for_mountpoint` are
O(entries * mountpoint length); the remaining accessors are O(1) except
`fstab_options`, which is O(options), and `fstab_has_option`, which is
O(options * name length).

Contract details:

- `fstab_parse` returns `Ok` for any document in sections 3-4, including empty
  and comment-only files; all failures are `Err` per section 7.
- Entry indexes are zero-based. Out of range: `fstab_device`,
  `fstab_mountpoint`, `fstab_fstype`, `fstab_options_string`, `fstab_option`,
  `fstab_dump` and `fstab_pass` return `None`; `fstab_option_count` and
  `fstab_line` return 0; `fstab_options` returns a fresh empty `Vec`;
  `fstab_has_option` returns false; `fstab_mountpoint_index` returns -1;
  `fstab_entries_for_mountpoint` returns an empty `Vec`.
- `fstab_dump` and `fstab_pass` use `Option[Int]` because 0 is a real value
  and cannot double as "out of range".
- `fstab_options` and `fstab_entries_for_mountpoint` return fresh vectors:
  mutating them never changes the document.
- `fstab_mountpoint_index`/`fstab_entries_for_mountpoint` compare the query
  byte-exactly with the decoded stored mountpoint, so callers pass the decoded
  spelling (`/mnt/my disk`), not the escaped one (`/mnt/my\040disk`).
- `fstab_emit` writes one line per entry as
  `device<TAB>mountpoint<TAB>fstype<TAB>options<TAB>dump<TAB>pass\n`; an empty
  document emits `""`. `emit(parse(x))` is idempotent: parsing the emitted text
  yields the same entries and emitting that result reproduces the text byte for
  byte.

## 7. Error catalog

All parse failures are `Err(msg)` with an exact ASCII message:

| Message | Trigger |
|---|---|
| `fstab: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, anywhere on line `<n>` (comments included) |
| `fstab: too few fields in line <n>` | entry line with 1..5 tokens before the comment cut |
| `fstab: too many fields in line <n>` | entry line with 7 or more tokens |
| `fstab: bad escape in device: <token>` | device contains a backslash that is not one of the four documented sequences |
| `fstab: bad escape in mountpoint: <token>` | same, for the mountpoint field |
| `fstab: bad escape in fstype: <token>` | same, for the fstype field |
| `fstab: empty device: <token>` | decoded device is empty or only SP/TAB/LF |
| `fstab: empty mountpoint: <token>` | decoded mountpoint is empty or only SP/TAB/LF |
| `fstab: empty fstype: <token>` | decoded fstype is empty or only SP/TAB/LF |
| `fstab: empty option: <token>` | options field has an empty element (leading/trailing/doubled comma) |
| `fstab: bad dump: <token>` | dump is not exactly `0`, `1` or `2` |
| `fstab: bad pass: <token>` | pass is not exactly `0`, `1` or `2` |

Check order within a line: control byte, field count, device (escape then
content), mountpoint, fstype, options, dump, pass. Across lines: the first
failing line is reported. `<n>` is the 1-based physical line; `<token>` is the
offending field exactly as written, before decoding.

Examples pinned by the tests:

```
fstab_parse("dev mnt ext4 defaults 3 0")   -> Err("fstab: bad dump: 3")
fstab_parse("dev mnt ext4 defaults 0")     -> Err("fstab: too few fields in line 1")
fstab_parse("dev\q mnt ext4 defaults 0 0")  -> Err("fstab: bad escape in device: dev\q")
fstab_parse("\040 mnt ext4 defaults 0 0")   -> Err("fstab: empty device: \040")
fstab_parse("dev mnt ext4 rw,,ro 0 0")     -> Err("fstab: empty option: rw,,ro")
```

## 8. Test plan

`tests/test_conformance.xi` (module `fstab_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single entry | six fields decoded, options list, dump/pass, line number |
| t2 | multiple entries | CRLF, missing final newline, line numbers |
| t3 | comments | full-line/trailing comments, tight `#` cut, blank/comment-only/empty docs |
| t4 | escape decoding | `\040`, `\011`, `\012`, `\134` in device/mountpoint/fstype |
| t5 | emit re-encoding | escapes re-encoded, reparse equality, emit fixed point |
| t6 | options access | order, text, per-index names, `has_option`, fresh copy |
| t7 | rw/ro | not enforced, not exclusive, not implied by `defaults` |
| t8 | dump/pass values | 0, 1 and 2 all accepted and readable |
| t9 | bad dump/pass | `3`, `10`, `x`, `-1`, `00`, `12` with exact messages |
| t10 | too few fields | 1..5 tokens, line numbering, blank/comment lines skipped |
| t11 | too many fields | 7+ tokens with exact messages |
| t12 | bad escapes | truncated/unknown sequences, `\134` plus a digit round-trips |
| t13 | empty word fields | whitespace-only decoded device/mountpoint/fstype |
| t14 | control bytes | byte 1, 31, DEL, VT, mid-line CR, comments included; TAB/CRLF ok |
| t15 | duplicate mountpoints | preserved entries, first-match index, all-index list |
| t16 | canonical emit | single tabs, trailing LF, empty and comment-only docs |
| t17 | round-trip | pinned canonical text, `parse(emit(parse(x)))`, fixed point |
| t18 | accessor guards | out-of-range `None`/0/empty/-1 and absent queries |
| t19 | empty options | `,`, `rw,`, `,rw`, `rw,,ro` rejected; single options accepted |
| t20 | non-ASCII bytes | UTF-8 device/mountpoint/comment bytes pass through |

The suite uses no `Vec[fn]` dispatch and no `==` on `Str` values read from
`Vec[Str]` elements: element reads bind a typed local first and every string
comparison uses `xiom.string.compare.str_compare` (BUG 17).

## 9. Compiler / stdlib notes

- v0.61.3: free functions only; no methods, lambdas, `match` arms with `mut`
  bindings, or `Vec[StructType]` are used. `Fstab` is a plain struct of nine
  homogeneous vectors plus the shared option pool.
- Every byte read goes through `_fs_byte_at`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no `UInt8` is ever compared
  against an integer literal (including literals >= 128).
- `Ok`/`Err` for the struct-payload `Result[Fstab, Str]` are constructed only
  in the leaf helpers `_fs_ok`/`_fs_err`.
- All pushes on the index-aligned vectors happen in `_fs_push_entry`, so the
  nine entry vectors cannot drift; accessors and the emitter clamp defensively.
- Only `xiom.string`, `xiom.string.compare` and `xiom.convert` are imported
  from `xiom.std` (`byte_at`, `str_slice`, `str_compare`, `int_to_string`). No
  FFI, no new dependencies.
