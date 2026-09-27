# xiom.oauth -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.oauth` (`src/oauth.xi`). Pure XIOM, no FFI.
Manifest: `package.xi` (deps: `xiom.std >=0.60.0 <1.0.0`).

## 1. Scope

An OAuth 2.0 (RFC 6749) / PKCE (RFC 7636) request-and-response **structure**
codec. It builds and parses the form-encoded and JSON payloads of an OAuth
exchange; it performs no network I/O, no JWT work and no hashing.

```xi
// form / params
pub fn oauth_form_encode(s: Str) -> Str
pub fn oauth_form_decode(s: Str) -> Result[Str, Str]
pub fn oauth_params_new() -> OAuthParams
pub fn oauth_params_add(p: &mut OAuthParams, name: Str, value: Str)
pub fn oauth_params_count(p: &OAuthParams) -> Int
pub fn oauth_params_name_at(p: &OAuthParams, i: Int) -> Str
pub fn oauth_params_value_at(p: &OAuthParams, i: Int) -> Str
pub fn oauth_params_has(p: &OAuthParams, name: Str) -> Bool
pub fn oauth_params_get(p: &OAuthParams, name: Str) -> Result[Str, Str]
pub fn oauth_params_encode(p: &OAuthParams) -> Str
pub fn oauth_params_parse(query: Str) -> Result[OAuthParams, Str]

// authorization request / response
pub fn oauth_authz_request(response_type: Str, client_id: Str, redirect_uri: Str,
                           scope: &Vec[Str], state: Str,
                           code_challenge: Str, code_challenge_method: Str) -> Result[AuthzRequest, Str]
pub fn oauth_authz_request_add_extra(req: &mut AuthzRequest, name: Str, value: Str) -> Result[Str, Str]
pub fn oauth_authz_request_encode(req: &AuthzRequest) -> Result[Str, Str]
pub fn oauth_authz_request_parse(query: Str) -> Result[AuthzRequest, Str]
pub fn oauth_authz_response_parse(query: Str) -> Result[AuthzResponse, Str]

// token request / response
pub fn oauth_token_request(grant_type: Str, code: Str, redirect_uri: Str,
                           refresh_token: Str, scope: &Vec[Str],
                           client_id: Str, client_secret: Str) -> Result[TokenRequest, Str]
pub fn oauth_token_request_add_extra(req: &mut TokenRequest, name: Str, value: Str) -> Result[Str, Str]
pub fn oauth_token_request_encode(req: &TokenRequest) -> Result[Str, Str]
pub fn oauth_token_request_parse(body: Str) -> Result[TokenRequest, Str]
pub fn oauth_token_response_parse(json: Str) -> Result[TokenResponse, Str]
pub fn oauth_json_has(text: &Vec[UInt8], key: Str) -> Bool
pub fn oauth_json_span(text: &Vec[UInt8], key: Str) -> Result[(Int, Int), Str]
pub fn oauth_json_str(text: &Vec[UInt8], key: Str) -> Result[Str, Str]
pub fn oauth_json_int(text: &Vec[UInt8], key: Str) -> Result[Int, Str]
pub fn oauth_max_json_bytes() -> Int

// PKCE and predicates
pub fn oauth_pkce_verifier_min() -> Int
pub fn oauth_pkce_verifier_max() -> Int
pub fn oauth_pkce_s256_hash_len() -> Int
pub fn oauth_pkce_verifier_is_valid(v: Str) -> Bool
pub fn oauth_pkce_verifier_check(v: Str) -> Result[Str, Str]
pub fn oauth_pkce_plain_challenge(verifier: Str) -> Result[Str, Str]
pub fn oauth_pkce_plain_matches(verifier: Str, challenge: Str) -> Bool
pub fn oauth_pkce_s256_challenge(hash: &Vec[UInt8]) -> Result[Str, Str]
pub fn oauth_pkce_challenge_is_valid(challenge: Str, method: Str) -> Bool
pub fn oauth_response_type_is_valid(v: Str) -> Bool
pub fn oauth_grant_type_is_valid(v: Str) -> Bool
pub fn oauth_challenge_method_is_valid(v: Str) -> Bool
pub fn oauth_authz_error_is_valid(code: Str) -> Bool
pub fn oauth_token_error_is_valid(code: Str) -> Bool
pub fn oauth_version() -> Str
```

Types (parallel `Vec[Str]` fields; `names[i]` pairs with `values[i]`):

