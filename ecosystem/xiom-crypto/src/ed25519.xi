module xiom.crypto.ed25519

pub type Ed25519KeyPair = {
  public_key: Vec[Int];
  private_key: Vec[Int];
}

pub type Ed25519Signature = {
  r: Vec[Int];
  s: Vec[Int];
}

pub fn ed25519_keygen() -> Ed25519KeyPair {
  return Ed25519KeyPair{
    public_key: Vec[Int].new(),
    private_key: Vec[Int].new(),
  };
}

pub fn ed25519_sign(message: &Vec[Int], keypair: &Ed25519KeyPair) -> Ed25519Signature {
  return Ed25519Signature{
    r: Vec[Int].new(),
    s: Vec[Int].new(),
  };
}

pub fn ed25519_verify(message: &Vec[Int], signature: &Ed25519Signature, public_key: &Vec[Int]) -> Bool {
  return false;
}
