module xiom.crypto.pbkdf

use xiom.crypto.sha;

pub fn pbkdf2_sha256(password: &Vec[Int], salt: &Vec[Int], iterations: Int, keylen: Int) -> Vec[Int]
  requires: password.len() > 0;
  requires: salt.len() > 0;
  requires: iterations >= 1;
  requires: keylen > 0;
{
  var result = Vec[Int].new();
  var block_count = (keylen + 31) / 32;
  var block = 1;

  while block <= block_count {
    var u = Vec[Int].new();
    var prev = Vec[Int].new();

    var i = 0;
    while i < salt.len() {
      u.push(salt[i]);
      i = i + 1;
    }

    u.push((block >> 24) & 0xFF);
    u.push((block >> 16) & 0xFF);
    u.push((block >> 8) & 0xFF);
    u.push(block & 0xFF);

    var hmac_result = sha256_hmac(&u, password);
    var block_result = Vec[Int].new();
    i = 0;
    while i < hmac_result.len() {
      block_result.push(hmac_result[i]);
      i = i + 1;
    }

    prev = hmac_result;

    var iter = 1;
    while iter < iterations {
      var next_hmac = sha256_hmac(&prev, password);
      i = 0;
      while i < block_result.len() {
        block_result[i] = block_result[i] ^ next_hmac[i];
        i = i + 1;
      }
      prev = next_hmac;
      iter = iter + 1;
    }

    i = 0;
    while i < block_result.len() && result.len() < keylen {
      result.push(block_result[i]);
      i = i + 1;
    }

    block = block + 1;
  }

  var final_result = Vec[Int].new();
  var i = 0;
  while i < keylen && i < result.len() {
    final_result.push(result[i]);
    i = i + 1;
  }

  return final_result;
}

pub fn hkdf_sha256(ikm: &Vec[Int], salt: &Vec[Int], info: &Vec[Int], length: Int) -> Vec[Int] {
  var actual_salt = Vec[Int].new();
  if salt.len() == 0 {
    var i = 0;
    while i < 32 {
      actual_salt.push(0);
      i = i + 1;
    }
  } else {
    var i = 0;
    while i < salt.len() {
      actual_salt.push(salt[i]);
      i = i + 1;
    }
  };

  var prk = sha256_hmac(ikm, &actual_salt);

  var okm = Vec[Int].new();
  var t = Vec[Int].new();
  var counter = 1;

  while okm.len() < length {
    var t_input = Vec[Int].new();
    var i = 0;
    while i < t.len() {
      t_input.push(t[i]);
      i = i + 1;
    }
    i = 0;
    while i < info.len() {
      t_input.push(info[i]);
      i = i + 1;
    }
    t_input.push(counter);

    t = sha256_hmac(&t_input, &prk);

    i = 0;
    while i < t.len() && okm.len() < length {
      okm.push(t[i]);
      i = i + 1;
    }

    counter = counter + 1;
  }

  var result = Vec[Int].new();
  var i = 0;
  while i < length {
    result.push(okm[i]);
    i = i + 1;
  }

  return result;
}


