import argparse
import httpx
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import yaml

from .defaults import *
from .hydra import Hydra
from .rosdeps import fetch_rosdeps
from .writer import Writer

logging.basicConfig()
logger = logging.getLogger(__package__)

def sanitize_ref(ref):
    if not ref.startswith("refs/"):
        if not ref.startswith("tags/"):
               # Did not start with tags/, add this in front.
            ref = f"tags/{ref}"
        # Did not start with refs/, add this in front.
        ref = f"refs/{ref}"
    # ref is now in the form of refs/tags/snapshot/20220329, like we would also obtain from git.
    return ref

def retry_subprocess_errors(fun=None, args=[], kwargs={}, retry_count=3):
    """
        Helper function to allow retrying functions in case they throw a CalledProcessError.
    """
    last_error = None
    for i in range(retry_count):
        time.sleep(i) # Linear back-off for all but the first attempt.
        try:
            return fun(*args, **kwargs)
        except subprocess.CalledProcessError as e:
            last_error = e
            logger.warn(f"Got {e} in retry errors {i + 1}/{retry_count}. ({fun}, {args}, {kwargs}).")
    logger.error(f"Exceeded number of retries, rethrowing the error.")
    raise last_error

def retrying_check_call(*args, **kwargs):
    return retry_subprocess_errors(subprocess.check_call, args=args, kwargs=kwargs)

