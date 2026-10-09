# xiom.ldap -- byte-level specification

Version: 0.1.2 (stable; published on the XIOM registry).

This document describes exactly what `src/ldap.xi` implements: the accepted
wire grammar, the validation order, the flat decode models and the complete
error catalog. It is the contract the conformance suite tests.

Vocabulary: a **TLV** is a tag byte, a definite length, and that many
content bytes. A **container** is the content span of a parsed TLV. All
offsets are absolute indexes into the caller's `Vec[UInt8]`; "reports at
OFF" means the error string `... at offset OFF`.

## 1. Scope

Decode (RFC 4511 with IMPLICIT TAGS):

* BER primitives: one-byte tags, definite short/long-form lengths,
  INTEGER, ENUMERATED, BOOLEAN, OCTET STRING, SEQUENCE/SET;
* the LDAPMessage envelope and the optional controls field (bounds only);
* BindRequest/BindResponse, UnbindRequest, SearchRequest,
  SearchResultEntry, SearchResultDone, SearchResultReference,
  ModifyRequest/ModifyResponse, AddRequest/AddResponse,
  DelRequest/DelResponse, ModifyDNRequest/ModifyDNResponse,
  CompareRequest/CompareResponse, AbandonRequest,
  ExtendedRequest/ExtendedResponse;
* the shared LDAPResult field set (resultCode, matchedDN,
  diagnosticMessage, referral, serverSaslCreds, responseName,
  responseValue);
* every RFC 4511 filter choice, flattened into parallel arrays with a
  depth cap.

Encode:

* minimal BER building blocks (`ber_*_encode`, `ber_tlv_wrap`);
* a simple-authentication BindRequest (0x60);
* a SearchRequest (0x63) with one equality filter;
* message wrapping (`ldap_message_encode`).

Out of scope: I/O, LDIF, schema, SASL mechanisms, Controls decoding,
IntermediateResponse (0x79), LDAPURL parsing, response/update builders.

## 2. BER layer

### 2.1 Tag

`ber_tlv_decode(data, off)` reads one tag byte.

1. `off < 0` -> `ber: negative offset` (no offset suffix).
2. `off >= len(data)` -> `ber: truncated tag` at `off`.
3. `tag % 32 == 31` (low five bits 11111, a multi-byte tag) ->
   `ber: multi-byte tag` at `off`.

No other tag value is rejected at this layer; type checking happens in the
typed decoders (`ber_int_decode`, ...) and operation parsers via
`ber: tag mismatch`.

### 2.2 Length

`ber_length_decode(data, off)` accepts the definite form only and requires
the minimal long form.

Short form (`b < 0x80`): content length `b`, size 1.

Long form (`0x80 | n`):

1. `n == 0` (byte 0x80) -> `ber: indefinite length` at `off`.
2. `n > 8` -> `ber: length overflow` at `off`.
3. fewer than `n` bytes remain -> `ber: truncated length` at `off`.
4. first length byte is 0x00 -> `ber: overlong length` at `off`.
5. accumulating the big-endian value overflows a signed 64-bit Int ->
   `ber: length overflow` at `off`.
6. accumulated value `< 128` -> `ber: overlong length` at `off`.

A long form therefore never encodes a length a short form could, and never
carries a leading zero byte.

### 2.3 TLV bounds

After the length, `content = off + 1 + size` and
`next = content + len`.

* `len > data.len() - content` -> `ber: value overruns buffer` at `off`
  (the content is not fully in the buffer).
* Container-scoped parsers re-check `next <= end` and report
  `ber: value overruns container` at the field's own offset.

### 2.4 Typed decoders

| Function | Tag | Content rules |
|---|---|---|
| `ber_int_decode` | 0x02 | 1..8 bytes; `ber: empty integer`, `ber: integer overflow` (n > 8) and `ber: non-minimal integer` (0x00 with next byte < 0x80, or 0xFF with next byte >= 0x80) all report at the TLV start. Value is the signed two's-complement integer. |
| `ber_enum_decode` | 0x0A | Same content rules and errors as INTEGER; the value may be negative at this layer and is range-checked by the operation parsers. |
| `ber_octet_string_decode` | 0x04 | Any content length including 0; bytes are copied verbatim. |
| `ber_bool_decode` | 0x01 | Exactly 1 content byte; `ber: bad boolean` otherwise. 0x00 -> 0, any other byte -> 1. |
| `ber_sequence_decode` | 0x30 or 0x31 | Header only; `BerTlv.tag` is the actual wire tag. |

