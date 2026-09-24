# xiom.pcap

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) reader for classic PCAP capture files: magic
> and byte-order detection, the 24-byte global header, and the 16-byte
> packet-record index (timestamps, captured/original lengths, payload
> offsets). Parse-only: no capture writing.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.pcap` parses the classic libpcap file format (the one produced by
`tcpdump`, Wireshark, `dumpcap` and friends -- **not** the newer pcapng).
A capture file is a 24-byte global header followed by any number of packet
records:

```
[global header: magic, version 2.4, thiszone, sigfigs, snaplen, linktype]
[record: ts_sec, ts_usec, incl_len, orig_len, incl_len packet bytes]
[record: ...]
```

`pcap_parse` detects the file's byte order from the magic (little-endian
files start `D4 C3 B2 A1`, big-endian files `A1 B2 C3 D4`), reads every
field with that order, and returns a `PcapFile` index. The packet bytes are
not copied: each record stores the absolute offset and captured length, and
`pcap_packet` slices the payload out of the original buffer on demand.
Malformed input is rejected with a documented error string (see `SPEC.md`).

## File layout

Global header, 24 bytes:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | magic | `D4 C3 B2 A1` little-endian file, `A1 B2 C3 D4` big-endian file |
| 4 | 2 | version_major | 2 in practice (read, not enforced) |
| 6 | 2 | version_minor | 4 in practice (read, not enforced) |
| 8 | 4 | thiszone | GMT offset; skipped |
| 12 | 4 | sigfigs | timestamp accuracy; skipped |
| 16 | 4 | snaplen | snapshot length in bytes |
| 20 | 4 | linktype (`network`) | 1 = Ethernet, 101 = raw IP, ... |

Packet record, 16-byte header + payload:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | ts_sec | capture timestamp, whole seconds |
| 4 | 4 | ts_usec | microseconds part; skipped |
| 8 | 4 | incl_len | captured bytes actually stored (caplen) |
| 12 | 4 | orig_len | original on-the-wire length |
| 16 | `incl_len` | packet bytes | located by `offsets[i]` / `caplens[i]` |

Every multi-byte field is read with the byte order detected from the magic.
Records are not padded or aligned; the next record starts immediately after
the payload.

## API

| Function | Returns | Description |
|---|---|---|
| `pcap_is_file(data)` | `Bool` | `data.len() >= 24` and either classic magic. |
| `pcap_parse(data)` | `Result[PcapFile, Str]` | Whole-file index; Err on truncation or bad magic. |
| `pcap_packet_count(p)` | `Int` | Number of packet records. |
| `pcap_packet(data, p, i)` | `Result[Vec[UInt8], Str]` | `caplens[i]` payload bytes at `offsets[i]`. |
| `pcap_caplen(p, i)` | `Int` | Captured length of record `i`; -1 out of range. |
| `pcap_origlen(p, i)` | `Int` | Original length of record `i`; -1 out of range. |
| `pcap_ts_sec(p, i)` | `Int` | Timestamp seconds of record `i`; -1 out of range. |
| `pcap_linktype(p)` | `Int` | The global header `network` field. |

`pub type PcapFile = { magic: Int; little_endian: Bool; version_major: Int;
version_minor: Int; snaplen: Int; linktype: Int; ts_secs: Vec[Int];
caplens: Vec[Int]; origlens: Vec[Int]; offsets: Vec[Int]; }` -- `magic` is
the magic read with the detected endianness (always `0xA1B2C3D4` /
2712847316 on success); the four Vec fields hold one entry per record.

Errors: `Err("pcap: truncated header")`, `Err("pcap: bad magic")`,
`Err("pcap: truncated record")`, `Err("pcap: truncated packet")`,
`Err("pcap: packet out of range")` (see `SPEC.md`).

## Usage

```xi
use xiom.pcap;
use xiom.convert;
use xiom.io;

var capture = Vec[UInt8].new();
// ... fill `capture` with the file bytes ...

if !pcap_is_file(&capture) {
  io.println("not a classic pcap file");
} else {
  let parsed = pcap_parse(&capture);
  match parsed {
    Ok(p) => {
      io.println("packets: " + convert.int_to_string(pcap_packet_count(&p)));
      let first = pcap_packet(&capture, &p, 0);
      match first {
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
& .\scripts\port.ps1 -Package xiom.pcap
```

Expected: the namespace check passes, 17 `[PASS]` lines, and a final
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Classic PCAP only, no pcapng.** The pcapng section header block starts
  `0A 0D 0D 0A`, which is rejected as `pcap: bad magic`; there is no
  enhanced-packet, interface-description or name-resolution-block support.
- **No protocol decoding.** Payloads are opaque bytes; linktype is reported
  but Ethernet/IP/TCP headers are not parsed here.
- **Parse-only.** The module never writes capture files.
- **In-memory buffers.** `pcap_parse` and `pcap_packet` operate on
  `Vec[UInt8]`, not streams; the source buffer must outlive the `PcapFile`
  index passed back to `pcap_packet`.
- **Timestamps are whole seconds.** `ts_usec` is skipped and not indexed.
- **No capture validation beyond structure.** Version, snaplen and the
  `caplen <= snaplen` relation are reported, not enforced; `origlen` may be
  less than `caplen` in a malformed file and is returned verbatim.
- **`pcap_parse` is all-or-nothing.** On the first malformed record the
  whole call is `Err`; the valid prefix is not returned.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
