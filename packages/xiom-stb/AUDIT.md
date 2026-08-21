# xiom-stb -- System Dependency Audit

## Dependency: stb_image (Single-Header Image Library)

This package provides FFI bindings to the stb_image library by Sean Barrett. stb_image is header-only; it must be compiled into a shared library for FFI use.

### Target Library

- **All platforms:** `libstb_image.so` / `stb_image.dll` / `libstb_image.dylib`

### Fetch & Compile the Shared Library

**Step 1 -- Download stb_image.h**
```
curl -O https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
curl -O https://raw.githubusercontent.com/nothings/stb/master/stb_image_write.h
```

**Step 2 -- Create the C wrapper (`stb_wrapper.c`)**
```c
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
```

**Step 3 -- Compile to shared library**

Windows (MSVC):
```
cl /LD stb_wrapper.c /Fe:stb_image.dll
```

Windows (MinGW):
```
gcc -shared -o stb_image.dll stb_wrapper.c
```

Linux:
```
gcc -shared -fPIC -o libstb_image.so stb_wrapper.c
```

macOS:
```
gcc -shared -fPIC -o libstb_image.dylib stb_wrapper.c
```

**Step 4 -- Place the shared library**
- Place the resulting `.dll`/`.so`/`.dylib` alongside your compiled XIOM executable, or in a system library path.

### Build & Link

When compiling an XIOM program that uses `xiom-stb`:
```
xiom --link stb_image -o app.exe src/main.xi
```

### Supported Formats

stb_image loads: PNG, JPG, BMP, TGA, GIF, PSD, HDR, PIC, PNM
stb_image_write writes: PNG, JPG, BMP, TGA

### Version Compatibility

- stb_image v2.29 (recommended -- latest from `nothings/stb` master)
- stb_image v2.28+
