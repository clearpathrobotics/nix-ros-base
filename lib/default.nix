final: prev:
let
  # Shamelessly cribbed from:
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/python-packages.nix
  makeOverridableColconPackage = f: origArgs:
    with prev.lib; let
      ff = f origArgs;
      overrideWith = newArgs: origArgs // (if isFunction newArgs then newArgs origArgs else newArgs);
    in
      if builtins.isAttrs ff then (ff // {
        overrideColconAttrs = newArgs: makeOverridableColconPackage f (overrideWith newArgs);
      })
      else if builtins.isFunction ff then {
        overrideColconAttrs = newArgs: makeOverridableColconPackage f (overrideWith newArgs);
        __functor = self: ff;
      }
      else ff;

  makeOverridableWorkspace = f: origArgs:
    with prev.lib; let
      ff = f origArgs;
      overrideWith = newArgs: origArgs // (if isFunction newArgs then newArgs origArgs else newArgs);
    in
      if builtins.isAttrs ff then (ff // {
        overrideWorkspaceAttrs = newArgs: makeOverridableWorkspace f (overrideWith newArgs);
      })
      else if builtins.isFunction ff then {
        overrideWorkspaceAttrs = newArgs: makeOverridableWorkspace f (overrideWith newArgs);
        __functor = self: ff;
      }
      else ff;

in {
  fetchFromClearpathGitLab = prev.callPackage ./fetch-gitlab.nix {};

  fetchdeb = prev.callPackage ./fetchdeb.nix {};

  quietSymlinkJoin = prev.callPackage ./quiet-symlink-join.nix { };
  catkinTestData = prev.callPackage ./catkin-test-data.nix { };

  developShellInfo = prev.callPackage ./develop-shell-info.nix { };
  developShellPreventMixing = prev.callPackage ./develop-shell-prevent-mix.nix { };

  pkgSrc = prev.callPackage ./pkg-src.nix {};

  makeColconHook = prev.callPackage ./make-colcon-hook.nix {};

  buildColconPackageDocs = prev.callPackage ./build-colcon-package-docs.nix {};

  buildColconPackageTesting = prev.callPackage ./build-colcon-package-testing.nix {};

  buildColconPackage = makeOverridableColconPackage (prev.lib.makeOverridable (
    prev.callPackage ./build-colcon-package.nix {}
  ));

  buildColconWorkspace = makeOverridableWorkspace (prev.lib.makeOverridable (
    prev.callPackage ./build-colcon-workspace.nix {}
  ));

  propagateColconRunDepends = prev.callPackage ./propagate-colcon-run-depends.nix {};

  flake-overlay = prev.callPackage  ./flake-overlay {};
}
