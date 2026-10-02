# xiom.oauth

> **Status:** `incubating` -- conformance-tested (25/25); published at `v0.1.2` on the XIOM registry.
> **Scope:** OAuth 2.0 (RFC 6749) / PKCE (RFC 7636) request-and-response
> **structure** codec: form-urlencoded and JSON message building/parsing.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.oauth` encodes and parses the payloads of an OAuth 2.0 exchange -- the
authorization query, the redirect query back, and the token endpoint POST
body and JSON reply. It is deliberately a **structure codec**: it never opens
a socket, never signs or verifies a JWT, and never hashes.

- **Form encoding** -- `application/x-www-form-urlencoded` with the OAuth
  rules: `A-Z a-z 0-9 - . _ ~` stay literal, space encodes as `+`, every
  other byte becomes `%XX` with uppercase hex. Decoding maps `+` to space and
  rejects malformed `%` escapes with the byte offset.
- **Authorization request** -- `response_type` (`code`/`token`), `client_id`,
  `redirect_uri`, `scope` (a list, space-joined on the wire), `state`,
  `code_challenge` + `code_challenge_method` (`plain`/`S256`), and any
  unknown parameters preserved in order.
- **Authorization response** -- `code` or the `error` +
  `error_description` + `error_uri` triple with the seven registered RFC
  6749 error codes; `code` and `error` together are rejected.
- **Token request** -- the `authorization_code`, `refresh_token` and
  `client_credentials` grants with grant-specific field rules, `scope`,
  and optional body `client_id`/`client_secret`.
- **Token response** -- `access_token`, `token_type` (`Bearer`,
  case-insensitive), `expires_in` (digits only), `refresh_token`, `scope`,
  or the `error`/`error_description` pair. JSON is inspected with a small
  bounded raw-byte key lookup, not a JSON parser.
- **PKCE** -- verifier validation (43..128 unreserved characters, no
  whitespace), the plain challenge equality helper, and the S256 challenge
  builder that base64url-encodes a **caller-computed** 32-byte SHA-256
  digest.

## Install

```
xiom pkg install xiom.oauth@0.1.0
```

## Quick start

```xi
use xiom.oauth;
use xiom.io;

