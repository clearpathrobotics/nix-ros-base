import argparse
from datetime import datetime
import fnmatch
import os
import sys
import time
import json
import urllib.parse
import httpx

# This should switch once we have the actual build step info endpoint.
HAVE_BUILDSTEP_ENDPOINT = True

from .cli import HYDRA_URL
from .cli import logger
from .hydra import Hydra
from .defaults import GITLAB_API_URL

from rich.tree import Tree
import rich.tree
from rich.table import Table

# Here, we monkeypatch the add method for the tree, this allows us to track the depth.
old_add = Tree.add
def add_tracked(obj_instance, *args, **kwargs):
    res = old_add(obj_instance, *args, **kwargs)
    if not hasattr(obj_instance, "_tracked_tree_depth"):
        obj_instance._tracked_tree_depth = 0
    res._tracked_tree_depth = obj_instance._tracked_tree_depth + 1
    return res
Tree.add = add_tracked
Tree.tracked_depth = lambda self: self._tracked_tree_depth if hasattr(self, "_tracked_tree_depth") else 0

# https://github.com/Textualize/rich/blob/79a41db38f3f2d20610d3b9cfe9b18074374ffca/rich/tree.py#L87-L91
TREE_LEVEL_WIDTH = 4
def calculate_width(obj_instance):
    return obj_instance.tracked_depth() * TREE_LEVEL_WIDTH
Tree.tracked_width = calculate_width
# Done patching this all up.

def format_time(ts):
    return datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")

def debug_print(d):
    import json
    sys.stdout.write(json.dumps(d, indent=4))
    print();

def format_job(job):
    tristate, icon, status_text = Hydra.determine_job_status(job)
    # The lastcheckedtime is None briefly when the job is created, if that is the case, make it zero.
    time_to_use = job["lastcheckedtime"]
    if time_to_use == None:
        time_to_use = 0
    ts = format_time(time_to_use)
    creset = "\x1b[0m"
    cfail = "\x1b[31m"
    csuccess = "\x1b[32m"
    cscheduled = "\x1b[34m"
    # Replace zeros with hyphens to make it easier to interpret
    job["#success"] = "-" if job["nrsucceeded"] == 0 else job["nrsucceeded"]
    job["#failed"] = "-" if job["nrfailed"] == 0 else job["nrfailed"]
    job["#scheduled"] = "-" if job["nrscheduled"] == 0 else job["nrscheduled"]
    t = (
        "{icon}  {name: <80}{ts: <20} {csuccess}{#success}{creset} {cfail}{#failed}{creset} "
        "{cscheduled}{#scheduled}{creset} / {nrtotal} -> {status_text}"
    )
    return t.format(
        status_text=status_text,
        icon=icon,
        ts=ts,
        csuccess=csuccess,
        creset=creset,
        cfail=cfail,
        cscheduled=cscheduled,
        **job,
    )


def run_jobset_list(args, client):
    jobsets = client.get_jobsets_status(project=args.project)
    if jobsets:
        for job in sorted(jobsets, key=lambda x: x["name"]):
            print(format_job(job))
    else:
        print(f"No jobsets in {args.project}.")
    print("", end='', flush=True)


def create_displayable_row(icon, number, text, statuslabel, alignment_offset=0, eol_status=True):
    grid = Table.grid(expand=False)
    grid.add_column() # Icon
    grid.add_column(min_width=alignment_offset, max_width=alignment_offset) # alignment
    grid.add_column(justify="right", min_width=5) # id.
    grid.add_column(justify="right", min_width=1) # padding between row and 
    grid.add_column(justify="left", min_width=120, max_width=120, overflow="ellipsis") # label
    elements = [icon, "", number, "", text,]
    if eol_status:
        grid.add_column(justify="right") # status string.
        elements.append(statuslabel)

    grid.add_row( *elements)
    console = rich.console.Console()
    with console.capture() as capture:
        console.print(grid)
    return capture.get()[0:-1]  # Ugly hack to remove the newline at the end of the console
    

