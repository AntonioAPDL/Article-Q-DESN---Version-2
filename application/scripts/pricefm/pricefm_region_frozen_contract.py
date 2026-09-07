#!/usr/bin/env python3
"""Shared contracts for region-frozen PriceFM calibration workflows."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any, Iterable, Mapping, Sequence


PAPER_QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
PRETEST_FIREWALL_FIELDS = (
    "test_opened",
    "test_access_authorized",
)
MUTATION_FIREWALL_FIELDS = (
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)
BINARY_MODEL_SUFFIXES = {".rds", ".rda", ".rdata"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: str | Path) -> str:
    path = Path(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(payload: Any) -> str:
    encoded = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii")
    return hashlib.sha256(encoded).hexdigest()


def atomic_write_json(path: str | Path, payload: Any) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def validate_pretest_firewall(payload: Mapping[str, Any], *, label: str) -> None:
    missing = [name for name in PRETEST_FIREWALL_FIELDS if name not in payload]
    if missing:
        raise RuntimeError(f"{label} omits pre-test firewall fields: {missing}")
    opened = payload["test_opened"]
    authorized = payload["test_access_authorized"]
    if opened is not False or authorized is not False:
        raise RuntimeError(
            f"{label} violates the pre-test firewall: "
            f"test_opened={opened!r}, test_access_authorized={authorized!r}"
        )


def validate_mutation_firewall(payload: Mapping[str, Any], *, label: str) -> None:
    missing = [name for name in MUTATION_FIREWALL_FIELDS if name not in payload]
    if missing:
        raise RuntimeError(f"{label} omits mutation firewall fields: {missing}")
    changed = [name for name in MUTATION_FIREWALL_FIELDS if payload[name] is not False]
    if changed:
        raise RuntimeError(f"{label} authorizes blocked actions: {changed}")


def validate_quantiles(values: Sequence[Any], *, label: str = "quantiles") -> None:
    observed = tuple(float(value) for value in values)
    if observed != PAPER_QUANTILES:
        raise RuntimeError(f"{label} must equal {PAPER_QUANTILES}; observed {observed}")


def validate_no_test_adapter(adapter: str | Path) -> None:
    adapter = Path(adapter)
    forbidden = [
        adapter / name
        for name in ("X_test.csv", "y_test.csv", "rows_test.csv")
        if (adapter / name).exists()
    ]
    if forbidden:
        raise RuntimeError(f"pre-test adapter contains test artifacts: {forbidden}")


def file_record(path: str | Path, role: str) -> dict[str, Any]:
    path = Path(path).resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "path": str(path),
        "role": role,
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }


def verify_file_record(record: Mapping[str, Any], *, label: str = "source") -> Path:
    path = Path(str(record["path"]))
    if not path.is_file():
        raise FileNotFoundError(path)
    observed = sha256_file(path)
    if observed != str(record["sha256"]):
        raise RuntimeError(f"{label} hash changed: {path}")
    return path


def content_task_id(prefix: str, identity: Mapping[str, Any], length: int = 12) -> str:
    safe = re.sub(r"[^a-z0-9]+", "_", prefix.lower()).strip("_")
    return f"{safe}_{canonical_sha256(identity)[:length]}"


def quarantine_path(path: str | Path, quarantine_root: str | Path, reason: str) -> Path:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(path)
    quarantine_root = Path(quarantine_root)
    quarantine_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    safe_reason = re.sub(r"[^A-Za-z0-9_.-]+", "_", reason).strip("_")[:80]
    destination = quarantine_root / f"{path.name}.{stamp}.{safe_reason}"
    counter = 1
    while destination.exists():
        destination = quarantine_root / f"{path.name}.{stamp}.{safe_reason}.{counter}"
        counter += 1
    path.rename(destination)
    return destination


def prepare_empty_directory(
    path: str | Path,
    *,
    quarantine_root: str | Path,
    reason: str,
    allow_quarantine: bool,
) -> tuple[Path, Path | None]:
    path = Path(path).resolve()
    quarantined = None
    if path.exists() and any(path.iterdir()):
        if not allow_quarantine:
            raise FileExistsError(path)
        quarantined = quarantine_path(path, quarantine_root, reason)
    path.mkdir(parents=True, exist_ok=True)
    return path, quarantined


def binary_artifacts(root: str | Path) -> list[Path]:
    root = Path(root)
    return sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in BINARY_MODEL_SUFFIXES
    )


@dataclass(frozen=True)
class GitIdentity:
    worktree: str
    branch: str
    head: str
    upstream: str
    upstream_head: str
    clean: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "worktree": self.worktree,
            "branch": self.branch,
            "head": self.head,
            "upstream": self.upstream,
            "upstream_head": self.upstream_head,
            "clean": self.clean,
        }


def _git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=root, text=True, stderr=subprocess.STDOUT
    ).strip()


def git_identity(root: str | Path) -> GitIdentity:
    root = Path(root).resolve()
    branch = _git(root, "branch", "--show-current")
    head = _git(root, "rev-parse", "HEAD")
    upstream = _git(root, "rev-parse", "--abbrev-ref", "@{upstream}")
    upstream_head = _git(root, "rev-parse", "@{upstream}")
    status = _git(root, "status", "--porcelain=v1", "--untracked-files=normal")
    return GitIdentity(
        worktree=str(root), branch=branch, head=head, upstream=upstream,
        upstream_head=upstream_head, clean=not bool(status),
    )


def validate_git_identity(
    root: str | Path,
    expected: Mapping[str, Any],
    *,
    require_clean: bool = True,
) -> GitIdentity:
    observed = git_identity(root)
    checks = {
        "branch": observed.branch == str(expected["branch"]),
        "head": observed.head == str(expected["head"]),
        "upstream": observed.upstream == str(expected["upstream"]),
        "upstream_head": observed.upstream_head == str(expected["upstream_head"]),
        "synchronized": observed.head == observed.upstream_head,
        "clean": observed.clean or not require_clean,
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise RuntimeError(f"Git launch identity mismatch ({failed}): {observed.to_dict()}")
    return observed


def verify_records(records: Iterable[Mapping[str, Any]], *, label: str) -> None:
    for record in records:
        verify_file_record(record, label=label)


def copy_file_verified(source: str | Path, destination: str | Path) -> dict[str, Any]:
    source, destination = Path(source), Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if sha256_file(source) != sha256_file(destination):
        raise RuntimeError(f"copy verification failed: {source} -> {destination}")
    return file_record(destination, "frozen_copy")
