# xiom.web3

> **Status:** `incubating` -- conformance-tested (28/28 checks, compiler
> v0.62.2, pinned stdlib); not yet published.
> **Scope:** pure-XIOM Web3 primitives: Keccak-256, EIP-55 account
> addresses, ENS normalization/namehash, contract selectors and a minimal
> 32-byte-word ABI subset, plus a blockchain-provider request/response
> **model**. No networking, no FFI, no crypto beyond Keccak-256.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.string.builder`, `xiom.convert`, `xiom.encoding.hex`; tests add
> `xiom.io` and `xiom.test`).

## What it is

`xiom.web3` is the deterministic, offline half of a Web3 client: everything
that can be computed byte-exactly without a socket. It implements Keccak-256
in-package (original Keccak padding, not NIST SHA3-256), builds on it for
EIP-55 checksums and EIP-137 namehash, derives 4-byte function selectors,
encodes/decodes the statically-sized Solidity ABI words, and models JSON-RPC
provider configuration, requests and responses so a caller can wire in any
transport.

The implementation is split into small modules; every `.xi` file stays under
600 lines. All public names are also re-exported through the `xiom.web3`
facade, so `use xiom.web3;` is enough.

## Libs inventory

| Module | Description |
|--------|-------------|
| `xiom.web3` | Facade: the whole public API in one import. |
| `xiom.web3.keccak` | Keccak-256 of bytes, `0x`-less lowercase hex digest. |
| `xiom.web3.accounts` | 0x addresses: validate, lowercase-normalize, EIP-55 checksum and verification. |
| `xiom.web3.ens` | ASCII-subset ENS normalization, labelhash, namehash. |
| `xiom.web3.contract` | Function selectors and the minimal 256-bit-word ABI codec. |
| `xiom.web3.provider` | Provider config + JSON-RPC request/response model (no transport). |

## API

| Function | Returns | Description |
|---|---|---|
| `keccak256(data)` | `Vec[UInt8]` | 32-byte Keccak-256 (pad byte `0x01`). |
| `keccak256_hex(data)` | `Str` | 64 lowercase hex digits, no prefix. |
| `account_address_bytes(input)` | `Result[Vec[UInt8], Str]` | 40 hex digits (optional `0x`/`0X`) to 20 bytes. |
| `account_address_normalize(input)` | `Result[Str, Str]` | Canonical `0x` + 40 lowercase digits. |
| `account_address_from_bytes(bytes)` | `Result[Str, Str]` | 20 bytes to the canonical lowercase address. |
| `account_address_checksum(input)` | `Result[Str, Str]` | EIP-55 mixed-case rendering. |
| `account_checksum_valid(input)` | `Result[Bool, Str]` | `true` only for mixed-case input matching EIP-55; single case is `false`. |
| `ens_normalize(name)` | `Result[Str, Str]` | ASCII-subset normalization (root `""` allowed). |
| `ens_labelhash(label)` | `Result[Vec[UInt8], Str]` | keccak256 of one normalized label. |
| `ens_namehash(name)` | `Result[Vec[UInt8], Str]` | EIP-137 node, 32 bytes. |
| `ens_namehash_hex(name)` | `Result[Str, Str]` | `0x` + 64 hex digits of the node. |
| `contract_selector(signature)` | `Result[Vec[UInt8], Str]` | First 4 bytes of keccak256 over a canonical signature. |
| `contract_selector_hex(signature)` | `Result[Str, Str]` | `0x` + 8 hex digits. |
| `abi_encode_uint(value)` | `Result[Vec[UInt8], Str]` | 32-byte big-endian uint256 (non-negative). |
| `abi_encode_int(value)` | `Vec[UInt8]` | 32-byte two's-complement int256. |
| `abi_encode_bool(value)` | `Vec[UInt8]` | 32-byte bool word (0/1). |
| `abi_encode_address(bytes)` | `Result[Vec[UInt8], Str]` | 32-byte word, 20-byte address right-aligned. |
| `abi_encode_words(words)` | `Result[Vec[UInt8], Str]` | Concatenate pre-encoded 32-byte words. |
| `abi_encode_call(selector, words)` | `Result[Vec[UInt8], Str]` | 4-byte selector + argument words. |
| `abi_read_word(data, off)` | `Result[Vec[UInt8], Str]` | Copy the 32 bytes at `off`. |
| `abi_decode_uint_word(word)` | `Result[Int, Str]` | uint256 word into signed 64-bit `Int`. |
| `abi_decode_address_word(word)` | `Result[Vec[UInt8], Str]` | Address word (bytes 0..11 zero). |
| `provider_config(kind, url, chain_id, timeout_ms)` | `Result[ProviderConfig, Str]` | Validate an http/ws/ipc endpoint description. |
| `provider_request(id, method, params)` | `Result[RpcRequest, Str]` | Validate one JSON-RPC request. |
| `provider_encode_request(req)` | `Str` | Canonical compact JSON-RPC 2.0 text. |
| `provider_response_ok(id, result_json)` | `RpcResponse` | Success response value. |
| `provider_response_error(id, code, message)` | `RpcResponse` | Error response value. |
| `provider_decode_response(body, expected_id)` | `Result[RpcResponse, Str]` | Scan a response envelope; `expected_id < 0` skips the id check. |
| `provider_parse_quantity(text)` | `Result[Int, Str]` | Canonical `0x` quantity to `Int`. |
| `provider_format_quantity(n)` | `Result[Str, Str]` | Minimal lowercase `0x` quantity text. |

Constants: `ACCOUNT_ADDRESS_HEX_LEN`, `ENS_MAX_LABEL_LEN`,
`ENS_MAX_NAME_LEN`, `PROVIDER_HTTP`, `PROVIDER_WS`, `PROVIDER_IPC`,
`PROVIDER_MAX_TIMEOUT_MS`.

```xi
use xiom.web3;

account_address_checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
// Ok("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")

ens_namehash_hex("foo.eth")
// Ok("0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f")

contract_selector_hex("transfer(address,uint256)")
// Ok("0xa9059cbb")
```

## Documented subset

- ENS uses a UTS-46-**lite** ASCII subset: lowercase `[a-z0-9-]` labels,
  no leading/trailing hyphen, no `xn--` punycode, label <= 63 bytes, name
  <= 255 bytes. Unicode input is rejected, not transliterated.
- ABI values are 256-bit words; decoded integers must fit the signed 64-bit
  platform `Int` (wider words are rejected, never truncated). Dynamic ABI
  types are out of scope.
- The provider response scanner reads the envelope members only; `result`
  must be a scalar JSON value (string/number/true/false/null), and error
  messages are returned with their JSON escapes intact. The module never
  opens a connection.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 28 `[PASS]` lines, then `xiom.web3: all tests passed`, exit 0.
Covers Keccak known vectors (including the 135/136-byte padding boundary),
all four EIP-55 vectors, ENS namehash vectors, selector and ABI round-trips,
and provider request/response handling.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
