# xiom.vault -- Specification (as implemented)

This document specifies exactly what the `xiom.vault` package does. It is
written from the implementation: where a helper is stricter or more relaxed
than a full Vault client, that is stated explicitly (section 12).

Baseline: XIOM compiler v0.62.2, package `xiom.vault` 0.1.0.

## 1. Scope

A pure-XIOM model of a Hashicorp-Vault-style secret backend integration:

* request/response structures for an HTTP API client (method codes, paths,
  query strings, headers, flat JSON-ish bodies, response envelopes);
* a bounded flat-JSON scanner for raw key lookup in request/response bodies;
* KV secrets engine paths, version selection and the v2 soft-delete state
  model;
* Shamir secret sharing over GF(256) plus an unseal progress model;
* token and AppRole authentication models;
* ACL policy capability sets, glob path matching and longest-prefix
  resolution.

All functions are free functions and total: they return `Result[...]` (or
plain values) and never abort on malformed input. Secrets are byte-oriented
(`Vec[UInt8]`); textual secrets are represented as hex, never as `Str` built
from arbitrary bytes.

## 2. Non-goals

No HTTP/TCP I/O, no FFI, no TLS, no cryptography (no hashes, signatures,
encryption, token generation or UUID generation), no lease arithmetic, no
clock/time handling, no URL percent-encoding, no HCL policy parser, no Vault
server semantics beyond the documented model. The package never decides
whether a token or credential is authentic.

## 3. Module layout and compiler constraints

All modules live under the `xiom.vault` namespace:

| Module | File | Purpose |
|--------|------|---------|
| `xiom.vault` | `src/vault.xi` | composed client operations (entry) |
| `xiom.vault.core` | `src/core.xi` | shared constants + byte helpers |
| `xiom.vault.client` | `src/client.xi` | request/response/body model |
| `xiom.vault.json` | `src/json.xi` | flat-JSON scanner |
| `xiom.vault.kv` | `src/kv.xi` | KV paths, versions, ledger |
| `xiom.vault.unseal` | `src/unseal.xi` | GF(256), Shamir, unseal |
| `xiom.vault.auth` | `src/auth.xi` | token / AppRole models |
| `xiom.vault.policy` | `src/policy.xi` | capabilities + path rules |

Import direction is sibling-to-sibling only: on compiler v0.62.2 a child
module cannot import and call its parent (a probe of the failing shape is
described in section 13), so base code lives in `core`/`client`/`json` and
only the entry module imports downward. Consumers may import only the area
modules they need.

## 4. Client model (`xiom.vault.client`)

### 4.1 Methods

`vault_method_code(name)` is case-insensitive over GET=1, POST=2, PUT=3,
PATCH=4, DELETE=5, LIST=6, HEAD=7, OPTIONS=8; unknown names return 0.
`vault_method_name(code)` returns the canonical uppercase name or "".

### 4.2 Path normalization

`vault_path_normalize(path)` rejects an empty path, paths longer than 4096
bytes, and any control byte or space (error carries the byte offset). Output
always has a leading '/', collapsed '/' runs, no trailing '/' (except "/"),
e.g. `sys/health` -> `/sys/health`, `/a//b/` -> `/a/b`. Bytes >= 0x80 are
passed through. Percent-encoding is the caller's concern.

### 4.3 Requests

`VaultRequest` is `{ method, path, query, header_names, header_values, body,
has_body }`; the header vectors never drift. `vault_request_new` validates
the method code (0 and out-of-range are errors) and normalizes the path.

* Query (`vault_request_set_query`): an optional leading '?' is stripped and
  the stored form never has one; empty input clears it; '?', '#', control
  bytes and spaces are rejected; every '&'-separated segment must be
  non-empty; max 4096 bytes.
* Headers (`vault_request_set_header`, `vault_request_remove_header`,
  `vault_request_header_get`, `vault_request_has_header`): names are RFC 7230
  tokens (max 128 bytes), values max 4096 bytes and reject control bytes
  except HTAB; name lookup/replace/removal is ASCII-case-insensitive; max 64
  headers. `vault_request_set_token` attaches `X-Vault-Token` after checking
  the token is non-empty and control-free.
* Body: `vault_request_set_body` renders a `VaultBody`;
  `vault_request_set_body_text` attaches pre-rendered JSON (non-empty, no
  control bytes except LF/CR/HTAB); `vault_request_clear_body`.
* `vault_request_target` is `path` plus `?<query>` when a query is set.

### 4.4 Body builder

