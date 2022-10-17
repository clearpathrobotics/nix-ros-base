# These arguments filled automatically when the file is imported with callPackage.
{
  catkinTestData,
  colconHomeTest,
  fetchurl,
  lib,
  makeColconHook,
  quietSymlinkJoin,
  stdenv,
  zstd
}:

# Passed manually when the function is called in buildColconPackage.
pkgFinal:

let
  name = pkgFinal.name;
  
  # https://gitlab.clearpathrobotics.com/tools/catkin_tools_merge/-/blob/72bfbeaee51bcc8ed05a9ac50f336e4163a2f31c/catkin_tools_merge/cli.py#L110-123
  makeUnpackPhase = unpack_target: ''
    #set -x
    # Unpack the old build directory, including the source directory
    export OLD_BUILD_TOP=$(cat ${unpack_target}/build_pwd.txt)
    tar -xf ${unpack_target}/build.tar.zst
    if [[ "$NIX_BUILD_TOP" != "$OLD_BUILD_TOP" ]]; then
      echo "$NIX_BUILD_TOP is not $OLD_BUILD_TOP patching up the paths."
      while IFS= read -r -d $'\0' f; do
        #echo fixing $f
        export OLD_BUILD_DATE=$(date -R -r $f)
        sed -i -E -e "s|$OLD_BUILD_TOP/source|$NIX_BUILD_TOP/source|g" $f
        sed -i -E -e "s|$OLD_BUILD_TOP/build|$NIX_BUILD_TOP/build|g" $f
        sed -i -E -e "s|$OLD_BUILD_TOP/install|$NIX_BUILD_TOP/install|g" $f
        touch -d "$OLD_BUILD_DATE" $f
      done < <(find $NIX_BUILD_TOP -type f \( -regex ".*\.txt$" -or -regex ".*\.sh$" -or -regex ".*\.pc$" -or -regex ".*\.pc\.py$" -or -regex ".*_setup_util\.py$" -or -regex ".*\.cmake$"  -or -regex ".*Makefile2?$"  -or -regex ".*\.make$"  -or -regex ".*\.rosinstall$"  -or -regex ".*\.d$" -or -regex ".*generate_cached_setup\.py$" -or -regex ".*\.sh\.env$" -or -regex ".*\.ini$" \) -print0)
    fi
  '';

