# xiom.aws

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.0` on the XIOM registry.
> **Scope:** SigV4 signing, credential model and resolution chain, service and
> request model, service registry, retry/backoff policy, response envelope.
> **Deps:** stdlib only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`, `xiom.convert`).

`xiom.aws` models the AWS request surface: it canonicalizes, signs and
classifies requests/responses, while the caller owns transport, clocks and
secret storage. Every input (region, amz date, credentials, response bytes) is
passed in, so every result is reproducible and testable offline.

## Modules

| Module | Role |
|--------|------|
| `xiom.aws` | public model: SigV4 signing, credentials, service registry, retry policy, response envelope |
| `xiom.aws.base` | in-package pure-XIOM SHA-256 / HMAC-SHA-256 / hex primitives |

## Example

```xiom
use xiom.aws;
use xiom.aws.base;

fn sign_get() -> Result[Str, Str] {
  let req = AwsRequest{
    service: "iam";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "Action=ListUsers&Version=2010-05-08";
    action: "ListUsers";
    payload_hash: base.aws_empty_payload_sha256();
  };
  let cred = AwsCredential{
    access_key: "AKIDEXAMPLE";
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  var names = Vec[Str].new();
  names.push("Host");
  names.push("X-Amz-Date");
  var values = Vec[Str].new();
  values.push("iam.amazonaws.com");
  values.push("20150830T123600Z");
  return aws_sign_v4(&req, &cred, "20150830T123600Z", &names, &values);
}
```

The returned string is the `Authorization` header value; the caller sends it
over its own transport with the same headers that were signed.

## Surface

- **Signing:** `aws_uri_encode`, `aws_canonical_uri`, `aws_canonical_query`,
  `aws_canonical_headers`, `aws_signed_headers`, `aws_canonical_request`,
  `aws_date8`, `aws_credential_scope`, `aws_string_to_sign`,
  `aws_signing_key`, `aws_signature_hex`, `aws_authorization_header`,
  `aws_sign_v4`.
- **Credentials:** `AwsCredential`, `AWS_CRED_SOURCE_*`,
  `aws_credential_source_name`, `aws_credential_valid`,
  `aws_resolve_credential` (parallel-vector resolution chain).
- **Services:** `AwsService`, `aws_service_lookup`, `aws_service_host`.
- **Requests:** `AwsRequest` (scalar fields; headers stay in caller-owned
  parallel `Vec[Str]`s).
- **Retry:** `aws_retryable_status`, `aws_retryable_error_code`,
  `aws_backoff_delay_ms`, `AWS_RETRY_*`.
- **Response:** `AwsResponse`, `aws_response_class`, `aws_response_is_success`,
  `aws_body_shape`, `aws_header_find`, `aws_response_envelope`.
- **Primitives:** `xiom.aws.base` (`aws_sha256`, `aws_hmac_sha256`, hex,
  bytes helpers).

## Tests

```powershell
.\scripts\port.ps1 -Package xiom-aws -TimeoutSec 60
```

27 conformance checks, 0 failures; known-answer vectors from NIST FIPS 180-4,
RFC 4231 and the AWS SigV4 documentation/test-suite examples (see SPEC.md).

## Implementation notes (v0.62.2)

The installed stdlib crypto does not link from a package (`undefined symbol:
xiom_sha256_hash` for both `xiom.crypto` and `xiom.crypto.hash`), so SHA-256
and HMAC-SHA-256 are hand-rolled in `xiom.aws.base` following the `xiom.saml`
precedent. The library is intentionally a single model module plus the
primitives sibling: with v0.62.2 a child module cannot import its parent, so a
finer split would force type duplication.

## License

MIT OR Apache-2.0.
