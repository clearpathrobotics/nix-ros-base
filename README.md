nix-base
========

This repository supplies the base Nix content which underpins the generated
package definitions available in `sweng-infra/nix`. Included here are
overrides and patches for various upstream packages, new dependencies which
aren't packaged upstream, plus the bits of plumbing needed to make package
and workspace building function.

The included `flake.nix` does not actually provide any buildable packages
as outputs— currently its outputs are exclusively intended to be consumed
by the generated snapshot flakes. However, the `flake.lock` in this repo
is critically important, as it controls which versions of our upstream
dependencies (nixpkgs, nix-ros-overlay) we are pinned to.
