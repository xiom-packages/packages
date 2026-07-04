# xiom:stb — Image Loading

stb_image FFI bindings. Load PNG, JPG, BMP, TGA, GIF, HDR.

## Example
```xiom
use xiom.stb;

fn main() -> Int {
  let image = load_image_rgba("texture.png")?;
  let (r, g, b, a) = pixel_at(image, 10, 10);
  write_jpg("output.jpg", image, 90)?;
  return 0;
}
```
