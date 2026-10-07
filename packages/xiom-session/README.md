# xiom.session

> **Status:** `incubating` -- conformance-tested (24/24); not yet published to the XIOM registry.
> **Scope:** pure-XIOM, stdlib-only in-memory session store: CSPRNG session ids
> as 32 lowercase hex characters, Str key/value entries, absolute TTL with an
> explicit caller clock, and exact `Set-Cookie` header rendering.
> **Deps:** `xiom.std` only (`xiom.crypto`, `xiom.string`,
> `xiom.string.compare`; the tests add `xiom.test` and `xiom.io`).

## What it is

`xiom.session` is a small, deterministic session store for web-style state.
Sessions are created with `session_create`, which draws 16 bytes from
`xiom.crypto.secure_random_bytes` and renders them as a 32-character lowercase
hex id. Each session owns an ordered list of opaque Str key/value entries and
an absolute expiry instant in caller-supplied milliseconds. The module **never
reads the system clock**: every expiring operation takes `now_ms` explicitly,
so behavior is deterministic given the caller's clock.

**Expiry semantics.** A session is valid while `now_ms < expires_ms`; at
`now_ms == expires_ms` it is expired. Expired sessions are never returned by
`session_get` / `session_value` and never accept `session_set` or
`session_touch`, but they stay stored until `session_prune` or
`session_remove` discards them -- so `session_count` counts stored sessions,
expired ones included.

**Cookie rendering.** `session_cookie_header` produces the exact header value
`name=id; Path=/; HttpOnly; SameSite=Lax; Max-Age=<n>`, appending `; Secure`
when asked; `Max-Age <= 0` clamps to 0 (the deletion form), and
`session_cookie_clear` renders `name=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`.

The package is deliberately transport-free: no sockets, no request parsing,
no persistence, no global state, no I/O. Session ids are validated by shape
with `session_id_valid` (exactly 32 lowercase hex characters; uppercase hex is
rejected).

## Install / use

```
xiom pkg install xiom.session@0.1.0
```

```xi
use xiom.session;
use xiom.io;

var s = session_store_new(30 * 60 * 1000);        // 30-minute default TTL
let created = session_create(&mut s, 1_000_000);  // Ok("3f2a...") 32 hex chars
let id = created.value;

if session_set(&mut s, id, "user", "alice", 1_000_100) {
  // ... later
  let v = session_value(&s, id, "user", 1_000_200); // Some("alice")
}

// Slide the expiry by another TTL
let extended = session_touch(&mut s, id, 1_000_300);

// Renew the id while keeping the entry data (login rotation)
let rotated = session_rotate(&mut s, id, 1_000_400); // Ok(new_id)

// Set-Cookie for the login response
let header = session_cookie_header("sid", rotated.value, 1800, true);
// "sid=<id>; Path=/; HttpOnly; SameSite=Lax; Max-Age=1800; Secure"
```

## API

| Function | Returns | Description |
|---|---|---|
| `session_store_new(ttl_ms)` | `SessionStore` | Empty store; `ttl_ms <= 0` clamps to 1. |
| `session_store_ttl_ms(s)` | `Int` | Configured default lifetime in milliseconds (>= 1). |
| `session_count(s)` | `Int` | Stored sessions, expired-but-unswept included. |
| `session_id_valid(id)` | `Bool` | Exactly 32 chars, each `0-9a-f` (lowercase only). |
| `session_create(s, now_ms)` | `Result[Str, Str]` | `Ok(id)`; session expires at `now_ms + ttl_ms`, entries empty. |
| `session_get(s, id, now_ms)` | `Option[Session]` | `Some(session)` when stored and `now_ms < expires_ms`; an independent copy. |
| `session_set(s, id, key, value, now_ms)` | `Bool` | Overwrite an existing key in place, else append; never extends expiry; false when absent/expired. |
| `session_value(s, id, key, now_ms)` | `Option[Str]` | Value of `key` when the session is live; None when absent/expired/key missing. |
| `session_touch(s, id, now_ms)` | `Bool` | `expires_ms = now_ms + ttl_ms`; false when absent/expired. |
| `session_remove(s, id)` | `Bool` | Remove the stored session (expired or not); false when absent. |
| `session_rotate(s, old_id, now_ms)` | `Result[Str, Str]` | `Ok(new_id)`: entries copied, created/expiry reset, old id removed. |
| `session_prune(s, now_ms)` | `Int` | Remove every session with `now_ms >= expires_ms`; returns the count. |
| `session_cookie_header(name, id, max_age_secs, secure)` | `Str` | Exact `Set-Cookie` header value (see above). |
| `session_cookie_clear(name)` | `Str` | Exact deletion header value. |

