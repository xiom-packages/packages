# xiom.consul -- Specification

Status: `incubating` (implemented, harness-green, not yet published).
Module: `xiom.consul` (`src/consul.xi`). Manifest: `package.xi` (name
`xiom.consul`, version `0.1.0`, category `systems`). `xiom.std` is a manifest
dependency; the library module imports `xiom.string`, `xiom.string.compare`,
`xiom.string.builder` and `xiom.convert`, and the tests use `xiom.test`,
`xiom.io` and `xiom.string.compare`.

Conformance: 24 checks in `tests/test_conformance.xi`
(`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`).

## 1. Scope and overlap boundary

A pure, deterministic, in-process model of the Consul agent/HTTP API
protocol semantics. No HTTP, no sockets, no agent process, no gossip or
consensus, no blocking queries, no real clock and no I/O. Time is an integer
tick count the caller advances explicitly.

| Area | What this package models |
|---|---|
| KV store | put/get/delete, three CAS modes, tombstones, monotonic store/modify/create indexes, session locks and lock-delay |
| Service registry | register/deregister services with id/name/address/port/tags, check attachment and cascade removal |
| Health | TTL checks with status transitions (passing/warning/critical), heartbeats and expiry, HTTP/TCP check configuration shapes, aggregate service and node health |
| Sessions | create/renew/invalidate, deterministic ids, TTL expiry, release-vs-delete behavior and lock-delay on invalidation |
| ACL | policy rules subset (exact and prefix rules per resource, read/write/list/deny), token policy lists, capability and allow resolution with deny precedence |

**Boundary with `xiom.discovery`.** `xiom.discovery` owns the *generic*
service-discovery abstraction: weighted selection, caller-polled watches,
tag lookups, TTL sweeps and reaping, independent of any wire protocol.
`xiom.consul` owns the *Consul-specific protocol model*: the KV index/CAS
semantics, Consul check IDs, kinds, statuses and aggregation, Consul session
identity, behaviors and lock-delay, and the Consul ACL rules grammar.
`xiom.consul` deliberately does **not** implement instance selection,
watches, change logs, or any other discovery-layer feature; an application
that needs both composes them (a Consul agent would translate its records
into a `DiscoveryRegistry` through the application, never through a package
import). Neither package imports the other.

## 2. Non-goals

- HTTP, URLs beyond check-URL validation, headers, blocking queries,
  `X-Consul-Index` waiting, request retries, TLS.
- The agent, service mesh (Connect), intentions, prepared queries, namespaces,
  admin partitions, federation, snapshots, reaping of dead servers.
- Health-check execution: an HTTP/TCP check is only its validated
  configuration shape; nothing is probed on a network.
- Real time. Ticks are logical integers; the caller drives
  `consul_check_advance`, `consul_session_advance` and
  `consul_kv_advance_locks`.
- Persistence, serialization, concurrency and atomicity. The caller
  serializes access.

## 3. State

All public state is plain structs of parallel `Vec`s (`Vec[StructType]` is
unsupported by the compiler). Every field is an implementation detail;
callers go through the free functions.

```xi
pub type ConsulKvStore = {
  keys: Vec[Str]; values: Vec[Str]; flags: Vec[Int];
  create_indexes: Vec[Int]; modify_indexes: Vec[Int]; present: Vec[Int];
  lock_sessions: Vec[Str]; lock_indexes: Vec[Int]; lock_delays: Vec[Int];
  index: Int;
}

pub type ConsulServiceRegistry = {
  service_ids, service_names, service_addresses: Vec[Str]; service_ports: Vec[Int];
  service_tags: Vec[Str];
  check_ids, check_service_ids, check_names: Vec[Str];
  check_kinds, check_statuses, check_ttls, check_remainings,
  check_intervals, check_timeouts: Vec[Int];
  check_urls, check_hosts: Vec[Str]; check_ports: Vec[Int]; check_notes: Vec[Str];
}

pub type ConsulSessions = {
  ids: Vec[Str]; ttls, remainings, behaviors, lock_delays, invalidated: Vec[Int];
}

pub type ConsulPolicyRules = {
  resource_codes, scopes, actions: Vec[Int]; paths: Vec[Str];
}

pub type ConsulAcl = {
  policy_names: Vec[Str]; policy_rule_offsets: Vec[Int];
  rule_resource_codes, rule_scopes: Vec[Int]; rule_paths: Vec[Str]; rule_actions: Vec[Int];
  token_ids, token_descriptions, token_policy_lists: Vec[Str];
  token_management, token_valid: Vec[Int];
}
```

