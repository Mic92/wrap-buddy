{
  lib,
  stdenv,
  buildPackages,
  callPackage,
  makeSetupHook,
  writeText,
  binutils,
  xxd,
  strace,
  pkgsi686Linux,
  llvmPackages,
  sources,
}:

let
  # Get interpreter info from stdenv attributes (avoids IFD)
  dynamicLinker = stdenv.cc.bintools.dynamicLinker;

  libcLib = "${stdenv.cc.libc}/lib";

  # Cross-compilation support:
  # - CC (from stdenv) builds stubs for TARGET platform (what gets patched)
  # - CXX_FOR_BUILD builds wrap-buddy for BUILD platform (what runs the patcher)
  # For native builds, these are the same compiler.
  cxxForBuild = "${buildPackages.stdenv.cc}/bin/c++";

  # Single derivation builds everything:
  # - loader.bin, stub.bin (and 32-bit variants on x86_64)
  # - wrap-buddy C++ patcher with embedded stubs
  wrapBuddy = stdenv.mkDerivation {
    pname = "wrap-buddy";
    version = "1.0.1";

    src = sources;

    # depsBuildBuild: tools that run on BUILD and compile for BUILD
    depsBuildBuild = [
      buildPackages.stdenv.cc # C++ compiler for wrap-buddy
    ];

    nativeBuildInputs = [
      binutils # objcopy (processes target ELF files)
      xxd # for embedding stubs (platform-independent)
    ];

    makeFlags = [
      "CXX_FOR_BUILD=${cxxForBuild}"
      "BINDIR=$(out)/bin"
      "LIBDIR=$(out)/lib/wrap-buddy"
      "INTERP=${dynamicLinker}"
      "LIBC_LIB=${libcLib}"
    ]
    ++ lib.optional stdenv.hostPlatform.isx86_64 "BUILD_32BIT=1";

    nativeInstallCheckInputs = [ strace ];
    doInstallCheck = true;
    installCheckTarget = "check";
    enableParallelBuilding = true;

    meta = {
      description = "Patch ELF binaries with stub loader for NixOS compatibility";
      mainProgram = "wrap-buddy";
      license = lib.licenses.mit;
      platforms = [
        "x86_64-linux"
        "i686-linux"
        "aarch64-linux"
      ];
    };
  };

  hookScript = writeText "wrap-buddy-hook.sh" (builtins.readFile ./wrap-buddy-hook.sh);

  hook = makeSetupHook {
    name = "wrap-buddy-hook";
    propagatedBuildInputs = [ wrapBuddy ];
    meta = {
      description = "Setup hook that patches ELF binaries with stub loader";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
    passthru = {
      inherit wrapBuddy;
      tests = {
        clang-tidy = callPackage ./clang-tidy.nix { sourceFiles = sources; };
        # Build patcher with ASan/UBSan to catch memory errors and undefined behavior
        test-sanitizers = wrapBuddy.overrideAttrs (old: {
          EXTRA_CXXFLAGS = "-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all";
        });
        # Build with libc++ to catch libstdc++-specific assumptions
        test-libcxx = (
          llvmPackages.libcxxStdenv.mkDerivation {
            inherit (wrapBuddy)
              pname
              version
              src
              nativeBuildInputs
              meta
              ;
            depsBuildBuild = [ llvmPackages.libcxxStdenv.cc ];
            makeFlags = [
              "CXX_FOR_BUILD=${llvmPackages.libcxxStdenv.cc}/bin/c++"
              "BINDIR=$(out)/bin"
              "LIBDIR=$(out)/lib/wrap-buddy"
              "INTERP=${dynamicLinker}"
              "LIBC_LIB=${libcLib}"
            ];
            nativeInstallCheckInputs = [ strace ];
            doInstallCheck = true;
            installCheckTarget = "check";
          }
        );
      }
      // lib.optionalAttrs stdenv.hostPlatform.isx86_64 {
        # Test 32-bit patching by building wrapBuddy with i686 stdenv
        test-32bit = pkgsi686Linux.callPackage ./package.nix { inherit sources; };
      };
    };
  } hookScript;
in
hook
