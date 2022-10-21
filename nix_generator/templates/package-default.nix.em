final: prev:

let
  srcs = prev.callPackage ./srcs {};
  @(scope_name)Scope = extra: prev.lib.callPackageWith (final // extra);

in {
  # A static file containing the snapshot version.
  bundleRelease = ../release;

  # Dedicated scope for all ROS packages. We provide a callPackage here
  # that passes through the srcs dict from above so that we don't have to
  # do it individually on each line.
  @(scope_name) = final.lib.makeScope @(scope_name)Scope (scopePrev:
    let
      callPackage = f: scopePrev.callPackage f {
        inherit final srcs;
      };
      packages = {
@[for package_name in package_names]@
        @(package_name) = callPackage ./@(package_name).nix;
@[end for]@
      };

      final_packages = lst: map (package: package.pkgFinal) lst;
      list_packages_by_repo = sources: (builtins.filter (package: (builtins.elem package.src (builtins.attrValues sources))) (builtins.attrValues packages));
      by_repo = builtins.listToAttrs (map (repo_name : {name=repo_name; value=(final_packages (list_packages_by_repo srcs.${repo_name}));})  (builtins.attrNames srcs));

    in {
      inherit callPackage srcs by_repo;

    } // packages
  );
}
