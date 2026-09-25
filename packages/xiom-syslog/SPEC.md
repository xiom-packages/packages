# xiom.syslog -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.syslog` (`src/syslog.xi`). Pure XIOM, no FFI, no file or
network I/O.

## 1. Scope

An in-memory codec for one RFC 5424 syslog message:

- `syslog_parse` -- wire text -> `Result[SyslogMsg, Str]`,
- `syslog_build` -- `SyslogMsg` -> canonical wire text,
- `syslog_timestamp_valid` -- RFC 3339 / RFC 5424 TIMESTAMP validation,
- header accessors (`syslog_pri`, `syslog_facility`, `syslog_severity`,
  `syslog_version`, `syslog_timestamp`, `syslog_hostname`, `syslog_app_name`,
  `syslog_procid`, `syslog_msgid`, `syslog_msg`, `syslog_has_bom`,
  `syslog_has_msg`),
- structured-data accessors (`syslog_sd_count`, `syslog_sd_id`,
  `syslog_sd_param_count`, `syslog_sd_param_name`, `syslog_sd_param_value`,
  `syslog_sd_param`),
- `syslog_ok` -- parse-success predicate.

The codec answers "what does this message say, and how do I write it back?"
It performs no transport framing, no timestamp arithmetic, no timezone
conversion and no UTF-8 validation.

## 2. Non-goals

- **No transport:** no UDP/TCP, no octet-counting (`<n>...`), no
  LF/NUL-delimited stream splitting, no TLS, no file I/O.
- **No RFC 3164 legacy mode** and no free-form fallback.
- **No timestamp arithmetic:** TIMESTAMP stays a validated string; there is
  no epoch conversion, no `now()`, no duration math, no leap second (`:60`
  is rejected).
- **No UTF-8/Unicode validation or normalization** of MSG or PARAM-VALUE.
- **No facility/severity name tables**; values are numeric.
- **No message emission policies** (batching, retry, rate limiting).
- **No escaping policy beyond RFC 5424:** only `"`, `\` and `]` are special
  in a PARAM-VALUE.

## 3. Wire grammar

RFC 5424 section 6, restated exactly as implemented:

```
SYSLOG-MSG      = HEADER SP STRUCTURED-DATA [SP MSG]
HEADER          = PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME
                  SP PROCID SP MSGID
