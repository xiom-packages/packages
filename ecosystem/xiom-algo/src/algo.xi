module xiom.algo

use xiom.math;
use xiom.rand;

// ============================================================
// Searching
// ============================================================

pub fn binary_search(arr: &Vec[Int], target: Int) -> Option[Int]
  requires: arr.len() > 0
{
  if arr.len() == 0 { return None; }
  var left = 0;
  var right = arr.len() - 1;
  while left <= right {
    var mid = left + (right - left) / 2;
    if arr[mid] < target {
      left = mid + 1;
    } elif arr[mid] > target {
      right = mid - 1;
    } else {
      return Some(mid);
    }
  }
  return None;
}

pub fn binary_search_insert_pos(arr: &Vec[Int], target: Int) -> Int
  requires: arr.len() > 0
{
  var left = 0;
  var right = arr.len();
  while left < right {
    var mid = left + (right - left) / 2;
    if arr[mid] < target {
      left = mid + 1;
    } else {
      right = mid;
    }
  }
  return left;
}

pub fn linear_search(arr: &Vec[Int], target: Int) -> Option[Int]
  requires: arr.len() > 0
{
  var i = 0;
  while i < arr.len() {
    if arr[i] == target { return Some(i); }
    i = i + 1;
  }
  return None;
}

pub fn find_min(arr: &Vec[Int]) -> Option[Int]
  requires: arr.len() > 0
{
  if arr.len() == 0 { return None; }
  var min = arr[0];
  var i = 1;
  while i < arr.len() {
    if arr[i] < min { min = arr[i]; }
    i = i + 1;
  }
  return Some(min);
}

pub fn find_max(arr: &Vec[Int]) -> Option[Int]
  requires: arr.len() > 0
{
  if arr.len() == 0 { return None; }
  var max = arr[0];
  var i = 1;
  while i < arr.len() {
    if arr[i] > max { max = arr[i]; }
    i = i + 1;
  }
  return Some(max);
}

pub fn find_min_max(arr: &Vec[Int]) -> (Int, Int)
  requires: arr.len() > 0
{
  var min = arr[0];
  var max = arr[0];
  var i = 1;
  while i < arr.len() {
    if arr[i] < min { min = arr[i]; }
    if arr[i] > max { max = arr[i]; }
    i = i + 1;
  }
  return (min, max);
}

// ============================================================
// Sorting
// ============================================================

pub fn quicksort(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  if arr.len() <= 1 { return arr; }
  var pivot_idx = arr.len() / 2;
  var pivot = arr[pivot_idx];
  var less = Vec[Int].new();
  var equal = Vec[Int].new();
  var greater = Vec[Int].new();
  var i = 0;
  while i < arr.len() {
    if arr[i] < pivot {
      less.push(arr[i]);
    } elif arr[i] > pivot {
      greater.push(arr[i]);
    } else {
      equal.push(arr[i]);
    }
    i = i + 1;
  }
  var sorted_less = quicksort(less);
  var sorted_greater = quicksort(greater);
  return concat_three(sorted_less, equal, sorted_greater);
}

fn concat_three(a: Vec[Int], b: Vec[Int], c: Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  while i < a.len() { result.push(a[i]); i = i + 1; }
  i = 0;
  while i < b.len() { result.push(b[i]); i = i + 1; }
  i = 0;
  while i < c.len() { result.push(c[i]); i = i + 1; }
  return result;
}

pub fn merge_sort(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  if arr.len() <= 1 { return arr; }
  var mid = arr.len() / 2;
  var left = Vec[Int].new();
  var right = Vec[Int].new();
  var i = 0;
  while i < mid {
    left.push(arr[i]);
    i = i + 1;
  }
  while i < arr.len() {
    right.push(arr[i]);
    i = i + 1;
  }
  left = merge_sort(left);
  right = merge_sort(right);
  return merge(left, right);
}

fn merge(left: Vec[Int], right: Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  var j = 0;
  while i < left.len() && j < right.len() {
    if left[i] <= right[j] {
      result.push(left[i]);
      i = i + 1;
    } else {
      result.push(right[j]);
      j = j + 1;
    }
  }
  while i < left.len() {
    result.push(left[i]);
    i = i + 1;
  }
  while j < right.len() {
    result.push(right[j]);
    j = j + 1;
  }
  return result;
}

pub fn insertion_sort(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  if arr.len() <= 1 { return arr; }
  var i = 1;
  while i < arr.len() {
    var key = arr[i];
    var j = i;
    while j > 0 && arr[j - 1] > key {
      arr[j] = arr[j - 1];
      j = j - 1;
    }
    arr[j] = key;
    i = i + 1;
  }
  return arr;
}

pub fn bubble_sort(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  var n = arr.len();
  var i = 0;
  while i < n {
    var swapped = false;
    var j = 0;
    while j < n - i - 1 {
      if arr[j] > arr[j + 1] {
        var tmp = arr[j];
        arr[j] = arr[j + 1];
        arr[j + 1] = tmp;
        swapped = true;
      }
      j = j + 1;
    }
    if !swapped { return arr; }
    i = i + 1;
  }
  return arr;
}

