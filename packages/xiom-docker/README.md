# xiom.docker

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** Docker container lifecycle *management model*: images, containers,
> registries, compose, volumes and networks.
> **Deps:** stdlib only (`xiom.string`); no HTTP, no sockets, no daemon.

`xiom.docker` models the data and state transitions behind a Docker-like
engine as pure values. Every function is a total, deterministic transition
over plain structs: there is no clock, no randomness, no file and no network
access anywhere in the package. The caller decides where the state lives and
when transitions happen.

## Modules

| Module | File | Owns |
|--------|------|------|
| `xiom.docker.image` | `src/image.xi` | Image reference grammar (`[registry/]repo[:tag][@sha256:digest]`), validation, canonical rendering, layer chain, config digest |
| `xiom.docker` | `src/docker.xi` | Container model and the create/start/stop/restart/remove state machine |
| `xiom.docker.registry` | `src/registry.xi` | Registry login/logout state (password never stored) and deterministic push/pull plans |
| `xiom.docker.compose` | `src/compose.xi` | Compose services, dependency edges, topological start order, cycle detection, per-service network/volume references |
| `xiom.docker.resources` | `src/resources.xi` | Named volume and network sets with drivers and stable (never-released) names |

## Model highlights

* **Image references** follow Docker's familiar grammar: lowercase repository
  components, tags of `[A-Za-z0-9_.-]` (not starting with `.`/`-`), digests of
  exactly `sha256:` + 64 lowercase hex digits. `registry:port/...` and
  `localhost` are recognised as registries; an omitted tag defaults to
  `latest` only when no digest is present.
* **Container lifecycle** is a strict four-state machine
  (`CREATED`, `RUNNING`, `STOPPED`, `REMOVED`). Every invalid transition
  returns `Err` and leaves state and counters untouched. Ids are dense and
  never reused; removed slots remain inspectable.
* **Registry plans** expose the fixed ordered step list for a pull (3 steps)
  or push (4 steps). A pull needs no session in this model; a push requires
  an active login and a tagged reference. `registry_login` validates and then
  discards the password.
* **Compose** stores a dependency graph as parallel edge vectors (edge
  `dep -> svc` means `dep` starts first) and computes the start order with
  Kahn's algorithm, always picking the smallest ready index, so the result is
  deterministic. Cycle-closing edges are accepted at insertion time and
  reported by `compose_topo_order` / `compose_has_cycle`.
* **Volumes and networks** are named sets with drivers and a removed flag.
  Removing never releases a name, so ids stay stable; live counts exclude
  removed entries.

## Names, not `Vec[Str]`

Lists of names, digests and step descriptions are stored as one `Str` blob
plus a monotone `Vec[Int]` offset table (`offsets[i]..offsets[i+1]`), never as
`Vec[Str]`. The invariant (`offsets.len() == count + 1`, last offset ==
`str_len(data)`) is maintained by a single append helper per module, and every
reader guards its own index. All string equality goes through
`string.str_compare`.

## Testing

```
.\scripts\port.ps1 -Package xiom-docker -TimeoutSec 60
```

`tests/test_conformance.xi` runs 26 deterministic checks covering the
reference grammar and its error cases, layer-chain rules, the full container
lifecycle (valid and invalid transitions, transition table, counters), login
state, pull/push plans, compose services/dependencies/topological order and
cycles, network/volume references, and the volume/network set lifecycle.

See `SPEC.md` for the pinned model, error catalogue and capacity guards.
