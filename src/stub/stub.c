/*
 * stub.c - Minimal entry stub for wrapBuddy
 *
 * This tiny stub is written to the binary's entry point.
 * It loads the external loader and jumps to it.
 */

#include <wrap-buddy/freestanding.h>

#include <wrap-buddy/arch.h>
#include <wrap-buddy/debug.h>
#include <wrap-buddy/mmap.h>

#ifndef LOADER_PATH
#error "LOADER_PATH must be defined"
#endif

#if RELOCATABLE_MODE
/* For figuring out the location of the LOADER_PATH. */
enum { MAX_PATH = 512 };
#endif

/* Mark as used to prevent optimization when referenced only via inline asm */
static const char loader_path[] __attribute__((used)) = LOADER_PATH;

// NOLINTNEXTLINE(misc-use-internal-linkage): referenced from inline asm in
// _start
__attribute__((noreturn)) void stub_main(const intptr_t *const stack_ptr) {
  /* Get loader path using PC-relative addressing */
  const char *path;
  PC_RELATIVE_ADDR(path, loader_path);

#if RELOCATABLE_MODE
  /* Load the second stage loader relative to the executed binary. */
  char loader_dir_path[MAX_PATH];
  intptr_t path_len =
      sys_readlink("/proc/self/exe", loader_dir_path, MAX_PATH - 1);
  if (path_len <= 0 || path_len >= MAX_PATH - 1) {
    die("open loader");
  }

  /* Find and zero-out the last slash to get the directory path. /proc/self/exe
     path is canonical, so this should always work. */
  intptr_t slash_pos = path_len - 1;
  while (slash_pos >= 0 && loader_dir_path[slash_pos] != '/') {
    slash_pos--;
  }

  /* In case the /proc/self/exe is busted somehow bail out. */
  if (slash_pos < 0) {
    die("bad exe path");
  }

  loader_dir_path[slash_pos] = '\0';

  /* Open the parent directory and openat the loader flat binary. */
  intptr_t loader_dir_desc =
      sys_open(loader_dir_path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
  if (loader_dir_desc < 0) {
    die("open loader");
  }

  intptr_t file_desc = sys_openat(loader_dir_desc, path, O_RDONLY, /*mode=*/0);
  sys_close(loader_dir_desc);
#else
  /* Open loader binary. */
  intptr_t file_desc = sys_open(path, O_RDONLY);
#endif

  if (file_desc < 0) {
    die("open loader");
  }

  /* Get actual loader size */
  struct stat file_stat;
  if (sys_fstat(file_desc, &file_stat) < 0) {
    die("fstat loader");
  }

  /* mmap loader as flat binary (entry at offset 0)
   * Note: This mapping is intentionally never unmapped and remains
   * until process exit. Could be reclaimed via trampoline but not worth
   * the complexity. */
  // NOLINTNEXTLINE(clang-analyzer-core.CallAndMessage)
  void *loader = (void *)sys_mmap(0,                     /* addr = NULL */
                                  file_stat.st_size,     /* len */
                                  PROT_READ | PROT_EXEC, /* prot */
                                  MAP_PRIVATE,           /* flags */
                                  file_desc,             /* fd */
                                  0                      /* offset */
  );
  if (IS_SYSCALL_ERR((intptr_t)loader)) {
    die("mmap loader");
  }

  sys_close(file_desc);

  /* Jump to loader with original stack pointer restored */
  JUMP_WITH_SP(stack_ptr, loader);
  __builtin_unreachable();
}

DEFINE_START(stub_main)