def format_build(build, icon_suffix="", alignment_offset=0, eol_status=True):
    nice_state, nice_icon, nice_string  = Hydra.interpret_build_status(build["buildstatus"])
    return create_displayable_row(icon=nice_icon, number=str(build["id"]), text=build["nixname"], statuslabel=nice_string, alignment_offset=alignment_offset, eol_status=eol_status)

def format_step(step, alignment_offset=0, client=None):
    nice_state, nice_icon, nice_string = Hydra.interpret_buildstep_status(step["status"], step["busy"])
    # Prettify the name a bit.
    text = step["drvpath"].replace("/nix/store/", "").replace(".drv", "")
    build_id = step["build"]

    # If this step didn't succeed, and we can produce an url to the build log.
    if client is not None and nice_state is False:
        # Build failed, lets provide a pretty link to the build log.
        log_url = client.format_url_buildstep_log(build_id=build_id, step_nr = step["stepnr"])
        # If we have a propagatedfrom, and a matching step, use that instead to work around hydra giving an error.
        if "propagatedfrom" in step and step["propagatedfrom"] and "matching_steps" in step["propagatedfrom"] and step["propagatedfrom"]["matching_steps"]:
            for propagated_step in step["propagatedfrom"]["matching_steps"]:
                log_url = client.format_url_buildstep_log(build_id=propagated_step["build"], step_nr = propagated_step["stepnr"])
                text += f"\nPropagated log can be found at 🗒️  {log_url}"
            if len(step["propagatedfrom"]["matching_steps"]) > 1:
                text += f"\nMultiple logs matched the failing derviation name, click the failing build for certainty."
        else:
            # No propagated info or no matching steps, just print the original, hope it exists.
            text += f"\nLog can be found at 🗒️  {log_url}"

    return create_displayable_row(icon=nice_icon, number=str(step["stepnr"]), text=text, statuslabel=nice_string, alignment_offset=alignment_offset)


def add_steps_to_tree(tree, client, build_id, steps, summarize_successful=True, indentation=""):
    indentation = tree.tracked_width()
    start_of_line = 5
    alignment_offset = start_of_line - indentation

    if summarize_successful:
        successful = len([s for s in steps if Hydra.interpret_buildstep_status(s["status"], s["busy"])[0] is True])
        # Create a mock step to pass to the printer.
        summary_step = {
            "drvpath": f"{successful} successfully completed",
            "build": 0,
            "busy": 0,
            "status": 0,
            "stepnr": "",
        }
        if successful:
            tree.add(format_step(summary_step, alignment_offset=alignment_offset, client=client))
    
    for step in steps:
        nice_state, nice_icon, nice_string = Hydra.interpret_buildstep_status(step["status"], step["busy"])
        if summarize_successful and nice_state is True:
            continue
        build_string = format_step(step, alignment_offset=alignment_offset, client=client)
        tree_entry = f"{build_string}"
        tree.add(tree_entry)



def print_jobset_jobs(client, project, jobset_name, summary_buildsteps=True, always_report_steps=True, console=None, eol_status=True):
    if console is None:
        console = rich.console.Console()

    info = get_jobset_jobs(client=client, project=project, jobset_name=jobset_name)

    if not "evals" in info:
        print(f"No evals in {project}/{jobset_name}, job not picked up yet?")
        return

    for eval in info["evals"]:
        t = format_time(time.time())
        tree_eval = Tree(f"Evaluation #{eval['id']} at {t}")

        indentation = tree_eval.tracked_width() 
        start_of_line = 5
        alignment_offset = start_of_line - indentation

        for build_id in eval["builds"]:
            build_info = info["builds_retrieved"][build_id]

            # New way after build step info.
            nice_state, nice_icon, nice_string = Hydra.interpret_build_status(build_info["buildstatus"])
            build_string = format_build(build_info, icon_suffix = indentation, alignment_offset=alignment_offset, eol_status=eol_status)
            z = tree_eval.add(f"{build_string}")
            if always_report_steps or nice_state is False:
                add_steps_to_tree(z, client, build_id=build_id, steps=build_info["steps"], summarize_successful=summary_buildsteps, indentation=" ")


        console.print(tree_eval)
    console.print("", end='')

