# xiom.consul

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic, pure-XIOM **Consul protocol model** (no HTTP, no
> agent, no network): the KV store with CAS and monotonic indexes, the
> service/check registry, TTL health transitions, session lifecycle with
> lock behavior, and the ACL rules subset.
> **Deps:** `xiom.std` only. The module imports `xiom.string`,
> `xiom.string.compare`, `xiom.string.builder` and `xiom.convert`; the tests
> add `xiom.test`, `xiom.io` and `xiom.string.compare`. No FFI.

## What it is

`xiom.consul` is the transport-free half of a Consul client: the semantics a
Consul agent or the HTTP API enforces, expressed as pure in-process state
machines. Feed it operations (put a key, register a service, heartbeat a
check, invalidate a session, resolve a capability) and it applies the
protocol rules deterministically; the caller owns the wire format, the
sockets and the clock.

| Area | Model |
|---|---|
| **KV** | `get`/`put`/`delete` with three CAS modes, tombstones, a monotonic store index, per-key create/modify indexes, session locks and lock-delay |
| **Services** | `register`/`deregister` with id, name, address, port, comma-joined tags; checks attach to services and are removed on deregistration |
| **Health** | TTL checks with `passing`/`warning`/`critical` transitions, heartbeats, tick-ageing expiry; HTTP and TCP check **configuration shapes**; worst-of aggregate service and node health |
| **Sessions** | deterministic ids, `create`/`renew`/`invalidate`, TTL expiry, and release-vs-delete behavior for the keys a session held |
| **ACL** | policy rules subset (`key`, `key_prefix`, `node`, `service`, `session`, `event`, `query`, `acl` with `read`/`write`/`list`/`deny`), token policy lists, capability resolution with deny precedence |

### Overlap boundary with `xiom.discovery`

`xiom.discovery` owns the generic discovery abstraction (weighted selection,
caller-polled watches, tag lookups, TTL sweeps). `xiom.consul` owns the
Consul-specific protocol model (KV indexes and CAS, Consul check IDs/kinds/
statuses, session behaviors and lock-delay, the ACL rules grammar). It does
not implement selection, watches or change logs, and neither package imports
the other; an application composes them. See `SPEC.md` section 1.

## API

KV store (`Result[_, Str]` errors are deterministic; see `SPEC.md` for the
full catalog):

| Function | Returns | Description |
|---|---|---|
| `consul_kv_new()` | `ConsulKvStore` | Empty store, index 0. |
| `consul_kv_put(kv, key, value, flags, cas)` | `Result[Int, Str]` | New modify index; `cas` = -1 none / 0 create-only / >0 index match. |
| `consul_kv_get(kv, key)` | `Result[Str, Str]` | Live value; tombstones are not found. |
| `consul_kv_delete(kv, key, cas)` | `Result[Bool, Str]` | `true` when a live key was deleted. |
| `consul_kv_find(kv, key)` | `Int` | Entry slot (live or tombstone), or -1. |
| `consul_kv_index/live_count/entry_count/is_tombstone` | `Int`/`Bool` | Index and counts. |
| `consul_kv_key_at/value_at/flags_at/create_index_at/modify_index_at` | mixed | Per-slot accessors. |
| `consul_kv_lock_session/lock_index/lock_delay` | `Str`/`Int` | Lock state. |
| `consul_kv_acquire(kv, sessions, key, value, session_id)` | `Result[Int, Str]` | Lock + write; new lock index. |
| `consul_kv_release(kv, key, session_id)` | `Result[Bool, Str]` | Holder-only release. |
| `consul_kv_advance_locks(kv, ticks)` | `Int` | Age lock delays; returns delays that expired. |

Sessions:

| Function | Returns | Description |
|---|---|---|
| `consul_sessions_new()` | `ConsulSessions` | Empty table. |
| `consul_session_create(sessions, ttl, behavior, lock_delay)` | `Result[Str, Str]` | New id `consul-session-N`. |
| `consul_session_renew(sessions, id)` | `Result[Int, Str]` | Reset remaining to TTL. |
| `consul_session_invalidate(kv, sessions, id)` | `Result[Int, Str]` | Keys affected; idempotent. |
| `consul_session_advance(kv, sessions, ticks)` | `Int` | Expire sessions; returns expired count. |
| `consul_session_find/id_at/ttl_at/remaining_at/behavior_at/lock_delay_at/invalidated_at` | mixed | Accessors. |

Services and checks:

