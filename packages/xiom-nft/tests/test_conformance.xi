// XIOM -- xiom.nft conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven deterministic tests, one direct call per check (no fn
// tables, no indexed dispatch). Coverage: empty-registry defaults,
// collection registration and validation, minting (accessors, duplicate
// rejection, error order), owner transfers, per-token approvals and expiry,
// operator grants/revocation with expiry, burn and supply accounting,
// unauthorized transfer/burn rejection, royalty split arithmetic (exact
// bps, truncation, overflow-free maximum Int), owner and collection
// enumeration, the canonical event log, invariant detection on tampered
// registries, canonical export, the permissions matrix, and a full
// lifecycle fixture.
//
// All Str equality goes through str_compare (BUG-17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison).

module nft_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.nft;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

fn int_err(r: Result[Int, Str]) -> Str {
  if r.is_ok {
    return "(ok)";
  }
  return r.error;
}

// Empty registry plus two collections: 0 = "nft-dao" (creator "dao",
// 500 bps), 1 = "art" (creator "artist", 250 bps).
fn fixture_registry() -> NftRegistry {
  var reg = nft_registry_new();
  let c0 = nft_collection_add(&mut reg, "nft-dao", "dao", 500);
  let c1 = nft_collection_add(&mut reg, "art", "artist", 250);
  if !c0.is_ok || !c1.is_ok {
    return nft_registry_new();
  }
  return reg;
}

// fixture_registry plus three mints:
//   1001 -> alice (collection 0, tick 10)
//   1002 -> bob   (collection 0, tick 11)
//   2001 -> alice (collection 1, tick 12)
fn fixture_three() -> NftRegistry {
  var reg = fixture_registry();
  let m0 = nft_mint(&mut reg, 0, 1001, "alice", 10);
  let m1 = nft_mint(&mut reg, 0, 1002, "bob", 11);
  let m2 = nft_mint(&mut reg, 1, 2001, "alice", 12);
  if !m0.is_ok || !m1.is_ok || !m2.is_ok {
    return nft_registry_new();
  }
  return reg;
}

// Tampered registry: two token rows share token id 5 (duplicate ownership
// key); all parallel vectors are consistent so only the id and supply
// invariants fail.
fn tampered_duplicate_ids() -> NftRegistry {
  var bad = nft_registry_new();
  let c = nft_collection_add(&mut bad, "c", "x", 100);
  if !c.is_ok {
    return bad;
  }
  bad.token_id.push(5);
  bad.token_id.push(5);
  bad.token_collection.push(0);
  bad.token_collection.push(0);
  bad.token_owner_text.push(0);
  bad.token_owner_text.push(1);
  bad.token_minted_tick.push(1);
  bad.token_minted_tick.push(1);
  bad.token_burn_tick.push(-1);
  bad.token_burn_tick.push(-1);
  bad.token_status.push(0);
  bad.token_status.push(0);
  bad.token_count = 2;
  return bad;
}

// Tampered registry: one live token but its collection recorded live count
// was zeroed, so supply accounting fails while ids stay unique.
fn tampered_supply() -> NftRegistry {
  var bad = nft_registry_new();
  let c = nft_collection_add(&mut bad, "c", "x", 100);
  if !c.is_ok {
    return bad;
  }
  let m = nft_mint(&mut bad, 0, 5, "alice", 1);
  if !m.is_ok {
    return bad;
  }
  var rebuilt = Vec[Int].new();
  var i = 0;
  while i < bad.coll_live.len() {
    rebuilt.push(0);
    i = i + 1;
  }
  bad.coll_live = rebuilt;
  return bad;
}

// Tampered registry: the second event carries sequence number 99 instead of
// 2; all parallel vectors are consistent.
fn tampered_event_seq() -> NftRegistry {
  var bad = nft_registry_new();
  let c = nft_collection_add(&mut bad, "c", "x", 100);
  if !c.is_ok {
    return bad;
  }
  let m = nft_mint(&mut bad, 0, 5, "alice", 1);
  if !m.is_ok {
    return bad;
  }
  bad.event_seq.push(99);
  bad.event_kind.push(1);
  bad.event_token_id.push(5);
  bad.event_collection.push(0);
  bad.event_actor_text.push(0);
  bad.event_to_text.push(0);
  bad.event_tick.push(2);
  bad.event_count = 2;
  return bad;
}

