module xiom.crypto.aes

use xiom.math;

type AesState = {
  s00: Int; s01: Int; s02: Int; s03: Int;
  s10: Int; s11: Int; s12: Int; s13: Int;
  s20: Int; s21: Int; s22: Int; s23: Int;
  s30: Int; s31: Int; s32: Int; s33: Int;
}

type AesCol = { b0: Int; b1: Int; b2: Int; b3: Int; }

type GfInput = { val: Int; }

type IntHolder = { val: Int; }

type StateHolder = { s: AesState; }

type KeyExpState = { temp0: Int; temp1: Int; temp2: Int; temp3: Int; rcon_iteration: Int; }

pub fn aes_sbox(b: Int) -> Int
  requires: b >= 0 && b <= 255
  ensures: result >= 0 && result <= 255
{
  var val = xiom.math.bit_and(b, 0xFF);
  if val == 0x00 { return 0x63; };
  if val == 0x01 { return 0x7c; };
  if val == 0x02 { return 0x77; };
  if val == 0x03 { return 0x7b; };
  if val == 0x04 { return 0xf2; };
  if val == 0x05 { return 0x6b; };
  if val == 0x06 { return 0x6f; };
  if val == 0x07 { return 0xc5; };
  if val == 0x08 { return 0x30; };
  if val == 0x09 { return 0x01; };
  if val == 0x0a { return 0x67; };
  if val == 0x0b { return 0x2b; };
  if val == 0x0c { return 0xfe; };
  if val == 0x0d { return 0xd7; };
  if val == 0x0e { return 0xab; };
  if val == 0x0f { return 0x76; };
  if val == 0x10 { return 0xca; };
  if val == 0x11 { return 0x82; };
  if val == 0x12 { return 0xc9; };
  if val == 0x13 { return 0x7d; };
  if val == 0x14 { return 0xfa; };
  if val == 0x15 { return 0x59; };
  if val == 0x16 { return 0x47; };
  if val == 0x17 { return 0xf0; };
  if val == 0x18 { return 0xad; };
  if val == 0x19 { return 0xd4; };
  if val == 0x1a { return 0xa2; };
  if val == 0x1b { return 0xaf; };
  if val == 0x1c { return 0x9c; };
  if val == 0x1d { return 0xa4; };
  if val == 0x1e { return 0x72; };
  if val == 0x1f { return 0xc0; };
  if val == 0x20 { return 0xb7; };
  if val == 0x21 { return 0xfd; };
  if val == 0x22 { return 0x93; };
  if val == 0x23 { return 0x26; };
  if val == 0x24 { return 0x36; };
  if val == 0x25 { return 0x3f; };
  if val == 0x26 { return 0xf7; };
  if val == 0x27 { return 0xcc; };
  if val == 0x28 { return 0x34; };
  if val == 0x29 { return 0xa5; };
  if val == 0x2a { return 0xe5; };
  if val == 0x2b { return 0xf1; };
  if val == 0x2c { return 0x71; };
  if val == 0x2d { return 0xd8; };
  if val == 0x2e { return 0x31; };
  if val == 0x2f { return 0x15; };
  if val == 0x30 { return 0x04; };
  if val == 0x31 { return 0xc7; };
  if val == 0x32 { return 0x23; };
  if val == 0x33 { return 0xc3; };
  if val == 0x34 { return 0x18; };
  if val == 0x35 { return 0x96; };
  if val == 0x36 { return 0x05; };
  if val == 0x37 { return 0x9a; };
  if val == 0x38 { return 0x07; };
  if val == 0x39 { return 0x12; };
  if val == 0x3a { return 0x80; };
  if val == 0x3b { return 0xe2; };
  if val == 0x3c { return 0xeb; };
  if val == 0x3d { return 0x27; };
  if val == 0x3e { return 0xb2; };
  if val == 0x3f { return 0x75; };
  if val == 0x40 { return 0x09; };
  if val == 0x41 { return 0x83; };
  if val == 0x42 { return 0x2c; };
  if val == 0x43 { return 0x1a; };
  if val == 0x44 { return 0x1b; };
  if val == 0x45 { return 0x6e; };
  if val == 0x46 { return 0x5a; };
  if val == 0x47 { return 0xa0; };
  if val == 0x48 { return 0x52; };
  if val == 0x49 { return 0x3b; };
  if val == 0x4a { return 0xd6; };
  if val == 0x4b { return 0xb3; };
  if val == 0x4c { return 0x29; };
  if val == 0x4d { return 0xe3; };
  if val == 0x4e { return 0x2f; };
  if val == 0x4f { return 0x84; };
  if val == 0x50 { return 0x53; };
  if val == 0x51 { return 0xd1; };
  if val == 0x52 { return 0x00; };
  if val == 0x53 { return 0xed; };
  if val == 0x54 { return 0x20; };
  if val == 0x55 { return 0xfc; };
  if val == 0x56 { return 0xb1; };
  if val == 0x57 { return 0x5b; };
  if val == 0x58 { return 0x6a; };
  if val == 0x59 { return 0xcb; };
  if val == 0x5a { return 0xbe; };
  if val == 0x5b { return 0x39; };
  if val == 0x5c { return 0x4a; };
  if val == 0x5d { return 0x4c; };
  if val == 0x5e { return 0x58; };
  if val == 0x5f { return 0xcf; };
  if val == 0x60 { return 0xd0; };
  if val == 0x61 { return 0xef; };
  if val == 0x62 { return 0xaa; };
  if val == 0x63 { return 0xfb; };
  if val == 0x64 { return 0x43; };
  if val == 0x65 { return 0x4d; };
  if val == 0x66 { return 0x33; };
  if val == 0x67 { return 0x85; };
  if val == 0x68 { return 0x45; };
  if val == 0x69 { return 0xf9; };
  if val == 0x6a { return 0x02; };
  if val == 0x6b { return 0x7f; };
  if val == 0x6c { return 0x50; };
  if val == 0x6d { return 0x3c; };
  if val == 0x6e { return 0x9f; };
  if val == 0x6f { return 0xa8; };
  if val == 0x70 { return 0x51; };
  if val == 0x71 { return 0xa3; };
  if val == 0x72 { return 0x40; };
  if val == 0x73 { return 0x8f; };
  if val == 0x74 { return 0x92; };
  if val == 0x75 { return 0x9d; };
  if val == 0x76 { return 0x38; };
  if val == 0x77 { return 0xf5; };
  if val == 0x78 { return 0xbc; };
  if val == 0x79 { return 0xb6; };
  if val == 0x7a { return 0xda; };
  if val == 0x7b { return 0x21; };
  if val == 0x7c { return 0x10; };
  if val == 0x7d { return 0xff; };
  if val == 0x7e { return 0xf3; };
  if val == 0x7f { return 0xd2; };
  if val == 0x80 { return 0xcd; };
  if val == 0x81 { return 0x0c; };
  if val == 0x82 { return 0x13; };
  if val == 0x83 { return 0xec; };
  if val == 0x84 { return 0x5f; };
  if val == 0x85 { return 0x97; };
  if val == 0x86 { return 0x44; };
  if val == 0x87 { return 0x17; };
  if val == 0x88 { return 0xc4; };
  if val == 0x89 { return 0xa7; };
  if val == 0x8a { return 0x7e; };
  if val == 0x8b { return 0x3d; };
  if val == 0x8c { return 0x64; };
  if val == 0x8d { return 0x5d; };
  if val == 0x8e { return 0x19; };
  if val == 0x8f { return 0x73; };
  if val == 0x90 { return 0x60; };
  if val == 0x91 { return 0x81; };
  if val == 0x92 { return 0x4f; };
  if val == 0x93 { return 0xdc; };
  if val == 0x94 { return 0x22; };
  if val == 0x95 { return 0x2a; };
  if val == 0x96 { return 0x90; };
  if val == 0x97 { return 0x88; };
  if val == 0x98 { return 0x46; };
  if val == 0x99 { return 0xee; };
  if val == 0x9a { return 0xb8; };
  if val == 0x9b { return 0x14; };
  if val == 0x9c { return 0xde; };
  if val == 0x9d { return 0x5e; };
  if val == 0x9e { return 0x0b; };
  if val == 0x9f { return 0xdb; };
  if val == 0xa0 { return 0xe0; };
  if val == 0xa1 { return 0x32; };
  if val == 0xa2 { return 0x3a; };
  if val == 0xa3 { return 0x0a; };
  if val == 0xa4 { return 0x49; };
  if val == 0xa5 { return 0x06; };
  if val == 0xa6 { return 0x24; };
  if val == 0xa7 { return 0x5c; };
  if val == 0xa8 { return 0xc2; };
  if val == 0xa9 { return 0xd3; };
  if val == 0xaa { return 0xac; };
  if val == 0xab { return 0x62; };
  if val == 0xac { return 0x91; };
  if val == 0xad { return 0x95; };
  if val == 0xae { return 0xe4; };
  if val == 0xaf { return 0x79; };
  if val == 0xb0 { return 0xe7; };
  if val == 0xb1 { return 0xc8; };
  if val == 0xb2 { return 0x37; };
  if val == 0xb3 { return 0x6d; };
  if val == 0xb4 { return 0x8d; };
  if val == 0xb5 { return 0xd5; };
  if val == 0xb6 { return 0x4e; };
  if val == 0xb7 { return 0xa9; };
  if val == 0xb8 { return 0x6c; };
  if val == 0xb9 { return 0x56; };
  if val == 0xba { return 0xf4; };
  if val == 0xbb { return 0xea; };
  if val == 0xbc { return 0x65; };
  if val == 0xbd { return 0x7a; };
  if val == 0xbe { return 0xae; };
  if val == 0xbf { return 0x08; };
  if val == 0xc0 { return 0xba; };
  if val == 0xc1 { return 0x78; };
  if val == 0xc2 { return 0x25; };
  if val == 0xc3 { return 0x2e; };
  if val == 0xc4 { return 0x1c; };
  if val == 0xc5 { return 0xa6; };
  if val == 0xc6 { return 0xb4; };
  if val == 0xc7 { return 0xc6; };
  if val == 0xc8 { return 0xe8; };
  if val == 0xc9 { return 0xdd; };
  if val == 0xca { return 0x74; };
  if val == 0xcb { return 0x1f; };
  if val == 0xcc { return 0x4b; };
  if val == 0xcd { return 0xbd; };
  if val == 0xce { return 0x8b; };
  if val == 0xcf { return 0x8a; };
  if val == 0xd0 { return 0x70; };
  if val == 0xd1 { return 0x3e; };
  if val == 0xd2 { return 0xb5; };
  if val == 0xd3 { return 0x66; };
  if val == 0xd4 { return 0x48; };
  if val == 0xd5 { return 0x03; };
  if val == 0xd6 { return 0xf6; };
  if val == 0xd7 { return 0x0e; };
  if val == 0xd8 { return 0x61; };
  if val == 0xd9 { return 0x35; };
  if val == 0xda { return 0x57; };
  if val == 0xdb { return 0xb9; };
  if val == 0xdc { return 0x86; };
  if val == 0xdd { return 0xc1; };
  if val == 0xde { return 0x1d; };
  if val == 0xdf { return 0x9e; };
  if val == 0xe0 { return 0xe1; };
  if val == 0xe1 { return 0xf8; };
  if val == 0xe2 { return 0x98; };
  if val == 0xe3 { return 0x11; };
  if val == 0xe4 { return 0x69; };
  if val == 0xe5 { return 0xd9; };
  if val == 0xe6 { return 0x8e; };
  if val == 0xe7 { return 0x94; };
  if val == 0xe8 { return 0x9b; };
  if val == 0xe9 { return 0x1e; };
  if val == 0xea { return 0x87; };
  if val == 0xeb { return 0xe9; };
  if val == 0xec { return 0xce; };
  if val == 0xed { return 0x55; };
  if val == 0xee { return 0x28; };
  if val == 0xef { return 0xdf; };
  if val == 0xf0 { return 0x8c; };
  if val == 0xf1 { return 0xa1; };
  if val == 0xf2 { return 0x89; };
  if val == 0xf3 { return 0x0d; };
  if val == 0xf4 { return 0xbf; };
  if val == 0xf5 { return 0xe6; };
  if val == 0xf6 { return 0x42; };
  if val == 0xf7 { return 0x68; };
  if val == 0xf8 { return 0x41; };
  if val == 0xf9 { return 0x99; };
  if val == 0xfa { return 0x2d; };
  if val == 0xfb { return 0x0f; };
  if val == 0xfc { return 0xb0; };
  if val == 0xfd { return 0x54; };
  if val == 0xfe { return 0xbb; };
  if val == 0xff { return 0x16; };
  return 0;
}

