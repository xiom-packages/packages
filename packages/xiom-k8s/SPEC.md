# xiom.k8s -- specification

Version 0.1.0. Pure-XIOM Kubernetes orchestration model; no API server, no
network, no clock, no file I/O. Every operation is a deterministic function
over the `K8sCluster` value; identical inputs always produce identical
outputs.

## 1. Data model

A cluster is one value holding parallel arrays per object kind (dense ids,
0-based, never reused):

- **Namespaces**: name blob + offsets; quotas `max_pods`, `cpu_milli`,
  `mem_mib` (`0` = unlimited).
- **Pods**: name, namespace, phase, `cpu_milli`, `mem_mib`, owner deployment
  id (`-1` = unowned), successful-transition counter, label entries.
- **Deployments**: name, namespace, replicas, strategy terms
  (`surge`,`surge_pct`,`unavail`,`unavail_pct`), current revision, image
  entries (append-only; the last entry owned by the deployment is current),
  revision-history records (append-only snapshots of `(revision, image)`).
- **Services**: name, namespace, type, port, target port, selector entries.
- **ConfigMaps**: name, namespace, immutable flag, key/value entries.
- **Secrets**: name, namespace, type, key/value entries.
- **Ingresses**: name, namespace, rules of `(host, path, service name,
  port)`.

All strings are stored in `Str` blobs with a monotone `Vec[Int]` offset table
(`off.len() == count + 1`, `off[count] == str_len(blob)`). Per-object
collections carry a parallel owner table; scans validate that the tables stay
parallel and return empty/`-1` on drift.

Verbatim limits:

| Constant | Value | Meaning |
|----------|-------|---------|
| `K8S_MAX_NAME` | 63 | max object-name bytes |
| `K8S_MAX_PORT` | 65535 | max port |
| `K8S_MAX_NAMESPACES` | 64 | namespaces per cluster |
| `K8S_MAX_OBJECTS` | 256 | objects per kind per cluster |
| `K8S_MAX_REVISIONS` | 16 | history records per deployment |
| `K8S_ROLLING_MAX_ROUNDS` | 1024 | rolling-update simulation bound |

## 2. Grammar

- **Object name** (`k8s_name_valid`): 1..63 bytes of `[a-z0-9-]`, first and
  last byte lowercase alphanumeric. Namespace-scoped uniqueness for pods,
  deployments, services, configmaps, secrets and ingresses.
- **Label key** (`selector.label_key_valid`): 1..63 bytes of
  `[A-Za-z0-9._/-]`, first/last alphanumeric.
- **Label value** (`selector.label_value_valid`): 0..63 bytes of the same
  class; non-empty values must start/end alphanumeric.
- **ConfigMap/Secret key**: 1..253 bytes of `[A-Za-z0-9._-]`, first/last
  alphanumeric.
- **Ingress host** (`ingress_host_valid`): 1..253 bytes,
  `label[.label]*`, each label 1..63 bytes of `[a-z0-9-]` with alphanumeric
  ends. An empty rule host is a wildcard.
- **Ingress path**: non-empty, starts with `/`.
- Selector strings parse as `k=v,k2=v2` (`selector.label_parts_parse`);
  empty string = empty selector set; no whitespace stripping.

## 3. Pod phase machine

Phases: `PENDING=0`, `RUNNING=1`, `SUCCEEDED=2`, `FAILED=3`, `UNKNOWN=4`.

| From | Legal targets |
|------|---------------|
| PENDING | RUNNING, FAILED, UNKNOWN |
| RUNNING | SUCCEEDED, FAILED, UNKNOWN |
| UNKNOWN | PENDING, RUNNING, SUCCEEDED, FAILED |
| SUCCEEDED | (none; terminal) |
| FAILED | (none; terminal) |

Exactly ten legal `(from,to)` pairs. `pod_transition` rejects unknown pods,
out-of-range phases, same-phase moves and illegal moves, each with its own
error, and increments the move counter only on success.

## 4. Deployments and rolling updates

New deployments use `maxSurge=25%`, `maxUnavailable=25%`, revision `1`.

**Strategy resolution** (`xiom.k8s.rolling`):

- absolute when `*_pct == 0`; otherwise `amount%` of `desired`;
- `maxSurge` percentages round **up** (`(desired*amount + 99)/100`);
- `maxUnavailable` percentages round **down** (`desired*amount/100`);
- the two raw terms may not both be zero; percent flags are `0` or `1`;
  percent values are `0..100`.

