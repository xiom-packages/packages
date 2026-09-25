# xiom.syslog

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an RFC 5424 syslog message codec: PRI parse/build, header field
> validation, RFC 3339 timestamp validation (kept as text), structured data
> with escape handling, and MSG with UTF-8 BOM detection -- in-memory `Str`
> only, no transport.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.syslog` turns an RFC 5424 syslog line such as

```
<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut="3" eventSource="Application"] BOMAn application event log entry...
```

into a flat `SyslogMsg` (facility/severity, VERSION, TIMESTAMP, HOSTNAME,
APP-NAME, PROCID, MSGID, structured-data elements and parameters, MSG) and
back. It is a *message codec*, not a syslog client or server: it never
touches sockets, files or octet-counting framing.

Design decisions worth knowing before you use it:

- **TIMESTAMP is validated, not converted.** The parser checks the RFC 3339
  shape (uppercase `T`/`Z`, 1..6 fraction digits, real calendar days, offset
  ranges) and stores the text verbatim. There is no epoch conversion, no
  timezone normalization and no arithmetic anywhere in the package.
- **NILVALUE is the empty string.** A wire `-` in TIMESTAMP/HOSTNAME/
  APP-NAME/PROCID/MSGID or as the whole structured-data section parses to
  `""` / zero elements, and the builder re-emits `-`.
- **Byte-exact round-trips.** For every accepted message,
  `syslog_build(syslog_parse(text))` reproduces `text`; the only wire
  normalization is that PRI leading zeros are dropped (`<034>` -> `<34>`),
  and even the optional `SP MSG` part is reproduced faithfully thanks to the
  `has_msg` flag.
- **MSG is opaque bytes.** A leading UTF-8 BOM (EF BB BF) is detected,
  stripped from `msg` and flagged by `bom`; no further UTF-8 validation is
  performed (MSG-ANY is legal in RFC 5424).

## API

| Function | Returns | Description |
|---|---|---|
| `syslog_parse(text)` | `Result[SyslogMsg, Str]` | Parse one message; `Err("syslog: ...")` per the error catalog. |
| `syslog_build(m)` | `Result[Str, Str]` | Encode a `SyslogMsg`; validates ranges, field lengths, timestamps and SD names. |
| `syslog_ok(text)` | `Bool` | True when `syslog_parse(text)` would succeed. |
| `syslog_timestamp_valid(s)` | `Bool` | Validate an RFC 5424 TIMESTAMP text (not `""`/`-`). |
| `syslog_pri(m)` | `Int` | `facility * 8 + severity` (0..191). |
| `syslog_facility(m)` | `Int` | Facility code 0..23. |
| `syslog_severity(m)` | `Int` | Severity code 0..7. |
| `syslog_version(m)` | `Int` | VERSION 1..999. |
| `syslog_timestamp(m)` | `Str` | TIMESTAMP text; `""` for NILVALUE. |
| `syslog_hostname(m)` | `Str` | HOSTNAME; `""` for NILVALUE. |
| `syslog_app_name(m)` | `Str` | APP-NAME; `""` for NILVALUE. |
| `syslog_procid(m)` | `Str` | PROCID; `""` for NILVALUE. |
| `syslog_msgid(m)` | `Str` | MSGID; `""` for NILVALUE. |
| `syslog_msg(m)` | `Str` | MSG without a leading BOM; `""` when absent/empty. |
| `syslog_has_bom(m)` | `Bool` | True when MSG carried a UTF-8 BOM (stripped). |
| `syslog_has_msg(m)` | `Bool` | True when the optional `SP MSG` part was present (even empty). |
| `syslog_sd_count(m)` | `Int` | Number of structured-data elements (0 = NILVALUE). |
| `syslog_sd_id(m, i)` | `Str` | SD-ID of element `i`; `""` when out of range. |
| `syslog_sd_param_count(m, elem)` | `Int` | Number of parameters of element `elem`. |
| `syslog_sd_param_name(m, elem, i)` | `Str` | Name of the `i`-th parameter; `""` when out of range. |
| `syslog_sd_param_value(m, elem, i)` | `Str` | Unescaped value of the `i`-th parameter; `""` when out of range. |
| `syslog_sd_param(m, elem, name)` | `Option[Str]` | First parameter named `name` (byte-exact); `None` when absent. |

Structured data is stored flat: `sd_ids` holds one SD-ID per element, and
parameter `p` belongs to element `sd_param_elem[p]` with
`sd_param_names[p]` / `sd_param_values[p]` (`Vec[StructType]` is not usable
in this compiler). Parse keeps wire order inside an element; build groups
parameters by element index.

## Quick start

```xi
use xiom.syslog;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let text = "<165>1 2003-10-11T22:14:15.003Z host app 42 ID47 [exampleSDID@32473 iut=\"3\"] hello";
  match syslog_parse(text) {
    Ok(m) => {
      io.println("facility: " + convert.int_to_string(syslog_facility(&m)));  // 20
      io.println(syslog_app_name(&m));                             // app
      io.println(syslog_msg(&m));                                  // hello
      match syslog_sd_param(&m, 0, "iut") {
        Some(v) => { io.println(v); },                             // 3
        None => {},
      }
      let back = syslog_build(&m);
      if back.is_ok {
        let wire: Str = back.value;
        io.println(wire);                                          // == text
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.syslog
```

Expected tail: 24 `[PASS]` lines, `xiom.syslog: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Install

```
xiom pkg install xiom.syslog@0.1.0     # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Error model

Every failure is `Err(msg)` where `msg` starts with `"syslog: "`. Messages
are deterministic and either name the offending field or quote its text,
e.g. `syslog: missing field: HOSTNAME`, `syslog: PRI out of range: 192`,
`syslog: bad TIMESTAMP: 2003-13-01T00:00:00Z`,
`syslog: bad param escape`, `syslog: unterminated structured data`. The full
catalog is in `SPEC.md` section 8. `syslog_build` adds struct-consistency
errors such as `syslog: bad structured data: inconsistent layout`.

## Limitations

- **No transport framing:** no octet counting, no LF-delimited streams, no
  BOM-at-start-of-stream handling, no truncation of a trailing line
  terminator (a trailing LF becomes MSG content or trailing junk).
- **No RFC 3164 legacy mode** and no PRI-only/free-form fallback.
- **No timestamp arithmetic:** no epoch, timezone conversion, `now()`, leap
  seconds (`:60` is rejected) or relative dates.
- **No UTF-8 validation:** MSG and PARAM-VALUE bytes are copied verbatim
  (only BOM detection looks at MSG's first three bytes).
- **Strict parameter values:** `"`, `\` and `]` must be escaped on the wire;
  an unescaped `]` is `Err("syslog: bad param value")`.
- **Byte-exact field rules:** HOSTNAME/APP-NAME/PROCID/MSGID must be
  PRINTUSASCII (33-126) within RFC 5424 length limits (255/48/128/32).
- **No facility/severity name tables** (`authpriv`, `warning`, ...) -- use
  the numeric codes.
- Errors carry no offset/position, only the offending text.

See `SPEC.md` for the exact grammar, catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