"""
    Collect all information about the jobs in the jobsets.
"""
def get_jobset_jobs(client, project, jobset_name):
    jobset_evals = client.get_jobset_evals(project=project, jobset_name=jobset_name)
    if not "evals" in jobset_evals:
        return {}
    for eval in jobset_evals["evals"]:
        jobset_evals["builds_retrieved"] = {}
        for build_id in eval["builds"]:
            if HAVE_BUILDSTEP_ENDPOINT:
                build_info = client.get_build_info(build_id)
                # retrieve any propagated build information to direct link logs from propagated builds.
                client.add_propagated_step_info(build_info)
            else:
                build_info = client.get_build(build_id)
                build_info["steps"] = []
            jobset_evals["builds_retrieved"][build_id] = build_info
    return jobset_evals


def run_jobset_jobs(args, client):
    print_jobset_jobs(client, project=args.project, jobset_name=args.jobset)


def run_jobset_cancel(args, client):
    client.cancel_jobset(project=args.project, jobset_name=args.jobset)


def run_jobset_create(args, client):
    # First, delete the jobset by this name, to ensure we can run ours.
    jobsets = client.get_jobsets_status(project=args.project)
    jobset_names = set(job["name"] for job in jobsets)
    if args.jobset_name in jobset_names:
        client.delete_jobset(project=args.project, jobset_name=args.jobset_name)
        print(f"Removed previous jobset {args.project}/{args.jobset_name}")

    # Now we can make the new jobset, two options, either a tag, or a flake url.
    if "http" in args.input:
        # Assume it is a plake url.
        jobset_name = args.jobset_name
        if jobset_name is None:
            jobset_name = urllib.parse.urlparse(args.input).path.replace("/", "-").strip("-")
        name = client.push_jobset_url(
            project=args.project,
            url=args.input,
            jobset_name=jobset_name,
            description=args.description,
        )
    else:
        # Lets hope it is a tag, lets give it a go!
        name = client.push_jobset_tag(
            project=args.project,
            tag=args.input,
            jobset_name=args.jobset_name,
            description=args.description,
        )
    print("Created jobset {}".format(client.format_url_jobset(project=args.project, jobset_name=name)), flush=True)
    return name


def run_jobset_delete(args, client):
    client.delete_jobset(project=args.project, jobset_name=args.jobset)
    print(f"Deleted {args.project}/{args.jobset}")

def add_json_report(args, add_report):
    if args.json_report is not None:
        report = []
        # If the report file already exists, load the original content.
        if os.path.isfile(args.json_report):
            with open(args.json_report) as f:
                report = json.load(f)
        extras = {}
        if args.json_report_extra is not None:
            entries = args.json_report_extra.split("|")
            if (len(entries) % 2) != 0:
                raise RuntimeError("Extra report does not have correct number of delimiters.")
            for i in range(int(len(entries) / 2)):
                k = entries[i * 2]
                v = entries[i * 2 + 1]
                extras[k] = v
        add_report["extras"] = extras
        add_report["report_time"] = time.time()
        report.append((args.json_report_name, add_report))
        # Save the updated report.
        with open(args.json_report, "w") as f:
            json.dump(report, f, indent=1)

