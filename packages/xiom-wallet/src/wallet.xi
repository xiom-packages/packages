// XIOM -- xiom.wallet: deterministic wallet metadata model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, deterministic MODEL of wallet metadata. It performs no
// cryptography, no hashing and no networking. Keys, addresses, references and
// intent ids are opaque caller-supplied strings; the module only validates
// them structurally and stores them.
//
//   * BIP32-style derivation paths: parse, validate, canonical re-format.
//     Grammar (EBNF):
//       path      := "m" | "m" ( "/" component )+
//       component := digits | digits marker
//       digits    := "0" | nonzero digit*
//       marker    := "'" | "h" | "H"
//     Component values are stored as raw indices in 0..2147483647 with a
//     parallel hardened flag; the marker is NOT folded into bit 31. The
//     canonical format emits "'" for every hardened component.
//   * Account book: labelled accounts, each with an opaque xpub-style key.
//   * Address book: labelled addresses with structural validation.
//   * Integer balance ledger: settled balance, reserved (pending intent)
//     funds, strictly increasing posting sequence numbers, and transfer
//     intents with fees, overflow guards and double-spend rejection.
//   * Canonical tab-separated text export of the whole wallet.
//
// Language notes (compiler v0.62.1): free functions only; no self methods,
// no lambdas, no Vec of struct types (the books use parallel Vec fields);
// Result construction is confined to the leaf helpers below; Str values are
// compared with str_compare, never with `==`; every Vec element read is
// bound to a typed local first; a Vec element is never assigned in place
// (the intent status vector is rebuilt instead).

