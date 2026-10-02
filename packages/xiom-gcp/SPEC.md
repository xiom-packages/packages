# xiom.gcp -- specification

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Pure-XIOM model of the Google Cloud provider surface. Version 0.1.0,
compiler v0.62.2, stdlib only.

## 1. Scope and non-goals

**In scope.** Deterministic, caller-driven models of:

- the GCP resource-name grammar (projects, regions, zones, resource paths);
- a six-service registry with hosts, API versions and endpoint bases;
- GCS buckets, objects, generations, preconditions and the ACL shape;
- GCE machine types, the instance lifecycle, metadata and instance paths;
- Cloud Functions runtimes, entry points, triggers, deploy validation and
  invoke classification;
- BigQuery identifiers, schemas, row-page framing and jobs;
- Pub/Sub topics, subscriptions, publish validation, ack ids and deadlines;
- service-account key shape, OAuth scopes, the token envelope and the JWT
  claim set.

**Out of scope (deliberately).**

- **No transport.** No HTTP client, no sockets, no URLs are fetched. Paths and
  endpoint bases are strings for the caller to use.
- **No FFI.** Every module is pure XIOM over `xiom.std`.
- **No clocks.** All timestamps (`expires_in`, `iat`, `exp`) are integers
  supplied by the caller; `exp` is validated against `iat` only.
- **No crypto and no signing.** On v0.62.2 the stdlib `xiom.crypto` does not
  link from a package (`undefined symbol: xiom_sha256_hash`), so the model
  validates key material shape and renders JWT claim-set bytes, but never
  signs. `gca_jwt_signing_supported()` returns `false`.
- **No IAM policy evaluation, no SQL execution, no service quotas.**

Every function is a free function. There are no methods, no `Vec[StructType]`,
no `Vec[Float64]` and no `&mut` scalar parameters; scalar state travels
through returns.

## 2. Module layout

| Module | File | Contents |
|--------|------|----------|
| `xiom.gcp` | `src/gcp.xi` | resource names, service registry, endpoints |
| `xiom.gcp.core` | `src/gcp_core.xi` | shared text/JSON helpers |
| `xiom.gcp.storage` | `src/gcp_storage.xi` | GCS model |
| `xiom.gcp.compute` | `src/gcp_compute.xi` | GCE model |
| `xiom.gcp.cloudfunctions` | `src/gcp_cloudfunctions.xi` | Cloud Functions model |
| `xiom.gcp.bigquery` | `src/gcp_bigquery.xi` | BigQuery model |
| `xiom.gcp.pubsub` | `src/gcp_pubsub.xi` | Pub/Sub model |
| `xiom.gcp.auth` | `src/gcp_auth.xi` | service-account/auth model |

Import direction is **sibling-to-sibling only** (compiler v0.62.2 rejects a
child importing its parent). The service modules import `xiom.gcp.core`; the
main module imports `xiom.gcp.core`. Structs are constructed with their bare
imported names: qualified literals such as `storage.GcsPreconditions` are
rejected by the checker.

Error messages are plain `"gcp: <what>"` strings produced by
`core.gcp_err`-style concatenation. Every validator returns
`Result[Str, Str]` with `Ok("")` on success and the first error message on
failure, except the payload-returning functions listed below.

## 3. Resource names (`xiom.gcp`)

### 3.1 Name rules (documented subset)

- **Project id:** 6..30 bytes; lowercase ASCII letters, digits, `-`;
  lowercase letter first; lowercase letter or digit last.
- **Region:** 2..63 bytes; lowercase letters, digits, `-`; lowercase letter
  first; lowercase letter or digit last.
- **Zone:** a valid region, `-`, exactly one lowercase letter
  (`us-central1-a`). The region of a zone is the text before the last `-`.
- **Collection token:** 1..64 ASCII letters, mixed case allowed
  (`instances`, `machineTypes`, `sslCertificates`).
- **Resource name leaf:** 1..255 bytes, no `/`.

### 3.2 Paths

