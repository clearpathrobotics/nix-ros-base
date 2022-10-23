# nix-ros-base

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

## Nix Installation

You can get Nix by the upstream-suggested `curl` install, by installing the
apt package on an OS new enough to support it, or by using the the container.

To use [the upstream-suggested installation][nix-install], run:
```
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Or, if you're on Ubuntu Jammy+, you can bootstrap Nix directly
from a distro package:
```
sudo apt install -y nix-setup-systemd

# Optional but recommended; allows nix usage without root. Must log out
# and in following this invocation:
sudo usermod -a -G nix-users $(whoami)
```

As a final alternative, you can pull and use the
[Nix container][nix-container] in docker or podman.

[nix-install]: https://nixos.org/download.html
[nix-container]: https://hub.docker.com/r/nixos/nix/

## Nix Configuration

Our work heavily leverages the upcoming [Flakes][nix-flakes] feature, so this
must be manually enabled in your Nix environment:
```
# Or to /etc/nix/nix.conf if you're running Nix as root.
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Add the repositories to your nix flake registry with:
```
nix registry add ros github:clearpathrobotics/nix-ros
nix registry add ros-base github:clearpathrobotics/nix-ros-base
```

And finally, we suggest [setting up Cachix][nix-ros-cachix] so that you can
pull pre-built binaries rather than building everything locally:
```
# Enter a temporary shell where cachix is available.
nix shell github:cachix/cachix
cachix use nix-ros
exit
```

[nix-flakes]: https://nixos.wiki/wiki/Flakes
[nix-ros-cachix]: https://app.cachix.org/cache/nix-ros#pull

## Usage

We can now build a ROS environment that holds the packages present in
`ros_base` with:
```
# ROS 2 "rolling" is also supported; switch to that if you prefer.
nix build ros#noetic.ros_base.ws.contents
```

You can also reference a specific flake tag snapshot if desired:
```
nix build ros/20221020-1#noetic.ros_base.ws.contents
```

A `result` symlink is now available to inspect a ros installation that has
everything in `ros_base`. This symlink ensures that Nix [garbage collection][gc]
will not remove these paths from the store.  

To use this installation we can enter a subshell that uses the binaries of
this installation with:
```
nix develop ros#noetic.ros_base.ws
```

This environment provides the tools and dependencies that were used to build
this package (or packages). The executables from `ros_base` are available in this
subshell, so `rostopic` and other base tools are available. This step is
equivalent to sourcing a ros installation and after this step developer 
workspaces can be created to extend the base ROS installation.

## Architecture

This demonstration uses the ROS package definitions from upstream rosdistro:

https://github.com/ros/rosdistro/

The Noetic and Rolling distributions are frozen and snapshotted daily by a
Github Action in our snapshots repo:

https://github.com/clearpathrobotics/rosdistro-snapshots

The snapshots are then cached by our colcon-distro instance, for example:

http://colcon-distro.ext.ottomotors.com/get/noetic/snapshot/20221020.json

The code for this caching layer is in these two repos:

- https://github.com/clearpathrobotics/colcon-distro
- https://github.com/clearpathrobotics/colcon-nix

The cache allows the generator in this repo to have access to package content
hashes without needing to download the source.

## Guide

Some starting points to find your way around in this repository.

### lib

The [lib](./lib) directory contains the 'meat' of this repository. This
provides the main functionality necessary to build and use ROS through nix;

- `buildColconPackage` is a wrapper around `mkDerivation` that makes it more
convenient to build ros packages by providing an abstraction of the actual
`colcon` build. This function takes in various arguments, the main ones are
the `colconBuildDepends`, `colconRunDepends` and `colconTestDepends`. This
also provides various subtargets like running unit tests for a particular
package. The `.ws` subtarget creates a colcon workspace with just this package
in it.
- `buildColconWorkspace` provides a way to collect multiple packages into
a traditional workspace-like environment. In other words, this creates a
'ros installation' as a nix derivation. This workspace also has various
properties and subtargets for example to enter an environment with debug
symbols or run unit tests.