### Types

| Type | Fields | Meaning |
|---|---|---|
| `SessionEntry` | `key: Str`, `value: Str` | One opaque key/value pair. |
| `Session` | `id: Str`, `entries: Vec[SessionEntry]`, `created_ms: Int`, `expires_ms: Int` | One stored session; entries in insertion order. |
| `SessionStore` | `sessions: Vec[Session]`, `ttl_ms: Int` | The in-memory store; `ttl_ms >= 1`. |

## Semantics

- **Clock discipline.** No function calls the system clock. `now_ms` is
  always the caller's clock reading and is compared against the absolute
  `expires_ms`; `now_ms` going backwards never extends a session (only
  `session_touch` writes an expiry, and it writes `now_ms + ttl_ms`).
- **Expiry boundary.** Valid while `now_ms < expires_ms`; expired at
  `now_ms == expires_ms` and later. `session_prune` removes sessions at the
  same boundary.
- **Id shape.** 32 lowercase hex characters (128 bits from the OS CSPRNG).
  Each create/rotate draw is checked against every stored id and redrawn on
  collision, up to 8 draws total.
- **Rotation.** `session_rotate` mints a new id, deep-copies the entries in
  order, resets `created_ms = now_ms` and `expires_ms = now_ms + ttl_ms`, and
  removes the old id. An absent or expired old id errs and changes nothing.
- **Removal.** `session_remove` needs no clock and removes expired-but-stored
  sessions too; `session_prune` is the clock-aware bulk form.
- **Cookie text.** Headers are rendered raw (no escaping, no id validation);
  attribute order is exactly `Path`, `HttpOnly`, `SameSite=Lax`, `Max-Age`,
  then `Secure` when requested.

## Error catalog

Every message starts with `session: `. Messages are static strings.

| Message | Raised by | Trigger |
|---|---|---|
| `session: id generation failed` | `session_create`, `session_rotate` | 8 consecutive secure id draws all collided with stored ids. |
| `session: not found or expired` | `session_rotate` | `old_id` is absent or expired at `now_ms`. |

`session_create` stores nothing on Err. `session_rotate` leaves the old
session in place on either Err. `session_get` / `session_set` /
`session_value` / `session_touch` / `session_remove` / `session_prune` have
no error channel: `false`/`None`/`0` report absence and expiry.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.session -TimeoutSec 60
```

Expected: the namespace check passes, 24 `[PASS]` lines, and a final
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **In-memory only.** No persistence, no file or network I/O, no FFI.
- **No locking / concurrency support.** A store is single-thread state; the
  caller serializes access.
- **Linear scans.** Lookups are O(stored sessions) and `session_set` copies a
  session's entry list; the store is sized for modest session counts.
- **No eviction policy.** Live sessions are never evicted; only expiry
  (prune/remove) shrinks the store.
- **No cookie parsing.** `session_cookie_header` / `session_cookie_clear`
  render text; parsing `Cookie` headers is out of scope (see `xiom.cookie`).
- **Opaque values.** Entry keys and values are raw Str; no typing, encoding
  or serialization.
- **Cookies are not hardened here.** `Secure`, `HttpOnly` and `SameSite=Lax`
  are emitted verbatim as configured; transport security is the caller's job.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
