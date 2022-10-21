{ lib, runCommand, lndir }:
  # https://github.com/NixOS/nixpkgs/blob/a624ff71ce538f7a9d9ad046f741db8daca4d1e6/pkgs/build-support/trivial-builders.nix#L431-L452
  # Modified to add 2> /dev/null to the command to silence collisions.
  /*
   * Create a forest of symlinks to the files in `paths'.
   *
   * This creates a single derivation that replicates the directory structure
   * of all the input paths.
   *
   * BEWARE: it may not "work right" when the passed paths contain symlinks to directories.
   *
   * Examples:
   * # adds symlinks of hello to current build.
   * symlinkJoin { name = "myhello"; paths = [ pkgs.hello ]; }
   *
   * # adds symlinks of hello and stack to current build and prints "links added"
   * symlinkJoin { name = "myexample"; paths = [ pkgs.hello pkgs.stack ]; postBuild = "echo links added"; }
   *
   * This creates a derivation with a directory structure like the following:
   *
   * /nix/store/sglsr5g079a5235hy29da3mq3hv8sjmm-myexample
   * |-- bin
   * |   |-- hello -> /nix/store/qy93dp4a3rqyn2mz63fbxjg228hffwyw-hello-2.10/bin/hello
   * |   `-- stack -> /nix/store/6lzdpxshx78281vy056lbk553ijsdr44-stack-2.1.3.1/bin/stack
   * `-- share
   *     |-- bash-completion
   *     |   `-- completions
   *     |       `-- stack -> /nix/store/6lzdpxshx78281vy056lbk553ijsdr44-stack-2.1.3.1/share/bash-completion/completions/stack
   *     |-- fish
   *     |   `-- vendor_completions.d
   *     |       `-- stack.fish -> /nix/store/6lzdpxshx78281vy056lbk553ijsdr44-stack-2.1.3.1/share/fish/vendor_completions.d/stack.fish
   * ...
   *
   * symlinkJoin and linkFarm are similar functions, but they output
   * derivations with different structure.
   *
   * symlinkJoin is used to create a derivation with a familiar directory
   * structure (top-level bin/, share/, etc), but with all actual files being symlinks to
   * the files in the input derivations.
   *
   * symlinkJoin is used many places in nixpkgs to create a single derivation
   * that appears to contain binaries, libraries, documentation, etc from
   * multiple input derivations.
   *
   * linkFarm is instead used to create a simple derivation with symlinks to
   * other derivations.  A derivation created with linkFarm is often used in CI
   * as a easy way to build multiple derivations at once.
   */
args_@{ name
 , paths
 , preferLocalBuild ? true
 , allowSubstitutes ? false
 , postBuild ? ""
 , ...
 }:
let
args = removeAttrs args_ [ "name" "postBuild" ]
  // {
    inherit preferLocalBuild allowSubstitutes;
    passAsFile = [ "paths" ];
  }; # pass the defaults
in runCommand name args
''
  mkdir -p $out
  for i in $(cat $pathsPath); do
    ${lndir}/bin/lndir -silent $i $out 2> /dev/null
  done
  ${postBuild}
''

