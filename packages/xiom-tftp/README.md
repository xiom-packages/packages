# xiom.tftp

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) TFTP packet codec (RFC 1350): RRQ, WRQ,
> DATA, ACK and ERROR packets, encoded and decoded as byte vectors.
> **Deps:** `xiom.std` only. The library module imports only
> `xiom.string.builder`; the tests use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.tftp` is the packet layer of Trivial File Transfer Protocol: 16-bit
big-endian opcodes and block numbers, NUL-terminated filename / mode /
error-message strings, and length-counted DATA payloads. It encodes the
five RFC 1350 packet types and parses them back with deterministic error
strings, but it does not open sockets, run sessions, retransmit or apply
timeouts -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `tftp_build_rrq(filename, mode)` | `Vec[UInt8]` | Read request (opcode 1): filename + NUL + mode + NUL. |
| `tftp_build_wrq(filename, mode)` | `Vec[UInt8]` | Write request (opcode 2): filename + NUL + mode + NUL. |
| `tftp_build_data(block, payload)` | `Vec[UInt8]` | DATA (opcode 3): u16 block + payload; block clamped 0..65535. |
| `tftp_build_ack(block)` | `Vec[UInt8]` | ACK (opcode 4): u16 block; block clamped 0..65535. |
| `tftp_build_error(code, message)` | `Vec[UInt8]` | ERROR (opcode 5): u16 code + message + NUL; code clamped. |
| `tftp_op(data)` | `Result[Int, Str]` | Opcode 1..5; Err for truncated/unknown headers. |
| `tftp_parse_rq(data)` | `Result[(Str, Str), Str]` | `(filename, mode)` of an RRQ/WRQ. |
| `tftp_parse_data(data)` | `Result[(Int, Vec[UInt8]), Str]` | `(block, payload)` of a DATA packet. |
| `tftp_parse_ack(data)` | `Result[Int, Str]` | Block number of an ACK. |
| `tftp_parse_error(data)` | `Result[(Int, Str), Str]` | `(code, message)` of an ERROR packet. |
| `tftp_is_last_block(data)` | `Result[Bool, Str]` | DATA whose payload is shorter than 512 bytes. |

Errors are `Err("tftp: ...")` strings; the full catalog is in `SPEC.md`.

## Wire format

Opcodes (first two bytes, big-endian):

| Opcode | Packet | Layout |
|---|---|---|
| 1 | RRQ | `[u16 1][filename][0x00][mode][0x00]` |
| 2 | WRQ | `[u16 2][filename][0x00][mode][0x00]` |
| 3 | DATA | `[u16 3][u16 block][payload bytes]` |
| 4 | ACK | `[u16 4][u16 block]` |
| 5 | ERROR | `[u16 5][u16 code][message][0x00]` |

All 16-bit fields are big-endian. DATA payloads are length-counted (the
remaining bytes), so they may contain `0x00`; request and error strings
are NUL-terminated, so they may not.

## Usage

```xi
use xiom.tftp;
use xiom.io;

let rrq = tftp_build_rrq("boot.img", "octet");
let op = tftp_op(&rrq);                       // Ok(1)

let parsed = tftp_parse_rq(&rrq);
match parsed {
  Ok(pair) => { io.println("want: " + pair.0 + " mode " + pair.1); },
  Err(e) => { io.println("bad request: " + e); },
}

var chunk = Vec[UInt8].new();
chunk.push(1);
let data = tftp_build_data(1, &chunk);        // 5 bytes
let last = tftp_is_last_block(&data);         // Ok(true)
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.tftp
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only.** No socket, no session state machine, no retransmission,
  no timeouts, no server or client. This package turns packets into bytes
  and bytes into packets; `xiom.net.socket`/UDP plumbing is a separate
  concern.
- **Octet mode only by convention.** `mode` is an opaque string here: the
  codec neither defaults it to `"octet"` nor rejects `"netascii"`/`"mail"`.
  Use `"octet"` for the binary-safe behavior the 512-byte block rule
  assumes.
- **No RFC 2347 option negotiation.** Bytes after the mode terminator are
  ignored on parse (so option-filled requests still decode), and no
  `blksize`/`timeout`/`tsize` helpers exist.
- **512-byte block size is the only block rule.** `tftp_is_last_block` is
  `payload < 512`; negotiated `blksize` values are out of scope.
- **No NUL validation on encode.** A filename, mode or message containing
  an embedded `0x00` produces a packet that violates the format; the codec
  copies strings verbatim.
- **No UTF-8 validation on decode.** Parsed strings carry the packet bytes
  verbatim (a legal TFTP name is not required to be UTF-8).
- **Error strings, not error codes.** All failures are `Err(Str)` with a
  stable `tftp: ...` text (catalog in `SPEC.md`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
