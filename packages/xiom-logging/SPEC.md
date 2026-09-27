# xiom.logging -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.logging` (`src/logging.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope and model

A small, dependency-free decoder for syslog message structure:

- `log_detect` -- format detection from the byte after PRI,
- `log3164_parse` -- RFC 3164 (BSD syslog) line -> `Result[Log3164, Str]`,
- `log5424_parse` -- RFC 5424 message -> `Result[Log5424, Str]`,
- `log5424_timestamp_valid` / `log5424_timestamp_parse` -- RFC 3339
  timestamps to structured fields,
- PRI/facility/severity tables (`log_facility_name`, `log_severity_name`,
  `log_facility_code`, `log_severity_code`, `log_pri_make`, `log_pri_valid`,
  `log_pri_facility`, `log_pri_severity`),
- field accessors (section 9).

Everything is byte-oriented and stateless: nothing allocates a connection
object, every function works on `Str` input, and malformed text yields a
deterministic `Err` or an empty value, never a crash. Non-goals: transports
(UDP/TCP/file/journald/log rotation), encoding or rendering, timezone
conversion, UTF-8 validation, message framing and clock access.

## 2. Data model

```xi
pub type LogTimestamp = {
  year: Int;        // 0 when present == false
  month: Int;       // 1..12
  day: Int;         // 1..(calendar length for year/month)
  hour: Int;        // 0..23
  minute: Int;      // 0..59
  second: Int;      // 0..59
  frac: Str;        // fractional-second digits without the dot ("" absent)
  offset_min: Int;  // signed UTC offset in minutes (0 for "Z" and "-00:00")
  present: Bool;    // false for the NILVALUE "-"
}

pub type Log3164 = {
  facility: Int;    // pri / 8   (0..23)
  severity: Int;    // pri % 8   (0..7)
  month: Int;       // 1..12
  day: Int;         // 1..31
  hour: Int;        // 0..23
  minute: Int;      // 0..59
  second: Int;      // 0..59
  timestamp: Str;   // raw "Mmm dd hh:mm:ss" (15 bytes, no year)
  hostname: Str;
  tag: Str;         // alphanumeric, without the optional "[pid]"
  pid: Str;         // digits, "" when absent
  has_pid: Bool;
  content: Str;     // bytes after "TAG:" (one optional SP skipped)
  has_content: Bool;
  consumed: Int;    // byte length of the line (up to the first CR/LF)
  ts_at: Int;       // byte offsets of the field starts in the input
  host_at: Int;
  tag_at: Int;
  content_at: Int;
}

pub type Log5424 = {
  facility: Int;    // pri / 8 (0..23)
  severity: Int;    // pri % 8 (0..7)
  version: Int;     // 1..999
  timestamp: Str;   // raw RFC 3339 text; "" for NILVALUE
  ts_present: Bool; // false for NILVALUE
  ts_year: Int; ts_month: Int; ts_day: Int;      // structured timestamp
  ts_hour: Int; ts_minute: Int; ts_second: Int;
  ts_frac: Str;
  ts_offset_min: Int;
  hostname: Str;    // NILVALUE "-" is stored as ""
  app_name: Str;
  procid: Str;
  msgid: Str;
  msg: Str;         // excludes a leading UTF-8 BOM
  bom: Bool;        // MSG began with EF BB BF
  has_msg: Bool;    // the optional SP MSG part was present
  sd_ids: Vec[Str];         // one SD-ID per element
  sd_param_elem: Vec[Int];  // owning element index, per parameter
  sd_param_names: Vec[Str]; // PARAM-NAME, per parameter
  sd_param_values: Vec[Str];// unescaped PARAM-VALUE, per parameter
  sd_param_val_at: Vec[Int]; // raw wire value span start, per parameter
  sd_param_val_len: Vec[Int];// raw wire value span length, per parameter
}
```

