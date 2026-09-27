# xiom.bonjour

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) Bonjour codec for mDNS
> (RFC 6762) and DNS-SD (RFC 6763): mDNS message framing, domain names
> with compression pointers (validated on decode, optional on encode),
> PTR/SRV/TXT/A/AAAA records, and the DNS-SD name conventions
> (`_services._dns-sd._udp.local`, service types, instances, subtypes,
> TXT key=value lists, `local` domain checks, cache-flush /
> unicast-response class bit).
> **Deps:** `xiom.std` only. The library module imports only `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`; the tests use
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.builder`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.bonjour` turns Bonjour traffic into bytes and bytes into Bonjour
traffic. It is a codec, not a responder: it does not open sockets, join the
multicast group, send queries, retry, cache or run a server loop. What it
does cover is the wire format used by zero-configuration service discovery,
with deterministic error strings for malformed input:

- the 12-byte mDNS header (QR, Opcode, AA, TC, RD, RA, Z, RCODE) and the
  QD/AN/NS/AR section counts;
- domain names: label-aware encoding with the 1..63-byte label and 255-byte
  name limits; decoding follows compression pointers with loop,
  out-of-range and truncation detection; encoding can optionally emit
  pointers against a table of previously written names;
- questions and generic resource records, including the top class bit
  (cache-flush in responses, unicast-response QU in questions);
- typed RDATA builders and parsers for PTR, SRV, TXT, A and AAAA;
- DNS-SD conventions: the service enumeration name, service type /
  instance / subtype builders, TXT key=value helpers, `local` domain
  checks and recommended TTLs;
- advertise (PTR + SRV + TXT response), browse (PTR query) and query
  builders, plus a whole-message parser that indexes every question and
  record by offset.

See `SPEC.md` for the byte layout, the error catalog and the exact subset.

## API