// --------------------------------------------------
//  t1: empty registry defaults and invariants
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let reg = nft_registry_new();
  if nft_collection_count(&reg) != 0 { ok = false; }
  if nft_token_count(&reg) != 0 { ok = false; }
  if nft_live_supply(&reg) != 0 { ok = false; }
  if nft_burned_supply(&reg) != 0 { ok = false; }
  if nft_approval_count(&reg) != 0 { ok = false; }
  if nft_operator_count(&reg) != 0 { ok = false; }
  if nft_event_count(&reg) != 0 { ok = false; }
  if !streq(nft_collection_name(&reg, 0), "") { ok = false; }
  if !streq(nft_collection_creator(&reg, -1), "") { ok = false; }
  if nft_collection_royalty_bps(&reg, 0) != -1 { ok = false; }
  if nft_collection_live_count(&reg, 0) != -1 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != -1 { ok = false; }
  if nft_collection_find(&reg, "nope") != -1 { ok = false; }
  if nft_token_row(&reg, 1) != -1 { ok = false; }
  if nft_token_exists(&reg, 1) { ok = false; }
  if nft_token_is_live(&reg, 1) { ok = false; }
  if !streq(nft_token_owner(&reg, 1), "") { ok = false; }
  if nft_token_collection(&reg, 1) != -1 { ok = false; }
  if nft_token_minted_tick(&reg, 1) != -1 { ok = false; }
  if nft_token_burn_tick(&reg, 1) != -1 { ok = false; }
  if nft_token_approval_count(&reg, 1) != -1 { ok = false; }
  if nft_owner_token_count(&reg, "alice") != 0 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 0) != -1 { ok = false; }
  if nft_collection_token_at(&reg, 0, 0) != -1 { ok = false; }
  if nft_event_seq(&reg, 0) != 0 { ok = false; }
  if nft_event_kind(&reg, 0) != -1 { ok = false; }
  if !streq(nft_event_kind_name(-1), "unknown") { ok = false; }
  if nft_event_token_id(&reg, 0) != -1 { ok = false; }
  if nft_event_collection(&reg, 0) != -1 { ok = false; }
  if !streq(nft_event_actor(&reg, 0), "") { ok = false; }
  if !streq(nft_event_to(&reg, 0), "") { ok = false; }
  if nft_event_tick(&reg, 0) != -1 { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, 100) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 0, 100) != 0 { ok = false; }
  if !streq(nft_royalty_split_text(&reg, 0, 100), "") { ok = false; }
  if !nft_token_ids_unique(&reg) { ok = false; }
  if !nft_supply_balanced(&reg) { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  let want = "nft-registry\t1\ncollections\t0\ntokens\t0\napprovals\t0\noperators\t0\nevents\t0\n";
  if !streq(nft_registry_export(&reg), want) { ok = false; }
  return assert(ok, "empty registry counts, defaults and invariants");
}

// --------------------------------------------------
//  t2: collection add, accessors, validation and boundaries
// --------------------------------------------------

fn t2() -> TestResult {
  var ok = true;
  var reg = nft_registry_new();
  let c0 = nft_collection_add(&mut reg, "nft-dao", "dao", 500);
  if !c0.is_ok {
    ok = false;
  } else {
    let i0: Int = c0.value;
    if i0 != 0 { ok = false; }
  }
  let c1 = nft_collection_add(&mut reg, "art", "artist", 250);
  if !c1.is_ok {
    ok = false;
  } else {
    let i1: Int = c1.value;
    if i1 != 1 { ok = false; }
  }
  let c2 = nft_collection_add(&mut reg, "zero", "z", 0);
  if !c2.is_ok { ok = false; }
  let c3 = nft_collection_add(&mut reg, "full", "f", 10000);
  if !c3.is_ok { ok = false; }
  let long_name = string.str_repeat("a", 64);
  let long_creator = string.str_repeat("b", 128);
  let c4 = nft_collection_add(&mut reg, long_name, long_creator, 1);
  if !c4.is_ok { ok = false; }
  if nft_collection_count(&reg) != 5 { ok = false; }
  if nft_collection_find(&reg, "art") != 1 { ok = false; }
  if nft_collection_find(&reg, "nft-dao") != 0 { ok = false; }
  if nft_collection_find(&reg, "nope") != -1 { ok = false; }
  if !streq(nft_collection_name(&reg, 0), "nft-dao") { ok = false; }
  if !streq(nft_collection_creator(&reg, 1), "artist") { ok = false; }
  if nft_collection_royalty_bps(&reg, 0) != 500 { ok = false; }
  if nft_collection_royalty_bps(&reg, 1) != 250 { ok = false; }
  if nft_collection_royalty_bps(&reg, 2) != 0 { ok = false; }
  if nft_collection_royalty_bps(&reg, 3) != 10000 { ok = false; }
  if nft_collection_royalty_bps(&reg, 4) != 1 { ok = false; }
  if nft_collection_live_count(&reg, 0) != 0 { ok = false; }
  if nft_collection_minted_count(&reg, 1) != 0 { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "", "c", 0)), "nft: empty collection name") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, string.str_repeat("a", 65), "c", 0)), "nft: collection name too long (max 64 bytes)") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "bad\nname", "c", 0)), "nft: collection name contains control character at offset 3") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "ok", "", 0)), "nft: empty creator") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "ok", string.str_repeat("b", 129), 0)), "nft: creator too long (max 128 bytes)") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "ok", "a\tb", 0)), "nft: creator contains control character at offset 1") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "ok", "c", -1)), "nft: royalty basis points out of range (0..10000)") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "ok", "c", 10001)), "nft: royalty basis points out of range (0..10000)") { ok = false; }
  if !streq(int_err(nft_collection_add(&mut reg, "nft-dao", "c", 0)), "nft: duplicate collection name") { ok = false; }
  if nft_collection_count(&reg) != 5 { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "collection add, accessors, validation and boundaries");
}

// --------------------------------------------------
//  t3: mint happy path and first event
// --------------------------------------------------

