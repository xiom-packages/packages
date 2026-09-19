# Service Discovery

> Status: Design stage -- specification only, not yet implemented.

Service discovery in `xiom.micro` answers a single question: *given a logical service name, where do I send this call right now?* The package deliberately does not hard-code any one registry. Instead it exposes a structural `Discovery` interface, and concrete registries (Kubernetes DNS, Consul-like systems, static maps, or a test registry) are adapters that satisfy it. This keeps business code registry-agnostic -- swapping infrastructure never requires touching call sites.

Discovery is split into three cooperating pieces. `discovery.xi` defines the abstraction, `registry.xi` provides the concrete adapters, and `resolver.xi` turns registry results into a single usable `Endpoint` by filtering on health state. Endpoints are typed values (`endpoint.xi`) carrying address, port, region, health, and capability tags -- not bare strings -- so downstream policies (routing, bulkheads, breakers) can reason about them safely.

Several discovery modes are supported by design: a **static registry** for local development, **client-side discovery** for internal service-to-service traffic, **server-side discovery** for simpler deployments behind a load balancer, **Kubernetes DNS/service awareness**, and a deterministic **test registry** for reproducible tests. The choice of mode is a configuration concern, not a code-structure concern.

The XIOM-native angle is that resolution carries contracts. A resolver is expected to `ensure` that the endpoint it returns is currently healthy, and callers get a typed `Result[Endpoint, ServiceError]` rather than a silent fallback to a dead host. Stale or inconsistent resolution is treated as a contract hotspot, so the failure is explicit and observable instead of manifesting later as a mysterious timeout.
