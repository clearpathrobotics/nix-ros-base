{
  buildColconPackage,
  rosCompileFlags,
  fetchFromGitHub,
  fetchgit,
  fetchpatch,
  fetchurl,
  lib,
  makeWrapper,
  propagateColconRunDepends,
  runCommand,
  stdenv,
  writeText,

  pkgs,
  python3
}:

let

  patchVendorUrl = pkg: {
    url, sha256,
    originalUrl ? url,
    file ? "CMakeLists.txt"
  }: pkg.overrideAttrs ({
    postPatch ? "", ...
  }: {
    postPatch = ''
      substituteInPlace '${file}' \
        --replace '${originalUrl}' '${fetchurl { inherit url sha256; }}'
    '' + postPatch;
  });

  patchVendorGit = pkg: {
    url,
    file ? "CMakeLists.txt",
    fetchgitArgs ? {}
  }: pkg.overrideAttrs ({
    postPatch ? "", ...
  }: {
    postPatch = ''
      sed -i '\|GIT_REPOSITORY\s.*${lib.escapeShellArg url}|c\
        URL "${fetchgit ({ inherit url; } // fetchgitArgs)}"' \
        '${file}'
    '' + postPatch;
  });

  runtimeDependencies = [
    pkgs.ros2.rmw_cyclonedds_cpp
    pkgs.ros2.rmw_fastrtps_cpp
  ];

in rosFinal: rosPrev: {
  inherit python3;
  python3Packages = python3.pkgs;

  boost = pkgs.boost173.override {
    python = rosFinal.python3;
    enablePython = true;
    enableNumpy = true;
  };

  gbenchmark = pkgs.gbenchmark.overrideAttrs(_: {
    cmakeFlags = [ "-DBUILD_SHARED_LIBS=ON" ];
    doCheck = false;
  });

  cyclonedds = rosPrev.cyclonedds.overrideColconAttrs {
    colconCMakeArgs = [
      "-DBUILD_IDLC=OFF"     # Tries to download something with maven
      "-DBUILD_DDSPERF=OFF"  # Throws a make error
    ];

    # Fix running ddsconf from within the build directory (probably an RPATH issue)
    preConfigure = ''
      export LD_LIBRARY_PATH="$(pwd)/build/lib"
    '';
  };

  google_benchmark_vendor = patchVendorGit rosPrev.google_benchmark_vendor {
    url = "https://github.com/google/benchmark.git";
    fetchgitArgs = {
      rev = "c05843a9f622db08ad59804c190f98879b76beba";
      sha256 = "sha256-h/e2vJacUp7PITez9HPzGc5+ofz7Oplso44VibECmsI=";
    };
  };

  foonathan_memory_vendor = patchVendorGit rosPrev.foonathan_memory_vendor {
    url = "https://github.com/foonathan/memory.git";
    fetchgitArgs = {
      rev = "293f88d3a7cc49b25ffd4e9f27b1e4a8e14ee0d7";
      sha256 = "0nr74xv1ajvblvnl070l83zsr69nc1ws7fl2fvfjdq90kvwrz7in";
    };
  };

  mimick_vendor = (patchVendorGit rosPrev.mimick_vendor {
    url = "https://github.com/ros2/Mimick.git";
    fetchgitArgs = {
      rev = "a819614f43592f551697e5bc9dba8a16e7d9f44d";
      sha256 = "sha256-LHz0xFt7Q1HKPJBDUnQoHEPbWLZ2zBwj4vxy0LZ2c5c=";
    };
  });

  rmw_implementation = rosPrev.rmw_implementation.overrideColconAttrs(old: {
    colconRunDepends = old.colconRunDepends ++ [ rosFinal.rmw_cyclonedds_cpp ];
  });

  libyaml_vendor = patchVendorGit rosPrev.libyaml_vendor {
    url = "https://github.com/yaml/libyaml.git";
    fetchgitArgs = {
      rev = "2c891fc7a770e8ba2fec34fc6b545c672beb37e6";
      sha256 = "sha256-S7PnooyfyAsIiRAlEPGYkgkVACGaBaCItuqOwrq2+qM=";
    };
  };

  shared_queues_vendor = (patchVendorUrl (patchVendorUrl rosPrev.shared_queues_vendor {
    url = "https://github.com/cameron314/concurrentqueue/archive/8f65a8734d77c3cc00d74c0532efca872931d3ce.zip";
    sha256 = "0cmsmgc87ndd9hiv187xkvjkn8fipn3hsijjc864h2lfcyigbxq1";
  }) {
    url = "https://github.com/cameron314/readerwriterqueue/archive/ef7dfbf553288064347d51b8ac335f1ca489032a.zip";
    sha256 = "1255n51y1bjry97n4w60mgz6b9h14flfrxb01ihjf6pwvvfns8ag";
  }).overrideAttrs(_: {
    separateDebugInfo = false;
  });

  yaml_cpp_vendor = patchVendorUrl rosPrev.yaml_cpp_vendor {
    url = "https://github.com/jbeder/yaml-cpp/archive/0f9a586ca1dc29c2ecb8dd715a315b93e3f40f79.zip";
    sha256 = "1g45f71mk4gyca550177qf70v5cvavlsalmg7x8bi59j6z6f0mgz";
  };

  iceoryx_posh = patchVendorGit rosPrev.iceoryx_posh {
    url = "https://github.com/skystrife/cpptoml.git";
    file = "cmake/cpptoml/cpptoml.cmake.in";
    fetchgitArgs = {
      rev = "v0.1.1";
      sha256 = "0gxzzi4xbjszzlvmzaniayrd190kag1pmkn1h384s80cvqphbr00";
    };
  };

  pybind11_vendor = patchVendorUrl rosPrev.pybind11_vendor {
    url = "https://github.com/pybind/pybind11/archive/v2.5.0.tar.gz";
    sha256 = "0145vj9hrhb9qjp6jfvw0d1qc31lbb103xzxscr0yms0asv4sl4p";
  };

  fastcdr = rosPrev.fastcdr.overrideAttrs(old: {
    postFixup = ''
      touch $out/share/$name/local_setup.{sh,bash}
    '';
  });

  fastrtps = rosPrev.fastrtps.overrideColconAttrs(old: {
    postPatch = ''
      # Use the ROS2-supplied TinyXML2 CMake module, and replace the bundled Asio find module
      # with just directly injecting the include path (it's a header-only lib).
      substituteInPlace CMakeLists.txt \
        --replace 'eprosima_find_thirdparty(TinyXML2 tinyxml2)' \
        'find_package(tinyxml2_vendor REQUIRED)
         find_package(TinyXML2 REQUIRED)' \
        --replace 'eprosima_find_thirdparty(Asio asio VERSION 1.10.8)' \
        'set(Asio_INCLUDE_DIR "${pkgs.asio}/include")'
    '';

    postFixup = ''
      touch $out/share/$name/local_setup.{sh,bash}
    '';

    colconBuildDepends = old.colconBuildDepends ++ [
      rosFinal.tinyxml2_vendor
    ];
  });
}
