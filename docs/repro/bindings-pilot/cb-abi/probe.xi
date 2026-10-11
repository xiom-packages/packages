// cb-abi probe: prove the XIOM-fn -> C-callback ABI before binding glfw's
// remaining callback setters (xiom.glfw 0.5.0 gate).
//
// Pattern under test (G-16, v0.56): a top-level XIOM function cast to Int
// (`cb as Int` -> ptrtoint @cb) is handed to C as a bare function pointer;
// C calls it back with the real C signature. Also probed: registry lifetime
// (store + later invoke) and Unit returns (GLFW key/close shapes).
//
// Run (from repo root):
//   & scripts\xiom.ps1 --run <abs path>\probe.xi --c-source <abs path>\cbhost.c
//
// Expected (all shapes proven): control=42 direct=42 stored=20 fire_rc=0
// calls=1 key=65 sc=33 action=1 mods=5 close_rc=0 close_calls=1 close_win=4242.

module cb_abi_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_plus_one(x: Int32) -> Int32;
  fn xt_cb_int(f: Int, x: Int32) -> Int32;
  fn xt_cb_store_int(f: Int);
  fn xt_cb_invoke_stored(x: Int32) -> Int32;
  fn xt_cb_set_key(f: Int);
  fn xt_cb_fire_key(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32) -> Int32;
  fn xt_cb_set_close(f: Int);
  fn xt_cb_fire_close(win: Int) -> Int32;
  fn xt_cb_note_key(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32);
  fn xt_cb_note_close(win: Int);
  fn xt_cb_key_calls() -> Int;
  fn xt_cb_last_key() -> Int32;
  fn xt_cb_last_scancode() -> Int32;
  fn xt_cb_last_action() -> Int32;
  fn xt_cb_last_mods() -> Int32;
  fn xt_cb_key_win() -> Int;
  fn xt_cb_close_calls() -> Int;
  fn xt_cb_close_win() -> Int;
  fn xt_cb_reset();
}

// G-16 pattern: top-level fn cast to Int becomes the C callback address.
fn cb_double(x: Int32) -> Int32 { return x * 2; }

// GLFW key-callback shape (void return, window handle + four int params).
fn cb_key(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32)
  requires: true
{
  xt_cb_note_key(win, key, scancode, action, mods);
}

// GLFW close-callback shape (void return, one window param).
fn cb_close(win: Int)
  requires: true
{
  xt_cb_note_close(win);
}

fn main() -> Int {
  unsafe {
    // control: plain C callee
    let control = xt_cb_plus_one(41) as Int;
    io.println("control=" + int_to_string(control));
    io.flush_stdout();

    // shape 1: immediate call through the cast address
    let direct = xt_cb_int(cb_double as Int, 21) as Int;
    io.println("direct=" + int_to_string(direct));
    io.flush_stdout();

    // shape 2: stored address survives the call that registered it
    xt_cb_store_int(cb_double as Int);
    let stored = xt_cb_invoke_stored(10) as Int;
    io.println("stored=" + int_to_string(stored));
    io.flush_stdout();

    // shape 3: GLFW key callback round trip
    xt_cb_reset();
    xt_cb_set_key(cb_key as Int);
    let key_rc = xt_cb_fire_key(0, 65, 33, 1, 5) as Int;
    io.println("fire_rc=" + int_to_string(key_rc));
    io.println("calls=" + int_to_string(xt_cb_key_calls()));
    io.println("key=" + int_to_string(xt_cb_last_key() as Int));
    io.println("sc=" + int_to_string(xt_cb_last_scancode() as Int));
    io.println("action=" + int_to_string(xt_cb_last_action() as Int));
    io.println("mods=" + int_to_string(xt_cb_last_mods() as Int));
    io.flush_stdout();

    // shape 4: GLFW close callback round trip (window pointer fidelity)
    xt_cb_set_close(cb_close as Int);
    let close_rc = xt_cb_fire_close(4242) as Int;
    io.println("close_rc=" + int_to_string(close_rc));
    io.println("close_calls=" + int_to_string(xt_cb_close_calls()));
    io.println("close_win=" + int_to_string(xt_cb_close_win()));
    io.flush_stdout();
  }
  return 0;
}
