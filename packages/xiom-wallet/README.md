# xiom.wallet

> **Status:** `incubating` -- conformance-tested (20/20); not yet published on the XIOM registry.
> **Scope:** a deterministic metadata model (paths, books, ledger, export).
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`); the tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.wallet` is a pure-XIOM, deterministic **model** of wallet metadata. It
is deliberately not a signer and not a key manager:

- **No cryptography, no hashing.** Keys are opaque caller-supplied strings
  (an "xpub-style" key is stored and compared, never parsed, derived or
  validated cryptographically).
- **No networking.** Only in-memory strings and integers are handled.
- **No address codecs.** Addresses are opaque strings with *structural*
  validation only (visible ASCII, no spaces, length bound).

Implemented:

- **BIP32-style derivation paths**: parse, validate and canonically
  re-format `m/44'/0'/0'/0/0` with `'`, `h` and `H` hardened markers
  (canonical form uses `'`), component bounds `0..2147483647`, no leading
  zeros, at most 255 components.
- **Account book**: labelled accounts with opaque xpub-style keys
  (add, find, rotate key; unique labels).
- **Address book**: labelled addresses with structural validation (add,
  find by label or address; unique labels and addresses).
- **Integer balance ledger**: settled balance, reserved (pending intent)
  funds, strictly increasing posting sequence numbers, credits, and
  transfer intents with fees, overflow guards, insufficient-funds checks
  and double-spend rejection (an intent settles at most once; intent ids
  are unique).
- **Canonical text export**: tab-separated listing of the wallet name,
  account book, address book and ledger (postings plus every intent with
  its status), deterministic byte-for-byte.

## API

| Function | Returns | Description |
|---|---|---|
| `derivation_path_parse(s)` | `Result[DerivationPath, Str]` | Parse `m`, `m/0`, `m/44'/0h/0H/0/0`, ... |
| `derivation_path_format(p)` | `Str` | Canonical text (`'` for hardened). |
| `derivation_path_validate(s)` | `Bool` | True when `parse` accepts `s`. |
| `derivation_path_new()` | `DerivationPath` | The empty path `m` (depth 0). |
| `derivation_path_depth(p)` / `..._component(p,i)` / `..._is_hardened(p,i)` / `..._hardened_count(p)` / `..._equal(a,b)` | `Int` / `Int` / `Bool` / `Int` / `Bool` | Accessors (component -1 out of range). |
| `account_book_new()` / `account_book_count(b)` | `AccountBook` / `Int` | Empty book / size. |
| `account_book_add(b, label, key)` | `Result[Int, Str]` | Append; returns the index. |
| `account_book_find(b, label)` | `Int` | Index or -1. |
| `account_book_label(b,i)` / `account_book_key(b,i)` | `Str` | `""` when out of range. |
| `account_book_set_key(b, i, key)` | `Result[Int, Str]` | Replace a key (validated). |
| `account_book_export(b)` | `Str` | Canonical account listing. |
| `address_book_new()` / `address_book_count(b)` | `AddressBook` / `Int` | Empty book / size. |
| `address_book_add(b, label, address)` | `Result[Int, Str]` | Append; returns the index. |
| `address_book_find_label(b, label)` / `address_book_find_address(b, addr)` | `Int` | Index or -1. |
| `address_book_label(b,i)` / `address_book_address(b,i)` | `Str` | `""` when out of range. |
| `address_book_export(b)` | `Str` | Canonical address listing. |
| `ledger_new()` | `Ledger` | Empty ledger. |
| `ledger_credit(l, amount, reference)` | `Result[Int, Str]` | Credit; returns the new balance. |
| `ledger_intent_create(l, id, amount, fee, dst)` | `Result[Int, Str]` | Reserve a transfer intent; returns its index. |
| `ledger_intent_execute(l, id)` | `Result[Int, Str]` | Settle once; returns the new balance. |
| `ledger_intent_cancel(l, id)` | `Result[Int, Str]` | Release the reservation. |
| `ledger_balance` / `ledger_reserved` / `ledger_available` / `ledger_sequence` | `Int` | Ledger state. |
| `ledger_posting_count(l)` and `ledger_posting_*(l, i)` | `Int` / `Str` | Posting accessors (defaults when out of range). |
| `ledger_intent_count` / `ledger_intent_index` / `ledger_intent_*` | `Int` / `Str` | Intent accessors. |
| `ledger_export(l)` | `Str` | Canonical ledger listing. |
| `wallet_new(name)` / `wallet_new_checked(name)` | `Wallet` / `Result[Wallet, Str]` | Aggregate of name + books + ledger. |
| `wallet_export(w)` | `Result[Str, Str]` | Canonical full-wallet listing. |

```xi
use xiom.wallet;

var ab = account_book_new();
account_book_add(&mut ab, "hot", "xpub-opaque-string");

var l = ledger_new();
ledger_credit(&mut l, 10000, "funding-1");
ledger_intent_create(&mut l, "t1", 3000, 10, "xpub-opaque-string");
ledger_intent_execute(&mut l, "t1");      // balance 6990, sequence 2

let p = derivation_path_parse("m/44'/0'/0'/0/0");
if p.is_ok {
  let path: DerivationPath = p.value;
  io.println(derivation_path_format(&path));   // m/44'/0'/0'/0/0
}
```

## Verify

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.wallet
```

Expected: 20 `[PASS]` lines and
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Install / publish

```
xiom pkg install xiom.wallet@0.1.0     # consumer (after publish)
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Not yet published on the XIOM registry; `0.1.0` is the intended first
release.

## Tests

`tests/test_conformance.xi` (`module wallet_tests`, 20 checks, direct
calls, fixture-driven): path canonicalization and every documented
rejection, account/address book validation and duplicates, ledger posting
sequences, credit overflow, intent reservation/execution/cancellation,
double-spend rejection and the canonical exports. See `SPEC.md` for the
precise grammar, ledger rules and error catalog.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
