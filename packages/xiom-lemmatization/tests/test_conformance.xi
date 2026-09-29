// XIOM -- xiom.lemmatization conformance tests (44 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every check calls the public API directly (no fn tables). All Str equality
// goes through xiom.string.compare.str_compare, and vector elements are read
// through a bounds-checked helper.

module lemmatization_tests
use xiom.io; use xiom.test; use xiom.lemmatization;
use xiom.string.compare;

fn eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn elem_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let e: Str = v[i];
  return compare.str_compare(e, want) == 0;
}

fn t01_irregular_nouns() -> TestResult {
  var ok = eq(lemmatize("men", "n"), "man");
  if !eq(lemmatize("women", "n"), "woman") { ok = false; }
  if !eq(lemmatize("children", "n"), "child") { ok = false; }
  if !eq(lemmatize("teeth", "n"), "tooth") { ok = false; }
  if !eq(lemmatize("feet", "n"), "foot") { ok = false; }
  if !eq(lemmatize("mice", "n"), "mouse") { ok = false; }
  if !eq(lemmatize("geese", "n"), "goose") { ok = false; }
  if !eq(lemmatize("people", "n"), "person") { ok = false; }
  return assert(ok, "irregular nouns map to their singular");
}

fn t02_irregular_verbs_be() -> TestResult {
  var ok = eq(lemmatize("was", "v"), "be");
  if !eq(lemmatize("were", "v"), "be") { ok = false; }
  if !eq(lemmatize("is", "v"), "be") { ok = false; }
  if !eq(lemmatize("are", "v"), "be") { ok = false; }
  if !eq(lemmatize("am", "v"), "be") { ok = false; }
  if !eq(lemmatize("been", "v"), "be") { ok = false; }
  return assert(ok, "irregular verb 'to be' forms map to be");
}

fn t03_irregular_verbs_have_do_go() -> TestResult {
  var ok = eq(lemmatize("had", "v"), "have");
  if !eq(lemmatize("has", "v"), "have") { ok = false; }
  if !eq(lemmatize("did", "v"), "do") { ok = false; }
  if !eq(lemmatize("done", "v"), "do") { ok = false; }
  if !eq(lemmatize("does", "v"), "do") { ok = false; }
  if !eq(lemmatize("went", "v"), "go") { ok = false; }
  if !eq(lemmatize("gone", "v"), "go") { ok = false; }
  if !eq(lemmatize("goes", "v"), "go") { ok = false; }
  return assert(ok, "irregular have/do/go forms map to their base");
}

fn t04_irregular_verbs_strong() -> TestResult {
  var ok = eq(lemmatize("ran", "v"), "run");
  if !eq(lemmatize("saw", "v"), "see") { ok = false; }
  if !eq(lemmatize("seen", "v"), "see") { ok = false; }
  if !eq(lemmatize("ate", "v"), "eat") { ok = false; }
  if !eq(lemmatize("eaten", "v"), "eat") { ok = false; }
  if !eq(lemmatize("came", "v"), "come") { ok = false; }
  if !eq(lemmatize("gave", "v"), "give") { ok = false; }
  if !eq(lemmatize("took", "v"), "take") { ok = false; }
  return assert(ok, "strong verb past forms map to their base");
}

fn t05_irregular_verbs_irregular_pairs() -> TestResult {
  var ok = eq(lemmatize("wrote", "v"), "write");
  if !eq(lemmatize("written", "v"), "write") { ok = false; }
  if !eq(lemmatize("taken", "v"), "take") { ok = false; }
  if !eq(lemmatize("spoke", "v"), "speak") { ok = false; }
  if !eq(lemmatize("spoken", "v"), "speak") { ok = false; }
  if !eq(lemmatize("chose", "v"), "choose") { ok = false; }
  if !eq(lemmatize("chosen", "v"), "choose") { ok = false; }
  if !eq(lemmatize("drove", "v"), "drive") { ok = false; }
  if !eq(lemmatize("driven", "v"), "drive") { ok = false; }
  return assert(ok, "strong verb pairs map to their base");
}