Invariants (maintained by the parsers): `sd_param_elem`, `sd_param_names`,
`sd_param_values`, `sd_param_val_at` and `sd_param_val_len` have equal
length; `sd_param_elem[p]` indexes `sd_ids`; `has_pid` implies `pid != ""`;
`ts_present` is false only when `timestamp == ""`. `Vec[StructType]` is
unsupported in this compiler, so structured data is stored as parallel
homogeneous vectors instead of a list of element/parameter structs.

## 3. PRI and the facility/severity tables

Grammar: `PRI = "<" 1*3DIGIT ">"`, value 0..191. A 4th digit, a non-digit, a
missing `<` or `>` and values 192..999 are rejected. Leading zeros are
accepted (`<007>` is 7). Facility = `pri / 8`, severity = `pri % 8`.

| Facility | Name | Facility | Name | Facility | Name |
|---|---|---|---|---|---|
| 0 | `kern` | 8 | `uucp` | 16 | `local0` |
| 1 | `user` | 9 | `cron` | 17 | `local1` |
| 2 | `mail` | 10 | `authpriv` | 18 | `local2` |
| 3 | `daemon` | 11 | `ftp` | 19 | `local3` |
| 4 | `auth` | 12 | `ntp` | 20 | `local4` |
| 5 | `syslog` | 13 | `audit` | 21 | `local5` |
| 6 | `lpr` | 14 | `alert` | 22 | `local6` |
| 7 | `news` | 15 | `clock` | 23 | `local7` |

| Severity | Name |
|---|---|
| 0 | `emerg` |
| 1 | `alert` |
| 2 | `crit` |
| 3 | `err` |
| 4 | `warning` |
| 5 | `notice` |
| 6 | `info` |
| 7 | `debug` |

`log_facility_name` / `log_severity_name` return `""` outside 0..23 / 0..7.
`log_facility_code` / `log_severity_code` compare byte-exactly and
case-sensitively and return `Err("logging: unknown facility: <name>")` /
`Err("logging: unknown severity: <name>")` otherwise.
`log_pri_make(facility, severity)` returns `facility * 8 + severity` or
`Err("logging: facility out of range: <f>")` /
`Err("logging: severity out of range: <s>")`. `log_pri_valid` is the
0..191 test; `log_pri_facility` / `log_pri_severity` return -1 outside
0..191.

## 4. RFC 3164 grammar and parsing decisions

```
message   = PRI timestamp SP hostname SP tag [ "[" pid "]" ] ":" [ SP ] [ content ] [ break ]
PRI       = "<" 1*3DIGIT ">"                     ; 0..191
timestamp = month SP day SP hh ":" mm ":" ss     ; exactly 15 bytes
month     = "Jan" / "Feb" / "Mar" / "Apr" / "May" / "Jun" /
            "Jul" / "Aug" / "Sep" / "Oct" / "Nov" / "Dec"
day       = 2DIGIT / SP DIGIT                    ; "01".."31" or " 1".." 9"
hh/mm/ss  = 2DIGIT                               ; hh 00-23, mm/ss 00-59
hostname  = 1*255 PRINTUSASCII                   ; %d33-126, no SP
tag       = 1*32 ( ALPHA / DIGIT )
pid       = 1*10 DIGIT
break     = CRLF / LF / CR
```

Decisions (each is covered by the conformance suite):

1. **One line.** The input is truncated at the first CR or LF; bytes after
   it are ignored and `consumed` records the line byte length, so callers can
   walk a buffer by skipping the break after `consumed`.
2. **Fixed timestamp.** Exactly 15 bytes; a shorter tail is
   `bad TIMESTAMP at <end of input>`. Month names are case-sensitive and
   matched against the table (no numeric months, no lowercase variants).
3. **Day padding.** The day field is two characters: space + digit for 1..9
   (` 1`) or two digits (`12`, `01`). ` 0`, `00`, `32`+ and mixed bytes are
   rejected.
