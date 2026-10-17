module d_mod_xiomprobe

pub type Handle = Int;

pub fn take(hs: &Vec[Handle]) -> Int {
  return hs.len();
}
