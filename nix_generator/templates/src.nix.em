{ pkgSrc, @(fetcher) }:
let
  pkg = pkgSrc (@(fetcher) {
    owner = "@(owner)";
    repo = "@(repo)";
    rev = "@(rev)";
    hash = "@(hash)";
    name = "@(safe_owner)-@(safe_repo)-@(safe_rev)";
  });
in
{
@[for p in packages]@
  @(p['name']) = pkg "@(p['metadata']['narhash'])" "@(p['path'])";
@[end for]@
}
