# Versioning

> Status: Design stage -- specification only, not yet implemented.

APIs change, and versioning is how `xiom-rest` lets them change without breaking existing clients. The guiding rule is that breaking changes must never be silent: a new incompatible shape lives under a new version, and old versions are retired only with explicit, discoverable deprecation metadata. Versioning is expressed as data on a `RestModule`, so it composes naturally with resource routing.

## Versioning strategies

Two strategies are supported through `VersionPolicy`:

- **URI versioning** (`VersionPolicy::Uri`) places the version in the path, e.g. `/v1/users`. It is the most visible and cache-friendly approach and is easy to route, which is why it is the common default.
- **Header versioning** (`VersionPolicy::Header`) keeps URLs stable and selects a version from a request header. It keeps resource identity clean at the cost of being less obvious to casual consumers and slightly harder to cache.

`versioned(version, module)` wraps a resource module under a version group, and `with_policy(module, policy)` selects how that version is resolved. Both return a `RestModule`, so a versioned resource is still just a composable description.

## Resolving the requested version

At request time, `resolve_version(req, policy)` extracts the version the client is asking for -- from the path segment under URI versioning, or from the negotiated header under header versioning. It returns `Result[Str, RestError]` so that an unknown or unsupported version becomes a typed error (a `400` or `404`-class response with a clear code) rather than a fallthrough to an arbitrary default. Making resolution explicit avoids the classic bug where an unversioned request silently hits the newest, possibly incompatible, handler.

## Deprecation

Retiring a version is a process, not an event. `deprecate(module, meta)` attaches a `Deprecation { since: Str; sunset: Option[Str]; message: Str; }` to a module. This metadata is surfaced to clients (for example via `Deprecation`/`Sunset` response headers and OpenAPI annotations) so consumers get advance, machine-readable notice before an endpoint disappears. The `sunset` field is optional because a version may be marked deprecated well before a removal date is decided.

## Conventions

The recommended defaults are: version by route group or header, never introduce silent breaking changes, and always deprecate with explicit metadata. Because versioning data rides on the same declarative `RestModule` used for routing, the OpenAPI generator can document versions and deprecations automatically, keeping the contract and the documentation in sync.
