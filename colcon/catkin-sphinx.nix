{ buildPythonPackage, docutils, fetchFromGitHub }:

buildPythonPackage {
  pname = "catkin-sphinx";
  version = "0.3.1";

  # Rev pending: https://github.com/ros-infrastructure/catkin-sphinx/pull/12
  src = fetchFromGitHub {
    owner = "ros-infrastructure";
    repo = "catkin-sphinx";
    rev = "586efc713228236b5b399e00b2cd9dbeb8156a9e";
    hash = "sha256-R/D6fW2h+Fp2XHW6qix07HSN6bqopGYcwVFYzYMHtZg=";
  };

  propagatedBuildInputs = [
    docutils
  ];

  doCheck = false;
}
