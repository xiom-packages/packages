# xiom.firebird -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.firebird` (`src/firebird.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope

A structural codec for the Firebird wire protocol, canonical-XDR subset:

- `firebird_packet_opcode` reads a packet's opcode;
- the opcode registry (`firebird_opcode_of/name/known/count`);
- emit/parse pairs for the connect, accept, attach, data, single-object and
  start-transaction blocks;
- `firebird_empty_packet_emit` for the fieldless packets.

The caller supplies and receives byte vectors; the package never performs
I/O, keeps connection state, or parses SQL. All wire constants are pinned to
the Firebird master sources `src/remote/protocol.h` (opcodes, block structs)
and `src/remote/protocol.cpp` (field layouts, XDR cstring padding).

## 2. Non-goals

- **No transport**: no sockets, no framing, no partial-packet reassembly.
- **No host-native XDR**: only the canonical big-endian forms negotiated with
  `arch_generic`; other architectures are out of scope.
- **No compression or wire crypt** (`pflag_compress`, `op_crypt` are
  registered but their field bodies are not implemented).
- **No authentication flow**: `op_cont_auth`, `op_trusted_auth`,
  `op_authenticate_user` payloads are out of scope.
- **No message payloads**: BLR-format messages, status-vector bodies, batch
  data and blob streams are not decoded.
- No FFI, no file I/O, no server.

## 3. Wire model

```
packet   = u32 opcode, fields(opcode)
u32      = 4 bytes, big-endian (canonical XDR short/long/enum/unsigned)
cstring  = u32 length, <length> bytes, zero padding to a 4-byte multiple
```

There is **no transport length prefix**: a packet is self-delimiting by its
opcode-and-fields layout. TCP fragmentation is handled upstream by buffering
with `op_partial`; this package's parsers therefore decode a complete packet
and ignore any bytes after the block they decode. Field widths: every
`xdr_short`, `xdr_u_short`, `xdr_enum` and `xdr_long` is 4 bytes; `xdr_quad`
is 8 bytes (not used by the implemented blocks).

Verified representative vectors (also pinned in the suite):

| Packet | Bytes |
|---|---|
| `ping` | `0000005d` |
| `dummy` | `00000047` |
| `accept(0x800F, 1, 5)` | `00000003 0000800F 00000001 00000005` |
| `attach(19, 7, "abc", "")` | `00000013 00000007 00000003 616263 00 00000000` |
| `data(25, 1, 2, 3, 4, 5)` | `00000019 00000001 00000002 00000003 00000004 00000005` |
| `object(30, 7)` | `0000001e 00000007` |
| `transaction(29, 9, "tpb")` | `0000001d 00000009 00000003 747062 00` |

## 4. Opcode registry

75 names pinned to the upstream `P_OP` enum; the commented-out upstream
slots (5, 7, 8, 10-18, 27, 45-47, 60, 72, 75-77, 87, 88, 90, 96-98, 104-108,
111) are deliberately unregistered:

```
connect=1 exit=2 accept=3 reject=4 disconnect=6 response=9
attach=19 create=20 detach=21 compile=22 start=23 start_and_send=24
send=25 receive=26 release=28 transaction=29 commit=30 rollback=31
prepare=32 reconnect=33 create_blob=34 open_blob=35 get_segment=36
put_segment=37 cancel_blob=38 close_blob=39 info_database=40
info_request=41 info_transaction=42 info_blob=43 que_events=48
cancel_events=49 commit_retaining=50 prepare2=51 event=52
connect_request=53 aux_connect=54 ddl=55 allocate_statement=62
execute=63 exec_immediate=64 fetch=65 fetch_response=66
free_statement=67 prepare_statement=68 set_cursor=69 info_sql=70
dummy=71 start_and_receive=73 start_send_and_receive=74 sql_response=78
transact=79 transact_response=80 drop_database=81 service_attach=82
service_detach=83 service_info=84 service_start=85 rollback_retaining=86
partial=89 cancel=91 cont_auth=92 ping=93 accept_data=94
abort_aux_connection=95 batch_create=99 batch_msg=100 batch_exec=101
batch_rls=102 batch_cs=103 batch_cancel=109 batch_sync=110
fetch_scroll=112 info_cursor=113 inline_blob=114
```

## 5. Block layouts

| Block | Opcodes | Fields after the opcode |
|---|---|---|
| fieldless | 4, 6, 71, 93, 95, 110 | none |
| connect | 1 | operation, cversion, client_arch, file (cstring), count, user_id (cstring), then count x (version, architecture, min_type, max_type, weight) |
| accept | 3 | version, architecture, ptype |
| attach | 19, 20, 82 | database, file (cstring), dpb (cstring) |
| data | 23, 24, 25, 26, 73, 74 | request, incarnation, transaction, message_number, messages |
| object | 21, 28, 30, 31, 32, 38, 39, 50, 62, 81, 83, 86, 102, 109 | object |
| transaction | 29, 33 | database, tpb (cstring) |

The connect block's `count` may not exceed 11 (`MAX_CNCT_VERSIONS`).

## 6. Error catalog

All messages are prefixed `firebird: `.

