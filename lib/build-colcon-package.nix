# This outer function is called via callPackage and assigned the name buildColconPackage, so it
# contains arguments which may be overridden as necessary.
{
  buildColconPackageDocs,
  buildColconPackageTesting,
  buildColconWorkspace,
  cmake,
  catkinTestData,
  colconHome,
  colconMinimal,
  developShellInfo,
  lib,
  makeColconHook,
  propagateColconRunDepends,
  python3,
  quietSymlinkJoin,
  setupDebugInfoDirs,
  stdenv,
  stdenvNoCC,
  writeTextFile,
  zstd
}:
# This inner function is what is called in the generated ROS packages definitions, but may also
# be overridden via overrideColconAttrs.
{
  name,
  pkgFinal,
  passthru ? {},

  # These map exactly to what's in the package definitions; no preprocessing magic other than
  # mapping rosdep keys to the proper nixpkgs names.
  colconBuildDepends ? [],
  colconRunDepends ? [],
  colconTestDepends ? [],

  # This takes a list of additional cmake-args to be passed to colcon via the colcon.pkg file.
  colconCMakeArgs ? [],

  # Flag to disable running the unit tests for this package.
  testDisableRun ? false,

  # Flag to disable compilation of the unit tests, this automatically disables test running.
  testDisableCompile ? false,

  # When adding new flags here, also add them to the 'removeAttrs attrs' line at the bottom of this file.
  # Otherwise passing them as a overrideColconAttrs argument will cause downstream packages to be rebuilt.
  ...
}@attrs:

# This logic is doing some pre-processing of dependencies. Typical Nix approach would lead to all
# colcon run dependencies becoming propagatedBuildDepends, but this gets out of control with high
# level packages pulling in hundreds of recursive run dependencies and overloading envvar limits.
# So instead, we:
#  - determine the recursive run dependences of all build dependencies, which is the full set of
#    everything that will need to be visible at build time for this package.
#  - divide that list by colcon and non-colcon packages, with the non-colcon ones becoming normal
#    Nix buildInputs, and the colcon ones being handled via colcon's fast workspace generation.
#  - stash the run depends in a passthru attr, to be pulled out only when a workspace is being
#    assembled.
with lib; let
  # The build depends of a colcon package are all of its build dependencies and all of *their*
  # recursive run dependencies, which is why this is calling propagateColconRunDepends. Test
  # dependencies must be available at configure time, and so are also basically build deps.
  recursiveBuildDepends = propagateColconRunDepends (colconBuildDepends ++ colconTestDepends);
  # Similarly, for the tests we want the run dependencies to also be present.
  recursiveTestDepends = propagateColconRunDepends (colconBuildDepends ++ colconTestDepends ++ colconRunDepends);

  # Divide the list by colcon and non-colcon packages.
  partitionedBuildDepends = partition (d: d.colconPackage or false) recursiveBuildDepends;
  colconRecursiveBuildDepends = partitionedBuildDepends.right;

  # Here, we add our own separate-debug-info replacement as a dependency, this overwrites the original shell function
  # with one that ensures the debug directory exists.
  nonColconRecursiveBuildDepends = partitionedBuildDepends.wrong ++ [ ./build-support/separate-debug-info.sh ];

  # And the same for the unit tests, divide them by colcon and non colcon recursive test depends.
  partitionedTestDepends = partition (d: d.colconPackage or false) recursiveTestDepends;
  colconRecursiveTestDepends = partitionedTestDepends.right;
  nonColconRecursiveTestDepends = partitionedTestDepends.wrong;

  # Recursive debug targets are made up of the build depends AND the run depends, this ensures we
  # can apply this to metapackages to pull in the run dependencies only.
  recursiveDebugTargets = map (d: d.debug) (filter (d: ((d.debug or null) != null)) (recursiveBuildDepends
                                                                                        ++ colconRunDepends));
  # Debug environment helper to expose shell variables about this build and modify the prompt.
  debugEnvHelper = developShellInfo {
    name = "${name}-debugEnv";
  };

  docs = buildColconPackageDocs pkgFinal;
  testing = buildColconPackageTesting pkgFinal;

  # Assert if pkgFinal.passthru.colconPackage is not set. This means that someone removed the passthru attributes with
  # in incorrect passthru override. We want this to be part of the actual build, but also a no-op.
  assertColconPackage = (if (hasAttr "colconPackage" pkgFinal.passthru)
    then
      []
    else
      (builtins.throw "passthru is missing colconPackage, use // passthru when overriding passthru values.")
  );

