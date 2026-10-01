# xiom.nft -- specification

Module: `xiom.nft` (package `xiom.nft` 0.1.0). Pure XIOM; imports only
`xiom.string`, `xiom.string.compare` and `xiom.convert` from `xiom.std`. No
FFI, no cryptography, no networking, no randomness: every function is
deterministic in its arguments, and all clocks are explicit caller-supplied
integer ticks.

## 1. Model

`NftRegistry` stores:

- **Text store** -- one `Str` blob plus parallel `Vec[Int]` start and length
  rows. Every identity string (collection name, creator, owner, spender,
  operator, burner, event actor/counterparty) is stored once and referenced
  by a stable text-row id. Text rows are append-only and never reused.
- **Collections** -- name text id, creator text id, royalty basis points,
  recorded live count.
- **Tokens** -- token id, collection index, last-owner text id, minted tick,
  burn tick (`-1` while live), status (`NFT_TOKEN_LIVE` = 0,
  `NFT_TOKEN_BURNED` = 1).
- **Approvals** -- token row, grantor text id, spender text id, expiry tick.
- **Operators** -- owner text id, operator text id, expiry tick.
- **Events** -- sequence number, kind, token id, collection, actor text id,
  counterparty text id, tick.

All vectors are parallel append-only rows; `nft_registry_valid` checks that
each vector length equals its section count.

### 1.1 Constants

| Constant | Value | Meaning |
|---|---|---|
| `NFT_MAX_NAME_LEN` | 64 | max collection-name bytes |
| `NFT_MAX_IDENTITY_LEN` | 128 | max owner/creator/spender/operator/burner bytes |
| `NFT_MAX_BPS` | 10000 | royalty denominator and maximum |
| `NFT_INT64_MAX` | 9223372036854775807 | largest platform Int |
| `NFT_TOKEN_LIVE` | 0 | token status |
| `NFT_TOKEN_BURNED` | 1 | token status |
| `NFT_EVENT_MINT` | 1 | event kind |
| `NFT_EVENT_TRANSFER` | 2 | event kind |
| `NFT_EVENT_APPROVE` | 3 | event kind |
| `NFT_EVENT_BURN` | 4 | event kind |

### 1.2 Identity validation

An identity string is valid when it is non-empty, at most 128 bytes
(collection names: 64 bytes) and contains no control byte (`0x00..0x1F` or
`0x7F`). Validation errors have the exact form
`nft: empty <kind>`, `nft: <kind> too long (max N bytes)` or
`nft: <kind> contains control character at offset N` (0-based byte offset),
where `<kind>` is `collection name`, `creator`, `owner`, `sender`,
`recipient`, `spender`, `operator` or `burner`.

Ticks are non-negative Ints; `nft: negative tick` is returned when a tick
argument is below 0, and `nft: negative expiry` when an expiry is below 0.

### 1.3 Ownership rules

- Token ids are positive (`nft: token id must be positive`) and globally
  unique forever: burning does not free an id, and `nft: duplicate token id`
  is returned for any row (live or burned) that already holds it.
- Exactly one owner is recorded per token row. A transfer atomically
  replaces the owner; a burn retains the final owner as historical data.
- `nft_token_owner` returns the last owner for any existing token (live or
  burned) and `""` only for an unknown id. Use `nft_token_is_live` for
  liveness.
- A transfer to the current owner is rejected
  (`nft: transfer to current owner`).

### 1.4 Authorization

A live token row `row` may be acted on (transfer or burn) by `actor` at
`tick` when any of the following holds:

1. `actor` equals the current owner;
2. `actor` holds a valid per-token approval for `row` (section 2);
3. `actor` is a valid operator of the current owner (section 3).

Otherwise `nft: sender not authorized` (transfer) or
`nft: burner not authorized` (burn) is returned.

### 1.5 Events

Every mint, transfer and burn, and every per-token approval, appends
exactly one event. Operator grants and revocations do not append events;
they are recorded in the operator table. Event sequence numbers are strictly
`1..event_count` and never reused. `nft_event_kind_name` maps kinds to
`"mint"`, `"transfer"`, `"approve"`, `"burn"` and anything else to
`"unknown"`.

Event fields by kind:

| Kind | `token_id` | `collection` | actor | counterparty (`to`) | tick |
|---|---|---|---|---|---|
| mint | new token | its collection | owner | owner | mint tick |
| transfer | token | its collection | sender (`from`) | recipient | transfer tick |
| approve | token | its collection | grantor | spender | approval tick |
| burn | token | its collection | burner | final owner | burn tick |

## 2. Collections and tokens

### 2.1 `nft_collection_add(reg, name, creator, royalty_bps) -> Result[Int, Str]`

Registers a collection and returns its index (0-based). Checks, in order:

1. name validation (section 1.2, max 64 bytes);
2. creator validation (section 1.2, max 128 bytes);
3. `royalty_bps` in `0..=10000`, else
   `nft: royalty basis points out of range (0..10000)`;
