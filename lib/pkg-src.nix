{ stdenvNoCC, coreutils }:
src: outputHash: path:
  stdenvNoCC.mkDerivation {
    inherit src outputHash path coreutils;
    name = "source";
    builder = builtins.toFile "builder.sh" ''
      $coreutils/bin/cp -a $src/$path $out
    '';
    outputHashMode = "recursive";
  }
