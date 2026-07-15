module xiom.sqlite.migration

use xiom.sqlite.types;
use xiom.sqlite.connection;

pub type Migration = {
  version: Int;
  name: Str;
  up_sql: Str;
  down_sql: Str;
}

fn clone_migration(m: &Migration) -> Migration {
  return Migration{
    version: m.version,
    name: m.name,
    up_sql: m.up_sql,
    down_sql: m.down_sql,
  };
}

pub type MigrationManager = {
  migrations: Vec[Migration];
  current_version: Int;
} derive[Clone]

pub fn Migration.new(version: Int, name: Str, up: Str, down: Str) -> Migration {
  return Migration{
    version: version,
    name: name,
    up_sql: up,
    down_sql: down,
  };
}

pub fn Migration.version(m: &Migration) -> Int {
  return m.version;
}

pub fn Migration.name(m: &Migration) -> Str {
  return m.name;
}

pub fn MigrationManager.new() -> MigrationManager {
  var migs = Vec[Migration].new();
  return MigrationManager{ migrations: migs, current_version: 0 };
}

pub fn MigrationManager.add(mgr: &mut MigrationManager, migration: Migration) {
  mgr.migrations.push(migration);
}

pub fn MigrationManager.count(mgr: &MigrationManager) -> Int {
  return mgr.migrations.len();
}

pub fn MigrationManager.version(mgr: &MigrationManager) -> Int {
  return mgr.current_version;
}

pub fn MigrationManager.pending(mgr: &MigrationManager) -> Vec[Migration] {
  var pending = Vec[Migration].new();
  var i = 0;
  while i < mgr.migrations.len() {
    if mgr.migrations[i].version > mgr.current_version {
      pending.push(clone_migration(&mgr.migrations[i]));
    }
    i = i + 1;
  }
  return pending;
}

pub fn MigrationManager.sort(mgr: &mut MigrationManager) {
  var i = 0;
  while i < mgr.migrations.len() {
    var j = i + 1;
    while j < mgr.migrations.len() {
      if mgr.migrations[j].version < mgr.migrations[i].version {
        var tmp = clone_migration(&mgr.migrations[i]);
        mgr.migrations[i] = clone_migration(&mgr.migrations[j]);
        mgr.migrations[j] = tmp;
      }
      j = j + 1;
    }
    i = i + 1;
  }
}

pub fn MigrationManager.up(mgr: &mut MigrationManager, conn: &SqliteConnection) -> Result[Int, SqliteError] {
  var ran = 0;
  MigrationManager.sort(mgr);
  var pending = MigrationManager.pending(mgr);
  var i = 0;
  while i < pending.len() {
    var m = pending[i];
    if m.up_sql == "" {
      return Err(SqliteError{
        code: -1,
        message: "Migration " + m.name + " has empty up_sql",
      });
    }
    var result = sqlite_execute(conn, m.up_sql);
    match result {
      Ok(_) => {
        mgr.current_version = m.version;
        ran = ran + 1;
      }
      Err(e) => {
        return Err(e);
      }
    }
    i = i + 1;
  }
  return Ok(ran);
}

pub fn MigrationManager.down(mgr: &mut MigrationManager, conn: &SqliteConnection, steps: Int) -> Result[Int, SqliteError] {
  if steps <= 0 { return Ok(0); }
  if mgr.migrations.len() == 0 { return Ok(0); }
  MigrationManager.sort(mgr);
  var rolled = 0;
  var applied = Vec[Migration].new();
  var i = 0;
  while i < mgr.migrations.len() {
    if mgr.migrations[i].version <= mgr.current_version {
      applied.push(clone_migration(&mgr.migrations[i]));
    }
    i = i + 1;
  }
  var idx = applied.len();
  while idx > 0 {
    if rolled >= steps {
      break;
    }
    idx = idx - 1;
    var m = clone_migration(&applied[idx]);
    if m.down_sql == "" {
      return Err(SqliteError{
        code: -1,
        message: "Migration " + m.name + " has empty down_sql",
      });
    }
    var result = sqlite_execute(conn, m.down_sql);
    match result {
      Ok(_) => {
        mgr.current_version = m.version - 1;
        rolled = rolled + 1;
      }
      Err(e) => {
        return Err(e);
      }
    }
  }
  return Ok(rolled);
}

pub fn MigrationManager.status(mgr: &MigrationManager) -> Int {
  return mgr.current_version;
}

pub fn migration_new(version: Int, name: Str, up: Str, down: Str) -> Migration {
  return Migration.new(version, name, up, down);
}

pub fn migration_manager_new() -> MigrationManager {
  return MigrationManager.new();
}

pub fn migration_manager_add(mgr: &mut MigrationManager, migration: Migration) {
  MigrationManager.add(mgr, migration);
}

pub fn migration_manager_up(mgr: &mut MigrationManager, conn: &SqliteConnection) -> Result[Int, SqliteError] {
  return MigrationManager.up(mgr, conn);
}

pub fn migration_manager_down(mgr: &mut MigrationManager, conn: &SqliteConnection, steps: Int) -> Result[Int, SqliteError] {
  return MigrationManager.down(mgr, conn, steps);
}

pub fn migration_manager_status(mgr: &MigrationManager) -> Int {
  return MigrationManager.status(mgr);
}
