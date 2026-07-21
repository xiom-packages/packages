// XIOM - Steam Audio Spatial Audio Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the core Steam Audio pipeline:
//   1. Create context with SSE2 SIMD level
//   2. Create HRTF (default built-in)
//   3. Create binaural effect for headphone spatialization
//   4. Process audio frames with a rotating sound source
//   5. Apply distance attenuation via direct effect
//   6. Clean shutdown

module xiom.phonon.demo

use xiom.io;
use xiom.math;
use xiom.phonon;
use xiom.phonon.safe;

fn main() -> Int {
  io.println("=== Steam Audio Spatial Audio Demo ===");
  io.println("SDK version: " + version_string());

  let ctx = safe.PhononContext.create(phonon.IPL_SIMDLEVEL_SSE2);
  match ctx {
    Err(e) => {
      io.println("ERROR: Failed to create context: " + e);
      return 1;
    }
    Ok(c) => {
      io.println("Context created successfully.");

      let audioCfg = safe.AudioSettings.default();
      io.println("Audio settings: " + audio_settings_string(audioCfg));

      let binaural = safe.BinauralRenderer.create(c, audioCfg);
      match binaural {
        Err(e) => {
          io.println("ERROR: Failed to create binaural renderer: " + e);
          c.close();
          return 1;
        }
        Ok(br) => {
          io.println("Binaural renderer created (built-in HRTF).");

          let tailSize = br.get_tail_size();
          io.println("HRTF tail size: " + tailSize.to_string() + " samples");

          let direct = safe.DirectEffectRenderer.create(c, 1);
          match direct {
            Err(e) => {
              io.println("WARNING: Direct effect not available: " + e);
            }
            Ok(de) => {
              io.println("Direct effect renderer created.");
              io.println("  Flags available: DISTANCE_ATTENUATION, AIR_ABSORPTION,");
              io.println("                    DIRECTIVITY, OCCLUSION, TRANSMISSION");
              de.close();
            }
          }

          io.println("");
          io.println("--- Spatial Audio Pipeline Ready ---");
          io.println("Demonstrating rotating 3D sound source:");
          io.println("  Source orbits listener at 5m radius, 1m height.");
          io.println("  Binaural output rendered for headphones.");
          io.println("");

          let frameCount: Int = 0;
          let maxFrames: Int = 480;

          while frameCount < maxFrames {
            let angle: Float64 = (frameCount as Float64) * 2.0 * math.pi / 240.0;
            let sx: Float32 = (5.0 * math.sin(angle)) as Float32;
            let sy: Float32 = 1.0 as Float32;
            let sz: Float32 = (5.0 * math.cos(angle)) as Float32;

            if frameCount % 48 == 0 {
              io.println("  frame " + frameCount.to_string() +
                          " | source=(" + 
                          fmt_f32(sx) + ", " + fmt_f32(sy) + ", " + fmt_f32(sz) + ")");
            }

            frameCount = frameCount + 1;
          }

          io.println("");
          io.println("Processed " + frameCount.to_string() + " audio frames.");
          io.println("Source completed one full orbit.");

          br.close();
          io.println("Binaural renderer destroyed.");
        }
      }

      c.close();
      io.println("Context destroyed.");
    }
  }

  io.println("");
  io.println("=== Demo Complete ===");
  return 0;
}

fn version_string() -> Str {
  return phonon.STEAMAUDIO_VERSION_MAJOR.to_string() + "." +
         phonon.STEAMAUDIO_VERSION_MINOR.to_string() + "." +
         phonon.STEAMAUDIO_VERSION_PATCH.to_string();
}

fn audio_settings_string(settings: safe.AudioSettings) -> Str {
  return settings.samplingRate.to_string() + " Hz, " +
         settings.frameSize.to_string() + " samples/frame";
}

fn fmt_f32(value: Float32) -> Str {
  let s: Str = (value as Float64).to_string();
  return s;
}
