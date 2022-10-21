{
  dpkg,
  fetchurl,
  lib,
  runCommand
}:

{ url, ... }@args:

let
  debFile = fetchurl args;
  name = lib.last (lib.splitString "/" url);

in
  # I tried doing this in a single stage just using fetchurl's postFetch, but it gave me
  # grief about the hash not matching any more, so now the download and extract are
  # separate derivations, for better or worse.
  runCommand "${name}-contents" {} ''
    ${dpkg}/bin/dpkg --extract ${debFile} $out
  ''
