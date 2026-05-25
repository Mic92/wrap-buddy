/*
 * Test program for --needed injection.
 * Does NOT link libneeded_test.so — wrap-buddy injects it at runtime.
 * Prints whether the library's constructor ran.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
  const char *val = getenv("WRAPBUDDY_NEEDED_LOADED");
  printf("NEEDED_LOADED=%s\n", (val && val[0] == '1') ? "yes" : "no");
  return (val && val[0] == '1') ? 0 : 1;
}

/* Reserve space at entry point for the stub */
#if defined(__x86_64__) || defined(__i386__)
__asm__(".section .text\n.space 4096, 0x90\n");
#elif defined(__aarch64__)
__asm__(".section .text\n.space 4096, 0x1f\n");
#endif