fn t06_irregular_adjectives() -> TestResult {
  var ok = eq(lemmatize("better", "a"), "good");
  if !eq(lemmatize("best", "a"), "good") { ok = false; }
  if !eq(lemmatize("worse", "a"), "bad") { ok = false; }
  if !eq(lemmatize("worst", "a"), "bad") { ok = false; }
  if !eq(lemmatize("further", "a"), "far") { ok = false; }
  if !eq(lemmatize("most", "a"), "much") { ok = false; }
  if !eq(lemmatize("least", "a"), "little") { ok = false; }
  return assert(ok, "irregular comparatives/superlatives map to positive");
}

fn t07_irregular_pos_scope() -> TestResult {
  var ok = eq(lemmatize("lives", "n"), "life");
  if !eq(lemmatize("lives", "v"), "live") { ok = false; }
  if !eq(lemmatize("leaves", "n"), "leaf") { ok = false; }
  if !eq(lemmatize("leaves", "v"), "leave") { ok = false; }
  return assert(ok, "irregular tables are POS-scoped (lives/leaves)");
}

fn t08_noun_ies() -> TestResult {
  var ok = eq(lemmatize("stories", "n"), "story");
  if !eq(lemmatize("ponies", "n"), "pony") { ok = false; }
  if !eq(lemmatize("parties", "n"), "party") { ok = false; }
  if !eq(lemmatize("cities", "n"), "city") { ok = false; }
  if !eq(lemmatize("babies", "n"), "baby") { ok = false; }
  if !eq(lemmatize("armies", "n"), "army") { ok = false; }
  return assert(ok, "noun -ies -> -y");
}

fn t09_noun_ies_exceptions() -> TestResult {
  var ok = eq(lemmatize("movies", "n"), "movie");
  if !eq(lemmatize("cookies", "n"), "cookie") { ok = false; }
  if !eq(lemmatize("series", "n"), "series") { ok = false; }
  if !eq(lemmatize("species", "n"), "species") { ok = false; }
  if !eq(lemmatize("pies", "n"), "pie") { ok = false; }
  return assert(ok, "exception dictionary wins over -ies");
}

fn t10_noun_ves() -> TestResult {
  var ok = eq(lemmatize("knives", "n"), "knife");
  if !eq(lemmatize("wolves", "n"), "wolf") { ok = false; }
  if !eq(lemmatize("leaves", "n"), "leaf") { ok = false; }
  if !eq(lemmatize("shelves", "n"), "shelf") { ok = false; }
  if !eq(lemmatize("curves", "n"), "curve") { ok = false; }
  if !eq(lemmatize("caves", "n"), "cave") { ok = false; }
  return assert(ok, "known -ves plurals to -f/-fe, others drop -s");
}

fn t11_noun_sibilant_es() -> TestResult {
  var ok = eq(lemmatize("churches", "n"), "church");
  if !eq(lemmatize("dishes", "n"), "dish") { ok = false; }
  if !eq(lemmatize("glasses", "n"), "glass") { ok = false; }
  if !eq(lemmatize("boxes", "n"), "box") { ok = false; }
  if !eq(lemmatize("buzzes", "n"), "buzz") { ok = false; }
  if !eq(lemmatize("kisses", "n"), "kiss") { ok = false; }
  return assert(ok, "noun -es after sibilants is removed");
}

fn t12_noun_oes() -> TestResult {
  var ok = eq(lemmatize("heroes", "n"), "hero");
  if !eq(lemmatize("potatoes", "n"), "potato") { ok = false; }
  if !eq(lemmatize("tomatoes", "n"), "tomato") { ok = false; }
  if !eq(lemmatize("shoes", "n"), "shoe") { ok = false; }
  if !eq(lemmatize("toes", "n"), "toe") { ok = false; }
  if !eq(lemmatize("canoes", "n"), "canoe") { ok = false; }
  return assert(ok, "noun -oes: known -o plurals, otherwise drop -s");
}