in stdenv.mkDerivation ({
  # Dev output needs more work, see SES-2437.
  # outputs = [ "out" "dev" ];
  outputs = [ "out" "build" ];
  ## https://gitlab.clearpathrobotics.com/sweng-infra/nix-base/-/merge_requests/24/

  # These are host/tool dependencies, so "native" is appropriate for them, but it's also
  # convenient as a way to differentiate between dependencies which we do and do not want
  # as part of a develop shell.
  nativeBuildInputs = [ colconHome colconMinimal zstd ];

  buildInputs = nonColconRecursiveBuildDepends ++ assertColconPackage;

  phases = [ "unpackPhase" "patchPhase" "buildPhase" "fixupPhase" ];

  # Rather than registering an individual hook for each package's local_setup.sh, we instead
  # use colcon's mechanism for this to generate a single script for the whole workspace.
  postHook = (makeColconHook colconRecursiveBuildDepends) + ''
    export COLCON_HOME=${colconHome}
  '';

  # Patch up all shebangs in the source directory for scripts and the like that exist there and may be ran during build
  prePatch = ''
    patchShebangs .
  '';

  colconPreVerbArgs = [];

  colconBuildArgs = [
    "--paths $sourceRoot"
    "--install-base $out"
    "--merge-install"
  ];

  buildPhase = let
    # Write the colcon.pkg file, which can provide cmake-args in addition to the ones coming from COLCON_HOME.
    colconPkgFile = writeTextFile {
      name = "colcon.pkg";
      text = builtins.toJSON {
        "cmake-args" = colconCMakeArgs;
      };
    };
  in ''
    runHook preBuild

    # Write the colcon pkg file.
    cp ${colconPkgFile} colcon.pkg

    # Run a colcon invocation to build this specific package.
    cd $NIX_BUILD_TOP
    colconArgs=$(eval echo "$colconPreVerbArgs build $colconBuildArgs")
    colcon $colconArgs

    mkdir $build
    tar -acf $build/build.tar.zst *
    pwd > $build/build_pwd.txt

    runHook postBuild
  '';

  # no expand: set -v
  # expand: set -x
  preFixup = ''
    # Root directory setup files that we don't want. We should be able to also remove
    # the .catkin file, but currently that breaks CATKIN_WORKSPACES, see: SES-2444
    rm -f $out/{setup.*,local_setup.*,_local_setup_util_sh.py,.colcon_install_layout,COLCON_IGNORE}

    # Remove the develspace as this can lead to rpath issues, especially with
    # python bindings.
    rm -rf build/${name}/devel

    # If it exists and we have a dev output, move the cmake directory to dev, and if so
    # also symlink the package.xml there, if that exists.
    if [[ -n "$dev" && -e $out/share/$name/cmake ]]; then
      moveToOutput "share/$name/cmake" "$dev"
      package_xml=share/$name/package.xml
      if [[ -e $out/$package_xml ]]; then
        mkdir -p $(dirname $dev/$package_xml)
        ln -s $out/$package_xml $dev/$package_xml
      fi
      ln -s $out/*local_setup* $dev/
    fi
  '';

  # Mark this derivation as a colcon package so that we can later sort colcon and non-colcon
  # packages for the purposes of assembling environments.
  passthru = {
    colconPackage = true;

    inherit colconBuildDepends colconRunDepends colconTestDepends;
    inherit colconRecursiveBuildDepends nonColconRecursiveBuildDepends;
    inherit colconRecursiveDocDepends nonColconRecursiveDocDepends;
    inherit colconRecursiveTestDepends nonColconRecursiveTestDepends;

    inherit testDisableCompile testDisableRun;

    inherit pkgFinal;
    inherit docs;
    inherit (testing) testCompile test;

    debugDir = quietSymlinkJoin {
      name = "${name}-debug-dir";
      paths = recursiveDebugTargets ++ lib.optional ((pkgFinal.debug or null) != null) pkgFinal.debug;
    };

    ws = buildColconWorkspace {
      name = pkgFinal.name;
      colconPackages = [
        pkgFinal
      ];
      includeBuildDepends = true;
    };

    # Minimal derivation that exports the NIX_DEBUG_INFO_DIRS to point to the provided debug symbols.
    debugEnv = stdenvNoCC.mkDerivation ({
      name = "${name}-debugEnv";
      buildInputs = [pkgFinal.debugDir setupDebugInfoDirs];
      # We just pull in the debug dir into the out folder, we must have an out folder, might as well make the
      # debug targets accessible for those that want to manually access them.
      src = pkgFinal.debugDir;
      phases = [ "unpackPhase"  "configurePhase" ];
      outputs = [ "out" ];
      configurePhase = ''
        mkdir $out
        cp -r lib $out/
      '';

      shellHook = ''
        source ${debugEnvHelper}/workspace_info.sh
        source ${debugEnvHelper}/change_shell_prompt.sh
      '';
    });
  } // passthru;

  # This removeAttrs is necessary because otherwise pkgFinal has to resolve as part of the
  # bash environment, and that triggers an infinite recursion.
} // removeAttrs attrs [ "pkgFinal" "testDisableRun" "testDisableCompile" ])