pub fn aes_inv_sbox(b: Int) -> Int
  requires: b >= 0 && b <= 255
  ensures: result >= 0 && result <= 255
{
  var val = xiom.math.bit_and(b, 0xFF);
  if val == 0x00 { return 0x52; };
  if val == 0x01 { return 0x09; };
  if val == 0x02 { return 0x6a; };
  if val == 0x03 { return 0xd5; };
  if val == 0x04 { return 0x30; };
  if val == 0x05 { return 0x36; };
  if val == 0x06 { return 0xa5; };
  if val == 0x07 { return 0x38; };
  if val == 0x08 { return 0xbf; };
  if val == 0x09 { return 0x40; };
  if val == 0x0a { return 0xa3; };
  if val == 0x0b { return 0x9e; };
  if val == 0x0c { return 0x81; };
  if val == 0x0d { return 0xf3; };
  if val == 0x0e { return 0xd7; };
  if val == 0x0f { return 0xfb; };
  if val == 0x10 { return 0x7c; };
  if val == 0x11 { return 0xe3; };
  if val == 0x12 { return 0x39; };
  if val == 0x13 { return 0x82; };
  if val == 0x14 { return 0x9b; };
  if val == 0x15 { return 0x2f; };
  if val == 0x16 { return 0xff; };
  if val == 0x17 { return 0x87; };
  if val == 0x18 { return 0x34; };
  if val == 0x19 { return 0x8e; };
  if val == 0x1a { return 0x43; };
  if val == 0x1b { return 0x44; };
  if val == 0x1c { return 0xc4; };
  if val == 0x1d { return 0xde; };
  if val == 0x1e { return 0xe9; };
  if val == 0x1f { return 0xcb; };
  if val == 0x20 { return 0x54; };
  if val == 0x21 { return 0x7b; };
  if val == 0x22 { return 0x94; };
  if val == 0x23 { return 0x32; };
  if val == 0x24 { return 0xa6; };
  if val == 0x25 { return 0xc2; };
  if val == 0x26 { return 0x23; };
  if val == 0x27 { return 0x3d; };
  if val == 0x28 { return 0xee; };
  if val == 0x29 { return 0x4c; };
  if val == 0x2a { return 0x95; };
  if val == 0x2b { return 0x0b; };
  if val == 0x2c { return 0x42; };
  if val == 0x2d { return 0xfa; };
  if val == 0x2e { return 0xc3; };
  if val == 0x2f { return 0x4e; };
  if val == 0x30 { return 0x08; };
  if val == 0x31 { return 0x2e; };
  if val == 0x32 { return 0xa1; };
  if val == 0x33 { return 0x66; };
  if val == 0x34 { return 0x28; };
  if val == 0x35 { return 0xd9; };
  if val == 0x36 { return 0x24; };
  if val == 0x37 { return 0xb2; };
  if val == 0x38 { return 0x76; };
  if val == 0x39 { return 0x5b; };
  if val == 0x3a { return 0xa2; };
  if val == 0x3b { return 0x49; };
  if val == 0x3c { return 0x6d; };
  if val == 0x3d { return 0x8b; };
  if val == 0x3e { return 0xd1; };
  if val == 0x3f { return 0x25; };
  if val == 0x40 { return 0x72; };
  if val == 0x41 { return 0xf8; };
  if val == 0x42 { return 0xf6; };
  if val == 0x43 { return 0x64; };
  if val == 0x44 { return 0x86; };
  if val == 0x45 { return 0x68; };
  if val == 0x46 { return 0x98; };
  if val == 0x47 { return 0x16; };
  if val == 0x48 { return 0xd4; };
  if val == 0x49 { return 0xa4; };
  if val == 0x4a { return 0x5c; };
  if val == 0x4b { return 0xcc; };
  if val == 0x4c { return 0x5d; };
  if val == 0x4d { return 0x65; };
  if val == 0x4e { return 0xb6; };
  if val == 0x4f { return 0x92; };
  if val == 0x50 { return 0x6c; };
  if val == 0x51 { return 0x70; };
  if val == 0x52 { return 0x48; };
  if val == 0x53 { return 0x50; };
  if val == 0x54 { return 0xfd; };
  if val == 0x55 { return 0xed; };
  if val == 0x56 { return 0xb9; };
  if val == 0x57 { return 0xda; };
  if val == 0x58 { return 0x5e; };
  if val == 0x59 { return 0x15; };
  if val == 0x5a { return 0x46; };
  if val == 0x5b { return 0x57; };
  if val == 0x5c { return 0xa7; };
  if val == 0x5d { return 0x8d; };
  if val == 0x5e { return 0x9d; };
  if val == 0x5f { return 0x84; };
  if val == 0x60 { return 0x90; };
  if val == 0x61 { return 0xd8; };
  if val == 0x62 { return 0xab; };
  if val == 0x63 { return 0x00; };
  if val == 0x64 { return 0x8c; };
  if val == 0x65 { return 0xbc; };
  if val == 0x66 { return 0xd3; };
  if val == 0x67 { return 0x0a; };
  if val == 0x68 { return 0xf7; };
  if val == 0x69 { return 0xe4; };
  if val == 0x6a { return 0x58; };
  if val == 0x6b { return 0x05; };
  if val == 0x6c { return 0xb8; };
  if val == 0x6d { return 0xb3; };
  if val == 0x6e { return 0x45; };
  if val == 0x6f { return 0x06; };
  if val == 0x70 { return 0xd0; };
  if val == 0x71 { return 0x2c; };
  if val == 0x72 { return 0x1e; };
  if val == 0x73 { return 0x8f; };
  if val == 0x74 { return 0xca; };
  if val == 0x75 { return 0x3f; };
  if val == 0x76 { return 0x0f; };
  if val == 0x77 { return 0x02; };
  if val == 0x78 { return 0xc1; };
  if val == 0x79 { return 0xaf; };
  if val == 0x7a { return 0xbd; };
  if val == 0x7b { return 0x03; };
  if val == 0x7c { return 0x01; };
  if val == 0x7d { return 0x13; };
  if val == 0x7e { return 0x8a; };
  if val == 0x7f { return 0x6b; };
  if val == 0x80 { return 0x3a; };
  if val == 0x81 { return 0x91; };
  if val == 0x82 { return 0x11; };
  if val == 0x83 { return 0x41; };
  if val == 0x84 { return 0x4f; };
  if val == 0x85 { return 0x67; };
  if val == 0x86 { return 0xdc; };
  if val == 0x87 { return 0xea; };
  if val == 0x88 { return 0x97; };
  if val == 0x89 { return 0xf2; };
  if val == 0x8a { return 0xcf; };
  if val == 0x8b { return 0xce; };
  if val == 0x8c { return 0xf0; };
  if val == 0x8d { return 0xb4; };
  if val == 0x8e { return 0xe6; };
  if val == 0x8f { return 0x73; };
  if val == 0x90 { return 0x96; };
  if val == 0x91 { return 0xac; };
  if val == 0x92 { return 0x74; };
  if val == 0x93 { return 0x22; };
  if val == 0x94 { return 0xe7; };
  if val == 0x95 { return 0xad; };
  if val == 0x96 { return 0x35; };
  if val == 0x97 { return 0x85; };
  if val == 0x98 { return 0xe2; };
  if val == 0x99 { return 0xf9; };
  if val == 0x9a { return 0x37; };
  if val == 0x9b { return 0xe8; };
  if val == 0x9c { return 0x1c; };
  if val == 0x9d { return 0x75; };
  if val == 0x9e { return 0xdf; };
  if val == 0x9f { return 0x6e; };
  if val == 0xa0 { return 0x47; };
  if val == 0xa1 { return 0xf1; };
  if val == 0xa2 { return 0x1a; };
  if val == 0xa3 { return 0x71; };
  if val == 0xa4 { return 0x1d; };
  if val == 0xa5 { return 0x29; };
  if val == 0xa6 { return 0xc5; };
  if val == 0xa7 { return 0x89; };
  if val == 0xa8 { return 0x6f; };
  if val == 0xa9 { return 0xb7; };
  if val == 0xaa { return 0x62; };
  if val == 0xab { return 0x0e; };
  if val == 0xac { return 0xaa; };
  if val == 0xad { return 0x18; };
  if val == 0xae { return 0xbe; };
  if val == 0xaf { return 0x1b; };
  if val == 0xb0 { return 0xfc; };
  if val == 0xb1 { return 0x56; };
  if val == 0xb2 { return 0x3e; };
  if val == 0xb3 { return 0x4b; };
  if val == 0xb4 { return 0xc6; };
  if val == 0xb5 { return 0xd2; };
  if val == 0xb6 { return 0x79; };
  if val == 0xb7 { return 0x20; };
  if val == 0xb8 { return 0x9a; };
  if val == 0xb9 { return 0xdb; };
  if val == 0xba { return 0xc0; };
  if val == 0xbb { return 0xfe; };
  if val == 0xbc { return 0x78; };
  if val == 0xbd { return 0xcd; };
  if val == 0xbe { return 0x5a; };
  if val == 0xbf { return 0xf4; };
  if val == 0xc0 { return 0x1f; };
  if val == 0xc1 { return 0xdd; };
  if val == 0xc2 { return 0xa8; };
  if val == 0xc3 { return 0x33; };
  if val == 0xc4 { return 0x88; };
  if val == 0xc5 { return 0x07; };
  if val == 0xc6 { return 0xc7; };
  if val == 0xc7 { return 0x31; };
  if val == 0xc8 { return 0xb1; };
  if val == 0xc9 { return 0x12; };
  if val == 0xca { return 0x10; };
  if val == 0xcb { return 0x59; };
  if val == 0xcc { return 0x27; };
  if val == 0xcd { return 0x80; };
  if val == 0xce { return 0xec; };
  if val == 0xcf { return 0x5f; };
  if val == 0xd0 { return 0x60; };
  if val == 0xd1 { return 0x51; };
  if val == 0xd2 { return 0x7f; };
  if val == 0xd3 { return 0xa9; };
  if val == 0xd4 { return 0x19; };
  if val == 0xd5 { return 0xb5; };
  if val == 0xd6 { return 0x4a; };
  if val == 0xd7 { return 0x0d; };
  if val == 0xd8 { return 0x2d; };
  if val == 0xd9 { return 0xe5; };
  if val == 0xda { return 0x7a; };
  if val == 0xdb { return 0x9f; };
  if val == 0xdc { return 0x93; };
  if val == 0xdd { return 0xc9; };
  if val == 0xde { return 0x9c; };
  if val == 0xdf { return 0xef; };
  if val == 0xe0 { return 0xa0; };
  if val == 0xe1 { return 0xe0; };
  if val == 0xe2 { return 0x3b; };
  if val == 0xe3 { return 0x4d; };
  if val == 0xe4 { return 0xae; };
  if val == 0xe5 { return 0x2a; };
  if val == 0xe6 { return 0xf5; };
  if val == 0xe7 { return 0xb0; };
  if val == 0xe8 { return 0xc8; };
  if val == 0xe9 { return 0xeb; };
  if val == 0xea { return 0xbb; };
  if val == 0xeb { return 0x3c; };
  if val == 0xec { return 0x83; };
  if val == 0xed { return 0x53; };
  if val == 0xee { return 0x99; };
  if val == 0xef { return 0x61; };
  if val == 0xf0 { return 0x17; };
  if val == 0xf1 { return 0x2b; };
  if val == 0xf2 { return 0x04; };
  if val == 0xf3 { return 0x7e; };
  if val == 0xf4 { return 0xba; };
  if val == 0xf5 { return 0x77; };
  if val == 0xf6 { return 0xd6; };
  if val == 0xf7 { return 0x26; };
  if val == 0xf8 { return 0xe1; };
  if val == 0xf9 { return 0x69; };
  if val == 0xfa { return 0x14; };
  if val == 0xfb { return 0x63; };
  if val == 0xfc { return 0x55; };
  if val == 0xfd { return 0x21; };
  if val == 0xfe { return 0x0c; };
  if val == 0xff { return 0x7d; };
  return 0;
}

