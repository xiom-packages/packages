// XIOM -- xiom.plural conformance tests (35 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module plural_tests
use xiom.io; use xiom.test; use xiom.plural;
use xiom.string.compare;

// Str equality goes through str_compare: BUG 17 lowers `==` between Str
// values read from a Vec[Str] to a pointer comparison, so elements of the
// Vec[Str] returned by plural_pluralize_all are compared only via
// compare.str_compare.

fn eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn all_is(words: &Vec[Str], a: Str, b: Str, c: Str) -> Bool {
  let got = plural_pluralize_all(words);
  if got.len() != 3 { return false; }
  if compare.str_compare(got[0], a) != 0 { return false; }
  if compare.str_compare(got[1], b) != 0 { return false; }
  if compare.str_compare(got[2], c) != 0 { return false; }
  return true;
}

fn irregular_plural_regular_nouns() -> TestResult {
  var ok = eq(plural_pluralize("person"), "people");
  if !eq(plural_pluralize("man"), "men") { ok = false; }
  if !eq(plural_pluralize("woman"), "women") { ok = false; }
  if !eq(plural_pluralize("child"), "children") { ok = false; }
  if !eq(plural_pluralize("tooth"), "teeth") { ok = false; }
  if !eq(plural_pluralize("foot"), "feet") { ok = false; }
  if !eq(plural_pluralize("mouse"), "mice") { ok = false; }
  if !eq(plural_pluralize("goose"), "geese") { ok = false; }
  if !eq(plural_pluralize("ox"), "oxen") { ok = false; }
  return assert(ok, "irregular plurals: people/men/women/children/teeth/feet/mice/geese/oxen");
}

fn irregular_plural_latin_greek() -> TestResult {
  var ok = eq(plural_pluralize("datum"), "data");
  if !eq(plural_pluralize("medium"), "media") { ok = false; }
  if !eq(plural_pluralize("analysis"), "analyses") { ok = false; }
  if !eq(plural_pluralize("basis"), "bases") { ok = false; }
  if !eq(plural_pluralize("crisis"), "crises") { ok = false; }
  if !eq(plural_pluralize("thesis"), "theses") { ok = false; }
  if !eq(plural_pluralize("index"), "indices") { ok = false; }
  if !eq(plural_pluralize("matrix"), "matrices") { ok = false; }
  if !eq(plural_pluralize("vertex"), "vertices") { ok = false; }
  if !eq(plural_pluralize("appendix"), "appendices") { ok = false; }
  return assert(ok, "irregular plurals: data/media/analyses/bases/crises/theses/indices/matrices/vertices/appendices");
}

fn irregular_singular_regular_nouns() -> TestResult {
  var ok = eq(plural_singularize("people"), "person");
  if !eq(plural_singularize("men"), "man") { ok = false; }
  if !eq(plural_singularize("women"), "woman") { ok = false; }
  if !eq(plural_singularize("children"), "child") { ok = false; }
  if !eq(plural_singularize("teeth"), "tooth") { ok = false; }
  if !eq(plural_singularize("feet"), "foot") { ok = false; }
  if !eq(plural_singularize("mice"), "mouse") { ok = false; }
  if !eq(plural_singularize("geese"), "goose") { ok = false; }
  if !eq(plural_singularize("oxen"), "ox") { ok = false; }
  return assert(ok, "irregular singulars: people/men/women/children/teeth/feet/mice/geese/oxen");
}

fn irregular_singular_latin_greek() -> TestResult {
  var ok = eq(plural_singularize("data"), "datum");
  if !eq(plural_singularize("media"), "medium") { ok = false; }
  if !eq(plural_singularize("analyses"), "analysis") { ok = false; }
  if !eq(plural_singularize("bases"), "basis") { ok = false; }
  if !eq(plural_singularize("crises"), "crisis") { ok = false; }
  if !eq(plural_singularize("theses"), "thesis") { ok = false; }
  if !eq(plural_singularize("indices"), "index") { ok = false; }
  if !eq(plural_singularize("matrices"), "matrix") { ok = false; }
  if !eq(plural_singularize("vertices"), "vertex") { ok = false; }
  if !eq(plural_singularize("appendices"), "appendix") { ok = false; }
  return assert(ok, "irregular singulars: data/media/analyses/bases/crises/theses/indices/matrices/vertices/appendices");
}

