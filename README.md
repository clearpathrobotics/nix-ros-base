# nix-base

This repository supplies the base Nix content which underpins the generated
package definitions available in [`nix-ros`][nixros]. Included here are
overrides and patches for various upstream packages, new dependencies which
aren't packaged upstream, plus the bits of plumbing needed to make package
and workspace building function.

The included `flake.nix` does not actually provide any buildable packages
as outputs— currently its outputs are exclusively intended to be consumed
by the generated snapshot flakes. However, the `flake.lock` in this repo
is critically important, as it controls which versions of our upstream
dependencies (nixpkgs, nix-ros-overlay) we are pinned to.


## Usage

Add the flake repositories to your nix installation with:
```
nix registry add ros github:clearpathrobotics/nix-ros
nix registry add ros-base github:clearpathrobotics/nix-ros-base
```

To avoid rebuilding everything, one can use the public cache for
[nix-ros][nix-ros-cachix] on cachix.

With those one-time steps done, we can now build a ros 'installation' that
holds the packages present in `ros_base` with:
```
nix build ros/latest#noetic.ros_base.ws.contents
```
A `result` symlink is now availabe to inspect a ros installation that has
everything in `ros_base`.

To use this installation we can enter a subshell that uses the binaries of
this installation with:
```
nix develop ros/latest#noestic.ros_base.ws
```

This also provides the tools and dependencies that were used to build this
package (or packages). The binaries from `ros_base` are available in this
subshell, so `rostopic` and other base tools are available. This step is
equivalent to sourcing a ros installation and after this step developer 
workspaces can be created to extend the base ROS installation.

## What's where

Some starting points to find your way around in this repository.

### lib
The [lib](./lib) directory contains the 'meat' of this repository. This
provides the main functionality necessary to build and use ROS through nix;

- `buildColconPackage` is a wrapper around `mkDerivation` that makes it more
convenient to build ros packages by providing an abstraction of the actual
`colcon` build. This function takes in various arguments, the main ones are
the `colconBuildDepends`, `colconRunDepends` and `colconRunDepends`. This
also provides various subtargets like running unit tests for a particular
package. The `.ws` subtarget creates a colcon workspace with just this package
in it.
- `buildColconWorkspace` provides a way to collect multiple packages into
a traditional workspace-like environment. In other words, this creates a
'ros installation' as a nix derivation. This workspace also has various
properties and subtargets for example to enter an environment with debug
symbols or run unit tests.

### nix_generator
The [nix_generator](./nix_generator) directory holds the Python files and
templates that are used to generate the nix files found in the main
[nix-ros][nixros] flake repository.

This directory also holds various tools that allow interacting with Hydra
through a commandline interface or Python class. This can, for example be
used to control Hydra from a different CI system like Jenkins or Gitlab CI.
Use this with `poetry install`, followed by `poetry run hydra`.

### colcon & flags

The [colcon](./colcon) directory holds various colcon plugins and the actual
closures that contain colcon and the correct plugins to be used for particular
tasks like building documentation, building packages or for use by developers.

The [flags](./flags) directory holds handling of compilation flags, this is
done by providing various colcon mixins. These mixins are then combined into
a single directory that can be used with a `COLCON_HOME` variable. These also
provide a default set of mixins to be used whener `colcon build` without any
arguments is invoked. This provides developers with sane defaults that are
exactly identical to what is used to build the package itself. Also provided
are mixins to compile with clang or ccache.

### overrides

Some packages may need extra overrides to ensure they build correctly, or
changes to the source code may be necessary to accomodate their use in Nix.


[nixros]: https://github.com/clearpathrobotics/nix-ros/
[nix-ros-cachix]: https://app.cachix.org/cache/nix-ros#pull
