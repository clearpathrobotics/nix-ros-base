colcon env setup
================

What is going on here? Please read the following page as background:

https://colcon.readthedocs.io/en/released/developer/environment.html

Colcon's dsv-based fast environment setup scheme is only designed to
work with workspaces that are either merged or in a rigidly-defined
isolated layout where all packages are one level deep subdirectories
named after themselves.

This folder copies in an instance of the script that is generated when
the [prefix_util.py.em][p] template is filled, and then supplies a
separate entry point script customized to the needs of the Nix build.

Down the road, this could be generated on demand, or alternatively we
could work with the colcon maintainers to make disparate workspaces
a first-class supported use-case for colcon, see [this ticket][t] for
a starting point in that discussion.

The predecessor of this scheme was just using Nix's standard setupHook
to register every dependency's `local_setup.sh` to get called at the
start of the build:

```
setupHook = writeText "setup-hook.sh" ''
  set +u
  COLCON_CURRENT_PREFIX=$1
  source $1/local_setup.sh
'';
```

This worked fine but was slow once there were many
deps, for the reasons outlined in the colcon RTD page linked above.

[p]: https://github.com/colcon/colcon-core/blob/master/colcon_core/shell/template/prefix_util.py.em
[t]: https://github.com/colcon/colcon-core/issues/365