PRI             = "<" 1*3DIGIT ">"          ; value 0..191
VERSION         = NONZERO-DIGIT 0*2DIGIT    ; 1..999
TIMESTAMP       = NILVALUE / FULL-DATE "T" FULL-TIME
FULL-DATE       = 4DIGIT "-" 2DIGIT "-" 2DIGIT
FULL-TIME       = 2DIGIT ":" 2DIGIT ":" 2DIGIT [ "." 1*6DIGIT ] TIME-OFFSET
TIME-OFFSET     = "Z" / ( "+" / "-" ) 2DIGIT ":" 2DIGIT
HOSTNAME        = NILVALUE / 1*255PRINTUSASCII
APP-NAME        = NILVALUE / 1*48PRINTUSASCII
PROCID          = NILVALUE / 1*128PRINTUSASCII
MSGID           = NILVALUE / 1*32PRINTUSASCII
STRUCTURED-DATA = NILVALUE / 1*SD-ELEMENT
SD-ELEMENT      = "[" SD-ID *(SP SD-PARAM) "]"
SD-PARAM        = PARAM-NAME "=" %d34 PARAM-VALUE %d34
SD-NAME         = 1*32PRINTUSASCII            ; except "=", SP, "]", %d34
PARAM-VALUE     = UTF-8-STRING                ; '"', '\', ']' escaped
NILVALUE        = "-"
MSG             = *OCTET                      ; optional UTF-8 BOM prefix
PRINTUSASCII    = %d33-126
```

Additional byte-level decisions (each pinned by a test):

1. `MSG` may contain any byte except that it is sliced out of the input
   verbatim, including spaces, brackets, backslashes and newlines.
2. The optional `SP MSG` separator is significant and preserved: a message
   that ends at the structured-data section (`... -`) and one with an empty
   MSG (`... - `) are distinguished by `has_msg`.
3. No transport terminator is stripped: a trailing LF is MSG content when a
   MSG part follows the separator, and is rejected as trailing junk
   otherwise.

## 4. Data model

```xi
pub type SyslogMsg = {
  facility: Int;          // 0..23
  severity: Int;          // 0..7
  version: Int;           // 1..999
  timestamp: Str;         // validated TIMESTAMP text, "" for NILVALUE
  hostname: Str;          // "" for NILVALUE
  app_name: Str;          // "" for NILVALUE
  procid: Str;            // "" for NILVALUE
  msgid: Str;             // "" for NILVALUE
  msg: Str;               // MSG bytes without a leading UTF-8 BOM
  bom: Bool;              // MSG began with EF BB BF (stripped)
  has_msg: Bool;          // the optional SP MSG part was present
  sd_ids: Vec[Str];       // one SD-ID per element, wire order
  sd_param_elem: Vec[Int];   // element index of each parameter
  sd_param_names: Vec[Str];  // parameter names
  sd_param_values: Vec[Str]; // unescaped parameter values
}
```

Invariants produced by `syslog_parse` and required by `syslog_build`:

- `facility` 0..23, `severity` 0..7, `version` 1..999;
- `timestamp` is `""` or a valid RFC 5424 timestamp;
- header fields are `""` (NILVALUE) or 1..limit PRINTUSASCII bytes;
- `sd_param_names.len() == sd_param_values.len()` and every
  `sd_param_elem[p]` is in `0..sd_ids.len()`;
- every `sd_ids[i]` and `sd_param_names[p]` is a valid SD-NAME.

`Vec[StructType]` is unsupported in this compiler, so elements and
parameters are stored in parallel homogeneous vectors. Parameters are kept
in wire order inside their element; building re-groups by element index,
which preserves the relative order of an element's parameters.

## 5. Parsing semantics

1. **PRI.** `<` then 1..3 ASCII digits then `>`; the value must be 0..191.
   `facility = value / 8`, `severity = value % 8`. Leading zeros are
   accepted (`<034>` -> PRI 34).
2. **VERSION.** The byte run between `>` and the next SP (or end). It must
   be 1..3 digits with a nonzero first digit. The next field is required, so
   a missing SP is `missing field: TIMESTAMP`.
3. **TIMESTAMP.** The run up to the next SP. `-` becomes `""`; anything else
   is validated with the rules of section 6. An empty field is
   `missing field: TIMESTAMP`.
4. **HOSTNAME / APP-NAME / PROCID / MSGID.** Each is the run up to the next
   SP; `-` becomes `""`; an empty run or a run truncated by end of input is
   `missing field: <NAME>` (MSGID truncation is `truncated message`);
   values must be PRINTUSASCII and within the RFC limits (255/48/128/32).
   Length is reported before charset.
5. **STRUCTURED-DATA.** After MSGID, one SP is required, then either `-`
   (zero elements) or one or more `[...]` elements. After the section the
   next byte must be SP or end of input.
6. **MSG.** When a SP follows the SD section, everything after it is MSG. A
   leading EF BB BF is consumed and flagged; the remainder is copied
   verbatim. `has_msg` is true whenever the separator was present.
7. **No trimming** is applied anywhere; trailing bytes that are not SP are
   errors after the SD section.

## 6. TIMESTAMP validation (`syslog_timestamp_valid`)

`syslog_timestamp_valid(s)` is true only for the full form

```
yyyy "-" mm "-" dd "T" hh ":" mi ":" ss [ "." 1*6DIGIT ] ( "Z" | ( "+" | "-" ) hh ":" mi )
```

with: `yyyy` four digits (0000..9999 accepted), `mm` 01..12, `dd`
01..(calendar length of that month in that year, with Gregorian leap rules),
`hh` 00..23, `mi` 00..59, `ss` 00..59, fraction 1..6 digits, offset hour
00..23 and offset minute 00..59. Uppercase `T` and `Z` only. `-00:00` (RFC
3339 "offset unknown") is accepted. `""`, `-` and any trailing byte make it
false. No arithmetic is performed: this is a shape and range check only.

## 7. Structured-data semantics

- An element is `[` SD-ID then zero or more `SP param="value"` then `]`.
- **SD-NAME** (SD-ID and PARAM-NAME): 1..32 bytes, PRINTUSASCII, none of
  `=`, SP, `]`, `"`. Empty, over-long or otherwise illegal names are errors.
