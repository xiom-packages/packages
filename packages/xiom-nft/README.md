# xiom.nft

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** one dependency-free module implementing a deterministic NFT
> registry model in pure XIOM: collections, mint/burn, approved transfers,
> royalty splits and a canonical event log.
> **Deps:** none beyond `xiom.std` (the library imports only `xiom.string`,
> `xiom.string.compare` and `xiom.convert`; the tests add `xiom.test`,
> `xiom.io` and `xiom.string.str_repeat`).

## What it is

`xiom.nft` models the bookkeeping an NFT indexer or marketplace needs,
without any cryptography or networking:

- **Collections** with unique names, creators and royalty basis points
  (0..10000), plus live and all-time-minted supply counters.
- **Tokens** identified by positive, globally unique ids that are never
  reused, even after burn: collection, last owner, minted tick and burn tick.
- **Ownership and transfers**: exactly one owner per live token; a transfer
  must come from the current owner, a spender holding an unexpired per-token
  approval, or an unexpired operator. Transfers to the current owner are
  rejected; a transfer implicitly invalidates approvals granted by the old
  owner (validity always requires the grantor to still be the owner).
- **Approvals and operators** with inclusive expiry ticks; only the latest
  row per (token, spender) or (owner, operator) pair is authoritative.
- **Royalty splits** computed as `floor(price * bps / 10000)` with an
  overflow-free q/r decomposition; the seller receives the remainder, so the
  two shares always sum exactly to the sale price.
- **Canonical events** (mint, transfer, approve, burn) with sequence numbers
  `1..N`; every token mutation and every approval appends exactly one event.
- **Invariant checks** (`nft_registry_valid`, `nft_token_ids_unique`,
  `nft_supply_balanced`) covering unique ownership, supply accounting and
  canonical event sequences.
- **Canonical text export** of the whole registry for golden tests.

Ids, owners, creators and spenders are opaque caller-supplied strings;
nothing here performs real cryptography, and ticks are explicit caller
integers, so every run is deterministic.

## API

| Function | Returns | Description |
|---|---|---|
| `nft_registry_new()` | `NftRegistry` | Empty registry. |
| `nft_collection_add(reg, name, creator, bps)` | `Result[Int, Str]` | Register a collection, returns its index. |
| `nft_collection_find(reg, name)` | `Int` | Collection index by name, -1 when absent. |
| `nft_collection_name/creator/royalty_bps/live_count/minted_count(reg, i)` | `Str`/`Str`/`Int`/`Int`/`Int` | Collection accessors (-1 / "" out of range). |
| `nft_mint(reg, collection, token_id, owner, tick)` | `Result[Int, Str]` | Mint a token, returns its row index. |
| `nft_transfer(reg, token_id, from, to, tick)` | `Result[Int, Str]` | Authorized transfer, returns event seq. |
| `nft_burn(reg, token_id, burner, tick)` | `Result[Int, Str]` | Authorized burn, returns event seq. |
| `nft_approve(reg, token_id, owner, spender, tick, expiry_tick)` | `Result[Int, Str]` | Per-token approval, returns its row index. |
| `nft_approval_valid_for(reg, token_id, spender, tick)` | `Bool` | Current-owner approval check. |
| `nft_approval_count/is_valid/token_id/owner/spender/expiry(...)` | mixed | Approval row accessors. |
| `nft_token_approval_count(reg, token_id)` | `Int` | Approval rows for a token. |
| `nft_set_operator(reg, owner, operator, expiry_tick)` | `Result[Int, Str]` | Operator grant, returns its row index. |
| `nft_operator_revoke(reg, owner, operator, tick)` | `Result[Int, Str]` | Revoke by appending an expired row. |
| `nft_is_operator(reg, owner, operator, tick)` | `Bool` | Latest-row operator check. |
| `nft_operator_count/owner/operator/expiry/is_valid(...)` | mixed | Operator row accessors. |
| `nft_token_row/exists/is_live/owner/collection/minted_tick/burn_tick(...)` | mixed | Token accessors ("" / -1 when unknown). |
| `nft_token_count/live_supply/burned_supply(reg)` | `Int` | Supply counters. |
| `nft_owner_token_count(reg, owner)` / `nft_owner_token_at(reg, owner, k)` | `Int` | Owner enumeration. |
| `nft_collection_token_at(reg, collection, k)` | `Int` | Collection enumeration (live only). |
| `nft_royalty_creator_amount/seller_amount(reg, collection, price)` | `Int` | Overflow-free bps split. |
| `nft_royalty_split_text(reg, collection, price)` | `Str` | `"creator\t<X>\tseller\t<Y>"`. |
| `nft_event_count/seq/kind/kind_name/token_id/collection/actor/to/tick(...)` | mixed | Event log accessors. |
| `nft_token_ids_unique/supply_balanced/registry_valid(reg)` | `Bool` | Invariants. |
| `nft_registry_export(reg)` | `Str` | Canonical tab-separated listing. |

```xi
use xiom.nft;

var reg = nft_registry_new();
let c = nft_collection_add(&mut reg, "dao", "deployer", 500);   // 500 bps = 5%
let m = nft_mint(&mut reg, 0, 7, "alice", 10);
let a = nft_approve(&mut reg, 7, "alice", "bob", 11, 100);
let t = nft_transfer(&mut reg, 7, "bob", "carol", 50);          // bob holds the approval
let split = nft_royalty_split_text(&reg, 0, 10000);             // "creator\t500\tseller\t9500"
```

## Tests

```
.\scripts\port.ps1 -Package xiom.nft -TimeoutSec 60
```

Expected: 20 `[PASS]` lines, `xiom.nft: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
