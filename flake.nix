{
  inputs = {
    # Main nixpkgs/NixOS package repository, containing most deps.
    # Temporarily locked for https://github.com/NixOS/nixpkgs/pull/198938
    nixpkgs.url = "github:nixos/nixpkgs/6739decba354";

    # This is Ben Wolsieffer's repo, containing definitions for Gazebo,
    # catkin-pkg, colcon, and numerous other low-level ROS dependencies.
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay";

    # This utility repo supplies the eachSystem functio
    flake-utils.url = "github:numtide/flake-utils";

    # Command line wrapper for GPU access.
    nixgl.url = "github:guibou/nixGL";

    # Easy bundling of our Poetry-based generator and API client for Nix.
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-ros-overlay, flake-utils, nixgl, poetry2nix }:
  let
    overlays = [
      nix-ros-overlay.overlays.default
      nixgl.overlay
      (import ./lib)
      (import ./flags)
      (import ./pkgs)
      (import ./overrides)
      (import ./colcon)
    ];

    defaultRosSystem = "x86_64-linux";

    mkPoetryApplication = (import nixpkgs {
      system = defaultRosSystem;
      overlays = [ poetry2nix.overlay ];
    }).poetry2nix.mkPoetryApplication;

  in
  {
    # Pass through nixpkgs, so that it's this flake's lock controlling
    # which version of it we are on for a given snapshot.
    inherit nixpkgs;

    # Wrap this helper function so that we can specify our supported systems
    # here rather than in the generated flake. We must specify them exactly
    # or else Hydra tries to build for aarch64 and so on, and we get errors
    # for packages like CUDA that aren't available there.
    eachRosSystem = flake-utils.lib.eachSystem [ defaultRosSystem ];
    makeRosPackages = { system, base-overlays, extra-overlays ? [], top-level-metadata ? null }: (import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = base-overlays ++ overlays ++
          [
            # Super hacky here, we inject 'flake-metadata' in packages, such that our flake-overlay can consume it
            # even though it is set from the flake.
            (if top-level-metadata != null  then (final: prev: rec {
              flake-metadata = top-level-metadata;
            }) else (final: prev: {}))
          ] ++ extra-overlays;
      });

    generate = (mkPoetryApplication {
      projectDir = ./.;
    }).overrideAttrs(_: {
      # Setting this name equal to the executable allows `nix run` usage.
      pname = "generate";
    });

    # These overlays must come after the generated ones from the snapshot
    # flake, since this contains overrides which are applied on top.
    overlays = overlays;

    # Pass through the list of CI jobs we want so that we don't have
    # to hard code that in the generator's template.
    ciPackages = packages: [
      { name = "noetic"; path = packages.noetic.ros_base.ws.contents; }
      { name = "rolling"; path = packages.rolling.ros_base.ws.contents; }
    ];
  };
}