Tag mismatches report `ber: tag mismatch` at the TLV's first byte.

### 2.5 Encoders

* `ber_length_encode(len)`: `len < 0` -> empty vector; `len < 128` -> one
  byte; otherwise `0x80|n` plus the minimal big-endian bytes.
* `ber_int_encode(v)` / `ber_enum_encode(v)`: minimal two's-complement
  content (0x00 for zero, 0xFF sign extension only where required).
* `ber_octet_string_encode(bytes)`: verbatim content.
* `ber_bool_encode(b)`: `01 01 FF` for true, `01 01 00` for false.
* `ber_tlv_wrap(tag, content)`: tag byte + definite length + content.

## 3. LDAP strings

LDAPString, LDAPDN and LDAPOID values that become a `Str` are validated as
printable ASCII, i.e. every byte in 0x20..0x7E. A violation reports
`ldap: non-printable string` at the offset of the string TLV (or, for
implicitly tagged fields, at the field's TLV). This is deliberate: a Str is
a NUL-terminated C string at the ABI, so arbitrary bytes cannot round-trip.
Everything that may hold arbitrary octets (attribute values, assertion
values, passwords, SASL credentials, requestValue, responseValue) stays a
raw `Vec[UInt8]` or an offset/length pair.

## 4. LDAPMessage

```
LDAPMessage ::= SEQUENCE {
     messageID   MessageID,          -- INTEGER >= 0
     protocolOp  CHOICE { ... },     -- one of the tags in section 5
     controls    [0] Controls OPTIONAL }
```

`ldap_message_parse(data)` validates, in order:

1. TLV at offset 0 must be a SEQUENCE; otherwise `ber: tag mismatch` at 0.
2. The messageID must be a minimal INTEGER inside the message container;
   a negative value reports `ldap: negative message id` at the INTEGER
   TLV. (0 is accepted; RFC 4511 reserves it for unsolicited notices, and
   this layer does not police that.)
3. The protocolOp TLV must start before the container end (`ber: truncated
   tag` otherwise), fit the container (`ber: value overruns container`),
   and carry a known tag from section 5 (`ldap: bad protocol op`).
4. If bytes remain after the protocolOp, the next tag must be 0xA0
   (`ldap: trailing bytes` otherwise). The controls TLV is bounds-checked
   and must end exactly at the message end; it is captured as
   `controls_offset` / `controls_length` (the whole TLV, tag through last
   content byte) and never decoded.
5. Bytes after the message TLV are ignored: a stream may hold
   back-to-back messages.

Result: `LdapMessage { message_id, op_tag, op_offset, op_length,
has_controls, controls_offset, controls_length, next }`, with
`op_length` the protocolOp TLV length (tag through last content byte).

`ldap_op_tag_known` / `ldap_op_tag_name` cover the protocolOp tag set.
Known tags: 0x42, 0x4A, 0x50, 0x60, 0x61, 0x63, 0x64, 0x65, 0x66, 0x67,
0x68, 0x69, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x73, 0x77, 0x78.

## 5. Operations

All constructs use implicit tagging: the context/application tag replaces
the underlying type's tag, so the content is the field list itself, not a
nested TLV of the original type. Field order is mandatory; a value field
that overruns its container reports `ber: value overruns container` at the
field offset, and any leftover byte inside a container reports
`ldap: trailing bytes` at the first unconsumed offset.

### 5.1 BindRequest -- 0x60 (constructed)

```
SEQUENCE {
     version         INTEGER (1..127),
     name            LDAPDN,
     authentication  CHOICE {
          simple      [0] OCTET STRING,     -- tag 0x80
          sasl        [3] SaslCredentials } -- tag 0xA3
}
SaslCredentials ::= { mechanism LDAPString, credentials OCTET STRING OPTIONAL }
```

* version outside 1..127 -> `ldap: bad bind version` at the INTEGER TLV.
* authentication tag other than 0x80/0xA3 -> `ldap: bad authentication`
  at the authentication TLV offset.
* simple: the password bytes are copied verbatim into `auth_bytes`.
* sasl: `mechanism` is a normal OCTET STRING TLV inside the 0xA3 content
  (wrong tag -> `ber: tag mismatch` at the mechanism offset), then the
  optional credentials OCTET STRING is copied verbatim. `sasl_present` is
  true; `auth_tag` is 0xA3.
* Decoded shape: `LdapBindRequest { version, name, auth_tag, sasl_present,
  mechanism, auth_bytes, next }`.

### 5.2 BindResponse -- 0x61 (constructed)

LDAPResult fields, then the optional `serverSaslCreds [7]` (tag 0x87,
implicit OCTET STRING: raw bytes).

### 5.3 UnbindRequest -- 0x42 (primitive)

NULL content; a non-empty content reports `ldap: bad unbind` at the tag.
Returns the offset just past the TLV.

### 5.4 AbandonRequest -- 0x50 (primitive)

Implicitly tagged MessageID: the content is an integer content field with
the INTEGER rules (1..8 bytes, minimal). `ldap: negative abandon id` for a
negative value; the empty/overflow/non-minimal errors come from the
integer content parser and report at the tag.

### 5.5 SearchRequest -- 0x63 (constructed)

```
SEQUENCE {
     baseObject      LDAPDN,
     scope           ENUMERATED { base (0), one (1), sub (2) },
     derefAliases    ENUMERATED { never (0), searching (1), find (2), always (3) },
     sizeLimit       INTEGER (>= 0),
     timeLimit       INTEGER (>= 0),
     typesOnly       BOOLEAN,
     filter          Filter,
     attributes      SEQUENCE OF LDAPString }
```

* scope outside 0..2 -> `ldap: bad scope` at the ENUMERATED TLV.
* derefAliases outside 0..3 -> `ldap: bad deref aliases` at the
  ENUMERATED TLV.
* negative limits -> `ldap: negative integer` at the INTEGER TLV.
* the filter is fully parsed into the embedded flat tree (section 6) and
  additionally bounded by `filter_offset` / `filter_length`.
* attributes: zero or more OCTET STRINGs, each validated printable.
* Decoded shape: `LdapSearchRequest { base_object, scope,
  deref_aliases, size_limit, time_limit, types_only, filter_offset,
  filter_length, filter, attributes, next }`.

### 5.6 SearchResultEntry -- 0x64 (constructed)

`SEQUENCE { objectName LDAPDN, attributes PartialAttributeList }` where

```
PartialAttributeList ::= SEQUENCE OF SEQUENCE {
     type  AttributeDescription,
     vals  SET OF AttributeValue }      -- SET tag 0x31
```

`ldap_attribute_list_parse` decodes the list standalone, reporting
`ber: tag mismatch` when an element or the value set uses the wrong tag.
Values are stored as offset/length pairs; nothing about them is
interpreted. Decoded shape: `LdapAttributeList { names, first_value,
value_count, value_offsets, value_lengths, next }` where entry `i` has
`value_count[i]` values starting at index `first_value[i]`.
`ldap_search_entry_parse` returns `LdapSearchEntry { object_name, attrs,
next }`.

### 5.7 LDAPResult responses

```
LDAPResult ::= SEQUENCE {
     resultCode         ENUMERATED (>= 0),
     matchedDN          LDAPDN,
     diagnosticMessage  LDAPString,
     referral           [3] Referral OPTIONAL }   -- tag 0xA3, implicit SEQUENCE OF LDAPURL
```

* a negative resultCode -> `ldap: negative result code` at the
  ENUMERATED TLV.
* referral content is one or more OCTET STRING TLVs (each validated
  printable); zero -> `ldap: empty referral` at the referral tag.
* an unknown tag in the optional position -> `ldap: trailing bytes`
  (strict per-response ordering).

| Tag | Response | Extra accepted fields |
|---|---|---|
| 0x61 | BindResponse | serverSaslCreds [7] = 0x87 |
| 0x65 | SearchResultDone | none |
| 0x67 | ModifyResponse | none |
| 0x69 | AddResponse | none |
| 0x6B | DelResponse | none |
| 0x6D | ModifyDNResponse | none |
| 0x6F | CompareResponse | none |
| 0x78 | ExtendedResponse | responseName [10] = 0x8A, responseValue [11] = 0x8B |

responseName is an implicitly tagged LDAPOID (raw bytes, validated
printable); responseValue is raw bytes. Decoded shape: `LdapResult {
result_code, matched_dn, diagnostic, has_referral, referrals,
has_sasl_creds, sasl_creds, has_response_name, response_name,
has_response_value, response_value, next }`.

### 5.8 ModifyRequest -- 0x66 (constructed)

```
SEQUENCE {
     object   LDAPDN,
     changes  SEQUENCE OF SEQUENCE {
          operation     ENUMERATED { add (0), delete (1), replace (2) },
          modification  PartialAttribute } }
```

An operation outside 0..2 -> `ldap: bad modify operation` at the
ENUMERATED TLV. Decoded shape: `LdapModifyRequest { object, changes, next }`
with `LdapChanges { ops, names, first_value, value_count, value_offsets,
value_lengths, next }` (same index layout as the attribute list).

### 5.9 AddRequest -- 0x68 (constructed)

`SEQUENCE { entry LDAPDN, attributes PartialAttributeList }` ->
`LdapAddRequest { entry, attrs, next }`.

### 5.10 DelRequest -- 0x4A (primitive)

Implicitly tagged LDAPDN: the content is raw DN bytes, validated printable.
Returns `LdapStr { value, next }`.

### 5.11 ModifyDNRequest -- 0x6C (constructed)

```
SEQUENCE {
     entry         LDAPDN,
     newrdn        RelativeLDAPDN,
     deleteoldrdn  BOOLEAN,             -- real BOOLEAN tag 0x01
     newSuperior   [0] LDAPDN OPTIONAL }
```

newSuperior (tag 0x80) is raw DN bytes, validated printable. A trailing
field whose tag is not 0x80 -> `ldap: trailing bytes`. Decoded shape:
`LdapModifyDnRequest { entry, new_rdn, delete_old_rdn, has_new_superior,
new_superior, next }`.

### 5.12 CompareRequest -- 0x6E (constructed)

```
SEQUENCE {
     entry  LDAPDN,
     ava    SEQUENCE { attributeDesc, assertionValue } }   -- real SEQUENCE tag
```

The assertion value stays in the buffer. Decoded shape:
`LdapCompareRequest { entry, attr, value_offset, value_length, next }`.

### 5.13 SearchResultReference -- 0x73 (constructed)

Implicitly tagged `SEQUENCE OF LDAPURL`: one or more OCTET STRING TLVs,
each validated printable; zero -> `ldap: empty search reference` at the
tag. Decoded shape: `LdapSearchReference { uris, next }`.

### 5.14 ExtendedRequest -- 0x77 (constructed)

```
SEQUENCE {
     requestName   [0] LDAPOID,                 -- tag 0x80, raw bytes
     requestValue  [1] OCTET STRING OPTIONAL }  -- tag 0x81, raw bytes
```

A missing/incorrectly tagged requestName -> `ldap: bad extended request`.
Decoded shape: `LdapExtendedRequest { request_name, has_value,
value_offset, value_length, next }`.

## 6. Filters -- flat tree

```
Filter ::= CHOICE {
     and             [0] SET OF Filter,          -- 0xA0
     or              [1] SET OF Filter,          -- 0xA1
     not             [2] Filter,                 -- 0xA2
     equalityMatch   [3] AttributeValueAssertion,-- 0xA3
     substrings      [4] SubstringFilter,        -- 0xA4
     greaterOrEqual  [5] AttributeValueAssertion,-- 0xA5
     lessOrEqual     [6] AttributeValueAssertion,-- 0xA6
     present         [7] AttributeDescription,   -- 0x87 primitive
     approxMatch     [8] AttributeValueAssertion,-- 0xA8
     extensibleMatch [9] MatchingRuleAssertion } -- 0xA9
```

`ldap_filter_parse(data, off)` fills one `LdapFilter` value:

| Field | Meaning |
|---|---|
| `kinds[i]` | 1 and, 2 or, 3 not, 4 equality, 5 substrings, 6 greaterOrEqual, 7 lessOrEqual, 8 present, 9 approx, 10 extensible |
| `parents[i]` | parent node index, -1 for the root |
| `depths[i]` | ancestor count (root 0) |
| `first_child[i]`, `child_count[i]` | and/or/not children; item nodes have 0 |
| `attrs[i]` | attribute description ("" for and/or/not) |
| `val_offsets[i]`, `val_lengths[i]` | raw assertion value bounds (item nodes) |
| `sub_first[i]`, `sub_count[i]` | substring part range into `part_*` |
| `part_kinds[p]`, `part_offsets[p]`, `part_lengths[p]` | 128 initial, 129 any, 130 final |
| `rules[i]` | extensible matchingRule ("" when absent) |
| `dn_attrs[i]` | extensible dnAttributes 0/1 |
| `next` | offset just past the filter TLV |

Rules and errors:

* every node's TLV must fit the container and depth
  `depth > LDAP_MAX_FILTER_DEPTH` (32) -> `ldap: filter too deeply
  nested` at the node offset;
* unknown choice tag -> `ldap: bad filter tag` at the tag;
* and/or must have at least one child -> `ldap: empty and/or filter`;
* not must have exactly one child and non-empty content ->
  `ldap: bad not filter`;
* AttributeValueAssertion (implicit tags 0xA3/0xA5/0xA6/0xA8): content is
  an OCTET STRING attribute description followed by an OCTET STRING
  assertion value; wrong inner tags -> `ber: tag mismatch`;
* substrings: OCTET STRING attribute description, then a real SEQUENCE
  (0x30) of implicitly tagged parts; a part tag outside
  0x80/0x81/0x82, an initial part that is not first, any part after a
  final part, or an empty part list -> `ldap: bad substring filter`
  (at the offending part, or at the filter tag for an empty list);
* extensibleMatch: optional [1] rule (0x81) and [2] type (0x82) as raw
  printable bytes in that order, required [3] matchValue (0x83) raw
  bytes, optional [4] dnAttributes (0x84) as a 1-byte BOOLEAN; a missing
  matchValue -> `ldap: bad extensible match` at the filter tag; an
  out-of-order or unknown trailing tag -> `ldap: trailing bytes`;
* any leftover byte inside a node -> `ldap: trailing bytes` at the first
  unconsumed offset.

## 7. Result-code table

`ldap_result_code_name(code)` returns the RFC 4511 / IANA name, `reserved`
for 37..47, 55..63 and 81..112, and `unknown` otherwise.
`ldap_result_code_known(code)` is true only for named codes.

| Code | Name | Code | Name |
|---|---|---|---|
| 0 | success | 48 | inappropriateAuthentication |
| 1 | operationsError | 49 | invalidCredentials |
| 2 | protocolError | 50 | insufficientAccessRights |
| 3 | timeLimitExceeded | 51 | busy |
| 4 | sizeLimitExceeded | 52 | unavailable |
| 5 | compareFalse | 53 | unwillingToPerform |
| 6 | compareTrue | 54 | loopDetect |
| 7 | authMethodNotSupported | 64 | namingViolation |
| 8 | strongerAuthRequired | 65 | objectClassViolation |
| 9 | partialResults | 66 | notAllowedOnNonLeaf |
| 10 | referral | 67 | notAllowedOnRDN |
| 11 | adminLimitExceeded | 68 | entryAlreadyExists |
| 12 | unavailableCriticalExtension | 69 | objectClassModsProhibited |
| 13 | confidentialityRequired | 70 | resultsTooLarge |
| 14 | saslBindInProgress | 71 | affectsMultipleDSAs |
| 16 | noSuchAttribute | 80 | other |
| 17 | undefinedAttributeType | 113 | lcupResourcesExhausted |
| 18 | inappropriateMatching | 114 | lcupSecurityViolation |
| 19 | constraintViolation | 115 | lcupInvalidData |
| 20 | attributeOrValueExists | 116 | lcupUnsupportedScheme |
| 21 | invalidAttributeSyntax | 117 | lcupReloadRequired |
| 32 | noSuchObject | 118 | canceled |
| 33 | aliasProblem | 119 | noSuchOperation |
| 34 | invalidDNSyntax | 120 | tooLate |
| 35 | isLeaf | 121 | cannotCancel |
| 36 | aliasDereferencingProblem | 122 | assertionFailed |
|  |  | 123 | authorizationDenied |
|  |  | 4096 | syncRefreshRequired |

## 8. Encoders

Validation happens before any byte is produced; encoder errors carry no
offset suffix.

`ldap_bind_request_encode(version, name, password)`:

1. `version` outside 1..127 -> `ldap: bad bind version`;
2. non-printable `name` -> `ldap: non-printable string`;
3. bytes: `60 LEN 02 01 VV 04 LEN name 80 LEN password`.
   Minimal case (version 3, "", empty password) is exactly
   `60 07 02 01 03 04 00 80 00`.

`ldap_search_request_encode(base, scope, deref, size, time, types_only,
attr, value, attributes)`:

1. scope outside 0..2 -> `ldap: bad scope`;
2. deref outside 0..3 -> `ldap: bad deref aliases`;
3. negative size/time limit -> `ldap: negative integer`;
4. non-printable base/attr/attribute -> `ldap: non-printable string`;
5. bytes: `63 LEN 04 LEN base 0A 01 scope 0A 01 deref 02 LEN size
   02 LEN time 01 01 TT A3 LEN (04 LEN attr 04 LEN value)
   30 LEN (04 LEN attribute ...)`.

`ldap_message_encode(message_id, op)`:

1. negative id -> `ldap: negative message id`; id above
   2147483647 -> `ldap: message id too large`;
2. empty op -> `ldap: empty operation`;
3. bytes: `30 LEN (02 LEN id, op)`.

Parse/re-encode stability: parsing the output of either builder and
re-encoding the parsed values yields byte-identical bytes (tested in
`t18`/`t19`).

## 9. Complete error catalog

BER layer (deferred by the offset suffix shown):

```
ber: negative offset
ber: truncated tag at offset N
ber: multi-byte tag at offset N
ber: truncated length at offset N
ber: indefinite length at offset N
ber: length overflow at offset N
ber: overlong length at offset N
ber: value overruns buffer at offset N
ber: value overruns container at offset N
ber: tag mismatch at offset N
ber: empty integer at offset N
ber: integer overflow at offset N
ber: non-minimal integer at offset N
ber: bad boolean at offset N
```

LDAP layer:

```
ldap: non-printable string at offset N
ldap: negative message id at offset N
ldap: bad protocol op at offset N
ldap: trailing bytes at offset N
ldap: bad bind version at offset N
ldap: bad authentication at offset N
ldap: bad unbind at offset N
ldap: negative abandon id at offset N
ldap: negative result code at offset N
ldap: empty referral at offset N
ldap: bad scope at offset N
ldap: bad deref aliases at offset N
ldap: negative integer at offset N
ldap: bad attribute list at offset N
ldap: bad filter tag at offset N
ldap: empty and/or filter at offset N
ldap: bad not filter at offset N
ldap: bad substring filter at offset N
ldap: bad extensible match at offset N
ldap: filter too deeply nested at offset N
ldap: bad filter at offset N          (internal progress guard)
ldap: bad modify operation at offset N
ldap: empty search reference at offset N
ldap: bad extended request at offset N
```

Encoder (no offsets):

```
ldap: bad bind version
ldap: non-printable string
ldap: bad scope
ldap: bad deref aliases
ldap: negative integer
ldap: negative message id
ldap: message id too large
ldap: empty operation
```

## 10. Limits

| Limit | Value | Behaviour |
|---|---|---|
| Filter nesting | 32 ancestors | `ldap: filter too deeply nested` |
| Integer content | 8 bytes | `ber: integer overflow` |
| Long-form length bytes | 8 | `ber: length overflow` |
| messageID / abandon id | 0..2147483647 | negative rejected on decode and encode; larger ids rejected only by `ldap_message_encode` (decode accepts any non-negative Int) |
| Decoded Str fields | printable ASCII 0x20..0x7E | `ldap: non-printable string` |

## Contracts (batch #49 hardening pass, 2026-10-09)

Runtime-checkable `ensures:` clauses (41, across the 15 functions below) were
added to `src/ldap.xi` in the batch #49 hardening pass (compiler v0.64.1;
`package.xi` is left for the coordinator to bump at integration). All are
`ensures:` with no `requires:`, so the accepted-input domain is unchanged.
Every clause is enforced as a runtime check; the 20-check conformance suite
exercises the contracted entry points and no clause trapped, so none was
dropped. Two consecutive green `& .\scripts\port.ps1 -Package xiom.ldap
-TimeoutSec 90` runs ended `port: PASS (passed=20 failed=0 program_exit=0
exit=0)` with the clauses active (19.98 s and 33.16 s). None is claimed
Z3-provable: `xiom-verify` was not run for this module, and per the batch
#37 finding a bare `[OK] VERIFIED` can be a vacuous UNSAT, so the
Z3-provable column is "no" throughout.

