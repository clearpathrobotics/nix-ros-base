final: prev:
{
  clang-tools-7 = prev.callPackage ./clang-tools-versioned.nix {
    llvmPackages = final.llvmPackages_7;
  };

  clang-tools-10 = prev.callPackage ./clang-tools-versioned.nix {
    llvmPackages = final.llvmPackages_10;
  };

  gtest-src = prev.callPackage ./gtest-src.nix {};

  nixGLDefault = final.nixgl.auto.nixGLDefault;
}
