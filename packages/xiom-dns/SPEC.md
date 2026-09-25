# xiom.dns -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.dns`, version `0.1.0`).
Module: `src/dns.xi` (`module xiom.dns`).
Depends on `xiom.std`; the library module imports only `xiom.string` and
`xiom.string.builder` (the tests add `xiom.test`, `xiom.io`,
`xiom.string`, `xiom.string.builder`, `xiom.string.compare` and
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI, no sockets) DNS message wire codec for the RFC 1035
subset listed here:

- `dns_header_encode` / `dns_header_decode`: the 12-byte header, including
  the packed flags word (QR, Opcode, AA, TC, RD, RA, Z, RCODE) and the four
  section counts;
- `dns_name_encode` / `dns_name_decode` / `dns_name_to_str`: domain names as
  length-prefixed labels; decoding follows compression pointers (with loop
  and out-of-range detection), encoding never emits them;
- `dns_question_encode` / `dns_question_parse`: the question section
  (QNAME, QTYPE, QCLASS);
- `dns_rr_encode` / `dns_rr_parse` / `dns_rr_rdata`: generic resource
  records (NAME, TYPE, CLASS, TTL, RDLENGTH, RDATA span);
- RDATA helpers for A, AAAA, CNAME, MX and TXT (builders and parsers);
- `dns_query_build`: a standard recursive query with one question;
- `dns_message_parse` plus count/offset accessors: whole-message parsing
  that indexes the questions and resource records by offset.

Errors are deterministic `Err(Str)` strings; the full catalog is below.

## Non-goals

- Socket I/O, retries, timeouts, transport (UDP/TCP), message IDs handled
  across requests, caching or servers/clients.
- DNSSEC (RRSIG/DNSKEY/DS), the AD/CD bits (the three Z bits are carried as
  opaque `z`, not interpreted) and EDNS(0) OPT processing (an OPT record in
  AR is parsed as a generic record like any other).
- Name compression on output: builders always write full names, so every
  builder output is self-contained; compression is supported on decode only.
- RDATA types beyond A, AAAA, CNAME, MX, TXT (NS, SOA, SRV, PTR, ... are
  carried as raw bytes by `dns_rr_encode` / `dns_rr_parse` /
  `dns_rr_rdata`, with no typed helper).
- Presentation-format parsing/rendering of addresses beyond the A and AAAA
  string renderers, and IPv6 "::" compression in `dns_rdata_aaaa_to_str`.
- Character-string escaping: names are split on '.' bytes with no escape
  syntax (a label cannot contain a literal '.'), and TXT supports exactly
  one character-string per RDATA.
- Multi-question queries (`dns_query_build` always writes QDCOUNT = 1).

## Byte-level layout

All multi-byte fields are unsigned **big-endian**.

### Header (12 bytes)

| Offset | Width | Field |
|---|---|---|
| 0 | 2 | ID |
| 2 | 2 | flags word |
| 4 | 2 | QDCOUNT |
| 6 | 2 | ANCOUNT |
| 8 | 2 | NSCOUNT |
| 10 | 2 | ARCOUNT |

