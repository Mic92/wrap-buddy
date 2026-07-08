# wrapBuddy Makefile - see README.md for documentation

CC ?= cc
CXX_FOR_BUILD ?= c++
OBJCOPY ?= objcopy
XXD ?= xxd
CLANG_TIDY ?= clang-tidy
CLANG_FORMAT ?= clang-format
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/wrap-buddy

# Path placeholder embedded in the stub loader. Rewritten with path relative to loader.bin
# depending on the location of the patched executable. The default is rather small, since it blows up the stub size.
# The string is produced with 'echo "placeholder" | b3sum -l 64'
RELOCATABLE_LOADER_PATH_PLACEHOLDER ?= 880031aabab70d51f1ff08762ad3c457bdaa2bf2687f4e864a33f63889a5ed1b571bebc01e6d248e9e4ac63c86b696712f07a701983375bd95910df9afa9a636

# C++23 flags for wrap-buddy (runs on build machine)
CXXFLAGS_FOR_BUILD ?= -std=c++23 -Wall -Wextra -O2 -Iinclude -DRELOCATABLE_LOADER_PATH_PLACEHOLDER='"$(RELOCATABLE_LOADER_PATH_PLACEHOLDER)"' -DLIBDIR='"$(LIBDIR)"'
EXTRA_CXXFLAGS ?=

# Auto-detect target architecture from compiler
TARGET := $(shell $(CC) -dumpmachine 2>/dev/null)

# Determine native arch flags
ifneq (,$(findstring aarch64,$(TARGET)))
  # aarch64: use tiny code model for truly PC-relative addressing (adr not adrp)
  ARCH_FLAGS = -mcmodel=tiny
  BUILD_32BIT =
else ifneq (,$(findstring x86_64,$(TARGET)))
  ARCH_FLAGS =
  BUILD_32BIT = 1
else
  ARCH_FLAGS =
  BUILD_32BIT =
endif

# Freestanding flags - no libc, no system headers
CFLAGS_BASE = -Wall -nostdlib -nostdinc -fPIC -fno-stack-protector \
              -fno-exceptions -fno-unwind-tables \
              -fno-asynchronous-unwind-tables -fno-builtin -Oz -Iinclude

# Linker flags for flat binary output
LDFLAGS = -Wl,-T,src/preamble.ld -Wl,-e,_start -Wl,-Ttext=0

# Native flags
CFLAGS_NATIVE = $(CFLAGS_BASE) $(ARCH_FLAGS) $(LDFLAGS)

# 32-bit flags (only used on x86_64)
CFLAGS_32 = $(CFLAGS_BASE) -m32 $(LDFLAGS)