Invariants: each type's parallel vectors share one length (entry counts are
`keys.len()`, `service_ids.len()`, `check_ids.len()`, `ids.len()`,
`policy_names.len()`, `token_ids.len()`); `policy_rule_offsets.len() ==
policy_names.len() + 1` with the first offset 0 and policy `i` owning rules
`[offsets[i], offsets[i+1])`; every token policy-list element names an
existing policy. Every helper pushes or removes all siblings together.

## 4. KV store

### 4.1 Index rules

- `index` starts at 0 and is bumped **only** by a successful write
  (put, delete of a live key, lock acquire, or the delete-behavior of a
  session invalidation). Reads never bump it.
- On every write, `modify_indexes[i]` becomes the new store index. The store
  index is therefore always the largest modify index ever written.
- `create_indexes[i]` is set when a key is first created and re-set when a
  tombstone is re-created; it never changes on an update of a live key.
- A key that existed and was deleted stays as a **tombstone**
  (`present[i] == 0`): it remains listed (`consul_kv_entry_count`,
  `consul_kv_find`, `consul_kv_is_tombstone`), but `consul_kv_get` reports
  not found, its value accessor reads `""`, and delete/put treat it as
  missing for CAS purposes.

### 4.2 CAS modes for `consul_kv_put`

| `cas` | Behaviour |
|---|---|
| `CONSUL_CAS_NONE` (-1) | unconditional create or update |
| `CONSUL_CAS_CREATE` (0) | write only when the key is not live (missing or tombstone); else `Err("consul: cas mismatch")` |
| `> 0` | write only when the key is live and `modify_indexes[i] == cas`; else `Err("consul: cas mismatch")` |

Flags must be `>= 0` (`Err("consul: flags must not be negative")`); `cas <
-1` is `Err("consul: invalid cas")`. On success the new modify index is
returned. A locked key refuses `Err("consul: key is locked")`.

### 4.3 CAS modes for `consul_kv_delete`

| `cas` | Behaviour |
|---|---|
| `CONSUL_CAS_NONE` (-1) | delete a live key (`Ok(true)`); a missing/tombstoned key also returns `Ok(true)` without writing |
| `CONSUL_CAS_CREATE` (0) | delete a live key (`Ok(true)`); otherwise `Ok(false)` without writing |
| `> 0` | delete only when live and `modify_indexes[i] == cas`; else `Err("consul: cas mismatch")` |

A successful delete leaves a tombstone, clears the lock, bumps the store
index and stamps the modify index. A locked key refuses
`Err("consul: key is locked")`.

### 4.4 Locks

`consul_kv_acquire(kv, sessions, key, value, session_id)` writes the value
and stamps `lock_sessions[i]`/`lock_indexes[i]` with the session and the new
store index. It refuses an unknown session (`consul: session not found`), an
invalidated session (`consul: session invalidated`), a key held by another
session (`consul: key is locked`) and a key inside a lock-delay window
(`consul: lock delay active`). The holder may re-acquire; that refreshes the
value and the lock index. `consul_kv_release` clears the lock only for the
holder and reports `Ok(false)` otherwise; it does not touch the value or the
index. `consul_kv_advance_locks(kv, ticks)` ages every positive lock delay
(floor 0) and returns how many reached zero.

## 5. Sessions

`consul_session_create(sessions, ttl, behavior, lock_delay)` appends a
session with the deterministic id `"consul-session-N"` (N = new slot + 1;
sessions are never removed, so ids never repeat) and returns it. Validation:
`ttl >= 1`, behavior `release|delete`, `lock_delay >= 0`.

- `consul_session_renew` resets `remaining` to the granted TTL and returns
  it; an invalidated session is `Err("consul: session invalidated")`.
- `consul_session_advance(kv, sessions, ticks)` ages every live session by
  `ticks` in slot order; a session reaching zero is invalidated in the same
  call. Returns the number expired; `ticks <= 0` is a no-op.
- `consul_session_invalidate(kv, sessions, id)` invalidates immediately and
  returns the number of held keys affected (0 when already invalidated, so
  the call is idempotent).
- **Release behavior**: every held key keeps its value; its lock is cleared
  and its lock delay is set to the session's `lock_delay`.
- **Delete behavior**: every held key becomes a tombstone (store index
  bumped, modify index stamped), the lock is cleared and the lock delay is
  applied.

## 6. Services

`consul_register_service(reg, id, name, address, port, tags)` validates in
order: non-empty printable id, duplicate id, non-empty printable name,
printable address, `0 <= port <= 65535`, tag list (comma-joined, no empty
element, printable). On success the service is appended and its slot
returned. `consul_deregister_service` removes the service and every check
attached to it (shift-compaction preserving order) and returns the number of
checks removed; unknown id is `Err("consul: service not found")`.

