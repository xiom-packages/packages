# xiom.audit -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.audit` (`src/audit.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free, in-memory hash-chained audit log:

- append entries to a chain seeded at 0 (`audit_append`),
- read entries/hashes and the head hash (`audit_entry`, `audit_hash`,
  `audit_head_hash`, `audit_len`),
- re-verify the full chain on demand (`audit_verify`,
  `audit_verify_prefix`),
- export the whole log as text (`audit_export`).

The module is deterministic: no clock, no randomness, no environment access,
no I/O. The caller stores, synchronizes and anchors the data.

## 2. Non-goals

- Cryptographic integrity: FNV-1a is a checksum, not a MAC.
- Authentication/authorization, secrets, signing, timestamps.
- Persistence, streaming, concurrency, deletion, compaction.
- Parsing the export back into a log (the export is a display/interchange
  format, not a round-trip serialization).
- Any FFI or registry integration.

## 3. Chain definition

```
h(-1) = 0
h(i)  = fnv1a( decimal(h(i-1)) + ":" + entry(i) )        for i >= 0
```

where:

- `decimal(x)` is the base-10 ASCII representation of the non-negative Int
  `x` (`xiom.convert.int_to_string`), with no padding or sign.
- `":"` is a single ASCII colon (0x3A), which separates the previous hash
  from the payload so that `("1","23:x")` and `("12","3:x")` cannot collide
  by concatenation.
- `entry(i)` is the raw UTF-8 payload of the entry (empty allowed).

Each `audit_append` returns `h(i)` for the new entry and stores both the entry
and its hash, so `hashes[i]` always corresponds to `entries[i]` for a log built
through the public API.

### 3.1 Hash function

FNV-1a 32-bit over the UTF-8 bytes of the payload (byte-exact; multi-byte
sequences are hashed as their UTF-8 bytes):

```
hash = 2166136261            // 0x811C9DC5, offset basis
for each byte b:
  hash = hash XOR b
  hash = (hash * 16777619) & 0xFFFFFFFF     // 16777619 = 0x01000193
```

Result range: `[0, 2^32-1]`, returned as a non-negative `Int` (never -1, so
-1 is available as an out-of-range sentinel elsewhere).

Known-answer vectors (pinned by the conformance suite):

| Input | Hash (decimal) | Hash (hex) |
|---|---|---|
| `""` | 2166136261 | 0x811C9DC5 |
| `"a"` | 3826002220 | 0xE40C292C |
| `"foobar"` | 3214735720 | 0xBF9CF968 |

## 4. API signatures

```xi
pub fn audit_hash_fnv1a(s: Str) -> Int
pub fn audit_new() -> AuditLog
pub fn audit_append(log: &mut AuditLog, entry: Str) -> Int
pub fn audit_len(log: &AuditLog) -> Int
pub fn audit_entry(log: &AuditLog, i: Int) -> Str
pub fn audit_hash(log: &AuditLog, i: Int) -> Int
pub fn audit_head_hash(log: &AuditLog) -> Int
pub fn audit_verify(log: &AuditLog) -> Bool
pub fn audit_verify_prefix(log: &AuditLog, up_to: Int) -> Bool
pub fn audit_export(log: &AuditLog) -> Str
```

`AuditLog` is `{ entries: Vec[Str]; hashes: Vec[Int]; }`. Fields are
implementation details: construct through `audit_new`, mutate through
`audit_append`.

### 4.1 Semantics

1. **Empty log.** `audit_new()` has `len == 0`, head `0`, `audit_verify`
   true, and exports as `""`.
2. **Out-of-range sentinels.** `audit_entry` returns `""` and `audit_hash`
   returns `-1` for negative or >= len indices (real hashes are never
   negative, so -1 is unambiguous).
3. **Head.** `audit_head_hash` is `hashes[len-1]`, or `0` when empty. Because
   0 is also the seed, an empty log and a hypothetical zero head are
   indistinguishable by design; callers should treat "empty" as a distinct
   case when anchoring.
4. **Verification.** `audit_verify` recomputes `h` from the seed over all
   entries and compares each recomputed value to the stored hash; it returns
   false immediately on the first mismatch and also when
   `entries.len() != hashes.len()` (a truncated or padded hash vector is
   itself tampering).
