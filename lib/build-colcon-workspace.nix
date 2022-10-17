{ buildEnv,
  bundleRelease,
  colconForDevelopment,
  colconDevelopHome,
  colconMinimal,
  colconMinimalDocs,
  developShellInfo,
  developShellPreventMixing,
  graphviz,
  lib,
  linkFarm,
  qt5,
  quietSymlinkJoin,
  rsync,
  runCommand,
  setupDebugInfoDirs,
  stdenv,
  stdenvNoCC,
  symlinkJoin,
  writeTextFile,
}:

{ name ? "colcon-ws",
  colconPackages,
  nonColconPackages ? [],
  disallowedColconPackages ? [],
  includeBuildDepends ? false,
  includeDebugSymbols ? false,
  ... }@args:

# Portions of this are significantly inspired by:
# https://github.com/lopsided98/nix-ros-overlay/blob/master/distros/build-env/default.nix

with lib; let
  # Function that can get the propagated colcon packages, capable of limiting recursion.
  # packages: The initial list of packages to operate on.
  # current_recursion: The current level of recursion gets incremented with each level.
  # max_recursions: If the current_level is equal to this value recursion is halted.
  propagateColconPackagesLimitedWorker = packages: current_recursion: max_recursions: let
    validPackages = if ((max_recursions == null) || (current_recursion <= max_recursions)) then (filter (d: d != null) packages) else [];
    propagatedColconRunDepends = if (validPackages != null) then 
      filter (d: d.colconPackage or false) (unique (concatLists
        (catAttrs "colconRunDepends" validPackages)
      ))
    else [];
    recurse = propagateColconPackagesLimitedWorker propagatedColconRunDepends (current_recursion + 1) max_recursions;
  in
    if length validPackages > 0 then
      unique (recurse ++ validPackages)
    else
      [];

  # Function that can get the propagated colcon packages, capable of limiting recursion.
  # packages: The initial list of packages to operate on.
  # max_recursions: If the current_level is equal to this value recursion is halted.
  propagateColconPackagesLimited = packages: max_recursions: (propagateColconPackagesLimitedWorker packages 0 max_recursions);

  propagateColconPackages = packages: propagateColconPackagesLimited packages null;


  # Provide alias for colcon to point at the development version of colcon.
  colcon = colconForDevelopment;

  # Get the set of all recursive run dependencies for the packages in the workspace. This set
  # is needed whether we're developing or just running existing binaries.
  colconRecursiveRunDepends = propagateColconPackages (flatten colconPackages);

  # Include a single layer of build dependencies. We don't want build dependencies of build
  # dependencies, but we do want all build dependencies of our workspace packages, to be
  # optionally included in the workspace if includeBuildDepends is set.
  colconBuildDepends = filter (d: d.colconPackage or false) (unique (concatLists
    (catAttrs "colconBuildDepends" colconRecursiveRunDepends)
  ));

  # All packages to be included in the merged colcon workspace.
  colconWorkspacePackages = if includeBuildDepends then
    (concatLists [colconRecursiveRunDepends colconBuildDepends])
  else
    colconRecursiveRunDepends;

  # Include all build dependencies of the workspace packages. These will all be system packages,
  # since we know that buildInputs in colconPackage are always system packages.
  nonColconBuildDepends = if includeBuildDepends then
    unique (concatLists (catAttrs "buildInputs" colconWorkspacePackages))
  else
    [];

  # Include all non-workspace runtime dependencies of the workspace packages.
  nonColconRunDepends = filter (d: !(d.colconPackage or false)) (unique (concatLists
    (catAttrs "colconRunDepends" colconRecursiveRunDepends)
  ));

  nonColconDepends = unique (nonColconBuildDepends ++ nonColconRunDepends ++ nonColconPackages);

  # With all dependencies known, we can collect the debug symbols.
  debugSymbols = map (d: d.debug) (filter (d: ((d.debug or null) != null)) (colconWorkspacePackages
                                                                              ++ nonColconDepends));

  # Target that holds the recursive debug symbols and debug symbols for this package itself.
  debugDir = symlinkJoin {
    name = "${name}-debug-dir";
    paths = debugSymbols;
  };


  # Collect all tests
  getTest = packages: map (d: d.test) (filter (d: ((d.test or null) != null)) (flatten packages));
  getTestCompile = packages: map (d: d.testCompile) (filter (d: ((d.test or null) != null)) (flatten packages));

  # Actual targets, recursive
  testTargetsRecursive = getTest colconWorkspacePackages;
  testTargetsCompileRecursive = getTestCompile colconWorkspacePackages;

  # Only immediate members of this workspace.
  testTargets = getTest colconPackages;
  testTargetsCompile = getTestCompile colconPackages;

  # Additional 'levels' of propagation can be done with;
  testTargets1 = getTest (propagateColconPackagesLimited (flatten colconPackages) 1); # Test of immediate members.
  testTargets2 = getTest (propagateColconPackagesLimited (flatten colconPackages) 2); # Immediate + 1 additional level.

  makeTestTarget = x: let
      mkDepEntryFromDrv = drv: { name = "${drv.original_name}"; path = drv; };
    in linkFarm "${name}-${builtins.readFile bundleRelease}"
      ((map mkDepEntryFromDrv (unique x)));

  makeJoinedTestTargets = x: quietSymlinkJoin {
    name = "${name}-test-targets";
    paths = x;
  };

  # Pretty useless target here, it contains symlinks of zip files... but it does allow us to compile all the tests.
  makeJoinedTestCompileTargets = makeTestTarget;

  # Helper to generate a test summary for a list of test targets.
  makeWorkspaceTestSummary = test_list: let
    test_results =  (makeJoinedTestTargets test_list);
  in stdenvNoCC.mkDerivation {
    name = "${name}-test-results";
    phases = ["buildPhase"];
    nativeBuildInputs = [ colconMinimal ];

    buildPhase = ''
      mkdir -p $out
      # Disable quit on error, we want to be able to capture the return code, not exit if it fails.
      set +e
      # Dump verbose output into verbose file.
      colcon test-result --all --verbose --test-result-base ${test_results}/test_results/ > $out/test_results_all_verbose.txt
      # Can't use tee here to duplicate to stdout and capture to file as the return code would be from tee.
      local var;  var=$(colcon test-result --test-result-base ${test_results}/test_results/)
      echo $? > $out/return_code.txt
      # Now that we have the return code, we can echo and write to file.
      echo "$var" | tee $out/test_results.txt
    '';
  };

  # The real test subtargets, recursive summary and compile.
  testRecursiveSummary = makeWorkspaceTestSummary testTargetsRecursive;
  testRecursiveCompile = makeJoinedTestCompileTargets testTargetsCompileRecursive;
  testRecursiveResults = makeJoinedTestCompileTargets testTargetsRecursive;

  # The real test subtargets, immediate packages in this workspaces' summary and compile.
  testSummary = makeWorkspaceTestSummary testTargets;
  testCompile = makeJoinedTestCompileTargets testTargetsCompile;
  testResults = makeJoinedTestCompileTargets testTargets;


  # This runs colcon with an empty workspace, just so it can generate what its setup
  # files look like for a merged installspace.
  colconMergedInstall = runCommand "colcon-merged" {} ''
    ${colcon}/bin/colcon build --merge-install --install-base $out
    rm $out/COLCON_IGNORE
  '';

  developEnvHelper = developShellInfo {
    name = "${name}";
  };

  developShellPreventMixingHelper = developShellPreventMixing {
    name = "${name}";
  };

  # Collect all colconWorkspaceHooks.
  collectWorkspaceHooks = let
      mkDepEntryFromDrv = drv: {
        name = "${drv.name}.sh";
        path =  writeTextFile {
          name = "colcon_workspace_hooks-${drv.name}.sh";
          text = drv.passthru.colconWorkspaceHook;
          executable = true;
        };
      };
    in linkFarm "colcon_workspace_hooks"
      (map mkDepEntryFromDrv (unique (filter (x: (hasAttr "colconWorkspaceHook" x.passthru)) colconWorkspacePackages)));

  # This buildEnv is not the final result, but rather an intermediate which is referenced
  # in the mkDerivation that is actually returned.
  mergedColconEnv = (buildEnv ({
    name = "${name}-merged";

    pathsToLink = [ "/etc" "/share" "/bin" "/lib" "/include" "/lib64" "/cmake" ];

    # Link the paths from all colcon packages, synthesizing a merged installspace.
    paths = colconWorkspacePackages ++ lib.optional includeDebugSymbols debugDir;

    postBuild = ''
      echo "copying colcon setup files from ${colconMergedInstall}"
      ${rsync}/bin/rsync -r ${colconMergedInstall}/ $out/

      echo "patching colcon-generated setup.sh files for new location"
      substituteInPlace $out/setup.sh --replace ${colconMergedInstall} $out
      substituteInPlace $out/local_setup.sh --replace ${colconMergedInstall} $out

      echo "creating workspace marker file, needed for ROS_PACKAGE_PATH and message generation"
      touch $out/.catkin

      echo "creating etc/ros/.release file with version info"
      mkdir -p $out/etc/ros
      ln -s ${bundleRelease} $out/etc/ros/.release

      echo "Copying the workspace hooks"
      ln -s ${collectWorkspaceHooks}/ $out/colcon_workspace_hooks
      # And write the shell file to source those hooks.
      echo "while IFS= read -r -d \$'\0' f; do source \$f; done < <(find -L $out/colcon_workspace_hooks/ -type f -print0)" > $out/colcon_workspace_hooks.sh

      echo "Exporting QT environment additions, doing this here avoids having to wrap every binary."
      echo export QT_PLUGIN_PATH="${qt5.qtbase.bin}/lib/qt-${qt5.qtbase.version}/plugins"''\\$\{QT_PLUGIN_PATH\:+\':\'}\$QT_PLUGIN_PATH >> $out/qt_env_hooks.sh
      echo export QT_PLUGIN_PATH="${qt5.qtsvg.bin}/lib/qt-${qt5.qtsvg.version}/plugins"''\\$\{QT_PLUGIN_PATH\:+\':\'}\$QT_PLUGIN_PATH  >> $out/qt_env_hooks.sh
      echo export QT_PLUGIN_PATH="${qt5.qtdeclarative.bin}/lib/qt-${qt5.qtdeclarative.version}/plugins"''\\$\{QT_PLUGIN_PATH\:+\':\'}\$QT_PLUGIN_PATH  >> $out/qt_env_hooks.sh
      echo export QT_PLUGIN_PATH="${qt5.qtwayland.bin}/lib/qt-${qt5.qtwayland.version}/plugins"''\\$\{QT_PLUGIN_PATH\:+\':\'}\$QT_PLUGIN_PATH  >> $out/qt_env_hooks.sh
      echo export QML2_IMPORT_PATH="${qt5.qtdeclarative}/lib/qt-${qt5.qtdeclarative.version}/qml"''\\$\{QML2_IMPORT_PATH\:+\':\'}\$QML2_IMPORT_PATH >> $out/qt_env_hooks.sh
      echo export QML2_IMPORT_PATH="${qt5.qtquickcontrols}/lib/qt-${qt5.qtquickcontrols.version}/qml"''\\$\{QML2_IMPORT_PATH\:+\':\'}\$QML2_IMPORT_PATH >> $out/qt_env_hooks.sh
      echo export QML2_IMPORT_PATH="${qt5.qtwayland.bin}/lib/qt-${qt5.qtwayland.version}/qml"''\\$\{QML2_IMPORT_PATH\:+\':\'}\$QML2_IMPORT_PATH >> $out/qt_env_hooks.sh

      echo "Exporting XDG_DATA_DIRS to include /usr/share, this allows applications to use theme assets like icons from the host OS."
      echo export XDG_DATA_DIRS="/usr/share/"''\\$\{XDG_DATA_DIRS\:+\':\'}\$XDG_DATA_DIRS >> $out/gtk_env_hooks.sh

      echo "Setting NIX_DEBUG_INFO_DIRS such that we can find the debug symbols."
      echo export NIX_DEBUG_INFO_DIRS="$out/lib/debug/" > $out/gdb_env_hooks.sh

      echo "Setting up conditional nixGL environment variables to support graphics card drivers properly."
      # Just sourcing the nixGL wrapper seems to be the most elegant.
      cat <<EOT >> $out/nixgl_env_hooks.sh
      export _nixGLLocation=''\\$(which nixGL 2> /dev/null)
      if [ ! -z ''\\$_nixGLLocation ]; then
          source ''\\$_nixGLLocation
      fi
      EOT
    '';
  })).overrideAttrs(_: {
    disallowedReferences = disallowedColconPackages;
  });

  colconWorkspacePackagesDocs = map (d: d.docs) colconWorkspacePackages;

  workspaceDocsSummary = stdenvNoCC.mkDerivation {
    name = "${name}-docs-summary";
    phases = ["buildPhase"];
    nativeBuildInputs = [
        colconMinimalDocs
        graphviz
      ];
    colconDocumentArgs = [
        "--docs-base $out" "--create-summary"
      ];

    COLCON_DOCUMENT_PATH = lib.makeSearchPath "/" colconWorkspacePackagesDocs;

    buildPhase = ''
        mkdir $out
        colconArgs=$(eval echo "document $colconDocumentArgs")
        colcon $colconArgs
        rm -f $out/COLCON_IGNORE
    '';

  };

in
  stdenv.mkDerivation {
    inherit name;

    # These packages will be brought into context by "nix develop" using the usual Nix mechanisms.
    buildInputs = nonColconDepends;

    # Native inputs are for tools that would not be linked to or executed on a target.
    nativeBuildInputs = [ colcon colconDevelopHome ];

    # After the main Nix environment setup is done, source the colcon setup file as well. The shellHook
    # is later in the bringup, when all of bashInteractive (include "complete") is available, unlike
    # with the postHook.
    shellHook = ''
      source ${developShellPreventMixingHelper}/guard.sh
      source ${mergedColconEnv}/qt_env_hooks.sh
      source ${mergedColconEnv}/gtk_env_hooks.sh
      source ${mergedColconEnv}/nixgl_env_hooks.sh
      source ${mergedColconEnv}/gdb_env_hooks.sh
      source ${mergedColconEnv}/colcon_workspace_hooks.sh
      source ${developEnvHelper}/workspace_info.sh
      source ${developEnvHelper}/change_shell_prompt.sh
      source ${mergedColconEnv}/setup.bash
      export COLCON_HOME=${colconDevelopHome}
    '';

    # This will notify a user attempting to build this derivation rather than use it with nix develop
    # or nix print-dev-env that they've made a wrong turn.
    buildCommand = ''
      echo -e >&2 "-"
      echo -e >&2 "- \033[0;31mColcon workspace derivations are for interactive sessions only.\033[0m"
      echo -e >&2 "- Use '\033[0;32mnix develop\033[0m' instead of 'nix build'."
      echo -e >&2 "-"
      exit 1
    '';

    # This provides a buildable target for CI/caching purposes, though the end result is not itself
    # useful for anything. We could have included the individual colcon package derivations here
    # but using the mergedColconEnv is faster and ensures that that too is built and cached.
    # The reason this is a bit custom is that linkFarmFromDrvs had issues with collisions on multi-
    # output derivations (like boost) where the multiple outputs all have the same name attribute.
    contents = let
      mkDepEntryFromDrv = drv: { name = "deps/${drv.name}/${drv.outputName}"; path = drv; };
    in linkFarm "${name}-${builtins.readFile bundleRelease}"
      ((map mkDepEntryFromDrv (filter (v: builtins.isAttrs v) nonColconDepends)) ++ [
        { name = "merged"; path = "${mergedColconEnv}"; }
        { name = "colcon"; path = "${colcon}"; }
      ]);


    passthru = {
      inherit
        colconBuildDepends
        colconRecursiveRunDepends
        colconWorkspacePackages
        mergedColconEnv
        nonColconBuildDepends
        nonColconDepends
        workspaceDocsSummary
        nonColconRunDepends
        debugDir

        # Just for inspection.
        testTargets
        testTargets1
        testTargets2
        testTargetsRecursive
        # Actual test targets
        testRecursiveResults
        testRecursiveSummary
        testRecursiveCompile
        testResults
        testSummary
        testCompile;


      docs = symlinkJoin {
        name = "${name}-docs";
        paths = colconWorkspacePackagesDocs ++ [ workspaceDocsSummary ];
      };
    };
  } // args
