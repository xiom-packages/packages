# xiom.fix -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.fix` (`src/fix.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for one in-memory FIX message held as a `Str`:

- `fix_parse` -- message text -> `Result[FixMessage, Str]`,
- `fix_tag_count` / `fix_value` / `fix_value_last` / `fix_msg_type` --
  accessors over the parsed fields,
- `fix_emit` -- canonical message text with tags 9 and 10 recomputed.

The codec handles framing: the SOH field separator, ordered `tag=value`
pairs, duplicate tags, and the four structural tags `8`, `9`, `35`, `10`.
It performs no repeating-group expansion, no data-dictionary or field-type
validation, no FIXML, no encryption, and no session-protocol behavior
(logon, heartbeats, sequence numbers, resend). Those are non-goals -- see
section 9.

## 2. Data model

```xi
pub type FixMessage = {
  raw: Str;          // the exact input text the spans index into
  tags: Vec[Int];    // tag numbers in wire order
  starts: Vec[Int];  // value start offsets into raw, aligned with tags
  ends: Vec[Int];    // value end offsets (exclusive), aligned with tags
  body_length: Int;  // validated value of tag 9
  checksum: Int;     // validated value of tag 10, 0..255
}
```

Invariants (for messages returned by `fix_parse`):

- `tags.len() == starts.len() == ends.len()`; field `i`'s value is the byte
  span `raw[starts[i], ends[i])` and is read with
  `xiom.string.str_slice` -- values are never copied into the struct.
- `tags` contains every wire field in order, including tags 8, 9 and 10;
  `fix_tag_count` therefore counts all of them.
- Tags 8, 9 and 10 appear exactly once; duplicates of 8 or 9 are parse
  errors and a second 10 can only appear after the first, which is a
  trailing-bytes error.
- `body_length` and `checksum` hold the validated scalars of tags 9 and 10.

`Vec[StructType]` is not usable in this compiler, so the field list is
deliberately flat (parallel homogeneous vectors) instead of a list of field
structs. Hand-built messages may violate the invariants; the accessors then
degrade to `None`/`""` rather than reading out of bounds, and `fix_emit`
returns a guard error (section 6).

## 3. Wire grammar

```
message     = "8=" begin SOH "9=" body-len SOH body "10=" check SOH?
begin       = 1*( byte except SOH )            ; non-empty; "=" allowed
body        = *( field )                       ; zero or more fields
field       = tag "=" value SOH
tag         = 1*9DIGIT                         ; value 1..999999999
value       = *( byte except SOH )             ; may be empty
body-len    = 1*9DIGIT
check       = 3DIGIT                           ; numeric value 000..255
SOH         = 0x01
```

Parsing decisions, each pinned by the conformance suite:

1. **Field split.** The first `=` after the tag bytes separates tag and
   value; every later byte up to the SOH belongs to the value. The documented
   producer subset uses values without `=` at all, but extra `=` bytes are
   tolerated and preserved (`44=a=b c` stores `a=b c`).
2. **Tags.** One to nine ASCII decimal digits. Leading zeros are accepted
   (`008` is tag 8) and canonicalized on emit; a tag of 0, a tag longer than
   nine digits, an empty tag and any non-digit byte are errors.
3. **Empty values.** `tag=` with nothing before the SOH is legal for every
   tag except 8 and 35, and stores `Some("")`.
4. **Field order.** Field 0 must be tag 8; field 1 must be tag 9; the field
   with tag 10 must be last. Any other tag may appear anywhere in the body,
   any number of times (except 8 and 9).