pub fn aes_rcon(round: Int) -> Int
  requires: round >= 1 && round <= 10
{
  if round == 1 { return 0x01; };
  if round == 2 { return 0x02; };
  if round == 3 { return 0x04; };
  if round == 4 { return 0x08; };
  if round == 5 { return 0x10; };
  if round == 6 { return 0x20; };
  if round == 7 { return 0x40; };
  if round == 8 { return 0x80; };
  if round == 9 { return 0x1b; };
  if round == 10 { return 0x36; };
  return 0;
}

fn aes_gf_mul2(input: GfInput) -> Int {
  var v = xiom.math.bit_and(input.val, 0xFF);
  var r = IntHolder{ val: xiom.math.bit_and(xiom.math.shl(v, 1), 0xFF) };
  var cond = xiom.math.bit_and(input.val, 0x80);
  if cond != 0 {
    r = IntHolder{ val: xiom.math.bit_xor(r.val, 0x1b) };
  };
  return r.val;
}

fn aes_gf_mul3(input: GfInput) -> Int {
  var v = xiom.math.bit_and(input.val, 0xFF);
  return xiom.math.bit_xor(aes_gf_mul2(input), v);
}

fn aes_gf_mul9(input: GfInput) -> Int {
  var v = xiom.math.bit_and(input.val, 0xFF);
  return xiom.math.bit_xor(
    aes_gf_mul2(GfInput{ val: aes_gf_mul2(GfInput{ val: aes_gf_mul2(input) }) }),
    v
  );
}

