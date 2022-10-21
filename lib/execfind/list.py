# This small Python program exists to help find executables in a built colcon
# package which require wrapping. Normally Nix culture would be to implement
# this kind of thing right in bash, but my head was spinning tryint to get it
# right; this is simple and explicit (and no, not perl).

from itertools import chain
from pathlib import Path
import stat
import sys

out_path = Path(sys.argv[1])
package_name = sys.argv[2]
exclusion_globs = sys.argv[3:]

search_paths = [
    out_path / "bin",
    out_path / "lib" / package_name,
    out_path / "share" / package_name,
]

for f in chain(*[p.glob("**/*") for p in search_paths]):
    if not f.is_file():
        # Not a file.
        continue

    if not f.stat().st_mode & stat.S_IXUSR:
        # Not executable.
        continue

    if any(f.match(x) for x in exclusion_globs):
        # Manually excluded.
        continue

    print(f)