5. **Terminators.** Every field except tag 10 must be terminated by SOH. The
   tag-10 field may be terminated by SOH or by the end of the input; bytes
   after the tag-10 field's terminating SOH are `trailing bytes after
   checksum`.
6. **Duplicates.** Duplicate tags in the body are preserved in wire order and
   are not merged. Duplicating 8 or 9 is rejected; duplicating 10 is
   impossible to observe because the first tag-10 field ends the frame.
7. **Encoding.** `Str` is treated as a byte buffer; scanning is byte-wise and
   never rewrites multi-byte sequences. The documented subset is
   high-bit-free ASCII; no byte is ever widened without masking.

## 4. Validation rules and check order

On parse, all of the following must hold; the first failing check is
reported, in this order:

1. Input is non-empty (`fix: empty message`).
2. Per field, scanning left to right: tag digits and `=` shape, tag range,
   field position (8 first, 9 second), duplicate 8/9, non-empty
   BeginString, non-empty MsgType.
3. At the tag-10 field, in order:
   1. no trailing bytes after it,
   2. tag 9 is a decimal integer (1-9 digits; empty/non-digit/too wide is
      an error),
   3. tag 9 equals `start_of_tag10_field - (end_of_tag9_value + 1)`, the
      exact byte count of the body between the SOH after tag 9 and the start
      of `10=`,
   4. a non-empty tag 35 field was seen,
   5. tag 10 is exactly three ASCII digits with value `000`-`255`,
   6. tag 10 equals the sum of all bytes before `10=` modulo 256.
4. If the input ends before a tag-10 field, `fix: missing tag 10 (CheckSum)`.

Worked example: `8=FIX.4.2<SOH>9=5<SOH>35=D<SOH>10=181<SOH>`. The body
`35=D<SOH>` is 5 bytes, so `9=5`; the bytes before `10=` (19 bytes) sum to
949, and `949 mod 256 = 181`.

## 5. Accessors

```xi
pub fn fix_tag_count(m: &FixMessage) -> Int
pub fn fix_value(m: &FixMessage, tag: Int) -> Option[Str]
pub fn fix_value_last(m: &FixMessage, tag: Int) -> Option[Str]
pub fn fix_msg_type(m: &FixMessage) -> Str
```

- `fix_tag_count` counts stored fields, duplicates included, and includes
  tags 8, 9 and 10 (a minimal message has count 4).
- `fix_value` returns the first value stored under `tag` in wire order;
  `fix_value_last` the last. Both return `None` when the tag is absent and
  `Some("")` for an empty value. Matching is byte-exact, there is no
  normalization.
- `fix_msg_type` returns the first tag-35 value, or `""` when the stored
  message has no tag-35 field (only possible for hand-built messages, since
  `fix_parse` requires it).
- All accessors are bounds-guarded: for a hand-built message whose three
  vectors are not aligned, they return `None`/`""` instead of reading out of
  range. Complexity is O(1) for the count and O(tag count) for lookups.

## 6. Canonical emit

```xi
pub fn fix_emit(m: &FixMessage) -> Result[Str, Str]
```

`fix_emit` writes the canonical frame:

```
8=<BeginString value><SOH> 9=<body length><SOH> <middle fields> 10=<checksum><SOH>
```

- The BeginString comes from the first (and only) tag-8 field.
- Every field whose tag is not 8, 9 or 10 is written in stored order as
  `tag=value<SOH>` -- this is the *middle section*. Stored tag-9 and tag-10
  fields are ignored and regenerated, so stale BodyLength/CheckSum values
  can never leak into the output.
- `body length` is the exact byte length of the middle section (each field
  includes its own SOH).
- `checksum` is the sum of every byte before `10=` modulo 256, written as
  three digits with leading zeros (`004` for 4).
- Tag numbers are written as plain decimals (no leading zeros, no padding).
- Values are copied byte-for-byte. A value containing NUL (`0x00`) or SOH is
  rejected, as is a value span outside `raw`.

For a message produced by `fix_parse` this reproduces the input byte-exactly
(including the trailing SOH), because the stored order is already
`8, 9, body..., 10` and the recomputed values equal the parsed ones. For
hand-built messages the output is still canonical: fields are re-framed, and
tag 8 is always first even if it was stored elsewhere.

Emit guard errors, in check order: `fix: cannot emit: field vectors are not
aligned`; then per field `fix: cannot emit: invalid tag`, `fix: cannot emit:
field span out of range`, `fix: cannot emit: duplicate tag 8`, `fix: cannot
emit: value contains a reserved byte`; then `fix: cannot emit without tag 8
(BeginString)`.

## 7. Error catalog

All parse failures are `Err(msg)` with a deterministic message starting with
`"fix: "`; `N` is a byte offset and the other scalars are decimal.

| Message | Trigger |
|---|---|
| `fix: empty message` | input `""` |
| `fix: missing SOH terminator at offset N` | a non-tag-10 field has no SOH before end of input |
| `fix: missing '=' in field at offset N` | the field has no `=` before its SOH |
| `fix: non-digit tag at offset N` | empty tag run or a non-digit byte in it |
| `fix: invalid tag 0 at offset N` | the tag is 0 |
| `fix: tag out of range at offset N` | the tag run is longer than 9 digits |
| `fix: first field must be tag 8 (BeginString)` | field 0 is not tag 8 |
| `fix: second field must be tag 9 (BodyLength)` | field 1 is not tag 9 |
| `fix: duplicate tag 8` | tag 8 appears again |
| `fix: duplicate tag 9` | tag 9 appears again |
| `fix: empty BeginString` | the tag-8 value is empty |
| `fix: empty MsgType` | the tag-35 value is empty |
| `fix: missing tag 35 (MsgType)` | no tag-35 field before the checksum |
| `fix: missing tag 10 (CheckSum)` | input ends without a tag-10 field |
| `fix: trailing bytes after checksum at offset N` | bytes follow the tag-10 field (covers a repeated tag 10) |
| `fix: BodyLength is not a non-negative integer` | tag 9 empty, non-digit, or wider than 9 digits |
| `fix: BodyLength mismatch: declared N actual M` | tag 9 differs from the body byte count |
| `fix: invalid CheckSum at offset N` | tag 10 is not exactly three digits in `000`-`255` |
| `fix: CheckSum mismatch: declared N computed M` | tag 10 is well formed but wrong |

Emit guard messages are listed in section 6.

## 8. Test plan

`tests/test_conformance.xi` (module `fix_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, prints `[PASS]`/`[FAIL]` and
`main` returns the failure count (0 = green). Fixtures F1-F6 are
high-bit-free ASCII messages with hand-computed BodyLength and CheckSum.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | minimal message | count 4, MsgType, BeginString, BodyLength 5, CheckSum 181 |
| t2 | NewOrderSingle | count 17, tag values, timestamps, decimal price, BodyLength 137 |
| t3 | execution report | MsgType 8, three-digit tags 150/31/32/14, BodyLength 86 |
| t4 | FIXT.1.1 | alternate begin string and custom tag 112 |
| t5 | duplicate tags | first/last differ for 58 and 55; value with `=` preserved |
| t6 | empty/punctuation values | `11=` is `Some("")`; absent 999 is `None`; pipes/carets/tildes survive |
| t7 | empty message struct | accessors inert on hand-built empty message |
| t8 | missing SOH | offsets 10 and 0 |
| t9 | non-digit tag | `3x` and empty tag, offset 14 |
| t10 | missing `=` | `35D`, offset 14 |
| t11 | duplicate 8/9 | exact messages |
| t12 | field order | first != 8, second != 9, empty BeginString |
| t13 | BodyLength errors | mismatch above and below, empty, non-digit, 10 digits |
| t14 | CheckSum format | 2 digits, 999, non-digit, 4 digits; offset 22 |
| t15 | CheckSum value | declared 182 and 0 against computed 181 |
| t16 | trailing bytes | `F1 + "X"` and a repeated `10=`; offset 26 |
| t17 | mandatory tags | missing 35, empty MsgType, missing 10, empty input |
| t18 | round trips | F1-F6 byte-exact; missing final SOH restored |
| t19 | emit recompute | stale `9=999`/`10=999` and `9=1`/`10=999` become correct frames |
| t20 | emit guards | misaligned, no tag 8, reserved byte, bad span, duplicate 8, tag 0 |