```xi
pub type OAuthParams  = { names: Vec[Str]; values: Vec[Str]; }
pub type AuthzRequest = { response_type: Str; client_id: Str; redirect_uri: Str;
                          scope: Vec[Str]; state: Str; code_challenge: Str;
                          code_challenge_method: Str; extra: OAuthParams; }
pub type AuthzResponse = { code: Str; state: Str; error: Str;
                           error_description: Str; error_uri: Str; extra: OAuthParams; }
pub type TokenRequest = { grant_type: Str; code: Str; redirect_uri: Str;
                          refresh_token: Str; scope: Vec[Str]; client_id: Str;
                          client_secret: Str; extra: OAuthParams; }
pub type TokenResponse = { access_token: Str; token_type: Str; expires_in: Int;
                           expires_in_present: Bool; refresh_token: Str;
                           scope: Vec[Str]; error: Str; error_description: Str; }
```

In every message type an empty `Str` means "absent from the wire". The
library never compares `Str` values with `==`; callers use
`xiom.string.compare.str_compare`.

## 2. Non-goals

- **No transport.** No sockets, HTTP, redirects, TLS or URL assembly; the
  leading `?` of a query is the caller's concern.
- **No crypto.** No JWT, no SHA-256, no signing or digest verification; the
  S256 helper only base64url-encodes a caller-computed digest.
- **No JSON parser.** Token responses are read through a bounded raw-byte
  key lookup (section 9): top-level scalar members only, no nested values,
  no unescaping, unknown members ignored.
- **No flow state.** No verifier generation, token storage, refresh
  scheduling, introspection or revocation.
- **No HTTP Basic client authentication.** `client_id`/`client_secret` are
  form fields; the `Authorization` header is the caller's job.
- **No streaming.** Whole buffers; the API is stateless free functions.

## 3. Notation

- `n` = input length in bytes.
- **Byte offset** = 0-based index into the string being parsed. For a value
  percent-decoded out of a form body, offsets in later checks (scope tokens,
  PKCE values) are into the **decoded** value.
- **Unreserved byte** = `A-Z a-z 0-9 - . _ ~` (RFC 3986 section 2.3).

## 4. Percent-encoding (`oauth_form_encode` / `oauth_form_decode`)

### 4.1 Encoding

One pass over the input bytes:

| Input byte | Output |
|---|---|
| `A-Z a-z 0-9 - . _ ~` | the byte itself |
| space `0x20` | `+` |
| every other byte | `%` + two **uppercase** hex digits (`0x2B` -> `%2B`, `0xC3` -> `%C3`, `0x00` -> `%00`) |

Empty input yields `""`. The encoding is canonical and total (never fails),
so `oauth_form_encode(oauth_form_decode(x).value) == x` for every canonical
`x`.

### 4.2 Decoding

One pass; `+` becomes a space; `%XX` (case-insensitive hex) becomes the byte
`0xXX`; every other byte is copied. Empty input yields `Ok("")`.

| Message | Trigger | Examples |
|---|---|---|
| `oauth: truncated percent escape at offset N` | input ends after `%` or after one hex digit | `"%"`, `"a%2"`, `"100%"` |
| `oauth: bad percent escape at offset N` | `%` followed by two bytes that are not hex digits | `"a%ZZ"`, `"%4G"` |
| `oauth: percent escape decodes to NUL at offset N` | the escape would decode to `0x00`, which cannot live in a NUL-terminated XIOM `Str` | `"%00"`, `"a=%00"` |

The first violation in input order is reported. Example: encode/decode
`"Grüße"` <-> `"Gr%C3%BC%C3%9Fe"`, `"a b"` <-> `"a+b"`.

## 5. Form bodies (`oauth_params_parse` / `oauth_params_encode`)

```
body        = [ pair *( "&" pair ) ]
pair        = name [ "=" value ]
name        = 1*( unreserved / "+" / pct )
value       = *( unreserved / "+" / pct )
pct         = "%" HEXDIG HEXDIG
```

Names and values are decoded (section 4.2) before interpretation; offsets
from the decoder are absolute offsets into the body.

- Empty body -> `Ok` with zero pairs.
- A pair without `=` yields an empty value (`"a"` -> name `a`, value `""`).
- Order and duplicates are preserved at the params layer.
- `oauth_params_encode` writes `name=value` pairs joined with a single `&`,
  encoding both sides; the round trip is canonical:
  `parse(encode(p))` equals `p` for any list `p` built with
  `oauth_params_add`.

