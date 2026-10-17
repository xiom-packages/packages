<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Relay archive (pre-bus, historical)

These are the lane's hand-delivered relay messages from the bootstrap era
(2026-10-08..10). **Live cross-lane coordination now runs on the private
`xiom-relays` bus** (`E:\xiom-lang\xiom-relays`; one item per issue,
`python tools/relay.py view --lane orbitdb`). Do not add files here; open a
bus item instead.

The content below is kept for provenance (pins at the time of writing were
compiler v0.64.0..v0.64.2; several statuses have moved since). Where a
message and a keeper doc disagree, trust the keeper doc, the bus item, or
`SESSION.md`.

| File | What it was | Live successor |
|---|---|---|
| `COMPILER-RELAY-2026-10-09-v0.64.2.md` | Incoming: compiler lane's v0.64.2 release state | `docs/COMPILER-FINDINGS-ORBITDB.md` (C-ORBIT-01..05 resolved) + bus items to `compiler` |
| `RELAY-COMPILER-ORBITDB.md` | Outbound: first compiler findings + repro pointers | same as above; open item: bus `REL-20261010-1550-orbitdb-2` |
| `RELAY-INTRO-ORBITDB.md` | Outbound: ecosystem intro one-pager | `README.md` / `SESSION.md`; bus ack `REL-20261010-1550-orbitdb` |
| `RELAY-STDLIB-ORBITDB.md` | Outbound: stdlib wishlist cover letter | `docs/STDLIB-WISHLIST-ORBITDB.md` + bus items `REL-20261010-1550-orbitdb-3..-8` |
| `RELAY-PACKAGES-ORBITDB.md` | Outbound: packages wishlist cover letter | `docs/PACKAGE-WISHLIST-ORBITDB.md` + bus items `-9..-10` |
| `RELAY-PACKAGES-RESPONSE-ORBITDB.md` | Outbound: response on xiom.wal/xiom.btree/xiom.durable | `docs/PACKAGE-WISHLIST-ORBITDB.md` deltas (xiom.wal consumer pass, order-3 fix) |
| `RELAY-XVECTOR-ORBITDB.md` | Outbound: hybrid integration handshake | `docs/XVECTOR-INTEGRATION.md` (sections 1-7) + bus `REL-20261010-1550-orbitdb-11` |