fn aes_gf_mul11(input: GfInput) -> Int {
  var v = xiom.math.bit_and(input.val, 0xFF);
  var x2v = aes_gf_mul2(input);
  var x4v = aes_gf_mul2(GfInput{ val: x2v });
  var x8v = aes_gf_mul2(GfInput{ val: x4v });
  return xiom.math.bit_xor(xiom.math.bit_xor(x8v, x2v), v);
}

fn aes_gf_mul13(input: GfInput) -> Int {
  var v = xiom.math.bit_and(input.val, 0xFF);
  var x2v = aes_gf_mul2(input);
  var x4v = aes_gf_mul2(GfInput{ val: x2v });
  var x8v = aes_gf_mul2(GfInput{ val: x4v });
  return xiom.math.bit_xor(xiom.math.bit_xor(x8v, x4v), v);
}

fn aes_gf_mul14(input: GfInput) -> Int {
  var x2v = aes_gf_mul2(input);
  var x4v = aes_gf_mul2(GfInput{ val: x2v });
  var x8v = aes_gf_mul2(GfInput{ val: x4v });
  return xiom.math.bit_xor(xiom.math.bit_xor(x8v, x4v), x2v);
}

fn aes_sub_bytes(state: AesState) -> AesState {
  return AesState{
    s00: aes_sbox(state.s00), s01: aes_sbox(state.s01), s02: aes_sbox(state.s02), s03: aes_sbox(state.s03),
    s10: aes_sbox(state.s10), s11: aes_sbox(state.s11), s12: aes_sbox(state.s12), s13: aes_sbox(state.s13),
    s20: aes_sbox(state.s20), s21: aes_sbox(state.s21), s22: aes_sbox(state.s22), s23: aes_sbox(state.s23),
    s30: aes_sbox(state.s30), s31: aes_sbox(state.s31), s32: aes_sbox(state.s32), s33: aes_sbox(state.s33),
  };
}