Flags word (RFC 1035 4.1.1), bit 15 is the most significant:

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+-----+--+--+--+--+--+-----+--------------+
|QR|Opcode|AA|TC|RD|RA|  Z  |    RCODE     |
+--+-----+--+--+--+--+--+-----+--------------+
```

Field widths and masks:

| Field | Bits | Encoded value |
|---|---|---|
| `qr` | 1 | `qr * 32768` |
| `opcode` | 4 | `opcode * 2048` |
| `aa` | 1 | `aa * 1024` |
| `tc` | 1 | `tc * 512` |
| `rd` | 1 | `rd * 256` |
| `ra` | 1 | `ra * 128` |
| `z` | 3 | `z * 16` |
| `rcode` | 4 | `rcode` |

**Masking rule.** Out-of-range values are reduced modulo 2^width (the low
bits are kept; a negative value wraps like two's complement). It applies to
the flag bits above, to `id`/counts/QTYPE/QCLASS/TYPE/CLASS/MX preference
(16 bits) and to TTL (32 bits). Encoding therefore cannot fail on field
range. E.g. `id = 65543` encodes as `0x0007`, `qr = 3` encodes as bit 15.

### Domain names

A name is a sequence of labels: one length byte (1..63) followed by that
many label bytes, terminated by a length byte of 0. The encoded name length
including the length bytes and the terminating zero must be <= 255.

Compression pointers are two bytes whose top bits are `11`; the remaining
14 bits are an offset into the message. The decoder follows them from any
name position, including pointer-to-pointer chains.

### Question entry

`QNAME` (name) then QTYPE[2], QCLASS[2].

### Resource record

`NAME` (name), TYPE[2], CLASS[2], TTL[4], RDLENGTH[2], RDATA[RDLENGTH].

### RDATA

| TYPE | Code | RDATA |
|---|---|---|
| A | 1 | 4 address octets |
| CNAME | 5 | an uncompressed-on-build domain name |
| MX | 15 | preference[2], then the exchange name |
| TXT | 16 | one character-string: length[1] + that many bytes |
| AAAA | 28 | 16 address octets |

Examples (hex):

- Header `id=0x1234`, QR=1, RD=1, QDCOUNT=1:
  `12 34 81 00 00 01 00 00 00 00 00 00`.
- `www.example.com` (uncompressed):
  `03 77 77 77 07 65 78 61 6d 70 6c 65 03 63 6f 6d 00`.
- Query for `www.example.com` A IN (`dns_query_build(0x1234, ...)`):
  `12 34 01 00 00 01 00 00 00 00 00 00` +
  `03 77 77 77 07 65 78 61 6d 70 6c 65 03 63 6f 6d 00 00 01 00 01`
  (33 bytes).
- A record for `example.com`, TTL 300, `192.0.2.1`:
  `07 65 78 61 6d 70 6c 65 03 63 6f 6d 00 00 01 00 01 00 00 01 2c
  00 04 c0 00 02 01`.

## API signatures

All functions are free functions in module `xiom.dns` (no self methods):

```xi
pub const DNS_TYPE_A: Int = 1
pub const DNS_TYPE_CNAME: Int = 5
pub const DNS_TYPE_MX: Int = 15
pub const DNS_TYPE_TXT: Int = 16
pub const DNS_TYPE_AAAA: Int = 28
pub const DNS_CLASS_IN: Int = 1

pub type DnsHeader = {
  id: Int; qr: Int; opcode: Int; aa: Int; tc: Int; rd: Int; ra: Int;
  z: Int; rcode: Int; qdcount: Int; ancount: Int; nscount: Int; arcount: Int;
}
pub type DnsName = { labels: Vec[Str]; next: Int; compressed: Bool; }
pub type DnsQuestion = { name: DnsName; qtype: Int; qclass: Int; next: Int; }
pub type DnsRecord = {
  name: DnsName; rtype: Int; rclass: Int; ttl: Int;
  rdata_offset: Int; rdata_length: Int; next: Int;
}
pub type DnsMessage = {
  header: DnsHeader; question_offsets: Vec[Int]; record_offsets: Vec[Int];
}

pub fn dns_header_encode(h: &DnsHeader) -> Vec[UInt8]
pub fn dns_header_decode(data: &Vec[UInt8]) -> Result[DnsHeader, Str]

pub fn dns_name_encode(name: Str) -> Result[Vec[UInt8], Str]
pub fn dns_name_decode(data: &Vec[UInt8], off: Int) -> Result[DnsName, Str]
pub fn dns_name_to_str(n: &DnsName) -> Str

pub fn dns_question_encode(name: Str, qtype: Int, qclass: Int) -> Result[Vec[UInt8], Str]
pub fn dns_question_parse(data: &Vec[UInt8], off: Int) -> Result[DnsQuestion, Str]

