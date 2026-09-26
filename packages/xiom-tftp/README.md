# xiom.tftp

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green
> under the repo harness. **NOT published** to the XIOM registry.
> **Scope:** TFTP packet codec: RRQ, WRQ, DATA, ACK, ERROR and OACK with
> the RFC 2347/2348/2349 option extension (`blksize`, `timeout`, `tsize`
> plus pass-through options such as `windowsize`).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.tftp` is the packet layer of the Trivial File Transfer Protocol:
16-bit big-endian opcodes and block numbers, NUL-terminated filename /
mode / option / message strings, and length-counted DATA payloads. Every
packet parses into one flat `TftpPacket` value (scalars, strings, the
payload bytes and two parallel option pools) and every packet can be
re-emitted canonically. It does not open sockets, run sessions,
retransmit, or enforce timeouts -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `tftp_build_rrq(filename, mode, opt_names, opt_values)` | `Result[Vec[UInt8], Str]` | RRQ (opcode 1); mode matched case-insensitively, emitted lowercase. |
| `tftp_build_wrq(filename, mode, opt_names, opt_values)` | `Result[Vec[UInt8], Str]` | WRQ (opcode 2), same rules. |
| `tftp_build_data(block, payload)` | `Result[Vec[UInt8], Str]` | DATA (opcode 3); block clamped 0..65535, payload up to 65464 bytes. |
| `tftp_build_ack(block)` | `Result[Vec[UInt8], Str]` | ACK (opcode 4); exactly 4 bytes. |
| `tftp_build_error(code, message)` | `Result[Vec[UInt8], Str]` | ERROR (opcode 5); code clamped 0..65535. |
| `tftp_build_oack(opt_names, opt_values)` | `Result[Vec[UInt8], Str]` | OACK (opcode 6); at least one option TLV. |
| `tftp_emit(p)` | `Result[Vec[UInt8], Str]` | Canonical emitter for any parsed/hand-built packet. |
| `tftp_parse(data)` | `Result[TftpPacket, Str]` | Dispatch on the opcode, exact-size validation. |
| `tftp_parse_rrq/wrq/data/ack/error/oack(data)` | `Result[TftpPacket, Str]` | Per-kind parsers with stable `not an X` errors. |
| `tftp_op(data)` | `Result[Int, Str]` | Opcode 1..6 only. |
| `tftp_opcode(p)` / `tftp_opcode_name(op)` | `Int` / `Str` | Opcode and its `RRQ`..`OACK` name (`UNKNOWN` otherwise). |
| `tftp_filename(p)` / `tftp_mode(p)` | `Str` | Request fields (`""` for other kinds); mode lowercase. |
| `tftp_block(p)` | `Int` | DATA/ACK block number. |
| `tftp_error_code(p)` / `tftp_error_name(code)` / `tftp_error_message(p)` | `Int` / `Str` / `Str` | Error fields; `tftp_error_name` is the RFC 1350 table. |
| `tftp_option_count(p)` / `tftp_option_name(p, i)` / `tftp_option_value(p, i)` | `Int` / `Str` / `Str` | Flat option pools; out-of-range indices return `""`. |
| `tftp_payload_len(p)` / `tftp_payload_byte(p, i)` / `tftp_payload_copy(p)` | `Int` / `Int` / `Vec[UInt8]` | Payload span; out-of-range byte is `-1`. |
| `tftp_is_last_block(p, blksize)` | `Bool` | `payload < blksize`, with 512 as the default for invalid sizes. |

Errors are `Err("tftp: ...")` strings; the full catalog is in `SPEC.md`.

## Options

Option names match case-insensitively; known names are stored and emitted
lowercase, everything else passes through verbatim.

| Name | Accepted value | Notes |
|---|---|---|
| `blksize` | canonical decimal, 8..65464 | RFC 2348; `tftp: bad block size` otherwise. |
| `timeout` | canonical decimal, 1..255 | RFC 2349 seconds. |
| `tsize` | canonical decimal, 0..4294967295 | 0 asks for the size on WRQ. |
| others (`windowsize`, ...) | any value bytes | Pass-through, no semantics. |

Canonical decimal means no leading zeros (`"08"` is rejected, `"0"` is
fine). Duplicate options are preserved in wire order.

## Wire format

| Opcode | Packet | Layout |
|---|---|---|
| 1 | RRQ | `[u16 1][filename][0x00][mode][0x00]` + option TLVs |
| 2 | WRQ | `[u16 2][filename][0x00][mode][0x00]` + option TLVs |
| 3 | DATA | `[u16 3][u16 block][payload]` |
| 4 | ACK | `[u16 4][u16 block]` (exactly 4 bytes) |
| 5 | ERROR | `[u16 5][u16 code][message][0x00]` |
| 6 | OACK | `[u16 6]` + at least one option TLV |

All 16-bit fields are big-endian. Strings are NUL-terminated (and cannot
embed `0x00`); DATA payloads are length-counted, so they may contain
`0x00`; ACK, ERROR and OACK use exact-size validation (no trailing
bytes). Modes are `netascii`, `octet` or `mail`, case-insensitive.

## Usage

```xi
use xiom.tftp;
use xiom.io;

fn main() -> Int {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("blksize");
  values.push("1428");
  names.push("tsize");
  values.push("1048576");

  let req = tftp_build_rrq("boot.img", "octet", &names, &values);
  if req.is_ok {
    let wire: Vec[UInt8] = req.value;
    let back = tftp_parse(&wire);
    if back.is_ok {
      let pkt: TftpPacket = back.value;
      io.println(tftp_opcode_name(pkt.opcode));   // RRQ
      io.println(tftp_filename(&pkt));            // boot.img
      io.println(tftp_option_name(&pkt, 0));      // blksize
      io.println(tftp_option_value(&pkt, 0));     // 1428
    }
  }

  var chunk = Vec[UInt8].new();
  chunk.push(65);
  let d = tftp_build_data(1, &chunk);
  if d.is_ok {
    let dw: Vec[UInt8] = d.value;
    let dp = tftp_parse(&dw);
    if dp.is_ok {
      let p: TftpPacket = dp.value;
      if tftp_is_last_block(&p, 512) {            // DATA final-block test
        io.println("final block");
      }
    }
  }
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.tftp
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only.** No sockets, sessions, retransmission, timeouts, server
  or client. Re-sent DATA/ACK blocks are accepted like any other packet;
  duplicate detection is a session concern.
- **No content translation.** Payload bytes are never converted;
  `netascii` and `mail` are validated mode names only.
- **Pass-through options.** Only `blksize`, `timeout` and `tsize` have
  value rules; `windowsize` and future options are carried verbatim with
  no semantics.
- **One packet per call.** Every parse validates exactly one packet and
  requires the whole buffer to be consumed (ACK/ERROR/OACK reject
  trailing bytes).
- **Protocol maximum only.** DATA payloads may be 0..65464 bytes; the
  effective block size (512 default or negotiated) is exposed by
  `tftp_is_last_block` but not enforced by the parser.
- **Strings are bytes.** No UTF-8 validation, no filename path rules; a
  `Str` cannot embed `0x00` at the XIOM ABI.

See `SPEC.md` for the byte layout, option rules, flat-storage model, the
full error catalog and the test plan. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