`VaultBody` is a flat object: parallel `names` / `kinds` / `values` vectors
(max 64 members). `vault_body_add_str` stores an escaped-on-render string,
`vault_body_add_raw` accepts only a JSON scalar (number per the JSON grammar,
or `true` / `false` / `null`), `vault_body_add_int` renders a decimal
integer, `vault_body_add_bool` renders a boolean. Member names are 1..128
printable bytes without '"', '\' or space. `vault_body_render` emits
`{"name":value,...}` in insertion order; an empty body renders `{}`.

### 4.5 Response envelope

`VaultResponse` is `{ status, body }`. `vault_response_new` requires a
100..599 status; `vault_response_is_success` is true for 2xx. The body is
kept verbatim for the JSON scanner; no interpretation is performed.

## 5. JSON scanner (`xiom.vault.json`)

A bounded scanner for flat JSON objects (typically a Vault response body).

* `vault_json_lookup(text, key)` finds a TOP-LEVEL member (first match wins)
  and returns a `VaultJsonHit` whose `[start, end)` span covers the whole
  raw value (string quotes and object/array delimiters included); `next`
  equals `end`. Member names are decoded (escapes applied) before the
  case-SENSITIVE comparison.
* Values are scanned by a depth-capped (16) balanced scanner; objects,
  arrays, strings, numbers and the literals true/false/null are validated;
  a malformed member anywhere before the match is an error with an offset.
* `vault_json_get_raw` returns the raw slice; `vault_json_get_str` decodes a
  string (escapes `" \ / b f n r t` and `\uXXXX` for code points 1..FFFF;
  NUL and surrogates are rejected); `vault_json_get_int` accepts only a
  decimal integer (no fraction/exponent, optional '-'); `vault_json_get_bool`
  accepts only `true`/`false`; `vault_json_get_strs` decodes an array of
  strings (up to 256 elements) and rejects any non-string element.

## 6. KV secrets engine (`xiom.vault.kv`)

### 6.1 Names and paths

Mounts are single segments of 1..64 bytes over `[A-Za-z0-9_-]`. Keys are
1..512 bytes of '/'-separated non-empty segments over `[A-Za-z0-9_.-]`, with
no leading, trailing or doubled '/'. Paths (no leading slash; the client
normalizes when building requests):

| Function | Path |
|----------|------|
| `vault_kv1_path` | `<mount>/<key>` |
| `vault_kv2_data_path` | `<mount>/data/<key>` |
| `vault_kv2_metadata_path` | `<mount>/metadata/<key>` |
| `vault_kv2_delete_path` | `<mount>/delete/<key>` |
| `vault_kv2_undelete_path` | `<mount>/undelete/<key>` |
| `vault_kv2_destroy_path` | `<mount>/destroy/<key>` |

### 6.2 Version selection and bodies

`vault_kv2_version_query(N)` returns `version=N` for N in 1..1000000.
`vault_kv2_versions_body(versions)` renders `{"versions":[...]}` for 1..64
version numbers, each 1..1000000, duplicates preserved.

### 6.3 Request builders

| Function | Method | Path | Notes |
|----------|--------|------|-------|
| `vault_kv2_read_request(mount, key, version)` | GET | data | `version` 0 = latest; >0 adds the query; negative is an error |
| `vault_kv2_write_request` | POST | data | caller attaches the secret body |
| `vault_kv2_metadata_request` | GET | metadata | |
| `vault_kv2_delete_request` | POST | delete | without a body: latest version |
| `vault_kv2_delete_versions_request` | POST | delete | with `{"versions":[...]}` |
| `vault_kv2_undelete_request` | POST | undelete | |
| `vault_kv2_undelete_versions_request` | POST | undelete | with `{"versions":[...]}` |
| `vault_kv2_destroy_request` | PUT | destroy | irreversible |
| `vault_kv2_destroy_versions_request` | PUT | destroy | with `{"versions":[...]}` |

### 6.4 Version state ledger

`vault_kv_versions_new(n)` creates a slot ledger for versions 1..n
(1..256). `states[i]` is the state of version i+1: 0 absent, 1 live,
2 soft-deleted, 3 destroyed. `vault_kv_versions_apply(v, op, version)`
returns a NEW ledger (the input is never mutated; the state vector is
copied) and never fails silently:

| Op | absent | live | soft-deleted | destroyed |
|----|--------|------|--------------|-----------|
| WRITE | -> live | -> live | -> live (revive) | error |
| READ | error "absent" | ok, unchanged | error "deleted" | error "destroyed" |
| DELETE | error "absent" | -> soft-deleted | -> soft-deleted (idempotent) | error "destroyed" |
| UNDELETE | error "absent" | -> live (idempotent) | -> live | error "destroyed" |
| DESTROY | error "absent" | -> destroyed | -> destroyed | -> destroyed (idempotent) |

