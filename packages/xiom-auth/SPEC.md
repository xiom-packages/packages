# xiom.auth -- Specification (as implemented)

This document specifies exactly what `src/auth.xi` does. It is written from
the implementation, not from the RFCs: where the code is stricter or more
relaxed than the ABNF, that is called out explicitly (section 11).

Baseline: XIOM compiler v0.61.3, package `xiom.auth` 0.1.0.

## 1. Scope

HTTP authentication header codecs for the field values of `Authorization`,
`Proxy-Authorization`, `WWW-Authenticate` and `Proxy-Authenticate`:

* RFC 7235 generic grammar: scheme + (token68 | auth-param list);
* Basic (RFC 7617);
* Digest (RFC 7616) challenge and response structures, including the
  extended `username*` / `realm*` / `nonce*` forms;
* Bearer (RFC 6750) credentials, challenge parameters and error codes.

All parsing functions are total (they return `Result[...]`, never crash on
malformed input) and report byte offsets for every error. Every parsed
element carries byte spans so the original text can be recovered.

## 2. Non-goals

No cryptography, no credential verification, no token issuance/validation,
no sessions, no I/O, no policy. In particular the module never computes the
Digest response hash; it validates the response structure and the
challenge/response consistency only.

## 3. Grammar implemented

```
authorization      = auth-scheme [ 1*OWS credentials ]
challenge          = auth-scheme [ 1*OWS credentials ]
www-authenticate   = 1#challenge            ; strict, see section 5
credentials        = token68 / #auth-param
auth-param         = token BWS "=" BWS param-value
param-value        = token / quoted-string / relaxed-raw
quoted-string      = DQUOTE *( qdtext / quoted-pair ) DQUOTE
quoted-pair        = "\" ( HTAB / SP / VCHAR / obs-text ) ; CR, LF, NUL rejected
token68            = 1*( ALPHA / DIGIT / "-" / "." / "_" / "~" / "+" / "/" ) *"="
auth-scheme        = token
token / tchar      = RFC 7230 section 3.2.6
OWS                = *( SP / HTAB )
BWS                = OWS
```

`relaxed-raw` is a documented extension: a parameter value that begins as a
token but continues with bytes outside the token set (for example
`Credential=AKIDEXAMPLE/20130524/...` in AWS4-HMAC-SHA256) is captured up to
the next comma or whitespace and reported with kind 2. See section 11.

## 4. Data model and byte spans

All offsets are byte offsets into the string passed to the parser (XIOM
`Str` indexing is byte-based).

`AuthHeader` (one parsed header item):

| field | meaning |
|-------|---------|
| `scheme`, `scheme_off` | scheme token and its offset |
| `start`, `end` | parsed region (`start` = scheme offset, `end` = one past the last consumed byte) |
| `uses_token68` | 1 for token68 credentials, 0 for auth-params |
| `token68`, `token68_off` | token68 text and offset (`""` / -1 when absent) |
| `cred_off`, `cred_end` | credentials region (-1 when scheme-only) |
| `pname`, `pvalue`, `pkind`, `poff`, `pvstart`, `pvend` | parallel per-parameter vectors: name, decoded value, kind (0 token, 1 quoted-string, 2 relaxed raw), name offset, raw value start, raw value end (quotes included for quoted-strings) |

`AuthChallenges` (a `WWW-Authenticate` list) flattens challenges:
per-challenge `scheme`, `start`, `end`, `uses_token68`, `token68`, `pbase`,
`pcount`; the parameter vectors are shared and challenge i owns slots
`[pbase[i], pbase[i] + pcount[i])`.

Accessors (`auth_header_*`, `auth_challenge_*`) validate nothing and are
documented for valid indices. `auth_header_consumed` = `end - start`.
`auth_header_param_get` / `auth_challenge_param_get` look names up
case-insensitively and return `Err("auth: parameter not found: <name>")`
when absent. `auth_header_slice`, `auth_header_cred_slice` and
`auth_challenge_slice` return raw text.