- `gcp_project_path(p)` = `projects/{p}`.
- `gcp_zone_path(p, z)` = `projects/{p}/zones/{z}`.
- `gcp_region_path(p, r)` = `projects/{p}/locations/{r}`.
- `gcp_global_path(p)` = `projects/{p}/global`.
- `gcp_resource_path(p, collection, location, name)` dispatches on `location`:
  - `""` -> `projects/{p}/{collection}/{name}`;
  - `"global"` -> `projects/{p}/global/{collection}/{name}`;
  - a valid zone -> `projects/{p}/zones/{z}/{collection}/{name}`;
  - a valid region -> `projects/{p}/locations/{r}/{collection}/{name}`;
  - otherwise an `invalid location` error.

### 3.3 Parsing

`gcp_parse_resource(path)` splits on `/` and accepts:

| Segments | Form | Result |
|----------|------|--------|
| 2 | `projects/{p}` | project only; kind/location/name `""` |
| 4 | `projects/{p}/{c}/{n}` | no location |
| 5 | `projects/{p}/global/{c}/{n}` | location `"global"` |
| 6 | `projects/{p}/zones/{z}/{c}/{n}` | location = zone |
| 6 | `projects/{p}/locations/{r}/{c}/{n}` | location = region |
| other | -- | `gcp: unsupported resource path` |

The first segment must be `projects`; the project id is validated; the
collection and name leaves are validated; a 6-segment path with a `zones`
or `locations` second segment validates the zone/region. The struct payload
returns through leaf `Ok`/`Err` helpers.

### 3.4 Service registry

| Code | Name | Host | Version | Global? |
|------|------|------|---------|---------|
| 1 | storage | storage.googleapis.com | v1 | yes |
| 2 | compute | compute.googleapis.com | v1 | no |
| 3 | cloudfunctions | cloudfunctions.googleapis.com | v1 | no |
| 4 | bigquery | bigquery.googleapis.com | v2 | yes |
| 5 | pubsub | pubsub.googleapis.com | v1 | yes |
| 6 | iam | iam.googleapis.com | v1 | yes |

`gcp_endpoint_base(code)` = `https://{host}/{version}`; unknown codes return
`gcp: unknown service code: N`.

## 4. Cloud Storage (`xiom.gcp.storage`)

### 4.1 Names and paths

- **Bucket:** 3..63 bytes; lowercase letters, digits, `-`, `_`, `.`;
  lowercase letter or digit first and last; no `..` run; no leading `goog`;
  no `google` substring.
- **Object:** 1..1024 bytes; not `"."` or `".."`; no CR or LF.
- `gcs_bucket_path(b)` = `b/{b}`.
- `gcs_object_path(b, o)` = `b/{b}/o/{encoded}` where unreserved RFC 3986
  bytes (`A-Z a-z 0-9 - . _ ~`) and `/` stay literal and every other byte
  becomes `%XX` with **uppercase** hex.
- `gcs_generation_is_valid(g)` is `g >= 1`;
  `gcs_generation_path(b, o, g)` appends `?generation={g}`.

### 4.2 Preconditions

`GcsPreconditions` carries the four integer preconditions; `0` means unset.

- Negative values are errors.
- `ifGenerationMatch > 0` with `ifGenerationNotMatch > 0` is a conflict.
- `ifMetagenerationMatch > 0` with `ifMetagenerationNotMatch > 0` is a
  conflict.
- `gcs_preconditions_query` renders non-zero pairs in the fixed order
  ifGenerationMatch, ifGenerationNotMatch, ifMetagenerationMatch,
  ifMetagenerationNotMatch, separated by `&` after a leading `?`; all-unset
  renders `""`.

### 4.3 ACL shape

- Roles: `READER`, `WRITER`, `OWNER`.
- Entities: `allUsers`, `allAuthenticatedUsers`, `user-<x>`, `group-<x>`,
  `domain-<x>` (each with a non-empty suffix), and `project-<team>-<project>`
  (non-empty, containing `-`).
- `gcs_acl_entry_validate(entity, role)` returns `Ok("")` or the first
  invalid field.

## 5. Compute Engine (`xiom.gcp.compute`)

### 5.1 Instance lifecycle

| Code | Status |
|------|--------|
| 0 | UNSPECIFIED (also the unknown-name code) |
| 1 | PROVISIONING |
| 2 | STAGING |
| 3 | RUNNING |
| 4 | STOPPING |
| 5 | SUSPENDING |
| 6 | SUSPENDED |
| 7 | REPAIRING |
| 8 | TERMINATED |

