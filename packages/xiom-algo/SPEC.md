# xiom.algo Specification

Comprehensive algorithm library for the XIOM language -- sorting, searching, math, combinatorics, and vector utilities. All implementations are concrete over `Int` to avoid codegen issues with generic constraints.

---

## Function Catalog

### Searching

| Function | Signature | Time | Space | Description |
|---|---|---|---|---|
| `binary_search` | `(arr: &Vec[Int], target: Int) -> Option[Int]` | O(log n) | O(1) | Index of `target` in sorted `arr`, or `None` |
| `binary_search_insert_pos` | `(arr: &Vec[Int], target: Int) -> Int` | O(log n) | O(1) | Insertion index to maintain sorted order |
| `linear_search` | `(arr: &Vec[Int], target: Int) -> Option[Int]` | O(n) | O(1) | First index of `target`, or `None` |
| `find_min` | `(arr: &Vec[Int]) -> Option[Int]` | O(n) | O(1) | Minimum element, or `None` if empty |
| `find_max` | `(arr: &Vec[Int]) -> Option[Int]` | O(n) | O(1) | Maximum element, or `None` if empty |
| `find_min_max` | `(arr: &Vec[Int]) -> (Int, Int)` | O(n) | O(1) | Both min and max in one pass |

---

### Sorting

| Function | Signature | Time | Space | Stable | Description |
|---|---|---|---|---|---|
| `quicksort` | `(arr: Vec[Int]) -> Vec[Int]` | O(n log n) avg / O(n2) worst | O(n) | No | In-place partition, new Vec returned |
| `merge_sort` | `(arr: Vec[Int]) -> Vec[Int]` | O(n log n) | O(n) | Yes | Divide-and-conquer, stable |
| `insertion_sort` | `(arr: Vec[Int]) -> Vec[Int]` | O(n2) avg / O(n) best | O(1) | Yes | Efficient for small or nearly-sorted |
| `bubble_sort` | `(arr: Vec[Int]) -> Vec[Int]` | O(n2) avg / O(n) best | O(1) | Yes | Early-exit on sorted input |
| `selection_sort` | `(arr: Vec[Int]) -> Vec[Int]` | O(n2) | O(1) | No | Minimal swaps |
| `counting_sort` | `(arr: Vec[Int], max_val: Int) -> Vec[Int]` | O(n + k) where k = max_val | O(k) | Yes | Integer keys only, non-comparison |
| `is_sorted` | `(arr: &Vec[Int]) -> Bool` | O(n) | O(1) | -- | Ascending-order check |

---

### Math

| Function | Signature | Time | Space | Description |
|---|---|---|---|---|
| `gcd` | `(a: Int, b: Int) -> Int` | O(log min(a,b)) | O(1) | Greatest common divisor (Euclidean) |
| `lcm` | `(a: Int, b: Int) -> Int` | O(log min(a,b)) | O(1) | Least common multiple via `a / gcd(a,b) * b` |
| `factorial` | `(n: Int) -> Int` | O(n) | O(1) | n!, bounded to n <= 20 |
| `fibonacci` | `(n: Int) -> Int` | O(n) | O(1) | nth Fibonacci (0-indexed), iterative DP |
| `power` | `(base: Int, exp: Int) -> Int` | O(log exp) | O(1) | Exponentiation by squaring |
| `is_power_of_two` | `(n: Int) -> Bool` | O(1) | O(1) | `n & (n-1) == 0` bit test |
| `abs` | `(n: Int) -> Int` | O(1) | O(1) | Absolute value |
| `min_val` | `(a: Int, b: Int) -> Int` | O(1) | O(1) | Minimum of two values |
| `max_val` | `(a: Int, b: Int) -> Int` | O(1) | O(1) | Maximum of two values |
| `clamp` | `(value: Int, lo: Int, hi: Int) -> Int` | O(1) | O(1) | Clamp to [lo, hi] inclusive |
| `is_prime` | `(n: Int) -> Bool` | O(sqrtn) | O(1) | Trial division primality test |
| `sieve_of_eratosthenes` | `(n: Int) -> Vec[Int]` | O(n log log n) | O(n) | All primes up to n |

---

### Combinatorics

