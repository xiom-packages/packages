# ROADMAP: xiom.redis

Current state: v0.1.0 (incubating), pure-XIOM RESP2 client, 19/19 checks
recorded x2 green on XIOM v0.64.5. See `SPEC.md` (declared surface and
non-goals), `AUDIT.md` (verification record and deviations) and
`PROVENANCE.md` (independent declaration).

Nothing below is implemented; each item is a candidate for a future
version and requires its own conformance slice before shipping.

## Near term (0.1.x)

1. **Live-server record.** Run the suite against a real Redis (a pinned
   server release in CI or a developer box) so checks n18/n19 execute
   their live paths and the record shows them green instead of SKIP.
2. **Live parity fixtures.** If a live-server record is established,
   capture a small set of server-produced reply bytes (e.g. an INFO
   bulk, a nested `COMMAND` array) as regression fixtures, with the
   capture procedure recorded in `PROVENANCE.md`.
3. **More typed verbs**, staying inside RESP2 reply shapes: `append`,
   `getset`, `setnx`, `sadd`/`srem`/`smembers`, `zadd`/`zrange`,
   `hset`/`hget`/`hgetall`/`hdel`, `lpush`/`rpop`/`lrange`,
   `persist`/`pttl`, `type`, `dbsize`. Each is a thin wrapper over the
   existing checked-command path.
4. **Pipeline helpers** for mixed checked/unchecked reads (e.g. a
   `pipeline_checked` that maps every `Error` element to a typed error
   position).

## Medium term (0.2+)

5. **RESP3** (`HELLO 3`): decode map (`%`), set (`~`), double (`,`),
   big number (`(`), verbatim string (`=`) and the push (`>`) type;
   keep RESP2 as the default dialect. Requires a codec extension plus
   new cap checks and goldens.
6. **TLS** via `xiom.net.tls` once the stdlib TLS client surface is
   stable for package consumers; planned as a transport-option on
   connect, not a fork of the client.
7. **Auth / SELECT helpers** (`AUTH`, `AUTH user pass`, `SELECT`,
   `HELLO AUTH`) as typed wrappers -- protocol-trivial, needs live
   verification against ACL-enabled servers.
8. **Blocking commands** (`BLPOP`/`BRPOP`) on the existing poll-deadline
   read path, with the timeout surfaced as `REDIS_ERR_TIMEOUT` vs the
   server's null reply distinguished.

## Long term (exploratory)

9. **Cluster / Sentinel redirects**: MOVED/ASK handling with explicit
   topology state; requires multi-connection management, currently out
   of scope by design (one `RedisConn` per task).
10. **Transactions**: `MULTI`/`EXEC`/`DISCARD` helpers layered on
    pipelines with explicit state tracking.
11. **Streams** (`XADD`/`XRANGE`/`XREAD`) with typed entry shapes.
12. **Pooling / reconnect**: an opt-in session pool with health checks;
    must stay free of library-internal clock state.