Errors: `oauth: empty parameter at offset N` (leading, trailing or doubled
`&`, e.g. `"&a=1"`, `"a=1&"`, `"a=1&&b=2"`), `oauth: empty parameter name
at offset N` (`"=v"`), plus the section 4.2 decode errors.

## 6. Authorization request

### 6.1 Builder (`oauth_authz_request`)

Validates, then stores:

| Check | Error |
|---|---|
| `response_type` in {`code`, `token`} | `oauth: unsupported response_type: <v>` |
| `client_id` non-empty | `oauth: empty client_id` |
| every scope token non-empty, bytes `0x21..0x7E` except `"` and `\` | `oauth: empty scope token` / `oauth: scope token has invalid character` (no offsets on the build path) |
| PKCE pair rules (section 10.3) | see section 10.3 |

`scope` is copied; later mutation of the caller's vector does not change the
request.

### 6.2 Wire order (`oauth_authz_request_encode`)

```
response_type, client_id, redirect_uri, scope, state,
code_challenge, code_challenge_method, *extra
```

Optional fields are omitted when empty; `scope` is the token list joined
with single spaces and then form-encoded (so spaces become `+` or `%20`
round-tripping to a list). Extras are emitted last in insertion order. The
encoder re-validates everything the builder validates; a request produced by
`oauth_authz_request` always encodes successfully.

### 6.3 Parser (`oauth_authz_request_parse`)

Known names: `response_type`, `client_id`, `redirect_uri`, `scope`, `state`,
`code_challenge`, `code_challenge_method`. Everything else is preserved in
`extra`.

| Rule | Error |
|---|---|
| a known name appears twice | `oauth: duplicate parameter: <name>` |
| `response_type` absent | `oauth: missing parameter: response_type` |
| `response_type` not `code`/`token` | `oauth: unsupported response_type: <v>` |
| `client_id` absent | `oauth: missing parameter: client_id` |
| `client_id` present but empty | `oauth: empty client_id` |
| a scope token is empty (from a leading/trailing/doubled space) | `oauth: empty scope token at offset N` |
| a scope byte is not `0x21..0x7E` or is `"`/`\` | `oauth: scope token has invalid character at offset N` |
| PKCE pair rules (section 10.3) | see section 10.3 |

An absent `scope` (or `scope=`) yields an empty token list. Extras keep
their order and duplicates.

`oauth_authz_request_add_extra` rejects `""` (`oauth: empty parameter
name`) and the seven known names (`oauth: reserved parameter: <name>`) so a
duplicate cannot be smuggled in.

## 7. Authorization response (`oauth_authz_response_parse`)

Known names: `code`, `state`, `error`, `error_description`, `error_uri`;
everything else is preserved in `extra`. Duplicated known names are errors.

Precedence:

1. `error` and `code` both present -> `oauth: code with error`.
2. `error` present: empty -> `oauth: empty error code`; not one of the seven
   registered codes -> `oauth: unsupported error code: <v>`.
   `error_description` / `error_uri` are captured when present.
3. no `error`: `code` absent -> `oauth: missing parameter: code`; `code`
   present but empty -> `oauth: empty code`.

`state` is optional in both halves.

## 8. Token request

### 8.1 Grants (`oauth_token_request` / `oauth_token_request_parse`)

| grant_type | required | forbidden |
|---|---|---|
| `authorization_code` | `code` | `refresh_token` |
| `refresh_token` | `refresh_token` | `code` |
| `client_credentials` | -- | `code`, `redirect_uri`, `refresh_token` |

Unregistered grant -> `oauth: unsupported grant_type: <v>`. Grant-specific
violations: `oauth: missing code`, `oauth: missing refresh_token`,
`oauth: unexpected code`, `oauth: unexpected redirect_uri`,
`oauth: unexpected refresh_token`. `scope` is validated like the
authorization request; `client_id` / `client_secret` are unconstrained
optional body fields.

### 8.2 Wire order (`oauth_token_request_encode`)

```
grant_type, code, redirect_uri, refresh_token, scope, client_id,
client_secret, *extra
```

Optional fields are omitted when empty; extras last. The parser applies the
same rules and preserves extras; a duplicated known name is an error and
`grant_type` absent yields `oauth: missing parameter: grant_type`.

## 9. Token response and the JSON lookup