## 5. Credentials-form decision and challenge boundaries

**token68 vs auth-param** (after the scheme and 1*OWS): when the first
credential byte can start a token68, the parser scans the maximal token68
run and then the `=` padding run:

* padding present and followed by end, comma or OWS -> token68 (padding is
  part of it);
* padding present and followed by other material (`abc=def`) -> auth-param
  list;
* no padding, run followed by end/comma -> token68;
* no padding, run followed by OWS: the OWS is skipped; a following `=` means
  auth-param (`name = value`, BWS before `=`); otherwise token68.

Otherwise (first byte is a token character that cannot start a token68, or
cannot start a token at all) the credentials are parsed as an auth-param
list, whose errors are reported with offsets.

**Challenge boundary rule** (`auth_parse_www_authenticate`, RFC 7235
section 2.1). At a comma inside a parameter list the parser peeks past the
comma: it skips OWS, requires a non-empty token `T` (the candidate scheme),
then requires `T` to be followed by 1*SP. After the spaces:

* end of input -> new challenge (scheme-only, e.g. `Negotiate, NTLM`);
* `=` -> **not** a new challenge (`stale = true` stays a parameter);
* a token68 start or a token start -> new challenge;
* anything else -> not a new challenge (the parameter parser then reports
  the syntax error).

A challenge ends at the comma that starts the next challenge; the comma
itself is consumed by the list parser. The list parser is strict: `#rule`
empty elements (leading/trailing/double commas) are rejected.

`auth_parse_authorization` applies the same item parser but requires the
whole value to be consumed (trailing OWS allowed); a boundary comma inside
an Authorization value therefore ends the item and the remainder is
reported as `unexpected trailing characters`.

`auth_parse_header_at(value, off)` is the parse-one primitive: it parses a
single item from `off` and reports `consumed = end - start`; the caller
decides what to do with the rest. `off < 0` or `off > len` is an error.

## 6. Basic (RFC 7617)

* `auth_basic_encode(user, password) -> Ok("Basic " + base64(user ":" password))`
  with standard base64 and `=` padding. Rejects `:` in the user-id and CTL
  bytes (0x00-0x1F, 0x7F) in either part; the password may contain colons.
* `auth_basic_decode(encoded) -> BasicCredentials` takes the token68 payload
  only (no scheme), base64-decodes it, splits at the FIRST colon and decodes
  the two parts into `user` / `password`. A missing colon is an error; later
  colons are part of the password. CTL bytes are rejected (a decoded 0x00
  can never reach a `Str`). The first-colon split makes a colon in the
  decoded user-id impossible by construction.
* `auth_basic_decode_strict` adds the extra rule that the password contains
  no colon.
* `auth_basic_parse(value)` parses a complete `Basic ...` header value and
  requires token68 credentials (`Basic realm="x"` is an error).
* Charset: the only registered value is `UTF-8` (case-insensitive) and it is
  the default. `auth_basic_charset(h)` returns the `charset` parameter value
  or `"UTF-8"`; `auth_basic_charset_ok(h)` accepts absent or
  case-insensitive `UTF-8`. Bytes are copied verbatim; UTF-8 validation of
  decoded credentials is the caller's concern.
* `auth_basic_user_is_valid` / `auth_basic_password_is_valid` expose the
  encode-side predicates.

## 7. Digest (RFC 7616)

**Algorithm table** (case-insensitive; canonical spellings): `MD5`,
`MD5-sess`, `SHA-256`, `SHA-256-sess`, `SHA-512-256`, `SHA-512-256-sess`.
`auth_digest_algorithm_canonical` returns the canonical spelling or `""`;
`auth_digest_algorithm_is_sess` identifies the `-sess` variants;
`auth_digest_response_hex_len` is 32 for MD5/MD5-sess and 64 for the
SHA-256/SHA-512-256 variants, 0 for unknown names. The default algorithm is
`MD5`.

