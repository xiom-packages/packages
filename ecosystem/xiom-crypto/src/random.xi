module xiom.crypto.random

use xiom.rand;

pub fn random_bytes(count: Int) -> Vec[Int]
  requires: count > 0;
{
  return xiom.rand.random_bytes(count);
}
