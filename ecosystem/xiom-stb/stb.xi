// XIOM — stb_image Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.stb

pub type Image = {
  width: Int;
  height: Int;
  channels: Int;
  data: Vec[UInt8];
} derive[Clone]

pub fn load_image(path: Str) -> Result[Image, Str];
pub fn load_image_rgba(path: Str) -> Result[Image, Str];
pub fn load_from_memory(data: &Vec[UInt8]) -> Result[Image, Str];
pub fn load_from_memory_rgba(data: &Vec[UInt8]) -> Result[Image, Str];

pub fn write_png(path: Str, image: &Image) -> Result[Unit, Str];
pub fn write_jpg(path: Str, image: &Image, quality: Int) -> Result[Unit, Str];
pub fn write_bmp(path: Str, image: &Image) -> Result[Unit, Str];

pub fn failure_reason() -> Str;
pub fn free_image(image: &mut Image);

// Pixel access helpers
pub fn pixel_at(image: &Image, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8);
pub fn pixel_index(image: &Image, x: Int, y: Int) -> Int;
