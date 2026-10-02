# xiom.aws -- SPEC

Pure-XIOM AWS request/signing model. Version 0.1.0.
License: MIT OR Apache-2.0.

## 1. Scope and non-goals

**In scope (deterministic, pure):**

- AWS Signature Version 4 (SigV4) signing: canonical request, string to sign,
  derived signing key, `Authorization` header.
- Credential model: access key / secret key / session token / expiry / source,
  with a resolution chain over caller-supplied candidates.
- Service/request model: service name, region, action, method, path, query,
  endpoint host, headers, payload hash.
- Service registry with explicit case dispatch (global vs regional endpoints,
  signing-name mapping).
- Retry/backoff policy: bounded full-jitter exponential schedule with a
  deterministic integer seed; retryable status/error-code classification.
- Response envelope: status class, success predicate, body-shape
  classification, case-insensitive header lookup.

**Non-goals:** no sockets, no TLS, no clock reads, no environment/profile
reads, no JSON/XML body parsing, no credential storage, no S3 path-style
specialization, no streaming/chunked signing (STREAMING-AWS4-HMAC-SHA256).

## 2. Modules and types

| Module | Contents |
|--------|----------|
| `xiom.aws` | types, constants, canonicalization, signing, credentials, registry, retry, response, date |
| `xiom.aws.base` | SHA-256, HMAC-SHA-256, hex, byte helpers |

```text
AwsCredential { access_key: Str; secret_key: Str; session_token: Str;
                expiry_unix: Int; source: Int }
AwsService    { name: Str; signing_name: Str; host: Str; is_global: Bool }
AwsRequest    { service: Str; region: Str; method: Str; path: Str;
                query: Str; action: Str; payload_hash: Str }
AwsResponse   { status: Int; shape: Int; retryable: Bool }
```

Constants: `AWS_SIGV4_ALGORITHM = "AWS4-HMAC-SHA256"`,
`AWS_SIGV4_TERMINATOR = "aws4_request"`, `AWS_STATUS_*` (0..5),
`AWS_SHAPE_*` (0..4), `AWS_CRED_SOURCE_*` (0..4), `AWS_RETRY_MAX_ATTEMPTS = 5`,
`AWS_RETRY_BASE_MS = 50`, `AWS_RETRY_MAX_MS = 20000`.

## 3. SigV4 signing steps

Given a request, a credential, an amz date `YYYYMMDDTHHMMSSZ` and the signed
headers (parallel name/value vectors):

1. **Canonical request**

   ```text
   Method \n
   CanonicalURI \n
   CanonicalQueryString \n
   CanonicalHeaders \n          (each line "name:value\n"; block ends with \n)
   SignedHeaders \n
   HexSHA256(Payload)
   ```

2. **Credential scope** `date8/region/signing-name/aws4_request`, where
   `date8` is the first 8 characters of the amz date and `signing-name` maps
   `cloudwatch -> monitoring` (identity otherwise).

3. **String to sign**

   ```text
   AWS4-HMAC-SHA256 \n
   amz-date \n
   scope \n
   HexSHA256(CanonicalRequest)
   ```

4. **Signing key** (32 bytes):

   ```text
   kDate    = HMAC-SHA256("AWS4" + secret, date8)
   kRegion  = HMAC-SHA256(kDate, region)
   kService = HMAC-SHA256(kRegion, signing-name)
   kSigning = HMAC-SHA256(kService, "aws4_request")
   ```

5. **Signature** = `Hex(HMAC-SHA256(kSigning, StringToSign))` (lowercase hex).

6. **Authorization header**

   ```text
   AWS4-HMAC-SHA256 Credential=<access-key>/<scope>, SignedHeaders=<sh>, Signature=<sig>
   ```

`aws_sign_v4` implements steps 1-6. `aws_canonical_request`, the individual
canonicalizers, `aws_credential_scope`, `aws_string_to_sign`,
`aws_signing_key`, `aws_signature_hex` and `aws_authorization_header` expose
each step for testing and custom flows.

## 4. Canonicalization rules

### 4.1 Canonical URI

Every byte is percent-encoded as `%XX` (uppercase hex) except the unreserved
set `ALPHA / DIGIT / '-' '.' '_' '~'` and `/`, which is preserved. The path is
not normalized (no dot-segment removal) and is signed as supplied.

### 4.2 Canonical query string

The raw query `k=v&...` is split on `&`; each name and value is URI-encoded
strictly (unreserved set only, `/` encoded), then pairs are sorted by encoded
name and, on ties, by encoded value; pairs are joined with `&`. A parameter
without `=` renders as `name=`. Empty segments are ignored. Encoding is
applied once to the raw input; values that are already encoded are not
double-encoded (callers that hold pre-encoded input must decode first, or rely
on AWS services that expect pre-encoded values being passed through).

### 4.3 Canonical headers

Header names are lowercased. Values are trimmed of leading/trailing SP and HT,
and internal runs of SP/HT collapse to a single space. Lines are sorted by
lowercased name and emitted as `name:value\n`; the block always ends with
`\n`. Duplicate header names are not merged -- the model requires unique names.
The `host` header is required for signing: `aws_canonical_request` fails with
`aws: missing host header` when it is absent.

### 4.4 Signed headers

The lowercased names, sorted by name, joined with `;`.

### 4.5 Payload hash

`HexSHA256` of the payload; `aws_empty_payload_sha256()` returns the constant
`e3b0c442...b855` for body-less requests.

