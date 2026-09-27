# xiom.pgp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pgp`, version `0.1.0`).
Module: `src/pgp.xi` (`module xiom.pgp`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`, `xiom.convert`).
No FFI, no crypto, no external libraries.

## 1. Scope

A structural OpenPGP (RFC 4880 / RFC 9580 subset) codec over `Vec[UInt8]` and
`Str`:

- `pgp_document_parse` frames a binary packet stream into a flat
  `PgpDocument`; both header formats are supported and every declared length
  is validated against the buffer before use.
- Packet tags 1..63 are framed; the ten tags this package names are
  Public-Key 6, Public-Subkey 14, Secret-Key 5, Signature 2, User ID 13,
  User Attribute 17, Literal Data 11, Compressed Data 8, Marker 10 and
  Trust 12 (`pgp_packet_type_*` constants and `pgp_packet_type_name`).
- The MPI codec (`pgp_mpi_decode`, `pgp_mpi_encode`, `pgp_mpi_value_bytes`)
  implements the two-octet bit count plus big-endian value octets, with
  canonical bit counts enforced on decode.
- `pgp_signature_v4_decode` / `pgp_signature_v4_encode` handle v4 signature
  bodies: version, type, public-key and hash algorithms, hashed subpacket
  region, unhashed subpacket region and left16.
- `pgp_subpacket_encode` / `pgp_subpacket_length_encode` emit one subpacket
  with the 1/2/5-octet length encoding; the same encoding is decoded as part
  of the signature body.
- `pgp_key_v4_decode` parses v4 key bodies: creation time, algorithm and the
  public MPI material (RSA, ElGamal, DSA, X9.42 DH, ECDH/ECDSA/EdDSA with a
  curve OID, and the RFC 9580 native curves X25519/X448/Ed25519/Ed448),
  exposing the split before any secret material.
- `pgp_user_id_text` validates User ID bodies as printable text and
  `pgp_user_id_key_index` / `pgp_user_id_binding_signature` expose the
  structural key-to-user-id binding.
- `pgp_armor_decode` / `pgp_armor_encode` implement ASCII armor: BEGIN/END
  labels, `Name: value` headers, blank separator, base64 payload and the
  optional CRC24 checksum line (CRC-24/OPENPGP, polynomial `0x1864CFB`,
  initial value `0xB704CE`), validated on decode and always emitted on
  encode.

All storage is flat: the document and the parsed bodies are parallel `Vec`
fields plus byte pools; there is no `Vec[StructType]` anywhere. Both
directions are O(n) and allocate their result in memory.

## 2. Non-goals

- **No cryptography.** No RSA/DSA/ECC arithmetic, no hashing, no signature
  verification, no key validation beyond structure. `left16` is carried, not
  checked.
- **No packet semantics** for Literal Data, Compressed Data, Trust, Marker
  or User Attribute bodies; they are framed bodies only.
- **No secret-key material parsing.** `pgp_key_v4_decode` stops at
  `public_end` and ignores trailing octets (S2K/secret MPIs).
- **No streaming/incremental API**: whole-value parse/emit only.
- **No partial lengths in subpackets** (RFC 4880 5.2.3.1), no partial chains
  shorter than the 512-octet RFC minimum for the first chunk.
- **No header folding, continuation lines, escaping or lookup** in armor.
- **No CR-only line endings** in armor.

## 3. Packet framing

### 3.1 Tag octets

A packet starts with a tag octet whose bit 7 must be set. For bit 6 set
(value 192..255) the packet is new-format and the tag is `value - 192`
(0..63); otherwise it is old-format and the tag is `(value - 128) / 4`
(0..15) with the length type in the low two bits. Tag 0 is reserved: both
formats reject it. A tag octet with bit 7 clear is rejected.

### 3.2 Old-format lengths (RFC 4880 4.2.1)

| Type | Field | Body length |
|---|---|---|
| 0 | 1 octet | the octet |
| 1 | 2 octets | big-endian 16-bit |
| 2 | 4 octets | big-endian 32-bit |
| 3 | none | rest of the input (indeterminate) |

`length_type` reports the type 0-3. Type 3 must be the last packet in
practice because its body consumes the remainder of the buffer.

### 3.3 New-format lengths (RFC 4880 4.2.2)

| First octet | Field | Body length |
|---|---|---|
| 0-191 | 1 octet | the octet |
| 192-223 | 2 octets | `((a - 192) * 256) + b + 192`, i.e. 192..8383 |
| 224-254 | 1 octet | partial chunk of `2 ** (a - 224)` octets |
| 255 | 5 octets | big-endian 32-bit, i.e. 0..4294967295 |

A partial chain is a run of partial chunks followed by one definite length;
the logical body is the concatenation of the chunk data. The first partial
chunk must be at least 512 octets; later partial chunks may be smaller.
`length_type` is 1, 2 or 5 for definite packets and 0 for partial packets;
`is_partial` and `chunk_count` describe the chain.

### 3.4 Validation

Every length is checked against the remaining buffer before any octet is
copied: a definite body that would run past the end is
`pgp: truncated packet body at offset N` (N = first body octet), a missing or
incomplete length field is `pgp: truncated packet header at offset N`
(N = first missing octet), a first partial chunk below 512 octets is
`pgp: partial body length below 512 at offset N` (N = chunk length octet).
An empty input parses to a document with zero packets.

### 3.5 Document storage

`PgpDocument` stores one entry per packet in parallel vectors: `tag`,
`format` (0 old, 1 new), `start` (offset in the source), `header_len`
(header octets before the first body octet), `length_type`, `is_partial`,
`chunk_count`, `body_start` (offset in the `bodies` pool), `body_len`, and
the `bodies: Vec[UInt8]` pool holding every body. Bodies are copied so
partial chains become contiguous; `pgp_packet_body(d, i)` returns a copy.

### 3.6 Encoding

`pgp_new_length_encode(len)` is the exact inverse of the definite new-format
reader: one octet for 0..191, two octets for 192..8383, five octets for
8384..4294967295 (negative values encode as 0). `pgp_packet_encode(tag, body)`
emits a new-format packet: tag octet `192 + tag` (tag clamped to 0..63),
shortest definite length, body.

## 4. MPI codec

An MPI is a two-octet big-endian **bit count** followed by `ceil(bits / 8)`
big-endian value octets.

- `pgp_mpi_decode(data, offset)` returns `PgpMpi{bits, value_start,
  value_len, next}`. The zero MPI (`00 00`) is accepted. A non-zero bit
  count is canonical only when the top value octet has bit `(bits - 1) % 8`
  set, i.e. the declared bit count equals the value's highest set bit; leading
  zero bits or octets are `pgp: non-canonical MPI at offset N`. Missing bit
  count or value octets are `pgp: truncated MPI at offset N`.
- `pgp_mpi_encode(value)` skips leading zero octets, computes the bit count
  from the first significant octet and emits the bit count plus value octets.
  An empty or all-zero value becomes `00 00`. A significant bit length above
  65535 is `pgp: MPI too large`.
- `pgp_mpi_value_bytes(data, mpi)` copies the value octets.

## 5. v4 signature body

Layout (RFC 4880 5.2.3, version 4):

```
offset 0     version = 4
offset 1     signature type
offset 2     public-key algorithm
offset 3     hash algorithm
offset 4-5   hashed subpacket region length (big-endian)
offset 6...  hashed subpackets
             unhashed subpacket region length (big-endian)
             unhashed subpackets
             left16 (2 octets)
```

`pgp_signature_v4_decode` rejects other versions
(`pgp: unsupported signature version N at offset 0`), frames every subpacket
in both regions (region flag, content offset, content length; the content is
the type octet plus data), records `left16` and rejects trailing octets and
truncation with offset-carrying messages. An empty unhashed region is legal.

### 5.1 Subpacket lengths (RFC 4880 5.2.3.1)

| First octet | Field | Content length |
|---|---|---|
| 0-191 | 1 octet | the octet |
| 192-223 | 2 octets | `((a - 192) * 256) + b + 192`, i.e. 192..8383 |
| 224-254 | -- | invalid in subpackets |
| 255 | 5 octets | big-endian 32-bit |

The content length includes the subpacket type octet and must be at least 1.
`pgp_subpacket_length_encode(len)` emits the shortest form for content length
`len` (1..4294967295) and is shared by `pgp_subpacket_encode(kind, payload)`,
which emits the length, the type octet and the payload.
`pgp_signature_v4_encode(sig_type, pubkey_algo, hash_algo, hashed, unhashed,
left16)` rebuilds a v4 body from pre-encoded regions; it requires a 2-octet
`left16`, algorithm/type octets in 0..255 and regions of at most 65535
octets.

## 6. v4 key body

Layout: version 4 (offset 0), creation time (offset 1-4, 32-bit unsigned
seconds), algorithm (offset 5), then algorithm-specific public material.

| Algorithms | Public material |
|---|---|
| 1, 2, 3 (RSA) | 2 MPIs: n, e |
| 16, 20 (ElGamal) | 3 MPIs: p, g, y |
| 17 (DSA) | 4 MPIs: p, q, g, y |
| 21 (X9.42 DH) | 3 MPIs: p, g, y |
| 18, 19, 22 (ECDH/ECDSA/EdDSA) | one-octet OID length, OID, 1 MPI (point) |
| 25, 26, 27, 28 (X25519/X448/Ed25519/Ed448) | 1 MPI (no OID) |

`pgp_key_v4_decode` records every MPI (`mpi_bits`, `mpi_start`,
`mpi_value_len`), the OID range for curve algorithms, and `public_end`, the
offset one past the public material. Any octets after `public_end` are
ignored (secret-key material, S2K usage and so on). Errors:
`pgp: unsupported key version N at offset 0`, `pgp: unsupported key
algorithm N at offset 5`, `pgp: truncated key at offset N`,
`pgp: bad curve OID at offset N`, plus the MPI errors from section 4.

## 7. User IDs and structural binding

- `pgp_user_id_text(d, i)` requires a User ID packet (tag 13) with a
  non-empty body. Bytes below 0x20 and DEL 0x7F are rejected
  (`pgp: user id has a non-printable byte at offset N`; N is the offset
  inside the body). Bytes >= 0x80 are accepted as UTF-8 text and are not
  validated further. Errors: `pgp: not a user id packet`,
  `pgp: user id is empty`.
- `pgp_user_id_key_index(d, i)` returns the highest index `j < i` whose tag
  is 5, 6 or 14 (the nearest preceding key packet), or -1.
- `pgp_user_id_binding_signature(d, i)` returns `i + 1` when that packet is
  a Signature (tag 2), or -1. The signature is not cryptographically
  verified; this is the structural binding only.

## 8. ASCII armor

### 8.1 Grammar

```
document   = *( blank-line / block )          ; non-empty text outside is Err
block      = begin-line LF [ headers blank-line ] body-lines [ crc-line ] end-line [LF]
begin-line = "-----BEGIN " label "-----"
end-line   = "-----END "   label "-----"
headers    = header-line *( LF header-line )
header-line= name ":" value
label      = 1..64 labelchar with single interior spaces
labelchar  = %x21-2C / %x2E-7E                ; printable, no space, no "-"
```

A line ends at LF or at end of input; one CR immediately before an LF is
removed. Exactly one block is decoded; text before or after it (other than
empty lines) is `pgp: armor text outside blocks`. An input with no BEGIN
line is `pgp: armor no block found`. A line starting with five dashes that is
not a well-formed marker is `pgp: armor malformed block marker`; a valid
BEGIN inside a block is `pgp: armor nested block not allowed`; the END label
must equal the BEGIN label (`pgp: armor label mismatch`); EOF inside a block
is `pgp: armor unterminated block`.

### 8.2 Headers and body

After BEGIN, a maximal run of `Name: value` lines is the header section; a
blank line (which may be the first line) ends it and starts the body. A
header-like line after the body started is `pgp: armor header after body`; a
header run without the blank separator is
`pgp: armor header section not terminated`; a second blank line is
`pgp: armor blank line in body`.

Body lines carry base64 characters; each line is at most 76 characters
(`pgp: armor bad body line length`). The concatenated body must have a length
that is a multiple of 4, `=` may appear only in the canonical final run, and
the unused low bits of a padded group must be zero:
`pgp: armor bad padding`, `pgp: armor invalid base64 character`,
`pgp: armor non-canonical trailing bits`.

### 8.3 Checksum

A checksum line is `=` followed by exactly four base64 characters. It is
optional; when present it is decoded and compared with CRC-24/OPENPGP of the
decoded payload. Malformed shapes and characters are
`pgp: armor bad checksum line`; a mismatch is
`pgp: armor checksum mismatch`; any body line after it is
`pgp: armor text after checksum`.

CRC-24/OPENPGP parameters: width 24, polynomial `0x1864CFB`, initial value
`0xB704CE`, no reflection, no final xor, check value `0x21CF02` for
`"123456789"` (`pgp_crc24`). The checksum characters are the base64 digits of
the 24-bit value (four characters, no padding).

### 8.4 Canonical emission

`pgp_armor_encode(a)` emits the BEGIN line, every stored header line, one
blank line (always, also with no headers), the payload as canonical base64
wrapped at exactly 64 characters per line with LF endings (no line for an
empty payload), the checksum line computed from the payload, the END line and
one trailing LF. `has_crc`/`crc` are ignored on encode. Invalid labels are
`pgp: armor invalid label`; malformed stored header lines are
`pgp: armor bad header line`.

## 9. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `pgp_document_parse(data)` | packet bytes | `Ok(PgpDocument)` | framing catalog |
| `pgp_packet_count/tag/format/start/header_len/length_type/is_partial/chunk_count/body_len(d, i)` | any document | value, or `-1` out of range | none |
| `pgp_packet_body(d, i)` | any document | body copy, or empty out of range | none |
| `pgp_new_length_encode(len)` | 0..4294967295 | shortest definite length | none |
| `pgp_packet_encode(tag, body)` | tag 0..63, bytes | complete new-format packet | none |
| `pgp_mpi_decode(data, offset)` | buffer, offset | `Ok(PgpMpi)` | truncated / non-canonical |
| `pgp_mpi_encode(value)` | magnitude bytes | `Ok(bytes)` | `pgp: MPI too large` |
| `pgp_mpi_value_bytes(data, mpi)` | buffer, MPI | value copy or empty | none |
| `pgp_subpacket_length_encode(len)` | 1..4294967295 | `Ok(bytes)` | bad length / too large |
| `pgp_subpacket_encode(kind, payload)` | type 0..255, bytes | `Ok(bytes)` | bad type, length errors |
| `pgp_signature_v4_decode(body)` | signature body | `Ok(PgpSignature)` | signature catalog |
| `pgp_signature_v4_encode(...)` | parts | `Ok(bytes)` | field/left16/region errors |
| `pgp_signature_*` accessors | signature | values or `-1`/empty out of range | none |
| `pgp_key_v4_decode(body)` | key body | `Ok(PgpKey)` | key catalog |
| `pgp_key_*` accessors | key | values or `-1`/empty out of range | none |
| `pgp_user_id_text(d, i)` | document, index | `Ok(Str)` | user-id catalog |
| `pgp_user_id_key_index(d, i)` | document, index | index or `-1` | none |
| `pgp_user_id_binding_signature(d, i)` | document, index | index or `-1` | none |
| `pgp_crc24(data)` | bytes | 24-bit checksum | none |
| `pgp_armor_decode(text)` | armor text | `Ok(PgpArmor)` | armor catalog |
| `pgp_armor_encode(a)` | armor value | `Ok(Str)` | label/header errors |
| `pgp_armor_label/header_count/header_line/payload_len/payload/crc/has_crc(a)` | armor | values or `""`/empty out of range | none |
| `pgp_packet_type_*()`, `pgp_packet_type_name(tag)` | none / tag | constants / name | none |
| `pgp_armor_label_message/public_key/private_key/signature()`, `pgp_armor_line_width()`, `pgp_base64_alphabet()` | none | constants | none |

### 9.1 Invariants

- `pgp_new_length_encode` and the new-format definite reader are exact
  inverses; `pgp_packet_encode` output re-parses to the same tag and body.
- `pgp_mpi_encode` output is canonical and re-decodes to the same bit count
  and value octets; every decoded MPI value has bit length `bits`.
- `pgp_subpacket_encode` output re-frames identically through a signature
  body.
- `pgp_armor_decode(pgp_armor_encode(a))` reproduces label, headers and
  payload; `pgp_armor_encode(pgp_armor_decode(t))` is the canonical form of
  `t` (64-column wrapping, blank line, CRC24 line, trailing LF).

## 10. Error catalog

All messages start with the literal prefix `pgp: `. The first applicable
rule in scan order wins.

| Message | Trigger |
|---|---|
| `pgp: invalid packet tag N at offset M` | Tag octet with bit 7 clear, or reserved tag 0. |
| `pgp: truncated packet header at offset N` | Length field missing or incomplete. |
| `pgp: truncated packet body at offset N` | Declared body (or partial chunk) runs past the buffer. |
| `pgp: partial body length below 512 at offset N` | First partial chunk < 512 octets. |
| `pgp: truncated MPI at offset N` | Bit count or value octets missing. |
| `pgp: non-canonical MPI at offset N` | Declared bit count does not match the value. |
| `pgp: MPI too large` | Encode: significant bit length > 65535. |
| `pgp: truncated signature at offset N` | Fixed field or left16 missing. |
| `pgp: unsupported signature version N at offset 0` | Version != 4. |
| `pgp: truncated hashed subpackets at offset N` | Hashed region runs past the body. |
| `pgp: truncated unhashed subpackets at offset N` | Unhashed length or region runs past the body. |
| `pgp: bad subpacket length at offset N` | Zero content length, or a partial-body code (224..254). |
| `pgp: truncated subpacket at offset N` | Subpacket header or content runs past its region. |
| `pgp: trailing signature data at offset N` | Octets after left16. |
| `pgp: bad signature field value` | Encode: type/algorithm octet outside 0..255. |
| `pgp: bad left16 length` | Encode: left16 is not 2 octets. |
| `pgp: subpacket region too long` | Encode: region > 65535 octets. |
| `pgp: bad subpacket length` | Encode: content length < 1. |
| `pgp: subpacket too large` | Encode: content length > 4294967295. |
| `pgp: bad subpacket type` | Encode: type octet outside 0..255. |
| `pgp: truncated key at offset N` | Fixed key fields, OID or MPI range missing. |
| `pgp: unsupported key version N at offset 0` | Version != 4. |
| `pgp: unsupported key algorithm N at offset 5` | Algorithm the package does not model. |
| `pgp: bad curve OID at offset N` | Zero-length OID for a curve algorithm. |
| `pgp: not a user id packet` | Index out of range or another tag. |
| `pgp: user id is empty` | Empty User ID body. |
| `pgp: user id has a non-printable byte at offset N` | Control byte or DEL. |
| `pgp: armor no block found` | No BEGIN line in the input. |
| `pgp: armor malformed block marker` | Five-dash line that is not a valid BEGIN/END. |
| `pgp: armor nested block not allowed` | BEGIN inside a block. |
| `pgp: armor text outside blocks` | Non-empty text before or after the block. |
| `pgp: armor label mismatch` | END label differs from BEGIN label. |
| `pgp: armor unterminated block` | EOF inside a block. |
| `pgp: armor header section not terminated` | Headers without a terminating blank line. |
| `pgp: armor blank line in body` | Second blank line inside one block. |
| `pgp: armor header after body` | `Name: value` line after the body started. |
| `pgp: armor invalid base64 character` | Body byte outside `A-Za-z0-9+/=`. |
| `pgp: armor bad padding` | Length not a multiple of 4, wrong `=` run, incomplete group. |
| `pgp: armor non-canonical trailing bits` | Padded group with non-zero unused bits. |
| `pgp: armor bad checksum line` | Checksum line not `=` plus four alphabet characters. |
| `pgp: armor checksum mismatch` | CRC24 of the payload differs from the checksum line. |
| `pgp: armor text after checksum` | Body data after the checksum line. |
| `pgp: armor bad body line length` | Body line longer than 76 characters. |
| `pgp: armor invalid label` | Encode: stored label fails the grammar. |
| `pgp: armor bad header line` | Encode: stored header lacks `Name: value` shape. |

## 11. Test plan

`tests/test_conformance.xi` (module `pgp_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Synthetic packets, MPIs, signatures and armored blocks are
built in-test from raw bytes; CRC24 expectations are pinned to
CRC-24/OPENPGP check values computed with an independent implementation
(`"123456789"` -> `0x21CF02`, `""` -> `0xB704CE`, `"Hello"` -> `0x10724C`),
and base64 expectations come from `xiom.encoding.base64`. All `Str` equality
goes through `xiom.string.compare.str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | constants | ten packet tags, names and armor labels |
| t2 | new one-octet | tag 13 User ID, header/body accessors, neutrals |
| t3 | new length boundaries | 191 (1), 192/8383 (2), 8384/16320 (5) |
| t4 | old length types | 0/1/2/3 including indeterminate |
| t5 | partial lengths | 1024+512+100 chain, 512 minimum, truncation, following packet |
| t6 | rejections | empty input, tags 0/plain, truncated headers/bodies |
| t7 | two packets | offsets and independent bodies |
| t8 | MPI decode | 57-bit vector, zero MPI, offset decode, truncation, canonicality |
| t9 | MPI encode | pinned magnitudes, round trip, 16-bit limit |
| t10 | v4 signature | fields, hashed/unhashed framing, starts, left16 |
| t11 | subpacket forms | content 100/200/16320/191 frame and re-read |
| t12 | signature errors | version, truncation, subpacket framing, trailing data |
| t13 | subpacket/signature encode | pinned 1/2/5 forms, round trip, limits |
| t14 | v4 RSA key | creation time, n/e MPIs, secret-material split |
| t15 | v4 key algorithms | DSA, ElGamal, ECDSA, EdDSA, X25519, key errors |
| t16 | user ids | printable text, empty/control rejection, key and signature binding |
| t17 | packet encode | length boundaries, pinned bytes, parse round trips |
| t18 | CRC24 | pinned check values and checksum characters |
| t19 | armor decode | headers, checksum, no-CRC, CRLF, multi-line body |
| t20 | armor checksum | mismatch, malformed line, text after, empty payload |
| t21 | armor framing | markers, outside text, headers, body rules |
| t22 | armor encode | canonical form, wrapping, validation errors |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pgp
# port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

## 12. Known limitations

- Structural only: no crypto, no key validation beyond layout, `left16` and
  signature material are opaque.
- Secret material is not parsed; `public_end` is the only split provided.
- One armor block per document; multi-block keyring files must be split by
  the caller.
- Armor body lines are limited to 76 characters; non-canonical wider wrapping
  (legal for some producers) is rejected.
- Partial-chunk chains are buffered whole (O(body size) memory).
- User ID text accepts high bytes without UTF-8 validation.

## 13. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch, no `match` in the library.
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_doc`/`_err_doc`,
  `_ok_mpi`/`_err_mpi`, `_ok_sig`/`_err_sig`, `_ok_key`/`_err_key`,
  `_ok_armor`/`_err_armor`, `_ok_bytes`/`_err_bytes`, `_ok_str`/`_err_str`,
  `_ok_int`/`_err_int`.
- Every raw byte read is widened with `(x as Int) & 0xFF`; every
  `Vec[Int]`/`Vec[Str]` element read is bound to a typed local first; `Str`
  values read from `Vec[Str]` are compared byte-wise (`_str_eq`).
- `&struct.field` is never passed where a `&Vec[UInt8]` parameter is expected;
  such fields are copied into locals first.
- No bitwise shifts: powers of two are built by multiplication, fields are
  split with division and modulo, and `ceil(bits / 8)` uses an explicit
  quotient/remainder.
- Error messages carry byte offsets produced with `xiom.convert.int`.
