// XIOM -- xiom.web3: pure-XIOM Web3 primitives (facade)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Public entry point for the package. The implementation is split into four
// submodules, each small enough to audit on its own; `use xiom.web3;` gives
// the whole surface through the thin delegating functions below.
//
//   * xiom.web3.keccak    -- Keccak-256 (original padding), hex helper.
//   * xiom.web3.accounts  -- 0x addresses, EIP-55 checksum/verification.
//   * xiom.web3.ens       -- ASCII-subset normalization, labelhash, namehash.
//   * xiom.web3.contract  -- selectors and the minimal 32-byte ABI word set.
//   * xiom.web3.provider  -- provider config + JSON-RPC request/response
//                            model (no networking).
//
// No cross-package imports, no FFI, no networking.

module xiom.web3

use xiom.web3.keccak;
use xiom.web3.accounts;
use xiom.web3.ens;
use xiom.web3.contract;
use xiom.web3.provider;

/// Number of hex digits in a canonical address (without the 0x prefix).
pub const ACCOUNT_ADDRESS_HEX_LEN: Int = 40;

/// Maximum label length in bytes (ENS limit; unchanged by normalization).
pub const ENS_MAX_LABEL_LEN: Int = 63;

/// Maximum normalized name length in bytes, dots included.
pub const ENS_MAX_NAME_LEN: Int = 255;

/// Provider transport kind: plain HTTP(S) endpoint.
pub const PROVIDER_HTTP: Int = 0;
/// Provider transport kind: WebSocket endpoint (modeled, not opened).
pub const PROVIDER_WS: Int = 1;
/// Provider transport kind: local IPC socket or pipe path.
pub const PROVIDER_IPC: Int = 2;
/// Largest accepted provider timeout, in milliseconds.
pub const PROVIDER_MAX_TIMEOUT_MS: Int = 3600000;

// --------------------------------------------------
//  keccak
// --------------------------------------------------

/// Keccak-256 (Ethereum's hash, pad byte 0x01) of `data`; 32 bytes.
pub fn keccak256(data: &Vec[UInt8]) -> Vec[UInt8] {
  return keccak.keccak256(data);
}

/// Lowercase hex of the Keccak-256 digest (64 digits, no 0x prefix).
pub fn keccak256_hex(data: &Vec[UInt8]) -> Str {
  return keccak.keccak256_hex(data);
}

// --------------------------------------------------
//  accounts
// --------------------------------------------------

/// Decode an address: exactly 40 hex digits, optional 0x/0X prefix, digits
/// case-insensitive.
pub fn account_address_bytes(input: Str) -> Result[Vec[UInt8], Str] {
  return accounts.account_address_bytes(input);
}

/// Canonical lowercase rendering `0x` + 40 hex digits.
pub fn account_address_normalize(input: Str) -> Result[Str, Str] {
  return accounts.account_address_normalize(input);
}

/// 20 raw bytes to the canonical lowercase address.
pub fn account_address_from_bytes(bytes: &Vec[UInt8]) -> Result[Str, Str] {
  return accounts.account_address_from_bytes(bytes);
}

/// EIP-55 mixed-case checksum of an address.
pub fn account_address_checksum(input: Str) -> Result[Str, Str] {
  return accounts.account_address_checksum(input);
}

/// EIP-55 verification; all-lowercase/all-uppercase input is Ok(false).
pub fn account_checksum_valid(input: Str) -> Result[Bool, Str] {
  return accounts.account_checksum_valid(input);
}

// --------------------------------------------------
//  ens
// --------------------------------------------------

/// Normalize an ENS name to the documented ASCII subset.
pub fn ens_normalize(name: Str) -> Result[Str, Str] {
  return ens.ens_normalize(name);
}

/// keccak256 of one normalized label's bytes (EIP-137 labelhash).
pub fn ens_labelhash(label: Str) -> Result[Vec[UInt8], Str] {
  return ens.ens_labelhash(label);
}