**qop**: offered values are parsed as a comma-separated token list with OWS
trimming; empty tokens and non-token characters are errors.
`auth_digest_qop_is_valid` accepts `auth` and `auth-int`.
`auth_digest_qop_offered` tests membership (case-insensitive);
`auth_digest_pick_qop(challenge, preferred)` implements the pick-one rule:
the first preferred token that the offer includes is returned in the
caller's spelling.

**Challenge** (`auth_digest_parse_challenge`): requires realm and nonce
(non-empty); canonicalizes `algorithm` (unknown -> error); tokenizes `qop`;
`opaque` kept as-is; `stale` / `userhash` accept case-insensitive
`true`/`false`; `domain` is a space-separated list of non-empty elements;
`charset` must be `UTF-8`. Unknown parameters are ignored (still reachable
through the generic header accessors).

`auth_digest_challenge_build` renders in this order: realm, nonce,
algorithm (token), qop (quoted comma list), opaque, `stale=true`, domain
(quoted space list), `userhash=true`, `charset=UTF-8`; `"` and `\` inside
quoted values are escaped. Empty realm/nonce, unknown algorithms, invalid
qop tokens, empty/space-containing domain elements and non-UTF-8 charsets
are errors.

**Response** (`auth_digest_parse_response`): accepts `username`/`username*`,
`realm`/`realm*`, `nonce`/`nonce*`; supplying both forms of one name is an
error; extended forms are stored raw with the matching `*_star` flag and can
be decoded with `auth_digest_ext_decode` (`UTF-8''` percent-encoded values,
case-insensitive hex; other charsets and NUL are rejected). `uri` and
`response` are required; `algorithm` is canonicalized; `qop` must be a
single token; `nc`, `cnonce`, `opaque`, `userhash` are optional here.

**Structural check** (`auth_digest_response_check`): username, realm, nonce,
uri and response present; response length matches the algorithm's hex length
and is hex; `nc` is exactly 8 hex digits when present; `qop` (when present)
is `auth`/`auth-int` and requires both `nc` and `cnonce`.

**Challenge/response validation** (`auth_digest_validate_response`):
structural check first, then realm and nonce must match the challenge (when
both sides carry them), the algorithms must match (absent means `MD5` on
both sides), `qop` is required when the challenge offered one and must be
one of the offered tokens, `qop` must be absent when the challenge offered
none, and `userhash` must be sent exactly when the challenge offered it.

## 8. Bearer (RFC 6750)

* `auth_bearer_token_check(token)` validates token68 shape;
  `auth_bearer_authorization(token) -> Ok("Bearer " + token)`.
* `auth_bearer_token(value)` parses a full `Bearer ...` header value and
  returns the token68; params form (`Bearer realm="x"`) is an error.
* `auth_bearer_error_is_valid` accepts exactly `invalid_request`,
  `invalid_token`, `insufficient_scope` (case-sensitive).
* `auth_bearer_parse_challenge` reads `realm`, `scope` (single-space
  separated tokens, each 0x21-0x7E except `"` and `\`), `error` (validated),
  `error_description` and `error_uri` (both require `error` to be present).
* `auth_bearer_challenge_build` renders `Bearer` followed by the present
  parameters in the order realm, scope, error, error_description,
  error_uri; values are quoted when they are not single tokens.

## 9. Test coverage map

`tests/test_conformance.xi` (24 checks; each maps to one `fn tN`):