fn aes_inv_sub_bytes(state: AesState) -> AesState {
  return AesState{
    s00: aes_inv_sbox(state.s00), s01: aes_inv_sbox(state.s01), s02: aes_inv_sbox(state.s02), s03: aes_inv_sbox(state.s03),
    s10: aes_inv_sbox(state.s10), s11: aes_inv_sbox(state.s11), s12: aes_inv_sbox(state.s12), s13: aes_inv_sbox(state.s13),
    s20: aes_inv_sbox(state.s20), s21: aes_inv_sbox(state.s21), s22: aes_inv_sbox(state.s22), s23: aes_inv_sbox(state.s23),
    s30: aes_inv_sbox(state.s30), s31: aes_inv_sbox(state.s31), s32: aes_inv_sbox(state.s32), s33: aes_inv_sbox(state.s33),
  };
}

fn aes_shift_rows(state: AesState) -> AesState {
  return AesState{
    s00: state.s00, s01: state.s01, s02: state.s02, s03: state.s03,
    s10: state.s11, s11: state.s12, s12: state.s13, s13: state.s10,
    s20: state.s22, s21: state.s23, s22: state.s20, s23: state.s21,
    s30: state.s33, s31: state.s30, s32: state.s31, s33: state.s32,
  };
}

fn aes_inv_shift_rows(state: AesState) -> AesState {
  return AesState{
    s00: state.s00, s01: state.s01, s02: state.s02, s03: state.s03,
    s10: state.s13, s11: state.s10, s12: state.s11, s13: state.s12,
    s20: state.s22, s21: state.s23, s22: state.s20, s23: state.s21,
    s30: state.s31, s31: state.s32, s32: state.s33, s33: state.s30,
  };
}

