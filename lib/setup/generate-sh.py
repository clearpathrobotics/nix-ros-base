from pathlib import Path
from sys import argv
from local_setup_util_sh import get_commands, add_package_runtime_dependencies, order_packages

colcon_dir = 'share/colcon-core/packages'

# We only want the sh environment for build purposes, since the bash one is just
# completions that don't work properly in the restricted environment anyway.
shells = ['sh', None]

pkg_paths = {}
pkg_deps = {}

for pkg_path in set(argv[1:]):
    pkg_name = pkg_path.split('-', maxsplit=1)[-1]
    if pkg_name not in pkg_paths:
        # Add this package to the environment.
        pkg_paths[pkg_name] = pkg_path
        colcon_deps_path = Path(pkg_path) / colcon_dir / pkg_name
        if colcon_deps_path.is_file():
            add_package_runtime_dependencies(colcon_deps_path, pkg_deps)

# Filter unknown deps.
pkg_names = set(pkg_deps.keys())
for deps in pkg_deps.values():
    deps.intersection_update(pkg_names)

# Dump to stdout.
for pkg_name in order_packages(pkg_deps):
	lines = get_commands(pkg_name, pkg_paths[pkg_name], *shells)
	for line in lines:
		print(line)
