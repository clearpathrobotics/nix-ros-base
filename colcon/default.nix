# A dedicated overlay for colcon and friends.
final: prev: {
  # Define the colcon environment to include additional extensions.
  colcon = with final.python3.pkgs; colcon-core.withExtensions [
    colcon-bash
    colcon-cmake
    colcon-core
    colcon-defaults
    # colcon-document
    colcon-library-path
    colcon-metadata
    colcon-mixin
    colcon-notification
    colcon-output
    colcon-package-selection
    colcon-parallel-executor
    colcon-python-setup-py
    colcon-recursive-crawl
    colcon-ros
    colcon-test-result
  ];

  # Mini-colcon that contains just the plugins needed for one at a time building
  # of packages in the Nix context.
  colconMinimal = with final.python3.pkgs; colcon-core.withExtensions [
    colcon-bash
    colcon-cmake
    colcon-core
    colcon-defaults
    colcon-metadata
    colcon-mixin
    colcon-python-setup-py
    colcon-ros
  ];

  colconMinimalDocs = with final.python3.pkgs; colcon-core.withExtensions [
    colcon-core
    # colcon-document
    colcon-recursive-crawl
  ];

  # Composable Python3 override to add additional extensions.
  python3 = final.lib.fix (py:
    prev.python3.override (old: {
      self = prev.python3;
      packageOverrides = final.lib.composeExtensions old.packageOverrides
        (pyFinal: pyPrev: {
          # Colcon extensions not (yet) packaged in nix-ros-overlay.
          colcon-bash = pyFinal.callPackage ./bash.nix {};
          colcon-defaults = pyFinal.callPackage ./defaults.nix {};
          colcon-mixin = pyFinal.callPackage ./mixin.nix {};
          colcon-notification = pyFinal.callPackage ./notification.nix {};
          colcon-output = pyFinal.callPackage ./output.nix {};
          colcon-parallel-executor = pyFinal.callPackage ./parallel-executor.nix {};
          # Patch colcon-ros to not warn about missing local_setup.sh files, since we delete
          # them from the individual package workspaces.
          colcon-ros = pyPrev.colcon-ros.overrideAttrs(_: {
            patches = [
              (final.fetchpatch {
                url = "https://github.com/colcon/colcon-ros/commit/7213a0431069bfe0e2f76c7237af60dd16982b15.patch";
                sha256 = "sha256-HozzErN19W5yKtG1khAbQx0QNm5xbCkLvYGmcBZsonE=";
              })
            ];
          });

          # Dependencies related to docs generation.
          catkin-sphinx = pyFinal.callPackage ./catkin-sphinx.nix {};
          pydoctor = pyFinal.callPackage ./pydoctor.nix {};

          # Clearpath-developed colcon extensions.
          # colcon-document = pyFinal.callPackage ./document.nix {};
        });
      }
    )
  );

  colconForDevelopment = let
    colcon-defaults-with-changes = final.python3.pkgs.colcon-defaults.overrideAttrs(_: {
      src = final.fetchFromGitHub {
        owner = "clearpathrobotics";
        repo = "colcon-defaults";
        rev = "9e0c5c2c585e5eb1c5e43adf9d26e3df9deaa7a0";
        hash = "sha256-2xfeVrN+SL8jt0/xgRvD7JBJNXjKIKvHDr/otu3JI7E=";
      };
    });
    colcon-mixin-with-changes = final.python3.pkgs.colcon-mixin.overrideAttrs(_: {
      src = final.fetchFromGitHub {
        owner = "clearpathrobotics";
        repo = "colcon-mixin";
        rev = "3cd0c6bc79fe8c1dceb46aaf9840ec9d1996f4ca";
        hash = "sha256-LrvA5UZN4wPuHe8mhsR8JVIfK7nZSVF2gnkibOrNfxo=";
      };
    });
  in with final.python3.pkgs; colcon-core.withExtensions [
    colcon-bash
    colcon-cmake
    colcon-core
    colcon-defaults-with-changes
    # colcon-document
    colcon-library-path
    colcon-metadata
    colcon-mixin-with-changes
    colcon-notification
    colcon-output
    colcon-package-selection
    colcon-parallel-executor
    colcon-python-setup-py
    colcon-recursive-crawl
    colcon-ros
    colcon-test-result
  ];


}
