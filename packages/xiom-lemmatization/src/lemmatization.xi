// XIOM -- xiom.lemmatization: deterministic rule-based English lemmatizer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM, deterministic lemmatizer for ASCII English words. The
// pipeline is: ASCII-letters-only guard -> per-POS irregular table ->
// shared exception dictionary -> ordered per-POS suffix rules -> casing
// restoration. No FFI, no data files, no allocation-owned state. See
// SPEC.md for the exact rule order and the input contract.

module xiom.lemmatization

use xiom.string;
use xiom.string.compare;
use xiom.string.lowercase;
use xiom.string.uppercase;

// --- byte predicates --------------------------------------------------------

// ASCII letter (A-Z or a-z).
fn _is_letter(b: Int) -> Bool {
  if b >= 65 && b <= 90 { return true; }
  if b >= 97 && b <= 122 { return true; }
  return false;
}

// ASCII lowercase letter (a-z).
fn _is_lower_byte(b: Int) -> Bool {
  return b >= 97 && b <= 122;
}

// ASCII uppercase letter (A-Z).
fn _is_upper_byte(b: Int) -> Bool {
  return b >= 65 && b <= 90;
}

// Lowercase ASCII vowel: a, e, i, o, u. 'y' counts as a consonant here.
fn _is_vowel_byte(b: Int) -> Bool {
  if b == 97 { return true; }
  if b == 101 { return true; }
  if b == 105 { return true; }
  if b == 111 { return true; }
  if b == 117 { return true; }
  return false;
}

// --- input classification ---------------------------------------------------

