# xiom.jwt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.63.1; not
published).
Manifest: `package.xi` (`xiom.jwt`, version `0.1.1`).
Module: `src/jwt.xi` (`module xiom.jwt`).
Depends on `xiom.std` (`xiom.string`, `xiom.crypto`). The package declares no
FFI of its own; HS256 links the stdlib HMAC-SHA-256 (runtime C SHA-256), no
network and no clock access.

**Security posture: HS256 sign/verify plus structural decoding.** `0.2` adds
`jwt_sign_hs256`, `jwt_signature_valid_hs256` and `jwt_verify_hs256`: HMAC-
SHA-256 with a single-value `alg` allowlist (`HS256`), a constant-time MAC
comparison, a required `exp` and an optional `nbf` evaluated against a
caller-supplied clock. The structural decoder and its documented JSON *subset*
scanner remain unchanged: claim text is attacker-controlled until the MAC has
been verified against a trusted secret.

## 1. Scope

Fourteen free functions over `Str` / `&Vec[UInt8]`:

```xi
pub fn jwt_segment_count(token: Str) -> Int
pub fn jwt_is_shaped(token: Str) -> Bool
pub fn jwt_decode_segment(token: Str, index: Int) -> Result[Str, Str]
pub fn jwt_header_text(token: Str) -> Result[Str, Str]
pub fn jwt_payload_text(token: Str) -> Result[Str, Str]
pub fn jwt_signature_text(token: Str) -> Result[Str, Str]
pub fn jwt_alg(token: Str) -> Result[Str, Str]
pub fn jwt_claim_str(token: Str, name: Str) -> Result[Str, Str]
pub fn jwt_claim_int(token: Str, name: Str) -> Result[Int, Str]
pub fn jwt_expired(token: Str, now_secs: Int) -> Result[Bool, Str]
pub fn jwt_not_before_ok(token: Str, now_secs: Int) -> Result[Bool, Str]
pub fn jwt_sign_hs256(claims: Str, secret: &Vec[UInt8]) -> Result[Str, Str]
pub fn jwt_signature_valid_hs256(token: Str, secret: &Vec[UInt8]) -> Result[Bool, Str]
pub fn jwt_verify_hs256(token: Str, secret: &Vec[UInt8], now_secs: Int) -> Result[Str, Str]
```

All scanning is byte-wise. Every byte read through `xiom.string.byte_at` (or a
`Vec[UInt8]` element) is widened with `(x as Int) & 0xFF` before comparison or
arithmetic. Complexity is O(n) over the input length for every function.
Result values are constructed only in tiny leaf helpers (`_ok_str`, `_err_str`,
`_ok_bool`, `_err_bool`, `_ok_int`, `_err_int`, `_ok_bytes`, `_err_bytes`).
Private string/byte plumbing added in 0.2: `_b64u_encode` (unpadded base64url
encode over a byte vector), `_str_bytes` (widen a `Str` into `Vec[UInt8]`) and
`_has_key` (presence probe over the claim scanner).

## 2. Token model

A compact token is split on the `.` byte (46). Because splitting is textual,
`jwt_segment_count` is `1 + number of '.'` bytes:

| Token | Count | Note |
|---|---|---|
| `header.payload.signature` | 3 | compact JWS |
| `header.encrypted_key.iv.ciphertext.tag` | 5 | JWE-style (counted only) |
| `abc` | 1 | no separator |
| `""` | 1 | one empty piece, not zero |

Segment offsets are computed with `_seg_start`/`_seg_end`; there is no
`Vec[Str]` split and therefore no `==` on `Str` anywhere in the module.

`jwt_is_shaped(token)` is true iff:

1. the token has exactly 3 segments, and
2. each segment is non-empty, and
3. every byte of every segment is in the base64url alphabet `A-Z a-z 0-9 - _`.

Consequences (documented, tested): `h.p` (2 segments) -> false; `a.b.c.d.e`
(JWE) -> false; `h.p.` (empty signature, unsecured JWT) -> false; `a+b.c.d`
-> false; a token with `=`-padded segments -> false (padding is not part of the
alphabet). The text accessors are more permissive than this predicate: they
require exactly 3 segments and non-empty header/payload, but accept optional
padding in header/payload and an empty signature.

Segment index rules for `jwt_decode_segment`: `index < 0` or beyond the last
segment is `jwt: segment index out of range`; an existing empty segment is
`jwt: empty segment`.

## 3. base64url rules