### 9.1 Raw-byte lookup (`oauth_json_*`)

`oauth_json_span(text, key)` finds the first **scalar top-level member**
`key` of the object text and returns its byte span (start, end), quotes
included for strings. `oauth_json_str` returns the inner bytes as a `Str`
(escapes left as written); `oauth_json_int` parses an optional `-` and
digits (magnitude <= 2147483647); `oauth_json_has` is the predicate form.

Rules:

- **Bounded:** text longer than `oauth_max_json_bytes()` (65536) ->
  `oauth: json too large`.
- **Boundary keys only:** a key matches at the start of the object, after
  `{`, `,`, space, TAB, LF or CR -- key text inside a string value never
  matches (`{"xaccess_token":...}` does not contain `access_token`).
- **Escape-aware strings:** inside a string value a backslash escapes the
  next byte, so `\"` does not terminate the value; the raw bytes are
  returned without unescaping.
- **No composites:** `{...}` and `[...]` values -> `oauth: json bad value:
  <key>`; `oauth_json_has` returns `false` for them.
- **No raw control bytes:** any byte below `0x20` other than TAB/LF/CR ->
  `oauth: json control byte at offset N` (so a returned `Str` never carries
  a NUL).
- Missing key -> `oauth: json key not found: <key>`; empty key ->
  `oauth: json empty key`; unterminated string or empty scalar ->
  `oauth: json bad value: <key>`.

### 9.2 Response rules (`oauth_token_response_parse`)

The body is trimmed of surrounding JSON whitespace and must be a `{...}`
object (`oauth: json not an object` otherwise). Then:

1. `error` and `access_token` both present -> `oauth: access_token with
   error`.
2. `error` present: empty -> `oauth: empty error code`; not one of the six
   registered section 5.2 codes -> `oauth: unsupported error code: <v>`;
   `error_description` captured when present.
3. otherwise: `access_token` required (`oauth: missing access_token`) and
   non-empty (`oauth: empty access_token`); `token_type` required
   (`oauth: missing token_type`) and equal to `Bearer` ignoring case
   (`oauth: unsupported token_type: <v>`).
4. `expires_in`, when present, must be digits only with magnitude
   <= 2147483647 (`oauth: invalid expires_in`); `expires_in_present` is set.
5. `refresh_token` and `scope` are captured when present; `scope` is split
   on single spaces like the form path. Unknown members are ignored.

## 10. PKCE (RFC 7636)

### 10.1 Verifier

43..128 characters, every character in the unreserved set (no whitespace).
`oauth_pkce_verifier_check` reports `oauth: pkce verifier length out of
range (43..128)` or `oauth: pkce verifier bad character at offset N`;
`oauth_pkce_verifier_is_valid` is the predicate form.
`oauth_pkce_verifier_min() == 43`, `oauth_pkce_verifier_max() == 128`.

### 10.2 Challenges

- **plain:** the challenge equals the verifier.
  `oauth_pkce_plain_challenge(v)` returns `Ok(v)` after validation;
  `oauth_pkce_plain_matches(v, challenge)` is the equality helper (an
  invalid verifier never matches).
- **S256:** the caller computes `SHA-256(verifier)`; this module only
  base64url-encodes the 32 raw digest bytes:
  `oauth_pkce_s256_challenge(hash)` -> `Ok(43-char unpadded base64url)`,
  `oauth: pkce s256 hash must be 32 bytes` otherwise. There is no hashing
  and no digest verification here.

### 10.3 Method pairing (build and parse)

- A method without a challenge ->
  `oauth: code_challenge_method without code_challenge`.
- A method that is not `plain`/`S256` ->
  `oauth: unsupported code_challenge_method: <v>`.
- A challenge with no method defaults to `plain` (RFC 7636 section 4.3) and
  is validated as a verifier; a `plain` challenge is validated as a
  verifier; an `S256` challenge must be exactly 43 base64url characters
  (`oauth: pkce s256 challenge length must be 43`,
  `oauth: pkce s256 challenge bad character at offset N`).

`oauth_pkce_challenge_is_valid(challenge, method)` combines these rules as a
predicate (empty method means `plain`).

## 11. Complete error catalog

Every message begins with `oauth: ` and is stable API. `... at offset N`
means a byte offset into the string being parsed.

