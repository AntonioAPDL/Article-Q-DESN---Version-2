#!/usr/bin/env python3
"""Validate one committed, audited direct-Overleaf reconciliation contract.

Python 3.6 standard library only. The command accepts no contract override:
authorization comes from the fixed contract path at the exact source commit.
This checks reviewed provenance, not scientific result or submission approval.
"""

import argparse
import collections
import csv
import hashlib
import io
import json
import re
import subprocess
import sys


CONTRACT_PATH = "overleaf/reviewed_direct_reconciliation_20261030.json"
LEDGER_PATH = "docs/reproducibility/advisor_revision_resolution_20261029.csv"
DECISION = "publish_reviewed_advisor_revision_no_external_history_in_main"
FIELDS = {
    "schema", "decision", "canonical_snapshot", "direct_commit", "direct_tree",
    "direct_diff_sha256", "historical_main", "source_anchor",
    "source_article_inputs_sha256", "captured_review", "reviewed_article_paths",
    "extra_support_paths", "expected_added_paths", "expected_modified_paths",
    "resolution_ledger_path", "resolution_ledger_sha256", "resolution_status_counts",
}


class ReconciliationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReconciliationError(message)


def git_bytes(*args):
    try:
        return subprocess.check_output(["git"] + list(args), stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ReconciliationError("required Git evidence unavailable: {}".format(" ".join(args))) from error


def git_text(*args):
    try:
        return git_bytes(*args).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReconciliationError("Git evidence is not UTF-8") from error


def ancestor(older, newer):
    result = subprocess.call(["git", "merge-base", "--is-ancestor", older, newer],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    require(result in (0, 1), "cannot determine required commit ancestry")
    return result == 0


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "contract repeats a JSON key")
        result[key] = value
    return result


def valid_path(path):
    return (isinstance(path, str) and re.fullmatch(r"[A-Za-z0-9._/-]+", path) and
            not path.startswith("/") and all(part not in ("", ".", "..")
                                           for part in path.split("/")))


def entry(commit, path):
    require(valid_path(path), "unsafe evidence path")
    lines = git_text("ls-tree", commit, "--", path).splitlines()
    require(len(lines) == 1, "evidence path missing or ambiguous: {}".format(path))
    try:
        attributes, actual_path = lines[0].split("\t", 1)
        mode, kind, blob = attributes.split()
    except ValueError as error:
        raise ReconciliationError("invalid tree entry") from error
    require(actual_path == path and kind == "blob" and mode in ("100644", "100755"),
            "evidence is not the expected regular file: {}".format(path))
    return {"path": path, "mode": mode, "blob": blob}


def article_input_inventory(commit):
    manifest = git_text("show", commit + ":overleaf/article_files.txt")
    paths = [line for line in manifest.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    require(paths == sorted(set(paths)) and all(valid_path(path) for path in paths),
            "source article manifest is unsafe, duplicated or unsorted")
    require(all(path in paths for path in ("main.tex", "qdesn-supplement.tex", "refs.bib")),
            "source article manifest lacks required manuscripts")
    require(all(path in ("main.tex", "qdesn-supplement.tex", "refs.bib") or
                path.startswith(("tables/", "figures/")) for path in paths),
            "source article manifest contains a research path")
    paths += ["overleaf/article_files.txt", "overleaf/README.md", "overleaf/overleaf.gitignore"]
    return [entry(commit, path) for path in sorted(paths)]


def inventory_sha256(rows):
    return sha256(json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def load_contract(source):
    try:
        return json.loads(git_text("show", source + ":" + CONTRACT_PATH),
                          object_pairs_hook=unique_object)
    except (TypeError, ValueError) as error:
        raise ReconciliationError("committed reconciliation contract is invalid JSON") from error


def validate_contract(contract, source, canonical, direct, requested):
    require(isinstance(contract, dict) and set(contract) == FIELDS, "contract field set is invalid")
    require(type(contract["schema"]) is int and contract["schema"] == 1 and
            contract["decision"] == DECISION, "unsupported reconciliation contract")
    for key in ("canonical_snapshot", "direct_commit", "direct_tree", "historical_main",
                "source_anchor", "captured_review"):
        require(isinstance(contract[key], str) and re.fullmatch(r"[0-9a-f]{40}", contract[key]),
                "invalid contract commit/tree identity: " + key)
    for key in ("direct_diff_sha256", "source_article_inputs_sha256", "resolution_ledger_sha256"):
        require(isinstance(contract[key], str) and re.fullmatch(r"[0-9a-f]{64}", contract[key]),
                "invalid contract SHA-256: " + key)
    require(canonical == contract["canonical_snapshot"] and direct == contract["direct_commit"] and
            requested == direct, "publication references differ from the exact reviewed contract")
    require(contract["resolution_ledger_path"] == LEDGER_PATH, "unexpected disposition ledger")
    article_paths = contract["reviewed_article_paths"]
    require(isinstance(article_paths, list) and len(article_paths) == 3 and
            all(valid_path(path) for path in article_paths) and article_paths == sorted(set(article_paths)),
            "contract must identify exactly three reviewed article paths")
    require(contract["extra_support_paths"] == ["README.md"], "unexpected support-file disposition")
    for key in ("expected_added_paths", "expected_modified_paths"):
        require(type(contract[key]) is int and contract[key] > 0, "invalid expected diff count")
    require(contract["expected_modified_paths"] == len(article_paths) + 1,
            "modified-path count does not match reviewed dispositions")

    anchor = contract["source_anchor"]
    historical = contract["historical_main"]
    captured = contract["captured_review"]
    require(ancestor(anchor, source) and ancestor(historical, anchor),
            "source anchor or historical main is not in research authority ancestry")
    require(not ancestor(direct, source) and not ancestor(captured, source),
            "external Overleaf/review history entered research authority")
    anchor_inventory = article_input_inventory(anchor)
    source_inventory = article_input_inventory(source)
    require(source_inventory == anchor_inventory and
            inventory_sha256(source_inventory) == contract["source_article_inputs_sha256"],
            "article inputs changed since the reviewed source anchor")
    source_paths = {row["path"] for row in source_inventory}
    require(all(path in source_paths for path in article_paths), "reviewed edits are outside article projection")

    ledger_raw = git_bytes("show", source + ":" + LEDGER_PATH)
    require(ledger_raw == git_bytes("show", anchor + ":" + LEDGER_PATH) and
            sha256(ledger_raw) == contract["resolution_ledger_sha256"],
            "advisor disposition ledger changed or failed authentication")
    try:
        ledger_rows = list(csv.DictReader(io.StringIO(ledger_raw.decode("utf-8"))))
    except (UnicodeDecodeError, csv.Error) as error:
        raise ReconciliationError("cannot read advisor disposition ledger") from error
    require(ledger_rows and all(row.get("issue_id") and row.get("status") for row in ledger_rows),
            "advisor disposition ledger lacks issue/status fields")
    require(len({row["issue_id"] for row in ledger_rows}) == len(ledger_rows),
            "advisor disposition ledger repeats an issue")
    status_counts = contract["resolution_status_counts"]
    require(isinstance(status_counts, dict) and status_counts and
            all(isinstance(key, str) and type(value) is int and value > 0
                for key, value in status_counts.items()) and
            dict(collections.Counter(row["status"] for row in ledger_rows)) == status_counts,
            "advisor disposition counts differ from the reviewed ledger")

    parents = git_text("rev-list", "--parents", "-n", "1", direct).split()
    require(parents == [direct, canonical], "reviewed direct commit must have the exact sole canonical parent")
    require(git_text("rev-parse", direct + "^{tree}").strip() == contract["direct_tree"],
            "reviewed direct tree differs from contract")
    raw_diff = git_bytes("diff", "--raw", "--no-abbrev", "--no-renames", "--no-ext-diff",
                         "--no-textconv", canonical, direct)
    require(sha256(raw_diff) == contract["direct_diff_sha256"], "reviewed direct diff inventory changed")
    changes = git_text("diff", "--name-status", "--no-renames", "--no-ext-diff",
                       "--no-textconv", canonical, direct).splitlines()
    added = []
    modified = []
    for change in changes:
        fields = change.split("\t")
        require(len(fields) == 2 and fields[0] in ("A", "M") and valid_path(fields[1]),
                "unreviewed change kind or unsafe path in direct commit")
        (added if fields[0] == "A" else modified).append(fields[1])
    require(len(added) == contract["expected_added_paths"] and
            len(modified) == contract["expected_modified_paths"] and
            set(modified) == set(article_paths + ["README.md"]),
            "direct change surface differs from reviewed dispositions")
    for path in article_paths:
        require(entry(direct, path) == entry(captured, path),
                "unseen article edit differs from captured advisor review: " + path)
    for path in added + ["README.md"]:
        require(path not in source_paths, "research addition entered the article manifest")
        parts = path.lower().split("/")
        require(not any(part in ("local_trackers", "cache", "caches", "logs", "checkpoints")
                        for part in parts) and
                not path.lower().endswith((".rds", ".rda", ".rdata", ".log")),
                "runtime/generated payload appears in reviewed drift")
        require(entry(direct, path) == entry(historical, path),
                "nonarticle drift differs from authenticated historical research source: " + path)
    return {
        "reconciliation_direct_commit": direct,
        "reconciliation_reviewed_article_paths": len(article_paths),
        "reconciliation_historical_added_paths": len(added),
        "reconciliation_ledger_items": len(ledger_rows),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("source_commit", "canonical_commit", "direct_commit", "requested_direct"):
        parser.add_argument(argument)
    args = parser.parse_args()
    try:
        require(all(re.fullmatch(r"[0-9a-f]{40}", value) for value in vars(args).values()),
                "all reconciliation identities must be full lowercase commit hashes")
        result = validate_contract(load_contract(args.source_commit), args.source_commit,
                                   args.canonical_commit, args.direct_commit, args.requested_direct)
    except ReconciliationError as error:
        print("OVERLEAF_REVIEWED_RECONCILIATION_ERROR: {}".format(error), file=sys.stderr)
        return 1
    for key in sorted(result):
        print("{}={}".format(key, result[key]))
    print("OVERLEAF_REVIEWED_RECONCILIATION_CHECK=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
