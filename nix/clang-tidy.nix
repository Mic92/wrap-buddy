{
  lib,
  llvmPackages_latest,
  binutils,
  xxd,
  jq,
  sourceFiles,
}:

llvmPackages_latest.libcxxStdenv.mkDerivation {
  name = "wrap-buddy-clang-tidy";
  src = sourceFiles;

  nativeBuildInputs = [
    llvmPackages_latest.clang-tools
    binutils
    jq
    xxd
  ];

  buildPhase = ''
    make clang-tidy \
      INTERP=/nix/store/dummy/ld.so \
      LIBC_LIB=/nix/store/dummy/lib
  '';

  installPhase = "touch $out";

  meta.platforms = lib.platforms.linux;
}
