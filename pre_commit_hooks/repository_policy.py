#!/usr/bin/env python3
#
# Copyright (c) 2026 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#
"""Enforce repository file policies not provided by Super-Linter."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
from dataclasses import dataclass
from pathlib import PurePosixPath

MAX_FILE_SIZE_KIB = 64
WINDOWS_ILLEGAL_NAME = re.compile(
    r"(?i)((^|/)(CON|PRN|AUX|NUL|COM[\d¹²³]|LPT[\d¹²³])"
    r"(\.|/|$)|[<>:\"\\|?*\x00-\x1F]|/[^/]*[\.\s]/|[^/]*[\.\s]$)",
)
TEXT_BYTES = frozenset(
    (7, 8, 9, 10, 11, 12, 13, 27),
) | frozenset(range(0x20, 0x100))
LFS_POINTER = re.compile(
    rb"\Aversion https://git-lfs.github.com/spec/v1\n"
    rb"(?:ext-[^\s]+ [^\n]+\n)*"
    rb"oid sha256:[0-9a-f]{64}\n"
    rb"size (?:0|[1-9][0-9]*)\n\Z",
)


@dataclass(frozen=True)
class TrackedFile:
    """A path and mode reported by the Git index."""

    mode: str
    object_id: str
    path: str

    @property
    def is_regular(self) -> bool:
        """Return whether the entry represents a regular tracked file."""
        return self.mode in {"100644", "100755"}

    @property
    def is_executable(self) -> bool:
        """Return whether Git records the executable bit for this file."""
        return self.mode == "100755"


def tracked_files() -> list[TrackedFile]:
    """Return files tracked by the current Git index."""
    result = subprocess.run(
        ("git", "ls-files", "-z", "--stage"),
        check=True,
        stdout=subprocess.PIPE,
    )
    entries: list[TrackedFile] = []
    for record in result.stdout.split(b"\0"):
        if not record:
            continue
        metadata, separator, encoded_path = record.partition(b"\t")
        if not separator:
            continue
        mode, object_id, _ = metadata.decode("ascii").split()
        entries.append(
            TrackedFile(
                mode,
                object_id,
                encoded_path.decode("utf-8", errors="surrogateescape"),
            ),
        )
    return entries


def lfs_paths(paths: list[str]) -> set[str]:
    """Return paths whose effective Git filter attribute is ``lfs``."""
    if not paths:
        return set()
    result = subprocess.run(
        ("git", "check-attr", "--cached", "filter", "-z", "--stdin"),
        check=True,
        input="\0".join(paths).encode("utf-8", errors="surrogateescape"),
        stdout=subprocess.PIPE,
    )
    fields = result.stdout.split(b"\0")
    filtered: set[str] = set()
    for index in range(0, len(fields) - 2, 3):
        path, _, value = fields[index : index + 3]
        if value == b"lfs":
            filtered.add(path.decode("utf-8", errors="surrogateescape"))
    return filtered


def added_paths(base_ref: str | None) -> set[str]:
    """Return files added to the index or since a CI base revision."""
    command = ["git", "diff", "--diff-filter=A", "--name-only", "-z"]
    if base_ref:
        command.append(f"{base_ref}...HEAD")
    else:
        command.append("--cached")
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE)
    return {
        path.decode("utf-8", errors="surrogateescape")
        for path in result.stdout.split(b"\0")
        if path
    }


def path_and_parents(path: str) -> set[str]:
    """Return a path and each of its repository-relative parent directories."""
    pure_path = PurePosixPath(path)
    parents = {
        parent.as_posix() for parent in pure_path.parents if parent.as_posix() != "."
    }
    return {path, *parents}


def case_conflict_violations(paths: list[str]) -> list[str]:
    """Report paths that collide on a case-insensitive filesystem."""
    all_paths = {candidate for path in paths for candidate in path_and_parents(path)}
    by_lowercase: dict[str, list[str]] = {}
    for path in all_paths:
        by_lowercase.setdefault(path.lower(), []).append(path)
    return [
        f"Case-insensitivity conflict found: {path}"
        for paths_with_same_case in by_lowercase.values()
        if len(paths_with_same_case) > 1
        for path in sorted(paths_with_same_case)
    ]


def staged_blob(tracked_file: TrackedFile) -> bytes:
    """Return the content stored in the Git index for a tracked file."""
    result = subprocess.run(
        ("git", "cat-file", "blob", tracked_file.object_id),
        check=True,
        stdout=subprocess.PIPE,
    )
    return result.stdout


def is_valid_lfs_content(content: bytes) -> bool:
    """Return whether staged content is empty or a complete Git LFS v1 pointer."""
    return content == b"" or (
        len(content) < 1024
        and not is_binary(content)
        and LFS_POINTER.fullmatch(content) is not None
    )


def is_binary(content: bytes) -> bool:
    """Use the same first-KiB text heuristic as pre-commit's identify library."""
    return any(byte not in TEXT_BYTES for byte in content[:1024])


def has_shebang(content: bytes) -> bool:
    """Return whether a file starts with the shebang marker."""
    return content.startswith(b"#!")


def content_violations(
    files: list[TrackedFile],
    lfs_tracked_paths: set[str],
    newly_added_paths: set[str],
) -> list[str]:
    """Check size, executable metadata, and binary storage policy."""
    violations: list[str] = []
    for tracked_file in files:
        if not tracked_file.is_regular:
            continue
        content = staged_blob(tracked_file)
        has_lfs_attribute = tracked_file.path in lfs_tracked_paths
        is_lfs = has_lfs_attribute and is_valid_lfs_content(content)
        if has_lfs_attribute and not is_lfs:
            violations.append(
                f"{tracked_file.path} is marked for LFS but its staged blob is not "
                "an LFS pointer",
            )
        size_kib = math.ceil(len(content) / 1024)
        if (
            not is_lfs
            and tracked_file.path in newly_added_paths
            and PurePosixPath(tracked_file.path).suffix != ".pkb"
            and size_kib > MAX_FILE_SIZE_KIB
        ):
            violations.append(
                f"{tracked_file.path} ({size_kib} KB) exceeds "
                f"{MAX_FILE_SIZE_KIB} KB.",
            )
        if tracked_file.is_executable and not has_shebang(content):
            violations.append(
                f"{tracked_file.path}: marked executable but has no valid shebang",
            )
        if not is_lfs and is_binary(content):
            violations.append(
                f"{tracked_file.path} appears to be a non-LFS binary file",
            )
    return violations


def find_violations(base_ref: str | None = None) -> list[str]:
    """Return every repository policy violation in deterministic order."""
    files = tracked_files()
    paths = [tracked_file.path for tracked_file in files]
    violations = case_conflict_violations(paths)
    violations.extend(
        f"Illegal Windows filename: {path}"
        for path in paths
        if WINDOWS_ILLEGAL_NAME.search(path)
    )
    violations.extend(
        content_violations(files, lfs_paths(paths), added_paths(base_ref))
    )
    return sorted(set(violations))


def main() -> int:
    """Print violations and return a CI-friendly status code."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--added-since",
        metavar="REVISION",
        help="check file-size policy for files added since this revision",
    )
    arguments = parser.parse_args()
    violations = find_violations(arguments.added_since)
    if violations:
        print("\n".join(violations))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
