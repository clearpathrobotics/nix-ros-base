{
  # This is a list of mixins that are enabled when a `colcon build` is ran without any mixin options. 
  defaultBuildMixins ? [],

  # Same as defaultBuildMixins but for `colcon test`.
  defaultTestMixins ? [],

  lib,
  name ? "colcon-home",

  # This is the list of mixins that is provided, in addition to the ones provided through defaultBuildMixins. These mixins
  # are available but not used by default when `colcon build` is ran without mixin options.
  providedBuildMixins ? [],

  # Same as providedBuildMixins but for `colcon test`.
  providedTestMixins ? [],

  stdenv,

  writeText,
  writeTextFile,
}: let

  have_test_mixins = lib.length providedTestMixins > 0;

  # Mixin body is the combination of both the default enabled mixins and the provided mixins.
  mixin_body = {
    build = builtins.listToAttrs (lib.unique (defaultBuildMixins ++ providedBuildMixins));
  } // (if have_test_mixins then
      {
        test = builtins.listToAttrs (lib.unique (defaultTestMixins ++ providedTestMixins));
      }
    else
      {});

  # Then, just the defaults are enabled by default through colcon's defaults.
  enabled_build_mixins = lib.attrNames (lib.listToAttrs (lib.unique defaultBuildMixins));
  enabled_test_mixins = lib.attrNames (lib.listToAttrs (lib.unique defaultTestMixins));
in stdenv.mkDerivation rec {
  pname = "colcon-home";
  version = "0.0.1";
  phases = [ "buildPhase" ];

  buildPhase = let
    # Write the text file that provides all mixins
    provided = writeTextFile {
      name = "compile-commands-mixin";
      text = builtins.toJSON mixin_body ;
    };

    # Write the text file that specifies which mixins are enabled for each command.
    defaults = writeTextFile {
      name = "colcon-home-defaults";
      text = builtins.toJSON ({
        build = {
          mixin = enabled_build_mixins;
        };
      } // (if have_test_mixins then {test = {mixin = enabled_test_mixins; };} else {}));
    };
  in ''
    mkdir -p $out/mixin
    ln -s ${defaults} $out/defaults.yaml
    ln -s ${provided} $out/mixin/all.mixin
  '';
}
