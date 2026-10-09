# xiom.bonjour -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `src/bonjour.xi` (`module xiom.bonjour`).
Depends on `xiom.std`; the library module imports only `xiom.string`,
`xiom.string.builder` and `xiom.string.compare` (the tests add `xiom.test`,
`xiom.io`, `xiom.string`, `xiom.string.builder`, `xiom.string.compare` and
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI, no sockets) codec for Bonjour traffic -- mDNS
(RFC 6762) message framing and DNS-SD (RFC 6763) record conventions -- for
the subset listed here:

- `bonjour_header_encode` / `bonjour_header_decode`: the 12-byte header,
  including the packed flags word (QR, Opcode, AA, TC, RD, RA, Z, RCODE)
  and the four section counts;
- `bonjour_name_encode` / `bonjour_name_encode_compressed` /
  `bonjour_name_decode` / `bonjour_name_to_str`: domain names as
  length-prefixed labels; decoding always follows compression pointers
  (with loop, out-of-range and truncation detection); encoding optionally
  emits pointers against a caller-supplied prior-name table;
- `bonjour_question_encode` / `bonjour_question_parse`: the question
  section (QNAME, QTYPE, QCLASS);
- `bonjour_rr_encode` / `bonjour_rr_parse` / `bonjour_rr_rdata`: generic
  resource records (NAME, TYPE, CLASS, TTL, RDLENGTH, RDATA span);
- RDATA helpers for PTR, SRV, TXT, A and AAAA (builders and parsers);
- the class top bit: cache-flush on response records, unicast-response
  (QU) on questions;
- DNS-SD names: `_services._dns-sd._udp.local`, service type names,
  service instance names, subtype names, TXT key=value lists, `local`
  domain checks, and the recommended TTLs (120 host / 4500 service);
- message builders: advertise (PTR + SRV + TXT response), browse (PTR
  query), instance (SRV query), enumeration (PTR query) and the generic
  one-question query;
- `bonjour_message_parse` plus count/offset accessors: whole-message
  parsing that indexes the questions and resource records by offset.

Errors are deterministic `Err(Str)` strings; the full catalog is below.

## Non-goals

- Socket I/O, multicast group membership, transport (UDP/TCP), query
  scheduling, duplicate suppression, caching, server/responder loops or
  conflict resolution.
- Message IDs across requests: mDNS messages use ID 0 (the builders write
  zero) and there is no transaction matching.
- Name compression in the record builders: `bonjour_advertise` and the
  per-record builders write full names; only
  `bonjour_name_encode_compressed` emits pointers, and only when the
  caller supplies the table of prior names with their absolute offsets.
- RDATA types beyond PTR, SRV, TXT, A and AAAA (NSEC, OPT, TSIG,
  DNSSEC, ... are carried as raw bytes by the generic record helpers).
- Character-set handling: labels and TXT strings are restricted to
  printable ASCII (`0x20..0x7E`) because the runtime `Str` is a
  NUL-terminated C string; no punycode, IDNA, escape syntax or UTF-8.
- TXT key=value semantics beyond splitting on the first '=' (no
  validation of key names beyond printability and the `'='` rule).
- IPv6 `::` compression in `bonjour_rdata_aaaa_to_str` (full-form, 8
  groups).
- Known-answer suppression, probing, rate limiting, goodbye scheduling
  (a goodbye record is available as a value, not as a state machine).
- Multi-question queries (the query builders always write QDCOUNT = 1).

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

