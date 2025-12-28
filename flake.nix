{
  description = "Patch ELF binaries with stub loader for NixOS compatibility";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          sources = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./include/wrap-buddy
              ./Makefile
              ./src
              ./.clang-tidy
              ./tests
            ];
          };
        in
        {
          packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            default = config.packages.wrapBuddy;
            wrapBuddy = pkgs.callPackage ./nix/package.nix { inherit sources; };
          };

          checks =
            let
              packages = lib.mapAttrs' (n: lib.nameValuePair "package-${n}") config.packages;
              devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") config.devShells;
              linuxChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
                {
                  clang-tidy = pkgs.callPackage ./nix/clang-tidy.nix {
                    sourceFiles = sources;
                  };
                  test-sanitizers = config.packages.wrapBuddy.passthru.tests.test-sanitizers;
                }
                // lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
                  test-32bit = pkgs.pkgsi686Linux.callPackage ./nix/package.nix { inherit sources; };
                }
              );
            in
            packages // devShells // linuxChecks;

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              clang-format.enable = true;
              nixfmt.enable = true;
              mdformat.enable = true;
              shfmt.enable = true;
            };
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = lib.optional pkgs.stdenv.hostPlatform.isLinux config.packages.wrapBuddy;
            packages = [
              pkgs.clang-tools
              pkgs.jq
              pkgs.xxd
              config.treefmt.build.wrapper
            ];
          };
        };
    };
}
