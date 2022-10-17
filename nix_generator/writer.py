import em
import logging
from operator import itemgetter
import os
from pkgutil import get_data
import re

# Setup logging.
logging.basicConfig()
logger = logging.getLogger(__name__)

URL_REGEX = re.compile(
    r"(?:\w+:\/\/|git@)(?P<server>[\w.-]+)[:/](?P<owner>[\w/_.-]*)/(?P<repo>[\w_.-]*)(?:\.git)?$"
)
FETCHERS = {
    "github.com": "fetchFromGitHub",
    "gitlab.com": "fetchFromGitLab",
    "bitbucket.org": "fetchFromBitbucket",
}
GITIGNORE_CONTENTS = """\
result*
*.swp
"""

def sanitize_store_name(name):
    return name.replace("~", "-").replace("/", "-")


class Writer:
    def __init__(self, packages_path, repositories, exclude_packages=tuple()):
        self.packages_path = packages_path
        self.repositories = repositories
        self.exclude_packages = exclude_packages

    @staticmethod
    def get_template(name):
        return get_data(__package__, f"templates/{name}.em").decode()

    @classmethod
    def write_base_files(cls, output_path, nix_base_url, overlay_paths, flake_tag, rosdistro_ref):
        with open(output_path / "flake.nix", "w") as output:
            v = {
                "nix_base_url": nix_base_url,
                "overlay_paths": overlay_paths,
                "rosdistro_ref": rosdistro_ref,
                "flake_tag": flake_tag,
            }
            i = em.Interpreter(output=output, globals=v)
            i.string(cls.get_template("flake.nix"))
            i.shutdown()
        with open(output_path / "release", "w") as output:
            output.write(flake_tag)
        with open(output_path / ".gitignore", "w") as output:
            output.write(GITIGNORE_CONTENTS)

    def write_srcs_files(self):
        for repo_name, repo_dict in self.repositories.items():
            package_dicts = [
                d
                for d in repo_dict["packages"]
                if d["name"] not in self.exclude_packages
            ]

            repo_file = self.packages_path / "srcs" / f"{repo_name}.nix"
            repo_file.parent.mkdir(exist_ok=True, parents=True)
            with open(repo_file, "w") as output:
                git_parts = URL_REGEX.match(repo_dict["url"])
                host_repo = git_parts.group("repo").split(".git")[0]
                package_dicts.sort(key=itemgetter("name"))
                v = {
                    "name": repo_name,
                    "fetcher": FETCHERS[git_parts.group("server")],
                    "owner": git_parts.group("owner"),
                    "repo": host_repo,
                    "rev": repo_dict["version"],
                    "hash": repo_dict["metadata"]["narhash"],
                    "safe_owner": sanitize_store_name(git_parts.group("owner")),
                    "safe_repo": sanitize_store_name(host_repo),
                    "safe_rev": sanitize_store_name(repo_dict["version"]),
                    "packages": package_dicts,
                }

                i = em.Interpreter(output=output, globals=v)
                i.string(self.get_template("src.nix"))
                i.shutdown()
        logger.info(f"Wrote {len(self.repositories)} repository source definitions.")

        with open(self.packages_path / "srcs" / "default.nix", "w") as output:
            v = {"repo_names": self.repositories.keys()}
            i = em.Interpreter(output=output, globals=v)
            i.string(self.get_template("src-default.nix"))
            i.shutdown()

    def write_packages_files(self, rosdep_mapping):
        # Remember these so we only warn once for each of them.
        unresolved_rosdeps = set()

        all_package_dicts = []
        for repo_name, repo_dict in self.repositories.items():
            for package_dict in repo_dict["packages"]:
                if package_dict["name"] in self.exclude_packages:
                    continue
                package_dict["repo_name"] = repo_name
                all_package_dicts.append(package_dict)

        # A set containing all known package names, for the purposes of identifying
        # non-workspace dependencies, which then go to rosdep.
        package_names = set(p["name"] for p in all_package_dicts)

        for package_dict in all_package_dicts:
            inputs = set()

            def process_dependencies(dep_names):
                for dep_name in dep_names:
                    if dep_name in package_names:
                        # Dependency is just another workspace package.
                        inputs.add(dep_name)
                        yield dep_name
                    else:
                        # Many internal packages have not been updated for python3-xx rosdep keys, so
                        # we provide a shim for that here. Explicit is not None check is needed here
                        # because empty list is falsy to Python.
                        if (mapped_py3 := rosdep_mapping.get(dep_name.replace("python-", "python3-", 1))) is not None:
                            for mapped_dep in mapped_py3:
                                inputs.add(mapped_dep.split(".")[0])
                            yield from mapped_py3
                        elif (mapped := rosdep_mapping.get(dep_name)) is not None:
                            for mapped_dep in mapped:
                                inputs.add(mapped_dep.split(".")[0])
                            yield from mapped
                        elif dep_name not in unresolved_rosdeps:
                            unresolved_rosdeps.add(dep_name)
                            logger.debug(f"Unable to resolve dependency: {dep_name}")

            buildDepends = set(process_dependencies(package_dict["depends"].get("build", [])))
            runDepends = set(process_dependencies(package_dict["depends"].get("run", [])))
            testDepends = set(process_dependencies(package_dict["depends"].get("test", [])))

            v = {
                "name": package_dict["name"],
                "repo_name": package_dict["repo_name"],
                "inputs": sorted(inputs),
                "buildDepends": sorted(buildDepends),
                "runDepends": sorted(runDepends),
                "testDepends": sorted(testDepends),
                "binary": package_dict["metadata"].get("binary"),
                "scope_name": self.packages_path.name,
            }
            filename = self.packages_path / f'{package_dict["name"]}.nix'
            with open(filename, "w") as output:
                i = em.Interpreter(output=output, globals=v)
                i.string(self.get_template("package.nix"))
                i.shutdown()

        logger.info(f"Wrote {len(all_package_dicts)} package definitions.")
        if unresolved_rosdeps:
            logger.warning(
                f"Unable to resolve {len(unresolved_rosdeps)} ROS dependencies."
            )

        with open(self.packages_path / "default.nix", "w") as output:
            v = {
                "package_names": sorted(package_names),
                "scope_name": self.packages_path.name,
            }
            i = em.Interpreter(output=output, globals=v)
            i.string(self.get_template("package-default.nix"))
            i.shutdown()
