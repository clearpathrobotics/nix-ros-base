# This solution is a bit a hack; the result of some frustrating shortcomings in both
# Nix and also GitLab. See SES-2450 for details.
#
# Basically the deal is we do a fetchzip with two URLs. The first is the normal URL
# which goes direct to GitLab, and the second is for an on-host reverse proxy which
# goes through to GitLab, but inserts the header with a personal access token. So this
# should transparently work for most local users (accessing GitLab directly), but the
# Hydra machine (running the nginx reverse proxy) has an escape hatch to access the
# private source repositories.
{ lib, fetchzip }:

{ owner,
  group ? null,
  repo,
  rev,
  hash,
  name ? "source",
  domain ? "gitlab.clearpathrobotics.com",
  alt_domain ? "localhost:8001",
  protocol ? "https" }:

let
  # See: https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/fetchgitlab/default.nix
  slug = lib.concatStringsSep "/" ((lib.optional (group != null) group) ++ [ owner repo ]);
  escapedSlug = lib.replaceStrings [ "." "/" ] [ "%2E" "%2F" ] slug;
  escapedRev = lib.replaceStrings [ "+" "%" "/" ] [ "%2B" "%25" "%2F" ] rev;
  location = "api/v4/projects/${escapedSlug}/repository/archive.tar.gz?sha=${escapedRev}";

  gitlab_url = "${protocol}://${domain}/${location}";
  alt_url = "http://${alt_domain}/${location}";

in
  fetchzip {
    urls = [ gitlab_url alt_url ];
    inherit name hash;
  }
