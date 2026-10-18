#!/usr/bin/env bash
set -euo pipefail

# Integration tests for wrap-buddy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP_BUDDY="$SCRIPT_DIR/../wrap-buddy"
INTERP=""
LIBS=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --interp)
    INTERP="$2"
    shift 2
    ;;
  --libs)
    LIBS="$2"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ARCH=$(uname -m)
case $ARCH in
x86_64) FHS_INTERP="/lib64/ld-linux-x86-64.so.2" ;;
i686) FHS_INTERP="/lib/ld-linux.so.2" ;;
aarch64) FHS_INTERP="/lib/ld-linux-aarch64.so.1" ;;
*)
  echo "Unsupported architecture: $ARCH"
  exit 1
  ;;
esac

compile() {
  ${CC:-cc} -o "$TMPDIR/$1" "$SCRIPT_DIR/$2" \
    -Wl,--dynamic-linker="$FHS_INTERP" "${@:3}"
}

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  exit 1
}

# --- Test 1: basic patching -------------------------------------------

echo "=== Test: basic patching ==="
compile basic test_program.c

"$WRAP_BUDDY" --paths "$TMPDIR/basic" --interpreter "$INTERP" --libs "$LIBS"

output=$("$TMPDIR/basic" 2>&1)
echo "$output" | grep -q "Hello from patched binary!" ||
  fail "patched binary did not produce expected output"
pass "basic patching"

# --- Test 2: --needed injects DT_NEEDED at runtime --------------------

echo "=== Test: --needed injection ==="
${CC:-cc} -shared -fPIC -o "$TMPDIR/libneeded_test.so" \
  "$SCRIPT_DIR/test_needed_lib.c"

compile check test_needed_program.c

"$WRAP_BUDDY" --paths "$TMPDIR/check" --interpreter "$INTERP" \
  --libs "$LIBS" "$TMPDIR" --needed libneeded_test.so

output=$("$TMPDIR/check" 2>&1)
echo "$output" | grep -q "NEEDED_LOADED=yes" ||
  fail "injected DT_NEEDED library was not loaded"
pass "--needed injection"

# --- Test 3: --relocatable patching -----------------------------------

echo "=== Test: --relocatable ==="

compile relocatable test_program.c

"$WRAP_BUDDY" --paths "$TMPDIR/relocatable" --interpreter "$INTERP" --libs "$LIBS" --relocatable

output=$("$TMPDIR/relocatable" 2>&1)
echo "$output" | grep -q "Hello from patched binary!" ||
  fail "patched binary did not produce expected output"
pass "--relocatable patching"

# --- Test 4: --relocatable survives binary movement -------------------

echo "=== Test: --relocatable binary movement ==="

mkdir -p "$TMPDIR/staging/bin" "$TMPDIR/staging/lib"
cp "$SCRIPT_DIR/../loader.bin" "$TMPDIR/staging/lib/"

${CC:-cc} -o "$TMPDIR/staging/bin/movable" "$SCRIPT_DIR/test_program.c" \
  -Wl,--dynamic-linker="$FHS_INTERP"

"$WRAP_BUDDY" --paths "$TMPDIR/staging/bin" --interpreter "$INTERP" \
  --libs "$LIBS" --relocatable --loader-dir-path "$TMPDIR/staging/lib"

# Move to a sibling directory so that all relative paths remain valid.
mv "$TMPDIR/staging" "$TMPDIR/relocated"

output=$("$TMPDIR/relocated/bin/movable" 2>&1)
echo "$output" | grep -q "Hello from patched binary!" ||
  fail "patched binary did not work after move"
pass "--relocatable binary movement"

# --- Test 5: --relocatable patches binaries with target interpreter ---
# Needed for 'nix bundle': Nix-built binaries already point at the target
# interpreter but still have to be patched.

echo "=== Test: --relocatable with target interpreter ==="

${CC:-cc} -o "$TMPDIR/nix_built" "$SCRIPT_DIR/test_program.c" \
  -Wl,--dynamic-linker="$INTERP"

patch_output=$("$WRAP_BUDDY" --paths "$TMPDIR/nix_built" --interpreter "$INTERP" \
  --libs "$LIBS" --relocatable)

echo "$patch_output" | grep -q "Patching: $TMPDIR/nix_built" ||
  fail "binary with target interpreter was not patched in relocatable mode"

output=$("$TMPDIR/nix_built" 2>&1)
echo "$output" | grep -q "Hello from patched binary!" ||
  fail "patched binary did not produce expected output"
pass "--relocatable with target interpreter"

echo "=== All tests passed ==="
