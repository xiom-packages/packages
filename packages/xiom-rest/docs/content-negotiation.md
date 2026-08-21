# Content Negotiation

> Status: Design stage -- specification only, not yet implemented.

Content negotiation lets a single endpoint serve different representations of the same resource based on what the client asks for. In `xiom-rest` this is explicit and typed: JSON is the default representation, and any alternatives (for example a compact form, CSV, or a versioned media type) are registered deliberately rather than inferred by magic. The negotiation layer only chooses *how* to encode a value; it never changes *what* the resource is.

## Parsing the Accept header

`parse_accept(header)` turns an `Accept` header into a ranked `Vec[MediaType]`, where `MediaType { main: Str; sub: Str; quality: Float; }` captures the type, subtype, and the client's quality weighting (`q`). Ranking by quality means a client can express preferences ("JSON if you can, otherwise anything") and the server can honor them predictably. Parsing is tolerant of the header's whitespace and parameter quirks but produces a clean, ordered structure for the selection step.

## Selecting a representation

`negotiate(accept, offered)` matches the client's ranked preferences against the representations the endpoint actually offers and returns the best `MediaType`, or a typed error if nothing acceptable is available. Returning `Result[MediaType, RestError]` makes the "406 Not Acceptable" case a first-class, explicit outcome rather than a silent fallback to an unexpected format. When a client sends no `Accept` header, or accepts anything, the server chooses its default representation (JSON).

## Encoding with typed representations

Each supported format is a `Representation[T] { media_type: MediaType; encode: fn(&T) -> Vec[Int]; }`. Once negotiation picks a media type, `encode(rep, value)` produces the response bytes using that representation's encoder. Tying the encoder to the media type in one value keeps serialization honest: the `Content-Type` the server advertises is exactly the encoder that produced the body, so there is no drift between the declared and actual format. JSON encoding delegates to `xiom-json`.

## Contracts and philosophy

Negotiation follows the package's contract-first stance: inputs are parsed into typed structures, failures surface as typed errors, and there is no hidden global state deciding formats behind the developer's back. The result is content negotiation that is easy to reason about -- a developer can look at the offered representations and the client's `Accept` header and predict exactly which encoder will run.