fn invariant_pluralize() -> TestResult {
  var ok = eq(plural_pluralize("sheep"), "sheep");
  if !eq(plural_pluralize("deer"), "deer") { ok = false; }
  if !eq(plural_pluralize("fish"), "fish") { ok = false; }
  if !eq(plural_pluralize("series"), "series") { ok = false; }
  if !eq(plural_pluralize("species"), "species") { ok = false; }
  return assert(ok, "invariant nouns are unchanged when pluralized");
}

fn invariant_singularize() -> TestResult {
  var ok = eq(plural_singularize("sheep"), "sheep");
  if !eq(plural_singularize("deer"), "deer") { ok = false; }
  if !eq(plural_singularize("fish"), "fish") { ok = false; }
  if !eq(plural_singularize("series"), "series") { ok = false; }
  if !eq(plural_singularize("species"), "species") { ok = false; }
  return assert(ok, "invariant nouns are unchanged when singularized");
}

fn suffix_ch_sh() -> TestResult {
  var ok = eq(plural_pluralize("church"), "churches");
  if !eq(plural_pluralize("brush"), "brushes") { ok = false; }
  return assert(ok, "ch/sh take -es: church, brush");
}

fn suffix_ss_x_z() -> TestResult {
  var ok = eq(plural_pluralize("class"), "classes");
  if !eq(plural_pluralize("box"), "boxes") { ok = false; }
  if !eq(plural_pluralize("buzz"), "buzzes") { ok = false; }
  return assert(ok, "ss/x/z take -es: class, box, buzz");
}

fn suffix_s() -> TestResult {
  var ok = eq(plural_pluralize("bus"), "buses");
  if !eq(plural_pluralize("gas"), "gases") { ok = false; }
  if !eq(plural_pluralize("kiss"), "kisses") { ok = false; }
  return assert(ok, "final s takes -es: bus, gas, kiss");
}

fn suffix_consonant_y() -> TestResult {
  var ok = eq(plural_pluralize("city"), "cities");
  if !eq(plural_pluralize("baby"), "babies") { ok = false; }
  if !eq(plural_pluralize("party"), "parties") { ok = false; }
  return assert(ok, "consonant + y becomes -ies: city, baby, party");
}

fn suffix_vowel_y() -> TestResult {
  var ok = eq(plural_pluralize("boy"), "boys");
  if !eq(plural_pluralize("key"), "keys") { ok = false; }
  if !eq(plural_pluralize("day"), "days") { ok = false; }
  return assert(ok, "vowel + y keeps -s: boy, key, day");
}

fn suffix_fe() -> TestResult {
  var ok = eq(plural_pluralize("knife"), "knives");
  if !eq(plural_pluralize("wife"), "wives") { ok = false; }
  if !eq(plural_pluralize("life"), "lives") { ok = false; }
  return assert(ok, "final fe becomes -ves: knife, wife, life");
}

fn suffix_f_ves_list() -> TestResult {
  var ok = eq(plural_pluralize("leaf"), "leaves");
  if !eq(plural_pluralize("wolf"), "wolves") { ok = false; }
  if !eq(plural_pluralize("half"), "halves") { ok = false; }
  if !eq(plural_pluralize("shelf"), "shelves") { ok = false; }
  if !eq(plural_pluralize("calf"), "calves") { ok = false; }
  if !eq(plural_pluralize("loaf"), "loaves") { ok = false; }
  if !eq(plural_pluralize("thief"), "thieves") { ok = false; }
  if !eq(plural_pluralize("scarf"), "scarves") { ok = false; }
  if !eq(plural_pluralize("self"), "selves") { ok = false; }
  return assert(ok, "known f words take -ves: leaf/wolf/half/shelf/calf/loaf/thief/scarf/self");
}

fn suffix_f_exceptions() -> TestResult {
  var ok = eq(plural_pluralize("roof"), "roofs");
  if !eq(plural_pluralize("chief"), "chiefs") { ok = false; }
  if !eq(plural_pluralize("belief"), "beliefs") { ok = false; }
  if !eq(plural_pluralize("chef"), "chefs") { ok = false; }
  if !eq(plural_pluralize("proof"), "proofs") { ok = false; }
  return assert(ok, "f exceptions keep -s: roof, chief, belief, chef, proof");
}

fn suffix_o_es_list() -> TestResult {
  var ok = eq(plural_pluralize("hero"), "heroes");
  if !eq(plural_pluralize("potato"), "potatoes") { ok = false; }
  if !eq(plural_pluralize("tomato"), "tomatoes") { ok = false; }
  if !eq(plural_pluralize("echo"), "echoes") { ok = false; }
  if !eq(plural_pluralize("veto"), "vetoes") { ok = false; }
  if !eq(plural_pluralize("volcano"), "volcanoes") { ok = false; }
  return assert(ok, "known o words take -oes: hero/potato/tomato/echo/veto/volcano");
}