fn main() -> Int {
  // Authorization request with the scope list and an extra parameter.
  var scope = Vec[Str].new();
  scope.push("read");
  scope.push("write");
  let rq = oauth_authz_request("code", "client-1", "https://app.example/cb",
                               &scope, "xyz", "", "");
  if !rq.is_ok { io.println(rq.error); return 1; }
  var req = rq.value;
  let ex = oauth_authz_request_add_extra(&mut req, "prompt", "consent");
  if !ex.is_ok { io.println(ex.error); return 1; }
  let q = oauth_authz_request_encode(&req);
  if q.is_ok { io.println(q.value); }
  // response_type=code&client_id=client-1&redirect_uri=...&scope=read+write&state=xyz&prompt=consent

  // The redirect query back to the client.
  let resp = oauth_authz_response_parse("code=S1&state=xyz");
  if resp.is_ok {
    let code: Str = resp.value.code;
    io.println("code received: " + code);
  }

  // PKCE S256: the caller runs SHA-256; this module only base64url-encodes.
  // let digest = sha256(verifier);            // caller-provided 32 bytes
  let digest = Vec[UInt8].new();               // placeholder for this sample
  let ch = oauth_pkce_s256_challenge(&digest);
  if !ch.is_ok { io.println(ch.error); }       // "must be 32 bytes"

  // Token endpoint reply (JSON object, bounded key lookup, no JSON parser).
  let body = "{\"access_token\":\"2YotnFZFEjr1zCsicMWpAA\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"scope\":\"read write\"}";
  let tr = oauth_token_response_parse(body);
  if tr.is_ok {
    if tr.value.expires_in_present {
      io.println("token valid for 3600s");
    }
  }
  return 0;
}
```

## API

**Form and parameters**

| Function | Returns | Description |
|---|---|---|
| `oauth_form_encode(s)` | `Str` | Form-encode: unreserved chars literal, space `+`, `%XX` uppercase. |
| `oauth_form_decode(s)` | `Result[Str, Str]` | Decode; `+` is space; bad `%` escapes carry byte offsets. |
| `oauth_params_new()` | `OAuthParams` | Empty ordered pair list. |
| `oauth_params_add(p, name, value)` | -- | Append one pair (duplicates allowed). |
| `oauth_params_count(p)` | `Int` | Number of pairs. |
| `oauth_params_name_at(p, i)` | `Str` | Name of pair `i`. |
| `oauth_params_value_at(p, i)` | `Str` | Value of pair `i`. |
| `oauth_params_has(p, name)` | `Bool` | First-match membership test. |
| `oauth_params_get(p, name)` | `Result[Str, Str]` | First value, or a not-found error. |
| `oauth_params_encode(p)` | `Str` | `k=v` pairs joined with `&`, each side encoded. |
| `oauth_params_parse(query)` | `Result[OAuthParams, Str]` | Strict form parse preserving order and duplicates. |

**Authorization request / response**

| Function | Returns | Description |
|---|---|---|
| `oauth_authz_request(response_type, client_id, redirect_uri, scope, state, code_challenge, code_challenge_method)` | `Result[AuthzRequest, Str]` | Validated builder; empty `Str` means absent. |
| `oauth_authz_request_add_extra(req, name, value)` | `Result[Str, Str]` | Append an extra; reserved names rejected. |
| `oauth_authz_request_encode(req)` | `Result[Str, Str]` | Query component (no leading `?`). |
| `oauth_authz_request_parse(query)` | `Result[AuthzRequest, Str]` | Strict parse; extras preserved. |
| `oauth_authz_response_parse(query)` | `Result[AuthzResponse, Str]` | Success or error redirect; extras preserved. |

**Token request / response**

| Function | Returns | Description |
|---|---|---|
| `oauth_token_request(grant_type, code, redirect_uri, refresh_token, scope, client_id, client_secret)` | `Result[TokenRequest, Str]` | Validated builder for the three grants. |
| `oauth_token_request_add_extra(req, name, value)` | `Result[Str, Str]` | Append an extra; reserved names rejected. |
| `oauth_token_request_encode(req)` | `Result[Str, Str]` | POST body (no leading `?`). |
| `oauth_token_request_parse(body)` | `Result[TokenRequest, Str]` | Strict parse; extras preserved. |
| `oauth_token_response_parse(json)` | `Result[TokenResponse, Str]` | Success or error JSON object. |
| `oauth_json_has/span/str/int(text, key)` | `Bool` / `Result[...]` | Bounded raw-byte JSON member lookup (see SPEC). |
| `oauth_max_json_bytes()` | `Int` | `65536`, the lookup scan bound. |

**PKCE and predicates**

| Function | Returns | Description |
|---|---|---|
| `oauth_pkce_verifier_min()` / `_max()` | `Int` | `43` / `128`. |
| `oauth_pkce_s256_hash_len()` | `Int` | `32` (the caller's SHA-256 digest size). |
| `oauth_pkce_verifier_check(v)` | `Result[Str, Str]` | Charset/length check with offsets. |
| `oauth_pkce_verifier_is_valid(v)` | `Bool` | Predicate form. |
| `oauth_pkce_plain_challenge(v)` | `Result[Str, Str]` | Validated plain challenge (= verifier). |
| `oauth_pkce_plain_matches(v, challenge)` | `Bool` | Plain equality after verification. |
| `oauth_pkce_s256_challenge(hash)` | `Result[Str, Str]` | 32 bytes -> 43-char unpadded base64url. |
| `oauth_pkce_challenge_is_valid(c, method)` | `Bool` | Method-aware challenge shape check. |
| `oauth_response_type_is_valid`, `oauth_grant_type_is_valid`, `oauth_challenge_method_is_valid`, `oauth_authz_error_is_valid`, `oauth_token_error_is_valid` | `Bool` | Registered-value predicates. |
| `oauth_version()` | `Str` | `"0.1.0"`. |

`OAuthParams` is `{ names: Vec[Str]; values: Vec[Str]; }` (parallel vectors,
`names[i]` paired with `values[i]`); the message types expose the same
parallel layout for extras. All functions are free functions and total where
documented; complexity is O(n) over the input.

## Error model

Every error message starts with `oauth: ` and is stable API. Structural
violations found in form text carry the byte offset of the first violation
(`... at offset N`); offsets are into the string being parsed (for a
percent-decoded value the offset is into the decoded value). Representative
messages -- the complete catalog lives in `SPEC.md`:

| Message | Trigger |
|---|---|
| `oauth: truncated percent escape at offset N` | input ends inside `%XX`. |
| `oauth: bad percent escape at offset N` | `%` followed by non-hex. |
| `oauth: percent escape decodes to NUL at offset N` | `%00`, which cannot live in a `Str`. |
| `oauth: empty parameter at offset N` | leading/trailing/double `&`. |
| `oauth: duplicate parameter: <name>` | a known parameter appears twice. |
| `oauth: missing parameter: <name>` | required parameter absent. |
| `oauth: unsupported response_type/grant_type/token_type/error code: <v>` | unregistered value. |
| `oauth: code with error` / `oauth: access_token with error` | success and error halves mixed. |
| `oauth: pkce verifier length out of range (43..128)` | verifier length. |
| `oauth: pkce verifier bad character at offset N` | non-unreserved byte in a verifier. |
| `oauth: pkce s256 challenge length must be 43` | S256 challenge not 43 chars. |
| `oauth: pkce s256 hash must be 32 bytes` | wrong digest length. |
| `oauth: json key not found: <key>` / `oauth: json bad value: <key>` | lookup miss / non-scalar value. |
| `oauth: json not an object` | token response is not a `{...}` object. |
| `oauth: invalid expires_in` | `expires_in` not a non-negative decimal integer. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.oauth
```