Allowed transitions (all other pairs are false, including self-transitions):

```
PROVISIONING -> STAGING
STAGING      -> RUNNING
RUNNING      -> STOPPING | SUSPENDING | REPAIRING
STOPPING     -> TERMINATED
SUSPENDING   -> SUSPENDED
SUSPENDED    -> RUNNING
REPAIRING    -> RUNNING | TERMINATED
TERMINATED   -> PROVISIONING
```

`gce_status_name(0)` = `"UNSPECIFIED"`; out-of-range codes return
`gcp: unknown instance status code: N`.

### 5.2 Machine types

Decomposed as `{family}-{series}-{size}` around the first and second `-`:

- known families: `e2 n1 n2 n2d c2 c2d c3 c3d t2d t2a m1 m2 m3 a2 a3 g2
  custom`;
- 1..64 bytes, lowercase letters/digits/hyphens, letter or digit first and
  last;
- missing segments stay `""` (`e2-micro` -> e2/micro/"").

`gce_machine_type_path(p, z, mt)` =
`projects/{p}/zones/{z}/machineTypes/{mt}`.

### 5.3 Instances and metadata

- **Instance name:** DNS-1035 label (1..63, lowercase letter first, letter or
  digit last, lowercase letters/digits/hyphens inside).
- `gce_instance_path(p, z, n)` =
  `projects/{p}/zones/{z}/instances/{n}`.
- **Metadata key:** 1..128 bytes; lowercase letter first; lowercase
  letters/digits/hyphens; letter or digit last; must not start with `google`
  or `ssh-keys`.
- **Metadata value:** up to 262144 bytes.

## 6. Cloud Functions (`xiom.gcp.cloudfunctions`)

### 6.1 Runtimes

| Code | Runtime | Language | Gen2 subset |
|------|---------|----------|-------------|
| 1 | nodejs20 | nodejs | yes |
| 2 | nodejs22 | nodejs | yes |
| 3 | python310 | python | no |
| 4 | python311 | python | no |
| 5 | python312 | python | yes |
| 6 | go121 | go | no |
| 7 | go122 | go | yes |
| 8 | java17 | java | no |
| 9 | java21 | java | yes |
| 10 | dotnet6 | dotnet | no |
| 11 | dotnet8 | dotnet | yes |
| 12 | ruby32 | ruby | no |
| 13 | php82 | php | yes |

Unknown names map to code 0 (`gcf_runtime_is_valid` false).

### 6.2 Entry points and triggers

- **Entry point:** 1..63 bytes; ASCII letter or `_` first; then ASCII
  letters/digits/`_`.
- **HTTP trigger (1):** event type, resource and retry policy must all be
  absent/`false`.
- **Event trigger (2):** event type must be non-empty and contain `.`;
  resource must be non-empty and contain `/`; retry is free.
- Any other kind returns `gcp: unknown trigger kind: N`.

### 6.3 Deploy validation

`GcfDeploy` fields: name, runtime, entry_point, memory_mb, timeout_sec,
max_instances, trigger_kind, event_type, resource, retry.

- name: DNS-1035 label;
- runtime: a modeled runtime;
- entry point: per 6.2;
- memory: 128..32768 MB;
- timeout: 1..3600 s for HTTP triggers, 1..540 s for event triggers;
- max_instances: 0..1000 (0 = unset);
- trigger fields: per 6.2.

`gcf_deploy_path(p, r, n)` =
`projects/{p}/locations/{r}/functions/{n}`.

### 6.4 Invoke model

| Code | Class | Condition |
|------|-------|-----------|
| 0 | UNKNOWN | status outside 100..599 |
| 1 | OK | 2xx without error flag |
| 2 | APP_ERROR | 2xx with error flag |
| 3 | RETRY | 429 or 503 |
| 4 | FAIL | any other HTTP status |

`gcf_invoke_url(region, project, name)` renders the gen1 shape
`https://{region}-{project}.cloudfunctions.net/{name}`.

## 7. BigQuery (`xiom.gcp.bigquery`)

### 7.1 Identifiers

- **Dataset/table id:** 1..1024 bytes; ASCII letter or `_` first; ASCII
  letters/digits/`_`.
- **Field name:** 1..300 bytes, same alphabet.
- `bq_qualified_name(p, d, t)` = `{p}.{d}.{t}`.