Flags word (RFC 1035 4.1.1, shared with mDNS), bit 15 is the most
significant:

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+-----+--+--+--+--+--+-----+--------------+
|QR|Opcode|AA|TC|RD|RA|  Z  |    RCODE     |
+--+-----+--+--+--+--+--+-----+--------------+
```

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
bits are kept; a negative value wraps like two's complement). It applies
to the flag bits above, to `id`/counts/QTYPE/QCLASS/TYPE/CLASS (16 bits),
to TTL (32 bits) and to the SRV priority/weight/port fields (16 bits).
Encoding therefore cannot fail on field range. E.g. `id = 65543` encodes
as `0x0007`, `qr = 3` encodes as bit 15.

### Domain names

A name is a sequence of labels: one length byte (1..63) followed by that
many label bytes, terminated by a length byte of 0. The encoded name
length including the length bytes and the terminating zero must be
<= 255.

Compression pointers are two bytes whose top bits are `11`; the remaining
14 bits are an offset into the message. The decoder follows them from any
name position, including pointer-to-pointer chains. `bonjour_name_decode`
returns `next` (the offset just past the name: after the terminating zero,
or after the two pointer bytes where the name started) independently of
how many pointers were followed, and `compressed` (true when at least one
pointer was followed).

Label bytes must be printable ASCII (`0x20..0x7E`); `0x00` and bytes
outside that range are rejected in both directions (`bonjour: label
contains NUL byte` / `bonjour: label not printable`).

### Question entry

`QNAME` (name) then QTYPE[2], QCLASS[2]. QCLASS carries the QU bit for
unicast-response queries (RFC 6762 section 5.4).

### Resource record

`NAME` (name), TYPE[2], CLASS[2], TTL[4], RDLENGTH[2], RDATA[RDLENGTH].
CLASS carries the cache-flush bit on unique records (RFC 6762 section
10.2).

### Class top bit

| Bit | In a question | In a response record |
|---|---|---|
| 15 | unicast-response (QU) | cache-flush |

`bonjour_class_value(top)` writes IN (1) with the bit set when `top`;
`bonjour_class_flush` / `bonjour_class_unicast` read it (same bit, named
for the two contexts); `bonjour_class_base` clears it.

### RDATA

| TYPE | Code | RDATA |
|---|---|---|
| A | 1 | 4 address octets |
| PTR | 12 | a domain name (the target), uncompressed on build |
| TXT | 16 | one or more character-strings: length[1] + bytes |
| AAAA | 28 | 16 address octets |
| SRV | 33 | priority[2], weight[2], port[2], then the target host name |

A PTR RDATA holds one name; an SRV RDATA is 6 fixed bytes plus a name
(minimum 7 bytes including the root name). A TXT RDATA is a concatenation
of length-prefixed strings; a zero length byte is the empty string (the
DNS-SD "no attributes" form). Empty TXT RDATA parses as an empty list.

### DNS-SD conventions

- Service enumeration name: `_services._dns-sd._udp.local`
  (`BONJOUR_ENUM_PREFIX + BONJOUR_DOMAIN`).
- Service type: `_<service>.<proto>.<domain>`, e.g. `_http._tcp.local`.
  `service` is one label (leading '_' optional), `proto` is `tcp`/`udp`
  (leading '_' optional, case-insensitive, normalized to `_tcp`/`_udp`),
  `domain` must be a local name.
- Service instance: `"<instance>.<service_type>"`. The instance is one
  label (no '.'), e.g. `Office._http._tcp.local`.
- Subtype: `"_<subtype>._sub.<service_type>"`, e.g.
  `_printer._sub._http._tcp.local`.
- Local domain: exactly `local` or any name ending in `.local`
  (case-insensitive, no trailing dot).
- Recommended TTLs: `BONJOUR_TTL_HOST` = 120 for host records,
  `BONJOUR_TTL_SERVICE` = 4500 for PTR/SRV/TXT.

Examples (hex):

- PTR record `_http._tcp.local` -> `Office._http._tcp.local`, TTL 4500,
  IN (49 bytes):
  `05 5f 68 74 74 70 04 5f 74 63 70 05 6c 6f 63 61 6c 00`
  `00 0c 00 01 00 00 11 94 00 19`
  `06 4f 66 66 69 63 65 05 5f 68 74 74 70 04 5f 74 63 70 05 6c 6f 63 61 6c 00`.
- Enumeration query for the `local` domain (46 bytes):
  header `00 00 00 00 00 01 00 00 00 00 00 00` +
  QNAME `09 5f 73 65 72 76 69 63 65 73 07 5f 64 6e 73 2d 73 64`
  `04 5f 75 64 70 05 6c 6f 63 61 6c 00` +
  QTYPE/QCLASS `00 0c 00 01`.
- SRV RDATA priority 0, weight 0, port 8080, target `myhost.local`:
  `00 00 00 00 1f 90 06 6d 79 68 6f 73 74 05 6c 6f 63 61 6c 00`.
- TXT RDATA `["txtvers=1", "path=/"]`:
  `09 74 78 74 76 65 72 73 3d 31 06 70 61 74 68 3d 2f`.

## API signatures

All functions are free functions in module `xiom.bonjour` (no self
methods):

```xi
pub const BONJOUR_PORT: Int = 5353
pub const BONJOUR_MDNS_IPV4: Str = "224.0.0.251"
pub const BONJOUR_MDNS_IPV6: Str = "ff02::fb"
pub const BONJOUR_TYPE_A: Int = 1
pub const BONJOUR_TYPE_PTR: Int = 12
pub const BONJOUR_TYPE_TXT: Int = 16
pub const BONJOUR_TYPE_AAAA: Int = 28
pub const BONJOUR_TYPE_SRV: Int = 33
pub const BONJOUR_TYPE_ANY: Int = 255
pub const BONJOUR_CLASS_IN: Int = 1
pub const BONJOUR_CLASS_TOP_BIT: Int = 32768
pub const BONJOUR_TTL_HOST: Int = 120
pub const BONJOUR_TTL_SERVICE: Int = 4500
pub const BONJOUR_DOMAIN: Str = "local"
pub const BONJOUR_ENUM_PREFIX: Str = "_services._dns-sd._udp."

