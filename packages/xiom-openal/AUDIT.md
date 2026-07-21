# xiom-openal — System Dependency Audit

## Dependency: OpenAL SDK (OpenAL Soft)

This package provides FFI bindings to the OpenAL audio library. The native library must be installed on the target system.

### Target Library

- **Windows:** `OpenAL32.dll`
- **Linux:** `libopenal.so`
- **macOS:** `libopenal.dylib` (or system framework `OpenAL.framework`)

### Install Instructions

**Windows**
1. Download the OpenAL Soft installer from https://openal-soft.org/
2. Run the installer — places `OpenAL32.dll` in `C:\Windows\System32\` (64-bit: `SysWOW64\`)
3. Alternatively, download the pre-built DLL and place it alongside your executable

**Linux (Debian/Ubuntu)**
```
sudo apt install libopenal-dev libopenal1
```

**Linux (Fedora/RHEL)**
```
sudo dnf install openal-soft-devel openal-soft
```

**macOS**
```
brew install openal-soft
```
Or use the built-in OpenAL framework (no install required).

### Build & Link

When compiling an XIOM program that uses `xiom-openal`:
```
xiom --link OpenAL32 -o app.exe src/main.xi
```

On Linux: `--link openal`
On macOS: `--link openal` (or `-framework OpenAL`)

### Compiler Flags

The `.xiom-bind` file targets the `OpenAL32` library. If using OpenAL Soft on Linux/macOS, the library name is `openal` — adjust the linker flag accordingly.

### Version Compatibility

- OpenAL Soft 1.23.x (recommended)
- OpenAL Core API 1.1
- Creative OpenAL SDK (legacy, Windows only)
