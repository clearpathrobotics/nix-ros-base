{ lib, buildPythonPackage, colcon-core, notify2, fetchFromGitHub }:

buildPythonPackage rec {
  pname = "colcon-notification";
  version = "0.2.13";

  src = fetchFromGitHub {
    owner = "colcon";
    repo = pname;
    rev = version;
    hash = "sha256-Fm5YWCyEns0T94FPfpDvYllKKs4i2XpRpa4Auf5Su04=";
  };

  propagatedBuildInputs = [ colcon-core notify2 ];

  doCheck = false;
}
