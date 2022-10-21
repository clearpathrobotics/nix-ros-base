import contextlib
import httpx
import time

class HydraException(BaseException):
    pass

class HydraResponseException(HydraException):
    def __init__(self, resp):
        self.response = resp
        self.request = self.response.request
        self.status_code = resp.status_code
        super().__init__(resp)
    def __str__(self):
        # Print the response, original request and returned text.
        return f"{self.response} {self.request} ({self.response.text})"

def client_wrapper(cls, retries=3):
    class Wrapper(cls):
        # For get methods, retry up to the allowed number of times.
        def get(self, *args, **kwargs):
            for i in range(retries - 1):
                resp = super().get(*args, **kwargs)
                # Return if the request was successful
                if not resp.is_error:
                    return resp
                if resp.status_code in (404, 403):
                    # Not found, or permission denied shouldn't need to be retried.
                    # break to fall through to the exception.
                    break
                time.sleep(0.3)
            # Did not get a non-error response in number of retries, fail with error.
            raise HydraResponseException(resp)

        # Don't retry post, but still make the failed requests into errors.
        def post(self, *args, **kwargs):
            resp = super().post(*args, **kwargs)
            if resp.is_error:
                raise HydraResponseException(resp)
            return resp

        # Don't retry delete, but still make the failed requests into errors.
        def delete(self, *args, **kwargs):
            resp = super().delete(*args, **kwargs)
            if resp.is_error:
                raise HydraResponseException(resp)
            return resp

    return Wrapper

