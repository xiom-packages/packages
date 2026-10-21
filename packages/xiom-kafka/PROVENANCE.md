# PROVENANCE: xiom.kafka

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | librdkafka -- https://github.com/confluentinc/librdkafka (formerly edenhill/librdkafka) |
| Upstream license | **BSD-2-Clause** (`LICENSE`, SHA256 `1AD5DF319467E7616C502D1CEE59423110024C3B27474A54AFF771B03DCA473E`) |
| Policy | BSD-2 is allowed by `docs/BINDINGS-LANE.md` §4. Nothing is vendored: the package ships no librdkafka source or binary. The bridge is original XIOM-side code that resolves a user-supplied shared library at runtime. |
| Reference clone | `E:\repos\librdkafka` -- pinned tag **v2.16.0**, commit `c6c9973cf1b25394c58e0cade13a36f386856f77` (`git describe --tags --exact-match` = `v2.16.0`) |
| Package license | MIT OR Apache-2.0 (no upstream code copied into this package) |

The shipped surface is **independent XIOM/C code** written against the
public C declarations in the pinned clone (the "declaration oracle" below)
and verified against a real shared build at runtime. The bridge never links
librdkafka; it resolves the release generation with `LoadLibraryA` /
`dlopen` and the suite SKIPs green when no build is present.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `src/rdkafka.h` | `4EB8EDE3471C9AD89A862CCDD1BDD21715C5A42EF0E8D285AADBDA7F4DE890C1` |
| `src/rdkafka_mock.h` | `7CC989C2D500F06E0BE7AE1B3741D84EA03D898FC9A53CD499ABA69EA205F029` |
| `src/rdkafka_admin.h` | `9E110CD4FEC0FD865488AF266D281AC1CC716F0C7F3190D32B5646EF5C11655A` |
| `src/rdkafka_mock_handlers.c` | handler table at lines 5167-5202 (admin-support evidence) |
| `src/rdkafka_queue.c` | queue (`rd_kafka_queue_new` / `_poll`) behavior for admin results |
| `src/rdkafka.c` | `rd_kafka_new` mock-cluster auto-creation (`test.mock.num.brokers`) and event serving |
| `src/rdkafka_admin.c` | admin request/result lifecycle and reply-queue routing |
| `CHANGELOG.md` | `E7E6297B80311FF03287E656C649D5AB7240E30522EF899453CA9C1F99F9CAB0` |
| `LICENSE` | `1AD5DF319467E7616C502D1CEE59423110024C3B27474A54AFF771B03DCA473E` |

Bound signatures come from `rdkafka.h`: version/error helpers; `conf_*`;
`rd_kafka_new`/`destroy`/`name`/`poll`/`flush`/`outq_len`/`clusterid`;
topic + produce; consumer poll/commit/close; topic-partition lists;
metadata structs; transactions (`rd_kafka_error_t`); admin
CreateTopics/DeleteTopics and their result events; and the
`rd_kafka_message_t` head + `rd_kafka_message_timestamp()` accessor. The
mock-control signatures come from `rdkafka_mock.h`.

**ABI notes (v2.16.0).** `rd_kafka_message_t` no longer stores
`timestamp`/`timestamp_type` (they moved behind
`rd_kafka_message_timestamp()`); the bridge encodes only the stable head
(err/rkt/partition/payload/len/key/key_len/offset/_private) and uses the
accessor for timestamps. The metadata struct field order was read directly
from `rdkafka.h:6143-6185`. The mock handler table was checked to establish
that `CreateTopics`/`DeleteTopics` are **not** served by the mock (see
`SPEC.md` §5); the admin success path was verified against a real local
Apache Kafka 3.9.1 broker instead.

## Derived vs independent

- `src/kafka_bridge.c` (the only C file; compiled with `--c-source`):
  **original XIOM-side code**, MIT OR Apache-2.0. It knows only public
  interface facts: the message-head offsets, the metadata struct field
  order, the pinned `rd_kafka_vtype`-era flags (`RD_KAFKA_MSG_F_COPY = 0x2`),
  offsets (`BEGINNING = -2`, `INVALID = -1001`), admin op/event numbers
  (`CREATETOPICS = 1/100`, `DELETETOPICS = 2/101`) and the retriable local
  error set. No upstream code, tables or generated files are copied.
- `kafka.xi` + `src/*.xi`: **independent XIOM code** -- loader
  classification, typed wrappers, copy-out/decode, config surface.
- No upstream test vectors are imported. The live suite uses the upstream
  mock cluster and the package's own assertions.

## Local runtime sample used for proof (NOT the pin; nothing committed)

Official Confluent `librdkafka.redist` **2.16.0** NuGet package
(43,345,224 B, SHA256
`F5B41D820D6A7E886BCB4C574020A1DCD54D72A965BAD681F15C1C788A80AF5B`),
win-x64 native set extracted under `E:\repos\librdkafka-bin\win-x64`:

| Artifact | Size | SHA256 |
|----------|------|--------|
| `librdkafka.dll` | 2,852,864 B | `8DB0996180665F2A52394F27DDC00DE6F08F64F9809E8B437FD209991A317953` |
| `libcrypto-3-x64.dll` | 5,303,296 B | `97F488DB248269E1D2AD426EEBD4F093333055BB30165D3C844A9EE06295FE05` |
| `libssl-3-x64.dll` | 865,792 B | `E739348CBA96819AC0E0B85F8FE160B0BCE6F0EB139A106E6F9CAAF63867DC28` |
| `libcurl.dll` | 709,120 B | `D843CF862C360AB1DEC4D236B5850208E8556BE64AACBE79260A4D1BAEC80FEA` |
| `zstd.dll` | 661,504 B | `C04BE707F8D1A1D264F62291F397957D145D6522D9A3BE4E160B58E4B437B181` |
| `z.dll` | 89,600 B | `933108900484900EEB6267C8C3D13DE74DAC2F44C2E9EB96B24DE5F1CE371BE2` |
| `librdkafkacpp.dll` | 92,160 B | `FDCB9FBAC3E72F12A519865554064D7B0A3BD0A789D98A703C4008A82621DF4E` |
| `msvcp140.dll` | 575,056 B | `7B8A6F283884E6448559DCF510B00C1A885BFB8E598EA05CD2C290C874657326` |
| `vcruntime140.dll` | 119,888 B | `642AE52687A7A6BFB03D0B20DC7E07F4B11CECA634F7EB7BA184D6711AB51A51` |

The live suite run recorded `librdkafka 2.16.0` (`rd_kafka_version_str`).
A supplementary real-broker run used `apache/kafka:3.9.1` (KRaft,
`127.0.0.1:9092`) and verified CreateTopics success, produce/consume,
DeleteTopics success and the topic-list before/after (`tests/test_real_broker.xi`,
10/10; not part of the default suite).

## Re-carve procedure (upstream moves)

1. Re-clone/refresh `E:\repos\librdkafka` at the new tag; update the pin,
   header hashes and sample hashes here and in `SPEC.md`.
2. Re-verify the message head / metadata layouts / admin and mock signatures
   at the new commit; re-check the mock handler table before claiming admin
   mock behavior.
3. Rebuild the redist sample (or use the matching official prebuilt) on
   `PATH`; run `scripts/port.ps1 -Package xiom.kafka -TimeoutSec 300` twice
   with and twice without the library; run the optional real-broker sample
   once; update `SPEC.md` / `AUDIT.md`; conventional commit.
