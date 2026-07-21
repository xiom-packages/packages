// XIOM — libsodium Bindings (Secure Cryptography)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.libsodium

pub fn init() -> Result[Unit, Str];

pub fn random_bytes(count: Int) -> Vec[UInt8]
  requires: count > 0;

pub fn random_int_uniform(upper_bound: Int) -> Int
  requires: upper_bound > 0;

pub fn secretbox_encrypt(message: &Vec[UInt8], key: &Vec[UInt8], nonce: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: key.len() == SECRETBOX_KEYBYTES
  requires: nonce.len() == SECRETBOX_NONCEBYTES;

pub fn secretbox_decrypt(ciphertext: &Vec[UInt8], key: &Vec[UInt8], nonce: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: key.len() == SECRETBOX_KEYBYTES
  requires: nonce.len() == SECRETBOX_NONCEBYTES;

pub fn box_keypair() -> (Vec[UInt8], Vec[UInt8]);

pub fn box_encrypt(message: &Vec[UInt8], nonce: &Vec[UInt8], receiver_pk: &Vec[UInt8], sender_sk: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: receiver_pk.len() == BOX_PUBLICKEYBYTES
  requires: sender_sk.len() == BOX_SECRETKEYBYTES;

pub fn box_decrypt(ciphertext: &Vec[UInt8], nonce: &Vec[UInt8], sender_pk: &Vec[UInt8], receiver_sk: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: sender_pk.len() == BOX_PUBLICKEYBYTES
  requires: receiver_sk.len() == BOX_SECRETKEYBYTES;

pub fn sign_keypair() -> (Vec[UInt8], Vec[UInt8]);

pub fn sign_detached(message: &Vec[UInt8], secret_key: &Vec[UInt8]) -> Vec[UInt8]
  requires: secret_key.len() == SIGN_SECRETKEYBYTES;

pub fn verify_detached(signature: &Vec[UInt8], message: &Vec[UInt8], public_key: &Vec[UInt8]) -> Bool
  requires: public_key.len() == SIGN_PUBLICKEYBYTES;

pub fn generic_hash(data: &Vec[UInt8], output_len: Int) -> Result[Vec[UInt8], Str]
  requires: output_len > 0;

pub fn generic_hash_keyed(data: &Vec[UInt8], key: &Vec[UInt8], output_len: Int) -> Result[Vec[UInt8], Str]
  requires: output_len > 0;

pub fn pwhash(password: Str, ops_limit: Int, mem_limit: Int) -> Result[Vec[UInt8], Str]
  requires: ops_limit > 0
  requires: mem_limit > 0;

pub fn pwhash_verify(hash: &Vec[UInt8], password: Str) -> Bool
  requires: hash.len() > 0;

pub const SECRETBOX_KEYBYTES: Int = 32;
pub const SECRETBOX_NONCEBYTES: Int = 24;
pub const BOX_PUBLICKEYBYTES: Int = 32;
pub const BOX_SECRETKEYBYTES: Int = 32;
pub const SIGN_PUBLICKEYBYTES: Int = 32;
pub const SIGN_SECRETKEYBYTES: Int = 64;
