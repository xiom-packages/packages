# xiom.saml -- Specification

This document is the contract for `xiom.saml` 0.1.0. It covers the XML
subset, the parser limits, the decoded models, the helper semantics, the
error catalog and the explicit non-goals. The conformance suite
(`tests/test_conformance.xi`, 28 checks) pins the behavior described here.

## 1. Scope

`xiom.saml` is a pure-XIOM structure toolkit for SAML 2.0 payloads. It
transforms text/bytes into decoded models and back, using only `xiom.std`.
It performs **no network I/O**, **no public-key cryptography**, **no
decryption** and **no trust decisions**.

## 2. The XML subset reader

`saml_xml_parse(text: Str) -> Result[XmlDoc, Str]` accepts:

* elements `<name ...>`, `</name>` and self-closing `<name/>`; names may
  contain namespace prefixes (`saml:Issuer`); end tags must match the open
  element byte-for-byte;
* attributes with double or single quotes; entity references are decoded
  inside values; duplicate attribute names are rejected (first error wins);
* character data with `&amp;` `&lt;` `&gt;` `&quot;` `&apos;`, decimal
  `&#NN;` and hexadecimal `&#xHH;` references; a numeric reference to U+0000
  or to a surrogate or a value above U+10FFFF is rejected;
* comments `<!-- ... -->`, processing instructions `<? ... ?>` and CDATA
  sections `<![CDATA[ ... ]]>`; comments and PIs are skipped, CDATA is copied
  verbatim as text;
* an optional XML declaration (a processing instruction);
* whitespace-only text outside the root element.

Rejected: a DOCTYPE or any other `<!...>` declaration, multiple root
elements, non-whitespace text outside the root, unclosed constructs,
mismatched end tags.

### 2.1 Limits

| Limit | Value |
|---|---|
| Document size | 1 MiB (`1048576`) |
| Nesting depth | 64 |
| Nodes (elements + text runs) | 16384 |
| Attributes per element | 256 |

### 2.2 The flat document model

`XmlDoc` carries parallel vectors; node 0 is a synthetic root element
(`parents[0] == -1`):

* `kinds[i]` -- 0 element, 1 text;
* `names[i]` -- element tag name (full qualified name); `""` for text;
* `texts[i]` -- decoded text of a text node; `""` for elements;
* `parents[i]` -- owning node index;
* `opens[i]`, `closes[i]` -- source byte span `[opens, closes)` of node i
  (start tag through end tag for elements, the raw run for text);
* `attr_names[k]`, `attr_values[k]`, `attr_owners[k]` -- flat attribute
  association list;
* `src` -- the whole document bytes.

Accessors: `saml_xml_root`, `saml_xml_node_count`, `saml_xml_node_kind`,
`saml_xml_node_name`, `saml_xml_node_local` (local name after the first `:`),
`saml_xml_node_parent`, `saml_xml_node_depth`, `saml_xml_text`,
`saml_xml_child_count`, `saml_xml_child`, `saml_xml_child_by_name`,
`saml_xml_descendant_by_name`, `saml_xml_attr_count`,
`saml_xml_attr_name_at`, `saml_xml_attr_value_at`, `saml_xml_attr`,
`saml_xml_attr_or`, `saml_xml_node_open`, `saml_xml_node_close`,
`saml_xml_node_raw_bytes`, `saml_xml_escape`.

`saml_xml_text` concatenates only *direct* text children of a node. Element
children are queried by local name.

## 3. Base64 and the POST binding

`saml_base64_encode` emits the standard RFC 4648 alphabet with `=` padding
(`""` for empty input).

`saml_base64_decode` skips space/TAB/CR/LF, accepts padded and unpadded
input (significant length 0, 2 or 3 mod 4), and rejects:

* a significant length of 1 mod 4 -- `saml: base64 invalid length at offset N`;
* a non-alphabet byte -- `saml: base64 invalid character at offset N`;
* `=` anywhere except a run at the very end -- `saml: base64 misplaced
  padding at offset N`;
* non-zero unused trailing bits -- `saml: base64 non-canonical trailing bits
  at offset N`.

Offsets are positions in the input string, whitespace included.

`saml_post_binding_encode(xml)` is base64 of the UTF-8 bytes;
`saml_post_binding_decode(payload)` inverts it and refuses decoded bytes
containing 0x00 (`saml: post binding payload contains NUL`), because a NUL
cannot live in a `Str` (see section 7).

## 4. SHA-256

`saml_sha256(data)` implements FIPS 180-4 with 32-bit masking and integer
arithmetic only (no floats); `saml_sha256_str(s)` hashes a `Str`'s UTF-8
bytes; `saml_sha256_hex(data)` renders 64 lowercase hex characters.
Known-answer vectors for `""`, `"abc"`, the 56-byte SHA-256 sample and the
quick-brown-fox sentence are pinned in the tests.

## 5. xs:dateTime

