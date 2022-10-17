{ lib, buildPythonPackage, colcon-core, pyyaml, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-defaults";
  version = "0.2.5";

  src = fetchFromGitHub {
    owner = "colcon";
    repo = pname;
    rev = version;
    hash = "sha256-WB6p3zW1j/Pw/PSa+bByGqGwxvT0eAIQ3Cvo3LUIgpA=";
  };

  propagatedBuildInputs = [ colcon-core pyyaml ];

  doCheck = false;
}
