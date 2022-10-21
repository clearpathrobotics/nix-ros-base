{ applyPatches, fetchpatch, fetchFromGitHub }:

# We use gtest from source, but the source needs to be pre-patched, so it works
# better to do this than use the gtest.src derivation.
applyPatches {
  name = "gtest-src";

  src = fetchFromGitHub {
    owner = "google";
    repo = "googletest";
    rev = "release-1.10.0";
    sha256 = "1zbmab9295scgg4z2vclgfgjchfjailjnvzc6f5x9jvlsdi3dpwz";
  };

  patches = [
    (fetchpatch {
      name = "fix-cmake-config-includedir.patch";
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/66e44425c6dfecbea68a5d6dc221ccd56561d4f1/pkgs/development/libraries/gtest/fix-cmake-config-includedir.patch";
      sha256 = "sha256-sOgrStEjAckqyDRRgbLRfAtzSMREbNs32gIX5AcPQHU=";
    })
    (fetchpatch {
      name = "fix-pkgconfig-paths.patch";
      url = "https://github.com/google/googletest/commit/5126ff48d9ac54828d1947d1423a5ef2a8efee3b.patch";
      sha256 = "sha256-TBvECU/9nuvwjsCjWJP2b6DNy+FYnHIFZeuVW7g++JE=";
    })
    (fetchpatch {
      name = "fix-cmake-minimum.patch";
      url = "https://github.com/google/googletest/commit/32f4f52d95dc99c35f51deed552a6ba700567f94.patch";
      sha256 = "sha256-txTbzBlxCZQq0DxZBY4b1hbxJkSLbS/xSYShQND20XY=";
    })
  ];
}
