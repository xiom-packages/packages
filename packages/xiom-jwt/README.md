# xiom.jwt

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) structural decoding of compact JWT/JWS tokens:
> segment splitting, base64url decoding, UTF-8 validation, a minimal claim
> scanner and exp/nbf time checks.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.io`,
> `xiom.test`, `xiom.string.compare`).

## SECURITY -- read this first

**This package is decode-only. It does NOT verify signatures.**

- `jwt_is_shaped` only checks that a token has three base64url-looking
  segments. **Anyone can mint a token that passes it.**
- `jwt_alg`, `jwt_claim_*`, `jwt_expired` and `jwt_not_before_ok` read
  attacker-controlled text. They prove nothing about authenticity.
- **Never make an authentication or authorization decision from this module
  alone.** Verify the signature with a real crypto library against a trusted
  key, reject `alg: none` (unless the protocol explicitly allows it), and
  only then use these helpers to inspect claims and times.
- `alg` is returned as text for routing diagnostics, not as a trusted
  algorithm choice; do not let the token dictate the verification algorithm.
- The claim scanner is a documented subset (see below), not a JSON parser.

## What it is

`xiom.jwt` turns `header.payload.signature` into decoded text and reads the
handful of fields needed for coarse time checks, with deterministic
`jwt: `-prefixed error strings. It carries its own small base64url decoder
instead of depending on `xiom.encoding.base64` (which allocates through FFI
and whose URL-safe decoder silently accepts a 1-character tail) or on
`xiom.codec` (cross-alphabet, standard-base64 tolerant).

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

Error catalog (every message starts with `jwt: `):

| Message | Raised by |
|---|---|
| `jwt: token is not a 3-segment JWT` | `jwt_header_text`, `jwt_payload_text`, `jwt_signature_text` (and the claim readers through them). |
| `jwt: segment index out of range` | `jwt_decode_segment`. |
| `jwt: empty segment` | `jwt_decode_segment`, `jwt_header_text`, `jwt_payload_text`. |
| `jwt: invalid base64url character` | `jwt_decode_segment` and the text/claim readers. |
| `jwt: invalid base64url padding` | same. |
| `jwt: invalid UTF-8` | same. |
| `jwt: key not found: <name>` | `jwt_alg`, `jwt_claim_str`, `jwt_claim_int`. |
| `jwt: expected string value` | `jwt_alg`, `jwt_claim_str`: no `:` after the key, or no `"` after the `:`. |
| `jwt: unterminated string value` | `jwt_alg`, `jwt_claim_str`. |
| `jwt: expected integer value` | `jwt_claim_int`: no `:` after the key, or the value does not start with `-`/a digit. |
| `jwt: malformed integer value` | `jwt_claim_int`: a non-digit byte interrupts the number and is not a terminator. |
| `jwt: integer out of range` | `jwt_claim_int`. |

## Claim scanner subset

No JSON parser is used. The scanner finds the **first** occurrence of the
quoted `"name"` anywhere in the text (including inside another string value or
a nested object), skips whitespace, expects `:`, skips whitespace, then reads:

- a **string** from the opening `"` to the **next `"`** -- escape sequences
  such as `\"` are NOT decoded (`"x\"y"` scans as `x\`);
- an **integer** matching `-?[0-9]+` followed by end-of-text, whitespace,
  `,` or `}` -- quoted numbers, floats and trailing junk are rejected.

## Usage

```xi
use xiom.jwt;
use xiom.io;

let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig";
if jwt_is_shaped(token) {
  // WARNING: shape is not verification. Verify the signature first.
  let alg = jwt_alg(token);          // Ok("HS256")
  let sub = jwt_claim_str(token, "sub");  // Ok("1234567890")
  let exp = jwt_expired(token, 1750000000);  // Err when "exp" is absent
}
```

## Time policy

- `jwt_expired` returns `Ok(true)` when `exp <= now_secs` (RFC 7519 requires
  the current time to be strictly before `exp`).
- `jwt_not_before_ok` returns `Ok(true)` when `now_secs >= nbf`.
- **No clock skew is applied.** Callers that want a skew allowance adjust
  `now_secs` themselves. Neither function reads the system clock.
- A missing or malformed time claim is an `Err`, never a silent `Ok`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.jwt
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a final
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No signature verification, no crypto, no keys.** Decode-only; see
  SECURITY above.
- **No JSON parsing.** The claim scanner is the documented subset above.
- **Strict base64url alphabet**: only `A-Z a-z 0-9 - _` plus an optional
  trailing `=` run; `+`/`/` are rejected. Trailing bits of a partial tail are
  ignored (non-canonical encodings decode).
- **JWE-style tokens** are counted (5 segments) but not decoded.
- **`jwt_is_shaped` is stricter than the text accessors**: padded segments and
  an empty signature (`h.p.`, unsecured JWT) fail the predicate while the
  accessors still accept/report them.
- Pure XIOM: no FFI, no file or network I/O, no clock access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
