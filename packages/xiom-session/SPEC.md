# xiom.session -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.64.0 on
2026-10-07; not published).
Manifest: `package.xi` (`xiom.session`, version `0.1.0`).
Module: `src/session.xi` (`module xiom.session`).
Depends on `xiom.std` (`xiom.crypto`, `xiom.string`, `xiom.string.compare`).
No FFI. Pure XIOM.

## 1. Scope

An in-memory session store with CSPRNG session ids, opaque Str key/value
entries, absolute expiry in caller-supplied milliseconds, and exact
`Set-Cookie` header rendering. Three public types and fourteen public
functions:

```xi
pub type SessionEntry = { key: Str; value: Str; }
pub type Session = { id: Str; entries: Vec[SessionEntry]; created_ms: Int; expires_ms: Int; }
pub type SessionStore = { sessions: Vec[Session]; ttl_ms: Int; }

pub fn session_store_new(ttl_ms: Int) -> SessionStore
pub fn session_store_ttl_ms(s: &SessionStore) -> Int
pub fn session_count(s: &SessionStore) -> Int
pub fn session_id_valid(id: Str) -> Bool
pub fn session_create(s: &mut SessionStore, now_ms: Int) -> Result[Str, Str]
pub fn session_get(s: &SessionStore, id: Str, now_ms: Int) -> Option[Session]
pub fn session_set(s: &mut SessionStore, id: Str, key: Str, value: Str, now_ms: Int) -> Bool
pub fn session_value(s: &SessionStore, id: Str, key: Str, now_ms: Int) -> Option[Str]
pub fn session_touch(s: &mut SessionStore, id: Str, now_ms: Int) -> Bool
pub fn session_remove(s: &mut SessionStore, id: Str) -> Bool
pub fn session_rotate(s: &mut SessionStore, old_id: Str, now_ms: Int) -> Result[Str, Str]
pub fn session_prune(s: &mut SessionStore, now_ms: Int) -> Int
pub fn session_cookie_header(name: Str, id: Str, max_age_secs: Int, secure: Bool) -> Str
pub fn session_cookie_clear(name: Str) -> Str
```

Private helpers: `_byte`, `_hex_digit`, `_hex_encode`, `_dec_str`,
`_store_find`, `_entry_find`, `_entries_copy`, `_generate_id`. The store is a
single `Vec[Session]` scanned linearly by id; entries are structs
(`SessionEntry`), never tuples.

## 2. Non-goals

- **No system clock.** The module never reads wall time; every expiring
  operation takes `now_ms` from the caller.
- **No persistence, I/O, FFI or global state.** The store is in-memory value
  state that travels by reference.
- **No concurrency or locking.** One store is single-thread state.
- **No cookie parsing, no header assembly, no HTTP transport.**
- **No value typing, encoding or serialization.** Keys and values are opaque
  Str.
- **No eviction policy for live sessions.** Only expiry removes sessions.
- **No id hardening beyond shape.** Ids are opaque bearer tokens; the store
  does not sign, hash or redact them.

## 3. Storage model and expiry semantics

- `SessionStore.sessions` holds sessions in insertion order (expired but
  unswept ones included). `session_count` returns `sessions.len()` and does
  not consult a clock.
- `SessionStore.ttl_ms` is clamped to `>= 1` by `session_store_new`
  (`ttl_ms <= 0` -> 1) and is the default lifetime applied by
  `session_create`, `session_touch` and `session_rotate`.
- A session is **valid** while `now_ms < expires_ms`; at
  `now_ms == expires_ms` it is **expired**. Expiry is absolute: `session_set`
  never changes `expires_ms`; `session_touch` replaces it with
  `now_ms + ttl_ms` (even when that shortens it, e.g. after the clock moves
  backwards).
- Expired sessions are never returned (`session_get`, `session_value` ->
  None) and never accept writes (`session_set`, `session_touch` -> false),
  but they remain stored. `session_prune` removes every session with
  `now_ms >= expires_ms` and returns the count; `session_remove` removes a
  stored session regardless of expiry and needs no clock.
- Entries are ordered as inserted. `session_set` overwrites the value of the
  first entry whose key matches byte-exactly (position preserved) and appends
  otherwise, so a store built only through the API never holds duplicate
  keys. `session_value` returns the first matching entry.
- `session_get` returns an independent deep copy of the session: later store
  mutations never change an earlier result and vice versa.

## 4. Id generation

- `session_create` and `session_rotate` draw 16 bytes from
  `xiom.crypto.secure_random_bytes` (OS entropy; Windows ProcessPrng /
  RtlGenRandom, `/dev/urandom` elsewhere) and render them as 32 lowercase hex
  characters, two per byte.
- Each drawn id is compared against every stored session id
  (`str_compare`). On collision the draw is retried, up to **8 draws total**;
  when every draw collides the functions return
  `Err("session: id generation failed")` (`session_create` stores nothing;
  `session_rotate` leaves the old session in place).
