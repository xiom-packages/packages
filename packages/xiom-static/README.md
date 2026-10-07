# xiom.static

> **Status:** `incubating` -- conformance-tested (25/25); not yet published to the XIOM registry.
> **Scope:** pure-XIOM, stdlib-backed static-file response planning: MIME typing,
> stat and sha256 ETags, hand-rolled RFC 1123 dates, Cache-Control policy
> strings, a single byte-range parser, a lexical path-traversal guard and one
> orchestration function that returns status + ordered headers + a
> binary-safe body.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`,
> `xiom.convert.percent`, `xiom.io`, `xiom.io.fs`, `xiom.net.mime`,
> `xiom.time`; the tests add `xiom.test` and `xiom.string.compare`).

## What it is

`xiom.static` plans static-file HTTP responses without a server framework:
the caller owns sockets and request parsing, the package answers the file
questions. `static_serve(root, url_path, if_none_match, range_header,
is_head, policy)` runs the whole pipeline -- resolve the untrusted path
against a trusted root, stat the file, derive `Content-Type`, the O(1)
stat ETag, `Last-Modified` and `Cache-Control`, evaluate `If-None-Match`,
parse a single `Range`, read the bytes -- and returns a `StaticResult`:

| Status | When | Body |
|---|---|---|
| **200** | a readable regular file, no matching validator, no usable Range | full file bytes |
| **206** | a satisfiable single range (`bytes=a-b`, `bytes=a-`, `bytes=-n`) | the exact range bytes |
| **304** | `If-None-Match` matches (ETag wins over Range) | empty |
| **404** | resolve/stat/read error, directory, or file > 2 GiB - 1 | empty |
| **416** | well-formed but unsatisfiable range (`Content-Range: bytes */size`) | empty |

A malformed `Range` header is ignored (full 200), and `HEAD` returns the
same status and headers with an empty body -- including the would-be
`Content-Length` -- so header-only clients work unchanged.

The body is a `Vec[UInt8]` end to end; file bytes never travel through a
`Str` (a `Str` round-trip corrupts `0x00` and bytes above `0x7A`).
`static_body_ints` is the sanctioned 0..255 bridge for APIs that only
accept `Vec[Int]`.

## Install / use

```
xiom pkg install xiom.static@0.1.0
```

```xi
use xiom.static;

let policy = StaticPolicy{ max_age: 3600; immutable: false; must_revalidate: false; no_store: false };

// GET /assets/logo.png, no validators, no range
let r = static_serve("C:/srv/public", "assets/logo.png", "", "", false, &policy);
// r.status == 200, r.headers: Content-Type/Content-Length/ETag/Last-Modified/
// Cache-Control/Accept-Ranges, r.body: the PNG bytes

// conditional revalidation
let again = static_serve("C:/srv/public", "assets/logo.png", r_etag, "", false, &policy);
// again.status == 304 when r_etag is the served ETag, "*", or W/-prefixed

