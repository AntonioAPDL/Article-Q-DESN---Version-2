#!/usr/bin/env python3
"""Refresh three shared document pins after an approved GloFAS-only revision.

Preserves every IND scientific source/output and the previous editorial receipt.
Python 3.6 standard library. No model, forecast, original truth or remote access.
"""
import argparse
import copy
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile


BASELINE = "0d111e0c2bf3951378aec2bbfc1f46fd9ecd8437"
BASELINE_RECEIPT_SHA256 = "0e319eb1731c459701e97738b04c23ef0a8ed82655bc0b45f94d6458e04e3e16"
RECEIPT = "tables/independent_forecast_300_500_article_manifest_v1.json"
REFRESHER = "scripts/refresh_glofas_article_shared_receipts.py"
AUTHORITY = "tables/glofas_same_family_current_authority.json"
MUTABLE = ("main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt")
FIELD = "glofas_article_source_refresh"
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class RefreshError(Exception):
    pass


def require(ok, why):
    if not ok:
        raise RefreshError("GLOFAS_SHARED_RECEIPT_INVALID: " + why)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def decode_json(raw, label):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, "duplicate JSON field in " + label)
            value[key] = item
        return value
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError):
        raise RefreshError("GLOFAS_SHARED_RECEIPT_INVALID: invalid JSON in " + label)
    require(isinstance(value, dict), "object JSON required: " + label)
    return value


def regular_bytes(root, relative, limit=32 * 1024 * 1024):
    require(isinstance(relative, str) and relative and "\\" not in relative and
            not PurePosixPath(relative).is_absolute() and
            all(part not in ("", ".", "..") for part in relative.split("/")), "safe relative source role required")
    path = root / relative
    require(path.is_file() and not any(p.is_symlink() for p in (path, *path.parents)) and
            0 < path.stat().st_size <= limit, "bounded regular source role required: " + relative)
    return path.read_bytes()


def verify_allowlist(baseline, current, additions):
    require(isinstance(additions, set) and len(additions) == 21, "exact twenty-one reviewed GloFAS additions required")
    try:
        before = baseline.decode("utf-8").splitlines(keepends=True)
        after = current.decode("utf-8").splitlines(keepends=True)
    except UnicodeDecodeError:
        raise RefreshError("GLOFAS_SHARED_RECEIPT_INVALID: UTF-8 allowlist required")
    def paths(lines):
        result = []
        for line in lines:
            value = line.rstrip("\r\n")
            if not value or value.startswith("#"):
                continue
            require(value == value.strip(), "allowlist path whitespace changed")
            require(not value.startswith("/") and "\\" not in value and
                    all(part not in ("", ".", "..") for part in value.split("/")), "unsafe allowlist path")
            result.append(value)
        require(len(result) == len(set(result)) and result == sorted(result), "allowlist must be sorted and unique")
        return result
    old_paths = paths(before); new_paths = paths(after)
    require(set(old_paths).isdisjoint(additions) and set(new_paths) - set(old_paths) == additions and
            set(old_paths) <= set(new_paths), "allowlist changes exceed the exact approved GloFAS additions")
    retained = [line for line in after if line.rstrip("\r\n") not in additions]
    require(retained == before, "original allowlist entries/comments/order/bytes changed")
    return sorted(additions)


def provenance(baseline, updated, context):
    return {
        "schema": "glofas-article-shared-source-refresh-v1",
        "baseline_commit": BASELINE, "original_manifest_sha256": BASELINE_RECEIPT_SHA256,
        "updated_paths": list(MUTABLE),
        "original_source_sha256": {path: baseline["sources"][path] for path in MUTABLE},
        "updated_source_sha256": {path: updated[path] for path in MUTABLE},
        "overleaf_added_paths": context["added_paths"],
        "authority_contract_sha256": context["authority_sha256"],
        "asset_manifest_sha256": context["asset_manifest_sha256"],
        "scored_packet_manifest_sha256": context["scored_packet_manifest_sha256"],
        "producer_source_commit": context["producer_source_commit"],
        "refresher": REFRESHER, "refresher_sha256": context["refresher_sha256"],
        "scientific_outputs_regenerated": False, "scientific_values_changed": False,
        "fits_launched": 0, "forecasts_launched": 0,
    }


