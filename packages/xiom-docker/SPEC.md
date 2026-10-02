# xiom.docker -- specification

Version 0.1.0. Pure XIOM management model for a Docker-like container engine.
No HTTP, sockets, daemon, clock, randomness or file access. All state is
plain values; all functions are total and deterministic.

## 1. Image references (`xiom.docker.image`)

### 1.1 Grammar

```
reference  := name [ ":" tag ] [ "@" digest ]
name       := [ registry "/" ] repository
registry   := a first path component containing "." or ":" or equal to "localhost"
repository := 1*( component "/" component )
component  := lowercase-letter/digit, then { lowercase-letter | digit | "." | "_" | "-" }, end alnum
tag        := 1..128 of [A-Za-z0-9_.-], first character not "." or "-"
digest     := "sha256:" 64 lowercase hex digits
```

Parsing rules:

* at most one `@` (more => `image: multiple digests`); the digest is the text
  after `@` and must match `digest` exactly;
* the tag separator is the last `:` before the digest; every `/` resets the
  candidate, so `host:5000/name` is a registry-port form, not a tag;
* when neither a tag nor a digest is written, the tag defaults to `latest`;
  a digest-only reference keeps tag `""`;
* the first path component is a registry only when it contains `.` or `:`, or
  equals `localhost`; otherwise the registry is `docker.io`.

### 1.2 API

* `image_ref_parse(ref) -> Result[ImageRef, Str]`
* `image_ref_valid(ref) -> Bool`
* `image_ref_render(ref) -> Str` -- `repository[:tag][@digest]`
* `image_ref_name(ref) -> Str` -- `registry/repository`
* accessors: `image_ref_registry`, `image_ref_repository`, `image_ref_tag`,
  `image_ref_digest`, `image_ref_has_digest`
* image model: `docker_image_new(ref)`, `docker_image_add_layer(img, digest)`
  (duplicate-free, ordered), `docker_image_set_config(img, digest)`,
  `docker_image_layer_count`, `docker_image_layer_at(img, i)` (`""` out of
  range), `docker_image_has_layer`, and field accessors
  (`docker_image_repository/_tag/_digest/_registry/_config_digest`).

Capacity: at most `DOCKER_MAX_LAYERS` (128) layers, tags at most
`DOCKER_MAX_TAG` (128) bytes.

## 2. Containers (`xiom.docker`)

States: `DOCKER_CT_CREATED=0`, `DOCKER_CT_RUNNING=1`, `DOCKER_CT_STOPPED=2`,
`DOCKER_CT_REMOVED=3`.

Transition table (`container_can_transition(from, to)`), exactly six legal
pairs:

| from \ to | CREATED | RUNNING | STOPPED | REMOVED |
|-----------|---------|---------|---------|---------|
| CREATED   | -       | yes     | -       | yes     |
| RUNNING   | -       | yes*    | yes     | -       |
| STOPPED   | -       | yes     | -       | yes     |
| REMOVED   | -       | -       | -       | -       |

\* RUNNING -> RUNNING only via `container_restart`.

Actions (`DOCKER_ACTION_START=1`, `STOP=2`, `RESTART=3`, `REMOVE=4`) and
their exact error strings:

| call | legal from | error otherwise |
|------|-----------|-----------------|
| `container_start` | CREATED, STOPPED | `container: already running` (RUNNING), `container: container removed`, `container: unknown id` |
| `container_stop` | RUNNING | `container: not running` (CREATED), `container: already stopped` (STOPPED), `container: container removed`, `container: unknown id` |
| `container_restart` | RUNNING, STOPPED | `container: not started` (CREATED), `container: container removed`, `container: unknown id` |
| `container_remove` | CREATED, STOPPED | `container: stop before removing` (RUNNING), `container: container removed`, `container: unknown id` |
| `container_transition(m, id, action)` | as above | `container: unknown action` for an unknown action code |

Counter rules: each successful `start`/`stop`/`restart` increments that
container's counter (`container_start_count`, `container_stop_count`,
`container_restart_count`); failed calls change nothing.

Construction and accessors: `container_model_new`,
`container_create(m, name, image)`;
`container_count` (all slots), `container_live_count` (non-removed),
`container_name`, `container_image`, `container_index`,
`container_state` (`DOCKER_NOT_FOUND = -1` out of range),
`container_state_name` (`"created" | "running" | "stopped" | "removed" |
"unknown"`). Ids are dense from 0 and never reused; removing marks the slot.

