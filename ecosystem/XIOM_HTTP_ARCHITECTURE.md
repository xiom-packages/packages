# XIOM HTTP — Language-Native HTTP Foundation

XIOM HTTP is the core HTTP primitives package for the XIOM ecosystem. It follows a hybrid architecture: a small, audited, dependency-free core (`xiom-http`) plus separate, optional higher-level packages (`xiom-rest`, `xiom-graphql`, `xiom-websocket`, `xiom-micro`, `xiom-realtime`) built on top of it. This mirrors how mature ecosystems separate a minimal transport/primitives layer from opinionated frameworks, the same way Rust separates `tokio` (async runtime) from `tower` (middleware/service abstraction) from `axum` (web framework).[cite:117][cite:123]

The design borrows the best proven ideas from Express, Fastify, Koa, and NestJS, then reimplements them idiomatically in XIOM using contracts, ownership, structural interfaces, and `Result`-based error handling instead of exceptions, decorators, or hidden magic.

## Why this split

Fastify's plugin/encapsulation model shows that a framework can stay fast and safe by scoping what each route or module can access, rather than exposing one global mutable app object.[cite:118][cite:127] Tower demonstrates that a tiny `Service`/`Layer` abstraction is enough to compose logging, auth, timeouts, and retries without a monolithic framework owning everything.[cite:117][cite:121][cite:123] Koa proved that a small "onion model" middleware core, with explicit `next()` control flow, is more predictable than deeply nested callback chains.[cite:116][cite:130] NestJS proved that structure (modules, dependency injection, decorators) is valuable, but it should be a layer on top of the transport, not baked into it.[cite:102][cite:103][cite:112]

XIOM HTTP takes: Koa's onion-shaped middleware execution, Fastify's schema-first validation and encapsulated plugin contexts, Tower's minimal composable service/layer abstraction, Express's simple and familiar routing ergonomics, and NestJS's modular structure — and expresses all of it through XIOM's `requires`/`ensures`/`invariant` contracts, `Option`/`Result` types, and structural interfaces instead of runtime type-checking or decorators.

## Ecosystem structure

```text
xiom-http/            core: server, client, routing, middleware, json, contracts, static files
xiom-rest/            REST resource routing, content negotiation, pagination, HATEOAS helpers
xiom-graphql/         GraphQL schema, resolvers, execution engine
xiom-websocket/       WebSocket upgrade, framing, pub/sub channels
xiom-micro/           service discovery, RPC clients, circuit breakers, retries
xiom-realtime/        pub/sub, presence, event channels, broadcast rooms
```

Only `xiom-http` is mandatory. Everything else is opt-in, versioned, and independently upgradable — matching the "smaller core, dedicated packages on top" philosophy already decided.[cite:123]

## `xiom-http` scope (core, kept lean)

`xiom-http` is intentionally narrow, comparable to Go's `net/http` or Node's `http` module: primitives only, no ORM, no templating, no business-logic conventions.[cite:113]

- Low-level HTTP server and client
- Basic routing (method + path matching, path params, wildcards)
- Middleware system (onion-style, composable)
- Request/Response types and body handling
- JSON serialization/deserialization
- Contract validation at the HTTP boundary (`requires`/`ensures` on handlers)
- Static file serving
- Plugin/module encapsulation scoping

## Repository scaffold

```text
xiom-http/
├── package.xi
├── README.md
├── ARCHITECTURE.md
├── docs/
│   ├── routing.md
│   ├── middleware-model.md
│   ├── contracts-at-the-edge.md
│   ├── plugin-encapsulation.md
│   ├── json-codec.md
│   └── error-catalog.md
├── src/
│   ├── mod.xi
│   ├── server.xi
│   ├── client.xi
│   ├── listener.xi
│   ├── connection.xi
│   ├── request.xi
│   ├── response.xi
│   ├── headers.xi
│   ├── status.xi
│   ├── method.xi
│   ├── body.xi
│   ├── router/
│   │   ├── mod.xi
│   │   ├── route.xi
│   │   ├── route_table.xi
│   │   ├── path_matcher.xi
│   │   ├── params.xi
│   │   └── wildcard.xi
│   ├── middleware/
│   │   ├── mod.xi
│   │   ├── middleware.xi
│   │   ├── chain.xi
│   │   ├── context.xi
│   │   ├── builtin/
│   │   │   ├── logger.xi
│   │   │   ├── cors.xi
│   │   │   ├── compress.xi
│   │   │   ├── rate_limit.xi
│   │   │   ├── timeout.xi
│   │   │   └── recover.xi
│   ├── plugin/
│   │   ├── mod.xi
│   │   ├── plugin.xi
│   │   ├── scope.xi
│   │   └── registry.xi
│   ├── json/
│   │   ├── mod.xi
│   │   ├── encode.xi
│   │   ├── decode.xi
│   │   └── schema.xi
│   ├── contracts/
│   │   ├── mod.xi
│   │   ├── request_contract.xi
│   │   ├── response_contract.xi
│   │   └── validation_error.xi
│   ├── static/
│   │   ├── mod.xi
│   │   ├── file_server.xi
│   │   └── mime.xi
│   ├── error.xi
│   ├── config.xi
│   └── testing/
│       ├── mod.xi
│       ├── test_client.xi
│       └── fixtures.xi
└── tests/
    ├── routing/
    ├── middleware/
    ├── contracts/
    └── plugins/
```