`consul_service_has_tag` performs whole-element, delimiter-aware membership
(`"a,b"` matches `a` and `b`, never `ab`).

## 7. Checks and health

Check kinds: `TTL 0`, `HTTP 1`, `TCP 2`. Statuses: `passing 0`,
`warning 1`, `critical 2`. Every check starts passing. A check with an empty
`service_id` is node-level.

| Builder | Validation beyond the common preamble |
|---|---|
| `consul_add_ttl_check(reg, id, service_id, name, ttl, notes)` | `ttl >= 1` |
| `consul_add_http_check(reg, id, service_id, name, url, interval, timeout, notes)` | URL starts with `http://` or `https://`; `1 <= timeout <= interval` |
| `consul_add_tcp_check(reg, id, service_id, name, host, port, interval, timeout, notes)` | non-empty printable host; `1 <= port <= 65535`; `1 <= timeout <= interval` |

The common preamble validates: non-empty printable check id, duplicate id,
existing `service_id` when non-empty, non-empty printable name, printable
notes. TTL checks start with `remaining = ttl`; HTTP/TCP checks keep
`remaining` 0.

- `consul_check_set_status` allows any transition and returns the previous
  status; an out-of-range code is `Err("consul: invalid check status")`.
- `consul_check_heartbeat` (TTL only) resets `remaining` to the TTL and sets
  the status to passing; a non-TTL check is
  `Err("consul: check is not a ttl check")`.
- `consul_check_advance(reg, ticks)` ages TTL checks in slot order; a check
  reaching zero becomes critical (remaining floored at 0) exactly once
  (already-critical checks are not counted again). Returns how many became
  critical; HTTP/TCP checks are not aged.
- `consul_service_health(reg, service_id)` is the worst status among the
  service's checks (critical > warning > passing), passing when there are
  none; an empty `service_id` aggregates node-level checks; an unknown
  non-empty service returns `CONSUL_NOT_FOUND` (-1).
- `consul_deregister_check` returns `Ok(true/false)`; duplicate check ids are
  refused.

## 8. ACL model

### 8.1 Rules grammar

One rule per line; blank lines and `#` / `//` comments are ignored; spaces
and tabs are free. Paths are printable ASCII without quotes and may be empty
(an empty prefix matches every path).

```
key_prefix "app/" { policy = "read" }
key "app/config" { policy = "write" }
node_prefix "web-" { policy = "read" }
service_prefix "" { policy = "write" }
session_prefix "s/" { policy = "write" }
event_prefix "deploy/" { policy = "list" }
query_prefix "" { policy = "read" }
acl = "read"
```

Resources: `key`, `node`, `service`, `session`, `event`, `query` (exact or
`_prefix`) and `acl` (exact only). Actions: `read`, `write`, `list`, `deny`.
A malformed line, unknown resource and unknown action produce distinct
deterministic errors carrying the 1-based line number.

### 8.2 Resolution

For one policy and one (resource, path):

1. A matching rule is one with the same resource whose path is equal (exact)
   or a prefix of the query path (`_prefix`).
2. **Deny wins**: if any matching rule is `deny`, the policy resolves to
   `DENY`.
3. Otherwise the most specific grant wins: an exact rule beats every prefix,
   a longer prefix beats a shorter one, and the later rule wins a tie.
4. No match resolves to `NONE`.

Across a token's policies: any `DENY` from any policy denies the path; else
the effective capability is `WRITE` > `LIST` > `READ` > `NONE`.
`consul_acl_allows` grants `read` for `READ` or `WRITE` (write implies
read), `write` only for `WRITE`, and `list` only for `LIST`.

### 8.3 Tokens

`consul_acl_add_token(acl, id, description, policy_list, management)`:
non-empty printable unique id, printable description, `management` 0 or 1,
and a comma-joined policy list whose every element names an existing policy
(no empty elements). Management tokens bypass all ACL checks (capability
`WRITE`, every action allowed). `token_valid` is 1 for tokens added through
this function; an invalid (0) token resolves to `NONE` and allows nothing.
Unknown token id: `Err("consul: token not found")`; unknown resource:
`Err("consul: unknown acl resource")`; unknown action
(requested action is not read/write/list): `Err("consul: invalid acl action")`.

## 9. Error catalog

