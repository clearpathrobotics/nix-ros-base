from nix_generator.cli import sanitize_ref

def test_sanitize_ref():
    assert sanitize_ref("refs/tags/snapshot/20220329") == "refs/tags/snapshot/20220329"
    assert sanitize_ref("tags/snapshot/20220329") == "refs/tags/snapshot/20220329"
    assert sanitize_ref("snapshot/20220329") == "refs/tags/snapshot/20220329"