`vault_kv_versions_state` returns -1 outside the ledger;
`vault_kv_can_read` is true only for live; `vault_kv_state_name` maps
0/1/2/3 to absent/live/soft-deleted/destroyed.

## 7. Shamir sharing and unseal (`xiom.vault.unseal`)

GF(256) arithmetic uses the AES polynomial 0x11B (283): `vault_gf_mul`
(Russian peasant, 8 iterations), `vault_gf_inv` (exhaustive search;
0 has no inverse), both range-checked to 0..255.

`vault_shamir_share_len(len)` is `len + 1` for len in 1..1024, else 0.

Split (`vault_shamir_split_with_coeffs`): secret bytes are the degree-0
coefficients; `coeffs` supplies exactly `(threshold - 1) * len` bytes in
degree-then-byte order. Output layout: `shares` blocks of
`[x, f(x)[0], ..., f(x)[len-1]]` with x = 1..shares, so
`shares * (len + 1)` bytes. Shares 2..255, threshold 2..shares.
`vault_shamir_split` derives the coefficients from a seed with a
deterministic xorshift-style 63-bit stream (non-positive seeds use a fixed
default), giving reproducible shares.

Combine (`vault_shamir_combine(shares, secret_len)`): the data length must
be a multiple of `secret_len + 1`; at least two shares are required; x
coordinates must be distinct and non-zero (errors name the share index).
Reconstruction is Lagrange interpolation at x = 0 in GF(256) and is
byte-exact for any qualifying subset.

Hex helpers: `vault_shamir_to_hex` (lowercase) and `vault_shamir_from_hex`
(rejects odd length / non-hex as `vault: shamir invalid hex`).

Unseal progress (`VaultUnseal`): `vault_unseal_new(threshold)` (1..255);
`vault_unseal_submit(u, share_ok)` returns a new progress value: an accepted
share increments, a rejected share resets to zero, a completed attempt stays
complete; `vault_unseal_complete`, `vault_unseal_remaining`,
`vault_unseal_reset`. Scalar state is threaded through returns because
`&mut Int` writes are dropped on v0.62.2.

## 8. Auth models (`xiom.vault.auth`)

### 8.1 Token payload

`vault_token_parse(text)` reads a flat object: `client_token` is required
and non-empty; `accessor`, `token_type`, `entity_id` default to "" when
absent; `lease_duration` defaults to 0; `renewable` defaults to false;
`policies` defaults to an empty list. A present field of the wrong kind is an
error (so malformed payloads never pass silently). `vault_token_has_policy`
is case-insensitive; `vault_token_is_root` checks the `root` policy;
`vault_token_default_policy()` is "default".

### 8.2 Lifecycle requests

| Function | Method | Path | Body / headers |
|----------|--------|------|----------------|
| `vault_token_lookup_request(token)` | GET | `/auth/token/lookup-self` | token header |
| `vault_token_renew_request(token, increment)` | PUT | `/auth/token/renew-self` | token header; increment 0 = no body, 1..31536000 = `{"increment":N}` |
| `vault_token_revoke_request(token)` | POST | `/auth/token/revoke-self` | token header |

Tokens must be non-empty and control-free.

### 8.3 AppRole

`vault_approle_role_id_is_valid` / `vault_approle_secret_id_is_valid`
require the canonical 8-4-4-4-12 UUID shape (hex, any case).
`vault_approle_login_path(mount)` is `auth/<mount>/login` (mount validated
like a KV mount). `vault_approle_login_request(mount, role_id, secret_id)`
is a POST with `{"role_id":"..","secret_id":".."}` and validates both UUIDs.
`vault_approle_parse_login(text)` extracts the nested `auth` object (which
must exist and be an object) and parses it with `vault_token_parse`.

## 9. Policy management (`xiom.vault.policy`)

Capabilities are single bits: create=1, read=2, update=4, delete=8, list=16,
sudo=32, deny=64, patch=128 (all = 255). `vault_capability_code` (case
insensitive, 0 unknown), `vault_capability_name` (single-bit canonical name),
`vault_capability_set(names)` (non-empty list, all names must be known),
`vault_capability_set_has`, and `vault_capability_set_render` (bit order,
comma separated; `create,deny`).

`VaultPolicy` is a pair of parallel rule vectors (max 64 rules).
`vault_policy_add` validates the pattern (1..512 printable bytes without
space, CTL, '?' or '#') and requires at least one defined capability bit.

