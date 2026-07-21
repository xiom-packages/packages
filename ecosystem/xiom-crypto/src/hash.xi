module xiom.crypto.hash

pub fn hash_djb2(data: &Vec[Int]) -> Int
  requires: data.len() > 0
{
  var hash = 5381;
  var i = 0;
  while i < data.len() {
    hash = ((hash << 5) + hash) + data[i];
    i = i + 1;
  }
  return hash;
}

pub fn hash_fnv1a(data: &Vec[Int]) -> Int
  requires: data.len() > 0
{
  var hash = -2128831035;
  var i = 0;
  while i < data.len() {
    hash = hash ^ data[i];
    hash = hash * 16777619;
    i = i + 1;
  }
  return hash;
}

pub fn hash_murmur3_32(data: &Vec[Int], seed: Int) -> Int
  requires: data.len() > 0
{
  var h1 = seed;
  var c1 = -862048943;
  var c2 = 461845907;
  var len = data.len();
  var i = 0;

  while i + 4 <= len {
    var k1 = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);

    k1 = k1 * c1;
    k1 = (k1 << 15) | ((k1 >> 17) & 0x7FFF);
    k1 = k1 * c2;

    h1 = h1 ^ k1;
    h1 = (h1 << 13) | ((h1 >> 19) & 0x1FFF);
    h1 = h1 * 5 + -430675100;

    i = i + 4;
  }

  var tail = 0;
  var remaining = len - i;
  if remaining == 3 {
    tail = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16);
  }
  elif remaining == 2 {
    tail = data[i] | (data[i + 1] << 8);
  }
  elif remaining == 1 {
    tail = data[i];
  }

  if remaining > 0 {
    tail = tail * c1;
    tail = (tail << 15) | ((tail >> 17) & 0x7FFF);
    tail = tail * c2;
    h1 = h1 ^ tail;
  };

  h1 = h1 ^ len;

  h1 = h1 ^ (h1 >> 16);
  h1 = h1 * -2048144789;
  h1 = h1 ^ (h1 >> 13);
  h1 = h1 * -1028477387;
  h1 = h1 ^ (h1 >> 16);

  return h1;
}