4. name uniqueness, else `nft: duplicate collection name`.

### 2.2 Collection accessors

| Function | Returns for valid `i` | Out of range |
|---|---|---|
| `nft_collection_count` | number of collections | -- |
| `nft_collection_find(name)` | index or `-1` | -- |
| `nft_collection_name(i)` | name | `""` |
| `nft_collection_creator(i)` | creator | `""` |
| `nft_collection_royalty_bps(i)` | 0..10000 | `-1` |
| `nft_collection_live_count(i)` | recorded live supply | `-1` |
| `nft_collection_minted_count(i)` | all-time mints (live + burned) | `-1` |

### 2.3 `nft_mint(reg, collection, token_id, owner, tick) -> Result[Int, Str]`

Mints a token and returns its token row index. Checks, in order:

1. `collection` in range, else `nft: unknown collection`;
2. `token_id > 0`, else `nft: token id must be positive`;
3. owner validation (kind `owner`);
4. `tick >= 0`, else `nft: negative tick`;
5. id uniqueness, else `nft: duplicate token id`.

On success: appends the token row (status live, burn tick `-1`), increments
the collection live count and appends a MINT event.

### 2.4 Token accessors

`nft_token_count` (rows), `nft_live_supply`, `nft_burned_supply`,
`nft_token_row(id)` (`-1` unknown), `nft_token_exists(id)`,
`nft_token_is_live(id)`, `nft_token_owner(id)` (`""` unknown),
`nft_token_collection(id)` (`-1` unknown), `nft_token_minted_tick(id)`
(`-1` unknown), `nft_token_burn_tick(id)` (`-1` unknown or live).

## 3. Approvals

### 3.1 `nft_approve(reg, token_id, owner, spender, tick, expiry_tick) -> Result[Int, Str]`

Appends an approval row and returns its index. Checks, in order:

1. token exists, else `nft: unknown token`;
2. token is live, else `nft: token is burned`;
3. `tick >= 0`, else `nft: negative tick`;
4. spender validation (kind `spender`);
5. `owner` equals the current token owner, else `nft: not token owner`;
6. `expiry_tick >= 0`, else `nft: negative expiry`.

On success: appends the row (grantor text id, spender text id, expiry) and
an APPROVE event.

**Validity.** An approval is valid for `(token_id, spender)` at `tick` when
the *latest* row for that token row and spender string satisfies all of:

- the token is live;
- the row's grantor text equals the token's current owner (so a transfer
  implicitly invalidates approvals granted by the previous owner);
- `expiry_tick >= tick` (inclusive).

Only the latest row per (token, spender) is authoritative: re-approval
supersedes earlier rows, and reviving an approval requires a new row.
`nft_approval_valid_for(reg, token_id, spender, tick)` implements this.
`nft_approval_is_valid(reg, i, tick)` is the row-level form and is `false`
for any row that is not the latest for its (token row, spender string).

### 3.2 Approval accessors

`nft_approval_count`; `nft_approval_token_id(i)` (`-1`), `nft_approval_owner(i)`
(`""`), `nft_approval_spender(i)` (`""`), `nft_approval_expiry(i)` (`-1`),
`nft_token_approval_count(reg, token_id)` (all rows, `-1` unknown token).

## 4. Operators

### 4.1 `nft_set_operator(reg, owner, operator, expiry_tick) -> Result[Int, Str]`

Appends an operator row and returns its index. Checks, in order:

1. `expiry_tick >= 0`, else `nft: negative expiry`;
2. owner validation (kind `owner`);
3. operator validation (kind `operator`).

An owner may name itself operator (harmless: the owner is always
authorized). No event is appended.

### 4.2 `nft_operator_revoke(reg, owner, operator, tick) -> Result[Int, Str]`

Checks, in order: `tick >= 0` (`nft: negative tick`); owner validation;
operator validation; existence of a row for the pair, else
`nft: unknown operator`; the latest row must still be valid at `tick`, else
`nft: operator already revoked`. On success, appends a row with
`expiry_tick = tick - 1` (already expired) and returns its index.

**Validity.** An operator is valid for `(owner, operator)` at `tick` when
the *latest* row for the pair has `expiry_tick >= tick` (inclusive).
`nft_is_operator` implements this; `nft_operator_is_valid(reg, i, tick)` is
the row-level form and is `false` for superseded rows.

### 4.3 Operator accessors

`nft_operator_count`; `nft_operator_owner(i)` (`""`), `nft_operator_operator(i)`
(`""`), `nft_operator_expiry(i)` (`-1`).

## 5. Transfers and burns

### 5.1 `nft_transfer(reg, token_id, from, to, tick) -> Result[Int, Str]`

Returns the TRANSFER event sequence number. Checks, in order:

1. token exists, else `nft: unknown token`;
2. token is live, else `nft: token is burned`;
3. `tick >= 0`, else `nft: negative tick`;
4. sender validation (kind `sender`);
5. recipient validation (kind `recipient`);
6. `from` is authorized (section 1.4), else `nft: sender not authorized`;
7. `to` differs from the current owner, else
   `nft: transfer to current owner`.