`vault_policy_path_matches(pattern, path)` is a glob matcher implemented as
an iterative dynamic program (no recursion; pairs over 131072 cells do not
match): `*` matches any run of bytes (including '/'), `+` matches one or
more bytes within a single segment (no '/'), any other byte is literal and
case-sensitive.

`vault_policy_effective_caps(p, path)` picks the LONGEST matching pattern;
equal-length matches are unioned, so a DENY in a tie survives.
`vault_policy_decision(p, path, cap)` returns NONE (0) when no rule matches,
DENY (2) when the effective mask has DENY or lacks the requested capability,
ALLOW (1) otherwise; `vault_policy_can` is the ALLOW predicate.

## 10. Test coverage map

`tests/test_conformance.xi` -- 28 deterministic checks, one `fn tN` each:

| Check | Covers |
|-------|--------|
| t1 | method codes, canonical names, case-insensitive and unknown lookup |
| t2 | path normalization: leading slash, collapsed/trailing slashes, errors |
| t3 | request construction, method/path/target accessors, method errors |
| t4 | query strip/clear, canonical target, empty-segment and '#' errors |
| t5 | headers: case-insensitive set/replace/remove, token header, errors |
| t6 | body builder: string escaping, raw/int/bool, empty body, errors |
| t7 | JSON lookup kinds/spans, nested skip, missing key, malformed member |
| t8 | JSON string escapes, NUL/surrogate/kind errors, raw quoted slice |
| t9 | JSON signed integers, booleans, kind errors |
| t10 | JSON string arrays, empty array, non-array/non-string errors |
| t11 | response envelope status range and success predicate |
| t12 | KV v1 path joining and mount/key validation (`//`, spaces, edges) |
| t13 | KV v2 data/metadata/delete/undelete/destroy paths |
| t14 | KV version query, latest vs pinned read target, negative version |
| t15 | KV v2 request methods/paths and versions body composition |
| t16 | version ledger transitions, destroy terminal/idempotent, no aliasing |
| t17 | GF(256) AES-polynomial products, inverses, range errors |
| t18 | Shamir known answer: threshold-2 split bytes and reconstruction |
| t19 | seeded split: any-threshold reconstruction, duplicates, zero x, hex |
| t20 | unseal progress: reset on reject, completion, remaining, reset |
| t21 | token payload: full/defaults, policy membership (case), root |
| t22 | token payload errors: missing/empty token, malformed fields |
| t23 | token lookup/renew/revoke requests, increment body, errors |
| t24 | AppRole UUIDs, login path/request/body, nested auth parse, errors |
| t25 | capability codes/names/masks/render, unknown-name and empty errors |
| t26 | policy glob: exact, `*`, `+`, interior stars, case sensitivity |
| t27 | policy rules: longest-prefix, tie union, deny, decisions, errors |
| t28 | composed client: health/seal/mounts, KV2 CRUD, token plumbing |

## 11. Error catalog

All messages start with `vault:`; offset-bearing messages end in
`at offset N` with N a byte offset into the function's text argument.

Client / core:

| Message |
|---------|
| `vault: unknown method code` / `vault: method code out of range at offset N` |
| `vault: path is empty` / `vault: path is too long` / `vault: path has a control or space byte at offset N` |
| `vault: query is too long` / `vault: query contains '?' or '#' at offset N` / `vault: query has a control or space byte at offset N` / `vault: query has an empty parameter at offset N` |
| `vault: header name is empty` / `vault: header name is too long` / `vault: header name has an invalid character` / `vault: header value is too long` / `vault: header value has a control byte at offset N` / `vault: too many headers` / `vault: header not found: <name>` |
| `vault: token is empty` / `vault: token has a control byte at offset N` |
| `vault: body member name is empty or invalid` / `vault: body raw value is not a JSON scalar` / `vault: body has too many members` / `vault: body text is empty` / `vault: body text has a control byte at offset N` |
| `vault: response status out of range: N` |

JSON:

| Message |
|---------|
| `vault: json expected object at offset N` / `vault: json expected ':' at offset N` / `vault: json expected ',' or '}' at offset N` / `vault: json expected ',' or ']' at offset N` / `vault: json unterminated object at offset N` / `vault: json unterminated array at offset N` |
| `vault: json expected string at offset N` / `vault: json unterminated string at offset N` / `vault: json control byte in string at offset N` / `vault: json unterminated escape at offset N` / `vault: json invalid escape at offset N` / `vault: json truncated escape at offset N` / `vault: json truncated unicode escape at offset N` / `vault: json invalid unicode escape at offset N` / `vault: json NUL escape at offset N` / `vault: json surrogate escape unsupported at offset N` |
| `vault: json invalid number at offset N` / `vault: json invalid literal at offset N` / `vault: json invalid value at offset N` / `vault: json nesting too deep at offset N` |
| `vault: json key not found: <key>` / `vault: json value is not a string` / `vault: json value is not an integer` / `vault: json value is not a boolean` / `vault: json value is not an array` / `vault: json array element is not a string` / `vault: json array is too long` |