def run_hydra_monitor(args, client, jobset_name_override=None):
    jobset_name = jobset_name_override if jobset_name_override is not None else args.jobset_name
    jobset_url = client.format_url_jobset(project=args.project, jobset_name=jobset_name)
    print(jobset_url)
    # We can go into the wait loop, first setup the variables for timing.
    now = time.time()
    start = now
    duration = now - start
    # And for state tracking.
    old_state = (0, 0, 0)  # success, fail, scheduled
    old_report_time = now
    console = rich.console.Console(color_system=None, width=200)

    def exit_status_message(exit_code, message, job):
        # Create our report and add it to the current reporting.
        our_report = {
            "jobset_name": jobset_name,
            "jobset_url": jobset_url,
            "start": start,
            "end": time.time(),
            "duration": duration,
            "exit_code": exit_code,
            "message": message,
            "hydra_jobset_jobs": get_jobset_jobs(client, project=args.project, jobset_name=jobset_name),
            "job": job,
        }
        add_json_report(args, our_report)

        print(message)
        sys.exit(exit_code)

    job = {}
    while duration < args.timeout:
        now = time.time()
        duration = now - start
        took_string = f" (took {duration:.1f}s)"

        # Get status of jobsets, check if our job still exists.
        jobsets = client.get_jobsets_status(project=args.project)
        jobsets_by_name = {job["name"]: job for job in jobsets}
        if not jobset_name in jobsets_by_name:
            exit_status_message(2, f"Job '{jobset_name}' disappeared{took_string}, reporting failure {jobset_url}", job)
        else:
            # The job exists, we can now determine the state.
            job = jobsets_by_name[jobset_name]
            job_state, job_emoji, text_status = Hydra.determine_job_status(job)

            # If the build numbers changed, or we have should update according to the report interval.
            current_state = (job["nrsucceeded"], job["nrfailed"], job["nrscheduled"])
            if old_state != current_state or (now - old_report_time) > args.report_interval:
                # Print the status of all jobs in the jobset.
                print_jobset_jobs(client, project=args.project, jobset_name=jobset_name, console=console)
                old_state = current_state
                old_report_time = now

            # Check if we reached a termination state.
            if job_state is False:
                exit_status_message(3, f"Job reports failure {job_emoji}{took_string}, reporting failure for {jobset_url}", job)
            elif job_state is True:
                exit_status_message(0, f"Job reports success 🎉{took_string} for {jobset_url}", job)
            else:
                pass  # Job state is None means pending, loops around.
        time.sleep(args.sleep_period)

    # If we got here, we timed out... in that case, lets cancel the job, hope that works.
    print(f"Job exceeded allowed runtime, cancelling and timing out with failure for {jobset_url}")
    client.cancel_jobset(project=args.project, jobset_name=jobset_name)
    exit_status_message(4, f"Job exceeded allowed runtime{took_string}, cancelled and timing out with failure for {jobset_url}", job)


def run_hydra_watcher(args, client):
    # We can go into the wait loop, first setup the variables for timing.
    now = time.time()
    start = now
    duration = now - start

    # The url where we can get the sub-pipeline statusses for the pipeline to be tracked.
    status_api = f"{GITLAB_API_URL}/projects/{args.gitlab_project}/pipelines/{args.gitlab_pipeline}/jobs"

    while duration < args.timeout:
        now = time.time()
        duration = now - start

        # Grab the current status.
        resp = httpx.Client(headers={"Accept": "application/json"}).get(status_api)
        if resp.is_error:
            print(f"Pipeline url retrieval failed {resp}, exiting with 3")
            sys.exit(3)
        resp = resp.json()

        # Cool, lets try to find the job id we are interested in.
        job = None
        for retrieved_job in resp:
            if retrieved_job["name"] == args.gitlab_job:
                job = retrieved_job
                break

        # Our job not here? Lets break, nothing to see here, perhaps pipeline got cancelled before job started?
        if job is None:
            print(f"Couldn't find our job in {resp}, exiting with 2.")
            sys.exit(2)

        # Now, we can check our job status.
        # Documentation here is severely lacking...  assuming it is the same as the pipeline status;
        # from https://docs.gitlab.com/ee/api/pipelines.html
        # The status of pipelines, one of: created, waiting_for_resource, preparing, pending, running, success, failed,
        # canceled, skipped, manual, scheduled.
        status = job["status"]
        t = format_time(now)
        print(f"Status: {status} at {t}")
        if status == "success":
            print(f"Status success, exiting with 0.")
            sys.exit(0)
        elif status == "failed":
            print(f"Status failed, reporting failure as well to make the view consistent, exiting with 1.")
            sys.exit(1)
        elif status == "canceled":
            print(f"The job we are watching reported canceled.")
            print(f"Cancelling hydra jobset {args.hydra_jobset_name} for {args.hydra_project}.")
            # This fails if the jobset doesn't exist yet, ah well...
            client.cancel_jobset(project=args.hydra_project, jobset_name=args.hydra_jobset_name)
            print(f"We cancelled our job, did our task, exiting with 0.")
            sys.exit(0)
        else:
            # Not a termination state, pass and keep watching.
            pass

        time.sleep(args.sleep_period)

    print(f"Timing out, exiting with 4.")
    sys.exit(4)