On success the owner is replaced and one TRANSFER event is appended.

### 5.2 `nft_burn(reg, token_id, burner, tick) -> Result[Int, Str]`

Returns the BURN event sequence number. Checks, in order:

1. token exists, else `nft: unknown token`;
2. token is live, else `nft: token is burned`;
3. `tick >= 0`, else `nft: negative tick`;
4. burner validation (kind `burner`);
5. `burner` is authorized (section 1.4), else
   `nft: burner not authorized`.

On success the status becomes burned, the burn tick is recorded, the
collection live count decreases, and one BURN event is appended. The token
row, id, last owner, minted tick and burn tick are retained; the id is never
reused. Approvals on a burned token are unusable because validity requires a
live token.

## 6. Royalties

`nft_royalty_creator_amount(reg, collection, sale_price)` returns
`floor(sale_price * bps / 10000)` where `bps` is the collection royalty,
computed as `q * bps + (r * bps) / 10000` with `q = sale_price / 10000` and
`r = sale_price % 10000`. This is exact for non-negative inputs and cannot
overflow: the result is at most `sale_price`. Returns 0 when the collection
is unknown or `sale_price <= 0`.

`nft_royalty_seller_amount` returns `sale_price - creator_amount` (0 for the
same invalid inputs), so `creator + seller == sale_price` exactly for every
valid input, including `sale_price = NFT_INT64_MAX`.

`nft_royalty_split_text(reg, collection, sale_price)` returns
`"creator\t<creator>\tseller\t<seller>"`, or `""` for invalid inputs.

## 7. Enumeration

- `nft_owner_token_count(reg, owner)` -- live tokens owned by `owner`.
- `nft_owner_token_at(reg, owner, k)` -- token id of the k-th (0-based) live
  token owned by `owner`, in token-row order; `-1` when out of range.
- `nft_collection_token_at(reg, collection, k)` -- token id of the k-th live
  token in `collection`, in token-row order; `-1` when out of range.
- `nft_collection_live_count` / `nft_collection_minted_count` as in 2.2.

Burned tokens are excluded from all live enumerations.

## 8. Invariants

- `nft_token_ids_unique(reg)` -- every token id is positive and no two rows
  share an id (the unique-ownership key), after checking parallel-vector
  consistency.
- `nft_supply_balanced(reg)` -- every token status is live or burned; the
  recorded live count of each collection equals the actual number of live
  tokens in it; the per-collection live counts sum to the global live
  supply; every parallel vector has its section's length.
- `nft_registry_valid(reg)` -- `nft_token_ids_unique` and
  `nft_supply_balanced` plus reference validity: token collection indexes in
  range; text-row ids valid; live tokens have burn tick `-1` and burned
  tokens a non-negative burn tick; collection royalty bps in `0..=10000`;
  approval and operator rows reference valid token rows and text rows with
  expiry `>= -1`; the event log has sequence `1..event_count`, kinds in
  `1..=4`, and every event references a real token row, a valid collection
  and valid text rows.

## 9. Canonical export

`nft_registry_export(reg)` returns a tab-separated listing; every line ends
with `\n`:

```
nft-registry\t1
collections\t<n>
collection\t<i>\t<name>\t<creator>\t<bps>\t<live>\t<minted>
tokens\t<n>
token\t<id>\t<collection>\t<owner>\t<live|burned>\t<minted_tick>\t<burn_tick>
approvals\t<a>
approval\t<token_id>\t<owner>\t<spender>\t<expiry>
operators\t<o>
operator\t<owner>\t<operator>\t<expiry>
events\t<e>
event\t<seq>\t<mint|transfer|approve|burn>\t<token_id>\t<collection>\t<actor>\t<to>\t<tick>
```

`"nft-registry\t1"` is the format version. The `owner` field of a burned
token is its final owner; its `burn_tick` is the recorded burn tick.

## 10. Error catalogue

All errors are `Err(Str)` with the exact `nft: ...` messages listed in the
sections above:

| Message | Returned by |
|---|---|
| `nft: empty <kind>` / `nft: <kind> too long (max N bytes)` / `nft: <kind> contains control character at offset N` | validation (1.2) |
| `nft: negative tick` | mint, transfer, burn, approve, operator revoke |
| `nft: negative expiry` | approve, set operator |
| `nft: unknown collection` | mint |
| `nft: token id must be positive` / `nft: duplicate token id` | mint |
| `nft: unknown token` / `nft: token is burned` | transfer, burn, approve |
| `nft: sender not authorized` / `nft: transfer to current owner` | transfer |
| `nft: burner not authorized` | burn |
| `nft: not token owner` | approve |
| `nft: unknown operator` / `nft: operator already revoked` | operator revoke |
| `nft: royalty basis points out of range (0..10000)` / `nft: duplicate collection name` | collection add |
