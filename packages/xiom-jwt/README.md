# xiom.jwt

> **Status:** `stable` -- conformance-tested (30/30); published at `v0.1.1` on the XIOM registry.
> **Scope:** structural decoding of compact JWT/JWS tokens (segment splitting,
> base64url encode/decode, UTF-8 validation, a minimal claim scanner and
> exp/nbf time checks) plus HS256 signing and verification.
> **Deps:** `xiom.std` (`xiom.string`, `xiom.crypto`; tests add `xiom.io`,
> `xiom.test`, `xiom.string.compare`). The HS256 path links the stdlib
> HMAC-SHA-256 (runtime C SHA-256); set `XIOM_RUNTIME_DIR` to a runtime that
> exports `xiom_sha256_hash` when building.

## SECURITY -- read this first

**HS256 sign/verify is available; it is the only algorithm supported, and it
is only as good as the secret you trust.**

- `jwt_sign_hs256(claims, secret)` signs a claims string with HMAC-SHA-256
  into `header.payload.signature`; verification accepts a header `alg` of
  exactly `HS256`. `alg: none`, `HS512` and everything else fail closed, and
  the token never picks the algorithm.
- `jwt_signature_valid_hs256` and `jwt_verify_hs256` compare the recomputed
  MAC in constant time (`xiom.crypto.constant_time_compare`); a wrong secret
  or a tampered payload/signature is `Ok(false)` / `Err("jwt: signature
  mismatch")`.
- `jwt_verify_hs256` verifies the signature FIRST, then requires `exp`
  (RFC 7519) and enforces optional `nbf` against the **caller's** clock. It
  never reads the system clock.
- The decode-only helpers (`jwt_is_shaped`, `jwt_alg`, `jwt_claim_*`,
  `jwt_expired`, `jwt_not_before_ok`) still read attacker-controlled text:
  on a token that has not passed `jwt_verify_hs256` they prove nothing about
  authenticity.
- No RS/ES/EdDSA, no `alg: none`, no key management, no JWKS fetching: bring
  your own trusted key. Never let the token dictate the verification
  algorithm.
- The claim scanner is a documented subset (see below), not a JSON parser.

## What it is

`xiom.jwt` turns `header.payload.signature` into decoded text, reads the
handful of fields needed for coarse time checks, and signs/verifies HS256
tokens -- with deterministic `jwt: `-prefixed error strings. It carries its
own small base64url codec instead of depending on `xiom.encoding.base64`
(which allocates through FFI and whose URL-safe decoder silently accepts a
1-character tail) or on `xiom.codec` (cross-alphabet, standard-base64
tolerant). Signing/verification delegates HMAC-SHA-256 to `xiom.crypto`.

## API

| Function | Returns | Description |
|---|---|---|
| `jwt_segment_count(token)` | `Int` | 1 + number of `.`; 3 for a JWS, 5 for a JWE-style token. |
| `jwt_is_shaped(token)` | `Bool` | Exactly 3 non-empty base64url-alphabet segments (padding and an empty signature make this false). |
| `jwt_decode_segment(token, index)` | `Result[Str, Str]` | Base64url-decode segment `index` and validate it as UTF-8; optional `=` padding. |
| `jwt_header_text(token)` | `Result[Str, Str]` | Decoded header (segment 0) text. |
| `jwt_payload_text(token)` | `Result[Str, Str]` | Decoded payload (segment 1) text. |
| `jwt_signature_text(token)` | `Result[Str, Str]` | Raw, undecoded signature (segment 2); may be empty. |
| `jwt_alg(token)` | `Result[Str, Str]` | The `"alg"` string from the header. |
| `jwt_claim_str(token, name)` | `Result[Str, Str]` | A quoted string claim from the payload. |
| `jwt_claim_int(token, name)` | `Result[Int, Str]` | A signed integer claim from the payload. |
| `jwt_expired(token, now_secs)` | `Result[Bool, Str]` | `Ok(true)` when `exp <= now_secs`; `Err` when `exp` is absent/malformed. |
| `jwt_not_before_ok(token, now_secs)` | `Result[Bool, Str]` | `Ok(true)` when `now_secs >= nbf`; `Err` when `nbf` is absent/malformed. |
| `jwt_sign_hs256(claims, secret)` | `Result[Str, Str]` | `Ok(token)` -- HS256 over the fixed header `{"alg":"HS256","typ":"JWT"}`; unpadded base64url. |
| `jwt_signature_valid_hs256(token, secret)` | `Result[Bool, Str]` | `Ok(true)` when the header alg is `HS256` and the 32-byte MAC matches (constant time); `Ok(false)` for a wrong alg/length/MAC. |
| `jwt_verify_hs256(token, secret, now_secs)` | `Result[Str, Str]` | Signature first, then required `exp` and optional `nbf` against the caller clock; `Ok(payload_text)` when valid. |

Error catalog (every message starts with `jwt: `):

