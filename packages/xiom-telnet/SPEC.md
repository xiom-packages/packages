# xiom.telnet -- specification

> **Status:** INCUBATING (v0.1.0). Implemented in `src/telnet.xi` and pinned
> by `tests/test_conformance.xi` (18 checks). Not yet published.

This document is the normative description of the `xiom.telnet` negotiation
codec. It covers the wire grammar, the parser and encoder rules, the
escaping rules, the error catalog, the event model and the test plan.
References: RFC 854 (Telnet Protocol Specification) and RFC 855 (Telnet
Option Specifications).

## 1. Scope

`xiom.telnet` models the negotiation layer of Telnet only:

- the four negotiation verbs `WILL` / `WONT` / `DO` / `DONT`,
- subnegotiation frames `IAC SB option ... IAC SE`, kept as raw byte ranges,
- the `IAC IAC` (255 255) data-escaping rule.

It does **not** model option semantics (NAWS, TTYPE, LINEMODE, BINARY, ...),
session state (which options are enabled, outstanding requests, client vs
server role), terminal emulation, timing or any I/O. RFC 854's other
commands (`NOP` 241, `DM` 242, `BRK` 243, `IP` 244, `AO` 245, `AYT` 246,
`EC` 247, `EL` 248, `GA` 249) are outside the model and are rejected.

## 2. Wire grammar

```
stream          = { unit } ;
unit            = data-byte | iac-escape | negotiation | subnegotiation ;
data-byte       = BYTE \ { IAC } ;                    (* 0x00..0xFE *)
iac-escape      = IAC IAC ;                           (* data byte 0xFF *)
negotiation     = IAC verb option ;
verb            = WILL | WONT | DO | DONT ;
option          = BYTE ;                              (* 0x00..0xFF *)
subnegotiation  = IAC SB option { sub-byte } IAC SE ;
sub-byte        = BYTE \ { SE, IAC } | IAC IAC ;      (* IAC only doubled *)
```

Byte constants:

| Name | Value |
|---|---|
| `TELNET_IAC` | 255 (0xFF) |
| `TELNET_DONT` | 254 (0xFE) |
| `TELNET_DO` | 253 (0xFD) |
| `TELNET_WONT` | 252 (0xFC) |
| `TELNET_WILL` | 251 (0xFB) |
| `TELNET_SB` | 250 (0xFA) |
| `TELNET_SE` | 240 (0xF0) |

The grammar is not self-synchronizing: an unescaped `0xFF` byte that is not
followed by a recognized command is an error, not data (see section 4).

## 3. Parser and encoder rules

### 3.1 `telnet_build_negotiation(verb, option) -> Result[Vec[UInt8], Str]`

1. `verb` must be one of 251, 252, 253, 254; otherwise
   `Err("telnet: verb out of range")`. The verb is checked first, so an
   invalid verb wins over an invalid option.
2. `option` must be in 0..255; otherwise
   `Err("telnet: option out of range")`.
3. Otherwise `Ok([255, verb, option])`, exactly three bytes.

### 3.2 `telnet_parse(data) -> Result[TelnetEvents, Str]`

Scans left to right; all indices are absolute within the input buffer.

| Input shape | Result |
|---|---|
| byte `!= IAC` | data byte: skipped, no event |
| `IAC IAC` | escaped data byte: skipped, no event |
| `IAC WILL/WONT/DO/DONT option` | one negotiation event: kind 1/2/3/4 |
| `IAC SB option ... IAC SE` | one SB event: kind 5, raw payload range |
| `IAC` at end of buffer | `Err("telnet: truncated IAC")` |
| `IAC verb` at end of buffer | `Err("telnet: truncated negotiation")` |
| `IAC SB` at end of buffer | `Err("telnet: truncated subnegotiation")` |
| SB payload reaches end of buffer | `Err("telnet: unterminated subnegotiation")` |
| `IAC` inside SB followed by anything but `IAC`/`SE` | `Err("telnet: IAC in subnegotiation must be followed by IAC or SE")` |
| `IAC` + any other byte | `Err("telnet: unknown IAC command")` |

Inside SB the payload scan treats `IAC IAC` as two payload bytes and
`IAC SE` as the terminator; the payload range excludes the terminator. The
scan is greedy and stops at the first `IAC SE`.

Parsing never wraps: every command must be complete inside the given buffer.

### 3.3 Event model

`TelnetEvents` is four index-aligned vectors; entry `i` is
`(kinds[i], options[i], payload_offsets[i], payload_lengths[i])`.
`kinds[i]` is 1 WILL, 2 WONT, 3 DO, 4 DONT, 5 SB.

- Negotiation events store `payload_offsets[i] = -1`,
  `payload_lengths[i] = 0`.
- SB events store the offset of their first raw payload byte and the raw
  payload length; a doubled `IAC` counts as two bytes because it is kept raw.
  The offset/length refer to the buffer passed to `telnet_parse`, not to the
  original stream.
