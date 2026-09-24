# xiom.telnet

> **Status:** INCUBATING -- implemented and covered by a green conformance
> suite, **not yet published** to the XIOM registry.
> **Scope:** the Telnet negotiation layer only: IAC verbs
> (WILL/WONT/DO/DONT), subnegotiation (SB ... SE) framing and 0xFF data
> escaping.
> **Deps:** none at runtime (the library module imports nothing; the tests
> use `xiom.std` modules).

## What it is

`xiom.telnet` is a pure-XIOM codec for the Telnet control stream defined by
RFC 854 and RFC 855. It turns a byte buffer into a flat table of negotiation
events and back, and implements the data-escaping rule that lets a literal
`0xFF` travel through the command stream.

The module is deliberately small: it frames and classifies the commands but
attaches no meaning to option codes (option 24 TTYPE, option 31 NAWS,
option 34 LINEMODE, ...). Session state -- which side asked for what, what is
currently enabled, how to answer -- belongs to the caller.

## API

| Function | Returns | Description |
|---|---|---|
| `telnet_build_negotiation(verb, option)` | `Result[Vec[UInt8], Str]` | Three bytes: `IAC verb option`. `verb` must be 251..254, `option` must be 0..255. |
| `telnet_parse(data)` | `Result[TelnetEvents, Str]` | Classify a stream chunk into ordered events (kinds 1 WILL, 2 WONT, 3 DO, 4 DONT, 5 SB). |
| `telnet_escape_data(data)` | `Vec[UInt8]` | Double every `0xFF` for transmission. |
| `telnet_unescape_data(data)` | `Vec[UInt8]` | Collapse `IAC IAC` to one `0xFF`; other sequences pass through. |
| `telnet_event_count(e)` | `Int` | Number of events. |
| `telnet_kind(e, i)` | `Int` | Kind of event `i`, or `-1` out of range. |
| `telnet_option(e, i)` | `Int` | Option code of event `i`, or `-1` out of range. |
| `telnet_payload_offset(e, i)` | `Int` | Raw payload offset of SB event `i`; `-1` for negotiation events and out of range. |
| `telnet_payload_length(e, i)` | `Int` | Raw payload length of SB event `i`; `0` for negotiation events; `-1` out of range. |

```xi
use xiom.telnet;

let asked = telnet_build_negotiation(TELNET_DO, 24);   // FF FD 18
let events = telnet_parse(&wire);                       // Ok / Err
let n = telnet_event_count(&events);
if telnet_kind(&events, 0) == 5 {
  // SB payload [offset, offset + length) is raw; unescape it if needed.
}
```

## Constants and events

| Byte | Value | Meaning |
|---|---|---|
| `TELNET_IAC` | 255 (`0xFF`) | Interpret As Command; introduces every command. |
| `TELNET_DONT` | 254 (`0xFE`) | Refuse / forbid option. |
| `TELNET_DO` | 253 (`0xFD`) | Request the peer to enable option. |
| `TELNET_WONT` | 252 (`0xFC`) | Refuse to enable option. |
| `TELNET_WILL` | 251 (`0xFB`) | Agree / offer to enable option. |
| `TELNET_SB` | 250 (`0xFA`) | Begin subnegotiation; must end with IAC SE. |
| `TELNET_SE` | 240 (`0xF0`) | End subnegotiation. |

| `kinds[i]` | Event |
|---|---|
| 1 | `WILL option` |
| 2 | `WONT option` |
| 3 | `DO option` |
| 4 | `DONT option` |
| 5 | `SB option` (payload in `payload_offsets[i]` / `payload_lengths[i]`) |

On the wire a command stream repeats the same three shapes:

```
negotiation   IAC WILL|WONT|DO|DONT  option          3 bytes
subnegotiation IAC SB option ... IAC SE              payload is raw
data           any byte except 0xFF, or 0xFF 0xFF    escaped data byte
```

## Testing

```
.\scripts\port.ps1 -Package xiom.telnet
```

Expected tail: eighteen `[PASS]` lines, `xiom.telnet: all tests passed`
and `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. The suite lives
in `tests/test_conformance.xi`; its coverage map is SPEC.md section 6.

## Limitations

- **Negotiation only.** No option semantics: NAWS, TTYPE, LINEMODE, BINARY
  and friends are opaque numbers here.
- **No session state.** The module does not track outstanding requests, which
  options are enabled, direction (client/server) or retry policy. It is a
  codec, not a state machine.
- **No terminal emulation, no I/O, no timing.** Bytes in, events out.
- **Modeled commands only.** RFC 854's NOP, DM, BRK, IP, AO, AYT, EC, EL and
  GA are rejected with `telnet: unknown IAC command`.
- **Chunk framing is the caller's job.** A buffer that ends mid-command is an
  error, not a promise that more bytes will follow.
- **SB payloads stay raw.** A doubled `IAC IAC` inside a subnegotiation
  counts as two bytes; callers that want the logical bytes should
  `telnet_unescape_data` the slice.
- `telnet_unescape_data` passes lone or unknown `IAC` sequences through
  verbatim, so it is not a full inverse for arbitrary streams; only use it on
  buffers that the peer produced with `telnet_escape_data`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
