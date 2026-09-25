# xiom.dns

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) DNS message wire codec
> (RFC 1035 subset): 12-byte header, domain names with compression-pointer
> decoding, questions, and A/AAAA/CNAME/MX/TXT resource records.
> **Deps:** `xiom.std` only. The library module imports only `xiom.string`
> and `xiom.string.builder`; the tests use `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.builder`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.dns` turns DNS messages into bytes and bytes into DNS messages. It is
a codec, not a resolver: it does not open sockets, send queries, retry,
cache or validate DNSSEC. What it does cover is the wire format of the
common record types, with deterministic error strings for malformed input:

- the header and its packed flags word (QR, Opcode, AA, TC, RD, RA, Z,
  RCODE) plus the four section counts;
- domain names: label-aware encoding with the 1..63-byte label and 255-byte
  name limits, and decoding that follows compression pointers with loop and
  out-of-range detection;
- questions and generic resource records;
- typed RDATA builders and parsers for A, AAAA, CNAME, MX and TXT;
- a query builder and a whole-message parser that indexes every question
  and record by offset.

Builders never emit compression pointers, so their output is always
self-contained. See `SPEC.md` for the byte layout, error catalog and the
exact subset.

## API

| Function | Returns | Description |
|---|---|---|
| `dns_header_encode(h)` | `Vec[UInt8]` | 12-byte header; fields masked to their bit width. |
| `dns_header_decode(data)` | `Result[DnsHeader, Str]` | Parse the header; `Err` below 12 bytes. |
| `dns_name_encode(name)` | `Result[Vec[UInt8], Str]` | Dotted name -> labels + terminating `0x00`. |
| `dns_name_decode(data, off)` | `Result[DnsName, Str]` | Decode a name at `off`, following compression pointers. |
| `dns_name_to_str(n)` | `Str` | Presentation form (`a.b.c`, root is `""`). |
| `dns_question_encode(name, qtype, qclass)` | `Result[Vec[UInt8], Str]` | One question entry. |
| `dns_question_parse(data, off)` | `Result[DnsQuestion, Str]` | Name, QTYPE, QCLASS, next offset. |
| `dns_rr_encode(name, rtype, rclass, ttl, rdata)` | `Result[Vec[UInt8], Str]` | One resource record. |
| `dns_rr_parse(data, off)` | `Result[DnsRecord, Str]` | Name, TYPE, CLASS, TTL and the RDATA span. |
| `dns_rr_rdata(data, r)` | `Result[Vec[UInt8], Str]` | Copy a parsed record's RDATA out. |
| `dns_rdata_a(octets)` | `Result[Vec[UInt8], Str]` | A RDATA from exactly 4 octets. |
| `dns_rdata_aaaa(octets)` | `Result[Vec[UInt8], Str]` | AAAA RDATA from exactly 16 octets. |
| `dns_rdata_cname(name)` | `Result[Vec[UInt8], Str]` | CNAME RDATA (uncompressed target name). |
| `dns_rdata_mx(preference, exchange)` | `Result[Vec[UInt8], Str]` | MX RDATA: u16 preference + exchange name. |
| `dns_rdata_txt(text)` | `Result[Vec<UInt8>, Str]` | TXT RDATA: one character-string (<= 255 bytes). |
| `dns_rdata_a_to_str(rdata)` | `Result[Str, Str]` | 4 bytes -> `"a.b.c.d"`. |
| `dns_rdata_aaaa_to_str(rdata)` | `Result[Str, Str]` | 16 bytes -> full-form IPv6. |
| `dns_rdata_name(data, off, len)` | `Result[DnsName, Str]` | Name stored in RDATA (CNAME/MX target). |
| `dns_rdata_mx_preference(data, off, len)` | `Result[Int, Str]` | MX preference field. |
| `dns_rdata_mx_exchange(data, off, len)` | `Result[DnsName, Str]` | MX exchange name. |
| `dns_rdata_txt_parse(rdata)` | `Result[Str, Str]` | The single character-string of a TXT RDATA. |
| `dns_query_build(id, name, qtype)` | `Result[Vec[UInt8], Str]` | Standard recursive query, one question, class IN. |
| `dns_message_parse(data)` | `Result[DnsMessage, Str]` | Whole message: header + offsets of every entry. |
| `dns_message_question_count(m)` | `Int` | Number of indexed questions. |
| `dns_message_record_count(m)` | `Int` | Number of indexed records (AN + NS + AR). |
| `dns_message_question_offset(m, i)` | `Int` | Name offset of question `i`; `-1` out of range. |
| `dns_message_record_offset(m, i)` | `Int` | Name offset of record `i`; `-1` out of range. |

Constants: `DNS_TYPE_A` (1), `DNS_TYPE_CNAME` (5), `DNS_TYPE_MX` (15),
`DNS_TYPE_TXT` (16), `DNS_TYPE_AAAA` (28), `DNS_CLASS_IN` (1).

Errors are `Err("dns: ...")` strings; the full catalog is in `SPEC.md`.

## Wire format

Header (12 bytes, big-endian): `ID[2] FLAGS[2] QDCOUNT[2] ANCOUNT[2]
NSCOUNT[2] ARCOUNT[2]`, where FLAGS packs QR (bit 15), Opcode (14..11),
AA (10), TC (9), RD (8), RA (7), Z (6..4) and RCODE (3..0).

Names are label sequences: `len label` repeated, then `0x00`. A two-byte
value with top bits `11` is a compression pointer to an offset (decode
only). A question is `QNAME QTYPE[2] QCLASS[2]`; a record is
`NAME TYPE[2] CLASS[2] TTL[4] RDLENGTH[2] RDATA`.

```text
query for www.example.com A, id 0x1234:
12 34 01 00 00 01 00 00 00 00 00 00   header (RD=1, QDCOUNT=1)
03 77 77 77 07 65 78 61 6d 70 6c 65 03 63 6f 6d 00   QNAME
00 01 00 01                            QTYPE=A, QCLASS=IN
```

RDATA: A = 4 octets, AAAA = 16 octets, CNAME = name, MX = u16 preference
+ name, TXT = one length-prefixed character-string.

## Usage

```xi
use xiom.dns;
use xiom.io;