| Function | Returns | Description |
|---|---|---|
| `consul_services_new()` | `ConsulServiceRegistry` | Empty registry. |
| `consul_register_service(reg, id, name, address, port, tags)` | `Result[Int, Str]` | New service slot. |
| `consul_deregister_service(reg, id)` | `Result[Int, Str]` | Checks removed with the service. |
| `consul_add_ttl_check(reg, id, service_id, name, ttl, notes)` | `Result[Int, Str]` | TTL check. |
| `consul_add_http_check(reg, id, service_id, name, url, interval, timeout, notes)` | `Result[Int, Str]` | HTTP check shape. |
| `consul_add_tcp_check(reg, id, service_id, name, host, port, interval, timeout, notes)` | `Result[Int, Str]` | TCP check shape. |
| `consul_check_set_status(reg, id, status)` | `Result[Int, Str]` | Previous status. |
| `consul_check_heartbeat(reg, id)` | `Result[Int, Str]` | TTL reset to passing. |
| `consul_check_advance(reg, ticks)` | `Int` | TTL checks becoming critical. |
| `consul_service_health(reg, service_id)` | `Int` | Worst status (node-level for `""`). |
| `consul_deregister_check(reg, check_id)` | `Result[Bool, Str]` | Existed? |
| `consul_service_*/check_*` accessors | mixed | Counts, slots, fields, `consul_service_has_tag`. |

ACL:

| Function | Returns | Description |
|---|---|---|
| `consul_acl_new()` | `ConsulAcl` | Empty store. |
| `consul_policy_parse(name, text)` | `Result[ConsulPolicyRules, Str]` | Parse the rules subset. |
| `consul_acl_add_policy(acl, name, text)` | `Result[Int, Str]` | Rules added; duplicate refused. |
| `consul_acl_add_token(acl, id, description, policy_list, management)` | `Result[Int, Str]` | New token slot. |
| `consul_acl_capability(acl, token_id, resource, path)` | `Result[Int, Str]` | Effective `NONE/READ/WRITE/LIST/DENY`. |
| `consul_acl_allows(acl, token_id, resource, path, action)` | `Result[Bool, Str]` | Deny-aware permission check. |
| `consul_acl_policy_find/token_find/*_at` accessors | mixed | Store accessors. |
| `consul_status_name/check_kind_name/session_behavior_name/acl_action_name/resource_name` | `Str` | Name tables. |

## Usage

```xi
use xiom.consul;

fn main() -> Int {
  var kv = consul_kv_new();
  // Unconditional write, then a compare-and-set on the returned index.
  let p = consul_kv_put(&mut kv, "app/config", "v1", 0, CONSUL_CAS_NONE);
  // let idx: Int = p.value;
  // let c = consul_kv_put(&mut kv, "app/config", "v2", 0, idx);

  var sessions = consul_sessions_new();
  let s = consul_session_create(&mut sessions, 15, CONSUL_BEHAVIOR_RELEASE, 5);
  // let sid: Str = s.value;
  // consul_kv_acquire(&mut kv, &sessions, "app/lock", sid, sid);
  // consul_session_invalidate(&mut kv, &mut sessions, sid); // lock released

  var reg = consul_services_new();
  consul_register_service(&mut reg, "web-1", "web", "10.0.0.1", 8080, "prod");
  consul_add_ttl_check(&mut reg, "web-1-ttl", "web-1", "heartbeat", 30, "");
  // let h = consul_service_health(&reg, "web-1"); // CONSUL_STATUS_PASSING

  var acl = consul_acl_new();
  consul_acl_add_policy(&mut acl, "app-ro", "key_prefix \"app/\" { policy = \"read\" }");
  consul_acl_add_token(&mut acl, "t1", "reader", "app-ro", 0);
  // let ok = consul_acl_allows(&acl, "t1", "key", "app/config", CONSUL_ACL_READ);
  return 0;
}
```

## Honest boundaries

- No HTTP: check URLs are validated shapes only; nothing is ever probed,
  and the package never opens a socket.
- No agent, gossip, consensus, blocking queries, retries, TLS, Connect,
  namespaces or snapshots.
- No wall clock: `consul_check_advance`, `consul_session_advance` and
  `consul_kv_advance_locks` are driven by integer ticks from the caller.
- Store/registry sizes are bounded by memory only; all operations are
  O(entries) or better and stated per function in `SPEC.md`.
- Values and keys are `Str`; arbitrary binary KV values (which the real API
  permits) are out of scope for this model.
- XIOM `Int` is signed 64-bit; flags and indexes are modeled in the
  non-negative range.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 24 `[PASS]` lines, then `xiom.consul: all tests passed`, exit 0.