### 7.2 Schema

| Type code | Name | | Type code | Name |
|-----------|------|-|-----------|------|
| 1 | STRING | | 8 | TIMESTAMP |
| 2 | BYTES | | 9 | DATE |
| 3 | INTEGER | | 10 | TIME |
| 4 | FLOAT | | 11 | DATETIME |
| 5 | NUMERIC | | 12 | GEOGRAPHY |
| 6 | BIGNUMERIC | | 13 | JSON |
| 7 | BOOL | | 14 | RECORD |

Modes: 1 NULLABLE, 2 REQUIRED, 3 REPEATED.

`bq_schema_validate(names, types, modes)` takes **parallel caller-owned
vectors** (no `Vec[StructType]`): the three lengths must match, there must be
1..10000 fields, each triple must validate, and field names must be unique
case-insensitively (`compare.str_compare_ignore_case`).

### 7.3 Row-page framing

`bq_page_frame(offset, page_size, total)` with `0 <= offset <= total`,
`1 <= page_size <= 100000`, `total >= 0`:

```
remaining = total - offset
count     = min(page_size, remaining)
has_more  = offset + count < total
```

`bq_page_token(page)` is `"offset={offset+count}"` when `has_more`, else `""`.
The page struct returns through leaf helpers.

### 7.4 Jobs

- Types: 1 QUERY, 2 LOAD, 3 EXTRACT, 4 COPY.
- States: 1 PENDING, 2 RUNNING, 3 DONE.
- Transitions: PENDING -> RUNNING, PENDING -> DONE, RUNNING -> DONE.
- `bq_job_id_is_valid` follows the dataset-id rule;
  `bq_job_path(p, j)` = `projects/{p}/jobs/{j}`.

## 8. Pub/Sub (`xiom.gcp.pubsub`)

### 8.1 Names and paths

- **Topic/subscription name:** 3..255 bytes; ASCII letter first; then ASCII
  letters/digits/`-`/`_`/`.`/`~`/`+`/`%`.
- `ps_topic_path(p, t)` = `projects/{p}/topics/{t}`;
  `ps_subscription_path(p, s)` = `projects/{p}/subscriptions/{s}`.

### 8.2 Publishing

`ps_publish_validate(data, attr_names, attr_values, ordering_key)`:

- data: 1..10000000 bytes;
- attribute vectors must have equal lengths and at most 100 entries;
- attribute names: 1..256 bytes and must not start with `goog`
  (case-insensitively, `ps_attr_name_is_reserved`);
- attribute values: at most 1024 bytes;
- ordering key: at most 1024 bytes and not `goog`-prefixed.

### 8.3 Ack and subscriptions

- **Ack id:** 1..1024 printable non-space ASCII bytes (33..126).
- **Ack deadline:** 10..600 s; `ps_ack_deadline_clamp` clamps into range;
  `ps_ack_deadline_extend(received, extension)` requires both in 0..600 and
  returns `min(600, received + extension)`.
- **Subscription:** kind 1 PULL requires an empty push endpoint; kind 2 PUSH
  requires an `https://` endpoint; ack deadline 10..600; retention
  600..604800 s (10 minutes .. 7 days).

## 9. Auth (`xiom.gcp.auth`)

### 9.1 Service-account key

`GcaServiceAccountKey` fields: key_type, project_id, private_key_id,
private_key, client_email, client_id, token_uri. Validation requires:

- `key_type == "service_account"`;
- project id 1..63 bytes;
- non-empty `private_key_id` and `client_id`;
- `private_key` containing `BEGIN PRIVATE KEY`;
- `client_email` containing `@` and ending in `.gserviceaccount.com`;
- `token_uri == "https://oauth2.googleapis.com/token"`.

The private key is never decoded or verified.

### 9.2 OAuth scopes

A scope is `https://www.googleapis.com/auth/` followed by 1+ bytes from
lowercase letters/digits/`.`/`-`/`_`. `gca_scope_list_join` joins a non-empty
list with single spaces; `gca_scope_list_has` is an exact membership test.
Constants: `GCA_SCOPE_CLOUD_PLATFORM`,
`GCA_SCOPE_DEVSTORAGE_READ_WRITE`, `GCA_SCOPE_BIGQUERY`, `GCA_SCOPE_PUBSUB`,
`GCA_SCOPE_COMPUTE`.

