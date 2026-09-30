# xiom.wallet -- Specification

Status: `incubating` (implemented, conformance-tested; not yet published).
Manifest: `package.xi` (`xiom.wallet`, version `0.1.0`).
Module: `src/wallet.xi` (`module xiom.wallet`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`,
`xiom.convert`). No FFI, no external packages, no cryptography, no hashing,
no networking.

This document specifies the behavior actually implemented: the derivation
path grammar, the book rules, the ledger rules and the complete error
catalog. All errors are `Err(Str)` with the prefix `wallet: `.

## 1. Conventions

- The platform `Int` is signed 64-bit (`9223372036854775807` is the
  largest value; `WALLET_INT64_MAX`).
- Every `Str` payload of a `Result` or every `Vec` element is copied to a
  typed local before use; equality between `Str` values uses
  `xiom.string.compare.str_compare` (never `==`).
- Collection types are structs with parallel `Vec` fields (no `Vec` of
  struct types); out-of-range accessors return a documented default
  (`-1` for indices/statuses, `0` for amounts, `""` for strings).
- All exports are byte-deterministic: records in insertion order,
  tab-separated fields, `\n` after every line.

## 2. Structural validation

Two validators are used everywhere. They never interpret the payload.

### 2.1 Text (labels, account keys, references, intent ids, wallet names)

Non-empty; at most `maxlen` bytes; every byte must be a non-control byte
(`0x20..0x7E` or `>= 0x80`; `0x00..0x1F` and `0x7F` are rejected). This
permits spaces and UTF-8 in labels while forbidding newlines/tabs that
would break the line-oriented export format.

Errors (in this order):

| Condition | Error |
|---|---|
| empty | `wallet: empty <kind>` |
| longer than `maxlen` bytes | `wallet: <kind> too long (max <maxlen> bytes)` |
| control byte at offset `N` | `wallet: <kind> contains control character at offset N` |

Kinds and caps: `label` / `wallet name` -- 64 bytes
(`WALLET_MAX_LABEL_LEN`); `account key` / `reference` / `intent id` -- 128
bytes (`WALLET_MAX_KEY_LEN`, `WALLET_MAX_REF_LEN`).

### 2.2 Visible token (addresses, intent destinations)

Non-empty; at most 128 bytes (`WALLET_MAX_ADDRESS_LEN`); every byte must be
visible ASCII `0x21..0x7E` (no controls, no spaces, no non-ASCII).

| Condition | Error |
|---|---|
| empty | `wallet: empty <kind>` |
| too long | `wallet: <kind> too long (max 128 bytes)` |
| byte outside `0x21..0x7E` at offset `N` | `wallet: <kind> contains invalid character at offset N` |

## 3. Derivation paths

### 3.1 Grammar

```
path      := "m" | "m" ( "/" component )+
component := digits | digits marker
digits    := "0" | nonzero-digit digit*
marker    := "'" | "h" | "H"
```

- Exactly one leading `m` (lowercase). Any other prefix is rejected.
- `digits` has no leading zeros: `0` is valid, `00`/`01` are not.
- Values are in `0..2147483647` (`WALLET_MAX_COMPONENT`, 2^31-1).
- At most 255 components after `m` (`WALLET_MAX_PATH_DEPTH`).
- `"''"`, `"h"` and `"H"` all mean *hardened*. The marker is **not**
  folded into bit 31: the value is stored raw plus a parallel hardened
  flag. The canonical format re-emits `'` only.

`DerivationPath = { depth: Int; components: Vec[Int]; hardened: Vec[Int] }`
where `hardened[i]` is 0 or 1 and `depth == components.len()` for every
parsed value.

### 3.2 Functions

| Function | Behavior |
|---|---|
| `derivation_path_new()` | Empty path `m`, depth 0. |
| `derivation_path_parse(s)` | Parse per 3.1; `Result[DerivationPath, Str]`. |
| `derivation_path_validate(s)` | `parse(s).is_ok`. |
| `derivation_path_format(p)` | Canonical text: `m`, then `/<v>` or `/<v>'`. Round-trips through `parse`. |
| `derivation_path_depth(p)` | `p.depth`. |
| `derivation_path_component(p, i)` | Raw value; `-1` out of range. |
| `derivation_path_is_hardened(p, i)` | Flag; `false` out of range. |
| `derivation_path_hardened_count(p)` | Count of set flags. |
| `derivation_path_equal(a, b)` | Same depth, values and flags. |

### 3.3 Parse error catalog (offsets are 0-based byte offsets)

| Input (example) | Error |
|---|---|
| `""` | `wallet: empty derivation path` |
| `M/0`, `x/0` | `wallet: derivation path must start with m` |
| `m/` (nothing after `/`) | `wallet: empty path component at offset N` |
| `m//0` | `wallet: invalid path character at offset 2` |
| `m/00` | `wallet: leading zero in path component at offset 2` |
| `m/0''` | `wallet: invalid path character at offset 4` |
| `m/abc`, `m/0x`, `m/12a` | `wallet: invalid path character at offset N` |
| `m/2147483648`, `m/99999999999999999999` | `wallet: path component out of range at offset 2` |
| `m/0/` + 255 more components | `wallet: derivation path depth exceeds 255` |

Precedence inside a component: separators and first characters are checked
as the scan proceeds; the numeric bound is checked while accumulating the
digits (overflow-safe: `value > (WALLET_MAX_COMPONENT - d) / 10`), so a
20-digit component is reported as out of range, never wrapped.

## 4. Account book

`AccountBook = { count: Int; labels: Vec[Str]; keys: Vec[Str] }` --
parallel vectors, one entry per account. Keys are opaque (never parsed).

| Function | Behavior |
|---|---|
| `account_book_new()` / `account_book_count(b)` | Empty book / size. |
| `account_book_add(b, label, key)` | Validate `label` (text, 64) then `key` (text, 128); reject a duplicate label (`wallet: duplicate account label`); append both; return the new index. |
| `account_book_find(b, label)` | Index or `-1`. |
| `account_book_label(b, i)` / `account_book_key(b, i)` | `""` out of range. |
| `account_book_set_key(b, i, key)` | `wallet: account index out of range` or the key validation errors; rebuilds the key vector. |
| `account_book_export(b)` | See 7.1. |

## 5. Address book

`AddressBook = { count: Int; labels: Vec[Str]; addresses: Vec[Str] }`.

| Function | Behavior |
|---|---|
| `address_book_new()` / `address_book_count(b)` | Empty book / size. |
| `address_book_add(b, label, address)` | Validate `label` (text, 64) then `address` (visible token, 128); reject a duplicate label (`wallet: duplicate address label`) or a duplicate address (`wallet: duplicate address`); append both; return the new index. |
| `address_book_find_label(b, label)` / `address_book_find_address(b, address)` | Index or `-1`. |
| `address_book_label(b, i)` / `address_book_address(b, i)` | `""` out of range. |
| `address_book_export(b)` | See 7.2. |

## 6. Ledger

### 6.1 State and invariants

```
Ledger = {
  balance: Int; reserved: Int; seq: Int;
  posting_count: Int; posting_seq: Vec[Int]; posting_kind: Vec[Int];
  posting_delta: Vec[Int]; posting_amount: Vec[Int]; posting_fee: Vec[Int];
  posting_ref: Vec[Str]; posting_to: Vec[Str];
  intent_count: Int; intent_id: Vec[Str]; intent_amount: Vec[Int];
  intent_fee: Vec[Int]; intent_to: Vec[Str]; intent_status: Vec[Int];
}
```

- `balance >= 0`; `0 <= reserved <= balance`;
  `available = balance - reserved`.
- `seq` is the sequence number of the last **posting**. Every settled
  balance change appends exactly one posting with `seq + 1`; the first
  posting has sequence 1. Intent creation and cancellation add no posting.
- Postings are append-only; parallel vectors are pushed together and never
  drift (accessors and exports guard mismatched lengths).
- Intent statuses: `INTENT_PENDING` (0), `INTENT_EXECUTED` (1),
  `INTENT_CANCELLED` (2). `INTENT_EXECUTED`/`INTENT_CANCELLED` are
  terminal: they cannot be executed or cancelled again, and their reserved
  funds have been settled or released.
- An intent reserves `amount + fee` at creation. Executing subtracts the
  reserved total from both `balance` and `reserved`; cancelling subtracts
  it from `reserved` only.

### 6.2 Credits

`ledger_credit(l, amount, reference)` -> new balance. Appends
`POSTING_CREDIT` with `delta = +amount`, `fee = 0`, `to = ""`.

Errors, in order:

1. `amount <= 0` -> `wallet: amount must be positive`
2. reference validation (2.1) -> `wallet: empty reference` /
   `wallet: reference too long (max 128 bytes)` /
   `wallet: reference contains control character at offset N`
3. `amount > WALLET_INT64_MAX - balance` -> `wallet: balance overflow`
   (the rejected call changes nothing)

### 6.3 Transfer intents

`ledger_intent_create(l, id, amount, fee, dst)` -> intent index.
Errors, in order:

1. intent id validation (2.1) -> `wallet: empty intent id` /
   `wallet: intent id too long (max 128 bytes)` /
   `wallet: intent id contains control character at offset N`
2. `amount <= 0` -> `wallet: amount must be positive`
3. `fee < 0` -> `wallet: negative fee`
4. `amount > WALLET_INT64_MAX - fee` -> `wallet: amount plus fee overflows`
5. destination validation (2.2) -> `wallet: empty intent destination` /
   `wallet: intent destination too long (max 128 bytes)` /
   `wallet: intent destination contains invalid character at offset N`
6. id already exists with **any** status -> `wallet: duplicate intent`
   (double-spend rejection; intent ids are unique forever)
7. `amount + fee > available` -> `wallet: insufficient funds`

On success the total is reserved and the intent is appended as
`INTENT_PENDING`.

`ledger_intent_execute(l, id)` -> new balance.

1. unknown id -> `wallet: unknown intent`
2. status not pending -> `wallet: intent already settled`
   (executing twice is the double-spend rejection)
3. defensive `amount + fee > balance` -> `wallet: insufficient funds`
4. on success: `balance -= total`, `reserved -= total`, `seq += 1`,
   status becomes `INTENT_EXECUTED`, and one `POSTING_TRANSFER` posting is
   appended with `delta = -(amount + fee)`, the intent id as reference and
   the destination.

`ledger_intent_cancel(l, id)` -> intent index.

1. unknown id -> `wallet: unknown intent`
2. status not pending -> `wallet: intent already settled`
3. on success: `reserved -= amount + fee`, no posting, status becomes
   `INTENT_CANCELLED`.

### 6.4 Accessors

| Function | Out-of-range default |
|---|---|
| `ledger_balance` / `ledger_reserved` / `ledger_available` / `ledger_sequence` / `ledger_posting_count` / `ledger_intent_count` | -- |
| `ledger_posting_seq` / `ledger_posting_kind` | -1 |
| `ledger_posting_delta` / `ledger_posting_amount` / `ledger_posting_fee` | 0 |
| `ledger_posting_ref` / `ledger_posting_to` | `""` |
| `ledger_intent_index(l, id)` | -1 (unknown) |
| `ledger_intent_status` | -1 |
| `ledger_intent_amount` / `ledger_intent_fee` | 0 |
| `ledger_intent_id` / `ledger_intent_to` | `""` |
| `ledger_intent_pending_count` | -- (count) |

## 7. Canonical export format

Every line ends with `\n`. Fields are separated by one tab. No field can
contain a tab or newline (enforced by 2.1/2.2).

### 7.1 `account_book_export(b)`

```
accounts\t<count>\n
account\t<i>\t<label>\t<key>\n            (for i = 0..count-1)
```

### 7.2 `address_book_export(b)`

```
addresses\t<count>\n
address\t<i>\t<label>\t<address>\n        (for i = 0..count-1)
```

### 7.3 `ledger_export(l)`

```
ledger\t<balance>\t<reserved>\t<seq>\t<pending>\n
postings\t<posting_count>\n
posting\t<seq>\t<credit|transfer>\t<delta>\t<amount>\t<fee>\t<ref>\t<to>\n
intents\t<intent_count>\n
intent\t<id>\t<pending|executed|cancelled>\t<amount>\t<fee>\t<to>\n
```

`pending` is `ledger_intent_pending_count(l)`.

### 7.4 `wallet_export(w)`

`Wallet = { name: Str; accounts: AccountBook; addresses: AddressBook;
ledger: Ledger }`.

```
wallet\t1\t<name>\n
<account_book_export(w.accounts)>
<address_book_export(w.addresses)>
<ledger_export(w.ledger)>
```

The `1` is the listing format version. `w.name` must be a valid label
(text, 64); otherwise the result is `Err` with the wallet-name validation
error (`wallet: empty wallet name`, `wallet: wallet name too long (max 64
bytes)`, `wallet: wallet name contains control character at offset N`).
`wallet_new(name)` builds the aggregate without validating; the books and
ledger are empty. `wallet_new_checked(name)` validates first and returns
`Result[Wallet, Str]`.

## 8. Non-goals

No secp256k1/BIP32 derivation, no xpub parsing or checksum validation, no
address encoding/decoding, no hashing, no signing, no persistence, no
concurrency. Consumers wanting those should combine this model with
`xiom.bitcoin` (wire/codec) and their own cryptographic backend.