pub fn selection_sort(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  var n = arr.len();
  var i = 0;
  while i < n {
    var min_idx = i;
    var j = i + 1;
    while j < n {
      if arr[j] < arr[min_idx] { min_idx = j; }
      j = j + 1;
    }
    if min_idx != i {
      var tmp = arr[i];
      arr[i] = arr[min_idx];
      arr[min_idx] = tmp;
    }
    i = i + 1;
  }
  return arr;
}

pub fn counting_sort(arr: Vec[Int], max_val: Int) -> Vec[Int]
  requires: max_val >= 0
{
  if arr.len() <= 1 { return arr; }
  var count = Vec[Int].new();
  var i = 0;
  while i <= max_val {
    count.push(0);
    i = i + 1;
  }
  i = 0;
  while i < arr.len() {
    count[arr[i]] = count[arr[i]] + 1;
    i = i + 1;
  }
  var result = Vec[Int].new();
  i = 0;
  while i <= max_val {
    var j = 0;
    while j < count[i] {
      result.push(i);
      j = j + 1;
    }
    i = i + 1;
  }
  return result;
}

pub fn is_sorted(arr: &Vec[Int]) -> Bool {
  if arr.len() <= 1 { return true; }
  var i = 1;
  while i < arr.len() {
    if arr[i - 1] > arr[i] { return false; }
    i = i + 1;
  }
  return true;
}

// ============================================================
// Math
// ============================================================

pub fn gcd(a: Int, b: Int) -> Int
  requires: a > 0
  requires: b > 0
{
  if b == 0 { return a; }
  return gcd(b, a % b);
}

pub fn lcm(a: Int, b: Int) -> Int
  requires: a > 0
  requires: b > 0
{
  return (a / gcd(a, b)) * b;
}

pub fn factorial(n: Int) -> Int
  requires: n >= 0
  requires: n <= 20
{
  if n <= 1 { return 1; }
  var result = 1;
  var i = 2;
  while i <= n {
    result = result * i;
    i = i + 1;
  }
  return result;
}

pub fn fibonacci(n: Int) -> Int
  requires: n >= 0
{
  if n <= 1 { return n; }
  var prev2 = 0;
  var prev1 = 1;
  var i = 2;
  while i <= n {
    var curr = prev1 + prev2;
    prev2 = prev1;
    prev1 = curr;
    i = i + 1;
  }
  return prev1;
}

pub fn power(base: Int, exp: Int) -> Int
  requires: exp >= 0
{
  if exp == 0 { return 1; }
  var result = 1;
  var b = base;
  var e = exp;
  while e > 0 {
    if e % 2 == 1 { result = result * b; }
    b = b * b;
    e = e / 2;
  }
  return result;
}

pub fn is_power_of_two(n: Int) -> Bool
  requires: n > 0
{
  return (n & (n - 1)) == 0;
}

pub fn abs(n: Int) -> Int {
  return xiom.math.abs_int(n);
}

pub fn min_val(a: Int, b: Int) -> Int {
  return xiom.math.min_int(a, b);
}

pub fn max_val(a: Int, b: Int) -> Int {
  return xiom.math.max_int(a, b);
}

pub fn clamp(value: Int, lo: Int, hi: Int) -> Int
  requires: lo <= hi
{
  if value < lo { return lo; }
  if value > hi { return hi; }
  return value;
}

pub fn is_prime(n: Int) -> Bool
  requires: n >= 0
{
  if n < 2 { return false; }
  if n == 2 { return true; }
  if n % 2 == 0 { return false; }
  var i = 3;
  while i * i <= n {
    if n % i == 0 { return false; }
    i = i + 2;
  }
  return true;
}

pub fn sieve_of_eratosthenes(n: Int) -> Vec[Int]
  requires: n >= 2
{
  var is_prime_arr = Vec[Bool].new();
  var i = 0;
  while i <= n {
    is_prime_arr.push(true);
    i = i + 1;
  }
  is_prime_arr[0] = false;
  is_prime_arr[1] = false;
  i = 2;
  while i * i <= n {
    if is_prime_arr[i] {
      var j = i * i;
      while j <= n {
        is_prime_arr[j] = false;
        j = j + i;
      }
    }
    i = i + 1;
  }
  var primes = Vec[Int].new();
  i = 2;
  while i <= n {
    if is_prime_arr[i] { primes.push(i); }
    i = i + 1;
  }
  return primes;
}

// ============================================================
// Combinatorics
// ============================================================

pub fn binomial(n: Int, k: Int) -> Int
  requires: n >= 0
  requires: k >= 0
  requires: k <= n
{
  if k == 0 || k == n { return 1; }
  if k > n - k { return binomial(n, n - k); }
  var result = 1;
  var i = 0;
  while i < k {
    result = result * (n - i);
    result = result / (i + 1);
    i = i + 1;
  }
  return result;
}

