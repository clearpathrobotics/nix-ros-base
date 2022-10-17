{
  inputs = {
    workspace.url = "@(backing_bundle)";

    # Hack pending: https://github.com/NixOS/nix/issues/3602
    base.url = "clearpath-base/e96923583baa58b4ffaaf931ab00ba37d0c0c192";
  };

  outputs = { self, workspace, base}:
    with workspace; eachClearpathSystem (system: rec {
      packages = makeClearpathPackages {
        inherit system base-overlays;
        extra-overlays = [
          (final: prev: rec {
            custom = with final; colconWorkspace {
              name = "custom";
              colconPackages =  [
                # Ros packages for your workspace go here, like ros.move_base, or ros2.cpr_api_adaptor.
                # Entire repositories can be added with ros.by_repo.cpr_navigation or ros2.by_repo.<repo_name>.
                @(packages)
              ];
              includeBuildDepends = true;
            };
          })
        ];
      };
      defaultPackage = packages.custom;
      hydraJobs = {@(hydra_workspace_target) = packages.custom.@(hydra_workspace_target);};
    }) // {
      # These are 'global' passhthroughs, outside of the system architectures.
      inherit refs;
    };
}
