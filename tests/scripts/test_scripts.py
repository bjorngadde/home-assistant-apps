"""The Build planner and the Renovate version bump, run in a scratch git repo."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / ".github" / "scripts"


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=repo, check=True, capture_output=True, text=True,
    ).stdout.strip()


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    for app in ("alpha", "beta"):
        (tmp_path / app).mkdir()
        (tmp_path / app / "config.yaml").write_text(
            f'name: {app}\nversion: "1.0.0"\narch:\n  - amd64\n'
            f'image: ghcr.io/x/{{arch}}-{app}\n'
        )
        (tmp_path / app / "Dockerfile").write_text("FROM scratch\n")
        (tmp_path / app / "CHANGELOG.md").write_text("# Changelog\n\n## 1.0.0\n\n- First.\n")
    (tmp_path / ".github").mkdir()
    (tmp_path / ".github" / "ci.yaml").write_text("x: 1\n")
    git(tmp_path, "init", "-q", "-b", "main")
    git(tmp_path, "add", "-A")
    git(tmp_path, "commit", "-qm", "base")
    return tmp_path


def commit(repo: Path, path: str, text: str) -> None:
    (repo / path).write_text(text)
    git(repo, "commit", "-qam", f"change {path}")


def plan(repo: Path, event: str, base: str) -> tuple[list, list]:
    env = {**os.environ, "EVENT": event, "BASE": base, "INPUT_APPS": ""}
    out = subprocess.run(
        [sys.executable, SCRIPTS / "plan.py"], cwd=repo, env=env,
        check=True, capture_output=True, text=True,
    ).stdout
    values = dict(line.split("=", 1) for line in out.splitlines())
    return json.loads(values["apps"]), json.loads(values["builds"])


class TestPlan:
    def test_builds_only_the_changed_app(self, repo):
        base = git(repo, "rev-parse", "HEAD")
        commit(repo, "alpha/Dockerfile", "FROM busybox\n")
        apps, builds = plan(repo, "push", base)
        assert apps == ["alpha"]
        assert builds == [{
            "app": "alpha", "arch": "amd64", "platform": "linux/amd64",
            "image": "ghcr.io/x/amd64-alpha", "version": "1.0.0",
        }]

    def test_markdown_changes_build_nothing(self, repo):
        base = git(repo, "rev-parse", "HEAD")
        commit(repo, "alpha/CHANGELOG.md", "# Changelog\n")
        assert plan(repo, "push", base) == ([], [])

    def test_workflow_changes_build_everything_on_pull_requests_only(self, repo):
        base = git(repo, "rev-parse", "HEAD")
        commit(repo, ".github/ci.yaml", "x: 2\n")
        assert plan(repo, "pull_request", base)[0] == ["alpha", "beta"]
        assert plan(repo, "push", base) == ([], [])


class TestBump:
    def bump(self, repo: Path) -> str:
        return subprocess.run(
            [sys.executable, SCRIPTS / "bump.py", "main", "Update thing to v2"],
            cwd=repo, check=True, capture_output=True, text=True,
        ).stdout

    def test_bumps_the_changed_app_once(self, repo):
        git(repo, "checkout", "-qb", "renovate/alpha")
        commit(repo, "alpha/Dockerfile", "FROM busybox\n")
        assert self.bump(repo) == "alpha 1.0.0 -> 1.0.1\n"
        assert 'version: "1.0.1"' in (repo / "alpha" / "config.yaml").read_text()
        assert (repo / "alpha" / "CHANGELOG.md").read_text().startswith(
            "# Changelog\n\n## 1.0.1\n\n- Update thing to v2\n\n## 1.0.0\n"
        )
        assert 'version: "1.0.0"' in (repo / "beta" / "config.yaml").read_text()
        git(repo, "commit", "-qam", "bump")
        assert self.bump(repo) == ""