fn suffix_o_exceptions() -> TestResult {
  var ok = eq(plural_pluralize("photo"), "photos");
  if !eq(plural_pluralize("piano"), "pianos") { ok = false; }
  if !eq(plural_pluralize("halo"), "halos") { ok = false; }
  if !eq(plural_pluralize("solo"), "solos") { ok = false; }
  if !eq(plural_pluralize("memo"), "memos") { ok = false; }
  if !eq(plural_pluralize("kilo"), "kilos") { ok = false; }
  return assert(ok, "o exceptions take -s: photo, piano, halo, solo, memo, kilo");
}

fn default_s_rule() -> TestResult {
  var ok = eq(plural_pluralize("cat"), "cats");
  if !eq(plural_pluralize("dog"), "dogs") { ok = false; }
  if !eq(plural_pluralize("banana"), "bananas") { ok = false; }
  return assert(ok, "default rule appends -s: cat, dog, banana");
}

fn single_letter_default() -> TestResult {
  var ok = eq(plural_pluralize("a"), "as");
  if !eq(plural_pluralize("z"), "zes") { ok = false; }
  return assert(ok, "single-letter words follow the default rules");
}

fn case_preservation_pluralize() -> TestResult {
  var ok = eq(plural_pluralize("City"), "Cities");
  if !eq(plural_pluralize("Person"), "People") { ok = false; }
  if !eq(plural_pluralize("Child"), "Children") { ok = false; }
  if !eq(plural_pluralize("Sheep"), "Sheep") { ok = false; }
  return assert(ok, "initial capitalization is preserved: City/Person/Child/Sheep");
}

fn case_preservation_singularize() -> TestResult {
  var ok = eq(plural_singularize("Cities"), "City");
  if !eq(plural_singularize("People"), "Person") { ok = false; }
  if !eq(plural_singularize("Leaves"), "Leaf") { ok = false; }
  return assert(ok, "initial capitalization is preserved when singularizing");
}

fn count_zero() -> TestResult {
  var ok = eq(plural_count(0, "item"), "0 items");
  if !eq(plural_count(0, "child"), "0 children") { ok = false; }
  return assert(ok, "count 0 uses the plural form");
}

fn count_one() -> TestResult {
  var ok = eq(plural_count(1, "item"), "1 item");
  if !eq(plural_count(1, "person"), "1 person") { ok = false; }
  return assert(ok, "count 1 uses the given singular form");
}

fn count_two() -> TestResult {
  var ok = eq(plural_count(2, "item"), "2 items");
  if !eq(plural_count(2, "person"), "2 people") { ok = false; }
  return assert(ok, "count 2 pluralizes: items, people");
}

fn count_irregular() -> TestResult {
  var ok = eq(plural_count(5, "child"), "5 children");
  if !eq(plural_count(1, "child"), "1 child") { ok = false; }
  if !eq(plural_count(0, "person"), "0 people") { ok = false; }
  return assert(ok, "count forms use the irregular table: child/children, people");
}

fn pluralize_all_three() -> TestResult {
  var words = Vec[Str].new();
  words.push("cat");
  words.push("city");
  words.push("leaf");
  return assert(all_is(&words, "cats", "cities", "leaves"), "pluralize_all rewrites all three elements in order");
}

fn pluralize_all_case() -> TestResult {
  var words = Vec[Str].new();
  words.push("Person");
  words.push("City");
  words.push("box");
  return assert(all_is(&words, "People", "Cities", "boxes"), "pluralize_all preserves capitalization per element");
}

fn round_trip_three() -> TestResult {
  var ok = eq(plural_pluralize(plural_singularize("cats")), "cats");
  if !eq(plural_pluralize(plural_singularize("cities")), "cities") { ok = false; }
  if !eq(plural_pluralize(plural_singularize("leaves")), "leaves") { ok = false; }
  return assert(ok, "pluralize(singularize(x)) round-trips cats/cities/leaves");
}

fn singularize_regular_s() -> TestResult {
  var ok = eq(plural_singularize("cats"), "cat");
  if !eq(plural_singularize("dogs"), "dog") { ok = false; }
  if !eq(plural_singularize("books"), "book") { ok = false; }
  return assert(ok, "regular +s words drop the s: cats, dogs, books");
}