`saml_parse_datetime(s)` accepts
`YYYY-MM-DDThh:mm:ss[.fff](Z|(+|-)hh:mm)` (case-insensitive `t`/`z`),
requires a timezone, accepts 1+ fractional digits (truncated), and returns
integer epoch seconds UTC. Rejected with `saml: invalid datetime`: year 0,
month outside 1..12, day outside the month (leap years per Gregorian rules),
hour above 23, minute/second above 59 (leap seconds rejected), an offset
above 14:00, a missing/garbled separator or timezone, and trailing bytes.
`saml_format_datetime(epoch)` renders `YYYY-MM-DDThh:mm:ssZ` and is exact for
years 0..9999.

## 6. SAML models

### 6.1 Assertion

`saml_assertion_parse(text)` / `saml_assertion_from_doc(doc, node)` require
the root to be an `Assertion` with `Version="2.0"`, a non-empty `ID` and a
parseable `IssueInstant`. They decode:

* `Issuer` text;
* `Subject` -> `NameID` text and `Format`, the number of
  `SubjectConfirmation` children, and `Recipient`/`InResponseTo` of the first
  `SubjectConfirmationData`;
* `Conditions` -> `NotBefore` / `NotOnOrAfter` (epochs) and the flattened
  `Audience` texts; a present but malformed timestamp is an error;
* `AuthnStatement` -> `AuthnInstant` (validated) and `SessionIndex`;
* every `AttributeStatement`/`Attribute` -> parallel name/format/friendly/
  count vectors plus the flat `values` / `value_owners` pair; an `Attribute`
  without `Name` is an error;
* the first `Signature` child -> `has_signature` / `signature_node`.

Helpers: `saml_assertion_valid_at(a, now)`, `saml_assertion_valid_skew(a,
now, skew)` (rejects a negative skew; `now + skew < NotBefore` is
"not yet valid", `now - skew >= NotOnOrAfter` is "expired"),
`saml_assertion_audience_matches` (true when no restriction),
`saml_assertion_attribute_value_count`, `saml_assertion_attribute_values`
(first attribute with that name), `saml_assertion_has_signature`,
`saml_assertion_signature`.

### 6.2 Response

`saml_response_parse(text)` / `saml_response_from_doc` require
`Version="2.0"`, a non-empty `ID` and a parseable `IssueInstant`; they decode
`Destination`, `InResponseTo`, `Issuer`, `Status` (`StatusCode/@Value` plus
`StatusMessage`; a `Status` without `StatusCode` is an error), direct
`Assertion` / `EncryptedAssertion` counts and the first `Signature` child.
`saml_response_is_success` compares the status code to the registered
`Success` URN; `saml_status_is_valid` accepts any
`urn:oasis:names:tc:SAML:2.0:status:`-prefixed non-empty code.

### 6.3 AuthnRequest

`saml_authn_request_build(id, issuer, destination, acs_url, issue_instant)`
emits a deterministic `samlp:AuthnRequest` document with `ID`, `Version`,
`IssueInstant` and optional `Destination` /
`AssertionConsumerServiceURL`, plus a `saml:Issuer` child; values are
XML-escaped. It rejects an empty id/issuer and a malformed IssueInstant.
`saml_authn_request_parse` round-trips the fields.

### 6.4 IdP metadata

`saml_idp_metadata_parse(text)` requires an `EntityDescriptor` root with a
non-empty `entityID` and an `IDPSSODescriptor` child carrying at least one
`SingleSignOnService` with non-empty `Binding` and `Location`. It records
`protocolSupportEnumeration`, `WantAuthnRequestsSigned` (`true`/`1`), every
SSO binding/location pair in order, and every `X509Certificate` descendant
normalized by stripping base64 whitespace. Accessors:
`saml_metadata_sso_count`, `saml_metadata_sso_binding_at`,
`saml_metadata_sso_location_at`,
`saml_metadata_sso_location_for_binding`, `saml_metadata_certificate_at`.

## 7. XML-DSig structure and digests

`saml_dsig_parse(doc, node)` requires a `Signature` element with
`SignedInfo` (containing `CanonicalizationMethod` and `SignatureMethod` with
non-empty `Algorithm`), at least one `Reference` (each with `DigestMethod`
and `DigestValue`; the URI defaults to `""`) and a `SignatureValue`.
References are flattened into parallel `ref_uri` / `ref_digest_algorithm` /
`ref_digest_value` vectors.

`saml_dsig_reference_target(doc, sig, i)` resolves `URI=""` to the document
root, `URI="#id"` to the first element whose `ID`, `Id` or `xml:id` equals
id, and rejects any other URI. `saml_dsig_digest_bytes` decodes the digest
and checks its length (20/32/64 for SHA-1/SHA-256/SHA-512);
`saml_dsig_signature_value_bytes` decodes the signature octets.

Digest verification (SHA-256 only, because that is the hash implemented
in-package):