| Message | Raised by |
|---|---|
| `jwt: token is not a 3-segment JWT` | `jwt_header_text`, `jwt_payload_text`, `jwt_signature_text` (and the claim readers through them). |
| `jwt: segment index out of range` | `jwt_decode_segment`. |
| `jwt: empty segment` | `jwt_decode_segment`, `jwt_header_text`, `jwt_payload_text`; `jwt_signature_valid_hs256` on an empty signature. |
| `jwt: invalid base64url character` | `jwt_decode_segment` and the text/claim readers. |
| `jwt: invalid base64url padding` | same. |
| `jwt: invalid UTF-8` | same. |
| `jwt: key not found: <name>` | `jwt_alg`, `jwt_claim_str`, `jwt_claim_int`. |
| `jwt: expected string value` | `jwt_alg`, `jwt_claim_str`: no `:` after the key, or no `"` after the `:`. |
| `jwt: unterminated string value` | `jwt_alg`, `jwt_claim_str`. |
| `jwt: expected integer value` | `jwt_claim_int`: no `:` after the key, or the value does not start with `-`/a digit. |
| `jwt: malformed integer value` | `jwt_claim_int`: a non-digit byte interrupts the number and is not a terminator. |
| `jwt: integer out of range` | `jwt_claim_int`. |
| `jwt: empty secret` | `jwt_sign_hs256`, `jwt_signature_valid_hs256` on a zero-length key. |
| `jwt: empty claims` | `jwt_sign_hs256` on an empty claims string. |
| `jwt: signature mismatch` | `jwt_verify_hs256` when the MAC check fails. |
| `jwt: missing exp` | `jwt_verify_hs256`: the verified payload has no `exp`. |
| `jwt: token expired` | `jwt_verify_hs256`: `exp <= now_secs`. |
| `jwt: token not yet valid` | `jwt_verify_hs256`: a present `nbf` has `now_secs < nbf`. |

## Claim scanner subset

No JSON parser is used. The scanner finds the **first** occurrence of the
quoted `"name"` anywhere in the text (including inside another string value or
a nested object), skips whitespace, expects `:`, skips whitespace, then reads:

- a **string** from the opening `"` to the **next `"`** -- escape sequences
  such as `\"` are NOT decoded (`"x\"y"` scans as `x\`);
- an **integer** matching `-?[0-9]+` followed by end-of-text, whitespace,
  `,` or `}` -- quoted numbers, floats and trailing junk are rejected.

## Usage

Sign and verify in three lines -- the claims string must be non-empty and
`now_secs` always comes from the caller:

```xi
use xiom.jwt;
use xiom.io;

let claims  = "{\"sub\":\"1234567890\",\"exp\":1750000000}";
let token   = jwt_sign_hs256(claims, &secret);                   // Ok("header.payload.signature")
let payload = jwt_verify_hs256(token.value, &secret, now_secs);  // Ok(claims); Err on bad MAC/exp/nbf
let sub     = jwt_claim_str(payload.value, "sub");               // Ok("1234567890") after verification
```

`secret` is a `Vec[UInt8]` that both sides trust. `jwt_verify_hs256` checks
the MAC before reading any claim, so the claim accessors on `payload.value`
are safe to use; the decode-only helpers on an unverified token are not.

## Time policy

- `jwt_expired` returns `Ok(true)` when `exp <= now_secs` (RFC 7519 requires
  the current time to be strictly before `exp`).
- `jwt_not_before_ok` returns `Ok(true)` when `now_secs >= nbf`.
- `jwt_verify_hs256` requires `exp` (absent -> `Err("jwt: missing exp")`) and
  applies the same two comparisons to `exp`/`nbf` on the verified payload.
- **No clock skew is applied.** Callers that want a skew allowance adjust
  `now_secs` themselves. None of these functions reads the system clock.
- A missing or malformed time claim is an `Err`, never a silent `Ok`.

## Testing

From the repository root:

```
$env:XIOM_COMPILER  = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"
& .\scripts\port.ps1 -Package xiom.jwt
```

`XIOM_RUNTIME_DIR` supplies the runtime C objects that carry
`xiom_sha256_hash` (linked by `xiom.crypto.hmac_sha256`). Expected: the
section-4 namespace check passes, 30 `[PASS]` lines, and a final
`port: PASS (passed=30 failed=0 program_exit=0 exit=0)`.

## Limitations

- **HS256 only.** No RS/ES/EdDSA, no `alg: none` acceptance, no key
  management or JWKS; asymmetric verification is out of scope.
- **Keys are caller-owned.** Secrets are `&Vec[UInt8]`; there is no key
  derivation, storage or rotation.
- **The payload is signed as-is.** Claims are not validated as JSON before
  signing (empty claims are rejected).
- **No JSON parsing.** The claim scanner is the documented subset above.
- **Strict base64url alphabet**: only `A-Z a-z 0-9 - _` plus an optional
  trailing `=` run; `+`/`/` are rejected. Trailing bits of a partial tail are
  ignored (non-canonical encodings decode).
- **JWE-style tokens** are counted (5 segments) but not decoded.
- **`jwt_is_shaped` is stricter than the text accessors**: padded segments and
  an empty signature (`h.p.`, unsecured JWT) fail the predicate while the
  accessors still accept/report them.
- No file or network I/O, no clock access. The package declares no FFI of its
  own; the HS256 path links the stdlib HMAC-SHA-256 implementation.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