### overrides

Some packages may need extra overrides to ensure they build correctly, or
changes to the source code may be necessary to accomodate their use in Nix.

If you wish to iterate on the overrides, it's easy to change or add additional
ones by modifying the files in that folder, and then re-running your build
with a Nix input override:
```
nix build ros/20221020-1#noetic.ros_base.ws.contents --override-input base /path/to/nix-ros-base
```

One obvious and common override when iterating on a package that fails to build
is to simply point the src attribute at a local source checkout:
```
  roscpp = rosPrev.roscpp.overrideColconAttrs (_: {
    src = /path/to/ros_comm/clients/roscpp
  });
```

And then build just that one package:
```
nix build ros/20221020-1#noetic.roscpp --override-input base /path/to/nix-ros-base --impure -L
```

The `--impure` flag is required so that this sandboxed build will be able to
"see" the whole filesystem, and `-L` makes the log spool visible without
having to inspect it afterward with `nix log`.

### nix_generator

The [nix_generator](./nix_generator) directory holds the Python files and
templates that are used to generate the nix files found in the main
[nix-ros][nixros] flake repository. You can iterate on the generator
and then run it locally with:
```
poetry install
poetry run generate -o /path/to/nix-ros
nix develop /path/to/nix-ros#noetic.ros_base.ws
```

This directory also holds various tools that allow interacting with Hydra
through a commandline interface or Python class. This can, for example be
used to control Hydra from a different CI system like Jenkins, Actions, or
GitLab CI. Use this with `poetry install`, followed by `poetry run hydra`.

### colcon & flags

The [colcon](./colcon) directory holds various colcon plugins and the actual
closures that contain colcon and the correct plugins to be used for particular
tasks like building documentation, building packages or for interactive use
by developers.

The [flags](./flags) directory holds handling of compilation flags, this is
done by providing various colcon mixins. These mixins are then combined into
a single directory that can be used with a `COLCON_HOME` variable. These also
provide a default set of mixins to be used whener `colcon build` without any
arguments is invoked. This provides developers with sane defaults that are
exactly identical to what is used to build the package itself. Also provided
are mixins to compile with clang or ccache.

## Disclaimer

We're delighted to collaborate long-term with other users of Nix and ROS, however
there's no commitment to support of the nix-ros and nix-ros-base repositories;
these were prepared specifically for a talk given at ROSCon 2022.

[nixros]: https://github.com/clearpathrobotics/nix-ros/
[gc]: https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-store-gc.html


## Credits

This work would not have been possible without @lopsided98's work on packaging
ROS for Nix in the [nix-ros-overlay][nro] repository, and in particular doing the
work of packaging the system dependencies such as `catkin_pkg` and Gazebo.

Some key differences between the approach there and this one include:

- This project uses source snapshots and colcon-distro, so it doesn't need to download
  source at generate time, and also doesn't require tagging or `bloom-release`, so it
  works well for things like hourly and PR builds.
- This project runs every build though colcon, rather than treating ROS packages as native
  CMake builds. This gives up some of Nix's built-in CMake optimization, but allows us
  to make the packaging builds closer to what developers build in workspaces.
- This project doesn't wrap executables, and propagates package run/exec dependencies
  via Nix's passthru mechanism, so that they only show up when a workspace is created.
  This slightly reduces Nix dependency weight since a changed package will not trigger
  down-tree builds of packages that _only_ have a run-depend on it.
- This project doesn't use `superflore` or normalize package names (for example,
  converting underscores to dashes).
- This project is a singular snapshot in time and won't be actively maintained, unless
  interested third parties step up to take it on.

Overally, `nix-ros-overlay` strives to align more closely to upstream Nix packaging
conventions and expectations than this one does.

[nro]: https://github.com/lopsided98/nix-ros-overlay/
