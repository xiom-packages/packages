module xiom.core.storage.checksum

// Corruption detection for blocks, WAL records, and snapshots. This is a real
// FNV-1a 32-bit hash over the low byte of each slot -- cheap, dependency-free,
// and adequate for detecting accidental corruption (not a cryptographic MAC).
//
// FNV-1a: hash = offset_basis; for each byte: hash ^= byte; hash *= prime.
//   offset_basis (32-bit) = 2166136261
//   prime        (32-bit) = 16777619
// All arithmetic is masked to 32 bits with 0xFFFFFFFF.

pub fn crc32(data: &Vec[Int]) -> Int {
  var hash = 2166136261;
  var i = 0;
  while i < data.len() {
    var b = data[i] & 255;
    hash = hash ^ b;
    hash = (hash * 16777619) & 4294967295;
    i = i + 1;
  }
  return hash;
}

pub fn verify_checksum(data: &Vec[Int], expected: Int) -> Bool {
  return crc32(data) == expected;
}