| Check | Covers |
|-------|--------|
| t1 | Basic encode: 0, 1 and 2 base64 padding variants |
| t2 | Basic decode round-trips of those variants |
| t3 | Basic colon rules: missing colon, colon in user-id, colon in password (tolerant + strict), CTL |
| t4 | Basic full-header parse, scheme case-insensitivity, token68 requirement |
| t5 | Basic charset: default, quoted, case-insensitive, other value rejected |
| t6 | Generic grammar: token68 header, digest params, spans, case-insensitive lookup, trailing-garbage error |
| t7 | Quoted-string `\"` and `\\` decoding plus malformed forms (unterminated, truncated pair, raw LF) |
| t8 | Parameter error offsets, token68/param disambiguation (`abc=def`, `abc==`, `abc=`, BWS, lone token) |
| t9 | RFC 7235 multi-challenge example: two challenges, parameter merging, slices, pick |
| t10 | Boundary rule: `stale = true` stays a parameter, token68 followed by a challenge, scheme-only challenges, strict list errors |
| t11 | Digest challenge: full RFC-style form, spaces in qop, minimal form, unknown algorithm, missing realm/nonce, bad stale, empty qop, wrong scheme |
| t12 | Algorithm table: six names, canonical spellings, sess flag, hex lengths, qop tokens |
| t13 | qop offer parsing, pick-one rule, empty-token error |
| t14 | Digest challenge build: exact output, quoting escapes, full round-trip, error cases |
| t15 | Digest response: RFC-style example, `username*` extended form + decode, both-forms error, missing uri, qop list error |
| t16 | Digest response check: required fields, nc shape, qop/nc/cnonce coupling, hex/length |
| t17 | Challenge/response validation: realm, nonce, algorithm, qop offered/required/absent, userhash both ways |
| t18 | Bearer credentials: token68 parse/build, errors |
| t19 | Bearer challenge parse: realm-only, error triple, scope split, unknown error, description without error, double-space scope, wrong scheme |
| t20 | Bearer challenge build: exact output, round-trip, build-side errors |
| t21 | Other schemes preserved: `Negotiate` token68 raw, AWS4-HMAC-SHA256 relaxed raw params, raw slices |
| t22 | Parse-one header: consumed counts at offsets, offset errors, scheme-only |
| t23 | Case-insensitive parameter lookup and value kinds (token/quoted/raw) |
| t24 | Consumed counts excluding leading/trailing OWS |

## 10. Error catalog

All offsets are byte offsets; for decoded-field checks (Basic parts, Bearer
scope, Digest qop/domain/ext-value) the offset is relative to the decoded
value, and this is noted per function.

Generic parser (shared by Authorization and challenge lists):

| Message |
|---------|
| `auth: start offset out of range at offset N` |
| `auth: expected auth-scheme at offset N` |
| `auth: expected parameter name at offset N` |
| `auth: expected '=' after parameter name at offset N` |
| `auth: expected parameter value at offset N` |
| `auth: invalid character in quoted-string at offset N` |
| `auth: truncated quoted-pair at offset N` |
| `auth: invalid quoted-pair escape at offset N` |
| `auth: unterminated quoted-string at offset N` |
| `auth: expected ',' between parameters at offset N` |
| `auth: unexpected trailing characters at offset N` |
| `auth: expected ',' between challenges at offset N` |
| `auth: expected challenge after ',' at offset N` |
| `auth: expected challenge at offset N` (empty WWW-Authenticate value) |
| `auth: parameter not found: <name>` |

Basic:

| Message |
|---------|
| `auth: basic invalid base64` |
| `auth: basic credentials missing colon separator` |
| `auth: basic user-id contains ':' at offset N` (encode side) |
| `auth: basic user-id contains control character at offset N` |
| `auth: basic password contains control character at offset N` |
| `auth: basic password contains ':' (strict) at offset N` |
| `auth: authorization scheme is not Basic` |
| `auth: Basic credentials must be a token68` |

Digest:

