{ buildPythonPackage, fetchurl, appdirs, astor, attrs, cachecontrol, docutils, lockfile, requests, twisted }:

buildPythonPackage {
  pname = "pydoctor";
  version = "21.12.1";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/ee/00/cdb4be2c6364f123e3d007ac827eaa9dcff145a07c18ac6c511d27ddd1a2/pydoctor-21.12.1-py3-none-any.whl";
    sha256 = "1rvdcc79jrdi9a7v9l0zsygzb19cm38rmmq2bxvflky258fsiq6y";
  };
  format = "wheel";

  propagatedBuildInputs = [
    appdirs
    astor
    attrs
    cachecontrol
    docutils
    lockfile
    requests
    twisted
  ];

  doCheck = false;
}
