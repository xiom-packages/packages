# xiom.logging

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** syslog message structure codecs for the two classic wire
> formats: RFC 3164 (BSD syslog) and RFC 5424. Parse the PRI field, the
> facility/severity tables, 3164 timestamps/hostname/TAG/pid/CONTENT, 5424
> timestamps/NILVALUE headers/structured data/MSG (with UTF-8 BOM), detect
> the format, and read every field back through accessors. Message structure
> only: no transports, no message building/rendering.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`, and
> `xiom.string.builder.sb_push_int`/`sb_to_str`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.logging` turns syslog wire text

```
<34>Oct 11 22:14:15 mymachine su[123]: 'su root' failed
<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut="3" eventSource="Application"] An application event log entry...
```

into flat `Log3164` / `Log5424` values. The codec is byte-oriented and
stateless: every function works on `Str` input and returns plain values, so
there is no socket, no file, no global configuration and no clock. All
decisions are pinned in `SPEC.md` and locked by the 22-check conformance
suite.

Non-goals: no transports (UDP/TCP/file/journald/rotation), no encoder or
renderer (parsing is one-way), no timezone conversion, no UTF-8 validation,
no message framing policy.

## API

Types:

| Type | Fields |
|---|---|
| `LogTimestamp` | `year`, `month`, `day`, `hour`, `minute`, `second`, `frac` (fraction digits without the dot, `""` when absent), `offset_min` (signed minutes), `present` (false for NILVALUE `-`) |
| `Log3164` | `facility`, `severity`, `month`, `day`, `hour`, `minute`, `second`, `timestamp` (raw `Mmm dd hh:mm:ss`), `hostname`, `tag`, `pid`, `has_pid`, `content`, `has_content`, `consumed` (line byte length), `ts_at`, `host_at`, `tag_at`, `content_at` |
| `Log5424` | `facility`, `severity`, `version`, `timestamp` (raw text), `ts_present`, flat `ts_*` timestamp fields, `hostname`, `app_name`, `procid`, `msgid`, `msg` (BOM excluded), `bom`, `has_msg`, and the structured-data parallel vectors `sd_ids`, `sd_param_elem`, `sd_param_names`, `sd_param_values`, `sd_param_val_at`, `sd_param_val_len` |

Functions:

| Function | Returns | Description |
|---|---|---|
| `log_detect(text)` | `Str` | `"rfc3164"` / `"rfc5424"` / `""` from the byte after PRI (shape only). |
| `log3164_parse(text)` | `Result[Log3164, Str]` | Parse one BSD syslog line; stops at the first CR/LF; `consumed` supports buffer walks. |
| `log5424_parse(text)` | `Result[Log5424, Str]` | Parse one RFC 5424 message (no transport framing removed). |
| `log3164_ok(text)` / `log5424_ok(text)` | `Bool` | True when the matching parser succeeds. |
| `log_facility_name(code)` | `Str` | `kern`..`local7` for 0..23, `""` outside. |
| `log_severity_name(code)` | `Str` | `emerg`..`debug` for 0..7, `""` outside. |
| `log_facility_code(name)` / `log_severity_code(name)` | `Result[Int, Str]` | Name -> code, case-sensitive; `Err("logging: unknown facility/severity: <name>")`. |
| `log_pri_make(facility, severity)` | `Result[Int, Str]` | `facility * 8 + severity`; rejects out-of-range inputs. |
| `log_pri_valid(pri)` | `Bool` | True for 0..191. |
| `log_pri_facility(pri)` / `log_pri_severity(pri)` | `Int` | Decode 0..191; `-1` outside. |
| `log5424_timestamp_valid(s)` | `Bool` | RFC 3339 shape and calendar check. |
| `log5424_timestamp_parse(s)` | `Result[LogTimestamp, Str]` | Timestamp text -> structured fields; errors carry offsets. |
| `log5424_timestamp(m)` | `LogTimestamp` | Structured timestamp of a parsed 5424 message. |
| `log3164_*` accessors | | `pri`, `facility`, `severity`, `month`, `day`, `hour`, `minute`, `second`, `timestamp`, `hostname`, `tag`, `pid`, `has_pid`, `content`, `has_content`, `consumed`. |
| `log5424_*` accessors | | `pri`, `facility`, `severity`, `version`, `timestamp_text`, `has_timestamp`, `hostname`, `app_name`, `procid`, `msgid`, `msg`, `has_bom`, `has_msg`, `sd_count`, `sd_id`, `sd_param_count`, `sd_param_name`, `sd_param_value`, `sd_param_value_at`, `sd_param_value_len`, `sd_param_value_wire`, `sd_param`. |