fn t3() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let m = nft_mint(&mut reg, 0, 1001, "alice", 10);
  if !m.is_ok {
    ok = false;
  } else {
    let row: Int = m.value;
    if row != 0 { ok = false; }
  }
  if nft_token_count(&reg) != 1 { ok = false; }
  if nft_live_supply(&reg) != 1 { ok = false; }
  if nft_burned_supply(&reg) != 0 { ok = false; }
  if nft_token_row(&reg, 1001) != 0 { ok = false; }
  if !nft_token_exists(&reg, 1001) { ok = false; }
  if !nft_token_is_live(&reg, 1001) { ok = false; }
  if !streq(nft_token_owner(&reg, 1001), "alice") { ok = false; }
  if nft_token_collection(&reg, 1001) != 0 { ok = false; }
  if nft_token_minted_tick(&reg, 1001) != 10 { ok = false; }
  if nft_token_burn_tick(&reg, 1001) != -1 { ok = false; }
  if nft_collection_live_count(&reg, 0) != 1 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != 1 { ok = false; }
  if nft_collection_live_count(&reg, 1) != 0 { ok = false; }
  if nft_event_count(&reg) != 1 { ok = false; }
  if nft_event_seq(&reg, 0) != 1 { ok = false; }
  if nft_event_kind(&reg, 0) != NFT_EVENT_MINT { ok = false; }
  if !streq(nft_event_kind_name(nft_event_kind(&reg, 0)), "mint") { ok = false; }
  if nft_event_token_id(&reg, 0) != 1001 { ok = false; }
  if nft_event_collection(&reg, 0) != 0 { ok = false; }
  if !streq(nft_event_actor(&reg, 0), "alice") { ok = false; }
  if !streq(nft_event_to(&reg, 0), "alice") { ok = false; }
  if nft_event_tick(&reg, 0) != 10 { ok = false; }
  if !nft_token_ids_unique(&reg) { ok = false; }
  if !nft_supply_balanced(&reg) { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "mint records token, supply and MINT event");
}

// --------------------------------------------------
//  t4: mint error order and state preservation
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let good = nft_mint(&mut reg, 0, 1001, "alice", 10);
  if !good.is_ok { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, -1, 1002, "alice", 10)), "nft: unknown collection") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 99, 1002, "alice", 10)), "nft: unknown collection") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 0, "alice", 10)), "nft: token id must be positive") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, -7, "alice", 10)), "nft: token id must be positive") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 1002, "", 10)), "nft: empty owner") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 1002, "bad\nowner", 10)), "nft: owner contains control character at offset 3") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 1002, string.str_repeat("o", 129), 10)), "nft: owner too long (max 128 bytes)") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 1002, "alice", -1)), "nft: negative tick") { ok = false; }
  if !streq(int_err(nft_mint(&mut reg, 0, 1001, "bob", 11)), "nft: duplicate token id") { ok = false; }
  if nft_token_count(&reg) != 1 { ok = false; }
  if nft_live_supply(&reg) != 1 { ok = false; }
  if nft_event_count(&reg) != 1 { ok = false; }
  if nft_collection_live_count(&reg, 0) != 1 { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "mint rejects bad collection, id, owner and tick in order");
}

// --------------------------------------------------
//  t5: transfer by the current owner
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let x = nft_transfer(&mut reg, 1001, "alice", "carol", 20);
  if !x.is_ok {
    ok = false;
  } else {
    let seq: Int = x.value;
    if seq != 4 { ok = false; }
  }
  if !streq(nft_token_owner(&reg, 1001), "carol") { ok = false; }
  if !nft_token_is_live(&reg, 1001) { ok = false; }
  if nft_owner_token_count(&reg, "alice") != 1 { ok = false; }
  if nft_owner_token_count(&reg, "carol") != 1 { ok = false; }
  if nft_owner_token_at(&reg, "carol", 0) != 1001 { ok = false; }
  if nft_live_supply(&reg) != 3 { ok = false; }
  if nft_event_count(&reg) != 4 { ok = false; }
  if nft_event_seq(&reg, 3) != 4 { ok = false; }
  if nft_event_kind(&reg, 3) != NFT_EVENT_TRANSFER { ok = false; }
  if !streq(nft_event_kind_name(nft_event_kind(&reg, 3)), "transfer") { ok = false; }
  if nft_event_token_id(&reg, 3) != 1001 { ok = false; }
  if nft_event_collection(&reg, 3) != 0 { ok = false; }
  if !streq(nft_event_actor(&reg, 3), "alice") { ok = false; }
  if !streq(nft_event_to(&reg, 3), "carol") { ok = false; }
  if nft_event_tick(&reg, 3) != 20 { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "owner transfer moves ownership and logs TRANSFER");
}

// --------------------------------------------------
//  t6: transfer rejection order and state preservation
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  if !streq(int_err(nft_transfer(&mut reg, 9999, "alice", "bob", 20)), "nft: unknown token") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "", "bob", 20)), "nft: empty sender") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, string.str_repeat("s", 129), "bob", 20)), "nft: sender too long (max 128 bytes)") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", "", 20)), "nft: empty recipient") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", "has\nnl", 20)), "nft: recipient contains control character at offset 3") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", string.str_repeat("r", 129), 20)), "nft: recipient too long (max 128 bytes)") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", "carol", -1)), "nft: negative tick") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "mallory", "carol", 20)), "nft: sender not authorized") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", "alice", 20)), "nft: transfer to current owner") { ok = false; }
  if !streq(nft_token_owner(&reg, 1001), "alice") { ok = false; }
  if nft_event_count(&reg) != 3 { ok = false; }
  let b = nft_burn(&mut reg, 1002, "bob", 30);
  if !b.is_ok { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1002, "bob", "carol", 31)), "nft: token is burned") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "transfer rejects unknown, bad ids, unauthorized and self");
}