- `session_id_valid` accepts exactly 32 bytes, each in `0-9a-f` (lowercase
  only). Uppercase hex, shorter/longer strings and non-hex bytes are
  rejected. The header functions do **not** validate ids; they render the
  caller's text raw.

## 5. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `session_store_new(ttl_ms)` | any Int | empty `SessionStore`; `ttl_ms <= 0` clamps to 1 | none |
| `session_store_ttl_ms(s)` | store | configured `ttl_ms >= 1` | none |
| `session_count(s)` | store | stored session count (expired included) | none |
| `session_id_valid(id)` | any Str | shape bool (32 lowercase hex) | none |
| `session_create(s, now_ms)` | store, clock | `Ok(id)`; entries empty; `expires_ms = now_ms + ttl_ms` | `session: id generation failed` (nothing stored) |
| `session_get(s, id, now_ms)` | store, id, clock | `Some(Session)` copy when stored and `now_ms < expires_ms`; else None | none |
| `session_set(s, id, key, value, now_ms)` | store, id, key, value, clock | true when written (overwrite in place or append) | none; false when absent/expired |
| `session_value(s, id, key, now_ms)` | store, id, key, clock | `Some(value)` for the first matching key when live | none; None when absent/expired/key missing |
| `session_touch(s, id, now_ms)` | store, id, clock | true and `expires_ms = now_ms + ttl_ms` when stored and live | none; false when absent/expired |
| `session_remove(s, id)` | store, id | true when a stored session was removed (expired or not) | none; false when absent |
| `session_rotate(s, old_id, now_ms)` | store, old id, clock | `Ok(new_id)`; entries copied in order; `created_ms = now_ms`; `expires_ms = now_ms + ttl_ms`; old id removed | `session: not found or expired` (store unchanged); `session: id generation failed` (old left in place) |
| `session_prune(s, now_ms)` | store, clock | count of sessions removed (`now_ms >= expires_ms`) | none |
| `session_cookie_header(name, id, max_age_secs, secure)` | any Str/Int/Bool | exact header text (section 5.1) | none |
| `session_cookie_clear(name)` | any Str | exact deletion text (section 5.1) | none |

### 5.1 Cookie headers

`session_cookie_header` renders, in exactly this order:

```
<name>=<id>; Path=/; HttpOnly; SameSite=Lax; Max-Age=<n>
```

followed by `; Secure` when `secure` is true. `max_age_secs <= 0` clamps to
`0`; `<n>` is the plain decimal rendering (no sign, no padding).
`session_cookie_clear` renders:

```
<name>=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0
```

Both render `name` and `id` raw: no escaping, no validation, no trimming.

### 5.2 Invariants

- `session_count(s) == s.sessions.len()` at all observable times.
- `session_store_ttl_ms(s) >= 1` always.
- A successful `session_create`/`session_rotate` returns a valid id
  (`session_id_valid` true) not present in the store before the call.
- `session_set`/`session_touch` never modify a session at
  `now_ms >= expires_ms`, and never modify `expires_ms` other than
  `session_touch` setting `now_ms + ttl_ms`.
- `session_prune(s, now)` leaves exactly the sessions with
  `expires_ms > now`; the number removed equals the pre-count minus the
  post-count.
- `session_rotate` on success preserves the entry list (key/value order and
  content) and the store count; on either Err the store is byte-for-byte
  unchanged.
- `session_get` results are independent copies (see section 3).

## 6. Test plan