| Function | Returns | Description |
|---|---|---|
| `bonjour_header_encode(h)` | `Vec[UInt8]` | 12-byte header; fields masked to their bit width. |
| `bonjour_header_decode(data)` | `Result[BonjourHeader, Str]` | Parse the header; `Err` below 12 bytes. |
| `bonjour_name_encode(name)` | `Result[Vec[UInt8], Str]` | Dotted name -> labels + terminating `0x00` (no pointers). |
| `bonjour_name_encode_compressed(name, prior_names, prior_offsets)` | `Result[Vec[UInt8], Str]` | Same, but emits a pointer on a suffix match. |
| `bonjour_name_decode(data, off)` | `Result[BonjourName, Str]` | Decode a name at `off`, following compression pointers. |
| `bonjour_name_to_str(n)` | `Str` | Presentation form (`a.b.c`, root is `""`). |
| `bonjour_class_value(top)` | `Int` | Class IN, plus the top bit when `top`. |
| `bonjour_class_flush(rclass)` | `Bool` | Cache-flush bit of a record class. |
| `bonjour_class_unicast(qclass)` | `Bool` | Unicast-response (QU) bit of a question class. |
| `bonjour_class_base(rclass)` | `Int` | Class with the top bit cleared (IN = 1). |
| `bonjour_question_encode(name, qtype, qclass)` | `Result[Vec[UInt8], Str]` | One question entry. |
| `bonjour_question_parse(data, off)` | `Result[BonjourQuestion, Str]` | Name, QTYPE, QCLASS, next offset. |
| `bonjour_rr_encode(name, rtype, rclass, ttl, rdata)` | `Result[Vec[UInt8], Str]` | One resource record. |
| `bonjour_rr_parse(data, off)` | `Result[BonjourRecord, Str]` | Name, TYPE, CLASS, TTL and the RDATA span. |
| `bonjour_rr_rdata(data, r)` | `Result[Vec[UInt8], Str]` | Copy a parsed record's RDATA out. |
| `bonjour_rdata_ptr(target)` | `Result[Vec[UInt8], Str]` | PTR RDATA (uncompressed target name). |
| `bonjour_rdata_srv(priority, weight, port, target)` | `Result[Vec[UInt8], Str]` | SRV RDATA: u16 x3 + target name. |
| `bonjour_rdata_txt(pairs)` | `Result[Vec[UInt8], Str]` | TXT RDATA: length-prefixed strings. |
| `bonjour_rdata_a(octets)` | `Result[Vec[UInt8], Str]` | A RDATA from exactly 4 octets. |
| `bonjour_rdata_aaaa(octets)` | `Result[Vec[UInt8], Str]` | AAAA RDATA from exactly 16 octets. |
| `bonjour_rdata_a_to_str(rdata)` | `Result[Str, Str]` | 4 bytes -> `"a.b.c.d"`. |
| `bonjour_rdata_aaaa_to_str(rdata)` | `Result[Str, Str]` | 16 bytes -> full-form IPv6. |
| `bonjour_rdata_name(data, off, len)` | `Result[BonjourName, Str]` | Name stored in RDATA (PTR/SRV target). |
| `bonjour_rdata_ptr_target(data, off, len)` | `Result[Str, Str]` | PTR target as a presentation string. |
| `bonjour_rdata_srv_priority(data, off, len)` | `Result[Int, Str]` | SRV priority field. |
| `bonjour_rdata_srv_weight(data, off, len)` | `Result[Int, Str]` | SRV weight field. |
| `bonjour_rdata_srv_port(data, off, len)` | `Result[Int, Str]` | SRV port field. |
| `bonjour_rdata_srv_target(data, off, len)` | `Result[BonjourName, Str]` | SRV target host name. |
| `bonjour_rdata_txt_parse(rdata)` | `Result[Vec[Str], Str]` | Split TXT RDATA into strings. |
| `bonjour_txt_pair(key, value)` | `Result[Str, Str]` | `"key=value"`, or `"key"` for an empty value. |
| `bonjour_txt_get(pairs, key)` | `Result[Str, Str]` | Value of `key` in a parsed TXT list. |
| `bonjour_service_enum_name()` | `Str` | `"_services._dns-sd._udp.local"`. |
| `bonjour_is_local_name(name)` | `Bool` | `local` / `*.local` check (case-insensitive). |
| `bonjour_check_local_name(name)` | `Result[Str, Str]` | The name when local, else `Err`. |
| `bonjour_service_type(service, proto, domain)` | `Result[Str, Str]` | `"_<service>.<proto>.<domain>"`. |
| `bonjour_service_type_name(service, proto)` | `Result[Str, Str]` | Service type in the `local` domain. |
| `bonjour_instance_name(instance, service_type)` | `Result[Str, Str]` | `"<instance>.<service_type>"`. |
| `bonjour_subtype_name(subtype, service_type)` | `Result[Str, Str]` | `"_<subtype>._sub.<service_type>"`. |
| `bonjour_enum_rdata(service_type)` | `Result[Vec[UInt8], Str]` | PTR RDATA for the enumeration record. |
| `bonjour_query_name(name, qtype, unicast)` | `Result[Vec[UInt8], Str]` | One-question query; QU + RD set when `unicast`. |
| `bonjour_service_query(service_type, unicast)` | `Result[Vec[UInt8], Str]` | Browse query (PTR) for a service type. |
| `bonjour_instance_query(instance_name, unicast)` | `Result[Vec[UInt8], Str]` | SRV query for an instance name. |
| `bonjour_enum_query(domain)` | `Result[Vec[UInt8], Str]` | PTR query for `_services._dns-sd._udp.<domain>`. |
| `bonjour_ptr_record(owner, target, ttl, flush)` | `Result[Vec[UInt8], Str]` | PTR record with TTL and flush choice. |
| `bonjour_srv_record(instance, priority, weight, port, host, ttl, flush)` | `Result[Vec[UInt8], Str]` | SRV record. |
| `bonjour_txt_record(instance, pairs, ttl, flush)` | `Result[Vec[UInt8], Str]` | TXT record. |
| `bonjour_a_record(owner, octets, ttl, flush)` | `Result[Vec[UInt8], Str]` | A record. |
| `bonjour_aaaa_record(owner, octets, ttl, flush)` | `Result[Vec[UInt8], Str]` | AAAA record. |
| `bonjour_goodbye_ptr(owner, target)` | `Result[Vec[UInt8], Str]` | PTR record with TTL 0. |
| `bonjour_advertise(instance, service_type, port, host, pairs)` | `Result[Vec[UInt8], Str]` | Response with PTR + SRV + TXT answers. |
| `bonjour_message_parse(data)` | `Result[BonjourMessage, Str]` | Whole message: header + offsets of every entry. |
| `bonjour_message_question_count(m)` | `Int` | Number of indexed questions. |
| `bonjour_message_record_count(m)` | `Int` | Number of indexed records (AN + NS + AR). |
| `bonjour_message_question_offset(m, i)` | `Int` | Name offset of question `i`; `-1` out of range. |
| `bonjour_message_record_offset(m, i)` | `Int` | Name offset of record `i`; `-1` out of range. |

Constants: `BONJOUR_PORT` (5353), `BONJOUR_MDNS_IPV4`
(`"224.0.0.251"`), `BONJOUR_MDNS_IPV6` (`"ff02::fb"`),
`BONJOUR_TYPE_A` (1), `BONJOUR_TYPE_PTR` (12), `BONJOUR_TYPE_TXT` (16),
`BONJOUR_TYPE_AAAA` (28), `BONJOUR_TYPE_SRV` (33), `BONJOUR_TYPE_ANY`
(255), `BONJOUR_CLASS_IN` (1), `BONJOUR_CLASS_TOP_BIT` (32768),
`BONJOUR_TTL_HOST` (120), `BONJOUR_TTL_SERVICE` (4500), `BONJOUR_DOMAIN`
(`"local"`), `BONJOUR_ENUM_PREFIX` (`"_services._dns-sd._udp."`).

Errors are `Err("bonjour: ...")` strings; the full catalog is in `SPEC.md`.

## Wire format

