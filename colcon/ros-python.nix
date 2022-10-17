{ lib, buildPythonPackage, colcon-core, colcon-ros, fetchFromClearpathGitLab }:

buildPythonPackage {
  pname = "colcon-ros-python";
  version = "0.1.0";

  src = fetchFromClearpathGitLab {
    owner = "mpurvis";
    repo = "colcon-ros-python";
    rev = "a8332f6afb90fa8167768e12d6565a86b6758a75";
    hash = "sha256-5pfv6xzEeAEV9rtHHAbItgq4UwN6B6ELgZq63TYFeo0=";
  };

  propagatedBuildInputs = [ colcon-core colcon-ros ];

  doCheck = false;
}
