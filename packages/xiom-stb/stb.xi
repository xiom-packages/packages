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

pub fn load_image(path: Str) -> Result[Image, Str]
    requires: path.len() > 0
    ensures: true;

pub fn load_image_rgba(path: Str) -> Result[Image, Str]
    requires: path.len() > 0
    ensures: true;

pub fn load_from_memory(data: &Vec[UInt8]) -> Result[Image, Str]
    requires: data.len() > 0
    ensures: true;

pub fn load_from_memory_rgba(data: &Vec[UInt8]) -> Result[Image, Str]
    requires: data.len() > 0
    ensures: true;

pub fn write_png(path: Str, image: &Image) -> Result[Unit, Str]
    requires: path.len() > 0 && image.data.len() > 0
    ensures: true;

pub fn write_jpg(path: Str, image: &Image, quality: Int) -> Result[Unit, Str]
    requires: path.len() > 0 && image.data.len() > 0 && quality >= 1 && quality <= 100
    ensures: true;

pub fn write_bmp(path: Str, image: &Image) -> Result[Unit, Str]
    requires: path.len() > 0 && image.data.len() > 0
    ensures: true;

pub fn failure_reason() -> Str
    ensures: true;

pub fn free_image(image: &mut Image)
    requires: true
    ensures: true;

pub fn pixel_at(image: &Image, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)
    requires: x >= 0 && x < image.width && y >= 0 && y < image.height
    ensures: true;

pub fn pixel_index(image: &Image, x: Int, y: Int) -> Int
    requires: x >= 0 && x < image.width && y >= 0 && y < image.height
    ensures: result >= 0 && result < image.data.len();