| Message | Raised by |
|---|---|
| `oauth: truncated percent escape at offset N` | decode (section 4.2) |
| `oauth: bad percent escape at offset N` | decode |
| `oauth: percent escape decodes to NUL at offset N` | decode |
| `oauth: empty parameter at offset N` | form parse |
| `oauth: empty parameter name at offset N` | form parse |
| `oauth: empty parameter name` | `add_extra` with `""` |
| `oauth: parameter not found: <name>` | `oauth_params_get` |
| `oauth: duplicate parameter: <name>` | message parsers |
| `oauth: missing parameter: response_type` | authz request parse |
| `oauth: missing parameter: client_id` | authz request parse |
| `oauth: missing parameter: code` | authz response parse |
| `oauth: missing parameter: grant_type` | token request parse |
| `oauth: reserved parameter: <name>` | `add_extra` |
| `oauth: unsupported response_type: <v>` | build and parse |
| `oauth: unsupported grant_type: <v>` | build and parse |
| `oauth: unsupported code_challenge_method: <v>` | build and parse |
| `oauth: unsupported error code: <v>` | authz/token response parse |
| `oauth: unsupported token_type: <v>` | token response parse |
| `oauth: empty client_id` | build and parse |
| `oauth: empty code` | authz response parse |
| `oauth: empty error code` | authz/token response parse |
| `oauth: empty access_token` | token response parse |
| `oauth: code with error` | authz response parse |
| `oauth: access_token with error` | token response parse |
| `oauth: missing access_token` | token response parse |
| `oauth: missing token_type` | token response parse |
| `oauth: invalid expires_in` | token response parse |
| `oauth: empty scope token` | build |
| `oauth: empty scope token at offset N` | parse |
| `oauth: scope token has invalid character` | build |
| `oauth: scope token has invalid character at offset N` | parse |
| `oauth: missing code` | token request (authorization_code) |
| `oauth: missing refresh_token` | token request (refresh_token) |
| `oauth: unexpected code` | token request |
| `oauth: unexpected redirect_uri` | token request |
| `oauth: unexpected refresh_token` | token request |
| `oauth: code_challenge_method without code_challenge` | build and parse |
| `oauth: pkce verifier length out of range (43..128)` | PKCE |
| `oauth: pkce verifier bad character at offset N` | PKCE |
| `oauth: pkce s256 challenge length must be 43` | PKCE |
| `oauth: pkce s256 challenge bad character at offset N` | PKCE |
| `oauth: pkce s256 hash must be 32 bytes` | PKCE |
| `oauth: json too large` | JSON lookup |
| `oauth: json empty key` | JSON lookup |
| `oauth: json key not found: <key>` | JSON lookup |
| `oauth: json bad value: <key>` | JSON lookup |
| `oauth: json control byte at offset N` | JSON lookup |
| `oauth: json not an object` | token response parse |

Validation helpers (`*_check`, `add_extra`) return `Ok("")` on success.

## 12. API contract

| Function | Errors | Complexity |
|---|---|---|
| `oauth_form_encode` | none (total) | O(n) |
| `oauth_form_decode` | section 4.2 | O(n) |
| `oauth_params_*` | not-found / section 5 | O(pairs) |
| `oauth_authz_request` | section 6.1 | O(total input) |
| `oauth_authz_request_add_extra` | empty/reserved name | O(name.len()) |
| `oauth_authz_request_encode` | section 6.2 | O(total text) |
| `oauth_authz_request_parse` | section 6.3 | O(query.len()) |
| `oauth_authz_response_parse` | section 7 | O(query.len()) |
| `oauth_token_request` / `_parse` | section 8 | O(total input) |
| `oauth_token_request_encode` | section 8 | O(total text) |
| `oauth_json_*` | section 9.1 | O(text.len()) |
| `oauth_token_response_parse` | section 9.2 | O(json.len()) |
| `oauth_pkce_*` | section 10 | O(input) |
| predicates / accessors | none | O(input) or O(1) |

Round-trip guarantees proved by the suite:

- `oauth_form_decode(oauth_form_encode(s)) == Ok(s)` for ASCII, UTF-8 and
  reserved-character inputs (section 4; `%00` is rejected by design).
- `oauth_authz_request_parse(oauth_authz_request_encode(r))` reproduces
  `r` for every request the builder accepts (scope order, state, PKCE pair,
  extras).
- The same holds for `oauth_token_request_encode` / `_parse`.
- `oauth_pkce_s256_challenge` maps the 32-byte digests 0x00..0x1F and 32 x
  0xFF to the pinned base64url strings in the suite.