- Accessors `telnet_event_count`, `telnet_kind`, `telnet_option`,
  `telnet_payload_offset`, `telnet_payload_length` are bounds-safe: any
  negative index or index `>= telnet_event_count` yields `-1` (and
  `telnet_payload_length` yields `0` for negotiation events).

## 4. Escaping rules

A literal `0xFF` in application data must be doubled before it enters the
command stream, because a lone `IAC` introduces a command.

- `telnet_escape_data(data)`: every `0xFF` byte becomes `IAC IAC`
  (`255 255`); every other byte is copied unchanged. The result length is
  `data.len() + count(0xFF)`.
- `telnet_unescape_data(data)`: every `IAC IAC` pair collapses to one `0xFF`
  byte; every other byte is copied unchanged. Consequences, all pinned by
  tests:
  - a lone trailing `IAC` passes through as one byte,
  - `IAC WILL ...` and other command sequences pass through verbatim,
  - `unescape(escape(x)) == x` always holds,
  - `escape(unescape(y)) == y` holds only when `y` contains no lone or
    unknown `IAC` sequence. `telnet_unescape_data` is therefore valid only
    on buffers that the peer built with `telnet_escape_data`, or on raw SB
    payload slices when the caller wants the logical bytes.

## 5. Error catalog

| Message | Function | Trigger |
|---|---|---|
| `telnet: verb out of range` | `telnet_build_negotiation` | verb outside {251, 252, 253, 254} (including SB 250 and IAC 255) |
| `telnet: option out of range` | `telnet_build_negotiation` | option < 0 or > 255 |
| `telnet: truncated IAC` | `telnet_parse` | buffer ends immediately after `IAC` |
| `telnet: truncated negotiation` | `telnet_parse` | `IAC verb` ends the buffer (option byte missing) |
| `telnet: truncated subnegotiation` | `telnet_parse` | `IAC SB` ends the buffer (option byte missing) |
| `telnet: unterminated subnegotiation` | `telnet_parse` | SB payload reaches the buffer end before `IAC SE` |
| `telnet: IAC in subnegotiation must be followed by IAC or SE` | `telnet_parse` | SB payload has `IAC` followed by any other byte |
| `telnet: unknown IAC command` | `telnet_parse` | `IAC` followed by a byte outside {IAC, WILL, WONT, DO, DONT, SB} (includes stray `SE` and the unmodeled RFC 854 commands) |

Errors are plain `Str` values with a `telnet: ` prefix; the codec defines no
typed error enum.

## 6. Test plan

`tests/test_conformance.xi` runs 18 checks. Every check prints a
`[PASS]`/`[FAIL]` line and `main` returns the failure count:

| # | Check | Pins |
|---|---|---|
| 1 | build exact bytes | `IAC WILL/WONT/DO/DONT option` byte-for-byte, length 3 |
| 2 | build errors | invalid verbs/options; precedence verb-before-option; option 0 and 255 accepted |
| 3 | parse WILL/WONT | kinds 1/2 and options in stream order |
| 4 | parse DO/DONT | kinds 3/4 and options 24/255 |
| 5 | event order | five mixed events, kind/option order, payload slots for negotiation |
| 6 | SB payload | offset 3 and length 3 pin the raw bytes `01 02 03` |
| 7 | SB doubled IAC | `IAC IAC` in payload stays raw (offset/length count two bytes) |
| 8 | SB empty payload | length 0 with the terminator immediately after the option |
| 9 | SB option 255 | option 255 and a NUL payload byte survive |
| 10 | truncation catalog | bare `IAC`, verb without option, `SB` without option, unterminated payload |
| 11 | IAC inside SB | `IAC` + non-`IAC`/`SE` is an Err, including more commands |
| 12 | unknown commands | `NOP` (241), `NUL`, 239, stray `SE`, after data bytes |
| 13 | data skipping | plain data, escaped `IAC IAC` and surrounding data never become events |
| 14 | escape | empty input, single/double `0xFF`, interior `0xFF` |
| 15 | unescape | pair collapse, lone `IAC`, command bytes pass through |
| 16 | round-trips | `unescape(escape(x)) == x` for five buffers; escape stable on wire buffers |
| 17 | empty input | `Ok` with zero events; accessors on an empty table are bounds-safe |
| 18 | accessors | valid values pinned; negative and past-the-end indices return `-1` |

Command: `.\scripts\port.ps1 -Package xiom.telnet` (compiler v0.61.3,
`XIOM_STDLIB=E:\xiom-lang\stdlib`). Expected tail:
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 7. Non-goals

- Option semantics and negotiation state machines.
- Terminal emulation, line editing, I/O and scheduling.
- Multi-chunk reassembly: a truncated command is an error, not a partial
  parse that the caller can resume.
- Security: the codec allocates only in proportion to its input; no option
  data is interpreted, so it makes no policy decisions.