fn aes_mix_single_column(col: AesCol) -> AesCol {
  var x0 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul2(GfInput{ val: col.b0 }), aes_gf_mul3(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(col.b2, col.b3)
  );
  var x1 = xiom.math.bit_xor(
    xiom.math.bit_xor(col.b0, aes_gf_mul2(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(aes_gf_mul3(GfInput{ val: col.b2 }), col.b3)
  );
  var x2 = xiom.math.bit_xor(
    xiom.math.bit_xor(col.b0, col.b1),
    xiom.math.bit_xor(aes_gf_mul2(GfInput{ val: col.b2 }), aes_gf_mul3(GfInput{ val: col.b3 }))
  );
  var x3 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul3(GfInput{ val: col.b0 }), col.b1),
    xiom.math.bit_xor(col.b2, aes_gf_mul2(GfInput{ val: col.b3 }))
  );
  return AesCol{ b0: x0, b1: x1, b2: x2, b3: x3 };
}

fn aes_mix_columns(state: AesState) -> AesState {
  var col0 = aes_mix_single_column(AesCol{ b0: state.s00, b1: state.s10, b2: state.s20, b3: state.s30 });
  var col1 = aes_mix_single_column(AesCol{ b0: state.s01, b1: state.s11, b2: state.s21, b3: state.s31 });
  var col2 = aes_mix_single_column(AesCol{ b0: state.s02, b1: state.s12, b2: state.s22, b3: state.s32 });
  var col3 = aes_mix_single_column(AesCol{ b0: state.s03, b1: state.s13, b2: state.s23, b3: state.s33 });
  return AesState{
    s00: col0.b0, s01: col1.b0, s02: col2.b0, s03: col3.b0,
    s10: col0.b1, s11: col1.b1, s12: col2.b1, s13: col3.b1,
    s20: col0.b2, s21: col1.b2, s22: col2.b2, s23: col3.b2,
    s30: col0.b3, s31: col1.b3, s32: col2.b3, s33: col3.b3,
  };
}

fn aes_inv_mix_single_column(col: AesCol) -> AesCol {
  var x0 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul14(GfInput{ val: col.b0 }), aes_gf_mul11(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(aes_gf_mul13(GfInput{ val: col.b2 }), aes_gf_mul9(GfInput{ val: col.b3 }))
  );
  var x1 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul9(GfInput{ val: col.b0 }), aes_gf_mul14(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(aes_gf_mul11(GfInput{ val: col.b2 }), aes_gf_mul13(GfInput{ val: col.b3 }))
  );
  var x2 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul13(GfInput{ val: col.b0 }), aes_gf_mul9(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(aes_gf_mul14(GfInput{ val: col.b2 }), aes_gf_mul11(GfInput{ val: col.b3 }))
  );
  var x3 = xiom.math.bit_xor(
    xiom.math.bit_xor(aes_gf_mul11(GfInput{ val: col.b0 }), aes_gf_mul13(GfInput{ val: col.b1 })),
    xiom.math.bit_xor(aes_gf_mul9(GfInput{ val: col.b2 }), aes_gf_mul14(GfInput{ val: col.b3 }))
  );
  return AesCol{ b0: x0, b1: x1, b2: x2, b3: x3 };
}

