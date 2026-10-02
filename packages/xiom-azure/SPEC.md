# xiom.azure -- specification

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Pure-XIOM model of the Microsoft Azure provider surface. No network, no FFI,
no clocks, no crypto: every input is supplied by the caller and every result
is deterministic. Version 0.1.0, category `systems`, dependency `xiom.std`.

## Package layout

| Module | Source | Role |
|--------|--------|------|
| `xiom.azure` | `src/azure.xi` | entry registry: hosts, provider namespaces, api-versions, `azure_version` |
| `xiom.azure.base` | `src/azure_base.xi` | shared helpers (compare, slicing, GUID shape, joins) |
| `xiom.azure.arm` | `src/azure_arm.xi` | ARM resource ids |
| `xiom.azure.storage` | `src/azure_storage.xi` | blob storage |
| `xiom.azure.compute` | `src/azure_compute.xi` | virtual machines |
| `xiom.azure.functions` | `src/azure_functions.xi` | Functions apps, routes, triggers |
| `xiom.azure.cosmos` | `src/azure_cosmos.xi` | Cosmos DB |
| `xiom.azure.servicebus` | `src/azure_servicebus.xi` | Service Bus |
| `xiom.azure.auth` | `src/azure_auth.xi` | Entra ID token envelopes |

All modules declare `module <dotted.name>` (no semicolon) and are free
functions only: no methods, no generics, no `match`, no `&mut` scalar
parameters, no `Vec[StructType]` and no module-level mutable state. Errors
are `Result[T, Str]` with messages prefixed `azure: `; `Ok`/`Err` are
constructed only in the per-module `_ok_*` / `_err_*` leaf helpers.

## 1. ARM resource ids (`xiom.azure.arm`)

Canonical shapes:

```
/subscriptions/{sub}
/subscriptions/{sub}/resourceGroups/{rg}
/subscriptions/{sub}/resourceGroups/{rg}/providers/{ns}/{type}/{name}
/subscriptions/{sub}/resourceGroups/{rg}/providers/{ns}/{t1}/{n1}/{t2}/{n2}
```

- A leading `/` is required; empty segments, a trailing `/` and `//` are
  rejected.
- The keywords `subscriptions`, `resourceGroups` and `providers` match
  case-insensitively; names keep their casing.
- After the provider namespace the segments are position-dependent pairs:
  odd segments form `type_path`, even segments `resource_name` (each joined
  with `/`); a count of zero pairs is a provider root and is rejected, an odd
  count is rejected ("must end with a name").
- `parent_id` is the id without the last pair; for a top-level resource it is
  the provider scope.
- `scope` is `AZURE_ARM_SCOPE_SUBSCRIPTION` / `_RESOURCE_GROUP` /
  `_RESOURCE`; `azure_arm_scope_name` names them.
- Names are 1..260 printable ASCII bytes without `/ \ ? # % & < > * : | = " '`.
- `azure_arm_resource_id` rebuilds the canonical id and enforces matching
  type/name segment counts.
- `azure_guid_valid` (base) checks the 8-4-4-4-12 GUID shape.

Tests: t1 (scopes, case-insensitivity), t2 (fields/parent/raw), t3 (child +
build round-trip), t4 (errors, GUID, scope names).

## 2. Blob storage (`xiom.azure.storage`)

- Account: 3..24 lowercase letters/digits.
- Container: 3..63 lowercase letters/digits/hyphens, alphanumeric first and
  last character, no `--`.
- Blob: 1..1024 printable ASCII bytes, no `\ ? #`, no leading `/`, no `//`,
  no trailing `/` or `.`.
- `azure_blob_url` -> `https://{account}.blob.core.windows.net/{container}/{blob}`.
- ETag: `"value"` (strong) or `W/"value"` (weak), value 1..128 bytes without
  `"` or control bytes. `azure_etag_strong_equal` requires both strong and
  byte-equal values; `azure_etag_weak_equal` ignores the weak marker.
- `azure_precondition_allows(op, exists, current_etag, requested_etag)`:
  `NONE` allows always; `IF_MATCH` requires existence and, unless the request
  is `*`, a byte-equal current ETag; `IF_NONE_MATCH` allows a missing blob or
  a differing ETag, `*` allows only a missing blob; unknown ops deny.
  Comparison is on the raw header strings (callers pass what they received).