- A parameter name must be followed by `=`. A space or `]` before `=` is
  `bad param name`.
- A value opens with `"`. Inside it, `\"` -> `"`, `\\` -> `\`, `\]` -> `]`.
  Any other `\` escape (including a trailing `\`) is `bad param escape`; a
  raw `]` is `bad param value`; end of input before the closing `"` is
  `bad param quote`.
- After the closing `"`, only SP (another parameter) or `]` (end of element)
  may follow; anything else is `bad structured data`.
- Elements repeat while the next byte is `[`; parameters of an element
  retain wire order. Interleaving elements is impossible on the wire, so
  parse output is always grouped.

## 8. Error catalog

All messages start with `syslog: `. Parse errors:

| Message | Trigger |
|---|---|
| `syslog: missing PRI` | empty input, or the first byte is not `<`. |
| `syslog: bad PRI` | PRI body empty, non-digit, longer than 3 digits, or no `>` after it. |
| `syslog: PRI out of range: <digits>` | PRI value > 191. |
| `syslog: bad version: <text>` | the version run is not 1..3 digits with a nonzero first digit. |
| `syslog: missing field: TIMESTAMP` / `HOSTNAME` / `APP-NAME` / `PROCID` / `MSGID` | the field is empty, or the input ends before the field's SP. |
| `syslog: truncated message` | the input ends at MSGID (no SP + SD), or right after that SP. |
| `syslog: bad TIMESTAMP: <text>` | non-NILVALUE timestamp failing section 6. |
| `syslog: bad HOSTNAME: <text>` (and APP-NAME/PROCID/MSGID) | a byte outside PRINTUSASCII (33-126). |
| `syslog: HOSTNAME too long` (and APP-NAME/PROCID/MSGID) | over 255/48/128/32 bytes. |
| `syslog: bad structured data` | SD starts with neither `-` nor `[`; `-` followed by a non-SP; junk after the SD section; junk after a closing param quote. |
| `syslog: bad SD-ID: <text>` | SD-ID empty, over 32 bytes, or containing a byte outside PRINTUSASCII or one of `=`, SP, `]`, `"`. |
| `syslog: bad param name: <text>` | same rule for a parameter name, or the name is not terminated by `=`. |
| `syslog: bad param quote` | a parameter value does not open with `"`, or its closing `"` is missing. |
| `syslog: bad param value` | an unescaped `]` inside a parameter value. |
| `syslog: bad param escape` | `\` at end of input, or `\` followed by anything but `"`, `\`, `]`. |
| `syslog: unterminated structured data` | an element `[` has no closing `]` (end of input, or a non-`]` byte where `]` is required). |

Build errors:

| Message | Trigger |
|---|---|
| `syslog: facility out of range` | `facility` outside 0..23. |
| `syslog: severity out of range` | `severity` outside 0..7. |
| `syslog: bad version: <n>` | `version` outside 1..999. |
| `syslog: bad TIMESTAMP: <text>` | non-empty `timestamp` failing section 6. |
| `syslog: bad <NAME>: <text>` / `syslog: <NAME> too long` | header field charset / length violations (same names as parse). |
| `syslog: bad SD-ID: <text>` | invalid `sd_ids[i]`. |
| `syslog: bad param name: <text>` | invalid `sd_param_names[p]`. |
| `syslog: bad structured data: inconsistent layout` | `sd_param_names.len() != sd_param_values.len()`, or a `sd_param_elem[p]` outside `0..sd_ids.len()`. |