fn singularize_es_group() -> TestResult {
  var ok = eq(plural_singularize("boxes"), "box");
  if !eq(plural_singularize("churches"), "church") { ok = false; }
  if !eq(plural_singularize("dishes"), "dish") { ok = false; }
  if !eq(plural_singularize("classes"), "class") { ok = false; }
  if !eq(plural_singularize("buzzes"), "buzz") { ok = false; }
  if !eq(plural_singularize("kisses"), "kiss") { ok = false; }
  return assert(ok, "-es groups strip to the base: boxes/churches/dishes/classes/buzzes/kisses");
}

fn singularize_ies() -> TestResult {
  var ok = eq(plural_singularize("cities"), "city");
  if !eq(plural_singularize("babies"), "baby") { ok = false; }
  if !eq(plural_singularize("parties"), "party") { ok = false; }
  return assert(ok, "-ies becomes -y: cities, babies, parties");
}

fn singularize_ves_list() -> TestResult {
  var ok = eq(plural_singularize("leaves"), "leaf");
  if !eq(plural_singularize("wolves"), "wolf") { ok = false; }
  if !eq(plural_singularize("knives"), "knife") { ok = false; }
  if !eq(plural_singularize("wives"), "wife") { ok = false; }
  if !eq(plural_singularize("lives"), "life") { ok = false; }
  if !eq(plural_singularize("halves"), "half") { ok = false; }
  if !eq(plural_singularize("shelves"), "shelf") { ok = false; }
  if !eq(plural_singularize("calves"), "calf") { ok = false; }
  if !eq(plural_singularize("loaves"), "loaf") { ok = false; }
  if !eq(plural_singularize("thieves"), "thief") { ok = false; }
  if !eq(plural_singularize("scarves"), "scarf") { ok = false; }
  return assert(ok, "known -ves plurals map back to their exact singulars");
}

fn singularize_oes_list() -> TestResult {
  var ok = eq(plural_singularize("heroes"), "hero");
  if !eq(plural_singularize("potatoes"), "potato") { ok = false; }
  if !eq(plural_singularize("tomatoes"), "tomato") { ok = false; }
  if !eq(plural_singularize("echoes"), "echo") { ok = false; }
  if !eq(plural_singularize("vetoes"), "veto") { ok = false; }
  if !eq(plural_singularize("volcanoes"), "volcano") { ok = false; }
  return assert(ok, "known -oes plurals map back to their exact singulars");
}

fn is_irregular_true() -> TestResult {
  var ok = plural_is_irregular("people");
  if !plural_is_irregular("children") { ok = false; }
  if !plural_is_irregular("geese") { ok = false; }
  if !plural_is_irregular("mice") { ok = false; }
  if !plural_is_irregular("matrices") { ok = false; }
  if !plural_is_irregular("person") { ok = false; }
  if !plural_is_irregular("sheep") { ok = false; }
  return assert(ok, "is_irregular is true for irregular forms in both directions");
}

fn is_irregular_false() -> TestResult {
  var ok = !plural_is_irregular("cat");
  if plural_is_irregular("city") { ok = false; }
  if plural_is_irregular("box") { ok = false; }
  if plural_is_irregular("bus") { ok = false; }
  return assert(ok, "is_irregular is false for rule-driven words");
}

fn empty_string() -> TestResult {
  var ok = eq(plural_pluralize(""), "");
  if !eq(plural_singularize(""), "") { ok = false; }
  var none = Vec[Str].new();
  if plural_pluralize_all(&none).len() != 0 { ok = false; }
  return assert(ok, "empty input returns empty output");
}

fn main() -> Int {
  io.println("=== xiom.plural conformance tests ===");
  var failed: Int = 0;
  let r1 = irregular_plural_regular_nouns();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = irregular_plural_latin_greek();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = irregular_singular_regular_nouns();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = irregular_singular_latin_greek();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = invariant_pluralize();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = invariant_singularize();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = suffix_ch_sh();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = suffix_ss_x_z();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = suffix_s();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = suffix_consonant_y();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = suffix_vowel_y();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = suffix_fe();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = suffix_f_ves_list();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = suffix_f_exceptions();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = suffix_o_es_list();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = suffix_o_exceptions();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = default_s_rule();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = single_letter_default();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = case_preservation_pluralize();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = case_preservation_singularize();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = count_zero();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = count_one();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = count_two();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = count_irregular();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = pluralize_all_three();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = pluralize_all_case();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = round_trip_three();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = singularize_regular_s();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = singularize_es_group();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = singularize_ies();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = singularize_ves_list();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = singularize_oes_list();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = is_irregular_true();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = is_irregular_false();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = empty_string();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.plural: all tests passed");
  } else {
    io.println("xiom.plural: tests failed");
  }
  return failed;
}