fn t13_noun_generic_s() -> TestResult {
  var ok = eq(lemmatize("cats", "n"), "cat");
  if !eq(lemmatize("dogs", "n"), "dog") { ok = false; }
  if !eq(lemmatize("houses", "n"), "house") { ok = false; }
  if !eq(lemmatize("tables", "n"), "table") { ok = false; }
  if !eq(lemmatize("cars", "n"), "car") { ok = false; }
  if !eq(lemmatize("books", "n"), "book") { ok = false; }
  return assert(ok, "noun plural -s is removed");
}

fn t14_noun_guards() -> TestResult {
  var ok = eq(lemmatize("glass", "n"), "glass");
  if !eq(lemmatize("bus", "n"), "bus") { ok = false; }
  if !eq(lemmatize("status", "n"), "status") { ok = false; }
  if !eq(lemmatize("analysis", "n"), "analysis") { ok = false; }
  if !eq(lemmatize("news", "n"), "news") { ok = false; }
  if !eq(lemmatize("gas", "n"), "gas") { ok = false; }
  return assert(ok, "noun guards: -ss, -us, -is, and dictionary forms stay");
}

fn t15_noun_ses_irregular() -> TestResult {
  var ok = eq(lemmatize("analyses", "n"), "analysis");
  if !eq(lemmatize("crises", "n"), "crisis") { ok = false; }
  if !eq(lemmatize("theses", "n"), "thesis") { ok = false; }
  if !eq(lemmatize("hypotheses", "n"), "hypothesis") { ok = false; }
  return assert(ok, "irregular -ses plurals map to -sis");
}

fn t16_verb_ies() -> TestResult {
  var ok = eq(lemmatize("studies", "v"), "study");
  if !eq(lemmatize("tries", "v"), "try") { ok = false; }
  if !eq(lemmatize("carries", "v"), "carry") { ok = false; }
  if !eq(lemmatize("flies", "v"), "fly") { ok = false; }
  if !eq(lemmatize("cries", "v"), "cry") { ok = false; }
  if !eq(lemmatize("applies", "v"), "apply") { ok = false; }
  return assert(ok, "verb 3rd-person -ies -> -y");
}

fn t17_verb_ies_exceptions() -> TestResult {
  var ok = eq(lemmatize("dies", "v"), "die");
  if !eq(lemmatize("ties", "v"), "tie") { ok = false; }
  if !eq(lemmatize("lies", "v"), "lie") { ok = false; }
  if !eq(lemmatize("vies", "v"), "vie") { ok = false; }
  if !eq(lemmatize("spies", "v"), "spy") { ok = false; }
  return assert(ok, "verb -ies honors the exception dictionary");
}

fn t18_verb_ing_basic() -> TestResult {
  var ok = eq(lemmatize("walking", "v"), "walk");
  if !eq(lemmatize("reading", "v"), "read") { ok = false; }
  if !eq(lemmatize("playing", "v"), "play") { ok = false; }
  if !eq(lemmatize("studying", "v"), "study") { ok = false; }
  if !eq(lemmatize("singing", "v"), "sing") { ok = false; }
  if !eq(lemmatize("bringing", "v"), "bring") { ok = false; }
  if !eq(lemmatize("going", "v"), "go") { ok = false; }
  if !eq(lemmatize("being", "v"), "be") { ok = false; }
  return assert(ok, "verb -ing removal with base guards");
}

fn t19_verb_ing_double() -> TestResult {
  var ok = eq(lemmatize("running", "v"), "run");
  if !eq(lemmatize("hopping", "v"), "hop") { ok = false; }
  if !eq(lemmatize("stopping", "v"), "stop") { ok = false; }
  if !eq(lemmatize("planning", "v"), "plan") { ok = false; }
  if !eq(lemmatize("sitting", "v"), "sit") { ok = false; }
  if !eq(lemmatize("beginning", "v"), "begin") { ok = false; }
  return assert(ok, "verb -ing drops one doubled consonant");
}

