# xiom-algo

> Pure XIOM algorithm library — sorting, searching, math, and combinatorics. Zero dependencies.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-algo provides 40+ production-grade algorithms implemented in pure XIOM. Every function includes compile-time contracts (`requires:`/`ensures:`) guaranteeing correctness at the compiler level.

## Installation

```bash
xiom install xiom-algo
```

## Quick Start

```xiom
use xiom.algo;

fn main() -> Int {
  var arr = [5, 2, 8, 1, 9];
  var sorted = quicksort(arr);
  var found = binary_search(&sorted, 5);
  return 0;
}
```

## API Reference

### Searching (6 functions)
| Function | Complexity | Description |
|----------|-----------|-------------|
| `binary_search(arr, target)` | O(log n) | Binary search on sorted array |
| `binary_search_insert_pos(arr, target)` | O(log n) | Find insertion index |
| `linear_search(arr, target)` | O(n) | Linear scan |
| `find_min(arr)` | O(n) | Find minimum value |
| `find_max(arr)` | O(n) | Find maximum value |
| `find_min_max(arr)` | O(n) | Find both in one pass |

### Sorting (6 functions)
| Function | Complexity | Description |
|----------|-----------|-------------|
| `quicksort(arr)` | O(n log n) | Quick sort (returns new Vec) |
| `merge_sort(arr)` | O(n log n) | Merge sort |
| `insertion_sort(arr)` | O(n²) | Insertion sort |
| `bubble_sort(arr)` | O(n²) | Bubble sort |
| `selection_sort(arr)` | O(n²) | Selection sort |
| `counting_sort(arr, max_val)` | O(n+k) | Counting sort |
| `is_sorted(arr)` | O(n) | Check if sorted |

### Math (12 functions)
| Function | Description |
|----------|-------------|
| `gcd(a, b)` | Greatest common divisor |
| `lcm(a, b)` | Least common multiple |
| `factorial(n)` | n! (n ≤ 20) |
| `fibonacci(n)` | nth Fibonacci number |
| `power(base, exp)` | Exponentiation |
| `is_power_of_two(n)` | Power-of-two check |
| `is_prime(n)` | Primality test O(√n) |
| `sieve_of_eratosthenes(n)` | All primes ≤ n |
| `abs(n)`, `min_val(a,b)`, `max_val(a,b)`, `clamp(v,lo,hi)` | Utility |

### Combinatorics (2 functions)
| Function | Description |
|----------|-------------|
| `binomial(n, k)` | n choose k |
| `catalan(n)` | nth Catalan number |

### Array Utilities (10 functions)
| Function | Description |
|----------|-------------|
| `reverse(arr)` | Reverse a Vec |
| `rotate_left(arr, k)` | Rotate left by k |
| `rotate_right(arr, k)` | Rotate right by k |
| `prefix_sum(arr)` | Prefix sum array |
| `shuffle(arr)` | Fisher-Yates shuffle |
| `slice(arr, start, len)` | Extract subarray |
| `concat(a, b)` | Concatenate two Vecs |
| `unique(sorted)` | Deduplicate sorted Vec |
| `count_if(arr, target)` | Count occurrences |
| `find_all(arr, target)` | All matching indices |

### Sequence Analysis (3 functions)
| Function | Description |
|----------|-------------|
| `is_palindrome(arr)` | Palindrome check |
| `longest_increasing_subsequence(arr)` | LIS length (DP) |
| `max_subarray_sum(arr)` | Kadane's algorithm |

## Safety Contracts

Every function with preconditions is guarded:
- `binary_search`: requires arr.len() > 0
- `gcd/lcm`: require a > 0, b > 0
- `factorial`: requires n >= 0, n <= 20
- `sieve`: requires n >= 2
- `quicksort/merge_sort`: ensures result.len() == input.len()

## Production Readiness

| Feature | Status |
|---------|--------|
| All 40 algorithm implementations | ✅ Complete |
| Time/space complexity documented | ✅ Complete |
| Compile-time contracts | ✅ Complete |
| O(n log n) sorting | ✅ Complete |
| O(log n) searching | ✅ Complete |
| Generic [T: Ord] support | ❌ Compiler limitation (codegen skips generics) |
| Graph algorithms (BFS/DFS/Dijkstra) | ❌ Not yet |
| String algorithms (KMP, Rabin-Karp) | ❌ Not yet |
| Float algorithms | ❌ Not yet |

### What's Left for v1.0
1. **Generic type support** — blocked on compiler `[T: Ord]` codegen
2. **Graph algorithms** — BFS, DFS, Dijkstra, A*, topological sort
3. **String algorithms** — KMP, Boyer-Moore, Levenshtein, longest common subsequence
4. **Float support** — `sqrt`, `pow`, `log`, `sin/cos` via Taylor series
5. **FFT** — Fast Fourier Transform

## Dependencies

**None.** Pure XIOM.

## Build & Run

```bash
xiom --run myprogram.xi
```

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