// Build a query: id 0x1234, www.example.com, type A.
let q = dns_query_build(4660, "www.example.com", DNS_TYPE_A);
match q {
  Ok(bytes) => { io.println("query is " + bytes.len().to_str() + " bytes"); },
  Err(e) => { io.println("bad query: " + e); },
}

// Parse a message and walk the questions.
let parsed = dns_message_parse(&query_bytes);
if parsed.is_ok {
  let m = parsed.value;
  io.println("answers: " + dns_message_record_count(&m).to_str());
  let i = 0;
  while i < dns_message_question_count(&m) {
    let off = dns_message_question_offset(&m, i);
    let qr = dns_question_parse(&query_bytes, off);
    match qr {
      Ok(q) => { io.println(dns_name_to_str(&q.name)); },   // "www.example.com"
      Err(e) => { io.println("bad question: " + e); },
    }
    i = i + 1;
  }
}

// Build an answer record and decode its RDATA.
var ip = Vec[UInt8].new();
ip.push(192); ip.push(0); ip.push(2); ip.push(1);
let rdata = dns_rdata_a(&ip);
if rdata.is_ok {
  let rd: Vec[UInt8] = rdata.value;
  let rr = dns_rr_encode("example.com", DNS_TYPE_A, DNS_CLASS_IN, 300, &rd);
  // rr is a complete resource record ready to append to a response.
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.dns
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only.** No socket, resolver, cache, retry or timeout logic;
  transport and retransmission are the caller's concern.
- **No compression on output.** Builders write full names, so rebuilt
  messages decode identically to a compressed original but are not
  byte-identical to it. Compression is decode-only.
- **`Str` is NUL-terminated.** A decoded label containing `0x00` cannot be
  represented and is rejected (`dns: label contains NUL byte`); a TXT text
  containing `0x00` truncates the parsed string at that byte.
- **One character-string per TXT.** Multi-string TXT RDATA is rejected by
  `dns_rdata_txt_parse` (the generic record parser still carries it as raw
  bytes).
- **Minimal presentation layer.** No name escape syntax, no IDNA/punycode,
  no IPv6 `::` compression on output.
- **Subset of record types.** Typed helpers exist for A, AAAA, CNAME, MX
  and TXT; other types (NS, SOA, SRV, OPT, DNSSEC) travel as raw RDATA.
  The Z bits are carried opaquely; there is no DNSSEC or EDNS(0) handling.
- **`dns_message_parse` ignores trailing bytes** after the last declared
  entry.
- **Error strings, not error codes.** All failures are `Err(Str)` with a
  stable `dns: ...` text (catalog in `SPEC.md`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