Errors: `container: name must not be empty`, `container: duplicate name`,
`container: container limit exceeded` (`DOCKER_MAX_CONTAINERS = 64`), and the
exact `image_ref_parse` error when the image is malformed.

## 3. Registry and plans (`xiom.docker.registry`)

`registry_new(host)` -> `Err("registry: host must not be empty")` when empty.
`registry_login(reg, user, password)` validates both non-empty and then
**discards the password** (never stored); it updates the user and returns the
login count. `registry_logout(reg)` returns the logout count, or
`Err("registry: not logged in")`.

Plans:

* `registry_plan_pull(reg, ref)` -- no login required; `needs_auth` records
  whether a session is active; steps (3): `resolve manifest`, `fetch config`,
  `fetch layers`.
* `registry_plan_push(reg, ref)` -- requires a session
  (`registry: login required for push`) and a tag
  (`registry: push requires a tag`); `needs_auth` is true; steps (4):
  `authenticate`, `check tag`, `upload layers`, `push manifest`.

Plan accessors: `plan_op` (`DOCKER_PLAN_PULL=0`, `DOCKER_PLAN_PUSH=1`),
`plan_operation_name`, `plan_needs_auth`, `plan_step_count`, `plan_step_at`
(`""` out of range), `plan_registry`, `plan_repository`, `plan_tag`,
`plan_digest`. Malformed references propagate the exact image error.

## 4. Compose (`xiom.docker.compose`)

`DockerCompose` services have a name, image, replicas (default 1; must be
>= 1) and up to `DOCKER_STACK_MAX_SERVICES` (64) entries. Dependencies are
edges `dep -> svc` stored in parallel vectors: `compose_add_dep(c, svc, dep)`
records that `svc` depends on `dep` (so `dep` starts first). Rejected:
unknown service, self-dependency (`compose: service cannot depend on itself`),
duplicate edge (`compose: duplicate dependency`),
`compose: dependency limit exceeded` (`DOCKER_STACK_MAX_EDGES = 512`).
A cycle-closing edge is *accepted*; `compose_topo_order` then fails with
`compose: dependency cycle` and `compose_has_cycle` returns true.
`compose_order_text` returns the comma-separated start order or `"cycle"`.

Start order algorithm (Kahn, deterministic): repeatedly emit the smallest
index whose not-yet-emitted dependencies are all emitted; a pass that finds
no candidate is a cycle. Bounded by the service/edge caps.

Network/volume references: `compose_attach_network(c, svc, name)` /
`compose_attach_volume(c, svc, name)` reject empty names and duplicates and
return the total attachment count;
`compose_network_count`/`compose_network_at`/`compose_volume_count`/
`compose_volume_at` read them (`""` out of range).

## 5. Volumes and networks (`xiom.docker.resources`)

`DockerResources` holds two independent named sets (up to
`DOCKER_STACK_MAX_RES = 128` each). `resources_add_volume(r, name, driver)`
and `resources_add_network(r, name, driver)` require non-empty name and driver
and a unique name (removed names stay reserved). `resources_remove_*` marks an
entry removed and returns the live count; removing twice or removing an
unknown name errors (`volume/network: already removed`, `volume/network: not
found`). Accessors: `*_exists`, `*_removed`, `*_count` (live), `*_total`
(slots), `*_name(i)`, `*_driver(i)` -- names remain readable after removal.

## 6. Capacity guards

| Constant | Value | Applies to |
|----------|-------|-----------|
| `DOCKER_MAX_LAYERS` | 128 | layers per image |
| `DOCKER_MAX_TAG` | 128 | tag bytes |
| `DOCKER_MAX_CONTAINERS` | 64 | containers per model |
| `DOCKER_STACK_MAX_SERVICES` | 64 | compose services |
| `DOCKER_STACK_MAX_EDGES` | 512 | compose dependency edges |
| `DOCKER_STACK_MAX_REFS` | 128 | network refs per service (and volume refs) |
| `DOCKER_STACK_MAX_RES` | 128 | entries per volume/network set |

## 7. Determinism and invariants

* No wall clock, no randomness, no I/O: all outputs are functions of inputs.
* Name/digest/step lists are one `Str` blob plus a monotone `Vec[Int]` offset
  table; the append helper is the only writer and every reader bounds-checks
  its index. No `Vec[Str]` and no `Vec[StructType]` are used.
* Parallel vectors are pushed in lockstep (container fields; compose
  services/edges/refs; resource name/driver/removed triples), so they cannot
  drift; accessors guard lengths and return `""`/`DOCKER_NOT_FOUND`.
* String equality uses `string.str_compare`; `==` is never used on `Str`.