Header (12 bytes, big-endian): `ID[2] FLAGS[2] QDCOUNT[2] ANCOUNT[2]
NSCOUNT[2] ARCOUNT[2]`, where FLAGS packs QR (bit 15), Opcode (14..11),
AA (10), TC (9), RD (8), RA (7), Z (6..4) and RCODE (3..0).

Names are label sequences: `len label` repeated, then `0x00`. A two-byte
value with top bits `11` is a compression pointer to an offset. A question
is `QNAME QTYPE[2] QCLASS[2]`; a record is `NAME TYPE[2] CLASS[2] TTL[4]
RDLENGTH[2] RDATA`. In a response record the top class bit is cache-flush;
in a question it is unicast-response (QU).

RDATA layouts (RFC 6762 / RFC 2782 / RFC 6763):

| TYPE | Code | RDATA |
|---|---|---|
| A | 1 | 4 address octets |
| PTR | 12 | a domain name (the target) |
| TXT | 16 | one or more length-prefixed strings (`key=value`, or bare `key`) |
| AAAA | 28 | 16 address octets |
| SRV | 33 | priority[2], weight[2], port[2], then the target host name |

```text
PTR record: _http._tcp.local -> Office._http._tcp.local, TTL 4500, IN
05 5f 68 74 74 70 04 5f 74 63 70 05 6c 6f 63 61 6c 00   owner name
00 0c 00 01 00 00 11 94 00 19                          PTR, IN, TTL, RDLENGTH
06 4f 66 66 69 63 65 05 5f 68 74 74 70 04 5f 74 63 70
05 6c 6f 63 61 6c 00                                    target "Office._http._tcp.local"

DNS-SD enumeration query (bonjour_enum_query("local"), 46 bytes):
00 00 00 00 00 01 00 00 00 00 00 00                     header (QDCOUNT=1)
09 5f 73 65 72 76 69 63 65 73 07 5f 64 6e 73 2d 73 64
04 5f 75 64 70 05 6c 6f 63 61 6c 00                     QNAME
00 0c 00 01                                             QTYPE=PTR, QCLASS=IN
```

## Usage

```xi
use xiom.bonjour;
use xiom.io;
use xiom.string.builder;

// Advertise an instance: PTR + SRV + TXT as a response message.
var pairs = Vec[Str].new();
pairs.push("txtvers=1");
pairs.push("path=/");
let msg = bonjour_advertise("Office._http._tcp.local", "_http._tcp.local", 8080, "myhost.local", &pairs);
if msg.is_ok {
  let bytes: Vec[UInt8] = msg.value;

  // Read it back: header, then each record by index.
  let parsed = bonjour_message_parse(&bytes);
  if parsed.is_ok {
    let m: BonjourMessage = parsed.value;
    var sb = builder.sb_new();
    builder.sb_push_int(&mut sb, bonjour_message_record_count(&m));
    io.println("answer records: " + builder.sb_to_str(&sb));
    let off = bonjour_message_record_offset(&m, 0);
    let rr = bonjour_rr_parse(&bytes, off);
    if rr.is_ok {
      let rec: BonjourRecord = rr.value;
      let target = bonjour_rdata_ptr_target(&bytes, rec.rdata_offset, rec.rdata_length);
      if target.is_ok {
        io.println("first answer points at " + target.value);
      }
    }
  }
}

// Browse for services: a PTR query for the service type.
let browse = bonjour_service_query("_http._tcp.local", false);
// A goodbye for the same instance: a PTR record with TTL 0.
let bye = bonjour_goodbye_ptr("_http._tcp.local", "Office._http._tcp.local");
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bonjour
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only.** No sockets, no multicast membership, no query/response
  scheduling, cache, retry or server loop; transport is the caller's
  concern.
- **Printable-ASCII subset.** Because a runtime `Str` is NUL-terminated,
  every label and TXT string is restricted to printable ASCII
  (`0x20..0x7E`); byte `0x00` and non-ASCII bytes are rejected on both
  encode and decode (`bonjour: label not printable`). DNS-SD in the wild
  may use UTF-8 labels; those are outside this documented subset.
- **Compression is opt-in.** `bonjour_name_encode` and the record builders
  write full names; `bonjour_name_encode_compressed` emits pointers only
  against a caller-supplied table of previously written names, so
  `bonjour_advertise` output is uncompressed (valid, just larger).
- **No character-string escaping.** Names split on '.' bytes with no
  escape syntax (a label cannot contain a literal '.'), so the
  instance/subtype builders reject dots in the instance label.
- **Subset of record types.** Typed helpers exist for PTR, SRV, TXT, A and
  AAAA; other types travel as raw RDATA through
  `bonjour_rr_encode` / `bonjour_rr_parse` / `bonjour_rr_rdata`. No
  DNSSEC, EDNS(0), NSEC or known-answer suppression.
- **`bonjour_message_parse` ignores trailing bytes** after the last
  declared entry.
- **TTL is a plain `Int`** (0..4294967295); there is no time arithmetic.
- **Error strings, not error codes.** All failures are `Err(Str)` with a
  stable `bonjour: ...` text (catalog in `SPEC.md`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
