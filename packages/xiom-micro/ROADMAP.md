# xiom.micro ROADMAP

## v0.1.0 (Current)
- [x] Core types (HttpMethod, MicroRequest, MicroResponse, MicroHeader, MicroQueryParam, MicroRouteParam)
- [x] Router type with route storage and lookup (router_new, router_route_count, router_find_route, router_has_route)
- [x] Route registration for all HTTP methods (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
- [x] Request builder API (request_new, request_add_header, request_add_query_param, request_set_body)
- [x] Request header helpers (request_get_header, request_has_header)
- [x] Response builder API (response_ok, response_json, response_created, response_not_found, response_internal_error, response_bad_request)
- [x] Response classification helpers (response_is_success, response_is_client_error, response_is_server_error)
- [x] Middleware type with Before/After phases (middleware_new, router_use_middleware)
- [x] Middleware chain evaluation stub with auth check (middleware_evaluate, middleware_evaluate_allowed)
- [x] Route-level middleware attachment (router_route_with_middleware)
- [x] Router dispatch (router_dispatch) with middleware pipeline and route matching
- [x] App builder (app_new, app_get, app_post, app_use_global_middleware, app_start, app_stop)
- [x] Route grouping stubs (route_group, router_group_with_prefix)
- [x] Conformance test suite (10 tests)

## v0.2.0 -- Full Router
- [ ] Pattern-based route matching (e.g. `/users/:id`)
- [ ] Path parameter extraction
- [ ] Method-not-allowed (405) responses
- [ ] Route conflict detection on registration
- [ ] Wildcard and glob route patterns
- [ ] Route ordering and priority

## v0.3.0 -- Middleware Engine
- [ ] Full middleware pipeline with next() chaining
- [ ] Error-handling middleware
- [ ] Request-scoped context propagation
- [ ] Logging middleware (request ID, timing)
- [ ] CORS middleware
- [ ] Compression middleware
- [ ] Rate-limiting middleware with token bucket
- [ ] Body-parsing middleware (JSON, form, multipart)

## v0.4.0 -- HTTP Transport Bridge
- [ ] Integration with xiom.http for network transport
- [ ] Keep-alive connection management
- [ ] Streaming response support
- [ ] Request body streaming
- [ ] Graceful shutdown

## v1.0.0 -- Production Readiness
- [ ] Static file serving
- [ ] Template rendering bridge
- [ ] Request validation schemas
- [ ] Full contract verification on public functions
- [ ] Performance benchmarks
- [ ] Load testing suite
- [ ] OpenAPI/Swagger doc generation stubs