- Block ids: 1..64 base64 characters; a list holds 1..50,000 ids of equal
  length. `azure_block_list_resolve` returns the requested ids joined with
  `,` after checking every id against the committed and staged lists.
- Names: `azure_blob_tier_name` (hot/cool/archive), `azure_blob_type_name`
  (block/append/page), `azure_lease_state_name` (available/leased/breaking/
  broken); unknown values render `unknown`.

Tests: t5 (names), t6 (blob names + URL), t7 (ETag), t8 (preconditions),
t9 (blocks and property names).

## 3. Virtual machines (`xiom.azure.compute`)

Pinned size table (`azure_vm_size_lookup`, case-insensitive):
`Standard_B1s` 1/1024/2, `Standard_B2s` 2/4096/4, `Standard_D2s_v5`
2/8192/4, `Standard_D4s_v5` 4/16384/8, `Standard_E2s_v5` 2/16384/4 and
`Standard_F2s_v2` 2/4096/4 (vCPUs / MiB / max data disks).
`azure_vm_size_name_by_shape` returns the first documented match or `""`.

Power states follow ARM `PowerState/<state>`:

```
starting -> running | stopped        running -> stopping | deallocating | restarting
stopping -> stopped                  stopped -> starting | deallocating
deallocating -> deallocated          deallocated -> starting
restarting -> running
```

Equal states are an idempotent observation and `unknown` transitions in both
directions; everything else is illegal. `azure_vm_power_can_start` is true
for stopped/deallocated, `azure_vm_power_can_deallocate` for running/stopped.

Locations: `azure_location_canonical` lowercases and drops spaces, hyphens
and underscores ("West Europe" -> "westeurope"); `azure_location_valid`
checks a pinned 19-region subset. Tags are parallel string vectors with
1..512-byte names (without `< > % & \ ? /`), values up to 256 bytes and
case-insensitively unique names; `azure_tags_get` looks up case-insensitively.

Tests: t10 (sizes), t11 (power), t12 (locations/tags).

## 4. Functions (`xiom.azure.functions`)

- App name: 2..60 chars, lowercase letters/digits/hyphens, alphanumeric first
  and last. Runtimes: dotnet, node, python, java, powershell, custom.
  `azure_function_app_lookup` validates name, location (via the compute
  module), runtime and version; `azure_function_default_hostname` returns
  `{app}.azurewebsites.net`.
- Routes: `""` (function root) or up to 32 non-empty segments of literals
  (`[A-Za-z0-9._~-]`) and whole-segment placeholders `{name}`,
  `{name:constraint}` and `{name:constraint?}`; at most 16 placeholders and
  512 bytes. Names are 1..32 characters, first a letter or `_`. Constraints:
  alpha, int, long, bool, guid, float, datetime, string.
  `azure_route_parameter_names` returns the comma-joined names;
  `azure_route_match` requires equal segment counts, compares literals
  case-insensitively, checks constraints and lets `?` placeholders match an
  empty segment.
- Triggers: methods CSV (1..8 of GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/
  TRACE, case-insensitive, surrounding spaces trimmed) and auth level
  anonymous/function/admin. Function keys are 1..128 URL-safe base64
  characters. `azure_function_invoke_url` yields
  `https://{app}.azurewebsites.net/{route}` (leading `/` ignored).
- Status classes mirror 1xx..5xx; retryable statuses are 408, 429, 500, 502,
  503, 504.

Tests: t13 (apps), t14 (routes), t15 (matching), t16 (triggers/invoke/status).

## 5. Cosmos DB (`xiom.azure.cosmos`)

- Database/container/document names: 1..255 printable bytes without
  `/ \ ? #`.
- Partition key path: leading `/`, 1..3 non-empty segments, 2..256 bytes,
  no `? # \` or control bytes, no trailing `/`. Values: 1..1024 printable
  bytes without `/ \ ? #`.
- Header codec: `azure_cosmos_partition_key_header` renders the single-value
  REST form `["value"]`; `..._parse` accepts only that form (composite
  headers, escapes and extra whitespace are rejected).
- TTL: `-1` (no expiry) or 1..2^31-1; `0` is invalid.
- Consistency levels: strong, bounded_staleness, session, consistent_prefix,
  eventual.
- Throughput: `azure_cosmos_throughput_normalize` clamps to at least 400,
  rounds up to the next 100 and caps at 1,000,000.
