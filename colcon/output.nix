{ lib, buildPythonPackage, colcon-core, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-output";
  version = "0.2.12";

  src = fetchFromGitHub {
    owner = "colcon";
    repo = pname;
    rev = version;
    hash = "sha256-qtz1DFsPuDWl3Q41SCmzX4RoPp/Vr3QXHrUg2Zo7JIY=";
  };

  propagatedBuildInputs = [ colcon-core ];

  doCheck = false;
}