fn aes_inv_mix_columns(state: AesState) -> AesState {
  var col0 = aes_inv_mix_single_column(AesCol{ b0: state.s00, b1: state.s10, b2: state.s20, b3: state.s30 });
  var col1 = aes_inv_mix_single_column(AesCol{ b0: state.s01, b1: state.s11, b2: state.s21, b3: state.s31 });
  var col2 = aes_inv_mix_single_column(AesCol{ b0: state.s02, b1: state.s12, b2: state.s22, b3: state.s32 });
  var col3 = aes_inv_mix_single_column(AesCol{ b0: state.s03, b1: state.s13, b2: state.s23, b3: state.s33 });
  return AesState{
    s00: col0.b0, s01: col1.b0, s02: col2.b0, s03: col3.b0,
    s10: col0.b1, s11: col1.b1, s12: col2.b1, s13: col3.b1,
    s20: col0.b2, s21: col1.b2, s22: col2.b2, s23: col3.b2,
    s30: col0.b3, s31: col1.b3, s32: col2.b3, s33: col3.b3,
  };
}

fn aes_add_round_key(state: AesState, round_key: &Vec[Int], offset: Int) -> AesState {
  return AesState{
    s00: xiom.math.bit_xor(state.s00, round_key[offset]),
    s01: xiom.math.bit_xor(state.s01, round_key[offset + 1]),
    s02: xiom.math.bit_xor(state.s02, round_key[offset + 2]),
    s03: xiom.math.bit_xor(state.s03, round_key[offset + 3]),
    s10: xiom.math.bit_xor(state.s10, round_key[offset + 4]),
    s11: xiom.math.bit_xor(state.s11, round_key[offset + 5]),
    s12: xiom.math.bit_xor(state.s12, round_key[offset + 6]),
    s13: xiom.math.bit_xor(state.s13, round_key[offset + 7]),
    s20: xiom.math.bit_xor(state.s20, round_key[offset + 8]),
    s21: xiom.math.bit_xor(state.s21, round_key[offset + 9]),
    s22: xiom.math.bit_xor(state.s22, round_key[offset + 10]),
    s23: xiom.math.bit_xor(state.s23, round_key[offset + 11]),
    s30: xiom.math.bit_xor(state.s30, round_key[offset + 12]),
    s31: xiom.math.bit_xor(state.s31, round_key[offset + 13]),
    s32: xiom.math.bit_xor(state.s32, round_key[offset + 14]),
    s33: xiom.math.bit_xor(state.s33, round_key[offset + 15]),
  };
}

fn aes_key_expansion_128(key: &Vec[Int]) -> Vec[Int] {
  var expanded = Vec[Int].new();
  var i = 0;
  while i < 176 {
    expanded.push(0);
    i = i + 1;
  }

  i = 0;
  while i < 16 {
    expanded[i] = key[i];
    i = i + 1;
  }

  var ks = KeyExpState{ temp0: 0, temp1: 0, temp2: 0, temp3: 0, rcon_iteration: 1 };
  var bytes_generated = 16;

  while bytes_generated < 176 {
    ks = KeyExpState{
      temp0: expanded[bytes_generated - 4],
      temp1: expanded[bytes_generated - 3],
      temp2: expanded[bytes_generated - 2],
      temp3: expanded[bytes_generated - 1],
      rcon_iteration: ks.rcon_iteration,
    };

    if bytes_generated % 16 == 0 {
      ks = KeyExpState{
        temp0: xiom.math.bit_xor(aes_sbox(ks.temp1), aes_rcon(ks.rcon_iteration)),
        temp1: aes_sbox(ks.temp2),
        temp2: aes_sbox(ks.temp3),
        temp3: aes_sbox(ks.temp0),
        rcon_iteration: ks.rcon_iteration + 1,
      };
    };

    expanded[bytes_generated] = xiom.math.bit_xor(expanded[bytes_generated - 16], ks.temp0);
    expanded[bytes_generated + 1] = xiom.math.bit_xor(expanded[bytes_generated - 15], ks.temp1);
    expanded[bytes_generated + 2] = xiom.math.bit_xor(expanded[bytes_generated - 14], ks.temp2);
    expanded[bytes_generated + 3] = xiom.math.bit_xor(expanded[bytes_generated - 13], ks.temp3);

    bytes_generated = bytes_generated + 4;
  }

  return expanded;
}

fn aes_key_expansion_256(key: &Vec[Int]) -> Vec[Int] {
  var expanded = Vec[Int].new();
  var i = 0;
  while i < 240 {
    expanded.push(0);
    i = i + 1;
  }

  i = 0;
  while i < 32 {
    expanded[i] = key[i];
    i = i + 1;
  }

  var ks = KeyExpState{ temp0: 0, temp1: 0, temp2: 0, temp3: 0, rcon_iteration: 1 };
  var bytes_generated = 32;

  while bytes_generated < 240 {
    ks = KeyExpState{
      temp0: expanded[bytes_generated - 4],
      temp1: expanded[bytes_generated - 3],
      temp2: expanded[bytes_generated - 2],
      temp3: expanded[bytes_generated - 1],
      rcon_iteration: ks.rcon_iteration,
    };

    if bytes_generated % 32 == 0 {
      ks = KeyExpState{
        temp0: xiom.math.bit_xor(aes_sbox(ks.temp1), aes_rcon(ks.rcon_iteration)),
        temp1: aes_sbox(ks.temp2),
        temp2: aes_sbox(ks.temp3),
        temp3: aes_sbox(ks.temp0),
        rcon_iteration: ks.rcon_iteration + 1,
      };
    }
    elif bytes_generated % 32 == 16 {
      ks = KeyExpState{
        temp0: aes_sbox(ks.temp0),
        temp1: aes_sbox(ks.temp1),
        temp2: aes_sbox(ks.temp2),
        temp3: aes_sbox(ks.temp3),
        rcon_iteration: ks.rcon_iteration,
      };
    };

    expanded[bytes_generated] = xiom.math.bit_xor(expanded[bytes_generated - 32], ks.temp0);
    expanded[bytes_generated + 1] = xiom.math.bit_xor(expanded[bytes_generated - 31], ks.temp1);
    expanded[bytes_generated + 2] = xiom.math.bit_xor(expanded[bytes_generated - 30], ks.temp2);
    expanded[bytes_generated + 3] = xiom.math.bit_xor(expanded[bytes_generated - 29], ks.temp3);

    bytes_generated = bytes_generated + 4;
  }

  return expanded;
}