| Condition | Exact message |
|---|---|
| Packet shorter than the block, or a cstring running past the end | `truncated packet` |
| Connect/accept parse with a different opcode | `unexpected opcode <n>` |
| Attach parse/emit with an opcode outside 19/20/82 | `not an attach opcode <n>` |
| Data parse/emit with an opcode outside 23/24/25/26/73/74 | `not a data opcode <n>` |
| Object parse/emit with an opcode outside the release family | `not a release opcode <n>` |
| Transaction parse/emit with an opcode outside 29/33 | `not a transaction opcode <n>` |
| Fieldless emit with any other opcode | `not a fieldless opcode <n>` |
| Emitted field outside 0..65535 (u16 fields) or 0..4294967295 (u32 fields) | `field out of range <v>` |
| Connect parse/emit with more than 11 offered protocols | `too many connect versions <n>` |
| Connect emit with unequal version-array lengths | `misaligned connect versions` |

## 7. API contract

```xi
pub fn firebird_packet_opcode(bytes: &Vec[UInt8]) -> Int
pub fn firebird_opcode_of(name: Str) -> Int
pub fn firebird_opcode_name(code: Int) -> Str
pub fn firebird_opcode_known(code: Int) -> Bool
pub fn firebird_opcode_count() -> Int
pub fn firebird_empty_packet_emit(op: Int) -> Result[Vec[UInt8], Str]
pub fn firebird_connect_new() -> FbConnect
pub fn firebird_connect_add_version(c: &mut FbConnect, protocol: Int, arch: Int, min_type: Int, max_type: Int, weight: Int)
pub fn firebird_connect_emit(c: &FbConnect) -> Result[Vec[UInt8], Str]
pub fn firebird_connect_parse(bytes: Vec[UInt8]) -> Result[FbConnect, Str]
pub fn firebird_accept_emit(version: Int, architecture: Int, ptype: Int) -> Result[Vec[UInt8], Str]
pub fn firebird_accept_parse(bytes: Vec[UInt8]) -> Result[FbAccept, Str]
pub fn firebird_attach_emit(op: Int, database: Int, file: Str, dpb: Str) -> Result[Vec[UInt8], Str]
pub fn firebird_attach_parse(bytes: Vec[UInt8]) -> Result[FbAttach, Str]
pub fn firebird_data_emit(op: Int, request: Int, incarnation: Int, transaction: Int, message_number: Int, messages: Int) -> Result[Vec[UInt8], Str]
pub fn firebird_data_parse(bytes: Vec[UInt8]) -> Result[FbData, Str]
pub fn firebird_object_emit(op: Int, object: Int) -> Result[Vec[UInt8], Str]
pub fn firebird_object_parse(bytes: Vec[UInt8]) -> Result[FbObject, Str]
pub fn firebird_transaction_emit(op: Int, database: Int, tpb: Str) -> Result[Vec[UInt8], Str]
pub fn firebird_transaction_parse(bytes: Vec[UInt8]) -> Result[FbTransaction, Str]
```

Complexity: O(1) for accept/data/object/fieldless packets; O(total string
length) for connect/attach/transaction; the opcode registry is O(table).

## 8. Test matrix

`tests/test_conformance.xi` (module `firebird_tests`) runs 22 named checks
through `assert(cond, "name")` and returns the failure count from `main`.
Byte-exact vectors use `xiom.encoding.hex`; round trips compare every field.

| # | Check | Contract pinned |
|---|---|---|
| t1 | packet opcode | wire model |
| t2 | registry values and count (75) | section 4 |
| t3 | fieldless packets | section 5 |
| t4 | default connect header | section 5 |
| t5 | connect with one version (byte-exact) | sections 3, 5 |
| t6 | connect round trip (two versions) | section 5 |
| t7 | connect parse errors | section 6 |
| t8 | connect emit validation | sections 5, 6 |
| t9 | accept byte-exact + round trip | section 3 |
| t10 | cstring padding (byte-exact) | section 3 |
| t11 | attach round trip + service_attach | section 5 |
| t12 | attach opcode validation | section 6 |
| t13 | data byte-exact + round trip | section 3 |
| t14 | data opcode family | sections 5, 6 |
| t15 | object family round trip | section 5 |
| t16 | object opcode validation | section 6 |
| t17 | transaction byte-exact + reconnect | sections 3, 5 |
| t18 | short packets | section 6 |
| t19 | cstring truncation | section 6 |
| t20 | trailing bytes ignored | section 3 |
| t21 | field range validation | section 6 |
| t22 | registry name/lookup round trip | section 4 |

## 9. Known limitations

- Canonical XDR only; host-native layouts and XDR quads are not implemented.
- Only the listed block families; response, execute, fetch, blob, batch,
  info and auth bodies are registered but not decoded.
- A counted string becomes a `Str`; embedded NUL bytes do not survive.
- Parsers ignore trailing bytes and do not validate semantic compatibility
  beyond the documented opcode families.
- No framing, partial reassembly, compression or crypt.

## 10. Compiler / stdlib notes (v0.62.2)

Free functions only; flat parallel Vecs instead of `Vec[StructType]`;
`Result` construction confined to leaf helpers; every `Vec[UInt8]` element
read bound to a typed local before widening (`(b as Int) & 255`); mutating
`Vec` parameters passed with an explicit `&mut`. The byte reader uses a
sticky error flag instead of out-parameters, avoiding the v0.62.2 `&mut Int`
write-drop finding. Hex literals in the suite use `xiom.encoding.hex`.
The suite is green on v0.62.2 with `program_exit=0`.
