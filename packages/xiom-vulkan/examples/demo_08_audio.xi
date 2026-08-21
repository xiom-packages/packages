// ===========================================================================
// XIOM Vulkan SDK -- Example 08: Audio
// Shows: audio_beep, audio_play_wav
// ===========================================================================

module demo_audio
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  io.println("08 -- Audio: Beep test");
  audio_beep();
  io.println("Beep played. Check speakers.");
  return 0;
}