in {
  testCompile = if pkgFinal.testDisableCompile then
    stdenv.mkDerivation rec {
      pname = "${name}-test-compile";
      version = "0.0.1";
      phases = [ "buildPhase" ];
      buildPhase = ''
        mkdir -p $out/test_state/${name}
        echo "nocompile" > $out/test_state/${name}/test_state.txt
      '';
      passthru = {
        original_name = "${name}";
      };
    }
  else let 
      # When we build the tests, we also want to do the ifd to grab the test assets
      # Create a nix file that contains all the downloads.
      tmp_list_of_downloads = catkinTestData {
        name = "${name}-test-data";
        path = pkgFinal.src;
      };
      # Import the defaults.nix file that the catkinTestData wrote.
      list_of_downloads = (import tmp_list_of_downloads);
      # Now, all that remains is to grab these downloads, patch up the CMakeLists.
      # Convert the list_of_downloads into a string of replacements for the CMakeLists.
      # Grab the files themselves.
      files = map (to_download: let 
        file = fetchurl ({
                  outputHashAlgo = "md5";
                  name="test-artifact-${to_download.name_valid}";
                  url = to_download.url;
                  outputHash = to_download.outputHash;
                });
        in stdenv.mkDerivation rec {
          name = "test-artifact-${to_download.name}";
          phases = ["buildPhase"];
          buildPhase = ''
            mkdir -p $out/
            ln -s ${file} $out/${to_download.name}
          '';
          passthru = {
            inherit (to_download) url name;
          };
      }) list_of_downloads;
      list_of_replacements = toString (map (x: "--replace ${x.url} file://${x}/${x.name}"  ) files);

      # Ros2 colcon packages use xmllint to lint the package.xml file using the xsd.
      # The xsd file can't be retrieved in the unit test container, so we have to pull this into the nix store
      # before we run the unit tests.
      package_xsd2_url = "http://download.ros.org/schema/package_format2.xsd";
      package_xsd2 = fetchurl({
        name = "package-format-2-xsd";
        url = package_xsd2_url;
        hash = "sha256-pzKK8IWbPxWuTwSRLYRqWO3GZk2x5pr/BhsilAwZQwQ=";
      });
      package_xsd3_url = "http://download.ros.org/schema/package_format3.xsd";
      package_xsd3 = fetchurl({
        name = "package-format-3-xsd";
        url = package_xsd3_url;
        hash = "sha256-WFIBgJy/jIHsWk19hNgn9Gdt1ipLwKgS2npIXeoq1Do=";
      });

  in stdenv.mkDerivation ({
    outputs = ["out"];

    phases = [ "unpackPhase" "patchPhase" "buildPhase" "fixupPhase" ];

    inherit (pkgFinal) nativeBuildInputs;
    buildInputs = pkgFinal.buildInputs ++ pkgFinal.nonColconRecursiveTestDepends;

    # Switch colcon home to use the test home dir, this ensures the tests get build.
    # SES-3264
    # We also add env vars to ensure package_xsd3 propagates, somehow package_xsd2 doesn't have any issues propagating
    # but package_xsd3 doesn't seem to propagate to the cpr_api_adaptor unit tests.
    # This export should be removed, at which point `nix build clearpath/2.28.0-20221006142341-CORE-23104-0#ros2.cpr_api_adaptor.test`
    # can be used to test, if the propagation is not working you'll see the xmllint test fail on;
    # ```
    # warning: failed to load external entity "file:///nix/store/752i3i7yqzr0zdd9k95hna37n26bgvmz-package-format-3-xsd"
    # Schemas parser error : Failed to locate the main schema resource at 'file:///nix/store/752i3i7yqzr0zdd9k95hna37n26bgvmz-package-format-3-xsd'.
    # WXS schema file:///nix/store/752i3i7yqzr0zdd9k95hna37n26bgvmz-package-format-3-xsd failed to compile
    # ```
    postHook = (makeColconHook pkgFinal.colconRecursiveTestDepends) + ''
      export COLCON_HOME=${colconHomeTest}
      export HACK_SES_3264_PROPAGATE_CHEAT_XSD3=${package_xsd3}
      export HACK_SES_3264_PROPAGATE_CHEAT_XSD2=${package_xsd2}
    '';

    name = "${name}-testCompile";

    passthru = {
      inherit list_of_downloads list_of_replacements files;
      original_name = "${name}";
    };

    # Replace in all CMakeLists.txt files, this is a bit spammy
    # if substitutions aren't present in the file handed in, but that should be rare.
    postPatch = ''
      while IFS= read -r -d $'\0' f; do
        substituteInPlace $f ${list_of_replacements}
      done < <(find . -type f -name CMakeLists.txt -print0)
      while IFS= read -r -d $'\0' f; do
        substituteInPlace $f --replace "${package_xsd2_url}" "file://${package_xsd2}" --replace "${package_xsd3_url}" "file://${package_xsd3}" 2> /dev/null
      done < <(find . -type f -name package.xml -print0)
    '';

    # https://gitlab.clearpathrobotics.com/tools/catkin_tools_merge/-/blob/72bfbeaee51bcc8ed05a9ac50f336e4163a2f31c/catkin_tools_merge/cli.py#L110-123
    unpackPhase = makeUnpackPhase pkgFinal.build;

    colconBuildArgs = [
      "--paths $sourceRoot"
      "--install-base ./install/"
      "--merge-install"
    ];

    buildPhase = ''
      runHook preBuild

      cd $NIX_BUILD_TOP

      # Construct the colcon commandline.
      colconArgs=$(eval echo "$colconPreVerbArgs build $colconBuildArgs ")
      colcon $colconArgs

      mkdir $out
      tar -acf $out/build.tar.zst *
      pwd > $out/build_pwd.txt
    '';
  } );

  # For testing this, test_rostest is an excellent trivial nosetest package high in the tree.
  # test_rosbag contains test bags that are downloaded, but unit test execution takes like 8 mins.
  # svg_draw_tool is an independent C++ package, only depends on boost and catkin, gtest unit tests as well as
  # artifacts in ./publish/
  # The rosconsole package is high up the dependency tree and prints times into the output.
  test = if (pkgFinal.testDisableRun || pkgFinal.testDisableCompile) then
    stdenv.mkDerivation rec {
      pname = "${name}-test-run";
      version = "0.0.1";
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/test_state/${name}
        echo "disabled" > $out/test_state/${name}/test_state.txt
      '';
      dont_symlink = true;
      passthru = {
        original_name = "${name}";
      };
    }
    #{dont_symlink = true;original_name="${name}";}
  else stdenv.mkDerivation ({
    outputs = ["out"];

    inherit (pkgFinal.testCompile) nativeBuildInputs buildInputs postHook;

    separateDebugInfo = false;
    phases = [ "unpackPhase" "buildPhase" "fixupPhase" ];

    # Check that there's no runtime dependencies save for references to ourself.
    allowedReferences = [ "out" ];

    name = "${name}-test";

    passthru = {
      # Also keep the original name around for the workspace symlink.
      original_name = "${name}";
    };

    unpackPhase = makeUnpackPhase pkgFinal.testCompile;

    colconBuildArgs = [
      "--paths $sourceRoot"
      "--install-base ./install/"
      "--merge-install"
    ];

    buildPhase = ''
      runHook preBuild

      # Ros needs a homedir to write log files.
      export HOME=$NIX_BUILD_TOP/administrator/
      mkdir -p $HOME/.ros/

      # Set the ros ip, this avoids spam from:
      # [ERROR] [1652991572.682431664]: Couldn't find a preferred IP via the getifaddrs() call;
      # I'm assuming that your IP address is 127.0.0.1.  This should work for local processes, but will almost 
      # certainly not work if you have remote processes.Report to the ROS development team to seek a fix
      export ROS_IP=127.0.0.1

      cd $NIX_BUILD_TOP

      # Disable halting on failure, tests should always succeed.
      set +e

      # Create the colcon command line and run the tests.
      colconArgs=$(eval echo "$colconPreVerbArgs test  --test-result-base $out/test_results/  $colconBuildArgs ")
      colcon $colconArgs

      # Create the results summary, and also put this into a txt file.
      mkdir -p $out/test_results/
      colconArgs=$(eval echo "$colconPreVerbArgs test-result --test-result-base $out/test_results/ --all --verbose ")
      colcon $colconArgs | tee -a $out/test_results/summary.txt

      # Try not to cause printing after this line, this way the log ends with the test summary.

      # Finally copy the .ros folder to the output.
      cp -r $HOME/.ros/ $out/home_ros/
      # Copy just the log folder
      cp -r log $out/

      # Copy the publish folders to the output, should be only one, but might as well tackle multiple test directories
      # or something.
      while IFS= read -r -d $'\0' f; do
        mkdir -p $out/$(echo $f | cut -d'/' -f2-)
        cp -r $f/* $out/$(echo $f | cut -d'/' -f2-)
      done < <(find . -type d -name publish -print0)
    '';

    # Sanitize the output by converting all nix store hashes to uppercase, this invalidates the search, but still
    # allows us humans to inspect exactly what we matched. We run this as a fixup in case unit tests install things.
    fixupPhase = ''
      find $out/ -type f -print0 | xargs -0 sed -i -E -e 's|/nix/store/[a-z0-9]{32}|\U&|g'
    '';
  } );
}