| Function | Signature | Time | Space | Description |
|---|---|---|---|---|
| `binomial` | `(n: Int, k: Int) -> Int` | O(k) | O(1) | C(n,k) via multiplicative formula |
| `catalan` | `(n: Int) -> Int` | O(n) | O(1) | nth Catalan number: `C(2n,n) / (n+1)` |

---

### Array / Vector Utilities

| Function | Signature | Time | Space | Description |
|---|---|---|---|---|
| `reverse` | `(arr: Vec[Int]) -> Vec[Int]` | O(n) | O(1) | In-place reversal, returns same Vec |
| `rotate_left` | `(arr: Vec[Int], k: Int) -> Vec[Int]` | O(n) | O(n) | Left-rotate by k positions |
| `rotate_right` | `(arr: Vec[Int], k: Int) -> Vec[Int]` | O(n) | O(n) | Right-rotate by k positions |
| `prefix_sum` | `(arr: &Vec[Int]) -> Vec[Int]` | O(n) | O(n) | Cumulative sum array |
| `shuffle` | `(arr: Vec[Int]) -> Vec[Int]` | O(n) | O(1) | Fisher-Yates in-place shuffle (LCG-based) |
| `slice` | `(arr: &Vec[Int], start: Int, len: Int) -> Vec[Int]` | O(len) | O(len) | Sub-vector from `start`, `len` elements |
| `concat` | `(a: Vec[Int], b: Vec[Int]) -> Vec[Int]` | O(n+m) | O(n+m) | Concatenate two vectors |
| `unique` | `(arr: Vec[Int]) -> Vec[Int]` | O(n log n) | O(n) | Deduplicate (sorts first) |
| `count_if` | `(arr: &Vec[Int], target: Int) -> Int` | O(n) | O(1) | Count occurrences of `target` |
| `find_all` | `(arr: &Vec[Int], target: Int) -> Vec[Int]` | O(n) | O(k) | All indices where element equals `target` |

---

### Sequence Analysis

| Function | Signature | Time | Space | Description |
|---|---|---|---|---|
| `is_palindrome` | `(arr: &Vec[Int]) -> Bool` | O(n) | O(1) | Reads same forward/backward |
| `longest_increasing_subsequence` | `(arr: &Vec[Int]) -> Int` | O(n2) | O(n) | Length of LIS (DP solution) |
| `max_subarray_sum` | `(arr: &Vec[Int]) -> Int` | O(n) | O(1) | Kadane's algorithm, maximum contiguous sum |

---

## Contract Guarantees

### `binary_search`
- **requires:** `arr.len() > 0`
- Behavior: Performs binary search on a sorted array. Caller must ensure the input is sorted.

### `gcd`
- **requires:** `a > 0`, `b > 0`
- Behavior: Euclidean algorithm. Returns the greatest integer dividing both inputs.

### `lcm`
- **requires:** `a > 0`, `b > 0`
- Behavior: Computes `(a / gcd(a,b)) * b` to avoid intermediate overflow.

### `factorial`
- **requires:** `n >= 0`, `n <= 20`
- Behavior: Upper bound of 20 prevents integer overflow for 64-bit Int.

### `fibonacci`
- **requires:** `n >= 0`
- Behavior: 0-indexed. `fibonacci(0)` -> 0, `fibonacci(1)` -> 1, `fibonacci(2)` -> 1.

### `power`
- **requires:** `exp >= 0`
- Behavior: Exponentiation by squaring. `power(2, 10)` -> 1024.

### `is_power_of_two`
- **requires:** `n > 0`
- Behavior: Bitwise test. Returns false for n <= 0.

### `clamp`
- **requires:** `lo <= hi`
- Behavior: Returns `lo` if `value < lo`, `hi` if `value > hi`, `value` otherwise.

### `is_prime`
- **requires:** `n >= 0`
- Behavior: Trial division up to sqrtn. Returns false for n < 2.

### `sieve_of_eratosthenes`
- **requires:** `n >= 2`
- Behavior: Returns all prime numbers from 2 to n inclusive.

### `binomial`
- **requires:** `n >= 0`, `k >= 0`, `k <= n`
- Behavior: Uses multiplicative formula with symmetry optimization (`k > n-k`).

### `catalan`
- **requires:** `n >= 0`
- Behavior: Integer arithmetic via binomial coefficient.

### `find_min_max`
- **requires:** `arr.len() > 0`
- Behavior: Returns tuple `(min, max)`. Single-pass algorithm.

