# These arguments filled automatically when the file is imported with callPackage.
{
  colconMinimalDocs,
  fontconfig,
  graphviz,
  lib,
  makeColconHook,
  propagateColconRunDepends,
  stdenv
}:

# Passed manually when the function is called in buildColconPackage.
pkgFinal:

with lib; let
  # The doc build of a package requires the package's runtime environment, plus access to the doc
  # outputs of all build dependencies (for the purposes of doxygen tags and intersphinx).
  colconRecursiveBuildDependsDocs = map (d: d.docs) pkgFinal.colconRecursiveBuildDepends;
  recursiveDocDepends = propagateColconRunDepends [ pkgFinal ];
  partitionedDocDepends = partition (d: d.colconPackage or false) recursiveDocDepends;
  colconRecursiveDocDepends = partitionedDocDepends.right;
  nonColconRecursiveDocDepends = partitionedDocDepends.wrong;

in stdenv.mkDerivation {
  name = "${pkgFinal.name}-docs";
  src = pkgFinal.src;

  nativeBuildInputs = [
    colconMinimalDocs
    fontconfig
    graphviz
  ];

  buildInputs = nonColconRecursiveDocDepends;

  phases = [ "unpackPhase" "patchPhase" "buildPhase" "fixupPhase" ];
  postHook = makeColconHook colconRecursiveDocDepends;

  colconDocumentArgs = [
    "--docs-base $out"
  ];

  COLCON_DOCUMENT_PATH = lib.makeSearchPath "/" colconRecursiveBuildDependsDocs;

  # Sandboxed builds don't have access to /etc or /home, so without this config we get a spew of warnings.
  FONTCONFIG_FILE="${fontconfig.out}/etc/fonts/fonts.conf";
  FONTCONFIG_PATH="${fontconfig.out}/etc/fonts/"; # default config directory
  XDG_CACHE_HOME = "/tmp/cache"; # creating a temp cache drectory for fontconfig

  buildPhase = ''
    colconArgs=$(eval echo "document $colconDocumentArgs")
    colcon $colconArgs
    rm -f $out/COLCON_IGNORE
  '';

  # Replace any symlinks with the actual files, so we don't have broken links to the source.
  fixupPhase = ''
    for f in $(find $out -type l); do
      cp --remove-destination $(readlink -e $f) $f
    done
  '';
}