Clause inputs are parameters or parameter fields only; no clause indexes a
vector, reads a vector element, compares a `Str` (length via `.len()` only),
uses a module constant (the message-id bound appears as the literal
2147483647), or reads a `&mut` parameter. Guards keep the plan's families:
tag guard pairs (`result is Ok` / `result is Err`), sentinel/out-of-range
guards (`off < 0`, `data.len() - off < 2`, `len < 0`, `message_id < 0`),
exact length formulas (`result.len() == 3`, `result.len() ==
content.len() + 2`, `result.len() == len`) and bounds (`result >= 0 &&
result <= 120`). The one cross-call is `ldap_op_tag_known(tag) == false =>
result.len() == 7` in `ldap_op_tag_name`; it is definitional and
non-re-entrant (`ldap_op_tag_known` never calls `ldap_op_tag_name`). Two
planned skips were kept: `ber_bool_decode` (its guarantee would need a
struct-Result payload field read) and `_partial_attr_parse` (five `&mut`
out-parameters; no readable post-state).

| Function | Clauses | Guarantee (abridged) | Z3-provable | Runtime-checked |
|---|---|---|---|---|
| `ber_length_decode` | 3 | negative or out-of-range `off` => `Err`; `Ok` implies `off` in range | no | yes |
| `ber_tlv_decode` | 4 | negative/out-of-range `off` or under 2 bytes => `Err`; `Ok` implies `off >= 0` and >= 2 bytes available | no | yes |
| `ber_octet_string_decode` | 3 | under 2 bytes from `off` => `Err`; `Ok` implies `off >= 0` and >= 2 bytes available | no | yes |
| `ber_sequence_decode` | 2 | negative `off` or under 2 bytes => `Err` | no | yes |
| `ber_length_encode` | 3 | `len < 0` => empty; `len < 128` => 1 byte; 128..255 => 2 bytes | no | yes |
| `ber_bool_encode` | 1 | always exactly 3 bytes | no | yes |
| `ber_tlv_wrap` | 2 | content < 128 bytes => `len + 2`; 128..255 => `len + 3` | no | yes |
| `ldap_bytes_copy` | 4 | out-of-range request => empty; in-range request => exactly `len` bytes | no | yes |
| `ldap_op_tag_known` | 2 | outside 66..120 => `false`; `true` implies 66..120 | no | yes |
| `ldap_op_tag_name` | 2 | unknown tag => name length 7; tag 99 => length 13 | no | yes |
| `ldap_message_parse` | 2 | input under 2 bytes => `Err`; `Ok` implies >= 2 bytes | no | yes |
| `ldap_message_encode` | 4 | negative/too-large id or empty op => `Err`; `Ok` implies id 0..2147483647 and non-empty op | no | yes |
| `ldap_abandon_request_parse` | 3 | negative `off` or under 2 bytes => `Err`; `Ok` implies non-negative id | no | yes |
| `ldap_bind_request_encode` | 2 | version outside 1..127 => `Err`; `Ok` implies version 1..127 | no | yes |
| `ldap_search_request_encode` | 4 | bad scope/deref or negative limits => `Err`; `Ok` implies all four in range | no | yes |
