import os

DISTRO_CACHE_URL = "http://colcon-distro.ext.ottomotors.com/get/{distro}/{ref}.json"
HYDRA_URL = os.environ.get("HYDRA_URL", None)

DISTRO_SNAPSHOTS_URL = "https://github.com/clearpathrobotics/rosdistro-snapshots"

DISTRO_URL = "https://github.com/ros/rosdistro"
DISTRO_NAMES = ("noetic", "rolling")
ROSDEP_URLS = (
    "{DISTRO_URL}/raw/{rosdep_branch}/rosdep/base.yaml",
    "{DISTRO_URL}/raw/{rosdep_branch}/rosdep/python.yaml",
)

EXCLUDE_PACKAGES = (
    "gtest",
)

ROSDEP_OVERRIDES = {
    "pybind11-dev": ["python3Packages.pybind11"],
    "python3-pytest": ["python3Packages.pytest"],
    "python3-qt5-bindings": ["python3Packages.pyqt5", "python3Packages.sip_4"],
}