## Core file responsibilities

### `src/server.xi`
Owns the listener lifecycle, accepts connections, and dispatches requests into the middleware chain and router. Modeled after a minimal async server loop rather than a framework god-object — comparable to how `axum` keeps the server itself thin and pushes behavior into composable `Service`/`Layer` types.[cite:117][cite:123]

### `src/client.xi`
A companion HTTP client sharing the same request/response types, JSON codec, and contract validation so client and server code stay symmetric.

### `src/request.xi` / `src/response.xi`
Immutable request view and an explicit, owned response builder. No hidden mutation of shared state — this maps directly onto XIOM's ownership model instead of Express's mutable `req`/`res` objects.[cite:109][cite:113]

### `src/router/`
Basic method+path routing with typed path parameters. Deliberately simpler than Express's full regex router; complex resource routing belongs in `xiom-rest`, not the core.[cite:106][cite:113]

### `src/middleware/`
Implements the onion model: each middleware wraps the next handler, calls it explicitly, and can act before and after. This is Koa's proven execution model, expressed here as ordinary XIOM functions with explicit `next` closures instead of implicit `async/await` chaining magic.[cite:116][cite:130]

### `src/plugin/`
Implements Fastify-style encapsulation: each plugin gets its own scope, and child scopes inherit from parents but not the reverse. This prevents global mutable app state and keeps large route trees auditable.[cite:118][cite:127]

### `src/json/`
Schema-first JSON encode/decode. Fastify's biggest architectural win is compiling JSON schema into fast serializers and validators ahead of time rather than validating ad hoc — `xiom-http` adopts the same idea, but the schema is a native XIOM `type` with `derive[Eq, Clone]` rather than a separate JSON Schema document.[cite:101][cite:105]

### `src/contracts/`
Turns `requires`/`ensures` into HTTP-boundary validation: a route handler's `requires` clause validates the incoming request, and `ensures` validates the outgoing response before it's sent. This is XIOM's direct answer to Fastify's schema validation, but validation is compiler-enforced rather than library-enforced.[cite:101][cite:105]

### `src/static/`
Static file serving with MIME resolution — comparable to Express's `express.static` but implemented as a narrow, explicit module rather than middleware with implicit fallthrough behavior.[cite:113]

### `src/testing/`
An in-process test client so route and middleware behavior can be tested without a real socket.

## Idiomatic XIOM design translation

| Framework idea | Origin | XIOM HTTP translation |
|---|---|---|
| Middleware as `(req, res, next)` chain | Express | `middleware/chain.xi` — explicit `next` closure, no hidden call order [cite:109][cite:113] |
| Onion-model async middleware | Koa | Same onion execution, but `next()` returns a typed `Result` instead of relying on exceptions/try-catch [cite:116][cite:130] |
| Schema-first validation & fast serialization | Fastify | Route contracts (`requires`/`ensures`) compiled at build time against a typed schema, not a runtime JSON Schema interpreter [cite:101][cite:105] |
| Plugin encapsulation / scoped decorators | Fastify | `plugin/scope.xi` — child scopes inherit parent capabilities, never the reverse [cite:118][cite:127] |
| Modules + Dependency Injection | NestJS | `module` + structural interfaces; XIOM has no DI container — dependencies are passed explicitly as function/struct fields, since XIOM rejects implicit wiring [cite:102][cite:103][cite:112] |
| `Service`/`Layer` composable middleware | Tower/Axum | `middleware.xi` interface: any type with a `handle(req) -> Result[Response, HttpError]` method structurally satisfies the middleware interface [cite:117][cite:123] |
| Router patterns for large apps | Express | Route tables are declared per-module and merged explicitly at startup, avoiding hidden global route registration [cite:106][cite:113] |

## Contract-first HTTP handlers

The signature difference from Node frameworks is that validation and postconditions are part of the function type, not a separate middleware call:

```xiom
module api.users

use xiom_http.contracts
use xiom_http.json

pub type CreateUserRequest = {
  name:  Str;
  email: Str;
  invariant: name.len() > 0;
  invariant: email.contains("@");
} derive[Clone, Display]

pub type UserResponse = {
  id:   UInt;
  name: Str;
} derive[Eq, Clone, Display]

pub async fn handle_create_user(req: HttpRequest) -> Result[HttpResponse, HttpError]
  requires: req.body_as[CreateUserRequest]() is Ok
  ensures:  result is Ok => result.status() == Status.Created
{
  let payload = req.body_as[CreateUserRequest]()?
  let user = users.create(payload.name, payload.email)?
  return Ok(HttpResponse.json(Status.Created, UserResponse{ id: user.id, name: user.name }))
}
```