### `counting_sort`
- **requires:** `max_val >= 0`
- Behavior: All elements must be in [0, max_val]. Non-comparison integer sort.

### `slice`
- **requires:** `start >= 0`, `len >= 0`, `start + len <= arr.len()`
- Behavior: Returns new Vec with `len` elements starting at index `start`.

### `unique`
- **ensures:** `is_sorted(&result)`
- Behavior: Sorts input first, then removes consecutive duplicates. Result is sorted and unique.

### `max_subarray_sum`
- **requires:** `arr.len() > 0`
- Behavior: Kadane's algorithm. Returns maximum sum of any contiguous subarray.

---

## Usage Examples

```xiom
import xiom_algo.{*}

fn main() {
  // Searching
  var sorted = Vec[Int].new();
  sorted.push(1); sorted.push(3); sorted.push(5); sorted.push(7); sorted.push(9);
  var idx = binary_search(&sorted, 5);       // Some(2)
  var pos = binary_search_insert_pos(&sorted, 6); // 3
  var not_found = linear_search(&sorted, 2); // None

  // Sorting
  var unsorted = Vec[Int].new();
  unsorted.push(5); unsorted.push(2); unsorted.push(8); unsorted.push(1);
  var sorted_quick = quicksort(unsorted);    // [1, 2, 5, 8]
  var sorted_merge = merge_sort(unsorted);   // [1, 2, 5, 8]
  var check = is_sorted(&sorted_quick);      // true

  // Math
  var g = gcd(48, 18);                       // 6
  var l = lcm(12, 18);                       // 36
  var f = fibonacci(10);                     // 55
  var p = power(2, 10);                      // 1024
  var prime = is_prime(17);                  // true
  var primes = sieve_of_eratosthenes(30);    // [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
  var clamp5 = clamp(10, 0, 5);             // 5

  // Combinatorics
  var bin = binomial(10, 3);                 // 120
  var cat = catalan(5);                      // 42

  // Array utilities
  var nums = Vec[Int].new();
  nums.push(1); nums.push(2); nums.push(3); nums.push(4); nums.push(5);
  var rev = reverse(nums);                   // [5, 4, 3, 2, 1]
  var rot = rotate_left(nums, 2);            // [3, 4, 5, 1, 2]
  var pref = prefix_sum(&nums);              // [1, 3, 6, 10, 15]
  var sub = slice(&nums, 1, 3);              // [2, 3, 4]
  var duped = Vec[Int].new();
  duped.push(1); duped.push(2); duped.push(2); duped.push(3); duped.push(3);
  var uniq = unique(duped);                  // [1, 2, 3]
  var cnt = count_if(&duped, 2);            // 2
  var idxs = find_all(&duped, 3);            // [3, 4]

  // Sequence analysis
  var pal = Vec[Int].new();
  pal.push(1); pal.push(2); pal.push(1);
  var is_pal = is_palindrome(&pal);          // true
  var seq = Vec[Int].new();
  seq.push(3); seq.push(1); seq.push(4); seq.push(1); seq.push(5);
  var lis_len = longest_increasing_subsequence(&seq); // 3 ([1, 4, 5])
  var sub_arr = Vec[Int].new();
  sub_arr.push(-2); sub_arr.push(1); sub_arr.push(-3); sub_arr.push(4);
  sub_arr.push(-1); sub_arr.push(2);
  var max_sum = max_subarray_sum(&sub_arr);  // 6 ([4, -1, 2])

  // Min/max
  var mn = find_min(&nums);                  // Some(1)
  var mx = find_max(&nums);                  // Some(5)
  var pair = find_min_max(&nums);            // (1, 5)
}
```

---

## Design Notes

- **No generics:** All functions use concrete `Int` types. Generic constraints (`[T: Ord]`) are avoided because the XIOM codegen silently drops functions with them.
- **While loops only:** No `for` loops. All iteration uses `while` per XIOM language constraints.
- **Contracts:** `requires` and `ensures` are used for preconditions and postconditions.
- **Shuffle randomness:** The Fisher-Yates shuffle uses a deterministic LCG (Linear Congruential Generator). Shuffles of equal-length arrays will produce the same permutation. This is acceptable for testing and deterministic use cases.
- **No silent failures:** Functions check preconditions via contracts. Empty-array cases return `None` from `Option`-typed functions or early-exit with appropriate defaults.