def build_refresh_plan(baseline, current, hash_file, context):
    """Pure exact-scope receipt algebra; production inputs are fixed Git pins."""
    require(baseline.get("schema") == "independent-forecast-300-500-article-v1" and
            baseline.get("authority_id") == "independent_forecast_300_primary_500_sensitivity_v1" and
            all(path in baseline.get("sources", {}) for path in MUTABLE), "original reporting schema and document roles")
    require(set(current) - {FIELD} == set(baseline), "only named GloFAS editorial field may be added")
    restored = copy.deepcopy(current); previous = restored.pop(FIELD, None)
    for path in MUTABLE:
        restored["sources"][path] = baseline["sources"][path]
    require(restored == baseline, "noneditorial sources/outputs/policy or historical editorial receipt changed")
    for group in ("sources", "outputs"):
        for path, expected in baseline[group].items():
            if group == "sources" and path in MUTABLE:
                continue
            require(hash_file(path) == expected, "immutable scientific/source/output digest differs: " + path)
    for key in ("authority_sha256", "asset_manifest_sha256", "scored_packet_manifest_sha256", "refresher_sha256"):
        require(isinstance(context.get(key), str) and SHA256.fullmatch(context[key]) is not None,
                "complete reviewed context hash required: " + key)
    require(context.get("producer_source_commit") == "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6" and
            isinstance(context.get("added_paths"), list) and len(context["added_paths"]) == 21 and
            context["added_paths"] == sorted(set(context["added_paths"])), "exact reviewed source and added-path context required")
    if previous is not None:
        # A repeat may refresh document hashes or reviewed presentation assets,
        # but cannot use previous metadata to widen scientific permissions.
        old_context = dict(context)
        for key, field in (("authority_sha256", "authority_contract_sha256"),
                           ("asset_manifest_sha256", "asset_manifest_sha256"),
                           ("scored_packet_manifest_sha256", "scored_packet_manifest_sha256")):
            value = previous.get(field)
            require(isinstance(value, str) and SHA256.fullmatch(value) is not None, "previous reviewed context hash differs")
            old_context[key] = value
        require(previous == provenance(baseline, current["sources"], old_context),
                "previous GloFAS refresh is outside its exact three-file scope")
    actual = {path: hash_file(path) for path in MUTABLE}
    require(all(isinstance(value, str) and SHA256.fullmatch(value) is not None for value in actual.values()),
            "complete current document digests required")
    result = copy.deepcopy(baseline)
    result["sources"].update(actual)
    result[FIELD] = provenance(baseline, actual, context)
    require(result.get("editorial_source_refresh") == baseline.get("editorial_source_refresh"),
            "historical editorial provenance must remain unchanged")
    return result


def git(root, args):
    try:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root)] + args,
                                       stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError):
        raise RefreshError("GLOFAS_SHARED_RECEIPT_INVALID: fixed Git baseline or ancestry unavailable")


def prepare(root):
    root = Path(root).absolute()
    require(root.is_dir() and not any(path.is_symlink() for path in (root, *root.parents)), "regular repository root required")
    for tip in ("HEAD", "refs/remotes/origin/main"):
        git(root, ["merge-base", "--is-ancestor", BASELINE, tip])
    original = git(root, ["show", BASELINE + ":" + RECEIPT])
    require(sha(original) == BASELINE_RECEIPT_SHA256, "exact original shared receipt bytes differ")
    baseline = decode_json(original, "baseline")
    current_raw = regular_bytes(root, RECEIPT, 1024 * 1024)
    current = decode_json(current_raw, "current receipt")
    helper = root / "scripts/glofas_current_article_authority.py"
    require(helper.is_file() and not helper.is_symlink(), "current GloFAS authority validator required")
    spec = importlib.util.spec_from_file_location("glofas_shared_receipt_authority", str(helper))
    module = importlib.util.module_from_spec(spec); sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    authority = module.validate_authority_tree(root)
    closure = module.authority_dependency_paths(root)
    old_allowlist = git(root, ["show", BASELINE + ":overleaf/article_files.txt"])
    require(sha(old_allowlist) == baseline["sources"]["overleaf/article_files.txt"], "original allowlist pin differs")
    manifest_path = authority["asset_manifest"]["relative_path"]
    manifest_raw = regular_bytes(root, manifest_path, 1024 * 1024)
    require(sha(manifest_raw) == authority["asset_manifest"]["sha256"], "reviewed asset manifest changed")
    entries = list(csv.DictReader(io.StringIO(manifest_raw.decode("utf-8"))))
    additions = {row["relative_path"] for row in entries} | {AUTHORITY, manifest_path}
    added_paths = verify_allowlist(old_allowlist, regular_bytes(root, "overleaf/article_files.txt", 1024 * 1024), additions)
    hash_file = lambda path: sha(regular_bytes(root, path))
    context = {"added_paths": added_paths, "authority_sha256": hash_file(AUTHORITY),
               "asset_manifest_sha256": authority["asset_manifest"]["sha256"],
               "scored_packet_manifest_sha256": authority["scored_packet_manifest_sha256"],
               "producer_source_commit": authority["producer_source_commit"], "refresher_sha256": hash_file(REFRESHER)}
    result = build_refresh_plan(baseline, current, hash_file, context)
    watched = set(baseline["sources"]) | set(baseline["outputs"]) | closure | {RECEIPT, REFRESHER}
    fingerprints = {path: hash_file(path) for path in watched}
    require(fingerprints[RECEIPT] == sha(current_raw), "shared receipt changed during planning")
    return root, current, result, fingerprints


def refresh(root, write=False):
    root, current, result, fingerprints = prepare(root)
    for path, expected in fingerprints.items():
        require(sha(regular_bytes(root, path)) == expected, "source changed during shared-receipt verification")
    if write:
        output = root / RECEIPT
        data = (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".glofas_shared_receipt_", dir=str(output.parent), delete=False) as stream:
                temporary = stream.name; stream.write(data); stream.flush(); os.fsync(stream.fileno())
            os.replace(temporary, str(output)); temporary = None
        finally:
            if temporary is not None and os.path.exists(temporary):
                os.unlink(temporary)
        require(decode_json(regular_bytes(root, RECEIPT, 1024 * 1024), "written receipt") == result,
                "atomic receipt readback differs")
    else:
        require(current == result, "live shared document metadata needs --refresh")
    print("GLOFAS_SHARED_ARTICLE_RECEIPT_{} updated_paths=3 scientific_files_regenerated=0 fits_launched=0 forecasts_launched=0".format(
        "REFRESHED" if write else "CHECK_PASS"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    try:
        refresh(args.root, write=args.refresh)
    except Exception as error:
        print("GLOFAS_SHARED_ARTICLE_RECEIPT_ERROR: {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