// --------------------------------------------------
//  t7: per-token approval authorizes the spender
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let a = nft_approve(&mut reg, 1001, "alice", "carol", 13, 100);
  if !a.is_ok {
    ok = false;
  } else {
    let idx: Int = a.value;
    if idx != 0 { ok = false; }
  }
  if nft_approval_count(&reg) != 1 { ok = false; }
  if nft_token_approval_count(&reg, 1001) != 1 { ok = false; }
  if nft_token_approval_count(&reg, 9999) != -1 { ok = false; }
  if nft_approval_token_id(&reg, 0) != 1001 { ok = false; }
  if !streq(nft_approval_owner(&reg, 0), "alice") { ok = false; }
  if !streq(nft_approval_spender(&reg, 0), "carol") { ok = false; }
  if nft_approval_expiry(&reg, 0) != 100 { ok = false; }
  if !nft_approval_is_valid(&reg, 0, 50) { ok = false; }
  if !nft_approval_is_valid(&reg, 0, 100) { ok = false; }
  if nft_approval_is_valid(&reg, 0, 101) { ok = false; }
  if !nft_approval_valid_for(&reg, 1001, "carol", 50) { ok = false; }
  if nft_approval_valid_for(&reg, 1001, "carol", 101) { ok = false; }
  if nft_approval_valid_for(&reg, 1002, "carol", 50) { ok = false; }
  if nft_event_count(&reg) != 4 { ok = false; }
  if nft_event_kind(&reg, 3) != NFT_EVENT_APPROVE { ok = false; }
  if !streq(nft_event_actor(&reg, 3), "alice") { ok = false; }
  if !streq(nft_event_to(&reg, 3), "carol") { ok = false; }
  if nft_event_tick(&reg, 3) != 13 { ok = false; }
  let x = nft_transfer(&mut reg, 1001, "carol", "dave", 50);
  if !x.is_ok {
    ok = false;
  } else {
    let seq: Int = x.value;
    if seq != 5 { ok = false; }
  }
  if !streq(nft_token_owner(&reg, 1001), "dave") { ok = false; }
  if nft_approval_valid_for(&reg, 1001, "carol", 50) { ok = false; }
  if nft_approval_is_valid(&reg, 0, 50) { ok = false; }
  let y = nft_transfer(&mut reg, 1001, "dave", "carol", 60);
  if !y.is_ok { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "carol", "carol", 61)), "nft: transfer to current owner") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "approval authorizes one spender then invalidates on transfer");
}

// --------------------------------------------------
//  t8: approval expiry boundary and re-approval
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let a0 = nft_approve(&mut reg, 1001, "alice", "carol", 13, 30);
  if !a0.is_ok { ok = false; }
  if !nft_approval_valid_for(&reg, 1001, "carol", 30) { ok = false; }
  if nft_approval_valid_for(&reg, 1001, "carol", 31) { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "carol", "dave", 31)), "nft: sender not authorized") { ok = false; }
  let a1 = nft_approve(&mut reg, 1001, "alice", "carol", 40, 50);
  if !a1.is_ok {
    ok = false;
  } else {
    let idx: Int = a1.value;
    if idx != 1 { ok = false; }
  }
  if nft_approval_is_valid(&reg, 0, 31) { ok = false; }
  if !nft_approval_is_valid(&reg, 1, 31) { ok = false; }
  if !nft_approval_valid_for(&reg, 1001, "carol", 31) { ok = false; }
  let x = nft_transfer(&mut reg, 1001, "carol", "dave", 45);
  if !x.is_ok { ok = false; }
  if !streq(nft_token_owner(&reg, 1001), "dave") { ok = false; }
  if nft_approval_count(&reg) != 2 { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "expiry is inclusive; re-approval supersedes the old row");
}

// --------------------------------------------------
//  t9: operators, expiry and revocation
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let s0 = nft_set_operator(&mut reg, "alice", "op", 40);
  if !s0.is_ok {
    ok = false;
  } else {
    let idx: Int = s0.value;
    if idx != 0 { ok = false; }
  }
  if nft_operator_count(&reg) != 1 { ok = false; }
  if !streq(nft_operator_owner(&reg, 0), "alice") { ok = false; }
  if !streq(nft_operator_operator(&reg, 0), "op") { ok = false; }
  if nft_operator_expiry(&reg, 0) != 40 { ok = false; }
  if !nft_is_operator(&reg, "alice", "op", 40) { ok = false; }
  if nft_is_operator(&reg, "alice", "op", 41) { ok = false; }
  if nft_is_operator(&reg, "bob", "op", 40) { ok = false; }
  if nft_is_operator(&reg, "alice", "op2", 40) { ok = false; }
  if !nft_operator_is_valid(&reg, 0, 40) { ok = false; }
  if nft_operator_is_valid(&reg, 0, 41) { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1002, "op", "dave", 30)), "nft: sender not authorized") { ok = false; }
  let x = nft_transfer(&mut reg, 1001, "op", "dave", 30);
  if !x.is_ok {
    ok = false;
  } else {
    let seq: Int = x.value;
    if seq != 4 { ok = false; }
  }
  if !streq(nft_token_owner(&reg, 1001), "dave") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "op", "erin", 35)), "nft: sender not authorized") { ok = false; }
  let rv = nft_operator_revoke(&mut reg, "alice", "op", 35);
  if !rv.is_ok {
    ok = false;
  } else {
    let idx: Int = rv.value;
    if idx != 1 { ok = false; }
  }
  if nft_operator_expiry(&reg, 1) != 34 { ok = false; }
  if !nft_is_operator(&reg, "alice", "op", 34) { ok = false; }
  if nft_is_operator(&reg, "alice", "op", 35) { ok = false; }
  if nft_operator_is_valid(&reg, 0, 34) { ok = false; }
  if !nft_operator_is_valid(&reg, 1, 34) { ok = false; }
  if nft_operator_is_valid(&reg, 1, 35) { ok = false; }
  if !streq(int_err(nft_operator_revoke(&mut reg, "alice", "op", 35)), "nft: operator already revoked") { ok = false; }
  if !streq(int_err(nft_operator_revoke(&mut reg, "alice", "nobody", 35)), "nft: unknown operator") { ok = false; }
  if !streq(int_err(nft_set_operator(&mut reg, "alice", "op", -1)), "nft: negative expiry") { ok = false; }
  if !streq(int_err(nft_set_operator(&mut reg, "", "op", 10)), "nft: empty owner") { ok = false; }
  if !streq(int_err(nft_set_operator(&mut reg, "alice", "", 10)), "nft: empty operator") { ok = false; }
  if !streq(int_err(nft_operator_revoke(&mut reg, "alice", "op", -1)), "nft: negative tick") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "operator grants, expiry boundary and revocation");
}