fn state_from_vec(input: &Vec[Int]) -> AesState {
  return AesState{
    s00: input[0], s01: input[4], s02: input[8],  s03: input[12],
    s10: input[1], s11: input[5], s12: input[9],  s13: input[13],
    s20: input[2], s21: input[6], s22: input[10], s23: input[14],
    s30: input[3], s31: input[7], s32: input[11], s33: input[15],
  };
}

fn state_to_vec(state: AesState) -> Vec[Int] {
  var result = Vec[Int].new();
  result.push(state.s00);
  result.push(state.s10);
  result.push(state.s20);
  result.push(state.s30);
  result.push(state.s01);
  result.push(state.s11);
  result.push(state.s21);
  result.push(state.s31);
  result.push(state.s02);
  result.push(state.s12);
  result.push(state.s22);
  result.push(state.s32);
  result.push(state.s03);
  result.push(state.s13);
  result.push(state.s23);
  result.push(state.s33);
  return result;
}

fn aes_encrypt_block(input: &Vec[Int], round_keys: &Vec[Int], rounds: Int) -> Vec[Int] {
  var h = StateHolder{ s: state_from_vec(input) };

  h = StateHolder{ s: aes_add_round_key(h.s, round_keys, 0) };

  var round = 1;
  while round < rounds {
    h = StateHolder{ s: aes_sub_bytes(h.s) };
    h = StateHolder{ s: aes_shift_rows(h.s) };
    h = StateHolder{ s: aes_mix_columns(h.s) };
    h = StateHolder{ s: aes_add_round_key(h.s, round_keys, round * 16) };
    round = round + 1;
  }

  h = StateHolder{ s: aes_sub_bytes(h.s) };
  h = StateHolder{ s: aes_shift_rows(h.s) };
  h = StateHolder{ s: aes_add_round_key(h.s, round_keys, rounds * 16) };

  return state_to_vec(h.s);
}

fn aes_decrypt_block(input: &Vec[Int], round_keys: &Vec[Int], rounds: Int) -> Vec[Int] {
  var h = StateHolder{ s: state_from_vec(input) };

  h = StateHolder{ s: aes_add_round_key(h.s, round_keys, rounds * 16) };

  var round = rounds - 1;
  while round > 0 {
    h = StateHolder{ s: aes_inv_shift_rows(h.s) };
    h = StateHolder{ s: aes_inv_sub_bytes(h.s) };
    h = StateHolder{ s: aes_add_round_key(h.s, round_keys, round * 16) };
    h = StateHolder{ s: aes_inv_mix_columns(h.s) };
    round = round - 1;
  }

  h = StateHolder{ s: aes_inv_shift_rows(h.s) };
  h = StateHolder{ s: aes_inv_sub_bytes(h.s) };
  h = StateHolder{ s: aes_add_round_key(h.s, round_keys, 0) };

  return state_to_vec(h.s);
}

pub fn aes128_encrypt(plaintext: &Vec[Int], key: &Vec[Int]) -> Result[Vec[Int], Str]
  requires: plaintext.len() == 16
  requires: key.len() == 16
  ensures: result is Ok => result.len() == 16
{
  if key.len() != 16 {
    return Err("aes128: key must be 16 bytes");
  };
  if plaintext.len() != 16 {
    return Err("aes128: plaintext must be 16 bytes (single block ECB)");
  };

  var round_keys = aes_key_expansion_128(key);
  var result = aes_encrypt_block(plaintext, &round_keys, 10);
  return Ok(result);
}

pub fn aes128_decrypt(ciphertext: &Vec[Int], key: &Vec[Int]) -> Result[Vec[Int], Str]
  requires: ciphertext.len() == 16
  requires: key.len() == 16
{
  if key.len() != 16 {
    return Err("aes128: key must be 16 bytes");
  };
  if ciphertext.len() != 16 {
    return Err("aes128: ciphertext must be 16 bytes (single block ECB)");
  };

  var round_keys = aes_key_expansion_128(key);
  var result = aes_decrypt_block(ciphertext, &round_keys, 10);
  return Ok(result);
}

pub fn aes256_encrypt(plaintext: &Vec[Int], key: &Vec[Int]) -> Result[Vec[Int], Str]
  requires: plaintext.len() == 16
  requires: key.len() == 32
{
  if key.len() != 32 {
    return Err("aes256: key must be 32 bytes");
  };
  if plaintext.len() != 16 {
    return Err("aes256: plaintext must be 16 bytes (single block ECB)");
  };

  var round_keys = aes_key_expansion_256(key);
  var result = aes_encrypt_block(plaintext, &round_keys, 14);
  return Ok(result);
}

pub fn aes256_decrypt(ciphertext: &Vec[Int], key: &Vec[Int]) -> Result[Vec[Int], Str]
  requires: ciphertext.len() == 16
  requires: key.len() == 32
{
  if key.len() != 32 {
    return Err("aes256: key must be 32 bytes");
  };
  if ciphertext.len() != 16 {
    return Err("aes256: ciphertext must be 16 bytes (single block ECB)");
  };

  var round_keys = aes_key_expansion_256(key);
  var result = aes_decrypt_block(ciphertext, &round_keys, 14);
  return Ok(result);
}
