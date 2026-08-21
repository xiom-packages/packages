// XIOM -- xiom-algo Conformance Tests
// 33 tests covering searching, sorting, math, combinatorics, arrays, sequences
module algo_tests
use xiom.io; use xiom.test; use xiom.algo;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; } var num = n; var out = "";
  while num > 0 { let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10; }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

fn arr(vals: Vec[Int]) -> Vec[Int] { return vals; }

// Searching
fn t1() -> TestResult { let r = binary_search(arr([1,3,5,7,9]), 5); return assert(r == 2, "search: binary_search 5 at idx 2"); }
fn t2() -> TestResult { let r = binary_search(arr([1,3,5,7,9]), 99); return assert(r == -1, "search: binary_search miss => -1"); }
fn t3() -> TestResult { let r = linear_search(arr([10,20,30]), 20); return assert(r == 1, "search: linear_search 20 at idx 1"); }
fn t4() -> TestResult { let r = find_min(arr([5,3,8,1,4])); return assert(r == 1, "search: find_min => 1"); }
fn t5() -> TestResult { let r = find_max(arr([5,3,8,1,4])); return assert(r == 8, "search: find_max => 8"); }

// Sorting
fn t6() -> TestResult { let r = is_sorted(arr([1,2,3,4])); return assert(r, "sort: is_sorted true"); }
fn t7() -> TestResult { let r = is_sorted(arr([1,3,2,4])); return assert(!r, "sort: is_sorted false"); }
fn t8() -> TestResult { var s = quicksort(arr([3,1,4,1,5])); return assert(s.len() == 5, "sort: quicksort length preserved"); }
fn t9() -> TestResult { var s = merge_sort(arr([3,1,2])); return assert(is_sorted(s), "sort: merge_sort produces sorted"); }
fn t10() -> TestResult { var s = insertion_sort(arr([5,2,8,1])); return assert(is_sorted(s), "sort: insertion_sort sorted"); }
fn t11() -> TestResult { var s = bubble_sort(arr([4,2,1,3])); return assert(is_sorted(s), "sort: bubble_sort sorted"); }
fn t12() -> TestResult { var s = selection_sort(arr([3,1,2])); return assert(is_sorted(s), "sort: selection_sort sorted"); }
fn t13() -> TestResult { var s = counting_sort(arr([3,0,1,2]), 3); return assert(is_sorted(s), "sort: counting_sort sorted"); }

// Math
fn t14() -> TestResult { let r = gcd(12, 8); return assert(r == 4, "math: gcd(12,8)=4"); }
fn t15() -> TestResult { let r = lcm(6, 8); return assert(r == 24, "math: lcm(6,8)=24"); }
fn t16() -> TestResult { let r = factorial(5); return assert(r == 120, "math: 5! = 120"); }
fn t17() -> TestResult { let r = fibonacci(7); return assert(r == 13, "math: fib(7)=13"); }
fn t18() -> TestResult { let r = power(2, 10); return assert(r == 1024, "math: 2^10=1024"); }
fn t19() -> TestResult { let r = is_power_of_two(64); return assert(r, "math: is_power_of_two(64) true"); }
fn t20() -> TestResult { let r = is_prime(17); return assert(r, "math: 17 is prime"); }
fn t21() -> TestResult { let r = is_prime(100); return assert(!r, "math: 100 not prime"); }
fn t22() -> TestResult { let r = clamp(5, 0, 10); return assert(r == 5, "math: clamp(5,0,10)=5"); }
fn t23() -> TestResult { let r = clamp(15, 0, 10); return assert(r == 10, "math: clamp(15,0,10)=10"); }
fn t24() -> TestResult { var s = sieve_of_eratosthenes(20); return assert(s.len() == 8, "math: primes <=20 = 8"); }

// Combinatorics
fn t25() -> TestResult { let r = binomial(5, 2); return assert(r == 10, "comb: C(5,2)=10"); }
fn t26() -> TestResult { let r = catalan(4); return assert(r == 14, "comb: Catalan(4)=14"); }

// Arrays
fn t27() -> TestResult { var r = reverse(arr([1,2,3])); return assert(r.len() == 3, "arr: reverse length"); }
fn t28() -> TestResult { var r = slice(arr([0,1,2,3,4]), 1, 3); return assert(r.len() == 3, "arr: slice len=3"); }
fn t29() -> TestResult { var r = prefix_sum(arr([1,2,3])); return assert(r[2] == 6, "arr: prefix_sum [1,2,3]"); }
fn t30() -> TestResult { var r = concat(arr([1,2]), arr([3,4])); return assert(r.len() == 4, "arr: concat len=4"); }
fn t31() -> TestResult { var r = unique(arr([1,1,2,2,3,3])); return assert(r.len() == 3, "arr: unique len=3"); }

// Sequences
fn t32() -> TestResult { let r = is_palindrome(arr([1,2,1])); return assert(r, "seq: is_palindrome true"); }
fn t33() -> TestResult { let r = max_subarray_sum(arr([-2,1,-3,4,-1,2,1,-5,4])); return assert(r == 6, "seq: max_subarray_sum=6"); }

fn main() -> Int {
  io.println("=== XIOM Algo Conformance ===");
  var failed: Int = 0; var total: Int = 0;
  var tests = [t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33];
  var i = 0; while i < tests.len() { total = total + 1; failed = failed + report(tests[i]().passed, tests[i]().name); i = i + 1; }
  let passed = total - failed;
  io.println(""); io.println("XIOM Algo: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