* `saml_dsig_verify_digest_sha256(digest_b64, octets)` -- caller owns the
  canonicalization and passes the exact octets;
* `saml_dsig_verify_reference_sha256(sig, i, octets)` -- as above for
  reference i;
* `saml_dsig_verify_reference_raw_sha256(doc, sig, i)` -- hashes the raw
  source span of the resolved element.

**Canonicalization caveat.** XML-DSig defines DigestValue over the octets
produced by the declared transform (for SAML usually Exclusive C14N), not
over the raw source span. The `..._raw_...` helper is exact only when the raw
span already equals the canonical octets (no comments/PIs inside the
element, attributes in canonical order, no adjacent text-node splits). Use
`..._reference_sha256` with caller-produced canonical octets for anything
stronger.

**Non-goal.** Public-key verification of `SignatureValue` (RSA/ECDSA),
transform execution and `EncryptedAssertion` decryption are out of scope.
The structural checks here establish shape, not trust.

## 8. Non-goals

Networking and HTTP-Redirect deflate encoding; XML Encryption; RSA/ECDSA
signature verification; exclusive C14N implementation; full XML validity
(namespaces are not resolved, only local names are compared); SAML protocol
state machines, artifact resolution, metadata signatures; JSON; clock access
(the caller supplies `now`).

## 9. Error catalog

XML errors are `saml: <what> at offset N` (the offset is the current scan
position when the error is recorded):

```
saml: document too large          saml: no root element
saml: stray '<'                   saml: text outside root element
saml: unsupported markup declaration
saml: unclosed tag                saml: unclosed element
saml: malformed tag               saml: malformed attribute
saml: unclosed attribute value    saml: duplicate attribute
saml: too many attributes         saml: too many nodes
saml: nesting too deep            saml: multiple root elements
saml: unexpected closing tag      saml: mismatched closing tag
saml: unclosed comment            saml: unclosed CDATA section
saml: unclosed processing instruction
saml: unterminated entity         saml: invalid character reference
```

Attribute lookup: `saml: attribute not found: <name>`, `saml: node index out
of range`. Base64: section 3. Datetime: `saml: invalid datetime`. Assertions:
`saml: not an Assertion element`, `saml: missing Version`,
`saml: unsupported Version`, `saml: missing ID`, `saml: empty ID`,
`saml: missing IssueInstant`, `saml: invalid IssueInstant`,
`saml: invalid NotBefore`, `saml: invalid NotOnOrAfter`,
`saml: invalid AuthnInstant`, `saml: Attribute missing Name`,
`saml: assertion not yet valid`, `saml: assertion expired`,
`saml: negative clock skew`. Responses: `saml: not a Response element`,
`saml: Status without StatusCode`, `saml: StatusCode without Value`,
`saml: assertion index out of range`. Metadata: `saml: not an
EntityDescriptor element`, `saml: missing entityID`, `saml: empty entityID`,
`saml: missing IDPSSODescriptor`, `saml: IDPSSODescriptor without
SingleSignOnService`, `saml: SingleSignOnService without Binding`,
`saml: SingleSignOnService without Location`, `saml: empty
SingleSignOnService Binding/Location`. DSig: `saml: not a Signature element`,
`saml: missing SignedInfo`, `saml: missing CanonicalizationMethod`,
`saml: empty CanonicalizationMethod Algorithm`, `saml: missing
SignatureMethod`, `saml: empty SignatureMethod Algorithm`,
`saml: Reference without DigestMethod`, `saml: empty DigestMethod
Algorithm`, `saml: Reference without DigestValue`, `saml: no Reference`,
`saml: missing SignatureValue`, `saml: unsupported digest algorithm`,
`saml: digest value length mismatch`, `saml: empty signature value`.

## 10. Implementation notes and stdlib gaps

* The compiler (v0.62.2) has no `Vec[StructType]`, so every collection is a
  set of parallel vectors; pushes are mirrored in lockstep and readers guard
  mismatched lengths.
* `Str` equality always goes through `xiom.string.compare.str_compare`
  (BUG 17); bytes read from `Vec[UInt8]` are widened with `(x as Int) &
  0xFF`.
* `Ok`/`Err` for struct payloads are constructed only in leaf helpers
  (`_ok_doc`, `_ok_assertion`, ...).
* Base64 was hand-rolled in-package as briefed. The local stdlib actually
  ships `xiom.encoding.base64` (plus the deprecated `xiom.convert.base64`
  shim); the in-package copy keeps this package dependency-free and pinned to
  its own strict error catalog. If stdlib base64 stabilizes, the internal
  functions can delegate without changing the public API.
* SHA-256 was likewise hand-rolled; the local stdlib has
  `xiom.crypto.hash.crypto_hash_sha256`, deliberately not used so the
  digest implementation is pinned in-package.
* There is no generic `Vec` structural equality helper in the stdlib; the
  package compares byte vectors with a local loop.