**Round model.** One round: create up to `maxSurge` new replicas plus any
capacity deficit, then retire up to `maxUnavailable` old replicas plus one per
new replica above `desired`. Totals stay in
`[desired - maxUnavailable, desired + maxSurge]`; the new count never exceeds
`desired`. `rolling_schedule(desired, surge, unavail)` returns the
new-replica count after each round (final entry always `desired`); `desired=0`
yields an empty schedule. Reference schedules:

| desired | surge | unavail | schedule |
|---------|-------|---------|----------|
| 4 | 1 | 0 | `[1,2,3,4]` |
| 5 | 2 | 0 | `[2,4,5]` |
| 4 | 1 | 1 | `[1,3,4]` |
| 4 | 0 | 1 | `[0,1,2,3,4]` |
| 10 | 3 | 2 | `[3,8,10]` |
| 0 | any | any | `[]` |

**Revision history.** `deployment_set_image` appends a `(revision, current
image)` snapshot, then increments the revision. Revisions are monotone;
rollback never rewrites history. `deployment_rollback(dep, target)`:

- `target < 0` selects the most recent history record; otherwise the latest
  record whose revision equals `target`;
- the replaced state is appended to history, a new image entry is appended,
  the revision increments by one, and the new revision is returned;
- errors: no history, revision not found, history limit reached.

## 5. Services and endpoints

Types: `ClusterIP=0`, `NodePort=1`, `LoadBalancer=2`; names render as
`"ClusterIP"`, `"NodePort"`, `"LoadBalancer"`, else `"unknown"`. Ports are
`1..65535`.

`service_endpoints(svc)` returns the pods that (a) live in the service's
namespace, (b) are in `RUNNING`, and (c) carry every selector entry
(byte-exact keys and values), in dense pod-id order. An empty selector is an
error (`"service: selector is empty"`), never "match everything". Removing a
pod from `RUNNING` (or a failed phase) removes it from endpoints immediately.

## 6. Ingress

A rule is `(host, path, service name, port)`; the service must exist in the
ingress namespace at resolution time. `ingress_resolve(ing, host, path)`
selects the candidate rule with the longest matching path; ties keep the
earlier rule. Host matches when the rule host is empty (wildcard) or
byte-equal. Path matches exactly, or as a **path-element prefix**: the rule
path is a byte prefix and either ends with `/` or the next request byte is
`/` (`/v1` does not match `/v1x`). Errors: unknown ingress, invalid host,
path not starting with `/`, no matching rule, backend service not found.

## 7. Config, secrets and scoping

ConfigMaps and Secrets store append-only `key=value` entries; reusing a key
is `"configmap: duplicate key"` / `"secret: duplicate key"`. Immutable
configmaps reject every later `configmap_set`. Secrets carry a non-empty
type string.

Scoping: `pod_ref_configmap` / `pod_ref_secret` resolve a name **only in the
referring pod's namespace**; a same-named object in another namespace is
invisible (`"configmap: not found"` / `"secret: not found"`). Ingress
backends resolve only against services in the ingress namespace.

## 8. Quota accounting

Per namespace: `namespace_used_pods`, `namespace_used_cpu`,
`namespace_used_mem`, `namespace_used_configmaps`, `namespace_used_secrets`.
`namespace_admit_pod(ns, cpu, mem)` checks, in order:

1. `"quota: resources must be >= 0"` for negative requests;
2. pod limit (`max_pods > 0` and `used + 1 > max_pods`);
3. CPU limit (`cpu_milli > 0` and `used_cpu + cpu > cpu_milli`);
4. memory limit (`mem_mib > 0` and `used_mem + mem > mem_mib`).

`pod_create` runs admission internally and propagates the exact quota error.

## 9. Error taxonomy

Errors are stable strings prefixed by the failing object:
`namespace:`, `pod:`, `deployment:`, `service:`, `configmap:`, `secret:`,
`ingress:`, `quota:`, `label:`, `rolling:`. Every error leaves the cluster
byte-identical to its pre-call state.

## 10. Determinism

No threads, timers, randomness, environment or I/O. All iteration is over
dense ids in ascending order; all scans are bounded by the limits above.
Labels, selector entries, config/secret keys and ingress rules keep insertion
order; revision history is append-only. Two clusters built by the same call
sequence compare equal through their accessors, and repeating a query never
changes its result.