# Header dependencies
HEADERS = include/wrap-buddy/*.h include/wrap-buddy/arch/*.h src/preamble.ld
PATCHER_HEADERS = src/patcher/*.h

# Targets
NATIVE_BINS = loader.bin stub.bin stub_reloc.bin
ifdef BUILD_32BIT
  ALL_BINS = $(NATIVE_BINS) loader32.bin stub32.bin
  STUB_HEADERS = src/patcher/stub_64.h src/patcher/stub_32.h src/patcher/stub_64_reloc.h src/patcher/stub_32_reloc.h
  STUB_32_DEF = -DHAVE_STUB_32
else
  ALL_BINS = $(NATIVE_BINS)
  STUB_HEADERS = src/patcher/stub_64.h src/patcher/stub_64_reloc.h
  STUB_32_DEF =
endif

.PHONY: all clean install bins patcher clang-tidy format check

all: bins patcher

bins: $(ALL_BINS)

patcher: wrap-buddy

# Native loader
loader.elf: src/loader/loader.c $(HEADERS)
	$(CC) $(CFLAGS_NATIVE) -o $@ src/loader/loader.c

loader.bin: loader.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

# Native stub
STUB_FLAGS = -Iinclude
stub.elf: src/stub/stub.c $(HEADERS)
	$(CC) -DRELOCATABLE_MODE=0 $(CFLAGS_NATIVE) $(STUB_FLAGS) -DLOADER_PATH='"$(LIBDIR)/loader.bin"' -o $@ src/stub/stub.c

stub_reloc.elf: src/stub/stub.c $(HEADERS)
	$(CC) -DRELOCATABLE_MODE=1 $(CFLAGS_NATIVE) $(STUB_FLAGS) -DLOADER_PATH='"$(RELOCATABLE_LOADER_PATH_PLACEHOLDER)"' -o $@ src/stub/stub.c

stub.bin: stub.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

stub_reloc.bin: stub_reloc.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

# 32-bit loader (x86_64 only)
loader32.elf: src/loader/loader.c $(HEADERS)
	$(CC) $(CFLAGS_32) -o $@ src/loader/loader.c

loader32.bin: loader32.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

# 32-bit stub (x86_64 only)
stub32.elf: src/stub/stub.c $(HEADERS)
	$(CC) -DRELOCATABLE_MODE=0 $(CFLAGS_32) -DLOADER_PATH='"$(LIBDIR)/loader32.bin"' -o $@ src/stub/stub.c

stub32_reloc.elf: src/stub/stub.c $(HEADERS)
	$(CC) -DRELOCATABLE_MODE=1 $(CFLAGS_32) -DLOADER_PATH='"$(RELOCATABLE_LOADER_PATH_PLACEHOLDER)"' -o $@ src/stub/stub.c

stub32.bin: stub32.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

stub32_reloc.bin: stub32_reloc.elf
	$(OBJCOPY) -O binary --only-section=.all $< $@

# Generate C headers from stub binaries for embedding
src/patcher/stub_64.h: stub.bin
	$(XXD) -i $< > $@

src/patcher/stub_32.h: stub32.bin
	$(XXD) -i $< > $@

src/patcher/stub_64_reloc.h: stub_reloc.bin
	$(XXD) -i $< > $@

src/patcher/stub_32_reloc.h: stub32_reloc.bin
	$(XXD) -i $< > $@

# Built-in interpreter defaults (optional)
ifdef INTERP
  INTERP_DEF = -DDEFAULT_INTERP='"$(INTERP)"'
else
  INTERP_DEF =
endif
ifdef LIBC_LIB
  LIBC_DEF = -DDEFAULT_LIBC_LIB='"$(LIBC_LIB)"'
else
  LIBC_DEF =
endif

# Combined flags for wrap-buddy
WRAP_BUDDY_FLAGS = $(CXXFLAGS_FOR_BUILD) $(EXTRA_CXXFLAGS) $(STUB_32_DEF) $(INTERP_DEF) $(LIBC_DEF) -Isrc/patcher

# C++ patcher with embedded stubs
wrap-buddy: src/patcher/main.cc $(STUB_HEADERS) $(HEADERS) $(PATCHER_HEADERS)
	$(CXX_FOR_BUILD) $(WRAP_BUDDY_FLAGS) -o $@ src/patcher/main.cc

# Generate compilation database for clang-tidy/LSP
JQ_ENTRY = jq -n --arg d "$(CURDIR)" --arg f
JQ_ARGS = '{directory: $$d, file: $$f, arguments: $$ARGS.positional + [$$f]}' --args --

compile_commands.json:
	{ $(JQ_ENTRY) src/patcher/main.cc $(JQ_ARGS) $(CXX_FOR_BUILD) $(CXXFLAGS_FOR_BUILD) $(EXTRA_CXXFLAGS) \
	    $(STUB_32_DEF) $(if $(INTERP),'-DDEFAULT_INTERP="$(INTERP)"') \
	    $(if $(LIBC_LIB),'-DDEFAULT_LIBC_LIB="$(LIBC_LIB)"') -Isrc/patcher; \
	  $(JQ_ENTRY) src/loader/loader.c $(JQ_ARGS) $(CC) $(CFLAGS_BASE) $(ARCH_FLAGS) -Iinclude; \
	  $(JQ_ENTRY) src/stub/stub.c $(JQ_ARGS) $(CC) $(CFLAGS_BASE) $(ARCH_FLAGS) \
	    '-DLOADER_PATH="$(LIBDIR)/loader.bin"' -Iinclude; \
	} | jq -s . > $@

# Static analysis (configuration in .clang-tidy)
clang-tidy: compile_commands.json $(STUB_HEADERS)
	$(CLANG_TIDY) -p . src/loader/loader.c src/stub/stub.c src/patcher/main.cc

# Format source files
format:
	find src -name '*.c' -o -name '*.cc' -o -name '*.h' | xargs $(CLANG_FORMAT) -i

clean:
	rm -f *.elf *.bin src/patcher/stub_64.h src/patcher/stub_32.h src/patcher/stub_64_reloc.h src/patcher/stub_32_reloc.h wrap-buddy compile_commands.json

check: wrap-buddy $(ALL_BINS)
	bash tests/test.sh --interp $(INTERP) --libs $(LIBC_LIB)

install: $(ALL_BINS) wrap-buddy
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 wrap-buddy $(DESTDIR)$(BINDIR)/
	install -d $(DESTDIR)$(LIBDIR)
	install -m 644 $(ALL_BINS) $(DESTDIR)$(LIBDIR)/