`jwt_decode_segment`, `jwt_header_text` and `jwt_payload_text` decode with a
local strict RFC 4648 section 5 decoder (`_b64u_decode`):

- Alphabet: `A-Z` = 0..25, `a-z` = 26..51, `0-9` = 52..61, `-` = 62,
  `_` = 63. `+` and `/` are **rejected** (`jwt: invalid base64url
  character`); there is no cross-alphabet tolerance and no whitespace removal.
- Padding: a trailing run of `=` is optional. When present it must complete
  the final quantum (`(core + pad) % 4 == 0` and a 1-pad/2-data or 2-pad/
  3-data split). More than two pads, misplaced pads or a data length of
  1 (mod 4) are `jwt: invalid base64url padding`.
- Trailing bits of a partial tail are ignored, so non-canonical encodings
  decode to the same bytes as their canonical form.
- Decoded bytes are validated as UTF-8 per RFC 3629 before being returned:
  stray continuation bytes, truncated sequences, overlong forms, UTF-16
  surrogates and code points above U+10FFFF are `jwt: invalid UTF-8`. The
  validator is local because the pinned stdlib validator accepts stray bytes
  >= 0x80.
- `jwt_signature_text` returns segment 2 **verbatim** and does not decode it.
- Encoding (`_b64u_encode`, used by `jwt_sign_hs256`): the inverse mapping
  (`0..25` -> `A-Z`, `26..51` -> `a-z`, `52..61` -> `0-9`, `62` -> `-`,
  `63` -> `_`) with **no padding**. A 3-byte quantum becomes 4 characters, a
  1-byte tail 2 characters and a 2-byte tail 3 characters; an empty input
  encodes to `""`. The jwt.io KAT below pins all three tail lengths.

Why not the stdlib: `xiom.encoding.base64` allocates through FFI (`malloc`/
`free`, `xiom_char_at`) and `xiom.encoding.base64.base64url_decode` accepts a
1-character remainder as `Ok(empty)` instead of erroring; `xiom.codec`'s
base64url decoder accepts `+`/`/` cross-decoding and ignores whitespace. JWT
decoding wants strict `-`/`_` with optional padding, so this package carries
its own pure-XIOM helper.

## 4. Claim scanner grammar

The scanner is a documented JSON **subset**. It does not parse JSON, does not
track nesting, and does not decode escapes.

```
find(key)   := first byte offset just past the closing quote of the first
               occurrence of '"' key '"' anywhere in the text; -1 if absent
value(key)  := find(key) ws* ':' ws* value
string      := '"' (any byte except '"')* '"'      ; escapes NOT decoded
integer     := '-'? [0-9]+ terminator
terminator  := end-of-text | ws | ',' | '}'
ws          := TAB(9) | LF(10) | CR(13) | space(32)
```

Concrete consequences (tested):

