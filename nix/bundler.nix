# Bundler for 'nix bundle': turns a Nix package into a relocatable tree
# (bin/ + lib/) that runs on any Linux without /nix/store.
{
  runCommand,
  closureInfo,
  wrapBuddy,
}:
drv:
runCommand "${drv.pname or drv.name}-bundle"
  {
    nativeBuildInputs = [ wrapBuddy ];
    closure = closureInfo { rootPaths = [ drv ]; };
  }
  ''
    mkdir -p $out/bin $out/lib

    # Copy executables
    for f in ${drv}/bin/*; do
      [ -f "$f" ] || continue
      cp -L "$f" $out/bin/
    done

    # Copy shared libraries and the dynamic linker from the runtime closure
    while read -r path; do
      for so in "$path"/lib/*.so*; do
        [ -e "$so" ] || continue
        cp -Ln "$so" $out/lib/
      done
    done < $closure/store-paths

    chmod -R u+w $out

    interp=$(find $out/lib -maxdepth 1 -name 'ld-*.so.*' | head -n1)
    if [ -z "$interp" ]; then
      echo "no dynamic linker found in closure of ${drv}" >&2
      exit 1
    fi

    cp ${wrapBuddy}/lib/wrap-buddy/loader.bin $out/lib/

    wrap-buddy \
      --paths $out/bin \
      --libs $out/lib \
      --interpreter "$interp" \
      --relocatable \
      --loader-dir-path $out/lib
  ''
