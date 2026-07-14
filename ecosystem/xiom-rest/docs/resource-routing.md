# Resource Routing

> Status: Design stage — specification only, not yet implemented.

Resource routing is the heart of `xiom-rest`. It turns a domain concept (a "user", an "order", a "comment") into a small, predictable set of HTTP endpoints, and then lowers that description onto the `xiom-http` transport. The design principle is that resources are declared, not imperatively wired — a `RestModule` is a plain, side-effect-free description of a resource and its routes until it is explicitly mounted onto an application.

## The resource abstraction

A resource is identified by a noun and exposes a conventional set of operations: list and create on the collection, and read/replace/update/delete on individual items. `RestModule.new("users")` seeds a module named `users`, and chained builder calls (`get_list`, `post`, `get_item`, `patch_item`, `delete_item`) attach handlers for each operation. Because the builder returns a new `RestModule` at each step, definitions stay declarative and composable — there is no hidden registry and no global mutable state. Collection routes are plural (`/users`) and item routes address a single entity (`/users/{id}`), following the recommended default conventions.

## Composition and nesting

Real APIs have relationships, so `RestModule.nest` composes a child resource under a parent to express paths like `/users/{id}/orders`. Nesting is kept shallow by convention: deep hierarchies make URIs brittle and are usually better modeled as top-level resources with filters. Composition happens at the module level, mirroring the "nested router" pattern from mature web frameworks but without any framework magic — a nested module is still just data describing routes.

## Lowering to xiom-http

The `router` module performs the translation from resource descriptions to concrete `xiom-http` registrations. `mount(app, module)` walks a `RestModule`, computes each concrete path via `resolve_path`, and registers the corresponding handler with the underlying HTTP application. This step is intentionally thin and deterministic: it contains no business logic, performs no I/O beyond registration, and produces the same routes for the same input every time. Keeping the router dumb makes the whole system easy to audit and test.

## Contracts and errors

Every entry point carries XIOM contracts. `RestModule.new` requires a non-empty name; `route` requires a non-empty path. Mounting returns `Result[Unit, RestError]` so that route collisions or invalid definitions surface as typed errors rather than panics or silent misconfiguration. This keeps routing failures explicit and diagnosable, consistent with the package's overall contract-first philosophy.