// True when every byte of `s` is an ASCII letter.
fn _letters_only(s: Str) -> Bool {
  var i = 0;
  let n = str_len(s);
  while i < n {
    let b = byte_at(s, i) as Int;
    if !_is_letter(b) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of `s` is an ASCII lowercase letter.
fn _all_lower(s: Str) -> Bool {
  var i = 0;
  let n = str_len(s);
  while i < n {
    let b = byte_at(s, i) as Int;
    if !_is_lower_byte(b) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of `s` is an ASCII uppercase letter.
fn _all_upper(s: Str) -> Bool {
  var i = 0;
  let n = str_len(s);
  while i < n {
    let b = byte_at(s, i) as Int;
    if !_is_upper_byte(b) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly "Upper" + zero or more lowercase letters.
fn _capitalized(s: Str) -> Bool {
  let n = str_len(s);
  if n == 0 { return false; }
  let first = byte_at(s, 0) as Int;
  if !_is_upper_byte(first) { return false; }
  var i = 1;
  while i < n {
    let b = byte_at(s, i) as Int;
    if !_is_lower_byte(b) { return false; }
    i = i + 1;
  }
  return true;
}

// Uppercase the first byte of `s`, leaving the rest alone.
fn _capitalize_first(s: Str) -> Str {
  let n = str_len(s);
  if n == 0 { return s; }
  return str_uppercase(str_slice(s, 0, 1)) + str_slice(s, 1, n);
}

// --- small string helpers ---------------------------------------------------

// Drop the final byte of `s`.
fn _drop_last_byte(s: Str) -> Str {
  let n = str_len(s);
  if n == 0 { return s; }
  return str_slice(s, 0, n - 1);
}

// Replace a known trailing suffix of `s` with `repl`.
fn _replace_suffix(s: Str, suffix: Str, repl: Str) -> Str {
  let n = str_len(s);
  let m = str_len(suffix);
  return str_slice(s, 0, n - m) + repl;
}

// True when `s` ends in two identical consonant bytes.
fn _is_double_consonant(s: Str) -> Bool {
  let n = str_len(s);
  if n < 2 { return false; }
  let a = byte_at(s, n - 1) as Int;
  let b = byte_at(s, n - 2) as Int;
  if a != b { return false; }
  return !_is_vowel_byte(a);
}

// True when a final double consonant should lose one letter in verb
// inflection. Double l, s and z are kept (Porter's exception).
fn _drops_double(s: Str) -> Bool {
  if !_is_double_consonant(s) { return false; }
  let n = str_len(s);
  let a = byte_at(s, n - 1) as Int;
  if a == 108 { return false; }
  if a == 115 { return false; }
  if a == 122 { return false; }
  return true;
}

// Number of lowercase vowels in `s`.
fn _count_vowels(s: Str) -> Int {
  var i = 0;
  var c = 0;
  let n = str_len(s);
  while i < n {
    let b = byte_at(s, i) as Int;
    if _is_vowel_byte(b) { c = c + 1; }
    i = i + 1;
  }
  return c;
}

// True when `s` contains at least one lowercase vowel.
fn _has_vowel(s: Str) -> Bool {
  return _count_vowels(s) > 0;
}

// True when `s` ends consonant-vowel-consonant and the final consonant is
// not w, x or y.
fn _ends_cvc(s: Str) -> Bool {
  let n = str_len(s);
  if n < 3 { return false; }
  let c1 = byte_at(s, n - 3) as Int;
  let c2 = byte_at(s, n - 2) as Int;
  let c3 = byte_at(s, n - 1) as Int;
  if _is_vowel_byte(c1) { return false; }
  if !_is_vowel_byte(c2) { return false; }
  if _is_vowel_byte(c3) { return false; }
  if c3 == 119 { return false; }
  if c3 == 120 { return false; }
  if c3 == 121 { return false; }
  return true;
}

// True when `s` ends in 'v' preceded by a consonant letter (solved -> solve).
fn _ends_v_after_consonant(s: Str) -> Bool {
  let n = str_len(s);
  if n < 2 { return false; }
  if (byte_at(s, n - 1) as Int) != 118 { return false; }
  let p = byte_at(s, n - 2) as Int;
  if _is_vowel_byte(p) { return false; }
  return _is_lower_byte(p);
}

// True when `s` ends in 'c' (danced -> dance).
fn _ends_c(s: Str) -> Bool {
  let n = str_len(s);
  if n == 0 { return false; }
  return (byte_at(s, n - 1) as Int) == 99;
}

// True when `s` ends in single 'l' preceded by a consonant (simpl -> simple).
fn _ends_l_after_consonant(s: Str) -> Bool {
  let n = str_len(s);
  if n < 2 { return false; }
  if (byte_at(s, n - 1) as Int) != 108 { return false; }
  let p = byte_at(s, n - 2) as Int;
  if p == 108 { return false; }
  if _is_vowel_byte(p) { return false; }
  return _is_lower_byte(p);
}

// Restore a verb stem that lost its silent final e, doubled consonant or
// inflectional ending. Shared by the -ing and -ed rules.
fn _restore_base(stem: Str) -> Str {
  if _drops_double(stem) { return _drop_last_byte(stem); }
  if _ends_cvc(stem) && _count_vowels(stem) == 1 { return stem + "e"; }
  if _ends_v_after_consonant(stem) { return stem + "e"; }
  if _ends_c(stem) { return stem + "e"; }
  return stem;
}

// --- irregular tables (per POS) ---------------------------------------------

// Irregular and suppletive noun plurals -> singulars. "" when absent.
fn _irregular_noun(lower: Str) -> Str {
  if str_compare(lower, "men") == 0 { return "man"; }
  if str_compare(lower, "women") == 0 { return "woman"; }
  if str_compare(lower, "children") == 0 { return "child"; }
  if str_compare(lower, "teeth") == 0 { return "tooth"; }
  if str_compare(lower, "feet") == 0 { return "foot"; }
  if str_compare(lower, "mice") == 0 { return "mouse"; }
  if str_compare(lower, "geese") == 0 { return "goose"; }
  if str_compare(lower, "oxen") == 0 { return "ox"; }
  if str_compare(lower, "people") == 0 { return "person"; }
  if str_compare(lower, "lives") == 0 { return "life"; }
  if str_compare(lower, "wives") == 0 { return "wife"; }
  if str_compare(lower, "knives") == 0 { return "knife"; }
  if str_compare(lower, "wolves") == 0 { return "wolf"; }
  if str_compare(lower, "leaves") == 0 { return "leaf"; }
  if str_compare(lower, "halves") == 0 { return "half"; }
  if str_compare(lower, "shelves") == 0 { return "shelf"; }
  if str_compare(lower, "calves") == 0 { return "calf"; }
  if str_compare(lower, "loaves") == 0 { return "loaf"; }
  if str_compare(lower, "thieves") == 0 { return "thief"; }
  if str_compare(lower, "scarves") == 0 { return "scarf"; }
  if str_compare(lower, "selves") == 0 { return "self"; }
  if str_compare(lower, "elves") == 0 { return "elf"; }
  if str_compare(lower, "hooves") == 0 { return "hoof"; }
  if str_compare(lower, "analyses") == 0 { return "analysis"; }
  if str_compare(lower, "crises") == 0 { return "crisis"; }
  if str_compare(lower, "theses") == 0 { return "thesis"; }
  if str_compare(lower, "hypotheses") == 0 { return "hypothesis"; }
  if str_compare(lower, "diagnoses") == 0 { return "diagnosis"; }
  if str_compare(lower, "indices") == 0 { return "index"; }
  if str_compare(lower, "matrices") == 0 { return "matrix"; }
  if str_compare(lower, "vertices") == 0 { return "vertex"; }
  if str_compare(lower, "criteria") == 0 { return "criterion"; }
  if str_compare(lower, "phenomena") == 0 { return "phenomenon"; }
  return "";
}

// Irregular and suppletive verb forms -> base form. "" when absent.
fn _irregular_verb(lower: Str) -> Str {
  if str_compare(lower, "went") == 0 { return "go"; }
  if str_compare(lower, "gone") == 0 { return "go"; }
  if str_compare(lower, "goes") == 0 { return "go"; }
  if str_compare(lower, "did") == 0 { return "do"; }
  if str_compare(lower, "done") == 0 { return "do"; }
  if str_compare(lower, "does") == 0 { return "do"; }
  if str_compare(lower, "was") == 0 { return "be"; }
  if str_compare(lower, "were") == 0 { return "be"; }
  if str_compare(lower, "been") == 0 { return "be"; }
  if str_compare(lower, "is") == 0 { return "be"; }
  if str_compare(lower, "are") == 0 { return "be"; }
  if str_compare(lower, "am") == 0 { return "be"; }
  if str_compare(lower, "had") == 0 { return "have"; }
  if str_compare(lower, "has") == 0 { return "have"; }
  if str_compare(lower, "ran") == 0 { return "run"; }
  if str_compare(lower, "came") == 0 { return "come"; }
  if str_compare(lower, "saw") == 0 { return "see"; }
  if str_compare(lower, "seen") == 0 { return "see"; }
  if str_compare(lower, "ate") == 0 { return "eat"; }
  if str_compare(lower, "eaten") == 0 { return "eat"; }
  if str_compare(lower, "gave") == 0 { return "give"; }
  if str_compare(lower, "given") == 0 { return "give"; }
  if str_compare(lower, "took") == 0 { return "take"; }
  if str_compare(lower, "taken") == 0 { return "take"; }
  if str_compare(lower, "made") == 0 { return "make"; }
  if str_compare(lower, "said") == 0 { return "say"; }
  if str_compare(lower, "found") == 0 { return "find"; }
  if str_compare(lower, "got") == 0 { return "get"; }
  if str_compare(lower, "gotten") == 0 { return "get"; }
  if str_compare(lower, "held") == 0 { return "hold"; }
  if str_compare(lower, "kept") == 0 { return "keep"; }
  if str_compare(lower, "left") == 0 { return "leave"; }
  if str_compare(lower, "lost") == 0 { return "lose"; }
  if str_compare(lower, "met") == 0 { return "meet"; }
  if str_compare(lower, "paid") == 0 { return "pay"; }
  if str_compare(lower, "put") == 0 { return "put"; }
  if str_compare(lower, "read") == 0 { return "read"; }
  if str_compare(lower, "rose") == 0 { return "rise"; }
  if str_compare(lower, "risen") == 0 { return "rise"; }
  if str_compare(lower, "sold") == 0 { return "sell"; }
  if str_compare(lower, "sent") == 0 { return "send"; }
  if str_compare(lower, "sat") == 0 { return "sit"; }
  if str_compare(lower, "slept") == 0 { return "sleep"; }
  if str_compare(lower, "spoke") == 0 { return "speak"; }
  if str_compare(lower, "spoken") == 0 { return "speak"; }
  if str_compare(lower, "spent") == 0 { return "spend"; }
  if str_compare(lower, "stood") == 0 { return "stand"; }
  if str_compare(lower, "taught") == 0 { return "teach"; }
  if str_compare(lower, "told") == 0 { return "tell"; }
  if str_compare(lower, "thought") == 0 { return "think"; }
  if str_compare(lower, "wore") == 0 { return "wear"; }
  if str_compare(lower, "worn") == 0 { return "wear"; }
  if str_compare(lower, "won") == 0 { return "win"; }
  if str_compare(lower, "wrote") == 0 { return "write"; }
  if str_compare(lower, "written") == 0 { return "write"; }
  if str_compare(lower, "bought") == 0 { return "buy"; }
  if str_compare(lower, "brought") == 0 { return "bring"; }
  if str_compare(lower, "caught") == 0 { return "catch"; }
  if str_compare(lower, "chose") == 0 { return "choose"; }
  if str_compare(lower, "chosen") == 0 { return "choose"; }
  if str_compare(lower, "drew") == 0 { return "draw"; }
  if str_compare(lower, "drawn") == 0 { return "draw"; }
  if str_compare(lower, "drank") == 0 { return "drink"; }
  if str_compare(lower, "drunk") == 0 { return "drink"; }
  if str_compare(lower, "drove") == 0 { return "drive"; }
  if str_compare(lower, "driven") == 0 { return "drive"; }
  if str_compare(lower, "fell") == 0 { return "fall"; }
  if str_compare(lower, "fallen") == 0 { return "fall"; }
  if str_compare(lower, "felt") == 0 { return "feel"; }
  if str_compare(lower, "flew") == 0 { return "fly"; }
  if str_compare(lower, "flown") == 0 { return "fly"; }
  if str_compare(lower, "forgot") == 0 { return "forget"; }
  if str_compare(lower, "forgotten") == 0 { return "forget"; }
  if str_compare(lower, "froze") == 0 { return "freeze"; }
  if str_compare(lower, "frozen") == 0 { return "freeze"; }
  if str_compare(lower, "grew") == 0 { return "grow"; }
  if str_compare(lower, "grown") == 0 { return "grow"; }
  if str_compare(lower, "heard") == 0 { return "hear"; }
  if str_compare(lower, "hid") == 0 { return "hide"; }
  if str_compare(lower, "hidden") == 0 { return "hide"; }
  if str_compare(lower, "hit") == 0 { return "hit"; }
  if str_compare(lower, "hurt") == 0 { return "hurt"; }
  if str_compare(lower, "knew") == 0 { return "know"; }
  if str_compare(lower, "known") == 0 { return "know"; }
  if str_compare(lower, "led") == 0 { return "lead"; }
  if str_compare(lower, "lent") == 0 { return "lend"; }
  if str_compare(lower, "let") == 0 { return "let"; }
  if str_compare(lower, "lit") == 0 { return "light"; }
  if str_compare(lower, "meant") == 0 { return "mean"; }
  if str_compare(lower, "rode") == 0 { return "ride"; }
  if str_compare(lower, "ridden") == 0 { return "ride"; }
  if str_compare(lower, "rang") == 0 { return "ring"; }
  if str_compare(lower, "rung") == 0 { return "ring"; }
  if str_compare(lower, "sang") == 0 { return "sing"; }
  if str_compare(lower, "sung") == 0 { return "sing"; }
  if str_compare(lower, "sank") == 0 { return "sink"; }
  if str_compare(lower, "sunk") == 0 { return "sink"; }
  if str_compare(lower, "shot") == 0 { return "shoot"; }
  if str_compare(lower, "showed") == 0 { return "show"; }
  if str_compare(lower, "shown") == 0 { return "show"; }
  if str_compare(lower, "shut") == 0 { return "shut"; }
  if str_compare(lower, "stole") == 0 { return "steal"; }
  if str_compare(lower, "stolen") == 0 { return "steal"; }
  if str_compare(lower, "swam") == 0 { return "swim"; }
  if str_compare(lower, "swum") == 0 { return "swim"; }
  if str_compare(lower, "threw") == 0 { return "throw"; }
  if str_compare(lower, "thrown") == 0 { return "throw"; }
  if str_compare(lower, "woke") == 0 { return "wake"; }
  if str_compare(lower, "woken") == 0 { return "wake"; }
  return "";
}

// Irregular comparative / superlative forms -> positive form. "" when absent.
fn _irregular_adj(lower: Str) -> Str {
  if str_compare(lower, "better") == 0 { return "good"; }
  if str_compare(lower, "best") == 0 { return "good"; }
  if str_compare(lower, "worse") == 0 { return "bad"; }
  if str_compare(lower, "worst") == 0 { return "bad"; }
  if str_compare(lower, "further") == 0 { return "far"; }
  if str_compare(lower, "furthest") == 0 { return "far"; }
  if str_compare(lower, "farther") == 0 { return "far"; }
  if str_compare(lower, "farthest") == 0 { return "far"; }
  if str_compare(lower, "elder") == 0 { return "old"; }
  if str_compare(lower, "eldest") == 0 { return "old"; }
  if str_compare(lower, "more") == 0 { return "much"; }
  if str_compare(lower, "most") == 0 { return "much"; }
  if str_compare(lower, "less") == 0 { return "little"; }
  if str_compare(lower, "least") == 0 { return "little"; }
  return "";
}

// Choose the POS-specific irregular table. Unknown POS uses the noun table.
fn _irregular(lower: Str, pos: Str) -> Str {
  if str_compare(pos, "v") == 0 { return _irregular_verb(lower); }
  if str_compare(pos, "a") == 0 { return _irregular_adj(lower); }
  return _irregular_noun(lower);
}

// --- exception dictionary ---------------------------------------------------

// Forms whose correct lemma the suffix rules would miss. Shared by all POS
// and consulted after the POS-specific irregular table. "" when absent.
fn _exception(lower: Str) -> Str {
  if str_compare(lower, "agreed") == 0 { return "agree"; }
  if str_compare(lower, "freed") == 0 { return "free"; }
  if str_compare(lower, "guaranteed") == 0 { return "guarantee"; }
  if str_compare(lower, "used") == 0 { return "use"; }
  if str_compare(lower, "using") == 0 { return "use"; }
  if str_compare(lower, "causing") == 0 { return "cause"; }
  if str_compare(lower, "becoming") == 0 { return "become"; }
  if str_compare(lower, "leaving") == 0 { return "leave"; }
  if str_compare(lower, "believed") == 0 { return "believe"; }
  if str_compare(lower, "believing") == 0 { return "believe"; }
  if str_compare(lower, "received") == 0 { return "receive"; }
  if str_compare(lower, "receiving") == 0 { return "receive"; }
  if str_compare(lower, "achieved") == 0 { return "achieve"; }
  if str_compare(lower, "achieving") == 0 { return "achieve"; }
  if str_compare(lower, "died") == 0 { return "die"; }
  if str_compare(lower, "dies") == 0 { return "die"; }
  if str_compare(lower, "dying") == 0 { return "die"; }
  if str_compare(lower, "tied") == 0 { return "tie"; }
  if str_compare(lower, "ties") == 0 { return "tie"; }
  if str_compare(lower, "tying") == 0 { return "tie"; }
  if str_compare(lower, "lied") == 0 { return "lie"; }
  if str_compare(lower, "lies") == 0 { return "lie"; }
  if str_compare(lower, "lying") == 0 { return "lie"; }
  if str_compare(lower, "vied") == 0 { return "vie"; }
  if str_compare(lower, "vies") == 0 { return "vie"; }
  if str_compare(lower, "vying") == 0 { return "vie"; }
  if str_compare(lower, "changed") == 0 { return "change"; }
  if str_compare(lower, "changing") == 0 { return "change"; }
  if str_compare(lower, "arranged") == 0 { return "arrange"; }
  if str_compare(lower, "arranging") == 0 { return "arrange"; }
  if str_compare(lower, "managed") == 0 { return "manage"; }
  if str_compare(lower, "managing") == 0 { return "manage"; }
  if str_compare(lower, "judged") == 0 { return "judge"; }
  if str_compare(lower, "judging") == 0 { return "judge"; }
  if str_compare(lower, "imagined") == 0 { return "imagine"; }
  if str_compare(lower, "imagining") == 0 { return "imagine"; }
  if str_compare(lower, "damaged") == 0 { return "damage"; }
  if str_compare(lower, "damaging") == 0 { return "damage"; }
  if str_compare(lower, "controlled") == 0 { return "control"; }
  if str_compare(lower, "controlling") == 0 { return "control"; }
  if str_compare(lower, "travelled") == 0 { return "travel"; }
  if str_compare(lower, "travelling") == 0 { return "travel"; }
  if str_compare(lower, "cancelled") == 0 { return "cancel"; }
  if str_compare(lower, "cancelling") == 0 { return "cancel"; }
  if str_compare(lower, "added") == 0 { return "add"; }
  if str_compare(lower, "movies") == 0 { return "movie"; }
  if str_compare(lower, "cookies") == 0 { return "cookie"; }
  if str_compare(lower, "pies") == 0 { return "pie"; }
  if str_compare(lower, "series") == 0 { return "series"; }
  if str_compare(lower, "species") == 0 { return "species"; }
  if str_compare(lower, "news") == 0 { return "news"; }
  if str_compare(lower, "gas") == 0 { return "gas"; }
  if str_compare(lower, "yes") == 0 { return "yes"; }
  if str_compare(lower, "physics") == 0 { return "physics"; }
  if str_compare(lower, "buses") == 0 { return "bus"; }
  if str_compare(lower, "gases") == 0 { return "gas"; }
  if str_compare(lower, "statuses") == 0 { return "status"; }
  if str_compare(lower, "quizzes") == 0 { return "quiz"; }
  if str_compare(lower, "larger") == 0 { return "large"; }
  if str_compare(lower, "largest") == 0 { return "large"; }
  if str_compare(lower, "stranger") == 0 { return "strange"; }
  if str_compare(lower, "strangest") == 0 { return "strange"; }
  if str_compare(lower, "simpler") == 0 { return "simple"; }
  if str_compare(lower, "simplest") == 0 { return "simple"; }
  if str_compare(lower, "gentler") == 0 { return "gentle"; }
  if str_compare(lower, "gentlest") == 0 { return "gentle"; }
  if str_compare(lower, "humbler") == 0 { return "humble"; }
  if str_compare(lower, "humblest") == 0 { return "humble"; }
  if str_compare(lower, "idler") == 0 { return "idle"; }
  if str_compare(lower, "idlest") == 0 { return "idle"; }
  return "";
}

// --- noun suffix rules (longest suffix first) -------------------------------

// Known -oes plurals that keep their -o singular. "" when absent.
fn _noun_oes_singular(lower: Str) -> Str {
  if str_compare(lower, "heroes") == 0 { return "hero"; }
  if str_compare(lower, "potatoes") == 0 { return "potato"; }
  if str_compare(lower, "tomatoes") == 0 { return "tomato"; }
  if str_compare(lower, "echoes") == 0 { return "echo"; }
  if str_compare(lower, "vetoes") == 0 { return "veto"; }
  if str_compare(lower, "volcanoes") == 0 { return "volcano"; }
  if str_compare(lower, "torpedoes") == 0 { return "torpedo"; }
  return "";
}

// Noun rules for an already-lowercased ASCII word.
fn _noun_rules(lower: Str) -> Str {
  let n = str_len(lower);
  if n >= 4 && str_ends_with(lower, "ies") { return _replace_suffix(lower, "ies", "y"); }
  if str_ends_with(lower, "ves") { return _drop_last_byte(lower); }
  if str_ends_with(lower, "ches") || str_ends_with(lower, "shes") {
    if n >= 4 { return _replace_suffix(lower, "es", ""); }
  }
  if str_ends_with(lower, "sses") || str_ends_with(lower, "xes") || str_ends_with(lower, "zes") {
    if n >= 4 { return _replace_suffix(lower, "es", ""); }
  }
  if str_ends_with(lower, "oes") {
    let known = _noun_oes_singular(lower);
    if str_len(known) > 0 { return known; }
    return _drop_last_byte(lower);
  }
  if str_ends_with(lower, "ss") { return lower; }
  if str_ends_with(lower, "us") { return lower; }
  if str_ends_with(lower, "is") { return lower; }
  if n >= 3 && str_ends_with(lower, "s") { return _drop_last_byte(lower); }
  return lower;
}

// --- verb suffix rules (longest suffix first) -------------------------------

// Verb rules for an already-lowercased ASCII word.
fn _verb_rules(lower: Str) -> Str {
  let n = str_len(lower);
  if n >= 4 && str_ends_with(lower, "ies") { return _replace_suffix(lower, "ies", "y"); }
  if n >= 5 && str_ends_with(lower, "ing") {
    let stem = _replace_suffix(lower, "ing", "");
    if str_len(stem) >= 2 && _has_vowel(stem) { return _restore_base(stem); }
    return lower;
  }
  if n >= 4 && str_ends_with(lower, "ied") { return _replace_suffix(lower, "ied", "y"); }
  if n >= 4 && str_ends_with(lower, "ed") {
    let stem = _replace_suffix(lower, "ed", "");
    if str_len(stem) >= 2 && _has_vowel(stem) { return _restore_base(stem); }
    return lower;
  }
  if str_ends_with(lower, "ches") || str_ends_with(lower, "shes") {
    if n >= 4 { return _replace_suffix(lower, "es", ""); }
  }
  if str_ends_with(lower, "sses") || str_ends_with(lower, "xes") || str_ends_with(lower, "zes") {
    if n >= 4 { return _replace_suffix(lower, "es", ""); }
  }
  if str_ends_with(lower, "ss") { return lower; }
  if str_ends_with(lower, "us") { return lower; }
  if str_ends_with(lower, "is") { return lower; }
  if n >= 3 && str_ends_with(lower, "s") { return _drop_last_byte(lower); }
  return lower;
}

// --- adjective suffix rules (longest suffix first) --------------------------

// Shared adjective comparatives/superlatives stem fixup.
fn _adj_base(stem: Str) -> Str {
  if _drops_double(stem) { return _drop_last_byte(stem); }
  if _ends_cvc(stem) && _count_vowels(stem) == 1 { return stem + "e"; }
  if _ends_l_after_consonant(stem) { return stem + "e"; }
  return stem;
}

// Adjective rules for an already-lowercased ASCII word.
fn _adj_rules(lower: Str) -> Str {
  let n = str_len(lower);
  if n >= 5 && str_ends_with(lower, "iest") { return _replace_suffix(lower, "iest", "y"); }
  if n >= 4 && str_ends_with(lower, "ier") { return _replace_suffix(lower, "ier", "y"); }
  if n >= 4 && str_ends_with(lower, "est") { return _adj_base(_replace_suffix(lower, "est", "")); }
  if n >= 3 && str_ends_with(lower, "er") { return _adj_base(_replace_suffix(lower, "er", "")); }
  return lower;
}

// Dispatch to the POS rule set. Unknown POS uses the noun rules.
fn _apply_rules(lower: Str, pos: Str) -> Str {
  if str_compare(pos, "v") == 0 { return _verb_rules(lower); }
  if str_compare(pos, "a") == 0 { return _adj_rules(lower); }
  return _noun_rules(lower);
}

// --- public API -------------------------------------------------------------

/// Lemmatize one English word.
/// Params: word - the token; only ASCII-letter tokens are processed
/// ("Lower", "lower" or "LOWER" casing is accepted, mixed case is returned
/// unchanged). pos - a POS tag: "n" noun, "v" verb, "a" adjective; any other
/// value selects the noun rules.
/// Returns: the lemma. Casing is restored: "Cats" -> "Cat", "CATS" -> "CAT".
/// Error case: none. Non-ASCII-letter tokens are returned unchanged.
/// Complexity: O(|word| * table size).
pub fn lemmatize(word: Str, pos: Str) -> Str {
  if str_len(word) == 0 { return ""; }
  if !_letters_only(word) { return word; }
  let is_lower = _all_lower(word);
  let is_cap = _capitalized(word);
  let is_upper = _all_upper(word);
  if !is_lower && !is_cap && !is_upper { return word; }
  let lower = str_lowercase(word);
  let irregular = _irregular(lower, pos);
  var result = lower;
  if str_len(irregular) > 0 {
    result = irregular;
  } else {
    let ex = _exception(lower);
    if str_len(ex) > 0 {
      result = ex;
    } else {
      result = _apply_rules(lower, pos);
    }
  }
  if is_upper { return str_uppercase(result); }
  if is_cap { return _capitalize_first(result); }
  return result;
}

/// Lemmatize a token vector with a parallel POS-tag vector.
/// Params: words - the tokens; tags - POS tags, one per token.
/// Returns: a fresh Vec[Str] of the same length as `words`; a token whose
/// tag index is missing from `tags` uses "n" (noun rules).
/// Error case: none. Complexity: O(total input bytes * table size).
pub fn lemmatize_all(words: &Vec[Str], tags: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = words.len();
  var i: Int = 0;
  while i < n {
    let w: Str = words[i];
    var tag = "n";
    if i < tags.len() {
      let t: Str = tags[i];
      tag = t;
    }
    out.push(lemmatize(w, tag));
    i = i + 1;
  }
  return out;
}

/// True when the word appears in any irregular table (noun, verb or
/// adjective), case-insensitively.
/// Params: word - the token to test.
/// Returns: false for words handled by suffix rules ("cats", "running").
/// Error case: none. Complexity: O(|word| * table size).
pub fn lemmatize_is_irregular(word: Str) -> Bool {
  if str_len(word) == 0 { return false; }
  if !_letters_only(word) { return false; }
  let lower = str_lowercase(word);
  if str_len(_irregular_noun(lower)) > 0 { return true; }
  if str_len(_irregular_verb(lower)) > 0 { return true; }
  if str_len(_irregular_adj(lower)) > 0 { return true; }
  return false;
}
