{ lib, buildPythonPackage, colcon-core, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-bash";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "colcon";
    repo = pname;
    rev = version;
    hash = "sha256-2Nx604iUJSg8iLYQzcOxpX8w0GR1Km1ye/uX6SOC3Zg=";
  };

  propagatedBuildInputs = [ colcon-core ];

  doCheck = false;
}
