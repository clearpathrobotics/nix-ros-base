{
  python3,
  runCommand
}:

colconDepends:

let
  colconSetupSh = runCommand "colcon-setup.sh" {} ''
    ${python3}/bin/python3 ${./setup}/generate-sh.py ${toString colconDepends} > $out
  '';

in ''
  echo "sourcing environment in ${colconSetupSh}"
  set +u
  source ${colconSetupSh}
  export PKG_CONFIG_PATH_FOR_TARGET=$PKG_CONFIG_PATH:$PKG_CONFIG_PATH_FOR_TARGET
  set -u
''