fn t20_verb_ing_lsz() -> TestResult {
  var ok = eq(lemmatize("falling", "v"), "fall");
  if !eq(lemmatize("calling", "v"), "call") { ok = false; }
  if !eq(lemmatize("passing", "v"), "pass") { ok = false; }
  if !eq(lemmatize("buzzing", "v"), "buzz") { ok = false; }
  if !eq(lemmatize("telling", "v"), "tell") { ok = false; }
  return assert(ok, "verb -ing keeps a final double l/s/z");
}

fn t21_verb_ing_cvc_e() -> TestResult {
  var ok = eq(lemmatize("hoping", "v"), "hope");
  if !eq(lemmatize("making", "v"), "make") { ok = false; }
  if !eq(lemmatize("writing", "v"), "write") { ok = false; }
  if !eq(lemmatize("taking", "v"), "take") { ok = false; }
  if !eq(lemmatize("coming", "v"), "come") { ok = false; }
  if !eq(lemmatize("driving", "v"), "drive") { ok = false; }
  if !eq(lemmatize("hopping", "v"), "hop") { ok = false; }
  return assert(ok, "CVC +e restoration distinguishes hoping from hopping");
}

fn t22_verb_ing_silent_e() -> TestResult {
  var ok = eq(lemmatize("solving", "v"), "solve");
  if !eq(lemmatize("dancing", "v"), "dance") { ok = false; }
  if !eq(lemmatize("placing", "v"), "place") { ok = false; }
  return assert(ok, "verb -ing restores silent -e after v/c stems");
}

fn t23_verb_ed_basic() -> TestResult {
  var ok = eq(lemmatize("walked", "v"), "walk");
  if !eq(lemmatize("played", "v"), "play") { ok = false; }
  if !eq(lemmatize("needed", "v"), "need") { ok = false; }
  if !eq(lemmatize("opened", "v"), "open") { ok = false; }
  if !eq(lemmatize("visited", "v"), "visit") { ok = false; }
  if !eq(lemmatize("printed", "v"), "print") { ok = false; }
  return assert(ok, "verb -ed removal on regular words");
}

fn t24_verb_ed_double() -> TestResult {
  var ok = eq(lemmatize("hopped", "v"), "hop");
  if !eq(lemmatize("planned", "v"), "plan") { ok = false; }
  if !eq(lemmatize("rubbed", "v"), "rub") { ok = false; }
  if !eq(lemmatize("added", "v"), "add") { ok = false; }
  if !eq(lemmatize("embedded", "v"), "embed") { ok = false; }
  if !eq(lemmatize("dropped", "v"), "drop") { ok = false; }
  return assert(ok, "verb -ed drops one doubled consonant, keeps add/embed");
}

fn t25_verb_ed_cvc_e() -> TestResult {
  var ok = eq(lemmatize("hoped", "v"), "hope");
  if !eq(lemmatize("liked", "v"), "like") { ok = false; }
  if !eq(lemmatize("noted", "v"), "note") { ok = false; }
  if !eq(lemmatize("used", "v"), "use") { ok = false; }
  if !eq(lemmatize("moved", "v"), "move") { ok = false; }
  if !eq(lemmatize("saved", "v"), "save") { ok = false; }
  return assert(ok, "verb -ed restores silent -e (CVC and dictionary)");
}

fn t26_verb_ed_ied() -> TestResult {
  var ok = eq(lemmatize("studied", "v"), "study");
  if !eq(lemmatize("tried", "v"), "try") { ok = false; }
  if !eq(lemmatize("carried", "v"), "carry") { ok = false; }
  if !eq(lemmatize("worried", "v"), "worry") { ok = false; }
  if !eq(lemmatize("fried", "v"), "fry") { ok = false; }
  if !eq(lemmatize("copied", "v"), "copy") { ok = false; }
  return assert(ok, "verb -ied -> -y (die/tie/lie via dictionary)");
}

