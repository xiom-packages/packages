# xiom.k8s

Pure-XIOM Kubernetes orchestration **model**: the object semantics of a
cluster as a deterministic in-memory value. No API server, no kubeconfig, no
networking, no file I/O, no FFI. Everything in this package is a total
function over plain values, so it is safe for tests, simulations, planners,
admission checks and config generators.

- **Package**: `xiom.k8s` 0.1.0 -- category `systems`
- **Deps**: `xiom.std` only
- **Modules**:
  - `xiom.k8s` -- cluster object model: Namespace, Pod, Deployment, Service,
    ConfigMap, Secret, Ingress; pod phase machine; quota accounting.
  - `xiom.k8s.selector` -- label sets and selector matching.
  - `xiom.k8s.rolling` -- rolling-update replica math (`maxSurge` /
    `maxUnavailable`, round schedule).
- **Tests**: `tests/test_conformance.xi` -- 23 deterministic checks.
- **License**: MIT OR Apache-2.0

## What is modeled

| Concern | Model |
|---------|-------|
| Namespaces | Dense ids; name grammar (DNS-1123); quotas (pods, CPU millicores, MiB; `0` = unlimited) |
| Pods | Create/admit, namespace-scoped names, resource requests, labels, phase machine, deployment ownership |
| Pod phases | `PENDING -> RUNNING -> SUCCEEDED/FAILED`, plus `UNKNOWN` loss/recovery; ten legal pairs |
| Deployments | Desired replicas, strategy resolution (absolute or percent), monotone revision history, rollback, pod adoption |
| Rolling updates | Bounded round simulation; schedule of new-replica counts; percentages round surge up / unavailable down |
| Services | ClusterIP / NodePort / LoadBalancer; selector entries; ready endpoints from matched Running pods in the same namespace |
| Ingress | Rules of (host, path, backend service, port); wildcard host; longest path-element prefix wins |
| ConfigMaps / Secrets | Key/value entries, immutable configmaps, typed secrets, namespace-scoped references |
| Quota accounting | Used pods/CPU/memory/configmaps/secrets per namespace; admission errors |

## Example

```xiom
use xiom.k8s;

pub fn main() -> Int {
  var c = k8s_cluster_new();
  let ns = namespace_create(&mut c, "default", 8, 4000, 4096);
  let d = deployment_create(&mut c, 0, "web", "nginx:1.25", 3);
  let p = pod_create(&mut c, 0, "web-0", 100, 128);
  let s = service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 8080);
  service_selector_add(&mut c, 0, "app", "web");
  // ... label + run the pods, then:
  // service_endpoints(&c, 0) -> Ok([pod ids in dense order])
  // deployment_rolling_schedule(&c, 0) -> Ok([1, 2, 3])
  return 0;
}
```

## Design notes

- **One value per cluster.** All per-kind collections are parallel `Vec`
  fields guarded against length drift; no `Vec[StructType]`, no `Vec[Str]`.
  Strings live in `Str` blobs with monotone `Vec[Int]` offset tables, so a
  caller can snapshot, copy and compare clusters deterministically.
- **Dense ids.** Ids are 0-based per kind, never reused; removed/lost state
  stays addressable (there is no removal API in this model).
- **Bounded work.** Rolling updates are capped by
  `K8S_ROLLING_MAX_ROUNDS`, object counts by `K8S_MAX_OBJECTS` /
  `K8S_MAX_NAMESPACES`, revision history by `K8S_MAX_REVISIONS`.
- **Errors are values.** Every fallible operation returns
  `Result[T, Str]` with a stable, prefixed message (`"pod: ..."`,
  `"quota: ..."`, `"ingress: ..."`); every error leaves the cluster
  unchanged.
- **Namespace scoping.** Object names are unique per namespace; endpoint
  matching, config/secret references and ingress backends only resolve
  inside the referrer's namespace.

See `SPEC.md` for the full behavioral contract and error taxonomy.
