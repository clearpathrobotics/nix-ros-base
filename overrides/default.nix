final: prev:

let
  overrideBoost = pkg: pkg.override {
    boost = final.ros-boost;
  };

  # This curious construct allows multiple levels of python3.packageOverride to compose
  # together, which we need since nix-ros-overlay already overrides it to add in stuff like
  # catkin-pkg that we obviously very much need. See also:
  # https://discourse.nixos.org/t/makeextensibleasoverlay/7116/5
  python3 = final.lib.fix (py:
    final.python310.override (old: {
      self = final.python310;
      packageOverrides = final.lib.composeManyExtensions [
        old.packageOverrides
        # Other python overlay
      ];
    })
  );

in {
  noetic = prev.noetic.overrideScope' (final.callPackage ./noetic.nix {
    inherit python3;
  });

  rolling = prev.rolling.overrideScope' (final.callPackage ./rolling.nix {
    inherit python3;
  });

  # This section is for overrides at the global scope. Caution should be used here as many
  # packages will trigger mass rebuilds when altered. Typically we should add modifications
  # under new names here, unless it's a change we're proposing to nixpkgs, or something
  # where we know we'll need it globally, like PCL or OpenCV.

  # Our scoped boost version is newer than the Nix default and also must include the
  # Python bindings with the correct Python version. Boost 1.73 is chosen as it is the
  # first which supplies a usable CMake config in the split install case, see:
  # https://github.com/NixOS/nixpkgs/issues/63104#issuecomment-914760816
  ros-boost = final.boost.override {
    python = python3;
    enablePython = true;
    enableNumpy = true;
  };

  # These packages need to use our ROS boost or we get link conflict in leaf packages
  # that combine them. But we don't want to set the global boost or we end up having
  # to rebuild other low-level system stuff.

  gazebo_11 = prev.gazebo_11.override {
    boost = final.ros-boost;
  };

  # Gazebo 11 uses Ogre 1.10, everything else (rviz) uses Ogre 1.9 still. This is fine,
  # but it does mean we need to patch both of them.
  ogre1_9 = overrideBoost prev.ogre1_9;
  ogre1_10 = overrideBoost prev.ogre1_10;

  opencv3 = (prev.opencv3.override {
    boost = final.ros-boost;
    enablePython = true;
    enableUnfree = true;
    enableVtk = true;
    pythonPackages = python3.pkgs;
    openblas = final.openblasCompat;
  }).overrideAttrs(old: {
    buildInputs = old.buildInputs ++ [ final.gtk3 ];

    # Use statically-linked internal protobuf to avoid propagation conflicts with other
    # protobuf versions, such as from Tensorflow.
    cmakeFlags = old.cmakeFlags ++ [ "-DBUILD_PROTOBUF=ON" "-DPROTOBUF_UPDATE_FILES=OFF" ];
  });

  suitesparse = prev.suitesparse.overrideAttrs(_: {
    propagatedBuildInputs = [ final.blas ];

    # Ticketed: https://github.com/DrTimothyAldenDavis/SuiteSparse/issues/112
    postPatch = ''
      sed -i -e "s/-gencode=arch=compute_30,code=sm_30//g" CHOLMOD/Tcov/Makefile
      sed -i -e "s/-gencode=arch=compute_30,code=sm_30//g" SuiteSparse_config/SuiteSparse_config.mk
    '';

    # Add a symlink to permit namespaced include use, similar to how Debian's package is.
    postFixup = ''
      ln -s $dev/include $dev/include/suitesparse
    '';
  });

  pcl = (prev.pcl.override {
    boost = final.ros-boost;
  }).overrideAttrs(old: rec {
    propagatedBuildInputs = old.propagatedBuildInputs ++ [ final.xorg.libXt ];
    CXXFLAGS = "${toString final.rosCompileFlags} -std=c++11";
    patches = [
      (final.fetchpatch {
        url = "https://github.com/PointCloudLibrary/pcl/commit/614e19d96bd8415dbfb52d86df0f3774a9f462fe.patch";
        sha256 = "sha256-mI4gPpoZdGA26ST8YLfeNUWTNCUoWeW61flc5f1BF9U=";
      })
    ];

    postPatch = ''
      sed -i -e "s/input_transformed_blob.reset(new PCLPointCloud2)/input_transformed_blob = pcl::make_shared<PCLPointCloud2>()/g" registration/include/pcl/registration/impl/icp.hpp
      sed -i -e "s/(new PointCloudSource)/ = pcl::make_shared<PointCloudSource>()/g" registration/include/pcl/registration/impl/icp.hpp
      sed -i -e "s/(new PCLPointCloud2)/ = pcl::make_shared<PCLPointCloud2>()/g" registration/include/pcl/registration/impl/icp.hpp
    '';
  });

  ceres-solver = prev.ceres-solver.overrideAttrs(old: {
    propagatedBuildInputs = old.propagatedBuildInputs ++ [ final.suitesparse ];
    cmakeFlags = [ "-DBUILD_SHARED_LIBS=ON" ];
    outputs = [ "out" "dev" ];
  });
}