def run_maintenance_gc(args, client):
    now = time.time()
    projects = client.get_projects()
    for project in projects:
        project_name = project["name"]
        if not fnmatch.fnmatch(project_name, args.project):
            continue
        else:
            print(f"Checking project {project_name}")
        jobsets = client.get_jobsets_status(project=project_name)

        def get_jobset_time(jobset):
            time_to_use = jobset["lastcheckedtime"]
            if time_to_use is None:
                time_to_use = now # Means job is likely still pending.
            return time_to_use

        # Sort them by most recent first.
        jobsets = sorted(jobsets, key=get_jobset_time, reverse=True)

        # Remove the most recent jobs we always want to preserve. If args.retain_per_project exceeds the
        # jobset length, then we preserve everything automatically.
        retaining = jobsets[0:args.retain_per_project]
        for retained in retaining:
            jobset_name = retained["name"]
            print(f"  Retaining {project_name}/{jobset_name}")
        jobsets = jobsets[args.retain_per_project:]

        # Finally, check the times on all the remaining jobsets and check which ones ought to be pruned.
        for jobset in jobsets[::-1]:
            time_to_use = get_jobset_time(jobset)
            too_old = (now - time_to_use) > args.retain
            if too_old:
                jobset_name = jobset["name"]
                ts = format_time(time_to_use)
                print(f"  Deleting {project_name}/{jobset_name} from {ts}")
                client.delete_jobset(project_name, jobset_name)


def run_build_info(args, client):
    build_info = client.get_build_info(args.build_id)
    build_status, build_status_icon, build_status_text = Hydra.interpret_build_status(build_info["buildstatus"])

    build_string = format_build(build_info)
    tree_eval = Tree(build_string)

    # Add the steps
    if build_info["steps"]:
        add_steps_to_tree(tree_eval, client, build_id=args.build_id, steps=build_info["steps"], summarize_successful=False)

    # Print the steps.
    rich.print(tree_eval)

    # Print a note if the build is not yet in a final state.
    if build_status is None:
        print("Build ongoing, more steps may appear.")

def run_report_add_entry(args, client=None):
    our_report = json.loads(args.json_input)
    add_json_report(args, our_report)