fn t27_verb_ed_silent() -> TestResult {
  var ok = eq(lemmatize("solved", "v"), "solve");
  if !eq(lemmatize("danced", "v"), "dance") { ok = false; }
  if !eq(lemmatize("placed", "v"), "place") { ok = false; }
  if !eq(lemmatize("produced", "v"), "produce") { ok = false; }
  if !eq(lemmatize("forced", "v"), "force") { ok = false; }
  if !eq(lemmatize("involved", "v"), "involve") { ok = false; }
  return assert(ok, "verb -ed silent-e restoration for -v and -c stems");
}

fn t28_verb_ed_dict() -> TestResult {
  var ok = eq(lemmatize("changed", "v"), "change");
  if !eq(lemmatize("managed", "v"), "manage") { ok = false; }
  if !eq(lemmatize("judged", "v"), "judge") { ok = false; }
  if !eq(lemmatize("agreed", "v"), "agree") { ok = false; }
  if !eq(lemmatize("freed", "v"), "free") { ok = false; }
  if !eq(lemmatize("guaranteed", "v"), "guarantee") { ok = false; }
  return assert(ok, "exception dictionary resolves -ed rule misses");
}

fn t29_verb_plural_s() -> TestResult {
  var ok = eq(lemmatize("runs", "v"), "run");
  if !eq(lemmatize("walks", "v"), "walk") { ok = false; }
  if !eq(lemmatize("plays", "v"), "play") { ok = false; }
  if !eq(lemmatize("loves", "v"), "love") { ok = false; }
  if !eq(lemmatize("misses", "v"), "miss") { ok = false; }
  if !eq(lemmatize("watches", "v"), "watch") { ok = false; }
  if !eq(lemmatize("fixes", "v"), "fix") { ok = false; }
  return assert(ok, "verb 3rd-person -s / sibilant -es");
}

fn t30_verb_guards() -> TestResult {
  var ok = eq(lemmatize("pass", "v"), "pass");
  if !eq(lemmatize("focus", "v"), "focus") { ok = false; }
  if !eq(lemmatize("cross", "v"), "cross") { ok = false; }
  if !eq(lemmatize("box", "v"), "box") { ok = false; }
  return assert(ok, "verb base forms with -ss/-us are unchanged");
}

fn t31_adj_er() -> TestResult {
  var ok = eq(lemmatize("bigger", "a"), "big");
  if !eq(lemmatize("hotter", "a"), "hot") { ok = false; }
  if !eq(lemmatize("thinner", "a"), "thin") { ok = false; }
  if !eq(lemmatize("taller", "a"), "tall") { ok = false; }
  if !eq(lemmatize("older", "a"), "old") { ok = false; }
  if !eq(lemmatize("younger", "a"), "young") { ok = false; }
  return assert(ok, "adjective comparative -er");
}

fn t32_adj_ier() -> TestResult {
  var ok = eq(lemmatize("happier", "a"), "happy");
  if !eq(lemmatize("easier", "a"), "easy") { ok = false; }
  if !eq(lemmatize("busier", "a"), "busy") { ok = false; }
  if !eq(lemmatize("luckier", "a"), "lucky") { ok = false; }
  return assert(ok, "adjective comparative -ier -> -y");
}

fn t33_adj_er_cvc() -> TestResult {
  var ok = eq(lemmatize("nicer", "a"), "nice");
  if !eq(lemmatize("finer", "a"), "fine") { ok = false; }
  if !eq(lemmatize("wider", "a"), "wide") { ok = false; }
  if !eq(lemmatize("safer", "a"), "safe") { ok = false; }
  if !eq(lemmatize("larger", "a"), "large") { ok = false; }
  if !eq(lemmatize("simpler", "a"), "simple") { ok = false; }
  return assert(ok, "adjective comparative silent-e restoration");
}

fn t34_adj_est() -> TestResult {
  var ok = eq(lemmatize("biggest", "a"), "big");
  if !eq(lemmatize("hottest", "a"), "hot") { ok = false; }
  if !eq(lemmatize("oldest", "a"), "old") { ok = false; }
  if !eq(lemmatize("nicest", "a"), "nice") { ok = false; }
  if !eq(lemmatize("happiest", "a"), "happy") { ok = false; }
  if !eq(lemmatize("simplest", "a"), "simple") { ok = false; }
  if !eq(lemmatize("largest", "a"), "large") { ok = false; }
  return assert(ok, "adjective superlative -est / -iest");
}