## 13. Test matrix

`tests/test_conformance.xi` (module `oauth_tests`) runs 25 named checks,
one `fn` per check, through `assert(cond, "name")`; `main` prints
`[PASS]`/`[FAIL]` and returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | form encode | unreserved literal, space `+`, `%XX` uppercase, UTF-8 bytes |
| t2 | form decode | `+`/`%20` as space, lowercase hex, reserved bytes |
| t3 | form round-trip | 8 inputs encode -> decode -> re-encode exactly |
| t4 | form decode errors | truncated/bad escapes and `%00` with offsets |
| t5 | params | ordered pairs, duplicates, `a` as empty value, encode round-trip |
| t6 | params errors | empty pair/name, decode errors with offsets |
| t7 | authz request build | exact wire, extras appended, reserved/empty extra names |
| t8 | authz request parse | fields, scope list, extras preserved |
| t9 | authz request errors | duplicates, missing required, bad type, extras order |
| t10 | authz request PKCE | default plain, S256 shape/length/char offsets |
| t11 | scope lists | empty/space/quote rejected, `scope=` is an empty list |
| t12 | authz response | code+state, error triple, extras |
| t13 | authz response errors | all 7 codes, code+error, empty/missing halves, duplicates |
| t14 | token request authorization_code | build, exact wire, parse, missing code, scope |
| t15 | token request grants | refresh/client_credentials, all grant-specific rules |
| t16 | json lookup | has/str/int/span, negative and bounded integers |
| t17 | json lookup edge cases | escape-aware, boundary keys, composite/NUL/unterminated |
| t18 | token response success | fields, Bearer case-insensitive, absent expires_in |
| t19 | token response errors | all 6 codes, description, exclusivity |
| t20 | token response malformed | required fields, token_type, expires_in, non-object |
| t21 | pkce verifier | 42/43/128/129 boundaries, charset, whitespace |
| t22 | pkce plain | challenge equality, method-aware validity |
| t23 | pkce S256 | pinned 32-byte digests -> base64url, length guard |
| t24 | predicates and limits | registered sets, accessors, version |
| t25 | ownership + extras | constructor/parse copy scope, extras round-trip |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.oauth
```

Last verified: compiler 0.61.3,
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## 14. Compiler / stdlib notes (v0.61.3)

- Free functions only; no methods, lambdas, `match`, or `Vec[StructType]`.
  Collections inside message types use parallel `Vec[Str]` fields, and the
  two vectors are always pushed together.
- `Ok`/`Err` construction for every `Result` type is confined to the leaf
  helpers `_ok_*` / `_err_*` (constructing Results inside larger functions
  miscompiles in this compiler).
- Every byte read from a `Str` or `Vec[UInt8]` is widened once with
  `(x as Int) & 0xFF` before comparison or arithmetic.
- No `Str` is compared with `==`; equality goes through
  `xiom.string.compare.str_compare` / `str_eq_ignore_case`, and `Str`
  values read out of structs, `Vec[Str]` or `Result` fields are bound to
  typed locals first (`&struct.field` is bound to a local before it reaches
  a `&Vec[Str]` parameter).
- `&mut` write-through is used only for `Vec` pushes (the sanctioned
  pattern); there are no `&mut Int` out-parameters and no `&mut Vec`
  returned through a parameter.
- `xiom.string.builder.sb_to_str` is never fed a NUL byte: `%00` is
  rejected, and the JSON scanner refuses raw control bytes below `0x20`.
- Integers are rendered with `builder.sb_push_int` (no `as` identifiers, no
  float formatting, no division beyond the truncating `/` used for the
  bounded digit parse).
- The module header has no `;`; every `use` statement ends with `;`.

## 15. Known limitations

- No transport, crypto (including SHA-256), JWT, introspection, revocation
  or flow orchestration.
- Token-response JSON extras are ignored; only form-message extras are
  preserved.
- The JSON lookup is not a parser: no arrays, no nested objects, no
  unescaping, no duplicate-key policy, bounded to 65536 bytes.
- Body client authentication only; HTTP Basic is the caller's concern.
- `%00` cannot be decoded into a `Str`; binary form values are out of
  scope.
- Strictness choices (duplicates rejected, `Bearer` only, digits-only
  `expires_in`, single-space scope lists) follow RFC 6749 but may reject
  lenient non-conformant peers.
- No streaming; thread-safety is the caller's concern.