5. **Prefix verification.** `audit_verify_prefix(log, up_to)` verifies exactly
   the links `[0, up_to)`: `up_to` is clamped into `[0, len]` (negative means
   the vacuous empty prefix, which is true; values past the end mean the whole
   log). If the prefix extends past the stored hashes, the result is false.
   `audit_verify_prefix(log, len) == audit_verify(log)` holds for a log whose
   vectors are aligned.
6. **Append.** Appending never fails; entries may be empty strings, may
   repeat, and may contain any UTF-8 (including LF and `|`).
7. **Complexity.** Append/verify/export are O(total payload); the accessors
   are O(1).

## 5. Export grammar

The export is a display/interchange format; it is **not** parseable back into
a log in general (see limitations).

```
export   = ""                    ; empty log
         / line *( LF line )     ; no trailing LF
line     = seq "|" hash "|" escaped
seq      = "0" / nonzero-digit *digit        ; zero-based entry index
hash     = "0" / nonzero-digit *digit        ; decimal chain hash
escaped  = *( UTF8-byte / "\n" / "\|" )
```

- `seq` is the **zero-based** index, identical to the `audit_entry` index.
  A log with `n` entries has lines `0 .. n-1`.
- `hash` is the decimal chain hash with no padding.
- Inside `escaped`, an LF byte (0x0A) is rendered as the two characters
  `\` `n`, and a `|` byte (0x7C) as the two characters `\` `|`. All other
  bytes pass through verbatim. Backslashes are **not** escaped themselves.
- Lines are separated by a single LF; there is no trailing LF, so an empty
  log exports as `""`.

Example: log with entries `"a|b"` and `"line1\nline2"` exports as

```
0|<h0>|a\|b
1|<h1>|line1\nline2
```

where `<h0>`/`<h1>` are the decimal chain hashes.

## 6. Test plan

`tests/test_conformance.xi` (module `audit_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fnv1a `""` | offset basis 0x811C9DC5 |
| t2 | fnv1a `"a"` | 0xE40C292C vector |
| t3 | fnv1a `"foobar"` | 0xBF9CF968 vector |
| t4 | fnv1a determinism | same input same hash; near inputs differ; 32-bit range |
| t5 | fresh log | len 0, head 0, verify true, export `""` |
| t6 | append return value | equals the stored hash at the new index |
| t7 | chain determinism | two logs, same entries, same hashes |
| t8 | position sensitivity | same entry at different positions hashes differently |
| t9 | append loop | verify stays true after every append |
| t10 | entry tamper | mutating `entries[0]` makes verify false |
| t11 | middle-hash tamper | mutating `hashes[1]` breaks verification |
| t12 | hash-vector truncation | `pop()` on hashes fails whole-log verify |
| t13 | verify_prefix | exact `[0, up_to)`, clamping, tamper scope |
| t14 | head tracking | head equals last hash; content changes it |
| t15 | head movement | common prefix agrees; append moves head |
| t16 | export single line | `"0\|<hash>\|first"` |
| t17 | export multi-line | LF joins, zero-based seq |
| t18 | export escaping | `\|` for pipe, `\n` for LF, exact lengths |
| t19 | out-of-range accessors | `""` / `-1` sentinels on empty and non-empty logs |
| t20 | order preservation | entries readable in append order |
| t21 | 100-entry chain | verifies; head is last hash; first != last |
| t22 | mid-chain tamper | one mutated link fails verify; prefix before it passes |
| t23 | empty entry | `""` chains over payload `"0:"`; second append differs |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Known limitations

- FNV-1a 32-bit is not collision-resistant; forged chains are cheap to build.
- Tamper-evidence requires the head hash (or the export) to be anchored
  outside the writer's control; this module stores nothing externally.
- The export escaping is not injective for entries containing the literal
  sequences `\n` or `\|` (backslash is not escaped).
- No persistence, concurrency control, timestamps, deletion, or compaction.
- A zero head is ambiguous between "empty log" and a zero-valued hash.

## 8. Compiler / stdlib notes

Target toolchain: XIOM v0.61.3 (`COMPILER_VERSION`), stdlib `xiom.std`.
The module uses `xiom.string.byte_at` (raw byte accessor, `UInt8` cast to
`Int` before arithmetic) and `xiom.convert.int_to_string` for decimal
rendering. Tests route every text comparison through
`xiom.string.compare.str_compare` to avoid BUG 17, and read the log through
small `&mut`-taking helpers so that a `&local` call is never followed by a
`&mut local` call in the same function body (advisory E001), matching the
`xiom.retry` conformance idiom.
