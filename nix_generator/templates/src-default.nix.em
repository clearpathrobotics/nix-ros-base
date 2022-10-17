{ callPackages }:
{
@[for repo_name in repo_names]@
  @(repo_name.replace("/", "_")) = callPackages ./@(repo_name).nix {};
@[end for]@
}
