# xiom.postgres roadmap

0.1.0 is the phase-1 surface: pure-XIOM wire protocol v3, three auth
methods, simple query, typed errors. Nothing below changes the frozen
0.1.0 surface; each item is gated on its stated need.

| Stage | Item | Gate |
| --- | --- | --- |
| surface | Extended query protocol: Parse/Bind/Describe/Execute with `$1` parameters and binary/text result formats; `pg_query_params(conn, sql, &Vec[Option[Str]])` | first consumer that needs server-side parameters (the documented workaround today is `pg_quote_literal` plus the injection caveat in SPEC section 8) |
| surface | COPY protocol (COPY IN/OUT) | data-loading consumer |
| surface | Async notification delivery: expose NotificationResponse through a listener/callback API (`LISTEN`/`NOTIFY`) | pub/sub consumer |
| security | TLS: SSLRequest negotiation is out of scope for 0.1.0 because the stdlib exposes no TLS client; revisit when `xiom.net.tls` gains a client usable from packages | stdlib TLS client availability (row tracks the stdlib lane, not this package) |
| correctness | SCRAM SASLprep (RFC 4013) for usernames/passwords; today ASCII credentials are unaffected and non-ASCII is passed verbatim (documented) | consumer with non-ASCII credentials |
| surface | SCRAM-SHA-256-PLUS channel binding | TLS support landing first |
| surface | Cancellation requests (`CancelRequest` with BackendKeyData) | long-running-query consumer |
| surface | Statement/portal cache and `exec_batch` over one round trip | consumer demand |
| tests | Live-PG parity leg wired into CI (dockerized PostgreSQL at a pinned version) | ops scheduling; the suite already runs the live leg opportunistically and SKIPs explicitly |
| hygiene | Re-check upstream `xiom.crypto.md5` once fixed and drop the local MD5 in favor of the stdlib (the local one stays meanwhile, pinned by RFC vectors) | stdlib fix landing; the local implementation is correct today either way |