- `_string_value("{\"a\":\"x\\\"y\"}", "a")` returns `x\` -- the escaped
  quote is not understood, so the value ends at the byte after the backslash.
- A `"name"` that appears inside another string value or a nested object can
  be matched; the scanner has no notion of "top level".
- `{"exp":"100"}` -> `jwt: expected string value` is not raised (that is the
  string reader); `jwt_claim_int` raises `jwt: expected integer value`.
- `{"exp":12.5}` and `{"exp":12abc}` -> `jwt: malformed integer value`;
  `{"exp":-}` -> `jwt: expected integer value`.
- `{"exp":1000}`, `{"exp":1000, ...}` and `{"exp":1000}` followed by
  whitespace all terminate correctly.
- Magnitudes beyond the signed 64-bit range -> `jwt: integer out of range`.

## 5. HS256 security policy

`jwt_sign_hs256`, `jwt_signature_valid_hs256` and `jwt_verify_hs256` implement
HMAC-SHA-256 compact JWS with these fixed choices:

| Decision | Policy |
|---|---|
| Header | `jwt_sign_hs256` writes the fixed literal `{"alg":"HS256","typ":"JWT"}` (no spaces); the payload is the caller's claims text, UTF-8 encoded as-is and **not** parsed or validated as JSON. |
| alg allowlist | Verification accepts a token only when the header `alg` is exactly the string `HS256` (byte-wise `str_compare(a, b) == 0`). `none`, `HS512`, a missing `alg` and every other value fail closed: a decoded header with a non-HS256 alg is `Ok(false)` from the predicate and `Err("jwt: signature mismatch")` from verify, with **no MAC computed**; an unreadable header/alg is `Err`. The token never selects the algorithm. |
| MAC compare | The recomputed HMAC is compared with `xiom.crypto.constant_time_compare` (equal-length check plus byte-wise XOR accumulation), never with a string comparison. |
| Segment shape | Exactly 3 segments and a non-empty signature segment are required. The signature must base64url-decode to exactly 32 bytes; a wrong length is `Ok(false)`, not `Err`. |
| Order | `jwt_verify_hs256` verifies the MAC BEFORE reading any claim; a false MAC is `Err("jwt: signature mismatch")` and no claim is touched. |
| exp | **Required.** Missing -> `Err("jwt: missing exp")`; malformed -> the scanner's integer error; `exp <= now_secs` -> `Err("jwt: token expired")` (RFC 7519 requires the current time to be strictly before `exp`). |
| nbf | Optional. When present: malformed -> the scanner's integer error; `now_secs < nbf` -> `Err("jwt: token not yet valid")`. |
| Clock | `now_secs` is always caller-supplied. The package never reads the system clock and applies no clock skew; callers wanting skew adjust `now_secs` themselves. |
| Keys | The secret is a caller-owned `&Vec[UInt8]` (any non-empty length; HMAC-SHA-256 key normalization per RFC 2104 applies inside the stdlib). No key derivation, storage, rotation or JWKS fetching. |
| Algorithm family | Symmetric HS256 only: no RS/ES/EdDSA, no `none`, no JWE decryption. |

## 6. Time semantics

- `jwt_expired(token, now)` = `Ok(exp <= now)`; `Ok(true)` at the exact
  boundary `exp == now` (RFC 7519: the current time must be strictly before
  `exp`).
- `jwt_not_before_ok(token, now)` = `Ok(now >= nbf)`; `Ok(true)` at
  `now == nbf`.
- `jwt_verify_hs256` applies the same comparisons on the verified payload:
  `exp <= now` -> `Err("jwt: token expired")` and `now < nbf` ->
  `Err("jwt: token not yet valid")`, with `exp` required (section 5).
- **Clock skew policy: none built in.** Callers needing a tolerance adjust
  `now_secs` (subtract from `now` for `exp`, add for `nbf`). The package never
  reads the system clock.
- A missing or malformed `exp`/`nbf` is `Err`, never a silent `Ok(true)`.

## 7. Error catalog

Every error message starts with the literal prefix `jwt: `.

| Message | Trigger |
|---|---|
| `jwt: token is not a 3-segment JWT` | `jwt_header_text` / `jwt_payload_text` / `jwt_signature_text` (and the claim readers through them) when `jwt_segment_count != 3`. |
| `jwt: segment index out of range` | `jwt_decode_segment`: `index < 0` or `index >= count`. |
| `jwt: empty segment` | `jwt_decode_segment` on an empty segment; `jwt_header_text`/`jwt_payload_text` on an empty header/payload; `jwt_signature_valid_hs256` on an empty signature segment. |
| `jwt: invalid base64url character` | Any byte outside `A-Z a-z 0-9 - _` (including `+`, `/`, `=`, whitespace). |
| `jwt: invalid base64url padding` | `=` run longer than 2, data after `=`, padding that does not complete the final quantum, or a data length of 1 (mod 4). |
| `jwt: invalid UTF-8` | Decoded bytes are not well-formed UTF-8 (RFC 3629). |
| `jwt: key not found: <name>` | Scanner: no quoted `"<name>"` occurrence; `<name>` is appended verbatim. |
| `jwt: expected string value` | Scanner: no `:` after the key, or after `:` no `"` byte. |
| `jwt: unterminated string value` | Scanner: the opening `"` has no follow-up `"`. |
| `jwt: expected integer value` | Scanner: no `:` after the key, or `-?` not followed by a digit. |
| `jwt: malformed integer value` | Scanner: a byte after the digits that is not end-of-text, whitespace, `,` or `}`. |
| `jwt: integer out of range` | Digit run exceeds the signed 64-bit range. |
| `jwt: empty secret` | `jwt_sign_hs256` / `jwt_signature_valid_hs256` when `secret.len() == 0` (checked before anything else). |
| `jwt: empty claims` | `jwt_sign_hs256` when `claims.len() == 0`. |
| `jwt: signature mismatch` | `jwt_verify_hs256` when the MAC check fails after a successful shape/alg decode. |
| `jwt: missing exp` | `jwt_verify_hs256` when the verified payload contains no quoted `"exp"`. |
| `jwt: token expired` | `jwt_verify_hs256` when `exp <= now_secs`. |
| `jwt: token not yet valid` | `jwt_verify_hs256` when a present `nbf` has `now_secs < nbf`. |

