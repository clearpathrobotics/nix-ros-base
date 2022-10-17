{ clang-tools, lib, llvmPackages, makeWrapper, runCommand }:

let
  clang-tools-versioned = clang-tools.override {
    inherit llvmPackages;
  };

  shortVersion = with lib; toString (take 1 (splitString "." llvmPackages.llvm.version));

in runCommand "clang-tools-${shortVersion}" {
  buildInputs = [ makeWrapper ];
} ''
  mkdir -p $out/bin

  cd ${clang-tools-versioned}/bin
  for f in $(ls clang-*); do
    makeWrapper ${clang-tools-versioned}/bin/''${f} $out/bin/''${f}-${shortVersion}
  done
''
