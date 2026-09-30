#!/usr/bin/env python3
"""Score-blind fitted-function audit of the R122 750/1,000-cap panel."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r122_engine import paired_cap_predictive_stability


DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
PREP_TAG = "pricefm_stage_r122_stage0a_convergence_calibration_20260929"
TAG = "pricefm_stage_r122_stage0a_predictive_stability_audit_20260930"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--prep-dir", type=Path)
    value.add_argument("--output-dir", type=Path)
    return value


def run(args: argparse.Namespace) -> dict[str, object]:
    data = args.artifact_repo.resolve() / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / PREP_TAG).resolve()
    output = (args.output_dir or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = pd.read_csv(prep / "contract_manifest.csv")
    if set(manifest.cap.astype(int)) != {750, 1000}:
        raise RuntimeError("R122 paired-cap audit requires both frozen caps")

    records: list[dict[str, object]] = []
    source_rows: list[dict[str, object]] = []
    keys = ["candidate_id", "split", "tau"]
    for key, group in manifest.groupby(keys, sort=True):
        by_cap = {int(row.cap): row for row in group.itertuples(index=False)}
        if set(by_cap) != {750, 1000}:
            raise RuntimeError(f"incomplete paired-cap atom: {key}")
        contracts = {cap: json.loads(Path(row.contract).read_text()) for cap, row in by_cap.items()}
        if contracts[750]["posterior_target_sha256"] != contracts[1000]["posterior_target_sha256"]:
            raise RuntimeError(f"posterior target changed across caps: {key}")
        result = paired_cap_predictive_stability(
            Path(contracts[1000]["design_dir"]),
            Path(contracts[750]["output_dir"]),
            Path(contracts[1000]["output_dir"]),
        )
        records.append({"candidate_id": key[0], "split": int(key[1]), "tau": float(key[2]), **result})
        for cap, row in by_cap.items():
            for role, path in (("contract", Path(row.contract)),
                               ("terminal", Path(row.output_dir) / "terminal.json"),
                               ("diagnostics", Path(row.output_dir) / "diagnostics.json"),
                               ("beta_mean", Path(row.output_dir) / "beta_mean.bin"),
                               ("beta_cov", Path(row.output_dir) / "beta_cov.bin")):
                source_rows.append({"candidate_id": key[0], "split": int(key[1]), "tau": float(key[2]),
                                    "cap": cap, "role": role, "path": str(path), "sha256": sha256_file(path)})
        design_dir = Path(contracts[1000]["design_dir"])
        for name in ("design.json", "terminal.json", "X.bin", "y.bin"):
            path = design_dir / name
            source_rows.append({"candidate_id": key[0], "split": int(key[1]), "tau": float(key[2]),
                                "cap": 0, "role": f"training_design_{name}", "path": str(path), "sha256": sha256_file(path)})

    metrics = pd.DataFrame(records)
    metrics.to_csv(output / "paired_cap_metrics.csv", index=False)
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)
    passed = bool(metrics.passed.all())
    decision = {
        "stage": "R122_stage0A_predictive_stability_audit", "tag": TAG,
        "status": "R122_STAGE0A_PREDICTIVE_STABILITY_PASS" if passed else "R122_STAGE0A_PREDICTIVE_STABILITY_FAIL",
        "passed": passed, "frozen_final_cap": 1000 if passed else None,
        "policy": "paired_cap_fitted_function_gate_v1",
        "raw_absolute_coefficient_gate_replaced": False,
        "interpretation": "paired-cap evidence may rescue only an atom that fails the raw coefficient gate while preserving sigma, ELBO, posterior-target, location-map, and readout-uncertainty stability",
        "score_opened": False, "test_opened": False, "selection_performed": False,
        "article_mutated": False, "registry_mutated": False,
        "atom_count": int(len(metrics)), "pair_count_passing": int(metrics.passed.sum()),
        "output_sha256": {"paired_cap_metrics.csv": sha256_file(output / "paired_cap_metrics.csv"),
                          "source_manifest.csv": sha256_file(output / "source_manifest.csv")},
    }
    write_json(output / "decision.json", decision)
    columns = ["candidate_id", "split", "tau", "beta_delta_l2", "location_delta_rms_response_scale",
               "readout_sd_delta_rms_response_scale", "near_null_beta_delta_fraction", "passed"]
    table = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in metrics[columns].itertuples(index=False, name=None):
        table.append("| " + " | ".join(f"{value:.8g}" if isinstance(value, float) else str(value) for value in row) + " |")
    report = ["# PriceFM R122 Stage-0A predictive-stability audit", "",
              f"Status: `{decision['status']}`", "",
              "This audit uses only frozen training designs and paired 750/1,000-iteration VB outputs. It opens no validation or test score.", "",
              "The raw absolute coefficient criterion remains recorded. A failed raw criterion is accepted only when both caps share the exact posterior target and the fitted location and uncertainty maps are stable on the training design.", "",
              *table, ""]
    (output / "audit_report.md").write_text("\n".join(report))
    write_json(output / "terminal.json", {**decision, "audit_report_sha256": sha256_file(output / "audit_report.md")})
    return decision


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
