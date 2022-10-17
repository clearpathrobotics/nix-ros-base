{ lib }:

with lib;

let
  fn = packages: let
    validPackages = filter (d: d != null) packages;
    propagatedColconRunDepends = unique (concatLists (
      catAttrs "colconRunDepends" validPackages
    ));
    recurse = fn propagatedColconRunDepends;
  in
    if length validPackages > 0 then
      unique (recurse ++ validPackages)
    else
      [];

in fn