Because `requires` is checked before the handler body runs, malformed requests are rejected the same way Fastify rejects invalid input before business logic executes — except the rejection logic is compiler-verified rather than a runtime schema library.[cite:101][cite:105]

## Middleware chain (Koa-style onion, XIOM-native)

```xiom
pub fn logger_middleware(ctx: &mut Context, next: NextFn) -> Result[(), HttpError] {
  let start = clock.now()
  next(ctx)?
  let elapsed = clock.now() - start
  io.print(ctx.request.method.to_str() + " " + ctx.request.path + " " + elapsed.to_str())
  return Ok(())
}
```

`next` is an explicit function value, not an implicit `await next()` inside hidden framework machinery — matching XIOM's "explicit over implicit" principle while preserving Koa's proven before/after control flow.[cite:116][cite:130]

## Plugin encapsulation (Fastify-style, XIOM-native)

```xiom
pub fn register_admin_scope(app: &mut App) {
  var scope = app.child_scope("admin")
  scope.use(auth_middleware)
  scope.route(Method.GET, "/admin/stats", handle_stats)
  // child_scope of scope inherits auth_middleware; sibling scopes do not
}
```

Scopes are ordinary values with ownership rules — a scope cannot leak into a sibling because XIOM's borrow rules prevent storing a mutable reference to it outside its own lexical block, which naturally enforces Fastify's encapsulation guarantee at compile time rather than at runtime.[cite:118][cite:127]

## Extension packages

### `xiom-rest`
Resource-oriented routing, pagination helpers, content negotiation, and conventions similar to Express-style REST scaffolding, but built as ordinary structural interfaces over `xiom-http` routes rather than a separate router engine.[cite:106][cite:113]

### `xiom-graphql`
Schema definition, resolvers, and an execution engine that reuses `xiom-http`'s JSON codec and contract system for input/output validation.

### `xiom-websocket`
Upgrade handshake, frame parsing, and channel abstractions built on the same connection primitives as the core server.

### `xiom-micro`
Service discovery, typed RPC clients, retries, and circuit breakers — the microservices layer, kept fully separate so monolith users never pay for it.

### `xiom-realtime`
Pub/sub channels, presence tracking, and broadcast rooms, layered on `xiom-websocket` and `xiom-micro`.

## Why no built-in dependency injection container

NestJS's DI container is powerful but implicit: providers are resolved by the framework at runtime based on decorators and metadata reflection.[cite:102][cite:103][cite:108][cite:112] XIOM rejects implicit resolution by design — there are no default arguments, no hidden constructors, and no reflection-driven wiring. Instead, `xiom-http` recommends explicit composition: services are constructed once at startup and passed into route modules as plain struct fields, which keeps every dependency visible in the function signature and fully inspectable by both humans and AI tooling.

## Design principles carried from XIOM language spec

- No implicit middleware ordering — the chain is an explicit, ordered list.
- No hidden allocations in the hot request path — buffers and body readers are explicitly owned.
- No exceptions — every handler returns `Result[HttpResponse, HttpError]`.
- No null — absent headers, params, or query values are `Option[Str]`.
- Contracts replace ad hoc validation middleware — `requires`/`ensures` are checked by the compiler-backed runtime guard layer, not a third-party schema library.
- `derive[Eq, Clone, Display]` on request/response DTOs removes an entire class of hand-written serialization bugs.

## Summary comparison table

| Concern | Express | Fastify | Koa | NestJS | Tower/Axum | xiom-http |
|---|---|---|---|---|---|---|
| Core size | Small | Small | Very small | Large (framework) | Very small | Small, dependency-free [cite:113][cite:123] |
| Middleware model | Callback chain | Hooks + plugins | Onion/async | Interceptors/guards | `Service`/`Layer` | Onion, explicit `next`, typed `Result` [cite:116][cite:117] |
| Validation | Manual/3rd-party | Schema-compiled | Manual/3rd-party | Decorator-based (`class-validator`) | Manual | Compiler-checked contracts (`requires`/`ensures`) [cite:101][cite:102] |
| Structure | Unopinionated | Plugin encapsulation | Unopinionated | Modules + DI | Tower layers | Modules + explicit scopes, no DI container [cite:112][cite:118] |
| Extension model | Middleware everywhere | Plugin registry | Middleware everywhere | Nest modules | Layer composition | Separate versioned packages (`xiom-rest`, etc.) [cite:123] |

This gives XIOM HTTP a foundation that is as lean as Go's `net/http`, as fast-by-design as Fastify's schema compilation, as predictable as Koa's onion model, as structured as NestJS's modules — but expressed entirely through XIOM's own contract system, ownership rules, and structural interfaces instead of borrowing any runtime-validation or reflection-based machinery.
