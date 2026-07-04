// XIOM — SQL Library
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.sql {

pub type Database = {
  handle: Int;
  path: Str;
} derive[Clone]

pub fn open(path: Str) -> Database {
  return Database{ handle: 0, path: path };
}

pub fn execute(db: &Database, sql: Str) -> Int {
  return 0; // MVP stub
}

pub fn close(db: &Database) -> Int {
  return 0; // MVP stub
}

}
