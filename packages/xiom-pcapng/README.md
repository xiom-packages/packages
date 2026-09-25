# xiom.pcapng

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) reader for PCAP Next Generation (pcapng)
> capture files: the flat block index, byte-order-aware SHB/IDB/EPB/SPB/NRB/
> ISB parsing, option TLV spans and raw-body preservation for unknown block
> types. Parse-only: no capture writing.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`.

## What it is

`xiom.pcapng` parses the pcapng container format produced by Wireshark,
`dumpcap` and friends (the successor of classic pcap). A pcapng file is a
sequence of blocks:

```
[block: type, total length, body, trailing total length]
[block: ...]
```

Each block's trailing total length must equal its leading copy. The first
block is a Section Header Block (SHB) carrying the byte-order magic
`0x1A2B3C4D`; the section's byte order is detected from it and every
multi-byte field of that section's blocks is read with it. `pcapng_parse`
walks the whole buffer and returns a `PcapngFile` index: one entry per block
(type, absolute offset, total/body length, section ordinal) plus parallel
pools for section headers, interfaces, packets, name-resolution records and
options. Packet data, option values, record addresses and DNS names stay in
the source buffer and are located by offset/length; the copy functions slice
them out on demand. Blocks of unknown type keep their raw body span.
Malformed input is rejected with a documented error string (see `SPEC.md`).

## Block types

| Type | Name | Parsed into |
|---|---|---|
| `0x0A0D0D0A` (168627466) | Section Header Block | section order, version, section length, options |
| 1 | Interface Description Block | linktype, snaplen, options |
| 3 | Simple Packet Block | original length + data span |
| 4 | Name Resolution Block | IPv4/IPv6 records + DNS name spans |
| 5 | Interface Statistics Block | interface, ifrecv/ifdrop 64-bit counters, options |
| 6 | Enhanced Packet Block | interface, 64-bit timestamp, caplen/origlen, data span, options |
| anything else | unknown (including obsolete Packet Block 2) | raw body span preserved |

Options are TLV entries (u16 code, u16 length, value padded to a 4-byte
boundary); code 0 ends the list. Every block type an SHB introduces begins a
new section; interfaces are numbered globally across sections.

## API

| Function | Returns | Description |
|---|---|---|
| `pcapng_is_file(data)` | `Bool` | 12+ bytes and the SHB type bytes `0A 0D 0D 0A`. |
| `pcapng_parse(data)` | `Result[PcapngFile, Str]` | Whole-file index; Err on malformation. |
| `pcapng_block_count(p)` | `Int` | Number of blocks. |
| `pcapng_block_type/offset/body_offset/body_length/section(p, i)` | `Int` | Block index fields; -1 out of range. |
| `pcapng_block_body(data, p, i)` | `Result[Vec[UInt8], Str]` | Raw body copy (works for unknown types). |
| `pcapng_section_count(p)` | `Int` | Number of SHB sections. |
| `pcapng_section_order/major/minor/length(p, s)` | `Int` | Order (1 LE / 0 BE), version, declared length (-1 unspecified); -1 out of range. |
| `pcapng_interface_count(p)` | `Int` | Number of IDBs. |
| `pcapng_interface_linktype/snaplen/block/section(p, i)` | `Int` | Interface fields; -1 out of range. |
| `pcapng_packet_count(p)` | `Int` | EPB + SPB records. |
| `pcapng_packet_kind(p, i)` | `Int` | 0 = EPB, 1 = SPB; -1 out of range. |
| `pcapng_packet_block/section/interface(p, i)` | `Int` | Links; interface is the global ordinal (-1 for SPB). |
| `pcapng_packet_ts_high/ts_low/timestamp(p, i)` | `Int` | 64-bit timestamp; 0 for SPB; -1 out of range. |
| `pcapng_packet_caplen/origlen/data_offset(p, i)` | `Int` | Captured data span; -1 out of range. |
| `pcapng_packet_data(data, p, i)` | `Result[Vec[UInt8], Str]` | Captured data copy. |
| `pcapng_record_count/type/block/name_count(p, r)` | `Int` | NRB records (1 = IPv4, 2 = IPv6); -1 out of range. |
| `pcapng_record_address(data, p, r)` | `Result[Vec[UInt8], Str]` | Address copy (4 or 16 bytes). |
| `pcapng_name_count(p)` | `Int` | DNS names across records. |
| `pcapng_name_record/offset/length(p, n)` | `Int` | Name linkage and span; -1 out of range. |
| `pcapng_name_bytes(data, p, n)` | `Result[Vec[UInt8], Str]` | Name copy (no NUL). |
| `pcapng_isb_count(p)` | `Int` | Interface statistics blocks. |
| `pcapng_isb_interface/block/ifrecv/ifdrop(p, i)` | `Int` | ISB links and 64-bit counters (-1 absent/out of range). |
| `pcapng_option_count(p)` | `Int` | Indexed options across SHB/IDB/EPB/ISB. |
| `pcapng_option_block/code/offset/length(p, i)` | `Int` | Option span; -1 out of range. |
| `pcapng_option_find(p, block, code)` | `Int` | First match in file order; -1 absent/invalid block. |
| `pcapng_option_value(data, p, i)` | `Result[Vec[UInt8], Str]` | Option value copy (no padding). |

Errors: `Err("pcapng: truncated block header")`, `Err("pcapng: bad block
length")`, `Err("pcapng: total length mismatch")`, `Err("pcapng: section
header block must be first")`, `Err("pcapng: bad byte-order magic")`,
`Err("pcapng: unsupported version")`, `Err("pcapng: span out of bounds")`
and the rest of the catalog in `SPEC.md`.

## Usage

```xi
use xiom.pcapng;
use xiom.convert;
use xiom.io;

var capture = Vec[UInt8].new();
// ... fill `capture` with the file bytes ...

if !pcapng_is_file(&capture) {
  io.println("not a pcapng file");
} else {
  let parsed = pcapng_parse(&capture);
  match parsed {
    Ok(p) => {
      io.println("sections: " + convert.int_to_string(pcapng_section_count(&p)));
      io.println("packets: " + convert.int_to_string(pcapng_packet_count(&p)));
      let data = pcapng_packet_data(&capture, &p, 0);
      match data {
        Ok(bytes) => { io.println("first packet bytes: " + convert.int_to_string(bytes.len())); },
        Err(e) => { io.println("packet error: " + e); },
      }
    },
    Err(e) => { io.println("parse error: " + e); },
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.pcapng
```

Expected: the namespace check passes, 19 `[PASS]` lines, and a final
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Read-only.** The module never writes or repairs capture files.
- **No packet dissection.** Payloads are opaque byte spans; linktype is
  reported but Ethernet/IP/TCP headers are not parsed.
- **No name resolution.** NRB record types 1 (IPv4) and 2 (IPv6) are parsed
  into address and DNS name spans; names are bytes, not `Str`, and nothing
  is resolved.
- **Unknown blocks are opaque.** Obsolete Packet Block (type 2), Decryption
  Secrets Block and future types are indexed with their body span only.
- **SPB is strict.** The data region must equal `origlen` padded to 4 bytes;
  an SPB with a snaplen-truncated payload is rejected.
- **Interface references must precede use.** An EPB/ISB may only name an
  interface declared by an earlier IDB in the same section.
- **No compression, no streaming.** Whole-buffer `Vec[UInt8]` parsing only;
  copy functions allocate per call and the source buffer must outlive the
  index.
- **`pcapng_parse` is all-or-nothing.** On the first malformed block the
  whole call is `Err`; the valid prefix is not returned.
- **64-bit composition is signed.** Timestamps/counters with bit 63 set are
  not representable and overflow.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
