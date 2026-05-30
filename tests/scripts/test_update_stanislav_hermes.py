"""Regression tests for the local custom-branch updater script."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "update-stanislav-hermes.sh"
LOCAL_BRANCH = "stanislav/hermes-local-fixes"
BACKUP_GLOB = "backup/stanislav-hermes-local-fixes-pre-update-*"


def _run(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}"
        )
    return result


def _git(cwd: Path, *args: str) -> str:
    return _run(["git", "-C", str(cwd), *args]).stdout.strip()


def _bash_path(path: Path) -> str:
    return str(path).replace("\\", "/")


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _commit(cwd: Path, message: str) -> str:
    _git(cwd, "add", ".")
    _git(cwd, "commit", "-m", message)
    return _git(cwd, "rev-parse", "HEAD")


def _init_custom_update_fixture(tmp_path: Path) -> tuple[Path, Path, Path]:
    upstream_bare = tmp_path / "official.git"
    upstream_work = tmp_path / "official-work"
    fork_bare = tmp_path / "fork.git"
    work = tmp_path / "work"

    _run(["git", "init", "--bare", str(upstream_bare)])
    _run(
        [
            "git",
            "--git-dir",
            str(upstream_bare),
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
        ]
    )
    _run(["git", "init", "-b", "main", str(upstream_work)])
    _git(upstream_work, "config", "user.name", "Test User")
    _git(upstream_work, "config", "user.email", "test@example.invalid")
    _write(upstream_work / "app.txt", "base\n")
    _commit(upstream_work, "base")
    _git(upstream_work, "remote", "add", "origin", upstream_bare.as_uri())
    _git(upstream_work, "push", "-u", "origin", "main")

    _run(["git", "init", "--bare", str(fork_bare)])
    _run(
        [
            "git",
            "--git-dir",
            str(fork_bare),
            "symbolic-ref",
            "HEAD",
            f"refs/heads/{LOCAL_BRANCH}",
        ]
    )

    _run(["git", "clone", "--branch", "main", upstream_bare.as_uri(), str(work)])
    _git(work, "config", "user.name", "Test User")
    _git(work, "config", "user.email", "test@example.invalid")
    _git(work, "remote", "add", "stanislav", fork_bare.as_uri())
    _git(work, "switch", "-c", LOCAL_BRANCH)
    _write(work / "app.txt", "custom local change\n")
    _commit(work, "custom local change")
    _git(work, "push", "-u", "stanislav", LOCAL_BRANCH)

    _write(upstream_work / "app.txt", "upstream change\n")
    _commit(upstream_work, "upstream conflicting change")
    _git(upstream_work, "push", "origin", "main")

    return work, upstream_bare, fork_bare


def test_custom_update_conflict_creates_backup_before_failed_merge(tmp_path: Path):
    bash = shutil.which("bash")
    if not bash:
        pytest.skip("bash is required for update-stanislav-hermes.sh")

    work, upstream_bare, fork_bare = _init_custom_update_fixture(tmp_path)
    pre_merge_sha = _git(work, "rev-parse", "HEAD")

    env = os.environ.copy()
    env.update(
        {
            "HERMES_REPO": _bash_path(work),
            "HERMES_UPSTREAM_REMOTE": "origin",
            "HERMES_UPSTREAM_BRANCH": "main",
            "HERMES_LOCAL_BRANCH": LOCAL_BRANCH,
            "HERMES_FORK_REMOTE": "stanislav",
            "HERMES_FORK_URL": fork_bare.as_uri(),
            "HERMES_OFFICIAL_URL": upstream_bare.as_uri(),
            "GIT_TERMINAL_PROMPT": "0",
        }
    )

    result = subprocess.run(
        [bash, str(SCRIPT), "--yes", "--no-tests"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )

    assert result.returncode == 20, result.stdout
    assert "Merge conflict" in result.stdout
    assert "Pre-merge backup branch:" in result.stdout
    assert (work / ".git" / "MERGE_HEAD").exists()
    assert _git(work, "rev-parse", "HEAD") == pre_merge_sha

    local_backups = _git(
        work,
        "for-each-ref",
        "--format=%(refname:short)",
        f"refs/heads/{BACKUP_GLOB}",
    ).splitlines()
    assert len(local_backups) == 1
    backup_branch = local_backups[0]
    assert _git(work, "rev-parse", backup_branch) == pre_merge_sha

    remote_output = _git(work, "ls-remote", "--heads", "stanislav", BACKUP_GLOB)
    assert pre_merge_sha in remote_output
    assert backup_branch in remote_output