class Hydra:
    def __init__(self, url, dry_run=False, retries=3):
        self.dry_run = dry_run
        self.client_cls = DryRunClient if self.dry_run else httpx.Client
        self.client_cls = client_wrapper(self.client_cls, retries=retries)

        self.client_args = {
            "base_url": url,
            "headers": {"Referer": url, "Accept": "application/json"},
            "cookies": None,
        }

    @contextlib.contextmanager
    def client(self):
        with self.client_cls(**self.client_args) as client:
            yield client

    def login(self, username, password):
        login_data = {"username": username, "password": password}
        with self.client() as c:
            resp = c.post("/login", data=login_data)
        self.client_args["cookies"] = resp.cookies

    def push_jobset(self, project, flake, jobset_name, description=""):
        jobset_data = {
            "description": description,
            "enabled": 1,
            "visible": True,
            "keepnr": 3,
            "checkinterval": 0,
            "schedulingshares": 10,
            "startime": 0,
            "type": 1,
            "flake": flake,
            "inputs": {},
        }

        with self.client() as c:
            # Create the jobset.
            resp = c.put(f"/jobset/{project}/{jobset_name}", data=jobset_data)

            # Cause it to begin evaluating.
            resp = c.post(f"/api/push?jobsets={project}:{jobset_name}&force=1")
        return jobset_name

    def push_jobset_tag(self, project, tag, jobset_name=None, description=""):
        jobset_name_used = f"v{tag}"
        if jobset_name is not None:
            jobset_name_used = jobset_name

        flake = f"ros/{tag}"
        return self.push_jobset(
            project=project,
            flake=flake,
            jobset_name=jobset_name_used,
            description=description,
        )

    def push_jobset_url(self, project, url, jobset_name, description=""):
        flake = f"{url}"
        return self.push_jobset(
            project=project,
            flake=flake,
            jobset_name=jobset_name,
            description=description,
        )

    def get_jobsets(self, project):
        with self.client() as c:
            resp = c.get(f"/project/{project}")
        return resp.json()["jobsets"]

    def get_jobsets_status(self, project):
        with self.client() as c:
            resp = c.get(f"/api/jobsets?project={project}")
        return resp.json()

    def get_jobset_evals(self, project, jobset_name):
        with self.client() as c:
            resp = c.get(f"/jobset/{project}/{jobset_name}/evals")
        return resp.json()

    def delete_jobset(self, project, jobset_name):
        with self.client() as c:
            resp = c.delete(f"/jobset/{project}/{jobset_name}")

    def get_build(self, build):
        with self.client() as c:
            resp = c.get(f"/build/{build}")
        return resp.json()

    def get_build_info(self, build):
        with self.client() as c:
            resp = c.get(f"/build/{build}/api/get-info")
        return resp.json()

    def add_propagated_step_info(self, build_info):
        """
            This function augments the build_info by retrieving the build info for each step that had a propagatedfrom
            element populated. It also attemps to determine which step from the propagated build is associated to the
            original step.
        """
        retrieved_builds = {}
        for step in build_info["steps"]:
            if "propagatedfrom" in step and step["propagatedfrom"]:
                build_id = step["propagatedfrom"]["id"]
                if not build_id in retrieved_builds:
                    retrieved_builds[build_id] = self.get_build_info(build_id)
                step["propagatedfrom"]["build_info"] = retrieved_builds[build_id]

                # The next step is a bit of an extra for this function, but it makes sense to do the matching here.
                # the step["propagatedfrom"] section does unfortunately not state the stepnr that that propagated step
                # was in the build, so we have to resort to string matching on the drvpath to find the matching steps
                # from the propagated build.

                # Find the matching step for this entry, we can't match by drvpath, because that's different.
                # Only failing steps are ever propagated, so we can match based on name and status.
                step_name = Hydra.get_name_from_drvpath(step["drvpath"])
                matching_steps = []
                for propagated_step in step["propagatedfrom"]["build_info"]["steps"]:
                    propagated_name = Hydra.get_name_from_drvpath(propagated_step["drvpath"])
                    propagated_state, propagated_emoji, propagated_state_text = Hydra.interpret_build_status(propagated_step["status"])
                    if propagated_state is False and propagated_name == step_name:
                        matching_steps.append(propagated_step)
                step["propagatedfrom"]["matching_steps"] = matching_steps


    @staticmethod
    def get_name_from_drvpath(drvpath):
        if "-" in drvpath:
            return drvpath[drvpath.find('-')+1:].replace(".drv", "")
        return drvpath

    def get_cancel_build(self, build):
        # This is a GET query with a side effect, it is not part of the api.
        # Prevent the request from happenning if we are in dry-run mode.
        if self.dry_run:
            return True
        with self.client() as c:
            resp = c.get(f"/build/{build}/cancel")
        return True

    def get_eval(self, evaluation):
        with self.client() as c:
            resp = c.get(f"/eval/{evaluation}")
        return resp.json()

    def get_projects(self):
        with self.client() as c:
            resp = c.get(f"/")
        return resp.json()

    def cancel_jobset(self, project, jobset_name):
        jobset_evals = self.get_jobset_evals(project=project, jobset_name=jobset_name)
        if not jobset_evals["evals"]:
            return
        self.cancel_evaluations(jobset_evals["evals"])

    def cancel_evaluations(self, evaluations):
        for eval in evaluations:
            for build_id in eval["builds"]:
                build_info = self.get_build(build_id)
                if not build_info["finished"]:
                    self.get_cancel_build(build_id)

    def format_url_jobset(self, project, jobset_name):
        return f"{self.client_args['base_url']}/jobset/{project}/{jobset_name}"

    def format_url_buildstep_log(self, build_id, step_nr):
        return f"{self.client_args['base_url']}/build/{build_id}/nixlog/{step_nr}"

    def format_url_build(self, build_id):
        return f"{self.client_args['base_url']}/build/{build_id}"

    @staticmethod
    def determine_job_status(job):
        """
        Function to infer the job status based on various fields.

        Returns (False/True/None, "emoji", "status_text")

        False if failure occured in the job, job is done.
        True if everything succeeded, job is done.
        None if not yet conclusive, not a termination state, ongoing job.
        """
        if job["lastcheckedtime"] is None:
            # Job is yet to be picked up by hydra.
            return (None, "⏳", "awaiting")
        elif job["haserrormsg"]:
            # Ok, we _clearly_ failed, something with nix...
            return (False, "🟥", f"error")
        elif job["nrsucceeded"] == job["nrtotal"]:
            # No error message, all jobs succeeded.
            return (True, "✅", "succeeded")
        elif (job["nrsucceeded"] + job["nrfailed"]) == job["nrtotal"]:
            # No error message in the evaluation, but still failed jobs, mark as unstable.
            return (False, "🟧", "partial failure")
        else:
            # Still being worked on.
            return (None, "🏗️", "processing")

    BUILD_STATUS_LOOKUP = {
        0: (True, "✅", "succeeded"),
        1: (False, "❌", "failed"), # Sounds like a nix evaluation error?
        2: (False, "💥", "dependency failed"),  # May be a 'build failed' really?
        3: (False, "💀", "aborted"),
        4: (False, "🛑", "canceled by the user"),
        6: (False, "🟥", "failed with output"),
        7: (False, "⌛", "timed out"),
        8: (False, "🥀", "cached failure"), # Happens for buildsteps that got a cached failure.
        9: (False, "💀", "aborted"),
        10: (False, "🔥", "log size limit exceeded"),
        11: (False, "🔥", "output size limit exceeded"),
        # The docs state 11 and onwards is also failure, probably future expansion.
        # In that case we use the fallback.
        "fallback": (False, "🔥", "some unspecified failure"),
        # If the status id is null in the json (None) in python, the build isn't finished yet.
        None: (None, "🏗️", "pending"),
    }

    @staticmethod
    def interpret_build_status(status_id):
        """
        Status id is populated if the job has concluded.

        Returns (False/True/None, "emoji", "status_text")

        False if failure occured in the job, job is done.
        True if everything succeeded, job is done.
        None if not yet conclusive, not a termination state, ongoing job.
        """
        return Hydra.BUILD_STATUS_LOOKUP.get(status_id, Hydra.BUILD_STATUS_LOOKUP["fallback"])

    BUILD_STEP_BUSY_LOOKUP = {
        1: (None, "♨️", "preparing"),
        10: (None, "🔗", "connecting"),
        20: (None, "📤", "sending inputs"),
        30: (None, "🏗️", "building"),
        40: (None, "📩", "receiving outputs"),
        50: (None, "🖌️", "post-processing"),
        "fallback": (None, "🔥", "unknown build step busy flag encountered."),
    }
    @staticmethod
    def interpret_buildstep_status(build_status, busy_state):
        """
        Return status for the build step.

        Returns (False/True/None, "emoji", "status_text")

        False if failure occured in the job, job is done.
        True if everything succeeded, job is done.
        None if not yet conclusive, not a termination state, ongoing job.
        """
        if busy_state == 0:
            return Hydra.interpret_build_status(build_status)
        # If busy state is set, we always return None, as we are working on this.
        return Hydra.BUILD_STEP_BUSY_LOOKUP.get(busy_state, Hydra.BUILD_STEP_BUSY_LOOKUP["fallback"])
        


class DryRunClient(httpx.Client):
    requests = []

    def _mock(self, url, **kwargs):
        class Response:
            is_error = False
            cookies = {}

        res = Response()
        res.url = url
        res.kwargs = kwargs
        self.requests.append(res)
        return res

    put = _mock
    post = _mock
    delete = _mock
