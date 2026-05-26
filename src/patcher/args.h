/*
 * args.h - Command-line argument parsing
 */

#pragma once

#include <expected>
#include <filesystem>
#include <format>
#include <optional>
#include <print>
#include <span>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace wrap_buddy {

namespace fs = std::filesystem;

struct Args {
  std::vector<fs::path> paths;
  std::vector<fs::path> libs;
  std::vector<fs::path> runtime_deps;
  std::vector<std::string> ignore_missing;
  std::vector<std::string> needed; // extra DT_NEEDED sonames to inject
  std::optional<std::string> interpreter;
  fs::path loader_dir_path =
      LIBDIR; // use default installation prefix by default
  bool recursive = true;
  bool dry_run = false;
  bool relocatable = false;
};

inline auto usage(std::string_view progname) -> void {
  std::println(stderr, "Usage: {} [options]", progname);
  std::println(stderr, "Options:");
  std::println(stderr,
               "  --paths PATH...          Paths to scan for executables");
  std::println(stderr,
               "  --libs PATH...           Library directories to search");
  std::println(stderr, "  --runtime-dependencies PATH...");
  std::println(stderr, "                           Runtime dependency paths");
  std::println(stderr, "  --ignore-missing PATTERN...");
  std::println(
      stderr,
      "                           Patterns for deps to ignore if missing");
  std::println(stderr,
               "  --needed SONAME...       Extra DT_NEEDED sonames to inject");
  std::println(stderr,
               "  --no-recurse             Don't recurse into subdirectories");
  std::println(stderr, "  --dry-run                Show what would be done");
  std::println(stderr, "  --interpreter PATH       Path to dynamic linker");
  std::println(stderr, "  --relocatable            Produce relocatable "
                       "binaries, resolve second-stage loader and interpreter "
                       "relative to the executable directory\n"
                       "                           Construct RUNPATH with "
                       "$ORIGIN and relative paths for dependencies");
  std::println(stderr,
               "  --loader-dir-path PATH   Path to directory containing "
               "loader.bin, uses the compiled-in LIBDIR by default");
  std::println(stderr, "  --help                   Show this help");
}

struct HelpRequested {};
using ParseError = std::variant<std::string, HelpRequested>;

inline auto parse_args(std::span<char *> argv_span)
    -> std::expected<Args, ParseError> {
  Args args;
  size_t idx = 1; // Skip program name

  // Collect non-option arguments until next option or end
  auto collect_args = [&](auto &vec) -> void {
    while (idx < argv_span.size()) {
      const std::string_view arg(argv_span[idx]);
      if (arg.starts_with('-')) {
        break;
      }
      vec.emplace_back(arg);
      ++idx;
    }
  };

  while (idx < argv_span.size()) {
    const std::string_view arg(argv_span[idx]);
    ++idx;

    if (arg == "--paths") {
      collect_args(args.paths);
    } else if (arg == "--libs") {
      collect_args(args.libs);
    } else if (arg == "--runtime-dependencies") {
      collect_args(args.runtime_deps);
    } else if (arg == "--ignore-missing") {
      collect_args(args.ignore_missing);
    } else if (arg == "--needed") {
      collect_args(args.needed);
    } else if (arg == "--no-recurse") {
      args.recursive = false;
    } else if (arg == "--dry-run") {
      args.dry_run = true;
    } else if (arg == "--relocatable") {
      args.relocatable = true;
    } else if (arg == "--loader-dir-path") {
      if (idx >= argv_span.size()) {
        return std::unexpected(
            ParseError{"--loader-dir-path requires an argument"});
      }
      args.loader_dir_path = argv_span[idx];
      ++idx;
    } else if (arg == "--interpreter") {
      if (idx >= argv_span.size()) {
        return std::unexpected(
            ParseError{"--interpreter requires an argument"});
      }
      args.interpreter = argv_span[idx];
      ++idx;
    } else if (arg == "--help" || arg == "-h") {
      return std::unexpected(ParseError{HelpRequested{}});
    } else if (arg.starts_with('-')) {
      return std::unexpected(
          ParseError{std::format("unknown option: {}", arg)});
    } else {
      return std::unexpected(
          ParseError{std::format("unexpected argument: {}", arg)});
    }
  }

  if (args.paths.empty()) {
    return std::unexpected(ParseError{"--paths is required"});
  }

  return args;
}

} // namespace wrap_buddy