fn t35_adj_unchanged() -> TestResult {
  var ok = eq(lemmatize("good", "a"), "good");
  if !eq(lemmatize("happy", "a"), "happy") { ok = false; }
  if !eq(lemmatize("red", "a"), "red") { ok = false; }
  if !eq(lemmatize("strong", "a"), "strong") { ok = false; }
  return assert(ok, "adjective base forms are unchanged");
}

fn t36_precedence() -> TestResult {
  var ok = eq(lemmatize("children", "n"), "child");
  if !eq(lemmatize("better", "a"), "good") { ok = false; }
  if !eq(lemmatize("stories", "n"), "story") { ok = false; }
  if !eq(lemmatize("boxes", "n"), "box") { ok = false; }
  if !eq(lemmatize("hoping", "v"), "hope") { ok = false; }
  if !eq(lemmatize("hopping", "v"), "hop") { ok = false; }
  return assert(ok, "rule precedence: irregular > dictionary > longest suffix");
}

fn t37_unknown() -> TestResult {
  var ok = eq(lemmatize("xyzzy", "n"), "xyzzy");
  if !eq(lemmatize("blorpt", "v"), "blorpt") { ok = false; }
  if !eq(lemmatize("qwerty", "a"), "qwerty") { ok = false; }
  if !eq(lemmatize("zzzz", "n"), "zzzz") { ok = false; }
  return assert(ok, "unknown words pass through unchanged");
}

fn t38_casing() -> TestResult {
  var ok = eq(lemmatize("Cats", "n"), "Cat");
  if !eq(lemmatize("Stories", "n"), "Story") { ok = false; }
  if !eq(lemmatize("Went", "v"), "Go") { ok = false; }
  if !eq(lemmatize("CATS", "n"), "CAT") { ok = false; }
  if !eq(lemmatize("CHILDREN", "n"), "CHILD") { ok = false; }
  if !eq(lemmatize("iPhone", "n"), "iPhone") { ok = false; }
  return assert(ok, "casing is restored: Capitalized and ALL-CAPS");
}

fn t39_non_letter_unchanged() -> TestResult {
  var ok = eq(lemmatize("cafe\u{0301}", "n"), "cafe\u{0301}");
  if !eq(lemmatize("don't", "v"), "don't") { ok = false; }
  if !eq(lemmatize("123", "n"), "123") { ok = false; }
  if !eq(lemmatize("", "n"), "") { ok = false; }
  if !eq(lemmatize("caf\u{00E9}", "n"), "caf\u{00E9}") { ok = false; }
  return assert(ok, "non-letter and empty tokens are returned unchanged");
}

fn t40_default_pos() -> TestResult {
  var ok = eq(lemmatize("men", ""), "man");
  if !eq(lemmatize("cats", "x"), "cat") { ok = false; }
  if !eq(lemmatize("walked", ""), "walked") { ok = false; }
  return assert(ok, "unknown/empty POS selects the noun rule set");
}

fn t41_batch_all() -> TestResult {
  var words = Vec[Str].new();
  words.push("men");
  words.push("running");
  words.push("happier");
  var tags = Vec[Str].new();
  tags.push("n");
  tags.push("v");
  tags.push("a");
  let out = lemmatize_all(&words, &tags);
  var ok = out.len() == 3;
  if !elem_is(&out, 0, "man") { ok = false; }
  if !elem_is(&out, 1, "run") { ok = false; }
  if !elem_is(&out, 2, "happy") { ok = false; }
  return assert(ok, "lemmatize_all uses parallel POS tags in order");
}

