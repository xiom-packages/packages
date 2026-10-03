// Enum payload structs with `Str` fields -- v0.62.3 corruption probe.
//
// Found while restoring `xiom.graphql`: `GraphQLSelection.Field(selection)`
// payloads lose their `Str` fields when read through a match binding
// (`x.name` reads empty or garbage), so the query validator could never
// find a field by name. `Vec[StructType]` element `Str` reads are correct.
//
// The simple payload shape (Str + Int, with and without derive[Clone])
// already passes; this probe mirrors the recursive
// payload -> nested struct -> Vec[enum] shape of the graphql types.
//
// Expected after the fix: `int=ok`, `str=ok`, `bad=0`, exit 0.
// On v0.62.3: prints `str=corrupt` (bad >= 1); never print the corrupt
// `Str` directly (it can be a garbage pointer) -- only status strings.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module enum_payload_str_probe

use xiom.io;
use xiom.convert;
use xiom.string.compare;

pub enum Wrap {
  Has(inner: Inner),
  Other(dummy: Int),
}

pub type Inner = {
  name: Str;
  alias: Str;
  n: Int;
  child: Set;
}

pub type Set = {
  items: Vec[Wrap];
}

pub type Op = {
  name: Str;
  set: Set;
}

pub fn add_field(op: &mut Op, w: Wrap) {
  op.set.items.push(w);
}

fn main() -> Int {
  var bad = 0;

  var empty_set = Set{ items: Vec[Wrap].new() };
  var op = Op{ name: "x", set: empty_set };
  var inner = Inner{ name: "hello", alias: "", n: 7, child: Set{ items: Vec[Wrap].new() } };
  var w = Wrap.Has(inner);
  add_field(&mut op, w);

  match op.set.items[0] {
    Wrap.Has(x) => {
      if x.n == 7 {
        io.println("int=ok");
      } else {
        io.println("int=corrupt");
        bad = bad + 1;
      }
      if compare.str_compare(x.name, "hello") == 0 {
        io.println("str=ok");
      } else {
        io.println("str=corrupt");
        bad = bad + 1;
      }
    },
    Wrap.Other(_) => {
      io.println("arm=wrong");
      bad = bad + 1;
    },
  };

  io.println("bad=" + int_to_string(bad));
  return bad;
}
