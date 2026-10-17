// XIOM ORBITDB -- free-space map model soak.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Randomized register/use/release/find against a flat reference model,
// checking: use/release return codes, clamping, invariants after every 500
// ops, best-fit placement (tightest page, lowest id on ties), and totals.
//
// Env:
//   ORBITDB_FSM_PAGES  pages to register   (default 64)
//   ORBITDB_FSM_OPS    operations          (default 20000)
//   ORBITDB_FSM_SEED   RNG seed            (default 12345)
//
// Exit: 0 green; 1..N = first mismatch class.

module orbitdb_probe_fsm

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.storage.free_space_map;

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  var pages = 64;
  var ops = 20000;
  var seed = 12345;
  match parse.parse_int(env.var_or("ORBITDB_FSM_PAGES", "64")) {
    Ok(v) => { if v > 0 { pages = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_FSM_OPS", "20000")) {
    Ok(v) => { if v > 0 { ops = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_FSM_SEED", "12345")) {
    Ok(v) => { seed = v; }
    Err(_) => {}
  }

  var fsm = free_space_map_new();
  var ids = Vec[PageId].new();
  var free = Vec[Int].new();
  var cap = Vec[Int].new();
  var i = 0;
  while i < pages {
    let c = 512 + ((i * 64) % 4096);
    let pid = fsm_register_page(&mut fsm, c);
    ids.push(pid);
    free.push(c);
    cap.push(c);
    i = i + 1;
  }
  if fsm_page_count(&fsm) != pages { return 1; }
  if !fsm_validate(&fsm) { return 2; }

  var state = seed;
  var step = 0;
  while step < ops {
    let p = rand_next(&mut state) % pages;
    let action = rand_next(&mut state) % 10;

    if action < 4 {
      // use
      let amount = rand_next(&mut state) % (cap[p] + 1);
      let expected_ok = amount <= free[p];
      let got = fsm_record_used(&mut fsm, &ids[p], amount);
      if got != expected_ok {
        io.println("MISMATCH use op=" + convert.int_to_string(step) + " p=" + convert.int_to_string(p));
        return 3;
      }
      if expected_ok {
        free[p] = free[p] - amount;
      } else {
        free[p] = 0;
      }
    } elif action < 7 {
      // release
      let amount = rand_next(&mut state) % (cap[p] + 1);
      let got = fsm_record_free(&mut fsm, &ids[p], amount);
      if !got {
        io.println("MISMATCH release op=" + convert.int_to_string(step));
        return 4;
      }
      var nv = free[p] + amount;
      if nv > cap[p] { nv = cap[p]; }
      free[p] = nv;
    } else {
      // find (best-fit model)
      let need = rand_next(&mut state) % 4097;
      var best = -1;
      var best_free = 0;
      var j = 0;
      while j < pages {
        if free[j] >= need {
          if best < 0 || free[j] < best_free {
            best = j;
            best_free = free[j];
          }
        }
        j = j + 1;
      }
      let got = fsm_find_page(&fsm, need);
      match got {
        None => {
          if best >= 0 {
            io.println("MISMATCH find-none op=" + convert.int_to_string(step) + " need=" + convert.int_to_string(need));
            return 5;
          }
        }
        Some(gid) => {
          if best < 0 {
            io.println("MISMATCH find-some op=" + convert.int_to_string(step) + " need=" + convert.int_to_string(need));
            return 6;
          }
          if gid.value != best {
            io.println("MISMATCH find-fit op=" + convert.int_to_string(step) + " got=" + convert.int_to_string(gid.value) + " want=" + convert.int_to_string(best));
            return 7;
          }
        }
      }
    }

    if step % 500 == 499 {
      if !fsm_validate(&fsm) {
        io.println("MISMATCH validate op=" + convert.int_to_string(step));
        return 8;
      }
    }
    step = step + 1;
  }

  // Totals and free/capacity getters.
  var model_total = 0;
  i = 0;
  while i < pages {
    model_total = model_total + free[i];
    if fsm_free_bytes(&fsm, &ids[i]) != free[i] {
      io.println("MISMATCH free-bytes p=" + convert.int_to_string(i));
      return 9;
    }
    if fsm_capacity_of(&fsm, &ids[i]) != cap[i] {
      io.println("MISMATCH capacity p=" + convert.int_to_string(i));
      return 10;
    }
    i = i + 1;
  }
  if fsm_total_free(&fsm) != model_total {
    io.println("MISMATCH total-free got=" + convert.int_to_string(fsm_total_free(&fsm)) + " want=" + convert.int_to_string(model_total));
    return 11;
  }
  if !fsm_validate(&fsm) { return 12; }

  show("fsm.pages", pages);
  show("fsm.ops", ops);
  show("fsm.total_free", model_total);
  io.println("fsm: OK pages=" + convert.int_to_string(pages) + " ops=" + convert.int_to_string(ops));
  return 0;
}
