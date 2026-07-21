# xiom-rest ROADMAP

## v0.1.0 (Current)
- [x] Core type system (RestClient, RestResponse, RestHeader, RestRequest, RestMethod, RestError)
- [x] Client builder API (client_new, client_set_timeout, client_add_header, client_remove_header)
- [x] Request builder API (request_new, request_add_header, request_add_query_param, request_set_body)
- [x] URL builder (request_build_url with path joining and query params)
- [x] Method enum with string conversion (method_to_str, method_from_str)
- [x] `extern "C"` libcurl FFI block (curl_easy_init, curl_easy_setopt, curl_easy_perform, curl_easy_getinfo, curl_easy_cleanup, curl_easy_strerror)
- [x] `extern "C"` XIOM FFI bridge (xiom_str_to_cstr, xiom_free_cstr, xiom_alloc, xiom_free_ptr, xiom_write_byte, xiom_read_byte)
- [x] Convenience methods (client_get, client_post, client_put, client_delete, client_patch)
- [x] Response helpers (response_is_success, response_is_client_error, response_is_server_error, response_status_category)
- [x] Error constructors (error_not_found, error_bad_request, error_internal, error_unauthorized)
- [x] Error-to-response mapping (error_to_response)
- [x] Conformance test suite (10 tests)

## v0.2.0 — Full libcurl Integration
- [ ] Working libcurl transport layer (response capture via temp files or callback)
- [ ] Custom header injection via curl_slist_append
- [ ] TLS/SSL configuration (verify peer, verify host, client certs)
- [ ] HTTP authentication (Basic, Bearer, Digest)
- [ ] Request timeout and connection timeout configuration
- [ ] Redirect following and policy
- [ ] Response body streaming

## v0.3.0 — Advanced Client Features
- [ ] Connection pooling and reuse
- [ ] Request retry with exponential backoff
- [ ] Circuit breaker pattern
- [ ] Rate limiting middleware
- [ ] Response caching (ETag, If-None-Match)
- [ ] Multipart form upload
- [ ] File download with progress
- [ ] Request/response logging middleware

## v0.4.0 — Resource Layer
- [ ] RestModule resource builder (collection + item routes)
- [ ] Route definition and mounting
- [ ] Path parameter extraction
- [ ] Nested subresource support
- [ ] Pagination primitives (page-based and cursor-based)
- [ ] Filtering and sorting query parameter parsing
- [ ] Content negotiation (Accept header parsing)
- [ ] Versioning strategies (URI and header-based)

## v0.5.0 — Code Generation & Docs
- [ ] OpenAPI document generation from resource definitions
- [ ] JSON Schema generation from XIOM types
- [ ] Contract-to-OpenAPI mapping
- [ ] API client code generation stubs

## v1.0.0 — Production Readiness
- [ ] Full contract verification on all public functions
- [ ] Structured error responses (RFC 7807 Problem Details)
- [ ] HATEOAS link generation
- [ ] Performance benchmarks
- [ ] Load testing suite
- [ ] Security audit (input validation, header injection)