4. **No year, no timezone.** The year is not on the wire and is not
   invented; `month`, `day`, `hour`, `minute`, `second` are stored as Ints
   and the raw 15-byte text as `timestamp`.
5. **Hostname.** 1..255 printable ASCII bytes (`%d33-126`), terminated by
   SP. Empty, over-long (`HOSTNAME too long`) and non-printable
   (`bad HOSTNAME`) hostnames are rejected. There is no NILVALUE in 3164.
6. **TAG.** 1..32 alphanumeric bytes (letters and digits only; `-`, `_` and
   `.` are rejected). A zero-length tag is `bad TAG`; more than 32 bytes is
   `TAG too long`.
7. **pid.** `[` digits `]` with 1..10 digits; empty, non-digit, over-long or
   unterminated pid parts are `bad pid`. A tag without `[pid]` keeps
   `pid == ""` and `has_pid == false`.
8. **Separator.** The tag/pid part must be followed by `:`; missing it is
   `bad TAG at <offset>`.
9. **Content.** After `:` exactly one optional SP is skipped (it is the
   conventional separator); the remaining bytes up to the line end are the
   content, kept byte-exact. `TAG:` (nothing after, or only the break)
   yields `has_content == false`; `TAG: x` and `TAG:x` both yield `x`;
   `TAG:  x` keeps the second space (content ` x`).
10. **Offsets.** `ts_at`, `host_at`, `tag_at`, `content_at` are byte offsets
    of the field starts; `consumed` is the line length.
11. **Strictness.** A message without hostname or without `TAG:` is
    rejected; there is no lenient fallback for vendor formats.

## 5. RFC 5424 grammar and parsing decisions

```
SYSLOG-MSG      = HEADER SP STRUCTURED-DATA [ SP MSG ]
HEADER          = PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME
                  SP PROCID SP MSGID
PRI             = "<" 1*3DIGIT ">"          ; value 0..191
VERSION         = NONZERO-DIGIT 0*2DIGIT    ; 1..999
TIMESTAMP       = NILVALUE / FULL-DATE "T" FULL-TIME
NILVALUE        = "-"
FULL-DATE       = year "-" month "-" day    ; 4DIGIT "-" 2DIGIT "-" 2DIGIT
FULL-TIME       = hh ":" mm ":" ss [ "." 1*6DIGIT ]
                ; hh 00-23, mm/ss 00-59, calendar-checked day
time-offset     = "Z" / ("+" / "-") hh ":" mm
STRUCTURED-DATA = NILVALUE / 1*SD-ELEMENT
SD-ELEMENT      = "[" SD-ID *(SP SD-PARAM) "]"
SD-PARAM        = PARAM-NAME "=" %d34 PARAM-VALUE %d34
SD-ID           = SD-NAME
PARAM-NAME      = SD-NAME
SD-NAME         = 1*32 PRINTUSASCII except "=", SP, "]", %d34
PARAM-VALUE     = 1*(UTF-8-STRING / %d34 / %d92 / %d93)
                  ; '"', '\' and ']' are backslash-escaped on the wire
MSG             = *OCTET, optionally prefixed with a UTF-8 BOM
```

Header field limits (bytes): HOSTNAME 255, APP-NAME 48, PROCID 128,
MSGID 32. A field is either NILVALUE `-` (stored as `""`) or 1..limit
PRINTUSASCII bytes (`%d33-126`).

Decisions:

1. **VERSION.** 1..3 digits with a nonzero first digit; `0`, `01`, empty,
   `1000` and non-digits are `bad version at <start>`. Values 1..999 parse;
   the codec does not interpret versions other than structurally.
2. **TIMESTAMP.** NILVALUE `-` sets `ts_present == false` and all-zero
   fields; otherwise the text is parsed per section 7. Uppercase `T` and
   `Z` only; `-00:00` is accepted as offset 0.