Expected tail: 25 `[PASS]` lines, `xiom.oauth: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No transport.** No sockets, no HTTP, no redirect handling, no TLS; the
  caller owns the wire and the URL (the leading `?` is the caller's job).
- **No crypto.** No JWT issuance/validation, no SHA-256, no signing. The
  S256 helper only base64url-encodes a digest the caller computed; there is
  no "verify the challenge" helper beyond shape validation.
- **No JSON parser.** Token responses go through a bounded raw-byte key
  lookup: only top-level scalar members are readable, composite values are
  rejected, escapes are not unescaped, unknown JSON members are ignored, and
  input above `oauth_max_json_bytes()` (65536) is rejected.
- **Extras are preserved for form messages only.** Authorization/token
  request/response extras survive; token-response JSON members do not.
- **Body client authentication only.** `client_id`/`client_secret` are form
  fields; HTTP Basic (`Authorization` header) is a caller concern.
- **No `%00` in decoded text.** A decoded 0x00 cannot live in a XIOM `Str`,
  so such escapes are rejected (`oauth: percent escape decodes to NUL ...`).
- **Strictness choices.** Duplicate known parameters are rejected; scope
  tokens are single-space separated printable ASCII without `"` or `\`;
  `token_type` must be `Bearer` (case-insensitive); `expires_in` must be
  digits only; `code` + `error` combinations are rejected.
- **No state machine.** No token storage, refresh scheduling, PKCE verifier
  generation, or flow orchestration; this package is a codec only.
- **Whole-buffer, stateless.** No streaming; thread-safety is the caller's
  concern.

See `SPEC.md` for the exact grammar, the complete error catalog and the test
matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
