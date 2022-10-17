{ lib, buildPythonPackage, colcon-core, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-parallel-executor";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "colcon";
    repo = pname;
    rev = version;
    hash = "sha256-cfmoyyQnlyhlu6ee0GZ7H/Sy56YOBa0lv52pcY5rvZA=";
  };

  propagatedBuildInputs = [ colcon-core ];

  doCheck = false;
}