// a range request
let part = static_serve("C:/srv/public", "assets/logo.png", "", "bytes=100-199", false, &policy);
// part.status == 206, part.headers has "Content-Range: bytes 100-199/<size>"
```

## API

| Function | Returns | Description |
|---|---|---|
| `static_mime_of(path)` | `Str` | MIME type from the extension (`xiom.net.mime.mime_type_of`); unknown -> `application/octet-stream`. |
| `static_etag_stat(size, mtime)` | `Str` | Primary quoted ETag `"<size>-<mtime>"` -- O(1), no file read. |
| `static_etag_sha256(data)` | `Str` | Strong quoted SHA-256 hex ETag over the bytes (`xiom.net.mime.etag_new`). |
| `static_etag_matches(etag, if_none_match)` | `Bool` | `If-None-Match` evaluation: `*`, exact, `W/` prefix, comma lists. |
| `static_http_date(epoch)` | `Str` | RFC 1123 `W, DD Mon YYYY HH:MM:SS GMT`; negative epochs clamp to the Unix epoch. |
| `static_last_modified(epoch)` | `StaticHeader` | `Last-Modified` header carrying `static_http_date(epoch)`. |
| `static_cache_control(p)` | `Str` | `<public|private>, max-age=<N>[, immutable][, must-revalidate][, no-store]`; negative max-age clamps to 0. |
| `static_range_parse(header, size)` | `StaticRange` | Single-range parser: `bytes=a-b`, `bytes=a-`, `bytes=-n`; malformed -> `valid=false`, `a >= size` -> unsatisfiable, end clamped. |
| `static_content_range(start, end, size)` | `StaticHeader` | `Content-Range: bytes s-e/size` (inclusive). |
| `static_accept_ranges()` | `StaticHeader` | `Accept-Ranges: bytes`. |
| `static_resolve_path(root, url_path)` | `Result[Str, Str]` | Lexical guard + manual join; rejects raw `%00`, bad escapes, empty, absolute, `..` segments, backslash and colon. |
| `static_serve(root, url_path, if_none_match, range_header, is_head, policy)` | `StaticResult` | Full 200/206/304/404/416 pipeline with HEAD support. |
| `static_body_ints(body)` | `Vec[Int]` | Byte-preserving `Vec[UInt8]` -> `Vec[Int]` bridge (0..255). |

### Types

| Type | Fields | Meaning |
|---|---|---|
| `StaticHeader` | `name: Str`, `value: Str` | One response header. |
| `StaticRange` | `valid: Bool`, `unsatisfiable: Bool`, `start: Int`, `end: Int` | One parsed range; inclusive offsets. |
| `StaticPolicy` | `max_age: Int`, `immutable: Bool`, `must_revalidate: Bool`, `no_store: Bool` | Cache policy inputs. |
| `StaticResult` | `status: Int`, `headers: Vec[StaticHeader]`, `body: Vec[UInt8]` | One planned response. |

## Response shapes

Headers are emitted in a fixed order, so tests and caches see stable bytes:

- **200** (`GET`): `Content-Type`, `Content-Length`, `ETag`, `Last-Modified`,
  `Cache-Control`, `Accept-Ranges`.
- **206**: `Content-Type`, `Content-Length` (range length), `Content-Range`,
  `ETag`, `Last-Modified`, `Cache-Control`, `Accept-Ranges`.
- **304**: `ETag`, `Last-Modified`, `Cache-Control` (no entity headers).
- **416**: `Content-Range: bytes */<size>`, `Accept-Ranges`.
- **404**: no headers, no body.
- **HEAD**: identical headers and status to the matching `GET` (including
  the would-be `Content-Length` for 200/206), but the body is empty.

## Matching and caching rules

- **Validators**: the stat ETag (`"<size>-<mtime>"`) is primary;
  `static_etag_sha256` is available when a content-stable tag is required.
  `If-None-Match` is evaluated before `Range`, so a matching validator
  yields 304 even when a `Range` header is present.
- **Ranges**: one range only; `bytes=a-b` (a <= b), `bytes=a-` and
  `bytes=-n` are accepted, case-sensitive `bytes=` prefix. Everything else
  -- comma lists, whitespace, signs, a second dash, reversed bounds, a
  suffix of 0 -- is either malformed (`valid=false`, ignored -> 200) or
  unsatisfiable (`bytes=-0`, first byte >= size -> 416).
- **Traversal guard**: `static_resolve_path` rejects a raw `%00` escape
  before decoding (the stdlib decoder truncates at NUL), then a decoded
  empty path, a leading `/`, any `..` segment under `/` or `\`, any
  backslash and any colon (Windows drive/ADS). `"."` segments are allowed.
  This is a lexical guard: there is no symlink resolution and no case
  folding.
- **Method**: `static_serve` has no method parameter; the caller decides
  which methods are eligible and passes `is_head` for `HEAD`.

## Error catalog

`static_resolve_path` is the only function with an error channel; every
message starts with `static: ` and the checks run in this order:

| Message | Trigger |
|---|---|
| `static: NUL byte in path` | raw `%00` escape (checked before decoding) or a decoded NUL byte. |
| `static: invalid percent-encoding` | `percent_decode` failed (truncated or malformed escape). |
| `static: empty path` | the decoded path is empty. |
| `static: absolute path` | the decoded path starts with `/`. |
| `static: parent segment in path` | a `..` segment delimited by `/` or `\` (raw or percent-encoded). |
| `static: backslash in path` | any `\` in the decoded path. |
| `static: drive colon in path` | any `:` in the decoded path. |

`static_serve` never surfaces these strings: any failure collapses to 404.

## Testing

From the repository root:

```
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
& .\scripts\port.ps1 -Package xiom.static -TimeoutSec 60
```

Expected: the namespace check passes, 25 `[PASS]` lines, and a final
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`. The suite is
hermetic: fixtures live under `fs.fs_temp_dir()` (`xiom_static_*`) and are
removed with `io.remove_file`; no network, no clock dependence beyond file
mtimes.

## Limitations

- **No streaming or mmap.** A 200 reads the whole file into memory; files
  above 2 GiB - 1 are rejected (404) because `fs_read_range` seeks with an
  `Int32` offset.
- **No multi-range, no gzip, no directory index.** One range per request;
  directories answer 404.
- **No symlink containment.** The guard is lexical only; a symlink inside
  the root that points outside it is followed by the OS.
- **No If-Modified-Since parsing.** There is no public HTTP-date parser in
  the stdlib; only `If-None-Match` is evaluated. `Last-Modified` is produced
  for clients and caches.
- **No case folding or Unicode normalization** on paths; bytes are compared
  as sent (after percent-decoding).
- **No auth, cookies, compression negotiation or MIME overrides**; those
  belong to the caller's server layer.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