module xiom.wallet

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (leaf helpers; see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[DerivationPath, Str].
fn _ok_path(v: DerivationPath) -> Result[DerivationPath, Str] {
  return Ok(v);
}

// Err(m) for Result[DerivationPath, Str].
fn _err_path(m: Str) -> Result[DerivationPath, Str] {
  return Err(m);
}

// Ok(v) for Result[Wallet, Str].
fn _ok_wallet(v: Wallet) -> Result[Wallet, Str] {
  return Ok(v);
}

// Err(m) for Result[Wallet, Str].
fn _err_wallet(m: Str) -> Result[Wallet, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Maximum number of components after "m" (BIP32 depth is one byte).
pub const WALLET_MAX_PATH_DEPTH: Int = 255;

/// Maximum component value (2^31 - 1); hardened components use the same
/// raw bound plus the hardened flag.
pub const WALLET_MAX_COMPONENT: Int = 2147483647;

/// Maximum label length (account labels, address labels, wallet name),
/// in bytes.
pub const WALLET_MAX_LABEL_LEN: Int = 64;

/// Maximum account key (xpub-style opaque string) length, in bytes.
pub const WALLET_MAX_KEY_LEN: Int = 128;

/// Maximum address length, in bytes.
pub const WALLET_MAX_ADDRESS_LEN: Int = 128;

/// Maximum reference / intent id length, in bytes.
pub const WALLET_MAX_REF_LEN: Int = 128;

/// Largest platform Int (2^63 - 1); ledger arithmetic is guarded against it.
pub const WALLET_INT64_MAX: Int = 9223372036854775807;

/// Intent status: created, funds reserved, not yet settled.
pub const INTENT_PENDING: Int = 0;

/// Intent status: executed (funds left the balance; a posting exists).
pub const INTENT_EXECUTED: Int = 1;

/// Intent status: cancelled (reserved funds released; no posting).
pub const INTENT_CANCELLED: Int = 2;

/// Posting kind: credit (balance increase).
pub const POSTING_CREDIT: Int = 0;

/// Posting kind: transfer (balance decrease of amount + fee).
pub const POSTING_TRANSFER: Int = 1;

// --------------------------------------------------
//  Structural validation helpers
// --------------------------------------------------

// True for ASCII digits 0..9.
fn _is_digit(b: Int) -> Bool {
  if b < 48 || b > 57 {
    return false;
  }
  return true;
}

// Validate a non-empty text whose bytes must not be control characters
// (0x00..0x1F and 0x7F): labels, keys, references, intent ids, wallet
// names. Returns the text or Err("wallet: ...").
fn _validate_text(s: Str, kind: Str, maxlen: Int) -> Result[Str, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_str("wallet: empty " + kind);
  }
  if n > maxlen {
    return _err_str("wallet: " + kind + " too long (max " + convert.int_to_string(maxlen) + " bytes)");
  }
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b == 127 {
      return _err_str("wallet: " + kind + " contains control character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _ok_str(s);
}

// Validate a non-empty address-like token: every byte must be visible ASCII
// 0x21..0x7E (no controls, no spaces, no non-ASCII). Used for addresses and
// intent destinations.
fn _validate_visible(s: Str, kind: Str, maxlen: Int) -> Result[Str, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_str("wallet: empty " + kind);
  }
  if n > maxlen {
    return _err_str("wallet: " + kind + " too long (max " + convert.int_to_string(maxlen) + " bytes)");
  }
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return _err_str("wallet: " + kind + " contains invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _ok_str(s);
}

// --------------------------------------------------
//  Derivation paths
// --------------------------------------------------

/// A parsed BIP32-style derivation path. components and hardened are
/// parallel vectors (hardened: 0 or 1); depth equals components.len() for
/// every value produced by derivation_path_parse. The hardened marker is
/// stored as a flag, not folded into the component value.
pub type DerivationPath = {
  depth: Int;
  components: Vec[Int];
  hardened: Vec[Int];
}

/// The empty path "m" (depth 0).
pub fn derivation_path_new() -> DerivationPath {
  return DerivationPath{ depth: 0; components: Vec[Int].new(); hardened: Vec[Int].new(); };
}

/// Parse a BIP32-style derivation path: "m" or "m" followed by "/"
/// components. A component is a decimal number without leading zeros,
/// optionally followed by a hardened marker ("'", "h" or "H"), with value
/// 0..2147483647. At most 255 components. The canonical form of every
/// marker is "'".
/// Errors (offsets are 0-based byte offsets into the input):
/// "wallet: empty derivation path"; "wallet: derivation path must start
/// with m"; "wallet: empty path component at offset N"; "wallet: invalid
/// path character at offset N"; "wallet: leading zero in path component at
/// offset N"; "wallet: path component out of range at offset N"; "wallet:
/// derivation path depth exceeds 255".
pub fn derivation_path_parse(s: Str) -> Result[DerivationPath, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_path("wallet: empty derivation path");
  }
  let b0 = (string.byte_at(s, 0) as Int) & 0xFF;
  if b0 != 109 {
    // 109 = 'm'
    return _err_path("wallet: derivation path must start with m");
  }
  var components = Vec[Int].new();
  var hardened = Vec[Int].new();
  var i = 1;
  while i < n {
    let sep = (string.byte_at(s, i) as Int) & 0xFF;
    if sep != 47 {
      // 47 = '/'
      return _err_path("wallet: invalid path character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
    let comp_start = i;
    if i >= n {
      return _err_path("wallet: empty path component at offset " + convert.int_to_string(i));
    }
    let fb = (string.byte_at(s, i) as Int) & 0xFF;
    if !_is_digit(fb) {
      return _err_path("wallet: invalid path character at offset " + convert.int_to_string(i));
    }
    if fb == 48 {
      // 48 = '0': a lone zero, never a leading zero
      i = i + 1;
      if i < n {
        let nb = (string.byte_at(s, i) as Int) & 0xFF;
        if _is_digit(nb) {
          return _err_path("wallet: leading zero in path component at offset " + convert.int_to_string(comp_start));
        }
      }
    } else {
      while i < n {
        let db = (string.byte_at(s, i) as Int) & 0xFF;
        if !_is_digit(db) {
          break;
        }
        i = i + 1;
      }
    }
    var value = 0;
    var j = comp_start;
    while j < i {
      let db = (string.byte_at(s, j) as Int) & 0xFF;
      let d = db - 48;
      if value > (WALLET_MAX_COMPONENT - d) / 10 {
        return _err_path("wallet: path component out of range at offset " + convert.int_to_string(comp_start));
      }
      value = value * 10 + d;
      j = j + 1;
    }
    var hard = 0;
    if i < n {
      let mb = (string.byte_at(s, i) as Int) & 0xFF;
      if mb == 39 || mb == 104 || mb == 72 {
        // 39 = "'", 104 = 'h', 72 = 'H'
        hard = 1;
        i = i + 1;
      } elif mb == 47 {
        // 47 = '/': next component, not hardened
        hard = 0;
      } else {
        return _err_path("wallet: invalid path character at offset " + convert.int_to_string(i));
      }
    }
    if components.len() >= WALLET_MAX_PATH_DEPTH {
      return _err_path("wallet: derivation path depth exceeds " + convert.int_to_string(WALLET_MAX_PATH_DEPTH));
    }
    components.push(value);
    hardened.push(hard);
  }
  let p = DerivationPath{ depth: components.len(); components: components; hardened: hardened; };
  return _ok_path(p);
}

/// Canonical text of a path: "m" for depth 0, otherwise "m" followed by
/// "/<n>" or "/<n>'" per component. Round-trips through
/// derivation_path_parse.
pub fn derivation_path_format(p: &DerivationPath) -> Str {
  var out = "m";
  var i = 0;
  while i < p.depth {
    if i < p.components.len() && i < p.hardened.len() {
      let c: Int = p.components[i];
      out = out + "/" + convert.int_to_string(c);
      let h: Int = p.hardened[i];
      if h != 0 {
        out = out + "'";
      }
    }
    i = i + 1;
  }
  return out;
}

/// True when derivation_path_parse accepts `s`.
pub fn derivation_path_validate(s: Str) -> Bool {
  let r = derivation_path_parse(s);
  return r.is_ok;
}

/// Number of components (0 for "m").
pub fn derivation_path_depth(p: &DerivationPath) -> Int {
  return p.depth;
}

/// Raw component value at index `i` (0..2147483647); -1 when out of range.
pub fn derivation_path_component(p: &DerivationPath, i: Int) -> Int {
  if i < 0 || i >= p.depth || i >= p.components.len() {
    return -1;
  }
  let v: Int = p.components[i];
  return v;
}

/// True when component `i` carries a hardened marker; false when out of
/// range.
pub fn derivation_path_is_hardened(p: &DerivationPath, i: Int) -> Bool {
  if i < 0 || i >= p.depth || i >= p.hardened.len() {
    return false;
  }
  let v: Int = p.hardened[i];
  if v != 0 {
    return true;
  }
  return false;
}

/// Number of hardened components.
pub fn derivation_path_hardened_count(p: &DerivationPath) -> Int {
  var c = 0;
  var i = 0;
  while i < p.depth {
    if i < p.hardened.len() {
      let v: Int = p.hardened[i];
      if v != 0 {
        c = c + 1;
      }
    }
    i = i + 1;
  }
  return c;
}

/// Structural equality: same depth, values and hardened flags.
pub fn derivation_path_equal(a: &DerivationPath, b: &DerivationPath) -> Bool {
  if a.depth != b.depth {
    return false;
  }
  var i = 0;
  while i < a.depth {
    if i >= a.components.len() || i >= b.components.len() {
      return false;
    }
    if i >= a.hardened.len() || i >= b.hardened.len() {
      return false;
    }
    let x: Int = a.components[i];
    let y: Int = b.components[i];
    if x != y {
      return false;
    }
    let hx: Int = a.hardened[i];
    let hy: Int = b.hardened[i];
    if hx != hy {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Account book
// --------------------------------------------------

/// A labelled account book. labels and keys are parallel vectors; keys are
/// opaque xpub-style strings (never parsed or derived here).
pub type AccountBook = {
  count: Int;
  labels: Vec[Str];
  keys: Vec[Str];
}

/// An empty account book.
pub fn account_book_new() -> AccountBook {
  return AccountBook{ count: 0; labels: Vec[Str].new(); keys: Vec[Str].new(); };
}

/// Number of accounts.
pub fn account_book_count(b: &AccountBook) -> Int {
  return b.count;
}

/// Append an account and return its index. Labels must be unique. The key
/// is opaque; it only has to be non-empty, control-free and at most 128
/// bytes.
/// Errors: label / key validation errors ("wallet: empty label", "wallet:
/// label too long (max 64 bytes)", "wallet: label contains control
/// character at offset N", and the account-key equivalents) plus "wallet:
/// duplicate account label".
pub fn account_book_add(b: &mut AccountBook, label: Str, key: Str) -> Result[Int, Str] {
  let lv = _validate_text(label, "label", WALLET_MAX_LABEL_LEN);
  if !lv.is_ok {
    return _err_int(lv.error);
  }
  let kv = _validate_text(key, "account key", WALLET_MAX_KEY_LEN);
  if !kv.is_ok {
    return _err_int(kv.error);
  }
  if account_book_find(b, label) >= 0 {
    return _err_int("wallet: duplicate account label");
  }
  let idx = b.count;
  b.labels.push(label);
  b.keys.push(key);
  b.count = b.count + 1;
  return _ok_int(idx);
}

/// Index of the account labelled `label`; -1 when absent.
pub fn account_book_find(b: &AccountBook, label: Str) -> Int {
  var i = 0;
  while i < b.count {
    if i < b.labels.len() {
      let s: Str = b.labels[i];
      if str_compare(s, label) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Label of account `i`; "" when out of range.
pub fn account_book_label(b: &AccountBook, i: Int) -> Str {
  if i < 0 || i >= b.count || i >= b.labels.len() {
    return "";
  }
  let s: Str = b.labels[i];
  return s;
}

/// Opaque key of account `i`; "" when out of range.
pub fn account_book_key(b: &AccountBook, i: Int) -> Str {
  if i < 0 || i >= b.count || i >= b.keys.len() {
    return "";
  }
  let s: Str = b.keys[i];
  return s;
}

/// Replace the key of account `i` (validated like account_book_add) and
/// return the index.
/// Errors: "wallet: account index out of range" plus the account-key
/// validation errors.
pub fn account_book_set_key(b: &mut AccountBook, i: Int, key: Str) -> Result[Int, Str] {
  if i < 0 || i >= b.count || i >= b.keys.len() {
    return _err_int("wallet: account index out of range");
  }
  let kv = _validate_text(key, "account key", WALLET_MAX_KEY_LEN);
  if !kv.is_ok {
    return _err_int(kv.error);
  }
  var rebuilt = Vec[Str].new();
  var j = 0;
  while j < b.keys.len() {
    if j == i {
      rebuilt.push(key);
    } else {
      let old: Str = b.keys[j];
      rebuilt.push(old);
    }
    j = j + 1;
  }
  b.keys = rebuilt;
  return _ok_int(i);
}

/// Canonical account listing (see wallet_export for the format).
pub fn account_book_export(b: &AccountBook) -> Str {
  var out = "accounts\t" + convert.int_to_string(b.count) + "\n";
  var i = 0;
  while i < b.count {
    if i < b.labels.len() && i < b.keys.len() {
      let label: Str = b.labels[i];
      let key: Str = b.keys[i];
      out = out + "account\t" + convert.int_to_string(i) + "\t" + label + "\t" + key + "\n";
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Address book
// --------------------------------------------------

/// A labelled address book. labels and addresses are parallel vectors;
/// addresses are opaque caller strings that must be visible ASCII without
/// spaces.
pub type AddressBook = {
  count: Int;
  labels: Vec[Str];
  addresses: Vec[Str];
}

/// An empty address book.
pub fn address_book_new() -> AddressBook {
  return AddressBook{ count: 0; labels: Vec[Str].new(); addresses: Vec[Str].new(); };
}

/// Number of addresses.
pub fn address_book_count(b: &AddressBook) -> Int {
  return b.count;
}

/// Append an address and return its index. Labels and addresses must both
/// be unique. An address is structurally valid when it is non-empty, at
/// most 128 bytes and every byte is visible ASCII 0x21..0x7E (no control
/// characters, no spaces, no non-ASCII).
/// Errors: label validation errors, "wallet: empty address", "wallet:
/// address too long (max 128 bytes)", "wallet: address contains invalid
/// character at offset N", "wallet: duplicate address label", "wallet:
/// duplicate address".
pub fn address_book_add(b: &mut AddressBook, label: Str, address: Str) -> Result[Int, Str] {
  let lv = _validate_text(label, "label", WALLET_MAX_LABEL_LEN);
  if !lv.is_ok {
    return _err_int(lv.error);
  }
  let av = _validate_visible(address, "address", WALLET_MAX_ADDRESS_LEN);
  if !av.is_ok {
    return _err_int(av.error);
  }
  if address_book_find_label(b, label) >= 0 {
    return _err_int("wallet: duplicate address label");
  }
  if address_book_find_address(b, address) >= 0 {
    return _err_int("wallet: duplicate address");
  }
  let idx = b.count;
  b.labels.push(label);
  b.addresses.push(address);
  b.count = b.count + 1;
  return _ok_int(idx);
}

/// Index of the entry labelled `label`; -1 when absent.
pub fn address_book_find_label(b: &AddressBook, label: Str) -> Int {
  var i = 0;
  while i < b.count {
    if i < b.labels.len() {
      let s: Str = b.labels[i];
      if str_compare(s, label) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the entry holding exactly `address`; -1 when absent.
pub fn address_book_find_address(b: &AddressBook, address: Str) -> Int {
  var i = 0;
  while i < b.count {
    if i < b.addresses.len() {
      let s: Str = b.addresses[i];
      if str_compare(s, address) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Label of entry `i`; "" when out of range.
pub fn address_book_label(b: &AddressBook, i: Int) -> Str {
  if i < 0 || i >= b.count || i >= b.labels.len() {
    return "";
  }
  let s: Str = b.labels[i];
  return s;
}

/// Address of entry `i`; "" when out of range.
pub fn address_book_address(b: &AddressBook, i: Int) -> Str {
  if i < 0 || i >= b.count || i >= b.addresses.len() {
    return "";
  }
  let s: Str = b.addresses[i];
  return s;
}

/// Canonical address listing (see wallet_export for the format).
pub fn address_book_export(b: &AddressBook) -> Str {
  var out = "addresses\t" + convert.int_to_string(b.count) + "\n";
  var i = 0;
  while i < b.count {
    if i < b.labels.len() && i < b.addresses.len() {
      let label: Str = b.labels[i];
      let address: Str = b.addresses[i];
      out = out + "address\t" + convert.int_to_string(i) + "\t" + label + "\t" + address + "\n";
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Ledger
// --------------------------------------------------

/// An integer balance ledger with transfer intents.
///
/// Invariants (maintained by every mutating function): balance >= 0,
/// 0 <= reserved <= balance, available = balance - reserved, and seq is the
/// sequence number of the last posting (0 with no postings; each settled
/// balance change appends exactly one posting with sequence seq+1).
///
/// Postings are append-only parallel vectors. A credit posting has kind
/// POSTING_CREDIT, delta = +amount, fee 0 and an empty destination; a
/// settled transfer has kind POSTING_TRANSFER, delta = -(amount + fee) and
/// carries the intent id as its reference.
///
/// Intents reserve amount + fee from available funds at creation time. An
/// intent can settle once (execute moves the reserved total out of the
/// balance and appends a posting) or be cancelled (released, no posting);
/// executing or cancelling a settled intent, or creating a second intent
/// with the same id, is rejected (double-spend rejection).
pub type Ledger = {
  balance: Int;
  reserved: Int;
  seq: Int;
  posting_count: Int;
  posting_seq: Vec[Int];
  posting_kind: Vec[Int];
  posting_delta: Vec[Int];
  posting_amount: Vec[Int];
  posting_fee: Vec[Int];
  posting_ref: Vec[Str];
  posting_to: Vec[Str];
  intent_count: Int;
  intent_id: Vec[Str];
  intent_amount: Vec[Int];
  intent_fee: Vec[Int];
  intent_to: Vec[Str];
  intent_status: Vec[Int];
}

/// An empty ledger: zero balance, no postings, no intents.
pub fn ledger_new() -> Ledger {
  return Ledger{
    balance: 0;
    reserved: 0;
    seq: 0;
    posting_count: 0;
    posting_seq: Vec[Int].new();
    posting_kind: Vec[Int].new();
    posting_delta: Vec[Int].new();
    posting_amount: Vec[Int].new();
    posting_fee: Vec[Int].new();
    posting_ref: Vec[Str].new();
    posting_to: Vec[Str].new();
    intent_count: 0;
    intent_id: Vec[Str].new();
    intent_amount: Vec[Int].new();
    intent_fee: Vec[Int].new();
    intent_to: Vec[Str].new();
    intent_status: Vec[Int].new();
  };
}

/// Settled balance in minor units.
pub fn ledger_balance(l: &Ledger) -> Int {
  return l.balance;
}

/// Sum of amount + fee of every pending intent (reserved funds).
pub fn ledger_reserved(l: &Ledger) -> Int {
  return l.reserved;
}

/// Spendable funds: balance - reserved.
pub fn ledger_available(l: &Ledger) -> Int {
  return l.balance - l.reserved;
}

/// Sequence number of the last posting; 0 when there are none.
pub fn ledger_sequence(l: &Ledger) -> Int {
  return l.seq;
}

/// Number of postings.
pub fn ledger_posting_count(l: &Ledger) -> Int {
  return l.posting_count;
}

/// Sequence number of posting `i`; -1 when out of range.
pub fn ledger_posting_seq(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.posting_count || i >= l.posting_seq.len() {
    return -1;
  }
  let v: Int = l.posting_seq[i];
  return v;
}

/// Kind of posting `i` (POSTING_CREDIT or POSTING_TRANSFER); -1 when out
/// of range.
pub fn ledger_posting_kind(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.posting_count || i >= l.posting_kind.len() {
    return -1;
  }
  let v: Int = l.posting_kind[i];
  return v;
}

/// Signed balance change of posting `i`; 0 when out of range.
pub fn ledger_posting_delta(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.posting_count || i >= l.posting_delta.len() {
    return 0;
  }
  let v: Int = l.posting_delta[i];
  return v;
}

/// Gross amount of posting `i` (credit amount or transfer amount, fee
/// excluded); 0 when out of range.
pub fn ledger_posting_amount(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.posting_count || i >= l.posting_amount.len() {
    return 0;
  }
  let v: Int = l.posting_amount[i];
  return v;
}

/// Fee of posting `i` (0 for credits); 0 when out of range.
pub fn ledger_posting_fee(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.posting_count || i >= l.posting_fee.len() {
    return 0;
  }
  let v: Int = l.posting_fee[i];
  return v;
}

/// Reference (caller id) of posting `i`; "" when out of range.
pub fn ledger_posting_ref(l: &Ledger, i: Int) -> Str {
  if i < 0 || i >= l.posting_count || i >= l.posting_ref.len() {
    return "";
  }
  let s: Str = l.posting_ref[i];
  return s;
}

/// Transfer destination of posting `i` ("" for credits); "" when out of
/// range.
pub fn ledger_posting_to(l: &Ledger, i: Int) -> Str {
  if i < 0 || i >= l.posting_count || i >= l.posting_to.len() {
    return "";
  }
  let s: Str = l.posting_to[i];
  return s;
}

// Append one posting and mirror every parallel push (they never drift).
fn _posting_push(l: &mut Ledger, seq: Int, kind: Int, delta: Int, amount: Int, fee: Int, reference: Str, dst: Str) {
  l.posting_seq.push(seq);
  l.posting_kind.push(kind);
  l.posting_delta.push(delta);
  l.posting_amount.push(amount);
  l.posting_fee.push(fee);
  l.posting_ref.push(reference);
  l.posting_to.push(dst);
  l.posting_count = l.posting_count + 1;
}

// Append one intent row and mirror every parallel push.
fn _intent_push(l: &mut Ledger, id: Str, amount: Int, fee: Int, dst: Str, status: Int) {
  l.intent_id.push(id);
  l.intent_amount.push(amount);
  l.intent_fee.push(fee);
  l.intent_to.push(dst);
  l.intent_status.push(status);
  l.intent_count = l.intent_count + 1;
}

// Rebuild the status vector with row `idx` set to `status`. The element is
// never assigned in place (see the module header).
fn _intent_set_status(l: &mut Ledger, idx: Int, status: Int) {
  var rebuilt = Vec[Int].new();
  var j = 0;
  while j < l.intent_status.len() {
    if j == idx {
      rebuilt.push(status);
    } else {
      let old: Int = l.intent_status[j];
      rebuilt.push(old);
    }
    j = j + 1;
  }
  l.intent_status = rebuilt;
}

/// Credit the ledger with a positive amount and return the new balance.
/// Appends one POSTING_CREDIT posting with sequence seq+1.
/// Errors, in this order: "wallet: amount must be positive"; the reference
/// validation errors ("wallet: empty reference", "wallet: reference too
/// long (max 128 bytes)", "wallet: reference contains control character
/// at offset N"); "wallet: balance overflow" when balance + amount would
/// exceed 9223372036854775807.
pub fn ledger_credit(l: &mut Ledger, amount: Int, reference: Str) -> Result[Int, Str] {
  if amount <= 0 {
    return _err_int("wallet: amount must be positive");
  }
  let rv = _validate_text(reference, "reference", WALLET_MAX_REF_LEN);
  if !rv.is_ok {
    return _err_int(rv.error);
  }
  if amount > WALLET_INT64_MAX - l.balance {
    return _err_int("wallet: balance overflow");
  }
  l.balance = l.balance + amount;
  l.seq = l.seq + 1;
  _posting_push(l, l.seq, POSTING_CREDIT, amount, amount, 0, reference, "");
  return _ok_int(l.balance);
}

/// Create a pending transfer intent and return its index. Reserves
/// amount + fee from available funds immediately.
/// Errors, in this order: intent-id validation errors ("wallet: empty
/// intent id", "wallet: intent id too long (max 128 bytes)", "wallet:
/// intent id contains control character at offset N"); "wallet: amount
/// must be positive"; "wallet: negative fee"; "wallet: amount plus fee
/// overflows"; destination validation errors ("wallet: empty intent
/// destination", "wallet: intent destination too long (max 128 bytes)",
/// "wallet: intent destination contains invalid character at offset N");
/// "wallet: duplicate intent" (the id already exists with any status —
/// double-spend rejection); "wallet: insufficient funds" when amount + fee
/// exceeds available funds.
pub fn ledger_intent_create(l: &mut Ledger, id: Str, amount: Int, fee: Int, dst: Str) -> Result[Int, Str] {
  let iv = _validate_text(id, "intent id", WALLET_MAX_REF_LEN);
  if !iv.is_ok {
    return _err_int(iv.error);
  }
  if amount <= 0 {
    return _err_int("wallet: amount must be positive");
  }
  if fee < 0 {
    return _err_int("wallet: negative fee");
  }
  if amount > WALLET_INT64_MAX - fee {
    return _err_int("wallet: amount plus fee overflows");
  }
  let dv = _validate_visible(dst, "intent destination", WALLET_MAX_ADDRESS_LEN);
  if !dv.is_ok {
    return _err_int(dv.error);
  }
  if ledger_intent_index(l, id) >= 0 {
    return _err_int("wallet: duplicate intent");
  }
  let total = amount + fee;
  if total > l.balance - l.reserved {
    return _err_int("wallet: insufficient funds");
  }
  l.reserved = l.reserved + total;
  let idx = l.intent_count;
  _intent_push(l, id, amount, fee, dst, INTENT_PENDING);
  return _ok_int(idx);
}

/// Settle a pending intent: subtract amount + fee from the balance,
/// release the reservation, mark the intent executed and append one
/// POSTING_TRANSFER posting with sequence seq+1. Returns the new balance.
/// Errors: "wallet: unknown intent"; "wallet: intent already settled"
/// (executing twice is the double-spend rejection); "wallet: insufficient
/// funds" (defensive re-check).
pub fn ledger_intent_execute(l: &mut Ledger, id: Str) -> Result[Int, Str] {
  let idx = ledger_intent_index(l, id);
  if idx < 0 {
    return _err_int("wallet: unknown intent");
  }
  let st: Int = l.intent_status[idx];
  if st != INTENT_PENDING {
    return _err_int("wallet: intent already settled");
  }
  let amount: Int = l.intent_amount[idx];
  let fee: Int = l.intent_fee[idx];
  let dst: Str = l.intent_to[idx];
  let total = amount + fee;
  if total > l.balance {
    return _err_int("wallet: insufficient funds");
  }
  l.balance = l.balance - total;
  l.reserved = l.reserved - total;
  l.seq = l.seq + 1;
  _intent_set_status(l, idx, INTENT_EXECUTED);
  _posting_push(l, l.seq, POSTING_TRANSFER, 0 - total, amount, fee, id, dst);
  return _ok_int(l.balance);
}

/// Cancel a pending intent, releasing its reserved funds; no posting is
/// appended. Returns the intent index.
/// Errors: "wallet: unknown intent"; "wallet: intent already settled".
pub fn ledger_intent_cancel(l: &mut Ledger, id: Str) -> Result[Int, Str] {
  let idx = ledger_intent_index(l, id);
  if idx < 0 {
    return _err_int("wallet: unknown intent");
  }
  let st: Int = l.intent_status[idx];
  if st != INTENT_PENDING {
    return _err_int("wallet: intent already settled");
  }
  let amount: Int = l.intent_amount[idx];
  let fee: Int = l.intent_fee[idx];
  l.reserved = l.reserved - (amount + fee);
  _intent_set_status(l, idx, INTENT_CANCELLED);
  return _ok_int(idx);
}

/// Number of intents (every status).
pub fn ledger_intent_count(l: &Ledger) -> Int {
  return l.intent_count;
}

/// Index of the intent with id `id`; -1 when absent.
pub fn ledger_intent_index(l: &Ledger, id: Str) -> Int {
  var i = 0;
  while i < l.intent_count {
    if i < l.intent_id.len() {
      let s: Str = l.intent_id[i];
      if str_compare(s, id) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Id of intent `i`; "" when out of range.
pub fn ledger_intent_id(l: &Ledger, i: Int) -> Str {
  if i < 0 || i >= l.intent_count || i >= l.intent_id.len() {
    return "";
  }
  let s: Str = l.intent_id[i];
  return s;
}

/// Status of intent `i` (INTENT_PENDING / INTENT_EXECUTED /
/// INTENT_CANCELLED); -1 when out of range.
pub fn ledger_intent_status(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.intent_count || i >= l.intent_status.len() {
    return -1;
  }
  let v: Int = l.intent_status[i];
  return v;
}

/// Amount of intent `i`, fee excluded; 0 when out of range.
pub fn ledger_intent_amount(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.intent_count || i >= l.intent_amount.len() {
    return 0;
  }
  let v: Int = l.intent_amount[i];
  return v;
}

/// Fee of intent `i`; 0 when out of range.
pub fn ledger_intent_fee(l: &Ledger, i: Int) -> Int {
  if i < 0 || i >= l.intent_count || i >= l.intent_fee.len() {
    return 0;
  }
  let v: Int = l.intent_fee[i];
  return v;
}

/// Destination of intent `i`; "" when out of range.
pub fn ledger_intent_to(l: &Ledger, i: Int) -> Str {
  if i < 0 || i >= l.intent_count || i >= l.intent_to.len() {
    return "";
  }
  let s: Str = l.intent_to[i];
  return s;
}

/// Number of pending intents.
pub fn ledger_intent_pending_count(l: &Ledger) -> Int {
  var c = 0;
  var i = 0;
  while i < l.intent_count {
    if i < l.intent_status.len() {
      let v: Int = l.intent_status[i];
      if v == INTENT_PENDING {
        c = c + 1;
      }
    }
    i = i + 1;
  }
  return c;
}

// "credit" / "transfer" for a posting kind; "unknown" otherwise.
fn _posting_kind_name(kind: Int) -> Str {
  if kind == POSTING_CREDIT {
    return "credit";
  }
  if kind == POSTING_TRANSFER {
    return "transfer";
  }
  return "unknown";
}

// "pending" / "executed" / "cancelled" for an intent status; "unknown"
// otherwise.
fn _intent_status_name(status: Int) -> Str {
  if status == INTENT_PENDING {
    return "pending";
  }
  if status == INTENT_EXECUTED {
    return "executed";
  }
  if status == INTENT_CANCELLED {
    return "cancelled";
  }
  return "unknown";
}

/// Canonical ledger listing:
///   ledger\t<balance>\t<reserved>\t<sequence>\t<pending>\n
///   postings\t<n>\n
///   posting\t<seq>\t<credit|transfer>\t<delta>\t<amount>\t<fee>\t<ref>\t<to>\n
///   intents\t<m>\n
///   intent\t<id>\t<pending|executed|cancelled>\t<amount>\t<fee>\t<to>\n
/// One line per record, tab-separated, trailing newline after every line.
pub fn ledger_export(l: &Ledger) -> Str {
  let pending = ledger_intent_pending_count(l);
  var out = "ledger\t" + convert.int_to_string(l.balance) + "\t" + convert.int_to_string(l.reserved) + "\t" + convert.int_to_string(l.seq) + "\t" + convert.int_to_string(pending) + "\n";
  out = out + "postings\t" + convert.int_to_string(l.posting_count) + "\n";
  var i = 0;
  while i < l.posting_count {
    if i < l.posting_seq.len() && i < l.posting_kind.len() && i < l.posting_delta.len() && i < l.posting_amount.len() && i < l.posting_fee.len() && i < l.posting_ref.len() && i < l.posting_to.len() {
      let sq: Int = l.posting_seq[i];
      let kd: Int = l.posting_kind[i];
      let dl: Int = l.posting_delta[i];
      let am: Int = l.posting_amount[i];
      let fe: Int = l.posting_fee[i];
      let rf: Str = l.posting_ref[i];
      let dst: Str = l.posting_to[i];
      out = out + "posting\t" + convert.int_to_string(sq) + "\t" + _posting_kind_name(kd) + "\t" + convert.int_to_string(dl) + "\t" + convert.int_to_string(am) + "\t" + convert.int_to_string(fe) + "\t" + rf + "\t" + dst + "\n";
    }
    i = i + 1;
  }
  out = out + "intents\t" + convert.int_to_string(l.intent_count) + "\n";
  i = 0;
  while i < l.intent_count {
    if i < l.intent_id.len() && i < l.intent_status.len() && i < l.intent_amount.len() && i < l.intent_fee.len() && i < l.intent_to.len() {
      let id: Str = l.intent_id[i];
      let st: Int = l.intent_status[i];
      let am: Int = l.intent_amount[i];
      let fe: Int = l.intent_fee[i];
      let dst: Str = l.intent_to[i];
      out = out + "intent\t" + id + "\t" + _intent_status_name(st) + "\t" + convert.int_to_string(am) + "\t" + convert.int_to_string(fe) + "\t" + dst + "\n";
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Wallet (name + account book + address book + ledger)
// --------------------------------------------------

/// A named wallet aggregate: metadata only, no key material of its own.
pub type Wallet = {
  name: Str;
  accounts: AccountBook;
  addresses: AddressBook;
  ledger: Ledger;
}

/// A wallet with an empty account book, address book and ledger. The name
/// is validated by wallet_export and wallet_new_checked, not here.
pub fn wallet_new(name: Str) -> Wallet {
  return Wallet{
    name: name;
    accounts: account_book_new();
    addresses: address_book_new();
    ledger: ledger_new();
  };
}

/// Validated wallet constructor: the wallet-name validation errors for an
/// invalid `name`, otherwise Ok(wallet) (same as wallet_new).
pub fn wallet_new_checked(name: Str) -> Result[Wallet, Str] {
  let nv = _validate_text(name, "wallet name", WALLET_MAX_LABEL_LEN);
  if !nv.is_ok {
    return _err_wallet(nv.error);
  }
  let w = wallet_new(name);
  return _ok_wallet(w);
}

/// Wallet name.
pub fn wallet_name(w: &Wallet) -> Str {
  let s: Str = w.name;
  return s;
}

/// Canonical wallet listing. The name must be a valid label (non-empty,
/// control-free, at most 64 bytes); the books and the ledger are rendered
/// even when empty:
///   wallet\t1\t<name>\n
///   <account_book_export>
///   <address_book_export>
///   <ledger_export>
/// The "1" is the listing format version. Errors: the wallet-name
/// validation errors ("wallet: empty wallet name", "wallet: wallet name
/// too long (max 64 bytes)", "wallet: wallet name contains control
/// character at offset N").
pub fn wallet_export(w: &Wallet) -> Result[Str, Str] {
  let nv = _validate_text(w.name, "wallet name", WALLET_MAX_LABEL_LEN);
  if !nv.is_ok {
    return _err_str(nv.error);
  }
  let ab: AccountBook = w.accounts;
  let rb: AddressBook = w.addresses;
  let lg: Ledger = w.ledger;
  var out = "wallet\t1\t" + w.name + "\n";
  out = out + account_book_export(&ab);
  out = out + address_book_export(&rb);
  out = out + ledger_export(&lg);
  return _ok_str(out);
}