- Status names: 400 BadRequest, 401 Unauthorized, 403 Forbidden, 404
  NotFound, 408 RequestTimeout, 409 Conflict, 412 PreconditionFailed, 413
  RequestEntityTooLarge, 429 TooManyRequests, 449 RetryWith, 503
  ServiceUnavailable; retryable: 408/429/449/503.
- Document path: `dbs/{db}/colls/{coll}/docs/{id}`.

Tests: t17 (names/partition keys), t18 (TTL/document/consistency), t19
(throughput/status/path).

## 6. Service Bus (`xiom.azure.servicebus`)

- Entity names: 1..260 chars, alphanumeric first and last, otherwise
  letters/digits/`.`/`-`/`_`, without `..` or `--`. Namespace names: 6..50
  chars, letters/digits/hyphens, alphanumeric first and last.
- Queue: lock duration 5..300 s (default 30), max delivery count 1..2000
  (default 10), session and dead-letter flags. URLs:
  `https://{ns}.servicebus.windows.net/{queue}`; subscription path
  `{topic}/subscriptions/{subscription}`.
- Message states: active, deferred, scheduled, dead_letter, completed.
  Actions: active + complete -> completed; + abandon/lock-expire -> active;
  + dead-letter -> dead_letter; + defer -> deferred; deferred + receive ->
  active; deferred + dead-letter -> dead_letter; scheduled + due -> active;
  dead_letter and completed are terminal for these actions.
- Lock expiry: a lock at `lock_expires_at` expires when `now >= lock_expires_at`
  (0 means no lock). A message is dead-lettered when its delivery count
  exceeds the max. Dead-letter reasons: MaxDeliveryCountExceeded,
  TTLExpiredException, HeaderSizeExceeded (case-insensitive). Scheduled
  delays are 1..604800 s. Rule filters are `$Default` or a 1..1024-byte
  printable expression.

Tests: t20 (names/queue/URLs), t21 (states and rules).

## 7. Entra ID tokens (`xiom.azure.auth`)

- Tenant id: GUID or domain (1..253 chars, alphanumeric ends, no `..`);
  client id: GUID.
- Scope: `https://{host}/.default` with a host without `/` or whitespace.
  `azure_scope_for_resource` appends the suffix (idempotent, trailing `/`
  removed); `azure_scope_resource` strips it.
- Endpoints: `https://login.microsoftonline.com/{tenant}` and
  `.../oauth2/v2.0/token`.
- Token envelope: 1..4096-byte printable access token, `Bearer`
  (case-insensitive) type, positive lifetime, valid scope, optional refresh
  token. Expiry: `azure_token_expires_at` adds the lifetime (non-negative
  acquisition time), `azure_token_is_expired` refreshes early by a
  caller-supplied skew; `azure_bearer_header` renders `Bearer {token}`.
- Identity chain: sources none, client_secret, certificate, managed_identity,
  cli, environment. An identity is usable when the source is known, tenant
  and client ids validate, secret/certificate sources carry a non-empty
  secret and the credential is not expired (0 = never).
  `azure_identity_resolve` walks parallel vectors in order and returns the
  first usable identity or `Err("azure: no usable identity")`.

Tests: t22 (ids/scopes/URLs), t23 (token), t24 (identity chain + facade).

## 8. Entry registry (`xiom.azure`)

Host suffixes (management, blob, functions, cosmos, service bus, login),
provider namespaces (`Microsoft.Compute`, `Microsoft.Storage`,
`Microsoft.Web`, `Microsoft.DocumentDB`, `Microsoft.ServiceBus`) and pinned
representative api-versions (compute `2023-03-01`, storage `2023-01-01`, web
`2022-03-01`, documentdb `2023-04-15`, servicebus `2022-10-01-preview`),
plus `azure_version() == "0.1.0"`. Unknown codes return `azure: unknown
service code` / `azure: unknown provider code`.

## Conformance suite

`tests/test_conformance.xi` (module `azure_tests`) has 24 named checks, one
`fn` per check, each returning `assert(cond, "<name>")`; `main` prints one
`[PASS]`/`[FAIL]` line per check and returns the failure count. Run:

```powershell
.\scripts\port.ps1 -Package xiom-azure -TimeoutSec 60
```

Expected: `port: PASS (passed=24 failed=0 program_exit=0)`.

## Non-goals

No HTTP client, no SAS/SigV4 signing, no JWT or OAuth cryptography, no
clock, no retry sleep loop, no pagination cursors. Those stay in the caller
or in dedicated transport packages.