/// EIP-137 namehash of a normalized name; 32 bytes.
pub fn ens_namehash(name: Str) -> Result[Vec[UInt8], Str] {
  return ens.ens_namehash(name);
}

/// `0x` + lowercase hex of the namehash.
pub fn ens_namehash_hex(name: Str) -> Result[Str, Str] {
  return ens.ens_namehash_hex(name);
}

// --------------------------------------------------
//  contract
// --------------------------------------------------

/// First 4 bytes of keccak256 over a canonical signature.
pub fn contract_selector(signature: Str) -> Result[Vec[UInt8], Str] {
  return contract.contract_selector(signature);
}

/// `0x` + lowercase hex of the 4-byte selector.
pub fn contract_selector_hex(signature: Str) -> Result[Str, Str] {
  return contract.contract_selector_hex(signature);
}

/// One 32-byte big-endian uint256 word.
pub fn abi_encode_uint(value: Int) -> Result[Vec[UInt8], Str] {
  return contract.abi_encode_uint(value);
}

/// One 32-byte two's-complement int256 word (sign-extended).
pub fn abi_encode_int(value: Int) -> Vec[UInt8] {
  return contract.abi_encode_int(value);
}

/// One 32-byte bool word.
pub fn abi_encode_bool(value: Bool) -> Vec[UInt8] {
  return contract.abi_encode_bool(value);
}

/// One 32-byte address word (20 bytes right-aligned).
pub fn abi_encode_address(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return contract.abi_encode_address(bytes);
}

/// Concatenate pre-encoded 32-byte ABI words verbatim.
pub fn abi_encode_words(words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  return contract.abi_encode_words(words);
}

/// Call data: 4-byte selector + concatenated 32-byte argument words.
pub fn abi_encode_call(selector: &Vec[UInt8],
                       words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  return contract.abi_encode_call(selector, words);
}

/// Copy the 32 bytes at absolute `off`.
pub fn abi_read_word(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  return contract.abi_read_word(data, off);
}

/// Decode one 32-byte word as uint256 into the signed 64-bit Int range.
pub fn abi_decode_uint_word(word: &Vec[UInt8]) -> Result[Int, Str] {
  return contract.abi_decode_uint_word(word);
}

/// Decode one 32-byte word as an address (bytes 0..11 must be zero).
pub fn abi_decode_address_word(word: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return contract.abi_decode_address_word(word);
}

// --------------------------------------------------
//  provider (model only; no networking)
// --------------------------------------------------

/// Validate a provider configuration.
pub fn provider_config(kind: Int, url: Str, chain_id: Int,
                       timeout_ms: Int) -> Result[ProviderConfig, Str] {
  return provider.provider_config(kind, url, chain_id, timeout_ms);
}

/// Validate one JSON-RPC request.
pub fn provider_request(id: Int, method: Str,
                        params: Str) -> Result[RpcRequest, Str] {
  return provider.provider_request(id, method, params);
}

/// Canonical compact JSON-RPC 2.0 request text.
pub fn provider_encode_request(req: &RpcRequest) -> Str {
  return provider.provider_encode_request(req);
}

/// Success response constructor.
pub fn provider_response_ok(id: Int, result_json: Str) -> RpcResponse {
  return provider.provider_response_ok(id, result_json);
}

/// Error response constructor.
pub fn provider_response_error(id: Int, code: Int, message: Str) -> RpcResponse {
  return provider.provider_response_error(id, code, message);
}

/// Scan a JSON-RPC response envelope (see xiom.web3.provider for the
/// documented subset).
pub fn provider_decode_response(body: Str,
                                expected_id: Int) -> Result[RpcResponse, Str] {
  return provider.provider_decode_response(body, expected_id);
}

/// Parse a canonical `0x` quantity into the signed 64-bit range.
pub fn provider_parse_quantity(text: Str) -> Result[Int, Str] {
  return provider.provider_parse_quantity(text);
}

/// Canonical `0x` quantity for a non-negative Int.
pub fn provider_format_quantity(n: Int) -> Result[Str, Str] {
  return provider.provider_format_quantity(n);
}