Element comparisons use `xiom.string.compare.str_compare`, never `==` on
`Str` values read from vectors (BUG 17).

## 9. Non-goals

- No session protocol: no Logon/Logout/Heartbeat state machine, no
  sequence numbers, no resend/gap handling, no timers.
- No repeating-group expansion: group count and entries stay ordinary
  fields; the caller interprets them.
- No data dictionary: field types, enumerations, lengths, required-field
  sets and conditional rules are not validated.
- No FIXML or any XML mapping, no FIXT session framing beyond the
  BeginString value being stored like any other field.
- No encryption, no compression, no checksum algorithms other than the
  FIX modulo-256 sum.
- No message building API beyond re-emitting a parsed/hand-built
  `FixMessage`; there is no field-editing surface in this version.
- No multi-message or batch parsing; one message per call.

## 10. Compiler / stdlib notes (XIOM v0.61.3)

Written under the same constraints as its sibling packages:

- free functions only -- no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]` dispatch, no `Vec[Float64]`;
- every byte read goes through `_byte_at`, which widens with
  `(string.byte_at(s, i) as Int) & 0xFF`; no `UInt8` is compared against an
  unmasked constant;
- `Vec[Int]`/`Vec[UInt8]` element reads are bound to typed locals before use
  (BUG-17 family), and every push on one parallel vector is mirrored on its
  siblings;
- `Ok`/`Err` for the struct-payload `Result[FixMessage, Str]` are constructed
  only in the leaf helpers `_ok_fix`/`_err_fix`; `fix_emit` uses the
  scalar-payload leaf helpers `_ok_out`/`_err_out`;
- output bytes are collected in a `Vec[UInt8]` and materialized once with
  `xiom.string.builder.sb_to_str`; every copied value byte is checked against
  NUL first, so the builder never receives a `0x00`;
- error messages are built from ASCII text and `_int_to_str` (which uses
  `sb_push_int`), so they are safe for the builder too;
- tests dispatch directly (`t1()` ... `t20()`); `Vec[fn]` indexed calls are
  not used, no `match` binds `mut`, every `match` is exhaustive, and the
  library uses no `match` at all.

## 11. Known limitations

- Values are opaque bytes: no charset conversion, no trimming, no escaping.
- Byte-exact round-trip requires the canonical framing already (`8` first,
  `9` second, `10` last with its SOH); `008=FIX.4.2` or a missing final SOH
  parse but canonicalize on emit.
- Errors carry offsets, not line/column positions (FIX has no lines).
- The 9-digit cap on tags, BodyLength and the checksum is deliberate: it
  keeps every accumulator inside `Int` and covers the standard tag space
  (tags are 1-4 digits in practice).
- `fix_emit` does not validate the BeginString value beyond "tag 8 exists
  and is unique"; `fix_parse` requires it non-empty but accepts any version
  spelling.