3. **Header fields.** Scanned as SP-terminated runs; the empty run is
   `missing <field>`, over-long is `<field> too long`, a non-printable byte
   is `bad <field>`. A header field without its terminating SP is
   `missing <field>` (or `truncated message` for MSGID, which must be
   followed by SP + structured data).
4. **Structured data.** `-` is the NILVALUE section (0 elements) and must be
   followed by SP or end; otherwise one or more `[` elements follow with no
   separator between them. A byte that is neither `-` nor `[` is
   `bad structured data`.
5. **SD elements.** An element must hold a valid 1..32-byte SD-ID, then any
   number of `SP PARAM-NAME "=" '"' value '"'` parameters, then `]`.
6. **Escapes.** Inside a PARAM-VALUE, `\"` -> `"`, `\\` -> `\`, `\]` -> `]`;
   any other escape is `bad param escape` at the backslash, an unescaped `]`
   is `bad param value`, and an unterminated value is `bad param quote`.
   Decoded bytes are stored in `sd_param_values`; the raw wire span (escapes
   intact) is stored as `sd_param_val_at` / `sd_param_val_len` and can be
   sliced with `log5424_sd_param_value_wire`.
7. **MSG.** The optional `SP MSG` part sets `has_msg`; a leading UTF-8 BOM
   (`EF BB BF`) is stripped and flagged by `bom`; the remaining bytes
   (including any trailing CR/LF -- 5424 has no line framing here) are
   stored verbatim in `msg`.
8. **NUL bytes.** A parameter value containing `0x00` is not supported by
   the builder materialization used for output strings; wire input is
   expected to be NUL-free text.

## 6. Timestamp validation and structured fields

`log5424_timestamp_valid(s)` and `log5424_timestamp_parse(s)` implement the
RFC 3339 subset of section 5: 4-digit year, month 01-12, day 01-`calendar
length` (proleptic Gregorian leap years included), `T`, hour 00-23, minute
00-59, second 00-59, 1..6 fraction digits, and `Z` / `+HH:MM` / `-HH:MM`
with offset hour 00-23 and offset minute 00-59. Leap seconds (`:60`) are
rejected. `frac` keeps the digits without the dot; `offset_min` is the
signed offset in minutes (150 for `+02:30`, -420 for `-07:00`, 0 for `Z`
and for `-00:00`). Failure offsets are relative to the timestamp text and
point at the offending byte (section 10).

## 7. Auto-detection

`log_detect(text)` parses the PRI prefix, then inspects the byte after `>`:

- a digit run of 1..3 digits followed by SP -> `"rfc5424"`,
- an ASCII letter -> `"rfc3164"`,
- anything else (malformed PRI, no byte, digit run not closed by SP,
  4+ digits) -> `""`.

Detection is shape-only and does not validate the rest of the message, so a
detected text may still fail its parser; `dispatch_ok`-style callers should
check the parse result.

## 8. API contract

```xi
pub fn log_detect(text: Str) -> Str
pub fn log3164_parse(text: Str) -> Result[Log3164, Str]
pub fn log5424_parse(text: Str) -> Result[Log5424, Str]
pub fn log3164_ok(text: Str) -> Bool
pub fn log5424_ok(text: Str) -> Bool
pub fn log_facility_name(facility: Int) -> Str
pub fn log_severity_name(severity: Int) -> Str
pub fn log_facility_code(name: Str) -> Result[Int, Str]
pub fn log_severity_code(name: Str) -> Result[Int, Str]
pub fn log_pri_make(facility: Int, severity: Int) -> Result[Int, Str]
pub fn log_pri_valid(pri: Int) -> Bool
pub fn log_pri_facility(pri: Int) -> Int
pub fn log_pri_severity(pri: Int) -> Int
pub fn log5424_timestamp_valid(s: Str) -> Bool
pub fn log5424_timestamp_parse(s: Str) -> Result[LogTimestamp, Str]
pub fn log5424_timestamp(m: &Log5424) -> LogTimestamp
pub fn log5424_has_timestamp(m: &Log5424) -> Bool
pub fn log3164_pri(m: &Log3164) -> Int
pub fn log3164_facility(m: &Log3164) -> Int
pub fn log3164_severity(m: &Log3164) -> Int
pub fn log3164_month(m: &Log3164) -> Int
pub fn log3164_day(m: &Log3164) -> Int
pub fn log3164_hour(m: &Log3164) -> Int
pub fn log3164_minute(m: &Log3164) -> Int
pub fn log3164_second(m: &Log3164) -> Int
pub fn log3164_timestamp(m: &Log3164) -> Str
pub fn log3164_hostname(m: &Log3164) -> Str
pub fn log3164_tag(m: &Log3164) -> Str
pub fn log3164_pid(m: &Log3164) -> Str
pub fn log3164_has_pid(m: &Log3164) -> Bool
pub fn log3164_content(m: &Log3164) -> Str
pub fn log3164_has_content(m: &Log3164) -> Bool
pub fn log3164_consumed(m: &Log3164) -> Int
pub fn log5424_pri(m: &Log5424) -> Int
pub fn log5424_facility(m: &Log5424) -> Int
pub fn log5424_severity(m: &Log5424) -> Int
pub fn log5424_version(m: &Log5424) -> Int
pub fn log5424_timestamp_text(m: &Log5424) -> Str
pub fn log5424_hostname(m: &Log5424) -> Str
pub fn log5424_app_name(m: &Log5424) -> Str
pub fn log5424_procid(m: &Log5424) -> Str
pub fn log5424_msgid(m: &Log5424) -> Str
pub fn log5424_msg(m: &Log5424) -> Str
pub fn log5424_has_bom(m: &Log5424) -> Bool
pub fn log5424_has_msg(m: &Log5424) -> Bool
pub fn log5424_sd_count(m: &Log5424) -> Int
pub fn log5424_sd_id(m: &Log5424, i: Int) -> Str
pub fn log5424_sd_param_count(m: &Log5424, elem: Int) -> Int
pub fn log5424_sd_param_name(m: &Log5424, elem: Int, i: Int) -> Str
pub fn log5424_sd_param_value(m: &Log5424, elem: Int, i: Int) -> Str
pub fn log5424_sd_param_value_at(m: &Log5424, elem: Int, i: Int) -> Int
pub fn log5424_sd_param_value_len(m: &Log5424, elem: Int, i: Int) -> Int
pub fn log5424_sd_param_value_wire(m: &Log5424, text: Str, elem: Int, i: Int) -> Str
pub fn log5424_sd_param(m: &Log5424, elem: Int, name: Str) -> Option[Str]
```

Accessor semantics: out-of-range indices return `""` (or 0 / -1 for the
numeric span accessors as documented in the source); `log5424_sd_param`
returns the first parameter with the exact (case-sensitive) name, or `None`.
`log5424_sd_param_value_wire(m, text, elem, i)` slices the raw value span out
of the original input so the still-escaped wire bytes are recoverable
byte-exactly.

## 9. Error catalog

All parse failures are `Err("logging: <reason> at <offset>")`, deterministic
and offset-carrying. Non-parse helpers use their own fixed messages.

| Reason | Function | Trigger (offset) |
|---|---|---|
| `missing PRI` | both parsers | empty text or first byte not `<` (0) |
| `bad PRI` | both parsers | no digit after `<` (1), a 4th digit, a non-digit or missing `>` (at that byte) |
| `PRI out of range` | both parsers | value > 191 (1) |
| `bad version` | `log5424_parse` | version run not 1..3 digits with nonzero first digit (at the run start) |
| `missing TIMESTAMP` | `log5424_parse` | no SP after VERSION (end), no SP after the field (end), empty field (field start) |
| `bad TIMESTAMP` | both parsers / `log5424_timestamp_parse` | 3164: short tail (end), month/separator/day/time byte (at the byte); 5424: failing RFC 3339 piece (at the absolute byte) |
| `missing HOSTNAME` | both parsers | 3164: no SP before it (end) or empty (start); 5424: empty or no SP after it (end) |
| `HOSTNAME too long` | both parsers | > 255 bytes (field start) |
| `bad HOSTNAME` | both parsers | non-printable byte (field start) |
| `missing APP-NAME` | `log5424_parse` | empty field or no SP after it (end) |
| `APP-NAME too long` / `bad APP-NAME` | `log5424_parse` | > 48 bytes / non-printable (field start) |
| `missing PROCID` | `log5424_parse` | empty field or no SP after it (end) |
| `PROCID too long` / `bad PROCID` | `log5424_parse` | > 128 bytes / non-printable (field start) |
| `missing MSGID` | `log5424_parse` | empty field (field start) |
| `MSGID too long` / `bad MSGID` | `log5424_parse` | > 32 bytes / non-printable (field start) |
| `truncated message` | `log5424_parse` | MSGID without a following SP, or no structured data at all (end) |
| `bad structured data` | `log5424_parse` | first SD byte neither `-` nor `[`; `-` not followed by SP; junk after an element; junk after the last element |
| `bad SD-ID` | `log5424_parse` | empty, > 32 bytes or forbidden byte in SD-ID (id start) |
| `bad param name` | `log5424_parse` | missing `=`, empty/invalid PARAM-NAME (name start) |
| `bad param quote` | `log5424_parse` | missing opening quote (at byte), unterminated value (end) |
| `bad param escape` | `log5424_parse` | backslash not followed by `"`, `\`, `]`, or a trailing backslash (at the backslash) |
| `bad param value` | `log5424_parse` | unescaped `]` inside a value (at the byte) |
| `unterminated structured data` | `log5424_parse` | element not closed by `]` before end (at the byte/end) |
| `missing TAG` | `log3164_parse` | no SP between HOSTNAME and TAG (end) |
| `bad TAG` | `log3164_parse` | empty/zero-length alphanumeric run (tag start), missing `:` (at the byte) |
| `TAG too long` | `log3164_parse` | > 32 bytes (tag start) |
| `bad pid` | `log3164_parse` | empty pid, > 10 digits or missing `]` (at the byte) |

Fixed non-parse errors:

| Message | Function |
|---|---|
| `logging: unknown facility: <name>` | `log_facility_code` |
| `logging: unknown severity: <name>` | `log_severity_code` |
| `logging: facility out of range: <n>` | `log_pri_make` (n < 0 or n > 23) |
| `logging: severity out of range: <n>` | `log_pri_make` (n < 0 or n > 7) |

## 10. Test matrix (`tests/test_conformance.xi`, 22 checks)

| # | Check | Semantics pinned |
|---|---|---|
| t1 | PRI make/decode | corners 0/7/8/76/191, out-of-range errors, `log_pri_valid`, -1 decodes |
| t2 | PRI parse bounds | `<0>`, `<191>`, `<192>`, `<999>`, missing `<`, `<>`, `<1a>`, `<1234>`, `<191` |
| t3 | tables | all 24 facility names, all 8 severity names, codes, case-sensitivity |
| t4 | 3164 basic | facility/severity, all time fields, TAG/pid, content, offsets, consumed 55 |
| t5 | 3164 day/content | ` 1`/`01`/`12`, `TAG:` empty, `TAG:hello`, one SP skipped, `content_at` |
| t6 | 3164 months/time | all 12 month names; bad month, day 0/32, hour 24, minute/second 60, bad separators, short tail |
| t7 | 3164 TAG/pid | 32-byte tag ok, 33 too long, `sys-temd` rejected, pid empty/non-digit/11-digit/unterminated, missing colon |
| t8 | 3164 headers | hostname 255 ok / 256 too long, high byte rejected, empty and missing hostname |
| t9 | 3164 walk | two messages by `consumed`, CRLF line, content excludes the break |
| t10 | detect | 3164 month letter, 5424 digit+SP, 1..3 digit versions, unknown shapes |
| t11 | 5424 NILVALUE | `-` fields, no SD, no MSG, `has_msg` with empty and non-empty MSG |
| t12 | 5424 RFC example | timestamp fields, SD element + 3 params, BOM, MSG, raw span slice |
| t13 | SD escapes/spans | `\"`, `\\`, `\]` decode, 12-byte raw span, multi-element, name lookup, case sensitivity, out-of-range |
| t14 | SD errors | bad escape, trailing backslash, raw `]`, bad quote, bad name, bad SD-ID, unterminated, junk, empty element |
| t15 | 5424 limits | 255/48/128/32 accepted, over-limit rejected, high byte hostname |
| t16 | 5424 headers | PRI, version, timestamp, missing/truncated field catalog with offsets |
| t17 | timestamp fields | fraction, `Z`, `+02:30`, `-07:00`, `-00:00`, validity matrix |
| t18 | timestamp errors | lowercase `t`, bad leap day, month 13, hour 24, second 60, fraction 7/0, bad offsets, trailing bytes |
| t19 | predicates | `log3164_ok`, `log5424_ok`, detect+parse dispatch |
| t20 | 5424 accessors | hostname/app/procid/msgid/msg, timestamp struct accessor |
| t21 | round-trip | all 192 facility x severity pairs through make/decode/name/code |
| t22 | empty parts | empty param value and span, bare `[a]` element, BOM-only MSG |

Element comparisons in the suite go through `xiom.string.compare`'s
`str_compare`, never `==` (BUG 17).

## 11. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only -- no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]` dispatch, no `Vec[Float64]`.
- `Str` values are never compared with `==` when read from a `Vec[Str]`
  element (BUG 17 lowers that to a pointer comparison); every table and
  parameter lookup uses `str_compare` and every `Vec` element read is bound
  with a typed `let`.
- `byte_at` results are widened with `as Int` before arithmetic; BOM
  constants >= 128 are masked on both sides before comparison.
- Output bytes (unescaped parameter values) are collected in a
  `Vec[UInt8]` and materialized with `xiom.string.builder.sb_to_str`.
- `Ok`/`Err` are constructed only in the tiny leaf helpers
  (`_ok_ts`/`_err_ts`, `_ok_3164`/`_err_3164`, `_ok_5424`/`_err_5424`,
  `_ok_int`/`_err_int`); the scanners return plain structs and the parsers
  return errors through the leaf helpers.
- The parsers own their scanning loops; read-only accessors borrow
  `&Log3164` / `&Log5424`.
- Tests dispatch directly (`t1()` ... `t22()`), with no match pattern
  binding `mut` and every `match` exhaustive.
- `LogTimestamp` nests inside the private `_TsScan` scan result only;
  `Log3164` and `Log5424` are flat for stable field access.

## 12. Non-goals and limitations

- **Decoder only:** no encoder/renderer, so parse/render round-trips are not
  offered.
- **No transports or policy:** no sockets, files, journald, rotation,
  routing, redaction or rate limiting; no clock access.
- **3164 strictness:** one line per call, hostname and `TAG:` required,
  alphanumeric TAG only (32 max), 1..10-digit pid, case-sensitive months,
  space/zero-padded two-character day; no year inference and no timezone.
- **5424 versions:** structurally accepted 1..999; only version 1 is the
  RFC 5424 version. Version-specific semantics are not implemented.
- **Timestamps:** validated and split into fields only; no epoch conversion,
  no `now()`, no duration math, no leap seconds.
- **MSG is bytes:** a UTF-8 BOM is detected and stripped; no further UTF-8
  validation, normalization or length policy. A trailing CR/LF after MSG is
  MSG content.
- **Detection is shape-only** and may report a format for text that then
  fails its parser.
- **NUL in values:** parameter values are materialized with the string
  builder, which cannot represent `0x00`.
