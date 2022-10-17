{ lib, buildPythonPackage, catkin-pkg, catkin-sphinx, colcon-core, colcon-recursive-crawl, colcon-ros, doxygen, fetchFromClearpathGitLab, pydoctor, sphinx, pyyaml}:

buildPythonPackage rec {
  pname = "colcon-document";
  version = "0.0.0";

  src = fetchFromClearpathGitLab {
     owner = "tools";
     repo = "colcon-document";
     rev = "63a064b139accb12d0080ad3d7fd772d44898889";
     hash = "sha256-lI2XoJ20RuFvQ0gxXuk5KNZP5f8VKVnHvfCzLTw3a44=";
  };

  # Must patch in the paths to these executables since we need them at runtime and since
  # colcon-document is a plugin we don't have the ability to wrap the executable and inject
  # these bin locations to the PATH.
  postPatch = ''
    substituteInPlace colcon_document/verb/executables.py \
        --replace "_which_executable('DOXYGEN_COMMAND', 'doxygen')" '"${doxygen}/bin/doxygen"' \
        --replace "_which_executable('EPYDOC_COMMAND', 'pydoctor')" '"${pydoctor}/bin/pydoctor"' \
        --replace "_which_executable('SPHINX_COMMAND', 'sphinx-build')" '"${sphinx}/bin/sphinx-build"'
   '';

  propagatedBuildInputs = [ catkin-pkg catkin-sphinx colcon-core colcon-recursive-crawl colcon-ros pyyaml ];

  nativeBuildInputs = [ catkin-sphinx ];

  doCheck = false;
}
