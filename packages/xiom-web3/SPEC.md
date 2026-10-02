# xiom.web3 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.62.2 and
the pinned stdlib; not published).
Manifest: `package.xi` (`xiom.web3`, version `0.1.0`).
Layout:

| Module | File |
|---|---|
| `xiom.web3` (facade, same public API) | `src/web3.xi` |
| `xiom.web3.keccak` | `src/keccak.xi` |
| `xiom.web3.accounts` | `src/accounts.xi` |
| `xiom.web3.ens` | `src/ens.xi` |
| `xiom.web3.contract` | `src/contract.xi` |
| `xiom.web3.provider` | `src/provider.xi` |

Depends on `xiom.std` only (`xiom.string`, `xiom.string.compare`,
`xiom.string.builder`, `xiom.convert`, `xiom.encoding.hex`). No FFI, no
networking, no external packages. Every integer is the signed 64-bit
platform `Int`; 256-bit ABI values outside its range are rejected, never
truncated.

## 1. Keccak-256

`keccak256(data)` implements the original Keccak (Ethereum's hash), **not**
NIST SHA3-256: pad10*1 with domain byte `0x01` (SHA3 uses `0x06`).

- Rate 136 bytes (1088 bits), capacity 512 bits, 32-byte digest.
- State: 25 lanes of 64 bits, lane `x + 5*y`, 24 rounds of Keccak-f[1600]
  (theta, rho+pi, chi, iota) over the signed 64-bit `Int` type.
- Padding: append `0x01`, zero-fill to a multiple of 136 bytes, then set the
  most significant bit of the final byte (`|= 0x80`); a message length of
  135 mod 136 therefore yields `0x81` in one byte.
- Absorption XORs each rate block little-endian into lanes 0..16; the digest
  is lanes 0..3 little-endian.
- `keccak256_hex(data)` returns the 64 lowercase hex digits without `0x`.

Implementation note (compiler/stdlib finding): the logical right shift used
by the 64-bit rotate special-cases `n = 63`, because `2^63` is
`Int64_MIN` (negative) and the stdlib `_u64_lshr` idiom divides by
`_pow2(n)`, which turns positive for negative numerators when `n = 63`
(`INT64_MIN / INT64_MIN == 1`, giving 3 instead of 1). The stdlib's
`xiom.crypto.hash._u64_lshr` / `_u64_shr` carry the same latent issue; their
callers never shift by 63, so they are unaffected.

Verified vectors (all in the test suite):

| Input | Digest |
|---|---|
| `""` | `c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470` |
| `"abc"` | `4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45` |
| `"The quick brown fox jumps over the lazy dog"` | `4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15` |
| `"Hello, world!"` | `b6e16d27ac5ab427a7f68900ac5559ce272dc6c37c82b3e052246c82244c50e4` |
| 135 x `0x00` | `29e3704feeca7fb9ba229f0fa04d9b36449cf3ad6e1d85d9cfff3a10df9abc3e` |
| 136 x `0x00` | `3a5912a7c5faa06ee4fe906253e339467a9ce87d533c65be3c15cb231cdb25f9` |
| `"transfer(address,uint256)"` | `a9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b` |

## 2. accounts

Canonical address text is `0x` + exactly 40 hex digits.

`account_address_bytes(input)` accepts an optional `0x`/`0X` prefix and
case-insensitive digits; it decodes to 20 bytes.

| Case | Error |
|---|---|
| length != 40 digits (prefix excluded) | `web3: address must be 40 hex digits with an optional 0x prefix` |
| a non-hex digit | `web3: address contains a non-hex character` |

- `account_address_normalize(input)` returns the lowercase `0x` form.
- `account_address_from_bytes(bytes)` requires exactly 20 bytes, else
  `web3: address bytes must be 20 bytes`.
- `account_address_checksum(input)` implements EIP-55: hash the 40
  lowercase hex digits with Keccak-256 and uppercase each letter whose
  matching hash nibble (high nibble for even positions, low nibble for odd)
  is >= 8. It validates first and returns the mixed-case `0x` form.
- `account_checksum_valid(input)` is the verification policy:
  - mixed-case input → `Ok(true)` iff it equals the EIP-55 rendering;
  - all-lowercase or all-uppercase input → `Ok(false)` (per EIP-55, single
    case carries no checksum information);
  - malformed input → `Err` from the same catalog as above.

Vectors (all `[PASS]` in the suite):

```
0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359
0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB
0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb
```

## 3. ens

### 3.1 Normalization (`ens_normalize`)

Documented ASCII subset:

- ASCII uppercase `A-Z` folds to lowercase (so `"FOO.eth"` → `"foo.eth"`).
- Label characters are `[a-z0-9-]` only.
- Labels are 1..63 bytes; a label may not start or end with `-`.
- The name (dots included) is at most 255 bytes.
- Punycode labels (`xn--` at the start of any label) are rejected because
  punycode is not decoded here.
- The empty name (root) normalizes to `""`.
- Anything else (Unicode, spaces, underscores, control bytes) is
  `web3: ENS name contains a character outside the ASCII subset`.

| Error | Case |
|---|---|
| `web3: ENS name has an empty label` | `foo..eth`, `.foo.eth`, `foo.eth.` |
| `web3: ENS label starts or ends with a hyphen` | `-foo.eth`, `foo-.eth` |
| `web3: ENS label exceeds 63 bytes` | any label > 63 bytes |
| `web3: ENS name exceeds 255 bytes` | normalized name > 255 bytes |
| `web3: ENS punycode labels are outside the documented ASCII subset` | `xn--...` label |

### 3.2 Hashing

- `ens_labelhash(label)`: the label must normalize to a non-empty string
  without dots (`web3: ENS label must not be empty`,
  `web3: ENS label must not contain a dot`); returns
  `keccak256(normalized label bytes)`.
- `ens_namehash(name)`: normalizes, then folds labels right-to-left:
  `node = keccak256(node ++ keccak256(label))` starting from 32 zero bytes.
  The root name hashes to 32 zero bytes.
- `ens_namehash_hex(name)`: `0x` + 64 lowercase hex digits.

Vectors:

| Name | Node |
|---|---|
| `""` | 32 x `0x00` |
| `labelhash("eth")` | `4f5b812789fc606be1b3b16908db13fc7a9adf7ca72641f84d75b47069d3d7f0` |
| `namehash("eth")` | `93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae` |
| `namehash("foo.eth")` | `de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f` |

Full UTS-46 / ENSIP-15 (Unicode normalization, script checks, emoji rules,
punycode) is explicitly out of scope.

## 4. contract: selectors and ABI words

### 4.1 Function selectors

`contract_selector(signature)` hashes the UTF-8 bytes of a canonical
signature such as `"transfer(address,uint256)"` and returns the first 4
bytes. Validation requires: length >= 3, every byte printable ASCII
(0x21..0x7E, so no spaces or controls), a function name before the first
`(`, balanced parentheses, and a trailing `)`.

| Error | Case |
|---|---|
| `web3: signature must be a non-empty function signature` | `""` (or < 3 bytes) |
| `web3: signature must be printable ASCII without spaces` | `transfer address)` |
| `web3: signature has unbalanced parentheses` | `transfer(`, `transfer(address` |
| `web3: signature must end with ')'` | `transfer(address]` |
| `web3: signature must start with a function name` | `(address)` |

`contract_selector_hex` adds `0x` and 8 lowercase hex digits
(`transfer(address,uint256)` → `0xa9059cbb`).

### 4.2 ABI words

Every value occupies one 32-byte big-endian word.

- `abi_encode_uint(value)`: non-negative, zero-padded on the left
  (`web3: ABI uint value is negative` otherwise).
- `abi_encode_int(value)`: two's complement, sign-extended to 32 bytes
  (infallible).
- `abi_encode_bool(value)`: 31 zero bytes then `0x00`/`0x01`.
- `abi_encode_address(bytes)`: exactly 20 bytes, 12 zero bytes then the
  address (`web3: ABI address value must be 20 bytes` otherwise).
- `abi_encode_words(words)`: concatenates pre-encoded words; each must be
  exactly 32 bytes (`web3: ABI word must be 32 bytes`). Empty is valid.
- `abi_encode_call(selector, words)`: exactly 4 selector bytes
  (`web3: ABI selector must be 4 bytes`) followed by the argument words;
  with `uint256(5)` and one address the result is 68 bytes, selector first.

Reads and decodes:

- `abi_read_word(data, off)`: copies 32 bytes at an absolute offset; a
  negative offset or a window past the end is
  `web3: ABI word out of bounds`.
- `abi_decode_uint_word(word)`: requires 32 bytes
  (`web3: ABI word must be 32 bytes`), bytes 0..23 zero and byte 24 < 0x80,
  else `web3: ABI uint word does not fit Int`; returns the big-endian value.
- `abi_decode_address_word(word)`: requires bytes 0..11 zero
  (`web3: ABI address word is not right-aligned`), then copies 20 bytes.

Dynamic types (bytes/string/arrays), int<M> decoding and selectors computed
from anything other than a canonical signature are out of scope.

## 5. provider (model only; no networking)

Three exported value types (in `xiom.web3.provider`):

```
ProviderConfig { kind: Int; url: Str; chain_id: Int; timeout_ms: Int; }
RpcRequest     { id: Int; method: Str; params: Str; }
RpcResponse    { id: Int; ok: Bool; result_json: Str;
                 error_code: Int; error_message: Str; }
```

### 5.1 Configuration

`provider_config(kind, url, chain_id, timeout_ms)`:

| Check | Error |
|---|---|
| `kind` in `PROVIDER_HTTP` (0), `PROVIDER_WS` (1), `PROVIDER_IPC` (2) | `web3: provider kind must be 0 (http), 1 (ws) or 2 (ipc)` |
| URL non-empty | `web3: provider url must not be empty` |
| HTTP kind: url starts `http://` or `https://`; WS kind: `ws://` or `wss://`; IPC kind: no `://` | `web3: provider url scheme does not match the provider kind` |
| `chain_id >= 0` | `web3: provider chain id is negative` |
| `1 <= timeout_ms <= PROVIDER_MAX_TIMEOUT_MS` (3600000) | `web3: provider timeout must be 1..3600000 ms` |

### 5.2 Requests

`provider_request(id, method, params)` requires `id >= 0`
(`web3: rpc request id is negative`), a non-empty method of
`[A-Za-z0-9_]` (`web3: rpc method must not be empty`,
`web3: rpc method contains an invalid character`), and `params` text
starting with `[` and ending with `]`
(`web3: rpc params must be a JSON array text`). The interior is caller
responsibility and is inserted verbatim.

`provider_encode_request(req)` emits the canonical compact envelope with a
fixed member order:

```
{"jsonrpc":"2.0","id":7,"method":"eth_chainId","params":[]}
```

### 5.3 Responses and quantities

`provider_response_ok(id, result_json)` and
`provider_response_error(id, code, message)` construct response values.

`provider_decode_response(body, expected_id)` is a byte-wise member scanner,
not a validating JSON parser:

- the `"id"` member must exist and be an integer
  (`web3: response has no id member`,
  `web3: response id is not an integer`,
  `web3: response id is out of range`);
- when `expected_id >= 0`, the id must match
  (`web3: response id does not match the request id`; pass `-1` to skip);
- `"result"` must be a **scalar** JSON value -- string, number, `true`,
  `false` or `null` -- and is returned verbatim in `result_json`
  (`web3: response result must be a scalar JSON value` rejects objects and
  arrays);
- or `"error"` must be an object with an integer `code` and string
  `message` (`web3: response error object needs code and message`,
  `web3: response error code is not an integer`,
  `web3: response error message is not a JSON string`); escapes inside the
  message are returned raw;
- having both members is
  `web3: response has both result and error`; having neither is
  `web3: response has neither result nor error member`.

Member key order is free; JSON whitespace is allowed; keys inside string
values are skipped.

`provider_parse_quantity(text)` accepts canonical `0x` quantities only
(`0x0`, `0x2a`, no leading zeros, no sign) and returns an `Int`
(`web3: quantity must start with 0x`, `web3: quantity has no hex digits`,
`web3: quantity is not canonical (leading zero)`,
`web3: quantity has a non-hex character`,
`web3: quantity exceeds the signed 64-bit range`).
`provider_format_quantity(n)` renders the minimal lowercase `0x` form and
rejects negative input (`web3: quantity must be non-negative`).

Transports, subscriptions, batching and JSON encoding/decoding beyond this
subset are deliberately out of scope; `result_json` is handed to the caller
as raw text for their own JSON layer.

## 6. Non-goals

Sockets/HTTP/WebSocket transports, JSON parsing or generation beyond the
response scanner, secp256k1 signing/recovery, EIP-1193 subscriptions,
EIP-2718 typed transactions, dynamic/nested ABI types, full Unicode ENS
normalization, and floating point.

## 7. Verification

```
xiom --run tests/test_conformance.xi
```

28 deterministic checks, all `[PASS]`, exit 0; no files, no network, no
randomness. The suite exercises every public function group, all Keccak
padding boundaries (0, 3, 13, 26, 40, 43, 135, 136 bytes), the four EIP-55
vectors, the EIP-137 namehash vectors, ABI round-trips and error catalogs,
and the provider request/response paths including id mismatch and malformed
envelopes.
