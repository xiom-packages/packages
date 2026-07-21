// XIOM — SQL Library
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.sql

pub type Database = {
  handle: Int;
  path: Str;
} derive[Clone]

pub fn open(path: Str) -> Database
  requires: path.len() > 0 {
  return Database{ handle: 0, path: path };
}

pub fn execute(db: &Database, sql: Str) -> Int
  requires: sql.len() > 0 {
  return 0; // MVP stub
}

pub fn close(db: &Database) -> Int
  requires: db.handle >= 0 {
  return 0; // MVP stub
}