pub type BonjourHeader = {
  id: Int; qr: Int; opcode: Int; aa: Int; tc: Int; rd: Int; ra: Int;
  z: Int; rcode: Int; qdcount: Int; ancount: Int; nscount: Int; arcount: Int;
}
pub type BonjourName = { labels: Vec[Str]; next: Int; compressed: Bool; }
pub type BonjourQuestion = { name: BonjourName; qtype: Int; qclass: Int; next: Int; }
pub type BonjourRecord = {
  name: BonjourName; rtype: Int; rclass: Int; ttl: Int;
  rdata_offset: Int; rdata_length: Int; next: Int;
}
pub type BonjourMessage = {
  header: BonjourHeader; question_offsets: Vec[Int]; record_offsets: Vec[Int];
}

pub fn bonjour_header_encode(h: &BonjourHeader) -> Vec[UInt8]
pub fn bonjour_header_decode(data: &Vec[UInt8]) -> Result[BonjourHeader, Str]

pub fn bonjour_name_encode(name: Str) -> Result[Vec[UInt8], Str]
pub fn bonjour_name_encode_compressed(name: Str, prior_names: &Vec[Str], prior_offsets: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn bonjour_name_decode(data: &Vec[UInt8], off: Int) -> Result[BonjourName, Str]
pub fn bonjour_name_to_str(n: &BonjourName) -> Str

pub fn bonjour_class_value(top: Bool) -> Int
pub fn bonjour_class_flush(rclass: Int) -> Bool
pub fn bonjour_class_unicast(qclass: Int) -> Bool
pub fn bonjour_class_base(rclass: Int) -> Int

pub fn bonjour_question_encode(name: Str, qtype: Int, qclass: Int) -> Result[Vec[UInt8], Str]
pub fn bonjour_question_parse(data: &Vec[UInt8], off: Int) -> Result[BonjourQuestion, Str]

pub fn bonjour_rr_encode(name: Str, rtype: Int, rclass: Int, ttl: Int, rdata: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn bonjour_rr_parse(data: &Vec[UInt8], off: Int) -> Result[BonjourRecord, Str]
pub fn bonjour_rr_rdata(data: &Vec[UInt8], r: &BonjourRecord) -> Result[Vec[UInt8], Str]

pub fn bonjour_rdata_ptr(target: Str) -> Result[Vec[UInt8], Str]
pub fn bonjour_rdata_srv(priority: Int, weight: Int, port: Int, target: Str) -> Result[Vec[UInt8], Str]
pub fn bonjour_rdata_txt(pairs: &Vec[Str]) -> Result[Vec[UInt8], Str]
pub fn bonjour_rdata_a(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn bonjour_rdata_aaaa(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]

pub fn bonjour_rdata_a_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str]
pub fn bonjour_rdata_aaaa_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str]
pub fn bonjour_rdata_name(data: &Vec[UInt8], off: Int, len: Int) -> Result[BonjourName, Str]
pub fn bonjour_rdata_ptr_target(data: &Vec[UInt8], off: Int, len: Int) -> Result[Str, Str]
pub fn bonjour_rdata_srv_priority(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str]
pub fn bonjour_rdata_srv_weight(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str]
pub fn bonjour_rdata_srv_port(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str]
pub fn bonjour_rdata_srv_target(data: &Vec[UInt8], off: Int, len: Int) -> Result[BonjourName, Str]
pub fn bonjour_rdata_txt_parse(rdata: &Vec[UInt8]) -> Result[Vec[Str], Str]

pub fn bonjour_txt_pair(key: Str, value: Str) -> Result[Str, Str]
pub fn bonjour_txt_get(pairs: &Vec[Str], key: Str) -> Result[Str, Str]

pub fn bonjour_service_enum_name() -> Str
pub fn bonjour_is_local_name(name: Str) -> Bool
pub fn bonjour_check_local_name(name: Str) -> Result[Str, Str]
pub fn bonjour_service_type(service: Str, proto: Str, domain: Str) -> Result[Str, Str]
pub fn bonjour_service_type_name(service: Str, proto: Str) -> Result[Str, Str]
pub fn bonjour_instance_name(instance: Str, service_type: Str) -> Result[Str, Str]
pub fn bonjour_subtype_name(subtype: Str, service_type: Str) -> Result[Str, Str]
pub fn bonjour_enum_rdata(service_type: Str) -> Result[Vec[UInt8], Str]

pub fn bonjour_query_name(name: Str, qtype: Int, unicast: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_service_query(service_type: Str, unicast: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_instance_query(instance_name: Str, unicast: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_enum_query(domain: Str) -> Result[Vec[UInt8], Str]

pub fn bonjour_ptr_record(owner: Str, target: Str, ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_srv_record(instance: Str, priority: Int, weight: Int, port: Int, host: Str, ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_txt_record(instance: Str, pairs: &Vec[Str], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_a_record(owner: Str, octets: &Vec[UInt8], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_aaaa_record(owner: Str, octets: &Vec[UInt8], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str]
pub fn bonjour_goodbye_ptr(owner: Str, target: Str) -> Result[Vec[UInt8], Str]
pub fn bonjour_advertise(instance: Str, service_type: Str, port: Int, host: Str, pairs: &Vec[Str]) -> Result[Vec[UInt8], Str]

pub fn bonjour_message_parse(data: &Vec[UInt8]) -> Result[BonjourMessage, Str]
pub fn bonjour_message_question_count(m: &BonjourMessage) -> Int
pub fn bonjour_message_record_count(m: &BonjourMessage) -> Int
pub fn bonjour_message_question_offset(m: &BonjourMessage, i: Int) -> Int
pub fn bonjour_message_record_offset(m: &BonjourMessage, i: Int) -> Int
```

## Semantics

`bonjour_header_encode(h)`
: Exactly 12 bytes; each field masked to its width (table above). Never
  fails.

`bonjour_header_decode(data)`
: Reads ID, the flags word split into the eight fields, and the four
  counts. Every bit pattern is valid. Bytes after offset 12 are ignored.
  `Err("bonjour: truncated header")` when `data.len() < 12`.

`bonjour_name_encode(name)`
: Splits on '.' bytes. A single trailing dot is accepted and ignored, so
  `"a.local"` and `"a.local."` encode alike; `""` and `"."` both encode
  the root as the single byte `0x00`. Validation order per label: empty
  label, length > 63, running wire length > 254 (i.e. the complete name
  would exceed 255), embedded `0x00`, non-printable byte.

`bonjour_name_encode_compressed(name, prior_names, prior_offsets)`
: Same validation, but before writing label `i` the suffix `labels[i..]`
  is joined with '.' and compared (case-sensitively) against
  `prior_names[j]`; on a match whose `prior_offsets[j]` is in
  `0..16383`, the remainder is written as a two-byte pointer and
  encoding stops. The lookup stops at the shorter of the two vectors.
  Without a hit the name is written in full (including the terminating
  zero). Callers keep the table in sync: `prior_names[j]` must be a name
  previously encoded at absolute message offset `prior_offsets[j]`.

`bonjour_name_decode(data, off)`
: Returns the labels, `next` and `compressed`. A pointer is only
  followed when its target is inside `data`; pointer jumps are capped at
  `data.len()` (exceeding the cap is a loop). A wire label containing
  `0x00` or a non-printable byte is rejected. Decoding a pointer that
  targets a root label yields the root name (no labels).

`bonjour_name_to_str(n)`
: Labels joined with '.', no trailing dot; root renders `""`. This is a
  rendering, not a lossy inverse issue: labels cannot contain '.' on
  decode (a wire label may, but then the rendering is ambiguous; the
  documented subset treats '.' as the separator on both sides).

`bonjour_class_*`
: `bonjour_class_value(true)` = 32769 (IN + top bit), `(false)` = 1.
  `bonjour_class_flush` / `bonjour_class_unicast` test bit 15 of the
  16-bit masked value; `bonjour_class_base` clears it. The two readers
  are aliases by design: the bit is cache-flush in responses and QU in
  questions.

`bonjour_question_encode(name, qtype, qclass)`
: Uncompressed name, QTYPE and QCLASS (masked to 16 bits).

`bonjour_question_parse(data, off)`
: Name errors propagate; after the name, four bytes must remain,
  otherwise `bonjour: truncated question`. `next` is the offset just past
  QCLASS.

`bonjour_rr_encode(name, rtype, rclass, ttl, rdata)`
: Uncompressed name, TYPE, CLASS, TTL (32 bits), RDLENGTH = `rdata.len()`
  and the RDATA bytes verbatim. `Err("bonjour: rdata too long")` when the
  RDATA exceeds 65535 bytes. Zero-length RDATA is legal (RDLENGTH = 0).

`bonjour_rr_parse(data, off)`
: Name errors propagate; after the name the fixed 10 bytes (TYPE, CLASS,
  TTL, RDLENGTH) must fit, otherwise `bonjour: truncated record`; the
  declared RDLENGTH must fit, otherwise `bonjour: truncated rdata`.
  `rdata_offset`/`rdata_length` locate the RDATA; `next` is just past it.

`bonjour_rr_rdata(data, r)`
: Copies the recorded span out of `data`.
  `Err("bonjour: rdata out of range")` when the span is negative or does
  not fit `data`; a zero-length span yields an empty `Ok`.

`bonjour_rdata_ptr(target)` / `bonjour_rdata_srv(...)` /
`bonjour_rdata_a(octets)` / `bonjour_rdata_aaaa(octets)`
: PTR = the target name uncompressed. SRV = three 16-bit masked fields
  (priority, weight, port) then the target host name. A/AAAA copy exactly
  4 / 16 octets (`bonjour: bad A rdata` / `bonjour: bad AAAA rdata`
  otherwise).

`bonjour_rdata_txt(pairs)`
: Concatenates each string as length byte + bytes.
  `Err("bonjour: TXT string too long")` above 255 bytes per string;
  `Err("bonjour: TXT byte not printable")` for bytes outside
  `0x20..0x7E`. An empty `pairs` yields an empty RDATA.

`bonjour_rdata_name(data, off, len)`
: Decodes the name stored in RDATA `[off, off+len)` with compression
  support; the name's `next` must be <= `off + len`, else
  `bonjour: bad rdata name` (also when `len < 1`).

`bonjour_rdata_ptr_target(data, off, len)`
: `len < 1` is `bonjour: bad PTR rdata`; otherwise
  `bonjour_rdata_name` followed by `bonjour_name_to_str`.

`bonjour_rdata_srv_priority/weight/port(data, off, len)`
: `len < 7` or a field outside the buffer is `bonjour: bad SRV rdata`;
  otherwise the 16-bit big-endian field at offsets 0 / 2 / 4.

`bonjour_rdata_srv_target(data, off, len)`
: `len < 7` is `bonjour: bad SRV rdata`; otherwise
  `bonjour_rdata_name` on `[off+6, off+len)`.

`bonjour_rdata_txt_parse(rdata)`
: Walks length-prefixed strings; `Err("bonjour: truncated TXT string")`
  when a declared string runs past the end;
  `Err("bonjour: TXT byte not printable")` for bytes outside
  `0x20..0x7E`. Empty RDATA yields an empty `Ok`; a zero length byte
  yields the empty string.

`bonjour_txt_pair(key, value)`
: `"key=value"`, or `"key"` when `value` is empty.
  `Err("bonjour: empty TXT key")`, `Err("bonjour: TXT key contains '='")`,
  `Err("bonjour: TXT byte not printable")` for the key/value bytes. The
  result may exceed 255 bytes; `bonjour_rdata_txt` enforces the limit.

`bonjour_txt_get(pairs, key)`
: First pair whose part before the first '=' equals `key` gives its value
  (a bare pair gives `""`); `Err("bonjour: TXT key not found")`
  otherwise.

`bonjour_is_local_name(name)` / `bonjour_check_local_name(name)`
: `local` or `*.local`, ASCII case-insensitive, no trailing dot. The
  check function returns the name unchanged or
  `Err("bonjour: not a local domain")`.

`bonjour_service_type(service, proto, domain)` /
`bonjour_service_type_name(service, proto)`
: Builds `"_<service>.<proto>.<domain>"`; the `_name` form uses `local`.
  Leading '_' on `service`/`proto` is optional; `proto` is normalized to
  `_tcp`/`_udp`; the emitted service keeps its original case.

`bonjour_instance_name(instance, service_type)` /
`bonjour_subtype_name(subtype, service_type)`
: Instance = one dot-free printable label; subtype = one dot-free
  printable label (leading '_' optional, one is always emitted). The
  service type must be a local name.

`bonjour_enum_rdata(service_type)`
: PTR RDATA whose target is `service_type` (must be local).

`bonjour_query_name(name, qtype, unicast)`
: 12-byte header (ID 0, QR 0, Opcode 0, RD = 1 when `unicast` else 0,
  QDCOUNT 1, other counts 0) then one question with QCLASS = IN + top bit
  when `unicast`.

`bonjour_service_query` / `bonjour_instance_query` / `bonjour_enum_query`
: PTR / SRV / PTR queries; the service and instance forms require local
  names; the enum form queries
  `_services._dns-sd._udp.<domain>`.

`bonjour_*_record(...)`
: One complete record: PTR/TXT/SRV/A/AAAA builders with the class from
  `flush`; `bonjour_goodbye_ptr` is a PTR with TTL 0.

`bonjour_advertise(instance, service_type, port, host, pairs)`
: A response header (QR 1, AA 1, ANCOUNT 3, other counts 0) followed by
  three answers in order: PTR `service_type -> instance` (TTL 4500, no
  flush), SRV `instance -> host:port` (TTL 4500, flush), TXT `instance ->
  pairs` (TTL 4500, flush). All three names must be local; names are
  uncompressed.

`bonjour_message_parse(data)`
: Decodes the header, then walks QDCOUNT questions and
  `ANCOUNT + NSCOUNT + ARCOUNT` resource records in order, recording the
  name offset of each in `question_offsets` / `record_offsets`. Entries
  are read back with `bonjour_question_parse` / `bonjour_rr_parse` at
  those offsets. A declared entry with no bytes left is
  `bonjour: truncated question` / `bonjour: truncated record`; other
  name/record errors propagate unchanged. Bytes after the last declared
  entry are ignored. Section membership: records
  `0..ancount-1` are answers, `ancount..ancount+nscount-1` are authority
  records, the rest additional records.

`bonjour_message_*_count` / `bonjour_message_*_offset`
: Index accessors; offsets return -1 out of range (negative or past the
  last indexed entry), no error channel.

## Contracts (batch #48 hardening pass, 2026-10-09)

`ensures:` clauses were added in this pass and are enforced at runtime on
every call in the instrumented build. No clause below has a demonstrated
Z3 proof obligation, so every clause is marked *runtime-checked*; none is
claimed Z3-proven. Guard families: guard-pair / Bool variant (`=>` guards
on parameters and `result` tags), sentinels (`-1`, `!result`), exact
formulas, bounds and lengths.

| Function | Clauses | Verification |
|---|---|---|
| `bonjour_header_encode` | `result.len() == 12` | runtime-checked |
| `bonjour_header_decode` | `data.len() < 12` => Err; `data.len() >= 12` => Ok | runtime-checked |
| `bonjour_name_encode` | empty name => Ok; Err => non-empty name | runtime-checked |
| `bonjour_name_decode` | `off < 0` / `off >= data.len()` => Err; Ok => `0 <= off < data.len()` | runtime-checked |
| `bonjour_question_encode` | empty name => Ok; Err => non-empty name | runtime-checked |
| `bonjour_class_value` | `top` => 32769; `!top` => 1 | runtime-checked |
| `bonjour_txt_pair` | empty key => Err; Ok => non-empty key | runtime-checked |
| `bonjour_rdata_a` | length `!= 4` => Err; `== 4` => Ok | runtime-checked |
| `bonjour_rdata_aaaa` | length `!= 16` => Err; `== 16` => Ok | runtime-checked |
| `bonjour_rdata_a_to_str` | length `!= 4` => Err; `== 4` => Ok | runtime-checked |
| `bonjour_rdata_srv_priority` | `len < 7` / `off < 0` / `off + 6 > data.len()` => Err; Ok => all bounds hold | runtime-checked |
| `bonjour_service_enum_name` | `result.len() == 28` | runtime-checked |
| `bonjour_is_local_name` | lengths 0, 1..4 and 6 => `!result`; `result` => `len >= 5 && len != 6` | runtime-checked |
| `bonjour_message_parse` | `data.len() < 12` => Err; Ok => `data.len() >= 12` | runtime-checked |
| `bonjour_message_question_offset` | out-of-range `i` => `-1`; `result != -1` => `i` in range | runtime-checked |

Deliberately skipped this pass (guarantee not expressible in the proven
families): `bonjour_name_encode_compressed` (suffix hit-test needs
`str_compare` over `Vec[Str]` elements), `bonjour_rr_parse` (guarantees
live on struct-Result payload fields), `bonjour_txt_get` (key match is
`str_compare`-based).

## Error string catalog

All error strings are stable API and start with `bonjour: `.

| Error text | Emitted by | Condition |
|---|---|---|
| `bonjour: truncated header` | `bonjour_header_decode`, `bonjour_message_parse` | fewer than 12 bytes |
| `bonjour: negative offset` | `bonjour_name_decode` (and callers) | `off < 0` |
| `bonjour: truncated name` | `bonjour_name_decode` | buffer ends inside a name, or a pointer's second byte is missing |
| `bonjour: truncated label` | `bonjour_name_decode` | a label's declared bytes run past the buffer end |
| `bonjour: unsupported label type` | `bonjour_name_decode` | length byte with bits 7..6 = 01 or 10 |
| `bonjour: pointer out of range` | `bonjour_name_decode` | pointer target >= `data.len()` |
| `bonjour: compression loop` | `bonjour_name_decode` | more pointer jumps than `data.len()` |
| `bonjour: name too long` | `bonjour_name_encode`, `bonjour_name_decode` | expanded/encoded name would exceed 255 bytes |
| `bonjour: empty label` | `bonjour_name_encode` | an empty label (leading dot, `..`, dot-only name other than `.`) |
| `bonjour: label too long` | `bonjour_name_encode` | a label longer than 63 bytes |
| `bonjour: label contains NUL byte` | `bonjour_name_encode`, `bonjour_name_decode` | label byte `0x00` |
| `bonjour: label not printable` | `bonjour_name_encode`, `bonjour_name_decode` | label byte outside 0x20..0x7E |
| `bonjour: truncated question` | `bonjour_question_parse`, `bonjour_message_parse` | fewer than 4 bytes after QNAME, or a declared question with no bytes left |
| `bonjour: truncated record` | `bonjour_rr_parse`, `bonjour_message_parse` | fewer than 10 bytes after NAME, or a declared record with no bytes left |
| `bonjour: truncated rdata` | `bonjour_rr_parse`, `bonjour_message_parse` | RDLENGTH runs past the buffer end |
| `bonjour: rdata out of range` | `bonjour_rr_rdata` | recorded span negative or beyond the passed buffer |
| `bonjour: rdata too long` | `bonjour_rr_encode` | `rdata.len() > 65535` |
| `bonjour: bad PTR rdata` | `bonjour_rdata_ptr_target` | `len < 1` |
| `bonjour: bad rdata name` | `bonjour_rdata_name` | `len < 1` or the name ends past `off + len` |
| `bonjour: bad SRV rdata` | `bonjour_rdata_srv_priority/weight/port/target` | `len < 7` (or a field outside the buffer) |
| `bonjour: bad A rdata` | `bonjour_rdata_a`, `bonjour_rdata_a_to_str` | length is not 4 |
| `bonjour: bad AAAA rdata` | `bonjour_rdata_aaaa`, `bonjour_rdata_aaaa_to_str` | length is not 16 |
| `bonjour: TXT string too long` | `bonjour_rdata_txt` | a TXT string exceeds 255 bytes |
| `bonjour: truncated TXT string` | `bonjour_rdata_txt_parse` | a length byte declares more bytes than the RDATA holds |
| `bonjour: TXT byte not printable` | `bonjour_rdata_txt`, `bonjour_rdata_txt_parse`, `bonjour_txt_pair` | TXT byte outside 0x20..0x7E |
| `bonjour: empty TXT key` | `bonjour_txt_pair` | empty key |
| `bonjour: TXT key contains '='` | `bonjour_txt_pair` | the key itself contains '=' |
| `bonjour: TXT key not found` | `bonjour_txt_get` | no pair matches the key |
| `bonjour: empty service` | `bonjour_service_type` | empty service label |
| `bonjour: service contains '.'` | `bonjour_service_type` | service is not a single label |
| `bonjour: service not printable` | `bonjour_service_type` | service byte outside 0x20..0x7E |
| `bonjour: bad service protocol` | `bonjour_service_type` | proto is not tcp/udp |
| `bonjour: empty instance` | `bonjour_instance_name` | empty instance label |
| `bonjour: instance contains '.'` | `bonjour_instance_name` | instance is not a single label |
| `bonjour: instance not printable` | `bonjour_instance_name` | instance byte outside 0x20..0x7E |
| `bonjour: empty subtype` | `bonjour_subtype_name` | empty subtype label |
| `bonjour: subtype contains '.'` | `bonjour_subtype_name` | subtype is not a single label |
| `bonjour: subtype not printable` | `bonjour_subtype_name` | subtype byte outside 0x20..0x7E |
| `bonjour: not a local domain` | local checks and the DNS-SD/query/advertise builders | name is not `local` / `*.local` |

Check order: header length, then offset sign, then name structure, then
the section-specific length fields, then RDATA contents. Name errors are
propagated unchanged through `bonjour_question_*`, `bonjour_rr_*` and
`bonjour_message_parse` (so `bonjour: pointer out of range` from a
question is reported as-is).

## Complexity

| Operation | Complexity |
|---|---|
| `bonjour_header_encode` / `bonjour_header_decode` | O(1) |
| `bonjour_name_encode` / `bonjour_name_decode` / `bonjour_name_to_str` | O(name bytes), decode worst case O(name bytes x pointer jumps) |
| `bonjour_name_encode_compressed` | O(labels x name length) |
| `bonjour_question_encode` / `bonjour_question_parse` | O(name bytes) |
| `bonjour_rr_encode` / `bonjour_rr_parse` | O(name bytes + RDATA length) |
| `bonjour_rr_rdata` | O(RDATA length) |
| `bonjour_rdata_*` builders/parsers | O(input length) |
| `bonjour_query_name` and the query/browse builders | O(name bytes) |
| `bonjour_advertise` | O(instance + type + host length + TXT bytes) |
| `bonjour_message_parse` | O(message bytes) |
| accessors | O(1) |

No allocation happens on an error path; every successful parse copies its
bytes into fresh values.

## Test plan

`tests/test_conformance.xi` (`module bonjour_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. header encode pins ID/flags/counts big-endian (`12 34 84 00 ...`) and
   masking (`id` 65543 -> 7, `qr` 3 -> 1, `opcode` 20 -> 4, `aa` 2 -> 0,
   `z` 9 -> 1, `rcode` 16 -> 0, `qdcount` 65537 -> 1), all-ones and
   all-zero decode, 11-byte truncation;
2. name encode pinned: `_http._tcp.local`, trailing-dot form, `""`/`"."`
   root, `local`, the enumeration name;
3. name encode boundaries: empty labels, 64-byte label, 255-byte name
   ok / 256-byte name error, non-printable bytes (0x7F, 0x09);
4. name decode: labels, `next`, `compressed` false, non-zero start
   offset, root;
5. compression pointers: `C0 00` to a full name, pointer-to-pointer
   chain, pointer-to-root;
6. name decode errors: empty buffer, `C0`, truncated label, unsupported
   label types `40`/`80`, pointer out of range, compression loop
   `C0 02 C0 00`, negative offset, NUL label, non-printable label,
   >255-byte expanded name;
7. compression encode: `Office._http._tcp.local` against
   `_http._tcp.local`@12 -> `06 4F 66 66 69 63 65 C0 0C`, full form on
   no match, no compression for offsets >= 16384, round-trip decode;
8. question encode pinned + QTYPE/QCLASS masking; parse fields/`next`;
   truncated question; negative offset;
9. class top bit: `bonjour_class_value`, base, flush and unicast readers;
10. generic resource record encode pinned (`host.local` A TTL 300),
    parse fields and RDATA span, RDATA copy, truncated record, truncated
    rdata, negative offset, shortened-buffer `rdata out of range`;
11. PTR RDATA build/parse, `bad PTR rdata` (`len < 1`), `bad rdata name`
    (span short), enumeration RDATA, non-local target;
12. SRV RDATA pinned (`myhost.local:8080`), priority/weight/port/target
    parsers, `len < 7` errors, field masking;
13. TXT RDATA pinned for two strings, parse list, empty string entry,
    truncated string, non-printable byte, 256-byte string rejected;
14. TXT key=value: pair builder (`key=value` and boolean `key`), empty
    key, key with '=', non-printable, lookups and missing key;
15. A/AAAA builders, bad lengths, `192.0.2.1` and
    `2001:db8:0:0:0:0:0:1` renderers;
16. DNS-SD names: service type (with/without underscores, case,
    errors), instance, subtype, enum name;
17. local checks: case-insensitive `local`/`*.local`, rejects empty,
    `local.`, `.local`, `example.com`; `check_local_name` Ok/Err;
18. enum/service/instance/generic queries: 46-byte enum query,
    QTYPE/QCLASS/QU/RD, PTR/SRV/ANY types, non-local errors;
19. record builders: PTR (shared), A/AAAA (flush), TXT (flush), SRV,
    goodbye TTL 0, TXT record;
20. advertise: parses as a 3-answer response (PTR/SRV/TXT in order,
    TTL 4500, flush bits, port, TXT pairs), non-local instance rejected;
21. message parse errors: truncated header/question/record/rdata;
    trailing bytes ignored;
22. message parse with a pointer-compressed owner name (`C0 0C`),
    question and record offsets, TTL, PTR target;
23. index accessors: counts, offsets, out-of-range `-1`;
24. browse query plus a synthetic PTR/SRV/TXT reply assembled from the
    record builders (port read back), and a subtype name round-tripped
    through encode/decode.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bonjour
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **Codec only.** No sockets, no multicast group membership, no
  query/response scheduling, no duplicate suppression, no cache, no
  conflict resolution; transport is the caller's concern.
- **Printable-ASCII subset.** A runtime `Str` is a NUL-terminated C
  string, so labels and TXT strings are restricted to `0x20..0x7E`
  (`bonjour: label not printable` / `bonjour: TXT byte not printable`);
  real-world DNS-SD names with UTF-8 bytes are outside the subset.
- **Compression is opt-in.** `bonjour_advertise` and the record builders
  emit full names (larger, but always self-contained).
  `bonjour_name_encode_compressed` compresses only against the caller's
  table of prior names; it never rewrites a name that was already
  emitted.
- **No name escape syntax.** A literal '.' cannot appear inside a label
  from the textual side; instance and subtype inputs must be single
  labels.
- **One `Str` per TXT string.** A TXT string longer than 255 bytes cannot
  be represented on the wire; multi-string RDATA is the way to carry
  more text.
- **No DNSSEC / EDNS(0).** Unknown RR types travel as raw RDATA; the Z
  bits are carried opaquely. There is no known-answer suppression or
  probing.
- **`bonjour_message_parse` ignores bytes after the last declared
  entry** (useful for framed transports; a strict length check is the
  caller's job).
- **TTL is a plain `Int`** (0..4294967295); there is no time arithmetic
  and no goodbye TTL handling beyond `bonjour_goodbye_ptr`.
- Not thread-safe; all values are plain value types and `Vec` fields.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_header`, `_err_header`, `_ok_name`, `_err_name`, `_ok_labels`,
  `_err_labels`, `_ok_question`, `_err_question`, `_ok_record`,
  `_err_record`, `_ok_message`, `_err_message`, `_ok_bytes`, `_err_bytes`,
  `_ok_str`, `_err_str`, `_ok_int`, `_err_int`); constructing `Result`
  values directly inside other functions miscompiles in this compiler.
- All big-endian packing/unpacking is arithmetic (division/modulo); every
  `Vec[UInt8]` byte read is widened with `(data[pos] as Int) & 0xFF`
  before it enters `Int` arithmetic.
- `Str` values read out of `Vec[Str]` are bound to typed locals
  (`let lbl: Str = labels[i];`) before use and compared only through
  `xiom.string.compare.str_compare` / `str_compare_ignore_case` (BUG 17:
  `==` on such elements lowers to a pointer comparison).
- Labels are materialized with `xiom.string.builder` (`sb_push_byte`,
  `sb_to_str`) only after the printable/NUL validation, so `sb_to_str`
  never sees `0x00`.
- No `match` appears in the library module (no mut in match arms); the
  tests use only `if`-based error checks.
- The whole-message index is flat (parallel `Vec[Int]` fields) because
  `Vec[StructType]` is unsupported.
- The tests call every check directly from `main` (no `Vec[fn]`
  dispatch, which miscompiles) and use typed locals for all Vec reads.
- The package declares no `extern "C"` blocks (no FFI).