## 9. Build and round-trip

`syslog_build` emits, in order: `<` PRI `>` VERSION SP TIMESTAMP SP HOSTNAME
SP APP-NAME SP PROCID SP MSGID SP SD, then `SP MSG` when `has_msg` is true or
`msg` is non-empty or `bom` is true (the BOM is re-emitted first).

Canonicalization rules:

- `""` header fields and an empty `sd_ids` emit `-` (NILVALUE);
- PRI is rebuilt from `facility`/`severity`, so leading zeros disappear
  (`<034>` -> `<34>`);
- `version` is emitted in decimal without leading zeros;
- parameter values are escaped (`"` -> `\"`, `\` -> `\\`, `]` -> `\]`);
- parameters are emitted grouped by element index, preserving relative
  order.

Round-trip guarantee: for every `text` accepted by `syslog_parse`,
`syslog_build(syslog_parse(text))` returns `Ok` and reproduces `text` byte
for byte, except that PRI leading zeros are removed. The optional `SP MSG`
separator, empty MSG, BOM and every escape are reproduced exactly.

## 10. API signatures

```xi
pub fn syslog_parse(text: Str) -> Result[SyslogMsg, Str]
pub fn syslog_build(m: &SyslogMsg) -> Result[Str, Str]
pub fn syslog_ok(text: Str) -> Bool
pub fn syslog_timestamp_valid(s: Str) -> Bool
pub fn syslog_pri(m: &SyslogMsg) -> Int
pub fn syslog_facility(m: &SyslogMsg) -> Int
pub fn syslog_severity(m: &SyslogMsg) -> Int
pub fn syslog_version(m: &SyslogMsg) -> Int
pub fn syslog_timestamp(m: &SyslogMsg) -> Str
pub fn syslog_hostname(m: &SyslogMsg) -> Str
pub fn syslog_app_name(m: &SyslogMsg) -> Str
pub fn syslog_procid(m: &SyslogMsg) -> Str
pub fn syslog_msgid(m: &SyslogMsg) -> Str
pub fn syslog_msg(m: &SyslogMsg) -> Str
pub fn syslog_has_bom(m: &SyslogMsg) -> Bool
pub fn syslog_has_msg(m: &SyslogMsg) -> Bool
pub fn syslog_sd_count(m: &SyslogMsg) -> Int
pub fn syslog_sd_id(m: &SyslogMsg, i: Int) -> Str
pub fn syslog_sd_param_count(m: &SyslogMsg, elem: Int) -> Int
pub fn syslog_sd_param_name(m: &SyslogMsg, elem: Int, i: Int) -> Str
pub fn syslog_sd_param_value(m: &SyslogMsg, elem: Int, i: Int) -> Str
pub fn syslog_sd_param(m: &SyslogMsg, elem: Int, name: Str) -> Option[Str]
```

Out-of-range element/parameter indexes return `""` / `0` / `None`; the
accessors never fail. `syslog_parse` is O(len(text)); `syslog_build` is
O(field bytes); accessors are O(elements + parameters).

## 11. Test matrix (`tests/test_conformance.xi`, 24 checks)

| # | Check | Semantics pinned |
|---|---|---|
| t1 | RFC 5424 example | header accessors, 3 SD params, BOM flag, MSG, lookup |
| t2 | PRI boundaries | `<0>`, `<8>`, `<191>`; facility/severity/pri; build boundaries |
| t3 | PRI errors | missing, bad, 4-digit, non-digit, 192/999 out of range |
| t4 | VERSION | 0, `01`, `1000`, non-digit, empty, truncation; `999` accepted |
| t5 | missing fields | TIMESTAMP/HOSTNAME/APP-NAME/PROCID/MSGID empty/truncated, truncation |
| t6 | valid timestamps | `Z`, `.1`, `.123456`, `+02:00`, `-00:00`, leap days, year 0000 |
| t7 | invalid timestamps | month 13, Feb 30, 1900-02-29, hour 24, minute/second 60, lowercase, 7 frac digits, bad offsets, junk; parse error |
| t8 | NILVALUE fields | all header fields `""`, `has_msg` false, exact round-trip |
| t9 | limits | 255/48/128/32 accepted, +1 rejected; tab rejected |
| t10 | SD basics | 3-param element, `[id]`, `[id a=""]`, lookup, None |
| t11 | multiple elements | order, per-element counts, cross-element lookup |
| t12 | escapes | `\"`, `\\`, `\]` decode; exact re-encode |
| t13 | SD errors | unterminated, quote, value `]`, escape, name, SD-ID, junk |
| t14 | MSG/BOM | spaces kept, odd bytes, BOM-only, BOM+text, absent MSG, trailing LF |
| t15 | round-trips | 8 fixtures, byte-exact |
| t16 | canonical build | full wire text; NILVALUE SD; MSG-less form |
| t17 | build errors | facility/severity/version/timestamp/hostname/SD-ID/name/layout |
| t18 | accessor bounds | `""`/`0`/`None` for out-of-range element/param/index |
| t19 | SD NILVALUE | `-` parses to 0 elements; `[id]` build exact |
| t20 | `syslog_ok` | agrees with `syslog_parse`, including malformed input |
| t21 | PRI leading zeros | `<034>` parses as 34 and rebuilds as `<34>` |
| t22 | param content | spaces and `=` kept; escaped bracket; name charset |
| t23 | build grouping | interleaved construction groups by element index |
| t24 | boundaries | offset extremes, Apr 31, month/day 00, NILVALUE timestamp |