## 8. Test plan

`tests/test_conformance.xi` (module `jwt_tests`) runs 30 named checks through
`assert(cond, "name")`, one free `fn` per check, and `main` returns the failure
count (0 = green). Tokens are fixed base64url literals computed independently
of the module under test; all `Str` equality uses
`xiom.string.compare.str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | shaped true | classic 3-segment JWT (`jwt.io` HS256 example) is shaped |
| t2 | shaped false | 2 segments, JWE 5 segments, empty signature, empty token, `+` |
| t3 | segment_count | 3 / 5 (JWE) / 4 / 1 (no dots) / 1 (empty) |
| t4 | decode_segment | header and payload decode to their exact JSON text |
| t5 | decode range | index 3, index -1 and an empty segment are Err |
| t6 | decode errors | `+`, `YQ=`, `Y===`, 5-char core (1 mod 4) are Err |
| t7 | invalid UTF-8 | `_w` (0xFF) is Err for decode_segment and payload_text |
| t8 | text accessors | header/payload text exact; signature stays raw |
| t9 | non-3-segment | 2-segment and empty tokens are Err for all three accessors |
| t10 | optional padding | `eyJhIjoxfQ==` and `eyJhIjoxfQ` both decode to `{"a":1}` |
| t11 | alg | `HS256` and `none` extracted from the header |
| t12 | alg errors | missing `alg` and a 2-segment token are Err |
| t13 | claim_str | `sub`, `name`; absent key is Err |
| t14 | claim_int | `iat`, `exp`, negative `level` (-3) |
| t15 | claim_int errors | quoted number, float, trailing junk, bare `-`, missing key |
| t16 | claim_int range | `9223372036854775807` ok; 20-digit value is Err |
| t17 | expired boundary | `exp == now` is expired; false before, true after |
| t18 | expired edges | negative `exp`; missing and float `exp` are Err |
| t19 | nbf | false before, true at and after `nbf`; missing `nbf` is Err |
| t20 | malformed tokens | empty, 2-segment, `+` char, `..` segments are Err |
| t21 | JWE-style | count 5, not shaped, header text is Err |
| t22 | unicode | `München ✓` claim round-trips through UTF-8 |
| t23 | scanner subset | escaped quote is not decoded (`x\`) |
| t24 | signature | raw segment equality; empty signature yields `Ok("")` |
| t25 | sign encode | a signed token's header/payload decode back exactly and its signature segment is the KAT raw text |
| t26 | sign KAT | jwt.io HS256 vector: secret `your-256-bit-secret`, fixed claims -> exact token bytes |
| t27 | signature_valid | KAT true; tampered payload / tampered signature / wrong secret / `alg:none` / `alg:HS512` false |
| t28 | binary secret | secret `Vec[UInt8]` 0..31 signs and verifies; wrong secret -> `jwt: signature mismatch` |
| t29 | verify exp/nbf | exp required and boundary (`999` Ok / `1000` `jwt: token expired`); `nbf` boundary (`499` Err / `500` Ok); missing exp Err |
| t30 | empty inputs | empty secret/claims Err; empty secret on verify Err; 2-segment verify Err |

Harness command (repository root):

```
$env:XIOM_COMPILER  = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"
& .\scripts\port.ps1 -Package xiom.jwt
```

The `XIOM_RUNTIME_DIR` override supplies the runtime C objects that carry
`xiom_sha256_hash`, which `xiom.crypto.hmac_sha256` links against.

Expected: namespace check OK, 30 `[PASS]`, 0 `[FAIL]`, and
`port: PASS (passed=30 failed=0 program_exit=0 exit=0)`.

## 9. Out of scope

- Asymmetric algorithms (RS/ES/EdDSA), `alg: none` acceptance, and JWE
  decryption; HS256 signing/verification is in scope as of 0.2.
- JSON validation before signing: the claims string is signed as-is (and must
  be non-empty), not parsed.
- Full JSON parsing; only the scanner subset in section 4.
- 5-segment tokens are counted, not decoded.
- Clock access, key storage, JWKS fetching, revocation.
- Registry integration (no `xiom pkg`, no `STATUS.json` writes by the package).
