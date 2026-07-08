#!/usr/bin/env python3
#
# Copyright (c) 2026 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#
"""Tests for the repository policy checker."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECKER = (
    Path(__file__).resolve().parents[1] / "pre_commit_hooks" / "repository_policy.py"
)


class _TemporaryRepository:
    """Create a minimal Git repository for an integration test."""

    def __init__(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.path = Path(self._temporary_directory.name)
        self.git("init", "--quiet")
        self.git("config", "core.fileMode", "true")
        self.git("config", "core.ignoreCase", "false")
        self.git("config", "commit.gpgSign", "false")
        self.git("config", "user.email", "repository-policy@example.invalid")
        self.git("config", "user.name", "Repository Policy Test")

    def close(self) -> None:
        self._temporary_directory.cleanup()

    def git(self, *arguments: str, input_text: str | None = None) -> str:
        result = subprocess.run(
            ("git", *arguments),
            cwd=self.path,
            check=True,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
        )
        return result.stdout.strip()

    def add_file(
        self,
        relative_path: str,
        contents: bytes,
        *,
        executable: bool = False,
    ) -> Path:
        path = self.path / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        if executable:
            path.chmod(0o755)
        self.git("add", "--", relative_path)
        return path

    def run_checker(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            (sys.executable, os.fspath(CHECKER), *arguments),
            cwd=self.path,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def commit(self) -> None:
        self.git("commit", "--quiet", "--message", "test fixture")


class _RepositoryPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = _TemporaryRepository()

    def tearDown(self) -> None:
        self.repository.close()

    def assert_policy_failure(self, expected_message: str) -> None:
        result = self.repository.run_checker()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(expected_message, result.stdout)

    def test_accepts_compliant_files(self) -> None:
        self.repository.add_file("README.md", b"Compliant repository\n")
        self.repository.add_file(
            "scripts/example.sh",
            b"#!/usr/bin/env bash\necho ok\n",
            executable=True,
        )

        result = self.repository.run_checker()

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_rejects_file_larger_than_64_kib(self) -> None:
        self.repository.add_file("large.txt", b"x" * (64 * 1024 + 1))

        self.assert_policy_failure("large.txt (65 KB) exceeds 64 KB")

    def test_accepts_preexisting_large_file(self) -> None:
        self.repository.add_file("large.txt", b"x" * (64 * 1024 + 1))
        self.repository.commit()

        result = self.repository.run_checker()

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_rejects_committed_large_file_added_since_base(self) -> None:
        self.repository.add_file("README", b"base\n")
        self.repository.commit()
        base_revision = self.repository.git("rev-parse", "HEAD")
        self.repository.add_file("large.txt", b"x" * (64 * 1024 + 1))
        self.repository.commit()

        result = self.repository.run_checker("--added-since", base_revision)

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("large.txt (65 KB) exceeds 64 KB", result.stdout)

    def test_accepts_large_package_body(self) -> None:
        self.repository.add_file("package.pkb", b"x" * (64 * 1024 + 1))

        result = self.repository.run_checker()

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_accepts_large_lfs_file(self) -> None:
        self.repository.add_file("image.bin", b"\x00" * (64 * 1024 + 1))
        self.repository.add_file(
            ".gitattributes",
            b"*.bin filter=lfs diff=lfs merge=lfs -text\n",
        )

        result = self.repository.run_checker()

        self.assertEqual(result.returncode, 0, result.stdout)

    def test_rejects_case_conflicting_paths(self) -> None:
        first_path = self.repository.add_file("README", b"first\n")
        blob = self.repository.git("hash-object", "-w", os.fspath(first_path))
        self.repository.git(
            "update-index",
            "--add",
            "--cacheinfo",
            f"100644,{blob},readme",
        )

        self.assert_policy_failure("Case-insensitivity conflict found: README")

    def test_rejects_illegal_windows_filename(self) -> None:
        self.repository.add_file("docs/AUX.txt", b"reserved name\n")

        self.assert_policy_failure("Illegal Windows filename: docs/AUX.txt")

    def test_rejects_executable_without_shebang(self) -> None:
        self.repository.add_file(
            "scripts/example.sh",
            b"echo missing shebang\n",
            executable=True,
        )

        self.assert_policy_failure(
            "scripts/example.sh: marked executable but has no valid shebang",
        )

    def test_rejects_non_lfs_binary(self) -> None:
        self.repository.add_file("payload.bin", b"binary\x00payload")

        self.assert_policy_failure(
            "payload.bin appears to be a non-LFS binary file",
        )


if __name__ == "__main__":
    unittest.main()