// --------------------------------------------------
//  t10: burn by the owner and supply accounting
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let b = nft_burn(&mut reg, 1002, "bob", 30);
  if !b.is_ok {
    ok = false;
  } else {
    let seq: Int = b.value;
    if seq != 4 { ok = false; }
  }
  if !nft_token_exists(&reg, 1002) { ok = false; }
  if nft_token_is_live(&reg, 1002) { ok = false; }
  if !streq(nft_token_owner(&reg, 1002), "bob") { ok = false; }
  if nft_token_burn_tick(&reg, 1002) != 30 { ok = false; }
  if nft_token_minted_tick(&reg, 1002) != 11 { ok = false; }
  if nft_token_count(&reg) != 3 { ok = false; }
  if nft_live_supply(&reg) != 2 { ok = false; }
  if nft_burned_supply(&reg) != 1 { ok = false; }
  if nft_owner_token_count(&reg, "bob") != 0 { ok = false; }
  if nft_collection_live_count(&reg, 0) != 1 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != 2 { ok = false; }
  if nft_collection_token_at(&reg, 0, 0) != 1001 { ok = false; }
  if nft_collection_token_at(&reg, 0, 1) != -1 { ok = false; }
  if nft_event_count(&reg) != 4 { ok = false; }
  if nft_event_kind(&reg, 3) != NFT_EVENT_BURN { ok = false; }
  if !streq(nft_event_kind_name(nft_event_kind(&reg, 3)), "burn") { ok = false; }
  if nft_event_token_id(&reg, 3) != 1002 { ok = false; }
  if !streq(nft_event_actor(&reg, 3), "bob") { ok = false; }
  if !streq(nft_event_to(&reg, 3), "bob") { ok = false; }
  if nft_event_tick(&reg, 3) != 30 { ok = false; }
  if !streq(int_err(nft_burn(&mut reg, 1002, "bob", 31)), "nft: token is burned") { ok = false; }
  if !nft_token_ids_unique(&reg) { ok = false; }
  if !nft_supply_balanced(&reg) { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "burn marks the token, drops supply and logs BURN");
}

// --------------------------------------------------
//  t11: burn authorization via approval and operator
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let a = nft_approve(&mut reg, 1001, "alice", "carol", 20, 60);
  if !a.is_ok { ok = false; }
  let b1 = nft_burn(&mut reg, 1001, "carol", 30);
  if !b1.is_ok { ok = false; }
  if nft_token_is_live(&reg, 1001) { ok = false; }
  let s = nft_set_operator(&mut reg, "bob", "op", 50);
  if !s.is_ok { ok = false; }
  let b2 = nft_burn(&mut reg, 1002, "op", 40);
  if !b2.is_ok { ok = false; }
  if nft_live_supply(&reg) != 1 { ok = false; }
  if nft_burned_supply(&reg) != 2 { ok = false; }
  if !streq(int_err(nft_burn(&mut reg, 2001, "mallory", 40)), "nft: burner not authorized") { ok = false; }
  if !streq(int_err(nft_burn(&mut reg, 2001, "", 40)), "nft: empty burner") { ok = false; }
  if !streq(int_err(nft_burn(&mut reg, 9999, "alice", 40)), "nft: unknown token") { ok = false; }
  if !streq(int_err(nft_burn(&mut reg, 2001, "alice", -1)), "nft: negative tick") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "approval and operator authorize burn, others are rejected");
}

// --------------------------------------------------
//  t12: royalty split arithmetic and truncation
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  if nft_collection_royalty_bps(&reg, 0) != 500 { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, 10000) != 500 { ok = false; }
  if nft_royalty_seller_amount(&reg, 0, 10000) != 9500 { ok = false; }
  if nft_royalty_creator_amount(&reg, 1, 1000) != 25 { ok = false; }
  if nft_royalty_seller_amount(&reg, 1, 1000) != 975 { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, 7) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 0, 7) != 7 { ok = false; }
  if nft_royalty_creator_amount(&reg, 1, 3) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 1, 3) != 3 { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, 199) != 9 { ok = false; }
  if nft_royalty_seller_amount(&reg, 0, 199) != 190 { ok = false; }
  let z = nft_collection_add(&mut reg, "zero", "z", 0);
  if !z.is_ok { ok = false; }
  let f = nft_collection_add(&mut reg, "full", "f", 10000);
  if !f.is_ok { ok = false; }
  if nft_royalty_creator_amount(&reg, 2, 12345) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 2, 12345) != 12345 { ok = false; }
  if nft_royalty_creator_amount(&reg, 3, 12345) != 12345 { ok = false; }
  if nft_royalty_seller_amount(&reg, 3, 12345) != 0 { ok = false; }
  if !streq(nft_royalty_split_text(&reg, 0, 10000), "creator\t500\tseller\t9500") { ok = false; }
  if !streq(nft_royalty_split_text(&reg, 1, 1234), "creator\t30\tseller\t1204") { ok = false; }
  if nft_royalty_creator_amount(&reg, 9, 100) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 9, 100) != 0 { ok = false; }
  if !streq(nft_royalty_split_text(&reg, 9, 100), "") { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, 0) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 0, 0) != 0 { ok = false; }
  if !streq(nft_royalty_split_text(&reg, 0, 0), "") { ok = false; }
  if nft_royalty_creator_amount(&reg, 0, -5) != 0 { ok = false; }
  if nft_royalty_creator_amount(&reg, -1, 100) != 0 { ok = false; }
  return assert(ok, "royalty bps split truncates toward zero and sums exactly");
}