All Str comparisons go through `xiom.string.compare.str_compare` (BUG 17:
`==` on a `Str` read from a `Vec[Str]` element lowers to a pointer
comparison). Tests dispatch directly `t1()`..`t24()`; no `Vec[fn]` table.

## 12. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only: no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]`, no `Vec[Float64]`; structured data is flat parallel vectors.
- `Ok`/`Err` for every `Result[...]` are constructed only in the tiny leaf
  helpers `_ok_msg`/`_err_msg`/`_ok_str`/`_err_str` (constructing a Result
  inside a larger function miscompiles).
- `Str` values read from `Vec[Str]` elements are always bound to typed
  locals before use, and compared with `str_compare`, never `==`.
- `byte_at` results are widened with `as Int` and masked with `& 0xFF`
  before any comparison with a byte >= 128.
- Surprise found while porting: `239u8 as Int` sign-extends to `-17`, so
  the BOM check compares `(byte_at(...) as Int) & 0xFF` against
  `(_SYSLOG_BOM0 as Int) & 0xFF`. Byte pushes (`out.push(239u8)`) are
  unaffected.
- Output bytes accumulate in a `Vec[UInt8]` and are materialized once with
  `xiom.string.builder.sb_to_str`; only local vectors are passed by
  reference (a struct-field `&Vec[UInt8]` argument is not trusted).

## 13. Known limitations

- One message per call: no batching and no stream framing.
- No RFC 3164, no PRI-only message, no NILVALUE-only message.
- TIMESTAMP is never converted or compared; callers needing ordering must
  parse the text themselves.
- MSG and PARAM-VALUE bytes are not validated as UTF-8 (BOM detection is
  the only encoding-aware step).
- An unescaped `]` in a PARAM-VALUE is an error rather than being accepted
  leniently (RFC 5424 requires the escape).
- Errors identify the offending text but carry no byte offset.
