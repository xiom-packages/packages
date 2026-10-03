# xiom.firebird

> **Status:** `incubating` -- conformance-tested (22/22); not yet published.
> **Scope:** structural codec for the Firebird wire protocol, canonical-XDR
> subset: the opcode registry, the connect/accept blocks, the attach block,
> the data block, the single-object release block and the start-transaction
> block. No sockets, no authentication, no compression, no server.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare` and `xiom.convert`). Tests additionally use
> `xiom.encoding.hex`, `xiom.test` and `xiom.io`.

## What it is

`xiom.firebird` is a pure-XIOM, dependency-free **structural** codec for the
Firebird client/server wire protocol, modelled on the published
`xiom.mysql` / `xiom.mssql` / `xiom.db2` packages. It turns the bytes a
transport would carry into typed XIOM values and back: it never performs
I/O, never keeps connection state and never looks inside SQL.

The documented subset is pinned to the Firebird master sources:

- **Canonical XDR encoding** as negotiated with `arch_generic`: every
  short/long/enum/unsigned field is a 32-bit big-endian word; a counted
  string is a 32-bit length, the bytes, then zero padding to the 4-byte
  boundary; a packet body is `[4-byte opcode][fields]` with **no transport
  length prefix** -- packets are self-delimiting and a fragmented receive
  surfaces upstream as `op_partial`.
- **Opcode registry** -- 75 names pinned to the upstream `P_OP` enum
  (`src/remote/protocol.h`), including the deliberately unregistered
  commented-out slots.
- **Blocks** -- connect (`P_CNCT`), accept (`P_ACPT`), attach / create /
  service-attach (`P_ATCH`), the five-word data block (`P_DATA`), the
  single-object release block (`P_RLSE`), the start-transaction block
  (`P_STTR`) and the fieldless packets (reject, disconnect, dummy, ping,
  abort_aux_connection, batch_sync).

## API

| Function | Returns | Description |
|---|---|---|
| `firebird_packet_opcode(bytes)` | `Int` | First big-endian word; `-1` for a short packet. |
| `firebird_opcode_of(name)` | `Int` | Numeric opcode; `-1` when unregistered. |
| `firebird_opcode_name(code)` | `Str` | Name; `""` when unregistered. |
| `firebird_opcode_known(code)` | `Bool` | Registry membership. |
| `firebird_opcode_count()` | `Int` | Size of the registry (75). |
| `firebird_empty_packet_emit(op)` | `Result[Vec[UInt8], Str]` | Opcode-only packet for the six fieldless ops. |
| `firebird_connect_new()` | `FbConnect` | Default offer (version 3, arch_generic). |
| `firebird_connect_add_version(c, protocol, arch, min_type, max_type, weight)` | nothing | Append one offered protocol. |
| `firebird_connect_emit(c)` / `firebird_connect_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbConnect, Str]` | Connect block codec. |
| `firebird_accept_emit(version, architecture, ptype)` / `firebird_accept_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbAccept, Str]` | Accept block codec. |
| `firebird_attach_emit(op, database, file, dpb)` / `firebird_attach_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbAttach, Str]` | Attach/create/service-attach codec. |
| `firebird_data_emit(op, request, incarnation, transaction, message_number, messages)` / `firebird_data_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbData, Str]` | Data block codec. |
| `firebird_object_emit(op, object)` / `firebird_object_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbObject, Str]` | Single-object release codec. |
| `firebird_transaction_emit(op, database, tpb)` / `firebird_transaction_parse(bytes)` | `Result[Vec[UInt8], Str]` / `Result[FbTransaction, Str]` | Start-transaction/reconnect codec. |

## Usage

```xi
use xiom.firebird;
use xiom.io;
use xiom.convert;
use xiom.encoding.hex;

fn main() -> Int {
  var c = firebird_connect_new();
  c.file = "employee.fdb";
  firebird_connect_add_version(&mut c, 32783, 1, 0, 5, 1);   // protocol 0x800F

  let e = firebird_connect_emit(&c);
  match e {
    Ok(bytes) => {
      io.println(hex.hex_encode(&bytes));            // canonical packet hex
      let p = firebird_connect_parse(bytes);
      match p {
        Ok(parsed) => { io.println(parsed.file); },  // employee.fdb
        Err(err) => { io.println(err); },
      }
    },
    Err(err) => { io.println(err); },
  }

  let ping = firebird_empty_packet_emit(firebird_opcode_of("ping"));
  match ping {
    Ok(bytes) => { io.println(hex.hex_encode(&bytes)); },  // 0000005d
    Err(err) => { io.println(err); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.firebird
```

Expected tail: 22 `[PASS]` lines, `xiom.firebird: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- Canonical (`arch_generic`) XDR only: host-native architectures, big-endian
  negotiation variants and symmetric-port layouts are out of scope.
- No compression, wire crypt, authentication flow, status-vector bodies or
  message-format (BLR) payloads; the response/execute/fetch families are
  registered but not decoded field-by-field.
- No transport: no sockets, no length prefix handling (there is none on this
  wire format), no `op_partial` reassembly -- the caller owns framing.
- Parsers ignore bytes after the decoded block (structural subset).
- A counted string is stored as UTF-8 text; embedded NUL bytes do not survive
  the `Str` round trip.
- Opcodes are checked against the documented block families, but a
  mislabelled payload is not semantically validated beyond that.
- In-memory only: no FFI, no file I/O.

See `SPEC.md` for the wire model, opcode table, error catalog and test
matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