def retrying_check_output(*args, **kwargs):
    return retry_subprocess_errors(subprocess.check_output, args=args, kwargs=kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-o", "--output", default=None, help="Output path, defaults to cwd/build."
    )
    parser.add_argument(
        "-n", "--nix-base", default=None, help="Flake URL for nix base repo, defaults to cwd."
    )
    parser.add_argument(
        "--nix-base-remote", action='store_true', help="Use remote URL for nix-base."
    )
    parser.add_argument(
        "-t", "--push-tag", action='store_true', help="Run flake check, tag, and git push the result."
    )
    parser.add_argument(
        "--create-hydra-job", action='store_true',
        help="Create hydra job for this tag, requires HYDRA_USERNAME and HYDRA_PASSWORD to be set."
    )
    parser.add_argument(
        "--hydra-project", type=str, help="Project on hydra to put the jobset under.", default="ros"
    )
    parser.add_argument(
        "--write-hydra-jobset-name-file", default=None, type=str,
        help="File to write the picked hydra jobset name to."
    )
    parser.add_argument(
        "--create-lock", action='store_true',
        help="Create the flake lock file, always done when making a hydra job."
    )
    parser.add_argument(
        "--rosdep-branch",
        help="The branch in rosdistro to retrieve the rosdep entries from [defaults to %(default)s].",
        default="master",
    )
    parser.add_argument(
        "--ref", default=None, help="Ref to generate for, otherwise uses the latest found."
    )

    parser.add_argument("--verbose", action="store_true", help="Additional log output.")
    args = parser.parse_args()

    logger.setLevel(logging.DEBUG if args.verbose else logging.INFO)

    hydra = Hydra(HYDRA_URL)
    if args.create_hydra_job:
        try:
            hydra_username = os.environ["HYDRA_USERNAME"]
            hydra_password = os.environ["HYDRA_PASSWORD"]
        except KeyError:
            logger.error("Auth vars HYDRA_USERNAME and HYDRA_PASSWORD are not set.")
            return 1
        logger.info(f"Logging into {HYDRA_URL}")
        hydra.login(hydra_username, hydra_password)

    # Setup output path.
    output_path = Path(args.output) if args.output else Path.cwd() / "build"
    output_path.mkdir(parents=True, exist_ok=True)

    if args.nix_base:
      nix_base_url = args.nix_base
    elif args.nix_base_remote:
      cmd = ["git", "rev-parse", "HEAD"]
      rev = subprocess.check_output(cmd, universal_newlines=True).strip()
      nix_base_url = f"ros-base/{rev}"
    else:
      nix_base_url = Path.cwd()
      if not (nix_base_url / "flake.nix").exists():
        logger.error("Current directory does not contain flake.nix. Specify --nix-base option.")
        return 1

    # Determine distro snapshot and version string.
    if args.ref:
        ref = sanitize_ref(args.ref)
        if ref != args.ref:
            logging.warn(f"Provided ref '{args.ref}' was not a full ref, using '{ref}'.")
    else:
        # Use git to determine the latest tag.
        git_cmd = ["git", "ls-remote", DISTRO_SNAPSHOTS_URL, "refs/tags/*"]
        git_output = retrying_check_output(git_cmd, universal_newlines=True).strip()
        ref = git_output.split()[-1]

    version = ref

    # If we have slashes in the ref it is a full ref, obtain just the date tag.
    version = ref.split("/")[-1]

    if args.push_tag:
        if str(nix_base_url).startswith("/"):
            logger.error("Unwilling to create and push tag with nix-base on a local path.");
            sys.exit(1)
        cmd = ["git", "ls-remote", "origin", f"refs/tags/{version}*"]
        remote_tags = retrying_check_output(cmd, universal_newlines=True, cwd=output_path)
        for tag_suffix in range(16):
            tag = f"{version}-{tag_suffix}"
            if tag not in remote_tags:
                break
        else:
            logger.error(f"Unable to find unused tag for version {version}.")
            sys.exit(1)
    else:
        tag = f"{version}-dev"
    logger.info(f"Version tag is {tag}.")

    # The final version is now available, write out the top level flake and release files.
    overlay_paths = DISTRO_NAMES
    Writer.write_base_files(output_path, nix_base_url, overlay_paths, flake_tag=tag, rosdistro_ref=ref)

    # Fetch rosdep information from rosdistro.
    rosdep_urls = (v.format(DISTRO_URL=DISTRO_URL, rosdep_branch=args.rosdep_branch) for v in ROSDEP_URLS)
    rosdep_mapping = fetch_rosdeps(rosdep_urls)
    rosdep_mapping.update(ROSDEP_OVERRIDES)

    # Fetch distro information and write out src/package definitions.
    for distro_name in DISTRO_NAMES:
        url = DISTRO_CACHE_URL.format(distro=distro_name, ref=ref)
        logger.info(f"Loading distro snapshot: {url}")
        req = httpx.get(url, timeout=420.0)
        if req.status_code == httpx.codes.OK:
            logger.debug(f"Distro cache request completed: {req}")
            info = req.json()
            writer = Writer(output_path / distro_name, info["repositories"], EXCLUDE_PACKAGES)
            writer.write_srcs_files()
            writer.write_packages_files(rosdep_mapping)
        else:
            logger.error(f"Failed to retrieve distro snapshot {url}, status code: {req.status_code}.")
            logger.error(f"Exiting, failure may be due to an incorrect snapshot reference.")
            sys.exit(2)

    logger.info(f"Successful generation for tag {tag}")

    if args.push_tag or args.create_lock:
        logger.info("Updating flake lock.");
        subprocess.check_call(["nix", "flake", "update"], cwd=output_path)

    if args.push_tag:
        hydra_project = args.hydra_project
        if str(nix_base_url).startswith("/"):
            logger.error("Unwilling to create and push tag with nix-base on a local path.");
            sys.exit(1)

        subprocess.check_call(["git", "add", "-A"], cwd=output_path)
        subprocess.check_call(["git", "commit", "--no-verify", "--allow-empty", "-m", tag], cwd=output_path)

        subprocess.check_call(["git", "tag", tag], cwd=output_path)
        retrying_check_call(["git", "push", "origin", tag], cwd=output_path)

        if args.create_hydra_job:
            logger.info(f"Creating and evaluating jobset {hydra_project}:v{tag}")
            hydra.push_jobset_tag(hydra_project, tag)
    if args.write_hydra_jobset_name_file:
        with open(args.write_hydra_jobset_name_file, "w") as f:
            f.write(f"v{tag}")