// --------------------------------------------------
//  t13: royalty split at the maximum Int (overflow-free)
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let max = 9223372036854775807;
  let c0 = nft_royalty_creator_amount(&reg, 0, max);
  let s0 = nft_royalty_seller_amount(&reg, 0, max);
  if c0 != 461168601842738790 { ok = false; }
  if s0 != 8762203435012037017 { ok = false; }
  if c0 > 0 && c0 + s0 != max { ok = false; }
  let f = nft_collection_add(&mut reg, "full", "f", 10000);
  if !f.is_ok { ok = false; }
  if nft_royalty_creator_amount(&reg, 2, max) != max { ok = false; }
  if nft_royalty_seller_amount(&reg, 2, max) != 0 { ok = false; }
  let z = nft_collection_add(&mut reg, "zero", "z", 0);
  if !z.is_ok { ok = false; }
  if nft_royalty_creator_amount(&reg, 3, max) != 0 { ok = false; }
  if nft_royalty_seller_amount(&reg, 3, max) != max { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "max Int royalty split stays exact with no overflow");
}

// --------------------------------------------------
//  t14: enumeration by owner
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let m0 = nft_mint(&mut reg, 0, 1001, "alice", 10);
  let m1 = nft_mint(&mut reg, 0, 1002, "bob", 11);
  let m2 = nft_mint(&mut reg, 0, 1003, "alice", 12);
  let m3 = nft_mint(&mut reg, 1, 2001, "alice", 13);
  if !m0.is_ok || !m1.is_ok || !m2.is_ok || !m3.is_ok { ok = false; }
  if nft_owner_token_count(&reg, "alice") != 3 { ok = false; }
  if nft_owner_token_count(&reg, "bob") != 1 { ok = false; }
  if nft_owner_token_count(&reg, "carol") != 0 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 0) != 1001 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 1) != 1003 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 2) != 2001 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 3) != -1 { ok = false; }
  if nft_owner_token_at(&reg, "alice", -1) != -1 { ok = false; }
  if nft_owner_token_at(&reg, "bob", 0) != 1002 { ok = false; }
  if nft_owner_token_at(&reg, "bob", 1) != -1 { ok = false; }
  let x = nft_transfer(&mut reg, 1001, "alice", "bob", 20);
  if !x.is_ok { ok = false; }
  if nft_owner_token_count(&reg, "alice") != 2 { ok = false; }
  if nft_owner_token_at(&reg, "alice", 0) != 1003 { ok = false; }
  if nft_owner_token_count(&reg, "bob") != 2 { ok = false; }
  if nft_owner_token_at(&reg, "bob", 0) != 1001 { ok = false; }
  if nft_owner_token_at(&reg, "bob", 1) != 1002 { ok = false; }
  return assert(ok, "owner enumeration follows live ownership in row order");
}

// --------------------------------------------------
//  t15: enumeration by collection
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let m0 = nft_mint(&mut reg, 0, 1001, "alice", 10);
  let m1 = nft_mint(&mut reg, 0, 1002, "bob", 11);
  let m2 = nft_mint(&mut reg, 0, 1003, "alice", 12);
  let m3 = nft_mint(&mut reg, 1, 2001, "alice", 13);
  if !m0.is_ok || !m1.is_ok || !m2.is_ok || !m3.is_ok { ok = false; }
  if nft_collection_live_count(&reg, 0) != 3 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != 3 { ok = false; }
  if nft_collection_live_count(&reg, 1) != 1 { ok = false; }
  if nft_collection_minted_count(&reg, 1) != 1 { ok = false; }
  if nft_collection_token_at(&reg, 0, 0) != 1001 { ok = false; }
  if nft_collection_token_at(&reg, 0, 1) != 1002 { ok = false; }
  if nft_collection_token_at(&reg, 0, 2) != 1003 { ok = false; }
  if nft_collection_token_at(&reg, 0, 3) != -1 { ok = false; }
  if nft_collection_token_at(&reg, 1, 0) != 2001 { ok = false; }
  if nft_collection_token_at(&reg, 1, 1) != -1 { ok = false; }
  let b = nft_burn(&mut reg, 1002, "bob", 30);
  if !b.is_ok { ok = false; }
  if nft_collection_live_count(&reg, 0) != 2 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != 3 { ok = false; }
  if nft_collection_token_at(&reg, 0, 0) != 1001 { ok = false; }
  if nft_collection_token_at(&reg, 0, 1) != 1003 { ok = false; }
  if nft_collection_token_at(&reg, 0, 2) != -1 { ok = false; }
  if nft_collection_live_count(&reg, 9) != -1 { ok = false; }
  if nft_collection_minted_count(&reg, 9) != -1 { ok = false; }
  if nft_collection_token_at(&reg, 9, 0) != -1 { ok = false; }
  if nft_collection_token_at(&reg, -1, 0) != -1 { ok = false; }
  if !nft_supply_balanced(&reg) { ok = false; }
  return assert(ok, "collection enumeration excludes burned tokens");
}

