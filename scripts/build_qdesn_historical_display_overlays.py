#!/usr/bin/env python3
"""Reproduce two explicitly label-only historical/uncertainty TeX overlays.

The original sources are pinned and untouched. The historical comparison is
not relabeled as a fitted current MQ–DESN model. Numbers, table rows, labels,
uncertainty statements, and non-equivalence context are preserved.
No fitting, forecast generation, rescoring, network, or runtime access occurs.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import tempfile


MANIFEST = Path("tables/qdesn_historical_display_manifest.json")
CONTRACTS = (
    {
        "role": "historical_multiquantile_sensitivity",
        "source": "tables/joint_qdesn_article_validation_phase153_replication_summary.tex",
        "source_sha256": "f2768de0639f82bbdfdc805ef068e68621e44f01c3c24711a92f25e2e155a19d",
        "output": "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex",
        "source_data_rows": 8,
        "replacements": (
            ("Joint: AL-exAL", r"\shortstack{Historical multiquantile\\AL--exAL}"),
            (r"\caption{Replicated VB comparison", r"\caption{Historical replicated VB comparison"),
        ),
    },
    {
        "role": "independent_metric_uncertainty_description",
        "source": "tables/qdesn_validation_500obs_metric_dependence_sensitivity.tex",
        "source_sha256": "74c165ad4b29f00808e058750d8f6a320b5454f97ae7133d1260ae9794d5ee2b",
        "output": "tables/qdesn_validation_500obs_metric_dependence_sensitivity_display.tex",
        "source_data_rows": 0,
        "replacements": (("For Q--DESN and exQ--DESN", "For Q--DESN under AL and exAL"),),
    },
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def numbers(text: str) -> Counter:
    return Counter(re.findall(r"[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", text))


def mapped_source(source: str, contract: dict) -> str:
    derivative = source
    for old, new in contract["replacements"]:
        assert derivative.count(old) == 1 and new not in derivative, "The exact old wording changed or is ambiguous."
        derivative = derivative.replace(old, new, 1)
    restored = derivative
    for old, new in reversed(contract["replacements"]):
        assert restored.count(new) == 1, "Mapped wording was lost or duplicated."
        restored = restored.replace(new, old, 1)
    assert restored == source, "Non-label content changed."
    assert numbers(derivative) == numbers(source), "A numerical token changed."
    return derivative


def build(root: Path, output_root: Path) -> dict:
    assets = []
    for contract in CONTRACTS:
        source_path = root / contract["source"]
        assert sha(source_path) == contract["source_sha256"], "Frozen source hash mismatch: " + contract["source"]
        source = source_path.read_text()
        if contract["source_data_rows"]:
            body = source.split(r"\midrule", 1)[1].split(r"\bottomrule", 1)[0]
            assert sum(" & " in row for row in body.splitlines()) == contract["source_data_rows"]
        derivative = mapped_source(source, contract)
        destination = output_root / contract["output"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(derivative)
        assert sha(source_path) == contract["source_sha256"], "Original source was modified."
        assets.append({
            "role": contract["role"], "source": contract["source"], "source_sha256": contract["source_sha256"],
            "output": contract["output"], "output_sha256": sha(destination),
            "replacements": [{"old": old, "new": new, "occurrences": 1} for old, new in contract["replacements"]],
            "all_non_replacement_bytes_unchanged": True, "numeric_tokens_unchanged": True,
            "source_data_rows": contract["source_data_rows"],
        })
    return {
        "schema": "qdesn-historical-display-overlay-v1",
        "purpose": "Historical qualifier and independent AL/exAL display names only; no current-target equivalence or new result.",
        "generator": "scripts/build_qdesn_historical_display_overlays.py", "generator_sha256": sha(Path(__file__)),
        "assets": assets, "new_model_runs": 0, "scores_recomputed": 0,
    }


def check(root: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix="qdesn-historical-display-proof-") as temporary:
        output_root = Path(temporary)
        manifest = build(root, output_root)
        assert (root / MANIFEST).read_bytes() == manifest_bytes(manifest), "Historical display receipt differs from a fresh proof."
        for asset in manifest["assets"]:
            relative = asset["output"]
            assert (root / relative).read_bytes() == (output_root / relative).read_bytes(), \
                "Historical display differs from its exact source mapping: " + relative
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify in a temporary directory without modifying repository files.")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.check:
        manifest = check(root)
        status = "PASS"
    else:
        manifest = build(root, root)
        (root / MANIFEST).write_bytes(manifest_bytes(manifest))
        status = "BUILT"
    print("QDESN_HISTORICAL_DISPLAY_CHECK=" + status)
    print(json.dumps({"status": status, "outputs": len(manifest["assets"]),
                      "new_model_runs": 0, "scores_recomputed": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