fn t42_batch_mismatch() -> TestResult {
  var words = Vec[Str].new();
  words.push("cats");
  words.push("men");
  var tags = Vec[Str].new();
  tags.push("v");
  let out = lemmatize_all(&words, &tags);
  var ok = out.len() == 2;
  if !elem_is(&out, 0, "cat") { ok = false; }
  if !elem_is(&out, 1, "man") { ok = false; }
  if !elem_is(&out, 0, "cat") { ok = false; }
  return assert(ok, "missing tags default to noun, extra tags are ignored");
}

fn t43_batch_empty() -> TestResult {
  var words = Vec[Str].new();
  var tags = Vec[Str].new();
  let out = lemmatize_all(&words, &tags);
  return assert(out.len() == 0, "lemmatize_all of empty vectors is empty");
}

fn t44_is_irregular() -> TestResult {
  var ok = lemmatize_is_irregular("went");
  if !lemmatize_is_irregular("better") { ok = false; }
  if !lemmatize_is_irregular("children") { ok = false; }
  if lemmatize_is_irregular("cats") { ok = false; }
  if lemmatize_is_irregular("running") { ok = false; }
  if lemmatize_is_irregular("") { ok = false; }
  if lemmatize_is_irregular("don't") { ok = false; }
  return assert(ok, "lemmatize_is_irregular reports table membership");
}

fn main() -> Int {
  io.println("=== xiom.lemmatization conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_irregular_nouns();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_irregular_verbs_be();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_irregular_verbs_have_do_go();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_irregular_verbs_strong();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_irregular_verbs_irregular_pairs();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_irregular_adjectives();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_irregular_pos_scope();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_noun_ies();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_noun_ies_exceptions();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_noun_ves();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_noun_sibilant_es();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_noun_oes();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_noun_generic_s();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_noun_guards();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_noun_ses_irregular();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_verb_ies();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_verb_ies_exceptions();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_verb_ing_basic();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_verb_ing_double();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_verb_ing_lsz();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_verb_ing_cvc_e();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_verb_ing_silent_e();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_verb_ed_basic();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_verb_ed_double();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_verb_ed_cvc_e();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_verb_ed_ied();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_verb_ed_silent();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_verb_ed_dict();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29_verb_plural_s();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30_verb_guards();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31_adj_er();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32_adj_ier();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33_adj_er_cvc();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34_adj_est();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = t35_adj_unchanged();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  let r36 = t36_precedence();
  if r36.passed { io.println("  [PASS] " + r36.name); } else { io.println("  [FAIL] " + r36.name); failed = failed + 1; }
  let r37 = t37_unknown();
  if r37.passed { io.println("  [PASS] " + r37.name); } else { io.println("  [FAIL] " + r37.name); failed = failed + 1; }
  let r38 = t38_casing();
  if r38.passed { io.println("  [PASS] " + r38.name); } else { io.println("  [FAIL] " + r38.name); failed = failed + 1; }
  let r39 = t39_non_letter_unchanged();
  if r39.passed { io.println("  [PASS] " + r39.name); } else { io.println("  [FAIL] " + r39.name); failed = failed + 1; }
  let r40 = t40_default_pos();
  if r40.passed { io.println("  [PASS] " + r40.name); } else { io.println("  [FAIL] " + r40.name); failed = failed + 1; }
  let r41 = t41_batch_all();
  if r41.passed { io.println("  [PASS] " + r41.name); } else { io.println("  [FAIL] " + r41.name); failed = failed + 1; }
  let r42 = t42_batch_mismatch();
  if r42.passed { io.println("  [PASS] " + r42.name); } else { io.println("  [FAIL] " + r42.name); failed = failed + 1; }
  let r43 = t43_batch_empty();
  if r43.passed { io.println("  [PASS] " + r43.name); } else { io.println("  [FAIL] " + r43.name); failed = failed + 1; }
  let r44 = t44_is_irregular();
  if r44.passed { io.println("  [PASS] " + r44.name); } else { io.println("  [FAIL] " + r44.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.lemmatization: all tests passed");
  } else {
    io.println("xiom.lemmatization: tests failed");
  }
  return failed;
}
