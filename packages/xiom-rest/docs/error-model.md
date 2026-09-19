# Error Model

> Status: Design stage -- specification only, not yet implemented.

A predictable error model is what makes an API pleasant to consume. `xiom.rest` maps typed XIOM errors onto stable HTTP status codes and a consistent, machine-readable response body. There are no silent failures: every error path is a typed value that flows through `Result`, and the mapping from domain error to HTTP response is explicit and centralized.

## The RestError type

The core type is `RestError { code: Str; status: Int; message: Str; details: Option[Str]; }`. The `code` is a stable, machine-readable string (for example `"user_not_found"`) that clients can branch on without parsing prose; the `status` is the HTTP status code; `message` is a human-readable summary; and `details` optionally carries additional context. Separating a stable `code` from a human `message` is deliberate -- the message can be improved or localized over time while the code remains a durable part of the contract.

## Constructing errors

Common cases have named constructors -- `not_found`, `bad_request`, `conflict`, `unprocessable` -- so handlers express intent directly rather than juggling raw status integers. The general constructor `RestError.new(code, status, message)` carries the contract `requires status >= 100, status < 600`, which prevents nonsensical status codes from ever reaching a client. Because these are ordinary typed values, they can be returned, matched on, and tested like any other data.

## Mapping to HTTP

`map_status(err)` resolves the HTTP status code for an error, and `to_response(err)` renders it into a full `HttpResponse` with a stable body shape (via the `ErrorEnvelope`). Centralizing this mapping means every endpoint reports errors identically: the same field names, the same status conventions, the same code vocabulary. Clients therefore only need to learn the error format once. Domain errors from lower layers are translated at the REST boundary, so internal error types never leak directly into responses.

## Conventions

The default conventions are: use structured error bodies, map domain errors to stable HTTP status codes, and always include a machine-readable error code. Validation and parsing failures from the filtering, sorting, pagination, and negotiation layers all funnel through `RestError`, so a `400` from a bad filter looks structurally identical to a `400` from a malformed page request. This uniformity is what lets client code handle errors generically and confidently.
