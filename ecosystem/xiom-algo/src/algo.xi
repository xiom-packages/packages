module xiom.algo

// ============================================================
// Binary Search — O(log n) search on sorted Vec
// ============================================================

pub fn binary_search[T: Ord](arr: &Vec[T], target: T) -> Option[Int]
  ensures: result is Some => arr[result.unwrap()] == target
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

// ============================================================
// Quicksort — O(n log n) generic sort, returns new sorted Vec
// ============================================================

pub fn quicksort[T: Ord](arr: Vec[T]) -> Vec[T]
  ensures: result.is_sorted()
{
  if arr.len() <= 1 { return arr; }
  var pivot_idx = arr.len() / 2;
  var pivot = arr[pivot_idx];
  var less = Vec[T].new();
  var equal = Vec[T].new();
  var greater = Vec[T].new();
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

fn concat_three[T](a: Vec[T], b: Vec[T], c: Vec[T]) -> Vec[T] {
  var result = Vec[T].new();
  var i = 0;
  while i < a.len() { result.push(a[i]); i = i + 1; }
  i = 0;
  while i < b.len() { result.push(b[i]); i = i + 1; }
  i = 0;
  while i < c.len() { result.push(c[i]); i = i + 1; }
  return result;
}

// ============================================================
// Greatest Common Divisor — Euclidean algorithm
// ============================================================

pub fn gcd(a: Int, b: Int) -> Int
  requires: a > 0
  requires: b > 0
{
  if b == 0 { return a; }
  return gcd(b, a % b);
}

// ============================================================
// Fibonacci — iterative DP, O(n) time, O(1) space
// ============================================================

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

// ============================================================
// Sieve of Eratosthenes — returns all primes up to n
// ============================================================

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
// Primality Test — O(sqrt(n)) trial division
// ============================================================

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

// ============================================================
// Factorial — iterative, bounded to prevent overflow
// ============================================================

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
