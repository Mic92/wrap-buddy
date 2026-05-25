# wrap-buddy

![wrap-buddy logo](https://github.com/Mic92/wrap-buddy/releases/download/assets/wrap-the-elf.png)

*"The best way to spread Christmas cheer is wrapping ELFs for all to hear!"*
— Buddy, probably

wrap-buddy is your enthusiastic helper for getting stubborn ELF binaries to run
on NixOS. Just like Buddy the Elf bringing holiday magic to New York City,
wrap-buddy brings NixOS compatibility to binaries that refuse to cooperate.

## Why wrap-buddy instead of autoPatchelfHook?

autoPatchelfHook rewrites ELF headers (interpreter path, RPATH) which can be
error-prone and may break binaries that, have unusual ELF layouts.

wrap-buddy takes a different approach: it patches the entry point to load a stub
that sets up the environment, then restores the original code before running.
The ELF headers remain mostly untouched (only PT_INTERP → PT_NULL).

Use wrap-buddy when autoPatchelfHook fails or breaks the binary.

## How it works

wrap-buddy uses a two-stage loader architecture:

1. **Stub** (~350 bytes): Written to the binary's entry point at build time.
   Loads the external loader and jumps to it.

1. **Loader** (~4KB): Pre-compiled flat binary that:

   - Reads config from `.<binary>.wrapbuddy`
   - Restores original entry point bytes
   - Sets up `DT_RUNPATH` in a new .dynamic section for library resolution
   - Loads the NixOS dynamic linker (ld.so)
   - Jumps directly to original entry point

```
Binary start
    │
    ▼
┌─────────┐     ┌─────────┐     ┌─────────┐
│  Stub   │────▶│ Loader  │────▶│  ld.so  │────▶ main()
└─────────┘     └─────────┘     └─────────┘
                     │
                     │ Sets DT_RUNPATH in memory
                     │ Loads NixOS ld.so
                     │ Restores entry bytes
                     ▼
```

The RPATH is set by creating a new .dynamic section in memory with a
`DT_RUNPATH` entry. This avoids modifying environment variables, so child
processes inherit a clean environment.

## Usage

Add wrap-buddy as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    wrap-buddy = {
      url = "github:Mic92/wrap-buddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Then use the `wrapBuddy` hook in your derivation:

```nix
{ stdenv, wrapBuddy, gcc-unwrapped, ... }:

stdenv.mkDerivation {
  # ...

  nativeBuildInputs = [ wrapBuddy ];

  # Runtime dependencies - wrapBuddy extracts library paths from these
  # and configures DT_RUNPATH so the binary can find them at runtime
  buildInputs = [
    gcc-unwrapped.lib  # provides libgcc_s.so.1, libstdc++.so
    # Add other runtime libraries as needed (e.g., libsecret, openssl)
  ];

  # The hook runs in fixupPhase and patches all ELF binaries
  # that have a non-NixOS interpreter (e.g., /lib64/ld-linux-x86-64.so.2)
}
```

## How Dependencies Work

wrap-buddy scans each binary's `DT_NEEDED` entries (like `autoPatchelfHook`)
and resolves them against `/lib` directories from `buildInputs`. If any
dependency is missing, the build fails with an error listing what's needed.

For libraries loaded via `dlopen()` at runtime (not linked at load time),
use `runtimeDependencies` - these are added to RPATH unconditionally:

```nix
runtimeDependencies = [ libayatana-appindicator ];
```

Some binaries load native addons that need libraries the main executable
doesn't link. If those addons can't be patched (e.g. embedded in a virtual
filesystem), use `wrapBuddyExtraNeeded` to inject `DT_NEEDED` entries at
runtime so ld.so loads the libraries at process start:

```nix
wrapBuddyExtraNeeded = [ "libstdc++.so.6" ];
```

Unlike `patchelf --add-needed`, this doesn't modify the binary on disk,
so it works with binaries that have appended payloads (e.g. bun-compiled
executables).

You can also manually add library search paths:

```nix
postFixup = ''
  addWrapBuddySearchPath /some/extra/lib/path
'';
```

## CLI Reference

```
wrap-buddy [options]

Options:
  --paths PATH...              Paths to scan for executables
  --libs PATH...               Library directories to search
  --runtime-dependencies PATH...  Paths added to RPATH unconditionally
  --ignore-missing PATTERN...  Patterns for deps to ignore if missing
  --needed SONAME...           Extra DT_NEEDED sonames to inject
  --no-recurse                 Don't recurse into subdirectories
  --dry-run                    Show what would be done
  --interpreter PATH           Path to dynamic linker
  --help                       Show help
```

### Examples

```bash
# Patch all binaries under ./out, resolve libs from ./lib
wrap-buddy --paths ./out --interpreter /lib64/ld-linux-x86-64.so.2 --libs ./lib

# Inject libstdc++ as a runtime dependency without modifying the binary
wrap-buddy --paths ./out/bin --interpreter /nix/store/.../ld-linux-x86-64.so.2 \
  --libs /nix/store/.../lib --needed libstdc++.so.6

# Dry run to see what would be patched
wrap-buddy --paths ./out --interpreter /lib64/ld-linux-x86-64.so.2 \
  --libs ./lib --dry-run
```

## Requirements

The binary must have sufficient space at the entry point for the stub (~400 bytes).

## Files created

For each patched binary `<name>`, the hook creates:

- `.<name>.wrapbuddy` - Hidden config file with original entry bytes,
  interpreter path, and library paths

## Limitations

- Linux only (x86_64, i386, and aarch64)
- Requires space at entry point for stub
- Binary must be writable during fixup phase

## Debugging

If a patched binary fails to start, check:

1. Config file exists: `ls -la .<binary>.wrapbuddy`
1. Interpreter is correct: `cat .<binary>.wrapbuddy | xxd | head`
1. Run with strace: `strace -f <binary>`

The loader prints debug info to stderr if it fails to load.

## Building from source

wrap-buddy builds two components:

- `loader.bin`: Flat binary loaded at runtime by patched binaries
- `wrap-buddy`: C++ patcher tool (with stub code embedded)

On x86_64, a 32-bit loader variant (`loader32.bin`) is also built.

### Make variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CC` | C compiler for target platform (stubs/loader) | `cc` |
| `CXX_FOR_BUILD` | C++ compiler for build platform (wrap-buddy) | `c++` |
| `OBJCOPY` | Binary extraction tool | `objcopy` |
| `XXD` | Hexdump tool for embedding binaries | `xxd` |
| `PREFIX` | Installation prefix | `/usr/local` |
| `BINDIR` | Binary directory | `$(PREFIX)/bin` |
| `LIBDIR` | Library directory | `$(PREFIX)/lib/wrap-buddy` |
| `DESTDIR` | Staging directory for packaging | (none) |
| `INTERP` | Default interpreter path (baked into binary) | (none) |
| `LIBC_LIB` | Default libc library path (baked into binary) | (none) |

### Cross-compilation

For cross-compilation, `CC` builds stubs for the **target** platform (what gets
patched), while `CXX_FOR_BUILD` builds wrap-buddy for the **build** platform
(what runs the patcher).

```bash
# Cross-compile for aarch64 from x86_64
make CC=aarch64-linux-gnu-gcc CXX_FOR_BUILD=g++
```

### Usage examples

```bash
# Traditional packaging
make
make install DESTDIR=/tmp/staging

# Nix packaging
make LIBDIR=$out/lib/wrap-buddy BINDIR=$out/bin
make install LIBDIR=$out/lib/wrap-buddy BINDIR=$out/bin
```

### Development

Generate a compilation database for IDE/LSP support:

```bash
make compile_commands.json
```

Run static analysis:

```bash
make clang-tidy
```