// --------------------------------------------------
//  t16: canonical event log across all four kinds
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let a = nft_approve(&mut reg, 1001, "alice", "carol", 13, 50);
  let t = nft_transfer(&mut reg, 1001, "alice", "dave", 20);
  let b = nft_burn(&mut reg, 1002, "bob", 30);
  if !a.is_ok || !t.is_ok || !b.is_ok { ok = false; }
  if nft_event_count(&reg) != 6 { ok = false; }
  var i = 0;
  while i < 6 {
    if nft_event_seq(&reg, i) != i + 1 { ok = false; }
    i = i + 1;
  }
  if nft_event_kind(&reg, 0) != NFT_EVENT_MINT { ok = false; }
  if nft_event_kind(&reg, 1) != NFT_EVENT_MINT { ok = false; }
  if nft_event_kind(&reg, 2) != NFT_EVENT_MINT { ok = false; }
  if nft_event_kind(&reg, 3) != NFT_EVENT_APPROVE { ok = false; }
  if nft_event_kind(&reg, 4) != NFT_EVENT_TRANSFER { ok = false; }
  if nft_event_kind(&reg, 5) != NFT_EVENT_BURN { ok = false; }
  if nft_event_token_id(&reg, 3) != 1001 { ok = false; }
  if nft_event_collection(&reg, 3) != 0 { ok = false; }
  if !streq(nft_event_actor(&reg, 3), "alice") { ok = false; }
  if !streq(nft_event_to(&reg, 3), "carol") { ok = false; }
  if nft_event_tick(&reg, 3) != 13 { ok = false; }
  if nft_event_token_id(&reg, 4) != 1001 { ok = false; }
  if !streq(nft_event_actor(&reg, 4), "alice") { ok = false; }
  if !streq(nft_event_to(&reg, 4), "dave") { ok = false; }
  if nft_event_tick(&reg, 4) != 20 { ok = false; }
  if nft_event_token_id(&reg, 5) != 1002 { ok = false; }
  if !streq(nft_event_actor(&reg, 5), "bob") { ok = false; }
  if !streq(nft_event_to(&reg, 5), "bob") { ok = false; }
  if nft_event_tick(&reg, 5) != 30 { ok = false; }
  if !streq(nft_event_kind_name(1), "mint") { ok = false; }
  if !streq(nft_event_kind_name(2), "transfer") { ok = false; }
  if !streq(nft_event_kind_name(3), "approve") { ok = false; }
  if !streq(nft_event_kind_name(4), "burn") { ok = false; }
  if !streq(nft_event_kind_name(0), "unknown") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "event log records mint/approve/transfer/burn in order");
}

// --------------------------------------------------
//  t17: invariant detection on tampered registries
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  let good = fixture_three();
  if !nft_registry_valid(&good) { ok = false; }
  if !nft_token_ids_unique(&good) { ok = false; }
  if !nft_supply_balanced(&good) { ok = false; }
  let dup = tampered_duplicate_ids();
  if nft_token_ids_unique(&dup) { ok = false; }
  if nft_supply_balanced(&dup) { ok = false; }
  if nft_registry_valid(&dup) { ok = false; }
  let sup = tampered_supply();
  if !nft_token_ids_unique(&sup) { ok = false; }
  if nft_supply_balanced(&sup) { ok = false; }
  if nft_registry_valid(&sup) { ok = false; }
  let seq = tampered_event_seq();
  if !nft_token_ids_unique(&seq) { ok = false; }
  if !nft_supply_balanced(&seq) { ok = false; }
  if nft_registry_valid(&seq) { ok = false; }
  return assert(ok, "invariants detect duplicate ids, bad supply and bad seq");
}

// --------------------------------------------------
//  t18: canonical export
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  var reg = nft_registry_new();
  let c = nft_collection_add(&mut reg, "dao", "deployer", 500);
  if !c.is_ok { ok = false; }
  let m = nft_mint(&mut reg, 0, 7, "alice", 5);
  if !m.is_ok { ok = false; }
  let a = nft_approve(&mut reg, 7, "alice", "bob", 6, 20);
  if !a.is_ok { ok = false; }
  let t = nft_transfer(&mut reg, 7, "bob", "carol", 10);
  if !t.is_ok { ok = false; }
  var want = "nft-registry\t1\n";
  want = want + "collections\t1\n";
  want = want + "collection\t0\tdao\tdeployer\t500\t1\t1\n";
  want = want + "tokens\t1\n";
  want = want + "token\t7\t0\tcarol\tlive\t5\t-1\n";
  want = want + "approvals\t1\n";
  want = want + "approval\t7\talice\tbob\t20\n";
  want = want + "operators\t0\n";
  want = want + "events\t3\n";
  want = want + "event\t1\tmint\t7\t0\talice\talice\t5\n";
  want = want + "event\t2\tapprove\t7\t0\talice\tbob\t6\n";
  want = want + "event\t3\ttransfer\t7\t0\tbob\tcarol\t10\n";
  if !streq(nft_registry_export(&reg), want) { ok = false; }
  return assert(ok, "registry export is canonical and complete");
}

