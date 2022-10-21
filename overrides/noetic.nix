{
  fetchFromGitHub,
  fetchpatch,
  fetchzip,
  lib,
  stdenv,
  writeText,

  catkinTestData,

  pkgs,
  python3
}:

let
  disableTestCompile = pkg: pkg.overrideColconAttrs(old: {
    testDisableCompile = true;
  });

in rosFinal: rosPrev: {
  # This section is for overrides within our ros scope. This includes providing our own
  # scoped python, boost, and gtest, but also patching up packages from the
  # auto-generated pool. Credit for a number of these patches from:
  # https://github.com/lopsided98/nix-ros-overlay/blob/master/distros/distro-overlay.nix

  # Add/update Python versions within our ros-scoped Python. It's important that this happens
  # here as there can be some surprising rebuild-triggers, like changing the global Django
  # changes Sphinx, which causes anything with Sphinx documentation to rebuild.
  inherit python3;
  python3Packages = python3.pkgs;

  #   
  boost = pkgs.ros-boost;

  # Copied from https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/libraries/libyaml-cpp/default.nix
  # can be removed on the next nixpkgs sync.
  libyamlcpp = pkgs.libyamlcpp.overrideAttrs(_: {
    patches = [
      (fetchpatch {
        url = "https://github.com/jbeder/yaml-cpp/commit/4f48727b365962e31451cd91027bd797bc7d2ee7.patch";
        sha256 = "sha256-jarZAh7NgwL3xXzxijDiAQmC/EC2WYfNMkYHEIQBPhM=";
      })
      (fetchpatch {
        url = "https://github.com/jbeder/yaml-cpp/commit/328d2d85e833be7cb5a0ab246cc3f5d7e16fc67a.patch";
        sha256 = "12g5h7lxzd5v16ykay03zww5g28j3k69k228yr3v8fnmyv2spkfl";
      })
    ];
  });

  # Scoping this override prevents blender from rebuilding.
  openvdb = (pkgs.openvdb.override {
    boost = rosFinal.boost;
  }).overrideAttrs(_: {
    setupHook = writeText "setup-hook.sh" ''
      export OPENVDB_ROOT=$1
    '';
  });

  # Disable slow/large parts of these builds that we do not need.
  libg2o = rosPrev.libg2o.overrideColconAttrs {
    colconCMakeArgs = [ "-DG2O_BUILD_EXAMPLES=0" "-DG2O_BUILD_APPS=0" ];
  };
  ompl = rosPrev.ompl.overrideColconAttrs {
    colconCMakeArgs = [ "-DOMPL_BUILD_TESTS=0" "-DOMPL_BUILD_DEMOS=0" ];
  };

  # Ensure that gtsam doesn't build against its bundled copy of eigen; also disable
  # building its tests and examples we don't care about.
  gtsam = rosPrev.gtsam.overrideColconAttrs(old: {
    colconCMakeArgs = [
      "-DGTSAM_WITH_EIGEN_MKL=0"
      "-DGTSAM_USE_SYSTEM_EIGEN=1"
      "-DGTSAM_BUILD_TESTS=0"
      "-DGTSAM_BUILD_EXAMPLES_ALWAYS=0"
      "-DGTSAM_BUILD_TIMING_ALWAYS=0"
      "-DGTSAM_BUILD_WITH_MARCH_NATIVE=0"
      "-DGTSAM_CMAKE_BUILD_TYPE=none"
    ];
    colconBuildDepends = old.colconBuildDepends ++ [ pkgs.eigen ];
    colconRunDepends = old.colconRunDepends ++ [ pkgs.tbb ];
  });

  catkin = rosPrev.catkin.overrideColconAttrs (_: {
    # Pending resolution to: https://github.com/ros/catkin/issues/1158
    src = fetchFromGitHub {
      owner = "ros";
      repo = "catkin";
      rev = "855c966f4b5f100d94e83778cbc8f873e2828dd1";
      hash = "sha256-XOCDkWo1U/yMH0fJ78XUdyXyPgFYBT8IxP95Yodx8Nk=";
    };

    postPatch = ''
      for f in $(grep -lr /usr/bin/env cmake/templates); do
        substituteInPlace $f --replace '/usr/bin/env' ${pkgs.coreutils}/bin/env
      done

      # Show catkin where Nix's gtest package is.
      substituteInPlace cmake/test/gtest.cmake --replace "\''${_googletest_path}" ${pkgs.gtest-src}
      substituteInPlace cmake/test/gtest.cmake --replace "\''${_gtest_path}" ${pkgs.gtest-src}/googletest
    '';

    # Disable the catkin unit tests, they fail on gtest things.
    testDisableCompile = true;
  });

  dynamic_reconfigure = rosPrev.dynamic_reconfigure.overrideAttrs (_: {
    postPatch = ''
      substituteInPlace cmake/setup_custom_pythonpath.sh.in \
        --replace '#!/usr/bin/env sh' '#!${stdenv.shell}'
    '';
  });

  python_qt_binding = rosPrev.python_qt_binding.overrideAttrs(_: {
    postPatch = ''
      sed -e "s#sipconfig\._pkg_config\['default_mod_dir'\]#'${rosFinal.python3Packages.pyqt5}/lib/python${rosFinal.python3.pythonVersion}/site-packages'#" \
          -e "s#qtconfig\['QT_INSTALL_HEADERS'\]#'${pkgs.qt5.qtbase.dev}/include'#g" \
          -i cmake/sip_configure.py
    '';
    dontWrapQtApps = true;
  });

  # This override will almost certainly always be necessary, since Plotjuggler's CMake config
  # detects at configure time whether to build in cmake/ament/catkin mode.
  plotjuggler = rosPrev.plotjuggler.overrideColconAttrs(old: {
    colconCMakeArgs = [ "-DCATKIN_BUILD_BINARY_PACKAGE=1" ];
    colconBuildDepends = old.colconBuildDepends ++ [
      rosFinal.catkin
      rosFinal.roslib
    ];
  });

  # SES-2447; Disable testCompile phase for several upstream packages.
  async_web_server_cpp = disableTestCompile rosPrev.async_web_server_cpp; # upstream missing dependencies.
  diff_drive_controller = disableTestCompile rosPrev.diff_drive_controller; # broken xacro file in tests.
  laser_geometry = disableTestCompile rosPrev.laser_geometry; # Produces crazy amounts of failed asserts. (1.2GB+)
  robot_state_publisher = disableTestCompile rosPrev.robot_state_publisher; # Downloads a bag file into devel dir.
  transmission_interface = disableTestCompile rosPrev.transmission_interface; # missing headers.
  openvslam = disableTestCompile rosPrev.openvslam; # Installs during test run, upstream.
  robot_localization = disableTestCompile rosPrev.robot_localization; # Stalls forever when ran.
}