pub fn dns_rr_encode(name: Str, rtype: Int, rclass: Int, ttl: Int, rdata: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dns_rr_parse(data: &Vec[UInt8], off: Int) -> Result[DnsRecord, Str]
pub fn dns_rr_rdata(data: &Vec[UInt8], r: &DnsRecord) -> Result[Vec[UInt8], Str]

pub fn dns_rdata_a(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dns_rdata_aaaa(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dns_rdata_cname(name: Str) -> Result[Vec[UInt8], Str]
pub fn dns_rdata_mx(preference: Int, exchange: Str) -> Result[Vec[UInt8], Str]
pub fn dns_rdata_txt(text: Str) -> Result[Vec[UInt8], Str]

pub fn dns_rdata_a_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str]
pub fn dns_rdata_aaaa_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str]
pub fn dns_rdata_name(data: &Vec[UInt8], off: Int, len: Int) -> Result[DnsName, Str]
pub fn dns_rdata_mx_preference(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str]
pub fn dns_rdata_mx_exchange(data: &Vec[UInt8], off: Int, len: Int) -> Result[DnsName, Str]
pub fn dns_rdata_txt_parse(rdata: &Vec[UInt8]) -> Result[Str, Str]

pub fn dns_query_build(id: Int, name: Str, qtype: Int) -> Result[Vec[UInt8], Str]
pub fn dns_message_parse(data: &Vec[UInt8]) -> Result[DnsMessage, Str]
pub fn dns_message_question_count(m: &DnsMessage) -> Int
pub fn dns_message_record_count(m: &DnsMessage) -> Int
pub fn dns_message_question_offset(m: &DnsMessage, i: Int) -> Int
pub fn dns_message_record_offset(m: &DnsMessage, i: Int) -> Int
```

## Semantics

`dns_header_encode(h)`
: Exactly 12 bytes; each field masked to its width (table above). Never
  fails.

`dns_header_decode(data)`
: Reads ID, the flags word split into the eight fields, and the four
  counts. Every bit pattern is valid. Bytes after offset 12 are ignored.
  `Err("dns: truncated header")` when `data.len() < 12`.

`dns_name_encode(name)`
: Splits on '.' bytes. A single trailing dot is accepted and ignored, so
  `"example.com"` and `"example.com."` encode alike; `""` and `"."` both
  encode the root as the single byte `0x00`. Label bytes are copied
  verbatim. Validation order per label: empty label, length > 63, running
  wire length > 254 (i.e. the complete name would exceed 255), embedded
  `0x00`.

`dns_name_decode(data, off)`
: Returns the labels, the offset just past the name (`next`) and whether a
  pointer was followed (`compressed`). A pointer is only followed when its
  target is inside `data`; the name's end (`next`) is the offset after the
  terminating zero or after the pointer two bytes at the position where the
  name started, so `next` is independent of how many pointers were
  followed. Pointer jumps are capped at `data.len()`; exceeding that cap
  means a loop and is an error. A wire label containing `0x00` is rejected
  because the runtime `Str` is a NUL-terminated C string and cannot carry
  an embedded NUL.

`dns_name_to_str(n)`
: Labels joined with '.', no trailing dot; root renders `""`. This is a
  rendering, not a lossless inverse of `dns_name_encode` when a label
  contains '.' (impossible from decoding, since '.' is not special on the
  wire) or a NUL (rejected on decode).

`dns_question_encode(name, qtype, qclass)`
: Uncompressed name, QTYPE and QCLASS (masked to 16 bits).

`dns_question_parse(data, off)`
: Name errors propagate; after the name, four bytes must remain, otherwise
  `dns: truncated question`. `next` is the offset just past QCLASS.

`dns_rr_encode(name, rtype, rclass, ttl, rdata)`
: Uncompressed name, TYPE, CLASS, TTL (32 bits), RDLENGTH = `rdata.len()`
  and the RDATA bytes verbatim. `Err("dns: rdata too long")` when the RDATA
  exceeds 65535 bytes. Zero-length RDATA is legal (RDLENGTH = 0).

`dns_rr_parse(data, off)`
: Name errors propagate; after the name the fixed 10 bytes (TYPE, CLASS,
  TTL, RDLENGTH) must fit, otherwise `dns: truncated record`; the declared
  RDLENGTH must fit, otherwise `dns: truncated rdata`. `rdata_offset` and
  `rdata_length` locate the RDATA; `next` is just past it. A record with
  RDLENGTH = 0 has `next == rdata_offset`.

`dns_rr_rdata(data, r)`
: Copies the recorded span out of `data`. `Err("dns: rdata out of range")`
  when the span is negative or does not fit `data` (e.g. a shortened
  buffer); a zero-length span yields an empty `Ok`.

`dns_rdata_a(octets)` / `dns_rdata_aaaa(octets)`
: Copy exactly 4 / 16 octets; any other length is `dns: bad A rdata` /
  `dns: bad AAAA rdata`.

`dns_rdata_cname(name)` / `dns_rdata_mx(preference, exchange)`
: Name encoded uncompressed; name errors propagate. MX prefixes the
  16-bit masked preference.

`dns_rdata_txt(text)`
: One character-string: `text.len()` as one byte, then the text bytes.
  `Err("dns: txt too long")` when `text.len() > 255`. No NUL/UTF-8
  validation (a character-string is binary; the runtime `Str` cannot carry
  an embedded NUL anyway).

`dns_rdata_a_to_str(rdata)` / `dns_rdata_aaaa_to_str(rdata)`
: Dotted-quad for 4 bytes; full-form lowercase IPv6 (8 groups, no `::`) for
  16 bytes. Other lengths are the bad-rdata errors above.

`dns_rdata_name(data, off, len)`
: Decodes the name stored in RDATA `[off, off+len)` with compression
  support; the name's `next` must be <= `off + len`, else
  `dns: bad rdata name` (also when `len < 1`). Name errors propagate.

`dns_rdata_mx_preference(data, off, len)`
: 16-bit preference; `len < 3` or a field outside `data` is
  `dns: bad MX rdata`.

`dns_rdata_mx_exchange(data, off, len)`
: `dns_rdata_name` on `[off+2, off+len)`; `len < 3` is
  `dns: bad MX rdata`.

`dns_rdata_txt_parse(rdata)`
: Requires exactly one complete character-string
  (`rdata.len() >= 1` and `rdata[0] + 1 == rdata.len()`); anything else is
  `dns: bad TXT rdata`. The text bytes are copied verbatim (including
  `0x00`, which terminates the resulting `Str` at the runtime boundary --
  see limitations).

`dns_query_build(id, name, qtype)`
: 12-byte header (ID masked, QR=0, Opcode=0, AA=TC=RA=Z=RCODE=0, RD=1,
  QDCOUNT=1, AN=NS=AR=0) then one question with QCLASS = `DNS_CLASS_IN`.
  Name errors propagate; the result is a complete, self-contained query.

`dns_message_parse(data)`
: Decodes the header, then walks QDCOUNT questions and
  `ANCOUNT + NSCOUNT + ARCOUNT` resource records in order, recording the
  name offset of each in `question_offsets` / `record_offsets`. Entries are
  read back with `dns_question_parse` / `dns_rr_parse` at those offsets.
  A declared entry with no bytes left is `dns: truncated question` /
  `dns: truncated record`; other name/record errors propagate unchanged.
  Bytes after the last declared entry are ignored. Section membership:
  records `0..ancount-1` are answers, `ancount..ancount+nscount-1` are
  authority records, the rest additional records.

`dns_message_*_count` / `dns_message_*_offset`
: Index accessors; offsets return -1 out of range (negative or past the
  last indexed entry), no error channel.

## Error string catalog

All error strings are stable API and start with `dns: `.

| Error text | Emitted by | Condition |
|---|---|---|
| `dns: truncated header` | `dns_header_decode`, `dns_message_parse` | fewer than 12 bytes |
| `dns: negative offset` | `dns_name_decode` (and callers) | `off < 0` |
| `dns: truncated name` | `dns_name_decode` | buffer ends inside a name, or a pointer's second byte is missing |
| `dns: truncated label` | `dns_name_decode` | a label's declared bytes run past the buffer end |
| `dns: unsupported label type` | `dns_name_decode` | length byte with bits 7..6 = 01 or 10 |
| `dns: pointer out of range` | `dns_name_decode` | pointer target >= `data.len()` |
| `dns: compression loop` | `dns_name_decode` | more pointer jumps than `data.len()` |
| `dns: name too long` | `dns_name_encode`, `dns_name_decode` | expanded/encoded name would exceed 255 bytes |
| `dns: empty label` | `dns_name_encode` | an empty label (leading dot, `..`, dot-only name other than `.`) |
| `dns: label too long` | `dns_name_encode` | a label longer than 63 bytes |
| `dns: label contains NUL byte` | `dns_name_encode`, `dns_name_decode` | label byte `0x00` (defensive on encode; the runtime `Str` cannot carry it) |
| `dns: truncated question` | `dns_question_parse`, `dns_message_parse` | fewer than 4 bytes after QNAME, or a declared question with no bytes left |
| `dns: truncated record` | `dns_rr_parse`, `dns_message_parse` | fewer than 10 bytes after NAME, or a declared record with no bytes left |
| `dns: truncated rdata` | `dns_rr_parse`, `dns_message_parse` | RDLENGTH runs past the buffer end |
| `dns: rdata out of range` | `dns_rr_rdata` | recorded span negative or beyond the passed buffer |
| `dns: rdata too long` | `dns_rr_encode` | `rdata.len() > 65535` |
| `dns: bad A rdata` | `dns_rdata_a`, `dns_rdata_a_to_str` | length is not 4 |
| `dns: bad AAAA rdata` | `dns_rdata_aaaa`, `dns_rdata_aaaa_to_str` | length is not 16 |
| `dns: bad rdata name` | `dns_rdata_name` | `len < 1` or the name ends past `off + len` |
| `dns: bad MX rdata` | `dns_rdata_mx_preference`, `dns_rdata_mx_exchange` | `len < 3` (or preference field outside the buffer) |
| `dns: bad TXT rdata` | `dns_rdata_txt_parse` | RDATA is empty or not exactly one complete character-string |
| `dns: txt too long` | `dns_rdata_txt` | `text.len() > 255` |

Check order: header length, then offset sign, then name structure, then the
section-specific length fields, then RDATA contents. Name errors are
propagated unchanged through `dns_question_*`, `dns_rr_*` and
`dns_message_parse` (so `dns: pointer out of range` from a question is
reported as-is).

## Complexity

| Operation | Complexity |
|---|---|
| `dns_header_encode` / `dns_header_decode` | O(1) |
| `dns_name_encode` / `dns_name_decode` / `dns_name_to_str` | O(name bytes), decode worst case O(name bytes x pointer jumps) |
| `dns_question_encode` / `dns_question_parse` | O(name bytes) |
| `dns_rr_encode` / `dns_rr_parse` | O(name bytes + RDATA length) |
| `dns_rr_rdata` | O(RDATA length) |
| `dns_rdata_*` builders/parsers | O(input length) |
| `dns_query_build` | O(name bytes) |
| `dns_message_parse` | O(message bytes) |
| accessors | O(1) |

No allocation happens on an error path; every successful parse copies its
bytes into fresh values.

## Test plan

`tests/test_conformance.xi` (`module dns_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. header encode pins ID, flags and QDCOUNT big-endian (`12 34 81 00 ...`);
2. header decode of all-ones bits (QR/Opcode/AA/TC/RD/RA/Z/RCODE and all
   four counts = 65535) and of the all-zero header;
3. header field masking on encode (`id` 65543 -> 7, `qr` 3 -> 1, `opcode`
   20 -> 4, `aa` 2 -> 0, `z` 9 -> 1, `rcode` 16 -> 0, `qdcount` 65537 -> 1)
   and read-back of the masked values;
4. header decode needs 12 bytes: empty and 11-byte inputs are
   `dns: truncated header`; 12-byte and 14-byte inputs are `Ok`;
5. name encode pinned: `www.example.com`, trailing-dot form,
   `_sip._tcp.example.com`, single label, `""` and `"."` (root);
6. name encode boundaries: a 63-byte label passes, 64 fails
   `dns: label too long`; a 255-byte name round-trips, 256 fails
   `dns: name too long`; `a..b`, `.a` and `a.b..` fail
   `dns: empty label`;
7. name decode: labels and `next`, `compressed` false, non-zero start
   offset, `dns_name_to_str` rendering;
8. compression pointer and pointer-to-pointer chains: `next` past the
   first pointer, labels expanded, `compressed` true;
9. name decode errors: empty buffer, `05` (truncated label), `03 61 62`
   (truncated label), `03 61 62 63` (truncated name), `40`/`80`
   (unsupported label type), `c0` (truncated name), `c0 09` (pointer out of
   range), `c0 02 c0 00` (compression loop), off past the end, NUL label;
10. question encode: exact 17 bytes for `example.com` A IN and QTYPE/QCLASS
    masking (65537 -> 1, 65536 -> 0);
11. question parse: fields, `next`, non-zero offset, 16-byte truncation,
    name-only buffer, negative offset;
12. A record encode: exact NAME/TYPE/CLASS/TTL(300)/RDLENGTH/RDATA bytes;
13. A record parse: pinned `rdata_offset`/`rdata_length`/`next`, TTL, RDATA
    copy, `dns_rdata_a_to_str` -> `192.0.2.1`;
14. record errors: empty buffer, name-only, RDLENGTH overrun, negative
    offset, and `dns_rr_rdata` on a shortened buffer;
15. A/AAAA: 4/16-octet builders, bad lengths, `10.0.0.255` and
    `2001:db8:0:0:0:0:0:1` renderers;
16. CNAME: uncompressed encode, `dns_rdata_name` on uncompressed and
    compressed targets, `len` smaller than the name and `len = 0` errors,
    propagated pointer error;
17. MX: preference + exchange encode (pinned bytes), preference and
    exchange parse, `len < 3` errors, preference masking;
18. TXT: `hello`, empty string, 255-byte boundary (256-byte RDATA), 256
    rejected, multi-string/truncated/empty RDATA rejected;
19. query build: exact 33 bytes, header fields, index counts/offsets,
    question read-back with `next = 33`, question re-encode;
20. message parse of a 45-byte response: header flags/counts, question and
    record offsets, a compressed owner name (`C0 0C`), TTL 60, RDATA slice;
21. message parse errors: declared question with no bytes, declared record
    with no bytes, RDATA overrun, short header; trailing bytes ignored;
22. zero-length RDATA: encodes, parses with `rdata_offset == next`, copies
    as an empty vector;
23. non-ASCII label bytes (`café`) preserved byte-for-byte through encode
    and decode;
24. AAAA query (`qtype` 28): exact wire value, question read-back, index
    accessors out of range return -1.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.dns
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **Codec only.** No sockets, no retries, no timeouts, no cache, no
  server/client roles; `xiom.net.dns` (record-string utilities) and the
  socket layer are separate concerns.
- **No compression on output.** Builder results are larger than an optimal
  encoder's; `dns_message_parse` -> rebuild produces uncompressed bytes,
  which decode identically but are not byte-identical to a compressed
  original.
- **`Str` is a NUL-terminated C string.** A decoded label containing a
  `0x00` byte cannot be represented and is rejected with
  `dns: label contains NUL byte`; the same check is defensive on encode.
  Likewise a TXT text byte `0x00` truncates the parsed `Str` at the runtime
  boundary even though the wire parse consumed the full character-string.
- **One character-string per TXT.** RDATA with zero or several
  character-strings is rejected by `dns_rdata_txt_parse` (the generic
  record parser still carries it as raw bytes).
- **Presentation parsing is minimal.** No escape syntax for names (a
  literal '.' cannot appear inside a label), no charset validation, no
  IDNA/punycode conversion, and IPv6 is rendered full-form (no `::`).
- **The Z bits are not interpreted** (AD/CD are not exposed); no DNSSEC or
  EDNS(0) OPT handling. An OPT record is indexed like any other record.
- **`dns_message_parse` ignores bytes after the last declared entry**
  (useful for framed transports, but a strict length check is the caller's
  job).
- **TTL is a plain `Int`** (0..4294967295); there is no time arithmetic.
- Not thread-safe; all values are plain value types and `Vec` fields.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_header`, `_err_header`, `_ok_name`, `_err_name`, `_ok_question`,
  `_err_question`, `_ok_record`, `_err_record`, `_ok_message`,
  `_err_message`, `_ok_bytes`, `_err_bytes`, `_ok_str`, `_err_str`,
  `_ok_int`, `_err_int`); constructing `Result` values directly inside
  other functions miscompiles in this compiler.
- All big-endian packing/unpacking is arithmetic (division/modulo); no
  `& 0xFF` is applied to a value that may have bit 31 set, and every
  `Vec[UInt8]` byte read is widened with `(data[pos] as Int) & 0xFF` before
  it enters `Int` arithmetic.
- `Str` label values read out of `Vec[Str]` are bound to typed locals
  (`let lbl: Str = n.labels[i];`) before use and compared only through
  `xiom.string.compare.str_compare` (BUG 17: `==` on such elements lowers
  to a pointer comparison).
- Names are materialized with `xiom.string.builder.sb_to_str` (the proven
  one-allocation pattern); the whole-message index is flat (parallel
  `Vec[Int]` fields) because `Vec[StructType]` is unsupported.
- No function builds a `Vec` inside a match arm over a tuple-Result (the
  `p_result_tuple_vec_loop` shape); matches appear only in the tests'
  small extractor helpers.
- The tests call every check directly from `main` (no `Vec[fn]` dispatch,
  which miscompiles) and use typed locals for all Vec reads.
- The package declares no `extern "C"` blocks (no FFI).