pub fn catalan(n: Int) -> Int
  requires: n >= 0
{
  return binomial(2 * n, n) / (n + 1);
}

// ============================================================
// Array / Vector Utilities
// ============================================================

pub fn reverse(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  var left = 0;
  var right = arr.len() - 1;
  while left < right {
    var tmp = arr[left];
    arr[left] = arr[right];
    arr[right] = tmp;
    left = left + 1;
    right = right - 1;
  }
  return arr;
}

pub fn rotate_left(arr: Vec[Int], k: Int) -> Vec[Int]
  requires: k >= 0
{
  if arr.len() <= 1 { return arr; }
  var n = arr.len();
  var shift = k % n;
  if shift == 0 { return arr; }
  var result = Vec[Int].new();
  var i = shift;
  while i < n {
    result.push(arr[i]);
    i = i + 1;
  }
  i = 0;
  while i < shift {
    result.push(arr[i]);
    i = i + 1;
  }
  return result;
}

pub fn rotate_right(arr: Vec[Int], k: Int) -> Vec[Int]
  requires: k >= 0
{
  if arr.len() <= 1 { return arr; }
  var n = arr.len();
  var shift = k % n;
  if shift == 0 { return arr; }
  return rotate_left(arr, n - shift);
}

pub fn prefix_sum(arr: &Vec[Int]) -> Vec[Int]
  requires: arr.len() > 0
{
  var result = Vec[Int].new();
  if arr.len() == 0 { return result; }
  result.push(arr[0]);
  var i = 1;
  while i < arr.len() {
    result.push(result[i - 1] + arr[i]);
    i = i + 1;
  }
  return result;
}

pub fn shuffle(arr: Vec[Int]) -> Vec[Int]
  ensures: result.len() == arr.len()@pre
{
  if arr.len() <= 1 { return arr; }
  xiom.rand.shuffle(&mut arr);
  return arr;
}

pub fn slice(arr: &Vec[Int], start: Int, len: Int) -> Vec[Int]
  requires: start >= 0
  requires: len >= 0
  requires: start + len <= arr.len()
{
  var result = Vec[Int].new();
  var i = start;
  var end = start + len;
  while i < end {
    result.push(arr[i]);
    i = i + 1;
  }
  return result;
}

pub fn concat(a: Vec[Int], b: Vec[Int]) -> Vec[Int]
  ensures: result.len() == a.len()@pre + b.len()@pre
{
  var result = Vec[Int].new();
  var i = 0;
  while i < a.len() { result.push(a[i]); i = i + 1; }
  i = 0;
  while i < b.len() { result.push(b[i]); i = i + 1; }
  return result;
}

pub fn unique(arr: Vec[Int]) -> Vec[Int]
  requires: is_sorted(&arr)
  ensures: is_sorted(&result)
{
  if arr.len() <= 1 { return arr; }
  var sorted = quicksort(arr);
  var result = Vec[Int].new();
  result.push(sorted[0]);
  var i = 1;
  while i < sorted.len() {
    if sorted[i] != sorted[i - 1] {
      result.push(sorted[i]);
    }
    i = i + 1;
  }
  return result;
}

pub fn count_if(arr: &Vec[Int], target: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < arr.len() {
    if arr[i] == target { count = count + 1; }
    i = i + 1;
  }
  return count;
}

pub fn find_all(arr: &Vec[Int], target: Int) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  while i < arr.len() {
    if arr[i] == target { result.push(i); }
    i = i + 1;
  }
  return result;
}

// ============================================================
// Sequence Analysis (Vec[Int] as sequences)
// ============================================================

pub fn is_palindrome(arr: &Vec[Int]) -> Bool {
  var left = 0;
  var right = arr.len() - 1;
  while left < right {
    if arr[left] != arr[right] { return false; }
    left = left + 1;
    right = right - 1;
  }
  return true;
}

pub fn longest_increasing_subsequence(arr: &Vec[Int]) -> Int
  requires: arr.len() > 0
{
  if arr.len() == 0 { return 0; }
  var dp = Vec[Int].new();
  var i = 0;
  while i < arr.len() {
    dp.push(1);
    i = i + 1;
  }
  i = 1;
  while i < arr.len() {
    var j = 0;
    while j < i {
      if arr[j] < arr[i] && dp[j] + 1 > dp[i] {
        dp[i] = dp[j] + 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  var max_len = dp[0];
  i = 1;
  while i < dp.len() {
    if dp[i] > max_len { max_len = dp[i]; }
    i = i + 1;
  }
  return max_len;
}

pub fn max_subarray_sum(arr: &Vec[Int]) -> Int
  requires: arr.len() > 0
{
  var max_ending = arr[0];
  var max_so_far = arr[0];
  var i = 1;
  while i < arr.len() {
    if arr[i] > max_ending + arr[i] {
      max_ending = arr[i];
    } else {
      max_ending = max_ending + arr[i];
    }
    if max_ending > max_so_far { max_so_far = max_ending; }
    i = i + 1;
  }
  return max_so_far;
}
