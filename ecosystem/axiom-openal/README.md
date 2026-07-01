# axiom:openal — 3D Audio

OpenAL Soft FFI bindings for AXIOM. 3D positional audio.

## Example
```axiom
use axiom.openal;

fn main() -> Int {
  let (buffer, freq) = load_wav("explosion.wav")?;
  let source = play_sound(buffer, freq)?;
  set_listener_position(0.0, 0.0, 10.0);
  set_source_position(source, 5.0, 0.0, 0.0);
  while is_source_playing(source) { }
  delete_source(source);
  return 0;
}
```
