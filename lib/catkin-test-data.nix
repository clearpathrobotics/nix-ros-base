{ lib, runCommand, stdenv, fetchurl, python3 }:
args_@{
  name
   , path
   , preferLocalBuild ? true
   , allowSubstitutes ? false
   , postBuild ? ""
   , ...
 }:
let
args = removeAttrs args_ [ "name" "postBuild" ]
  // {
    inherit preferLocalBuild allowSubstitutes;
    passAsFile = [ "path" ];
  }; # pass the defaults
in runCommand name args
''
  mkdir -p $out
  ${python3}/bin/python3 ${./catkin-test-data.py}  $(cat $pathPath)/ $out/
''