def run_report_comment(args, client=None):
    comment_lines = []

    # Fail gracefully if the file doesn't exist.
    if os.path.isfile(args.json_report):
        with open(args.json_report) as f:
            d = json.load(f)
    else:
        d = []
        comment_lines.append(f"No nix json report file found at `{args.json_report}`")

    for name, report in d:
        # Most things have a hydra report, if so, build out the nice status information.
        if "hydra_jobset_jobs" in report:
            job_state, job_emoji, text_status = Hydra.determine_job_status(report["job"])

            duration = report["duration"]
            jobset_url =  report["jobset_url"]
            line = f"- {job_emoji} [{name}]({jobset_url}) ({duration:.0f}s)"

            if job_state is True and name == "Build Bundle":
                # Add a pretty comment about how to use this, since it is now available.
                tag = report["extras"]["HYDRA_JOBSET_NAME"][1:] # [1:] to strip the 'v'
                line += f" test with: `nix develop ros/{tag}#ros_desktop_full.ws`"
                comment_lines.append(line)
            elif job_state is True:
                comment_lines.append(line)
            elif job_state is False:
                # Hydra pipeline failed, print the failed jobs with links to hydra to find the failed steps.
                line += f" {text_status}:"
                comment_lines.append(line)
                for eval in report["hydra_jobset_jobs"]["evals"]:
                    for build_id in eval["builds"]:
                        build = report["hydra_jobset_jobs"]["builds_retrieved"][str(build_id)]
                        build_state, build_icon, build_string = Hydra.interpret_build_status(build["buildstatus"])
                        build_job = build["job"]
                        # Concensus in navigation was that printing the usable bundles for an MR has value, even
                        # if the build partially failed, so we print all of them, not only the failures.
                        build_url = client.format_url_build(build_id)
                        clickable = f'[{build_job}]({build_url})'
                        comment_lines.append(f"  - {build_icon} {clickable}")
                        if "steps" in build and HAVE_BUILDSTEP_ENDPOINT: # Adapted from format_step
                            for step in build["steps"]:
                                # Only for failed builds, add an entry.
                                nice_state, nice_icon, nice_string = Hydra.interpret_buildstep_status(step["status"], step["busy"])
                                # Prettify the name a bit.
                                name = step["drvpath"].replace("/nix/store/", "").replace(".drv", "")
                                # remove the hash
                                if "-" in name:
                                    name = name[name.index('-') + 1:]
                                build_id = step["build"]

                                # If this step didn't succeed, and we can produce an url to the build log.
                                if client is not None and nice_state is False:
                                    # Build failed, lets provide a pretty link to the build log.
                                    log_url = client.format_url_buildstep_log(build_id=build_id, step_nr = step["stepnr"])
                                    suffix = ""

                                    # If we have a propagatedfrom, and a matching step, use that instead to work around hydra giving an error.
                                    if "propagatedfrom" in step and step["propagatedfrom"] and "matching_steps" in step["propagatedfrom"] and step["propagatedfrom"]["matching_steps"]:
                                        if len(step["propagatedfrom"]["matching_steps"]) == 1:
                                            propagated_step = step["propagatedfrom"]["matching_steps"][0]
                                            log_url = client.format_url_buildstep_log(build_id=propagated_step["build"], step_nr = propagated_step["stepnr"])
                                            suffix = "(propagated)"
                                        elif len(step["propagatedfrom"]["matching_steps"]) >= 1:
                                            log_url = build_url
                                            suffix = "(multiple propagated steps; linking to build url)"
                                    comment_lines.append(f"    - {nice_icon} [{name}]({log_url}) {suffix}")



        # The pipeline report that states whether the tests pass.
        if "test_pass" in report:
            url = report["extras"]["BUILD_URL"]
            clickable = f'[Test Results]({url}testReport/)'
            # The actual boolean whether the tests passed.
            if report["test_pass"]:
                comment_lines.append(f"- ✅ {clickable}")
            else:
                comment_lines.append(f"- ❌ {clickable}")

    comment = "\n".join(comment_lines) + "\n"

    if args.output is not None:
        with open(args.output, "w") as f:
            f.write(comment)
    else:
        sys.stdout.write(comment)



def add_json_report_arguments(argparser):
    argparser.add_argument(
        "--json-report",
        nargs="?",
        type=str,
        default=None,
        help="Insert an update entry into the json file, or create it.",
    )
    argparser.add_argument(
        "--json-report-name",
        nargs="?",
        type=str,
        default="report",
        help="Name to use for this monitor report.",
    )
    argparser.add_argument(
        "--json-report-extra",
        nargs="?",
        type=str,
        default=None,
        help="Extra variables to store in this report, 'varname1|varvalue|varname1|varvalue2'",
    )