| Message |
|---------|
| `auth: challenge scheme is not Digest` |
| `auth: authorization scheme is not Digest` |
| `auth: digest challenge missing realm` |
| `auth: digest challenge missing nonce` |
| `auth: digest challenge realm is empty` (build) |
| `auth: digest challenge nonce is empty` (build) |
| `auth: digest unknown algorithm: X` |
| `auth: digest invalid stale value: X` |
| `auth: digest invalid userhash value: X` |
| `auth: digest unsupported charset: X` |
| `auth: digest qop list is empty` |
| `auth: digest qop token is empty at offset N` |
| `auth: digest qop token has invalid character at offset N` |
| `auth: digest qop token has invalid character` (build) |
| `auth: digest challenge offers no qop` |
| `auth: digest no preferred qop is offered` |
| `auth: digest domain list is empty` |
| `auth: digest domain has empty element at offset N` |
| `auth: digest domain element is empty or contains a space` (build) |
| `auth: digest response has both <name> and <name>*` |
| `auth: digest response missing username` / `... realm` / `... nonce` / `... uri` / `... response digest` |
| `auth: digest response qop must be a single token` |
| `auth: digest response digest length mismatch` |
| `auth: digest response digest is not hexadecimal` |
| `auth: digest nc must be 8 hex digits` |
| `auth: digest nc required with qop` |
| `auth: digest cnonce required with qop` |
| `auth: digest unknown qop: X` |
| `auth: digest response realm mismatch` |
| `auth: digest response nonce mismatch` |
| `auth: digest algorithm mismatch` |
| `auth: digest challenge unknown algorithm: X` |
| `auth: digest response unknown algorithm: X` |
| `auth: digest qop required: challenge offered qop` |
| `auth: digest qop not offered: X` |
| `auth: digest qop sent but challenge offered none` |
| `auth: digest userhash required` |
| `auth: digest userhash not offered` |
| `auth: digest ext-value missing charset separator` |
| `auth: digest ext-value charset is not UTF-8: X` |
| `auth: digest ext-value missing language separator` |
| `auth: digest ext-value invalid percent escape at offset N` |
| `auth: digest ext-value percent escape decodes to NUL at offset N` |

Bearer:

| Message |
|---------|
| `auth: challenge scheme is not Bearer` |
| `auth: authorization scheme is not Bearer` |
| `auth: Bearer credentials must be a token68` |
| `auth: bearer token is empty` |
| `auth: bearer token is not a token68` |
| `auth: bearer token has invalid character at offset N` |
| `auth: bearer unknown error code: X` |
| `auth: bearer error_description without error` |
| `auth: bearer error_uri without error` |
| `auth: bearer scope list is empty` |
| `auth: bearer scope has empty element at offset N` |
| `auth: bearer scope token has invalid character at offset N` (offsets into the decoded scope value) |
| `auth: bearer scope token is empty or contains a space` (build) |

## 11. Known limitations and documented relaxations

1. **No crypto.** Digest response hashes are never computed or compared;
   `auth_digest_validate_response` is a structural/consistency check.
2. **Relaxed raw parameter values.** RFC 7235 allows only token or
   quoted-string values. To preserve deployed schemes such as
   AWS4-HMAC-SHA256 (`Credential=.../...`), a token-like value that
   continues with non-token bytes up to the next comma or whitespace is
   accepted and reported with kind 2. Strict callers can reject kind 2 via
   `auth_header_param_kind` / `auth_challenge_param_kind`.
3. **Strict challenge lists.** Empty list elements (leading, trailing or
   doubled commas) are rejected although RFC 7230 section 7 suggests
   recipients ignore a reasonable number of them.
4. **No obs-fold.** CR, LF and NUL are rejected everywhere (the quoted-string
   reader, the raw value reader and qdtext all stop at them).
5. **Authorization is a single item.** A value that looks like it carries
   multiple comma-separated challenges is rejected with `unexpected
   trailing characters`; use `auth_parse_www_authenticate` for lists.
6. **Extended forms are stored raw.** `username*`/`realm*`/`nonce*` values
   keep their `UTF-8''...` text; decode explicitly with
   `auth_digest_ext_decode`. Other charsets are rejected only by the decode
   helper, not by the parser.
7. **Basic is byte-transparent.** No UTF-8 validation is performed on
   decoded credentials; the charset note is exposed through
   `auth_basic_charset` / `auth_basic_charset_ok`.
8. **Bearer error codes are case-sensitive** (they are exact registered
   tokens); scheme and parameter names are compared case-insensitively.
9. **Empty credentials are allowed** where the grammar allows them: an empty
   user-id (`:pass`), an empty password (`user:`) and empty tokens in
   `auth_basic_encode`.