`tests/test_conformance.xi` (module `session_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality goes through
`xiom.string.compare.str_compare` via the local `streq` helper; every Vec
element read is bound to a typed local. Session ids are drawn from the OS
CSPRNG, so checks pin shape, uniqueness and resolvability rather than any
specific id value. Read-only calls are wrapped in `&mut`-taking helpers so a
shared read never precedes a `&mut` call on the same local in one body
(advisory E001; the xiom.rate suite pattern).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | id shape | valid 32-lowercase-hex accepted (incl. all zeros); empty, 31/33 chars, uppercase and `g` rejected |
| t2 | store new/accessors | ttl 1500 kept; `0` and `-50` clamp to 1; count starts 0 |
| t3 | create | two creates yield valid, distinct ids; both resolve; count 2 |
| t4 | get round-trip | id/created/expires fields and empty entries; unknown valid-shaped id and non-id return None |
| t5 | expiry boundary | live at 999, None at 1000 (== expires) and 1001 for ttl 1000 created at 0 |
| t6 | set/value | insert, read back, overwrite in place, count stays 2 |
| t7 | set/value misses | missing key None; absent id None/false; expired set false and value None |
| t8 | set no extension | set at 50 leaves created 0 / expires 100; expired at 100 |
| t9 | touch | 50 -> 150; 100 -> 200; false at boundary 200 and for absent id |
| t10 | remove | true once, false on repeat and unknown; siblings survive |
| t11 | remove vs expiry | expired session still counted; `remove` ignores expiry; count drops |
| t12 | rotate | valid new id != old; old gone; count 1; times reset to (500, 1500); both entries copied |
| t13 | rotate errors | absent id and expired id both Err("session: not found or expired"); count unchanged |
| t14 | prune boundary | 0 at 99; removes only the ttl-100 session at 100; sibling live; 150 clears; 0 after |
| t15 | cookie header insecure | exact `sid=abc; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600` |
| t16 | cookie header secure | `; Secure` appended last |
| t17 | Max-Age clamp | 0 and -5 render `Max-Age=0`; 1000000 renders in decimal |
| t18 | cookie clear | exact `sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0` |
| t19 | 64-session store | all 64 ids valid/unique; every lookup resolves to its created time under the linear scan |
| t20 | 64-session prune | prune(300) removes 21, prune(700) removes 40, prune(1000) removes 3; boundary survivor i=21 looks up at 300; removed i=20 does not lookup |
| t21 | raw cookie text | empty id renders `sid=; ...` with no validation |
| t22 | composite | rotate/touch across two sessions: values carried, sibling untouched, expiry 1900, count 2 |
| t23 | empty store | prune 0; get/touch/remove on unknown id are safe no-ops |
| t24 | get copy independence | a snapshot taken before a later `session_set` still reports the old value |

Scripted expectation from the repository root:

```
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
& .\scripts\port.ps1 -Package xiom.session -TimeoutSec 60
# port: PASS (passed=24 failed=0 program_exit=0 exit=0)
```

Verified green twice with compiler v0.64.0 (2026-10-07).

## 7. Error catalog

Every message starts with the literal prefix `session: `. Messages are static
strings (no numbers are formatted into them).

| Message | Raised by | Trigger |
|---|---|---|
| `session: id generation failed` | `session_create`, `session_rotate` | 8 consecutive secure id draws all collided with stored ids |
| `session: not found or expired` | `session_rotate` | `old_id` absent or `now_ms >= expires_ms` |

`session_create` validates nothing else and stores nothing on Err.
`session_rotate` checks the old session first (Err `not found or expired`)
and the id source second (Err `id generation failed`); both Errs leave the
store unchanged.

## 8. Known limitations

- **In-memory, single-thread.** No locking; the caller serializes access.
- **Linear scans.** Every lookup is O(stored sessions); id collision checks
  and `session_set`'s entry copy add O(entries).
- **No live eviction.** Only expiry removes sessions; a store can grow until
  the caller prunes.
- **No cookie parsing or transport.** Rendering only; see `xiom.cookie` for
  parsing.
- **Opaque values.** No typing or serialization of entry values.
- **Security is caller-shaped.** Ids are unguessable while the CSPRNG works,
  but the store performs no signing, hashing or redaction; cookies are
  rendered exactly as configured.

## 9. Compiler / stdlib notes

The implementation follows the v0.64.0 package idioms:

- Free functions only; stores travel by reference (`&mut SessionStore` to
  mutate, `&SessionStore` to read) and state lives in the public fields.
- Every byte read via `xiom.string.byte_at` is widened with
  `(x as Int) & 0xFF` before comparison (`_byte`); hex and decimal rendering
  slice a constant digit table with `xiom.string.str_slice` and concatenate
  with `xiom.string.str_concat`.
- No `==` on Str anywhere: all string comparisons go through
  `xiom.string.compare.str_compare`; `Vec[Str]`/field reads bind typed locals
  first.
- **Vec[Struct] `.clone()` crashes the v0.64.0 codegen** (access violation
  reproduced with a minimal probe). The module therefore never clones
  sessions or entry vectors: `_entries_copy` copies entry fields element by
  element, `session_get` rebuilds a fresh `Session`, and `session_set` /
  `session_rotate` write whole sessions back (`s.sessions[at] = Session{ ... }`,
  `s.sessions.push(...)`).
- `Str` fields and locals are copied freely (copy semantics at the variable
  level); no `.clone()` calls remain in the module.
- Ids are generated through `xiom.crypto.secure_random_bytes`, the OS-entropy
  CSPRNG documented in the stdlib; the module documents the 8-draw collision
  bound and surfaces an Err rather than degrading silently.
- Result/Option values are constructed inline (`Ok`, `Err`, `Some`, `None`)
  and inspected with `.is_ok` / `.is_some` / `.value` / `.error`; no
  contracts (`ensures:`/`requires:`) are declared in 0.1.0 -- the 24-check
  suite pins the behavior instead.
- Imports: `xiom.crypto`, `xiom.string` and `xiom.string.compare` only; the
  tests additionally use `xiom.test` and `xiom.io`.