def main():
    parser = argparse.ArgumentParser(description="Hydra command line utility")
    parser.add_argument("-n", "--dry-run", default=False, action="store_true", help="Dry run only.")
    subparsers = parser.add_subparsers(dest="command")

    # Start of jobset subcommand.
    jobset_parser = subparsers.add_parser("jobset", help="Things related to jobsets.")
    jobset_parser.add_argument("project", default=None, help="Project to perform jobset operations on.")
    jobset_subparsers = jobset_parser.add_subparsers(dest="sub_command")

    jobset_list = jobset_subparsers.add_parser("list", help="List jobsets")
    jobset_list.set_defaults(func=run_jobset_list)

    jobset_create = jobset_subparsers.add_parser("create", help="Create a jobset.")
    jobset_create.add_argument(
        "input",
        help="Input can either be a tag, like '2.26.0-20220331114913-0' or an url" " to a flake tarball.",
    )
    jobset_create.add_argument(
        "--name",
        nargs="?",
        dest="jobset_name",
        default=None,
        help="Jobset name to use. [Either tag name or hyphened-url path]",
    )
    jobset_create.add_argument("--description", nargs="?", default="", help="Description to use.")
    jobset_create.add_argument("--requires_login", default=True, nargs="*", help=argparse.SUPPRESS)
    jobset_create.set_defaults(func=run_jobset_create)

    jobset_delete = jobset_subparsers.add_parser("delete", help="Delete a jobset.")
    jobset_delete.add_argument("jobset", help="The jobset to delete.")
    jobset_delete.add_argument("requires_login", default=True, nargs="*", help=argparse.SUPPRESS)
    jobset_delete.set_defaults(func=run_jobset_delete)

    jobset_jobs = jobset_subparsers.add_parser("jobs", help="List jobs in a jobset.")
    jobset_jobs.add_argument("jobset", help="Jobset to list the jobs for.")
    jobset_jobs.set_defaults(func=run_jobset_jobs)

    jobset_cancel = jobset_subparsers.add_parser("cancel", help="Cancel a jobset.")
    jobset_cancel.add_argument("jobset", help="Jobset to cancel.")
    jobset_cancel.add_argument("--requires_login", default=True, nargs="*", help=argparse.SUPPRESS)
    jobset_cancel.set_defaults(func=run_jobset_cancel)

    jobset_hydra_monitor = subparsers.add_parser("monitor", help="Monitor a jobset on running on hydra.")
    jobset_hydra_monitor.add_argument("project", help="Project to put the jobset under.")
    jobset_hydra_monitor.add_argument("jobset_name", help="The jobset name to monitor.")
    jobset_hydra_monitor.add_argument(
        "--timeout",
        nargs="?",
        type=float,
        default=float("inf"),
        help="Timeout in seconds.  [%(default)s]",
    )
    jobset_hydra_monitor.add_argument(
        "--report-interval",
        nargs="?",
        type=float,
        default=30.0,
        help="Report at this interval, even if there were no changes. [%(default)ss]",
    )
    jobset_hydra_monitor.add_argument(
        "--sleep-period",
        nargs="?",
        type=float,
        default=5.0,
        help="Sleep period in the poll loop. [%(default)ss]",
    )
    add_json_report_arguments(jobset_hydra_monitor)
    jobset_hydra_monitor.set_defaults(func=run_hydra_monitor)



    jobset_hydra_watcher = subparsers.add_parser(
        "ci_watcher",
        help="Something to track a gitlab ci pipeline and cancel hydra if the upstream task is cancelled.",
    )
    jobset_hydra_watcher.add_argument("hydra_project", default=None, help="Project on hydra.")
    jobset_hydra_watcher.add_argument("hydra_jobset_name", help="Jobset name to cancel")
    jobset_hydra_watcher.add_argument("gitlab_project", help="The project the pipeline is running in.")
    jobset_hydra_watcher.add_argument("gitlab_pipeline", help="The pipeline id to monitor.")
    jobset_hydra_watcher.add_argument("gitlab_job", help="Pipeline job to monitor for cancellation.")
    jobset_hydra_watcher.add_argument(
        "--sleep-period",
        nargs="?",
        type=float,
        default=5.0,
        help="Sleep period in the poll loop. [%(default)ss]",
    )
    jobset_hydra_watcher.add_argument(
        "--timeout",
        nargs="?",
        type=float,
        default=float("inf"),
        help="Timeout in seconds.  [%(default)s]",
    )
    jobset_hydra_watcher.set_defaults(func=run_hydra_watcher)

    report_subparser = subparsers.add_parser("report", help="Commands relating to the nix json report.")
    report_subparsers = report_subparser.add_subparsers(dest="sub_command")

    report_add_entry = report_subparsers.add_parser(
        "add",
        help="Add an entry to the json report.",
    )
    report_add_entry.add_argument("json_input", default="{}", nargs="?", help="Json blob to store as the report")
    add_json_report_arguments(report_add_entry)
    report_add_entry.set_defaults(func=run_report_add_entry)


    report_comment = report_subparsers.add_parser(
        "comment",
        help="Generate the MR comment from a particular nix json report.",
    )
    report_comment.add_argument("--output", nargs="?", help="Write the html comment to this file, if unset to stdout.")
    report_comment.add_argument("json_report", type=str, help="The report file to generate a comment from.")
    report_comment.set_defaults(func=run_report_comment)


    # Start of maintenance subcommand
    def duration_parser(duration_string):
        if duration_string.endswith("s"):
            return float(duration_string[:-1])
        elif duration_string.endswith("m"):
            return float(duration_string[:-1]) * 60.0
        elif duration_string.endswith("h"):
            return float(duration_string[:-1]) * 60.0 * 60.0
        elif duration_string.endswith("d"):
            return float(duration_string[:-1]) * 60.0 * 60.0 * 24

    maintenance_subparser = subparsers.add_parser("maintenance", help="A bunch of maintenance helpers.")
    maintenance_subparsers = maintenance_subparser.add_subparsers(dest="sub_command")
    gc_parser = maintenance_subparsers.add_parser("gc", help="Perform a garbage collection on the hydra server.")
    gc_parser.add_argument("--requires_login", default=True, nargs="*", help=argparse.SUPPRESS)
    gc_parser.add_argument(
        "project",
        default="*",
        nargs="?",
        help="Project to garbage collect on [default: %(default)s].",
    )
    gc_parser.add_argument(
        "--retain",
        default="14d",
        type=duration_parser,
        help="History of jobsets to retain " "(single number and unit, like '14d') [default: %(default)s]",
    )
    gc_parser.add_argument(
        "--retain-per-project",
        default="1",
        type=int,
        help="The number of jobsets to retain per project, regardless of retain duration  [default: %(default)s]",
    )
    gc_parser.set_defaults(func=run_maintenance_gc)



    # Start of build subcommand.
    build_parser = subparsers.add_parser("build", help="Things related to builds.")
    build_parser.add_argument("build_id", default=None, help="Build to operate on.")
    build_subparsers = build_parser.add_subparsers(dest="sub_command")

    build_info = build_subparsers.add_parser("info", help="Show info about a particular build")
    build_info.set_defaults(func=run_build_info)



    # Start of actual processing of the input arguments.
    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        parser.exit()


    client = Hydra(HYDRA_URL, dry_run=args.dry_run)

    # Check if we have to login, if so login or bail out.
    requires_login = hasattr(args, "requires_login") and args.requires_login
    if requires_login and not args.dry_run:
        try:
            hydra_username = os.environ["HYDRA_USERNAME"]
            hydra_password = os.environ["HYDRA_PASSWORD"]
            logger.info(f"Logging into {HYDRA_URL}")
            client.login(hydra_username, hydra_password)
        except KeyError:
            logger.warn("Auth vars HYDRA_USERNAME and HYDRA_PASSWORD are not set, cannot login, please provide these.")
            sys.exit(1)

    subparser_commands = {"jobset": jobset_parser, "build": build_parser, "maintenance": maintenance_subparser}

    if args.command in subparser_commands:
        # This has a subparser, if there's no command, print a help.
        subparser = subparser_commands[args.command]
        if args.sub_command is None:
            subparser.print_help()
            subparser.exit()
        else:
            args.func(args, client)
    else:
        args.func(args, client)