## 5. Credential model

- Validity: `access_key` and `secret_key` non-empty; `expiry_unix <= 0` means
  "never expires"; otherwise the credential is valid only when
  `expiry_unix > now_unix`.
- Resolution chain: `aws_resolve_credential` walks caller-supplied parallel
  vectors (sources, access keys, secret keys, session tokens, expiries) in
  order -- the documented AWS chain order is explicit > environment > profile
  > instance -- and returns the first usable credential. All vectors must have
  equal length.
- A session credential must have its token included as the
  `x-amz-security-token` header by the caller; the signer signs whatever
  headers it is given.

## 6. Service registry

Explicit case dispatch (no lookup tables):

| Service | Host | Global | Signing name |
|---------|------|--------|--------------|
| `iam` | `iam.amazonaws.com` | yes | `iam` |
| `sts` | `sts.amazonaws.com` | yes | `sts` |
| `route53` | `route53.amazonaws.com` | yes | `route53` |
| `cloudfront` | `cloudfront.amazonaws.com` | yes | `cloudfront` |
| `cloudwatch` | `monitoring.{region}.amazonaws.com` | no | `monitoring` |
| any other | `{service}.{region}.amazonaws.com` | no | identity |

Errors: empty service -> `aws: empty service name`; empty region for a regional
service -> `aws: empty region for regional service`.

## 7. Retry / backoff policy

- Retryable statuses: 408, 429, 500, 502, 503, 504.
- Retryable error codes: `Throttling`, `ThrottlingException`,
  `ProvisionedThroughputExceededException`, `RequestTimeout`,
  `RequestTimeoutException`, `SlowDown`, `InternalError`,
  `InternalErrorException`, `ServiceUnavailable`, `TransientError`.
- Full-jitter schedule: for 1-based attempt `a`, the cap is
  `min(base * 2^(a-1), max)`; the delay is `r % (cap + 1)` where `r` is a
  fixed LCG/xorshift mix of `seed` alone. Same inputs always produce the same
  delay; `attempt <= 0` or non-positive `base`/`max` yield 0. The schedule is
  bounded by `max_ms` for any attempt value.

## 8. Response envelope

- Status class: 1xx informational, 2xx success, 3xx redirect, 4xx client
  error, 5xx server error, anything else unknown; 2xx is success.
- Body shape: leading SP/TAB/CR/LF are skipped; empty -> `AWS_SHAPE_EMPTY`;
  first byte `{`/`[` -> JSON; `<` -> XML; otherwise all bytes must be printable
  ASCII or TAB/LF/CR for TEXT, else BINARY.
- `aws_header_find` matches header names case-insensitively and returns the
  first value.
- `aws_response_envelope` composes status, shape and `aws_retryable_status`.

## 9. Date conversion

`aws_amz_date_from_unix(secs)` converts non-negative Unix seconds (UTC) to
`YYYYMMDDTHHMMSSZ` using integer-only Hinnant civil_from_days; negative input
is `aws: negative unix time`. KAT: `1440938160 -> 20150830T123600Z`.

## 10. Error cases (exact messages)

| Message | Raised by |
|---------|-----------|
| `aws: missing method` | canonical request, method empty |
| `aws: missing payload hash` | canonical request, payload hash empty |
| `aws: header name/value count mismatch` | canonical request, header find, sign |
| `aws: missing host header` | canonical request |
| `aws: bad amz date` | credential scope, date8 length != 8 |
| `aws: missing region` / `aws: missing service` | credential scope |
| `aws: missing access key` / `aws: missing secret key` | sign |
| `aws: credential chain arity mismatch` | credential resolution |
| `aws: no usable credentials` | credential resolution |
| `aws: empty service name` | service lookup |
| `aws: empty region for regional service` | service lookup |
| `aws: header not found: <name>` | header find |
| `aws: negative unix time` | amz date conversion |

## 11. Known-answer tests (tests/test_conformance.xi, 27 checks)

- SHA-256: NIST `abc`, empty, 448-bit; `hello world`.
- HMAC-SHA-256: RFC 4231 TC1, TC2, TC3, TC6 (131-byte key).
- SigV4 canonical request (get-vanilla): exact text and SHA-256
  `bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63`.
- SigV4 IAM ListUsers full request (AWS documentation example): signing key
  `c4afb1cc...a4b9`, signature
  `5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7`.
- SigV4 get-vanilla full request (aws-sig-v4-test-suite): signature
  `5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31`.
- Session-token request (service `sts`, `x-amz-security-token` signed):
  signature `10d12af4f59ebc6f28e7962f0a3f38f5649ad8811f1a82d770f13dbf94d9831c`.
- Backoff: exact deterministic values (35 / 83 / 705, bounds, seed divergence).

## 12. v0.62.2 implementation notes

- **Stdlib crypto gap:** `xiom.crypto` and `xiom.crypto.hash` fail to link from
  a package (`undefined symbol: xiom_sha256_hash`), so SHA-256/HMAC are
  hand-rolled in `xiom.aws.base` (saml precedent) and pinned by the KATs above.
- Free functions only, no `match`, no methods, no `Vec[StructType]`, no
  floats; `Ok`/`Err` only inside leaf helpers; Str equality via
  `compare.str_compare`; byte reads widened with `& 0xFF`.
- One model module plus the primitives sibling: v0.62.2 rejects child ->
  parent module imports, so a finer split would duplicate shared types or
  constants.
