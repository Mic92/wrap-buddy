/*
 * Shared library for testing --needed injection.
 * A constructor sets an env var so the test binary can verify it was loaded.
 */
#include <stdlib.h>

__attribute__((constructor)) static void needed_lib_init(void) {
  setenv("WRAPBUDDY_NEEDED_LOADED", "1", 1);
}
