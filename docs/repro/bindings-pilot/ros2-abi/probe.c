// ros2-abi probe: does the XIOM fn-cast call implement the MS x64 ABI for
// records passed/returned BY VALUE? Build: clang -shared -o probe.dll probe.c
// No CRT dependency: pure integer/pointer arithmetic.

typedef struct Alloc5_s {
  void * allocate;
  void * deallocate;
  void * reallocate;
  void * zero_allocate;
  void * state;
} Alloc5;

typedef struct Pair2_s {
  long long a;
  long long b;
} Pair2;

__declspec(dllexport) long long probe_sum5(Alloc5 al) {
  return (long long)al.allocate + (long long)al.deallocate +
         (long long)al.reallocate + (long long)al.zero_allocate +
         (long long)al.state;
}

__declspec(dllexport) Alloc5 probe_make5(long long base) {
  Alloc5 al;
  al.allocate = (void *)(base + 1);
  al.deallocate = (void *)(base + 2);
  al.reallocate = (void *)(base + 3);
  al.zero_allocate = (void *)(base + 4);
  al.state = (void *)(base + 5);
  return al;
}

__declspec(dllexport) long long probe_sum2(Pair2 p, long long bias) {
  return p.a * 1000 + p.b + bias;
}

__declspec(dllexport) Pair2 probe_make2(long long base) {
  Pair2 p;
  p.a = base + 7;
  p.b = base + 9;
  return p;
}

__declspec(dllexport) long long probe_mul(long long x, long long y) {
  return x * y;
}

__declspec(dllexport) long long probe_sum5p(Alloc5 * al) {
  return (long long)al->allocate + (long long)al->deallocate + (long long)al->reallocate + (long long)al->zero_allocate + (long long)al->state;
}


__declspec(dllexport) long long probe_ws9(void * ws, long long a, long long b, long long c, long long d, long long e, long long f, void * ctx, Alloc5 al) {
  long long s = (long long)ws + a + b + c + d + e + f + (long long)ctx;
  s += (long long)al.allocate + (long long)al.deallocate + (long long)al.reallocate + (long long)al.zero_allocate + (long long)al.state;
  return s;
}
__declspec(dllexport) long long probe_t7(void * t, void * cl, void * x, long long p, long long cb, Alloc5 al, long long au) {
  long long s = (long long)t + (long long)cl + (long long)x + p + cb + au;
  s += (long long)al.allocate + (long long)al.state;
  return s;
}
__declspec(dllexport) long long probe_c3(long long ty, void * cl, Alloc5 al) {
  return ty + (long long)cl + (long long)al.allocate + (long long)al.state;
}