## Quick start

```xi
use xiom.logging;
use xiom.io;

fn main() -> Int {
  let line = "<165>1 2003-10-11T22:14:15.003Z host evntslog - ID47 [ex iut=\"3\"] hello";
  match log5424_parse(line) {
    Ok(m) => {
      io.println(log_facility_name(log5424_facility(&m)));  // local4
      io.println(log_severity_name(log5424_severity(&m)));  // notice
      let ts = log5424_timestamp(&m);
      io.println(log5424_app_name(&m));                     // evntslog
      io.println(log5424_sd_param_value(&m, 0, 0));         // 3
      io.println(log5424_msg(&m));                          // hello
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Walking an RFC 3164 buffer (one line per message, `consumed` excludes the
line break):

```xi
use xiom.logging;
use xiom.io;
use xiom.string;

fn main() -> Int {
  let buf = "<13>Aug  1 12:00:00 h1 t1:x\n<14>Aug  2 13:00:00 h2 t2:y\n";
  let r = log3164_parse(buf);
  match r {
    Ok(m) => {
      io.println(m.hostname + " " + m.content);       // h1 x
      let rest = string.str_slice(buf, m.consumed + 1, buf.len());
      let r2 = log3164_parse(rest);
      match r2 {
        Ok(m2) => { io.println(m2.hostname + " " + m2.content); },  // h2 y
        Err(e2) => { io.println(e2); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Error model

Every fallible entry point returns `Err(Str)` whose message starts with
`logging: ` and ends with ` at <byte offset>` (the offset is relative to the
input, or to the timestamp text for `log5424_timestamp_parse`). Examples:
`logging: PRI out of range at 1`, `logging: bad TIMESTAMP at 8`,
`logging: bad param escape at 26`, `logging: truncated message at 15`. The
non-parse helpers use plain messages such as
`logging: unknown facility: LOCAL0` and `logging: facility out of range: 24`.
The full catalog is in `SPEC.md` section 10.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.logging
```

Expected tail: 22 `[PASS]` lines, `xiom.logging: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Decoder only:** there is no encoder/renderer, so round-trip equality is
  not offered; parsing is the whole contract.
- **No transports or policy:** sockets, files, journald, rotation, routing
  and rate limiting are out of scope. `xiom.logging` never reads a clock.
- **3164 is strictly one line:** the walk stops at the first CR/LF; `consumed`
  is the line byte length and the caller frames the buffer. A message
  without HOSTNAME or without `TAG:` is rejected (no lenient fallbacks).
- **3164 TAG grammar:** alphanumeric only, 1..32 bytes, so tags like
  `systemd-logind` are rejected; the pid part is 1..10 digits; the month name
  is case-sensitive (`Oct`, not `oct`); the day is two characters, either
  space-padded (` 1`) or zero-padded (`01`); there is no year and no
  timezone on the wire.
- **5424 versions:** any 1..3-digit version with a nonzero first digit
  (1..999) parses; the codec does not interpret versions other than
  structurally.
- **Timestamps are validated, not converted:** calendar checks are
  proleptic Gregorian; leap seconds (`:60`) are rejected; `-00:00` is
  accepted and yields offset 0.
- **Structured data:** escaped values are decoded, and the raw wire span of
  each value is available byte-exactly via `sd_param_val_at` /
  `sd_param_val_len` / `sd_param_value_wire`; a raw `]` inside a value and
  any escape other than `\"`, `\\`, `\]` are rejected.
- **MSG is opaque bytes:** a leading UTF-8 BOM is stripped and flagged;
  otherwise no UTF-8 validation, normalization or length policy is applied.
  For 5424 a trailing LF/CRLF is MSG content, not framing.
- **Detection is shape-only:** `log_detect` inspects the byte after PRI
  (version digit run + SP vs a letter) and can report a format for text that
  then fails its parser.

See `SPEC.md` for the exact grammars, parsing decisions, API contract, error
catalog and test matrix. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
