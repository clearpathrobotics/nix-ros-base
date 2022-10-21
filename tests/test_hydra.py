from nix_generator.hydra import Hydra

def test_push_jobset_tag():
    client = Hydra("http://hydra", dry_run=True)
    print(client.client_cls.requests.clear())

    project = "my_project"
    tag = "2.26_tag"
    client.push_jobset_tag(project=project, tag=tag)

    jobset_name = f"v{tag}"
    print(client.client_cls.requests)
    assert client.client_cls.requests[0].url == f"/jobset/my_project/{jobset_name}"
    assert client.client_cls.requests[0].kwargs["data"]["flake"] == f"ros/{tag}"
    assert client.client_cls.requests[1].url == f"/api/push?jobsets={project}:{jobset_name}&force=1"

def test_push_jobset_url():
    client = Hydra("http://hydra", dry_run=True)
    print(client.client_cls.requests.clear())

    project = "my_project"
    my_flake_url = "http://my_host/flake.tar.gz"
    jobset_name = "foo_bar_buz"
    client.push_jobset_url(project=project, url=my_flake_url, jobset_name=jobset_name)

    assert client.client_cls.requests[0].url == f"/jobset/my_project/{jobset_name}"
    assert client.client_cls.requests[0].kwargs["data"]["flake"] == my_flake_url
    assert client.client_cls.requests[1].url == f"/api/push?jobsets={project}:{jobset_name}&force=1"