KV:

| Message |
|---------|
| `vault: kv mount is empty or invalid` / `vault: kv key is empty or invalid` |
| `vault: kv version out of range: N` / `vault: kv versions list is empty` / `vault: kv versions list is too long` |
| `vault: kv version count out of range: N` / `vault: kv unknown op: N` |
| `vault: kv version N is destroyed` / `vault: kv version N is absent` / `vault: kv version N is deleted` / `vault: kv version N is not deleted` |

Shamir / unseal:

| Message |
|---------|
| `vault: gf byte out of range: N` / `vault: gf has no inverse for zero` |
| `vault: shamir secret length out of range: N` / `vault: shamir share count out of range: N` / `vault: shamir threshold out of range: N` / `vault: shamir coefficient count mismatch: N (want M)` / `vault: shamir share data length mismatch: N` / `vault: shamir needs at least two shares` / `vault: shamir has too many shares` / `vault: shamir share x coordinate is zero at share N` / `vault: shamir duplicate share x coordinate at share N` / `vault: shamir invalid hex` |
| `vault: unseal threshold out of range: N` |

Auth / policy:

| Message |
|---------|
| `vault: token response missing client_token` / `vault: token response has empty client_token` |
| `vault: token renew increment out of range: N` |
| `vault: approle mount is empty or invalid` / `vault: approle role_id is not a UUID` / `vault: approle secret_id is not a UUID` / `vault: approle login response missing auth` / `vault: approle login response auth is not an object` |
| `vault: capability list is empty` / `vault: unknown capability: <name>` |
| `vault: policy pattern is empty or invalid` / `vault: policy rule has no capabilities` / `vault: policy has too many rules` |

Note: error strings from the JSON scanner surface through every auth/kv
caller unchanged (the `vault:` prefix is shared).

## 12. Known limitations and documented simplifications

1. **No I/O, no crypto, no time.** Requests are structures; tokens are
   opaque strings; lease durations are plain integers.
2. **Paths are not encoded.** A space or control byte in a path, query or
   header value is rejected instead of percent-encoded or escaped.
3. **JSON scanner is flat and top-level.** Only top-level members are
   addressable; nested values are validated and skipped. Duplicate keys use
   the first match. Surrogate pairs are rejected (`\uD800`-`\uDFFF`), and
   NUL escapes are rejected so no `Str` is built from bytes containing 0x00.
4. **Body builder is a flat object.** Nested objects/arrays as raw members
   are not accepted by `vault_body_add_raw`; use
   `vault_request_set_body_text` for pre-rendered JSON such as the KV
   versions body.
5. **KV ledger is slot-based.** One slot per version number; a write to a
   live slot overwrites it and a write to a soft-deleted slot revives it.
   Real Vault creates a new version per write and delete/undelete/destroy
   operations apply to whole sets of versions; the request builders and the
   versions body cover those wire shapes, while the ledger documents the
   state semantics.
6. **Policy patterns generalize Vault globs.** Vault documents trailing `*`
   and single-segment `+`; this matcher allows them anywhere. Resolution is
   longest-pattern-first with equal-length union; DENY always overrides.
7. **No HCL policy file parsing.** Capability names are provided directly;
   callers assembling policies from text own the tokenization.
8. **AppRole IDs must be UUID-shaped.** Non-UUID custom role IDs are
   rejected (Vault generates UUIDs; the model is stricter).
9. **`+` matches one or more bytes.** A trailing `+` therefore requires at
   least one byte in the final segment (`secret/+` does not match `secret`).

## 13. Compiler findings (v0.62.2)

* **Child modules cannot call their parent.** A module `xiom.vault.json`
  with `use xiom.vault;` and a call `vault.vault_int_str(7)` fails with
  `error[T001]: cannot call 'vault_int_str' on this expression` (an alias
  does not help); the same call works between sibling modules and a parent
  can import/call a child. This shaped the sibling-only import layout in
  section 3.
* **`&mut Int` scalar writes are dropped**, so unseal progress and all
  scalar state are threaded through return values.
* **Local `Vec[Str]` pushes are fine**; module-level `Vec[Str]` pushes
  mis-lower, so the package has no module-level vectors.
* **Arity/bracket laxness**: every signature was kept single-style
  (`Vec[...]`, `Result[...]`) and audited with a post-green
  `Vec<`/`Result<` grep.
