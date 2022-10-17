final: prev: let 

  # Helper function to make the list of cmake args from a set of flags.
  make_flags = flags: [
    # Don't use gnu++14, instead always stick to c++14.
    "-DCMAKE_CXX_EXTENSIONS=OFF"
    "-DCMAKE_CXX_FLAGS='${toString flags}'"
    "-DCMAKE_C_FLAGS='${toString flags}'"
    # Only link as needed, see SES-2446
    "-DCMAKE_SHARED_LINKER_FLAGS='-Wl,--as-needed'"
    # Setuptools can't be passed the '--install-layout' argument.
    "-DSETUPTOOLS_DEB_LAYOUT=OFF"
    # Tell cmake not to touch rpaths when it installs libraries. SES-2834
    # Somehow this also affects the behaviour during install.
    # https://cmake.org/cmake/help/latest/variable/CMAKE_SKIP_RPATH.html
    "-DCMAKE_SKIP_RPATH=ON"
  ];

  # https://stackoverflow.com/a/54505212
  # Merges list of records, concatenates arrays, if two values can't be merged - the latter is preferred
  recursiveMerge = with final.lib; attrList:
    let f = attrPath:
      zipAttrsWith (n: values:
        if tail values == []
          then head values
        else if all isList values
          then unique (concatLists values)
        else if all isAttrs values
          then f (attrPath ++ [n]) values
        else last values
      );
    in f [] attrList;

  # The available mixins for easy consumption. Key and the 'name' value MUST be identical.
  build_mixins = let
      # Use the let-in such that we can compose mixins here, as colcon doesn't support that.

      flags-value = {
        cmake-args = make_flags (final.rosCompileFlags ++ final.extraColconCompileFlags);
      };

      flags-clang-value = {
        cmake-args = let
          # The following flags are not supported by clang, they can be removed without any abi changes.
          unsupportedInClang = [
            # no-abm specifies no advanced bit manipulation instructions should be used. Bmi1/bmi2 are used on clang.
            "-mno-abm"
            # no-hle specifies no hardware lock elison, disabled via a microcode update, clang doesn't use it.
            "-mno-hle"
            # Clang doesn't have these param entries, they are probably used by optimisations in gcc.
            "--param l1-cache-line-size=64"
            "--param l1-cache-size=32"
            "--param l2-cache-size=6144"
          ];
          # We add the following to ensure debug symbols are in a style gdb likes very much. This ensures we don't
          # end up with undeined types when debugging a clang-compiled binary with gdb.
          toAddToClang = [ "-ggdb" ];
          # Finally, we can make the clang flags.
          clangCompileFlags = final.lib.subtractLists unsupportedInClang final.rosCompileFlags;
          flags = clangCompileFlags ++ final.extraColconCompileFlags ++ toAddToClang;
        in make_flags flags;
      };

      workspace-setup-value = {
        # Use a merged install space that's easy to source in full.
        merge-install = true;
        # Symlink as much as possible, this ensures install/ is up to date when libraries get rebuild from the build
        # folder through make invocation.
        symlink-install = true;
        cmake-args = [
            # Export the compile_commands.json file for IDEs and clang-tidy.
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            # Prevent cmake from complaining about variables passed to packages that go unused.
            "--no-warn-unused-cli"
        ];
      };

      clang-value = {
        cmake-args = [
          "-DCMAKE_C_COMPILER=clang"
          "-DCMAKE_CXX_COMPILER=clang++"
        ];
      };

      skip-building-tests-value = {
        # For catkin packages (flag in the colcon-ros plugin).
        catkin-skip-building-tests = true;

        # Standard for CMake and ament packages.
        cmake-args = [
          "-DBUILD_TESTING=OFF"
        ];
      };

      force-building-tests-value = {
        # For catkin packages (flag in the colcon-ros plugin).
        catkin-skip-building-tests = false;

        # Standard for CMake and ament packages.
        cmake-args = [
          "-DBUILD_TESTING=ON"
        ];
      };

  in {
    flags = {
      name = "flags";
      value = flags-value;
    };

    # Equivalent compile flags when using clang.
    flags-clang = {
      name = "flags-clang";
      value = flags-clang-value;
    };

    verbose = {
      name = "verbose";
      value = {
        event-handlers = [ "console_direct+" ];
      };
    };

    cpr-no-unity = {
      name = "cpr-no-unity";
      value = {
        # Disables unity builds for all packages, this may cause warnings about unused cmake arguments for packages
        # that do not use cpr_unity cmake files.
        cmake-args = [ "-Dcpr_unity_build=off" ];
      };
    };

    workspace-setup = {
      name = "workspace-setup";
      value = workspace-setup-value;
    };

    skip-building-tests = {
      name = "skip-building-tests";
      value = skip-building-tests-value;
    };

    force-building-tests = {
      name = "force-building-tests";
      value = force-building-tests-value;
    };

    # Compose the 'ws' flag as a composite of enabling the merge install space and the flags.
    ws = {
      name = "ws";
      value = (recursiveMerge [flags-value workspace-setup-value skip-building-tests-value]);
    };
    ws-test = {
      name = "ws-test";
      value = (recursiveMerge [flags-value workspace-setup-value force-building-tests-value]);
    };

    # And, compose the ws-clang mixin from the workspace values, clang compiler and clang flags.
    ws-clang = {
      name = "ws-clang";
      value = (recursiveMerge [workspace-setup-value clang-value flags-clang-value skip-building-tests-value]);
    };
    ws-clang-test = {
      name = "ws-clang-test";
      value = (recursiveMerge [workspace-setup-value clang-value flags-clang-value]);
    };

    # Mixin to use the clang compiler.
    clang = {
      name = "clang";
      value = clang-value;
    };

    # Mixin to use ccache as a compiler prefix.
    ccache = {
      name = "ccache";
      value = {
        cmake-args = [
          "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
          "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        ];
      };
    };
  };

  # A list of all build mixins that are known.
  build_mixins_all = final.lib.attrValues build_mixins;

  test_mixins = {
    workspace-setup = {
      name = "workspace-setup";
      value = {
        # Workspace was built with merge install, so test with merge install by default.
        merge-install = true;
      };
    };
  };
  # A list of all test mixins that are known.
  test_mixins_all = final.lib.attrValues test_mixins;

  readFileList = filename: with final.lib;
    lists.remove "" (splitString "\n" (readFile filename));

  # List of flags to pass to g++ and gcc when compiling all distribution packages; as a variable
  # here it is also available to be patched into non-distribution packages like Tensorflow.
  rosCompileFlags = readFileList ./flags.txt;

in {
  inherit rosCompileFlags;

  # Extra compile flags used only for colcon packages.
  # - BOOST_BIND_GLOBAL_PLACEHOLDERS: Prevents boost from warning about the bind placeholders being placed in the global
  #   namespace. Upstream ros_comm tried to correct the usage, but dependencies were expecting the placeholders to be
  #   defined, ultimately the change was backed out again in https://github.com/ros/ros_comm/pull/2187
  extraColconCompileFlags = [
    "-DBOOST_BIND_GLOBAL_PLACEHOLDERS=1"
  ];

  # colconHome is used for all colcon packages.
  colconHome = final.callPackage ./colcon-home.nix {
    defaultBuildMixins = [ build_mixins.flags build_mixins.skip-building-tests ];
    providedBuildMixins = [];
  };

  colconHomeTest = final.callPackage ./colcon-home.nix {
    defaultBuildMixins = [ build_mixins.flags  build_mixins.force-building-tests ];
    providedBuildMixins = [];
  };

  # colconDevelopHome is used for the development workspace.
  colconDevelopHome = final.callPackage ./colcon-home.nix {
    defaultBuildMixins = [ build_mixins.ws ];
    providedBuildMixins = build_mixins_all;
    defaultTestMixins = [ test_mixins.workspace-setup ];
    providedTestMixins = test_mixins_all;
  };
}