// --------------------------------------------------
//  t19: permissions matrix (approvals and operators)
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  var reg = fixture_three();
  let a = nft_approve(&mut reg, 1001, "alice", "carol", 5, 90);
  if !a.is_ok { ok = false; }
  let s = nft_set_operator(&mut reg, "alice", "op", 90);
  if !s.is_ok { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1002, "carol", "dave", 10)), "nft: sender not authorized") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1002, "op", "dave", 10)), "nft: sender not authorized") { ok = false; }
  let x = nft_transfer(&mut reg, 1001, "alice", "bob", 20);
  if !x.is_ok { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "carol", "dave", 25)), "nft: sender not authorized") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "op", "dave", 25)), "nft: sender not authorized") { ok = false; }
  let a2 = nft_approve(&mut reg, 1001, "bob", "carol", 30, 60);
  if !a2.is_ok { ok = false; }
  let y = nft_transfer(&mut reg, 1001, "carol", "erin", 40);
  if !y.is_ok { ok = false; }
  if !streq(nft_token_owner(&reg, 1001), "erin") { ok = false; }
  if !streq(int_err(nft_transfer(&mut reg, 1001, "alice", "frank", 41)), "nft: sender not authorized") { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  return assert(ok, "approvals and operators are scoped per token and owner");
}

// --------------------------------------------------
//  t20: full lifecycle fixture
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = true;
  var reg = fixture_registry();
  let m0 = nft_mint(&mut reg, 0, 1001, "alice", 10);
  let m1 = nft_mint(&mut reg, 0, 1002, "bob", 11);
  let m2 = nft_mint(&mut reg, 1, 2001, "alice", 12);
  if !m0.is_ok || !m1.is_ok || !m2.is_ok { ok = false; }
  let a = nft_approve(&mut reg, 1001, "alice", "carol", 13, 40);
  if !a.is_ok { ok = false; }
  let t1 = nft_transfer(&mut reg, 1001, "carol", "dave", 20);
  if !t1.is_ok { ok = false; }
  let op = nft_set_operator(&mut reg, "alice", "op", 60);
  if !op.is_ok { ok = false; }
  let t2 = nft_transfer(&mut reg, 2001, "op", "bob", 30);
  if !t2.is_ok { ok = false; }
  let b = nft_burn(&mut reg, 1002, "bob", 35);
  if !b.is_ok { ok = false; }
  if nft_live_supply(&reg) != 2 { ok = false; }
  if nft_burned_supply(&reg) != 1 { ok = false; }
  if nft_token_count(&reg) != 3 { ok = false; }
  if !streq(nft_token_owner(&reg, 1001), "dave") { ok = false; }
  if !streq(nft_token_owner(&reg, 2001), "bob") { ok = false; }
  if !streq(nft_token_owner(&reg, 1002), "bob") { ok = false; }
  if nft_token_is_live(&reg, 1002) { ok = false; }
  if nft_owner_token_count(&reg, "dave") != 1 { ok = false; }
  if nft_owner_token_count(&reg, "bob") != 1 { ok = false; }
  if nft_owner_token_count(&reg, "alice") != 0 { ok = false; }
  if nft_collection_live_count(&reg, 0) != 1 { ok = false; }
  if nft_collection_live_count(&reg, 1) != 1 { ok = false; }
  if nft_collection_minted_count(&reg, 0) != 2 { ok = false; }
  if nft_collection_minted_count(&reg, 1) != 1 { ok = false; }
  if nft_event_count(&reg) != 7 { ok = false; }
  if nft_event_seq(&reg, 6) != 7 { ok = false; }
  if nft_event_kind(&reg, 6) != NFT_EVENT_BURN { ok = false; }
  if !streq(nft_event_actor(&reg, 6), "bob") { ok = false; }
  if nft_event_token_id(&reg, 6) != 1002 { ok = false; }
  if !nft_token_ids_unique(&reg) { ok = false; }
  if !nft_supply_balanced(&reg) { ok = false; }
  if !nft_registry_valid(&reg) { ok = false; }
  let e = nft_registry_export(&reg);
  if !string.str_starts_with(e, "nft-registry\t1\ncollections\t2\n") { ok = false; }
  if !string.str_ends_with(e, "event\t7\tburn\t1002\t0\tbob\tbob\t35\n") { ok = false; }
  return assert(ok, "full lifecycle keeps invariants, events and export coherent");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn report(r: TestResult, failed: Int) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return failed;
  }
  io.println("  [FAIL] " + r.name);
  return failed + 1;
}

fn main() -> Int {
  io.println("=== xiom.nft conformance tests ===");
  var failed: Int = 0;
  failed = report(t1(), failed);
  failed = report(t2(), failed);
  failed = report(t3(), failed);
  failed = report(t4(), failed);
  failed = report(t5(), failed);
  failed = report(t6(), failed);
  failed = report(t7(), failed);
  failed = report(t8(), failed);
  failed = report(t9(), failed);
  failed = report(t10(), failed);
  failed = report(t11(), failed);
  failed = report(t12(), failed);
  failed = report(t13(), failed);
  failed = report(t14(), failed);
  failed = report(t15(), failed);
  failed = report(t16(), failed);
  failed = report(t17(), failed);
  failed = report(t18(), failed);
  failed = report(t19(), failed);
  failed = report(t20(), failed);
  if failed == 0 {
    io.println("xiom.nft: all tests passed");
  } else {
    io.println("xiom.nft: tests failed");
  }
  return failed;
}
