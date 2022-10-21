{ stdenvNoCC
  , python3
  , pkgs
  , makeWrapper
  , writeTextFile
  , bundleRelease
  , flake-metadata ? {}
}:
let
  # Export all package names, such that we can list packages in the help, or complain or something... 
  # Just sounds like a neat feature.
  flake-metadata-file = writeTextFile {
    name = "flake-metadata";
    text = builtins.toJSON {
      overlay_targets = {
        packages = {
          ros = builtins.attrNames pkgs.ros;
          ros2 = builtins.attrNames pkgs.ros2;
        };
        repositories = {
          ros = builtins.attrNames pkgs.ros.by_repo;
          ros2 = builtins.attrNames pkgs.ros2.by_repo;
        };
      };
      # This is not the refs thing... but perhaps it works?
      flake-metadata = flake-metadata;
    };
  };
in
stdenvNoCC.mkDerivation rec {
  pname = "flake-overlay-generator";
  version = "0.0.0";

  src = ".";

  nativeBuildInputs = [ makeWrapper ];
  phases = [ "installPhase" "fixupPhase" ];

  # Install by copying the files.
  installPhase = ''
    mkdir -p $out/bin/
    cp -r ${./flake.nix.em} $out/bin/flake.nix.em
    cp -r ${flake-metadata-file} $out/bin/flake-metadata.json
    cp -r ${./flake-overlay-generator} $out/bin/flake-overlay-generator
  '';

  # Wrap the binary with PYTHONPATH to ensure empy ends up as a runtime dependency.
  preFixup = ''
     wrapProgram $out/bin/flake-overlay-generator   --set PYTHONPATH ${pkgs.python3Packages.empy}/lib/python3.9/site-packages
  '';

  passthru = {
    inherit flake-metadata-file;
  };

}