### 9.3 Token envelope

`gca_token_json_parse(json)` scans a **flat** JSON object for
`access_token` (string), `token_type` (string) and `expires_in` (integer).
The scanner supports `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t` escapes
(`\uXXXX` digits are preserved literally; the subset is documented).
Missing fields return `gcp: token JSON missing field: <name>`.
`gca_token_is_valid` requires a non-empty access token, `expires_in >= 1` and
`token_type == "Bearer"`. The token struct returns through leaf helpers.

### 9.4 JWT claim set (signing out of scope)

`GcaJwtClaims` fields: issuer, scope, audience, issued_at, expires_at.

- issuer must contain `@` and end in `.gserviceaccount.com`;
- scope must be a non-empty space-separated list of valid scopes;
- audience must be non-empty;
- `issued_at >= 0`; `0 < expires_at - issued_at <= 3600`.

`gca_jwt_claims_json` renders exactly the bytes to sign, in the fixed field
order `iss, scope, aud, iat, exp`, e.g.:

```
{"iss":"svc@my-proj-1.iam.gserviceaccount.com","scope":"https://www.googleapis.com/auth/cloud-platform","aud":"https://oauth2.googleapis.com/token","iat":1700000000,"exp":1700003600}
```

`gca_jwt_signing_supported()` returns `false`: signing must be done by the
caller with a tool that links a crypto library (see section 1).

## 10. Conformance suite

`tests/test_conformance.xi` (module `gcp_tests`) runs 28 named checks and
returns the failure count; `main` prints `[PASS]`/`[FAIL]` per check.

| # | Area | Check |
|---|------|-------|
| 1 | resource | project/zone/region/global paths and invalid project |
| 2 | resource | project/region/zone validators and zone->region |
| 3 | resource | parse zone/region/global paths and error forms |
| 4 | registry | service codes, hosts, versions and endpoints |
| 5 | gcs | bucket names and bucket path |
| 6 | gcs | object names, encoded object path and generations |
| 7 | gcs | precondition query and conflict rules |
| 8 | gcs | ACL roles, entities and entry validation |
| 9 | gce | status code/name dispatch |
| 10 | gce | instance lifecycle transitions |
| 11 | gce | machine type validation, parse and path |
| 12 | gce | metadata keys and instance naming/path |
| 13 | cloudfunctions | runtime registry, language and generation |
| 14 | cloudfunctions | HTTP/event trigger validation |
| 15 | cloudfunctions | entry point and deploy validation |
| 16 | cloudfunctions | deploy path, invoke class and gen1 URL |
| 17 | bigquery | identifier rules and qualified names |
| 18 | bigquery | type registry and schema validation |
| 19 | bigquery | row-page framing and next-page token |
| 20 | bigquery | job types, states and transitions |
| 21 | pubsub | topic/subscription names and paths |
| 22 | pubsub | publish validation and reserved attributes |
| 23 | pubsub | ack ids, deadline clamp and extension |
| 24 | pubsub | pull/push subscription validation |
| 25 | auth | service-account key shape |
| 26 | auth | OAuth scope validation and joining |
| 27 | auth | flat token-envelope JSON parsing |
| 28 | auth | JWT claim-set validation, rendering and no-signing boundary |

Run:

```powershell
.\scripts\port.ps1 -Package xiom-gcp -TimeoutSec 60
```

Expected: `port: PASS (program_exit=0)` with `passed=28 failed=0`.

## 11. Determinism and limits

- All functions are pure; there is no global mutable state, no module-level
  vector, no clock and no randomness.
- Every loop has a strictly increasing counter; scanners are bounded by the
  input length.
- Byte widening always uses `(b as Int) & 0xFF`; string equality always goes
  through `xiom.string.compare`; JSON escaping emits `\u00xx` with lowercase
  hex.
- BigQuery schema validation is O(n^2) in the field count (duplicate scan);
  all other validators are linear in their inputs.

## 12. Versioning and license

Version 0.1.0 models the service surface as documented at the 2026-10 model
snapshot; additions are backwards-compatible, breaking changes require a
minor bump. License: MIT OR Apache-2.0.
