# xiom.router

> **Status:** `incubating` -- conformance-tested (22/22); not yet published to the XIOM registry.
> **Scope:** pure-XIOM, stdlib-only deterministic HTTP route table: ordered
> registration, exact and `:name` path patterns, byte-exact method matching,
> 404/405 classification with an Allow-list, raw parameter capture.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`; the tests
> add `xiom.test` and `xiom.io`).

## What it is

`xiom.router` is a small, deterministic route table for HTTP-style dispatch.
Routes are registered in order as a method plus a path pattern
(`router_add`), and looked up by method + path (`router_match`). A pattern
segment is either a literal, compared byte-for-byte, or a `:name` parameter
that matches exactly one **non-empty** path segment and captures its raw
text. The **first registered** pattern that matches the path shape *and*
whose method matches wins -- there is no specificity ranking, so
`/users/:id` registered before `/users/me` captures `me` as `id`.

`router_match` classifies every lookup:

- **200** -- matched; `index` is the winning route's registration index and
  `params` holds the captured `:name` segments in path order;
- **405** -- at least one pattern matches the path shape but no registered
  method equals the queried method; `router_allowed_methods` returns the
  deduplicated Allow-list in registration order;
- **404** -- no pattern matches the path shape.

The package is deliberately transport-free: no sockets, no request parsing,
no global state, no I/O. It matches `Str` paths; the caller strips the query
string first, and there is no percent-decoding.

## Install / use

```
xiom pkg install xiom.router@0.1.0
```

```xi
use xiom.router;
use xiom.io;

var r = router_new();
let a = router_add(&mut r, "GET", "/users/:id");   // Ok(0)
let b = router_add(&mut r, "POST", "/users");      // Ok(1)

let m = router_match(&r, "GET", "/users/42");
// m.code == 200, m.index == 0, m.params == [{ name: "id", value: "42" }]

let miss = router_match(&r, "DELETE", "/users");
// miss.code == 405 -- router_allowed_methods(&r, "/users") => ["POST"]
```

## API

| Function | Returns | Description |
|---|---|---|
| `router_new()` | `Router` | Empty route table. |
| `router_add(r, method, pattern)` | `Result[Int, Str]` | Append a route; `Ok(index)` is the new registration index. Validates the method and pattern (see the error catalog). |
| `router_match(r, method, path)` | `RouteMatch` | Look up `method` + `path`; `code` 200/404/405, `index` the first 200 match or -1, `params` captured in path order (empty on 404/405). |
| `router_allowed_methods(r, path)` | `Vec[Str]` | Methods of every pattern whose path shape matches `path`, registration order, deduplicated -- the Allow-list for 405 responses. |
| `router_count(r)` | `Int` | Number of registered routes. |
| `router_method(r, i)` | `Result[Str, Str]` | Method of route `i` in registration order. |
| `router_pattern(r, i)` | `Result[Str, Str]` | Pattern of route `i` in registration order. |

### Types

| Type | Fields | Meaning |
|---|---|---|
| `RouteParam` | `name: Str`, `value: Str` | One captured parameter: the pattern text after `:`, and the raw matched path segment. |
| `RouteMatch` | `code: Int`, `index: Int`, `params: Vec[RouteParam]` | One lookup result. |
| `Router` | `methods: Vec[Str]`, `patterns: Vec[Str]` | The ordered route table; `methods[i]` and `patterns[i]` describe route `i`. |

## Matching rules

- A path or pattern is split by stripping one leading `/` and splitting on
  `/`. `"/"` and `""` both have zero segments (the root); `"/a/"` is
  `["a", ""]`, so **trailing slashes are significant** (`/a` != `/a/`), and
  interior empty segments are literal (`/a//b` matches only `/a//b`).
- A pattern segment that starts with `:` and has at least one character
  after it is a parameter: it matches exactly one **non-empty** path segment
  and captures its raw text. Any other segment must equal the path segment
  byte-for-byte.
- Matching is **registration order only**; the first route whose pattern
  matches the shape and whose method equals the queried method wins. A later
  route can still win for a different method (and 405 is reported only when
  no registered method works at all).
- Method strings are matched **byte-exactly and case-sensitively**
  (`"get"` != `"GET"`), and are never normalized. No method validation is
  performed at registration; any non-empty string is accepted.
- No percent-decoding and no query handling: `router_match` treats `%2F`
  and `?` as ordinary bytes; the caller must strip the query string before
  calling.

## Error catalog

Every message starts with `router: `.

| Message | Raised by | Trigger |
|---|---|---|
| `router: empty method` | `router_add` | `method` is `""`. |
| `router: pattern must start with '/'` | `router_add` | `pattern` is `""` or its first byte is not `/`. |
| `router: empty parameter name` | `router_add` | a pattern segment is a bare `:` with no name after it. |
| `router: index out of range` | `router_method`, `router_pattern` | `i < 0` or `i >= router_count(r)`. |

`router_add` validates before touching the table, so a failed add registers
nothing and returns the registered count unchanged. `router_match` and
`router_allowed_methods` have no error channel: 404/405 travel in the
`RouteMatch`, and a non-matching `path` yields an empty Allow-list.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.router -TimeoutSec 60
```

Expected: the namespace check passes, 22 `[PASS]` lines, and a final
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No specificity ranking.** First registration wins; ordering the table is
  the caller's job.
- **No wildcards, regex or catch-all routes.** Literals and `:name` segments
  only.
- **No percent-decoding and no query parsing.** Raw bytes in, raw bytes out;
  the caller strips the query and decodes as needed.
- **No method normalization or validation.** `get`, `GET` and `Get` are
  three different methods; any non-empty byte string is a legal method.
- **No path validation.** A path without a leading `/` is split as-is; an
  empty pattern is only rejected at `router_add`, and matching is shape-only.
- **No middleware, no handlers, no routing state.** This package is the
  lookup table, not a server or a dispatcher.
- **In-memory only.** No persistence, no file or network I/O, no FFI.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
