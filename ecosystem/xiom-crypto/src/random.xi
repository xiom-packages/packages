module xiom.crypto.random

pub fn xorshift32(state: Int) -> Int {
  var x = state;
  x = x ^ (x << 13);
  x = x ^ (x >> 17);
  x = x ^ (x << 5);
  return x;
}

pub fn xorshift64(state: Int) -> Int {
  var x = state;
  x = x ^ (x << 13);
  x = x ^ (x >> 7);
  x = x ^ (x << 17);
  return x;
}

pub fn xorshift128(state: Int) -> Int {
  var x = state;
  x = x ^ (x << 11);
  x = x ^ (x >> 8);
  x = x ^ (x << 19);
  return x;
}

pub fn xorshift_star64(state: Int) -> Int {
  var x = state;
  x = x ^ (x >> 12);
  x = x ^ (x << 25);
  x = x ^ (x >> 27);
  return x * -1275374097;
}

pub fn random_range(state: Int, min: Int, max: Int) -> (Int, Int) {
  var new_state = xorshift64(state);
  var range = max - min;
  if range == 0 {
    return (min, new_state);
  };
  var value = min + (new_state % range);
  return (value, new_state);
}

pub fn random_bytes(state: Int, count: Int) -> (Vec[Int], Int) {
  var result = Vec[Int].new();
  var current = state;
  var i = 0;
  while i < count {
    current = xorshift64(current);
    result.push(current & 0xFF);
    if count - i > 1 {
      result.push((current >> 8) & 0xFF);
      i = i + 1;
    };
    if count - i > 2 {
      result.push((current >> 16) & 0xFF);
      i = i + 1;
    };
    if count - i > 3 {
      result.push((current >> 24) & 0xFF);
      i = i + 1;
    };
    i = i + 1;
  }
  return (result, current);
}