| Err string | Produced by |
|---|---|
| `consul: empty key` | KV get/put/delete/acquire/release |
| `consul: key not printable` | same |
| `consul: key not found` | get |
| `consul: flags must not be negative` | put |
| `consul: invalid cas` | put, delete (`cas < -1`) |
| `consul: cas mismatch` | put, delete |
| `consul: key is locked` | put, delete, acquire |
| `consul: lock delay active` | acquire |
| `consul: ttl must be >= 1` | session create, TTL check |
| `consul: invalid session behavior` | session create |
| `consul: lock delay must not be negative` | session create |
| `consul: session not found` | renew, invalidate, acquire |
| `consul: session invalidated` | renew, acquire |
| `consul: service id must not be empty` | register service |
| `consul: service id not printable` | register service |
| `consul: service name must not be empty` | register service |
| `consul: service name not printable` | register service |
| `consul: service address not printable` | register service |
| `consul: service port out of range` | register service |
| `consul: empty service tag` | register service |
| `consul: service tag not printable` | register service |
| `consul: duplicate service` | register service |
| `consul: service not found` | deregister service |
| `consul: check id must not be empty` | add check |
| `consul: check id not printable` | add check |
| `consul: duplicate check` | add check |
| `consul: unknown service for check` | add check |
| `consul: check name must not be empty` | add check |
| `consul: check name not printable` | add check |
| `consul: check notes not printable` | add check |
| `consul: interval must be >= 1` | HTTP/TCP check |
| `consul: timeout must be >= 1` | HTTP/TCP check |
| `consul: timeout must not exceed interval` | HTTP/TCP check |
| `consul: invalid http check url` | HTTP check |
| `consul: tcp host must not be empty` | TCP check |
| `consul: tcp host not printable` | TCP check |
| `consul: tcp port out of range` | TCP check |
| `consul: check not found` | set status, heartbeat |
| `consul: invalid check status` | set status |
| `consul: check is not a ttl check` | heartbeat |
| `consul: empty policy name` | policy parse |
| `consul: policy name not printable` | policy parse |
| `consul: malformed acl rule at line N` | policy parse |
| `consul: unknown acl resource at line N` | policy parse |
| `consul: unknown acl policy at line N` | policy parse |
| `consul: duplicate policy` | add policy |
| `consul: token id must not be empty` | add token |
| `consul: token id not printable` | add token |
| `consul: token description not printable` | add token |
| `consul: duplicate token` | add token |
| `consul: token policy list not printable` | add token |
| `consul: empty policy in token list` | add token |
| `consul: unknown policy in token: <name>` | add token |
| `consul: invalid token management flag` | add token |
| `consul: token not found` | capability, allows |
| `consul: unknown acl resource` | capability, allows |
| `consul: invalid acl action` | allows |

## 10. Accessor sentinels

Out-of-range indices never panic. Str accessors return `""`; Int accessors
return `CONSUL_NOT_FOUND` (-1); Bool accessors return `false`;
`consul_service_health` returns -1 for an unknown non-empty service;
`consul_check_kind_name`, `consul_status_name`,
`consul_session_behavior_name`, `consul_acl_action_name` and
`consul_resource_name` return `"unknown"` for unrecognized codes.

## 11. Complexity

| Operation | Complexity |
|---|---|
| constructors, accessors, name tables, index/count reads | O(1) |
| `consul_kv_find`, `consul_kv_put`, delete, acquire, release, live_count | O(entries) |
| `consul_kv_advance_locks` | O(entries) |
| session create/find/renew | O(sessions) |
| `consul_session_advance`, `consul_session_invalidate` | O(sessions + entries) |
| service/check find, register, add-check, deregister-check | O(services + checks) |
| `consul_deregister_service` | O(services + checks) |
| `consul_check_advance`, health, service check count | O(checks) |
| `consul_policy_parse` | O(text bytes) |
| `consul_acl_add_policy`, add_token | O(rules / policy-list bytes + policies) |
| `consul_acl_capability`, `consul_acl_allows` | O(token policies * policy rules) |

## 12. Conformance

`tests/test_conformance.xi` pins: put/get values, flags and indexes with
unchanged state on every rejection; all three CAS modes for put and delete;
tombstone listing, not-found reads and re-creation; index monotonicity and
the largest-modify-index rule; acquire/refresh/refuse/release and
lock-delay windows; deterministic session ids, renew, TTL expiry and
invalidated-session refusal; release and delete behaviors on both explicit
invalidation and expiry, with idempotent invalidation counts; service
register/accessors/tags and cascade deregistration; every service and check
validation error; TTL status transitions, heartbeat resets and manual
overrides; HTTP/TCP shape validation; critical-transition counting; aggregate
service and node health; policy parsing with comments, blanks and compact
forms; malformed/unknown-resource/unknown-action line numbers; precedence
(exact > longest prefix > later rule, deny wins); token read/write/list
resolution and write-implies-read; management bypass; unknown token/resource/
action errors; duplicate policy/token refusal; constants, name tables,
fresh-store and accessor sentinels.
