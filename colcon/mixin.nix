{ lib, buildPythonPackage, colcon-core, pyyaml, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-mixin";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "clearpathrobotics";
    repo = pname;
    rev = "7c0ead65e82e050b0a1f0c52fde0d9ce1e9eb5f2";
    hash = "sha256-WEh+9UV3S2DHWOMTfQaYe7H9jgbX9M7mqGOXxISoKXg=";
  };

  propagatedBuildInputs = [ colcon-core pyyaml ];

  doCheck = false;
}
