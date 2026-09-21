#!/usr/bin/env python3
"""Cache frozen PriceFM validation quantiles needed by the R108 driver audit."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import numpy as np

from pricefm_common import load_config, pricefm_block, sha256_file


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
OUTPUT_TAG = "pricefm_stage_r108_pricefm_validation_driver_cache_20260920"
COMPLETE_REGIONS = ("AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES")
MODEL_SHA256 = "387f1ba06dc42235d23267d0b2228225e33efffb20aeca9c94094f9fef4d19a5"
PRICEFM_COMMIT = "c72d1228bde80417d5cc782521328e02ab5401c3"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "diagnostics" / OUTPUT_TAG,
    )
    value.add_argument("--batch-size", type=int, default=128)
    value.add_argument("--force", action="store_true")
    return value


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load script: {}".format(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")


def git_head(path: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def required_regions(data_root: Path) -> list[str]:
    result: set[str] = set()
    for region in COMPLETE_REGIONS:
        config_path = (
            data_root / "launch_prep" / R103_TAG / "cases"
            / "r103_{}_f1.json".format(region.lower())
        )
        config = json.loads(config_path.read_text())
        result.update(str(value) for value in config["active_regions"])
    return sorted(result)


def run(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    output = args.output_dir.resolve()
    if int(args.batch_size) < 1:
        raise ValueError("batch size must be positive")
    if output.exists() and any(output.iterdir()) and not args.force:
        summary = json.loads((output / "summary.json").read_text())
        if summary.get("status") != "completed_pricefm_validation_driver_cache":
            raise FileExistsError(output)
        for record in summary["artifacts"]:
            path = Path(record["path"])
            if not path.is_file() or sha256_file(path) != record["sha256"]:
                raise RuntimeError("cached PriceFM artifact changed: {}".format(path))
        return summary

    scripts = Path(__file__).resolve().parent
    phase1 = load_script(scripts / "17_run_pricefm_phase1_predictions.py", "r108_phase1")
    config_path = data_root / "campaigns" / "pricefm_stage_r102_recursive_normal_20260916" / "configs" / "data_L96.yaml"
    window_root = (
        data_root / "campaigns" / "pricefm_stage_r97_global_region_frozen_campaign_20260908"
        / "processed_scoring"
    )
    model_path = data_root / "external" / "PriceFM" / "Model" / "PhaseI_best.keras"
    pricefm_repo = data_root / "external" / "PriceFM"
    if sha256_file(model_path) != MODEL_SHA256:
        raise RuntimeError("frozen PriceFM checkpoint hash changed")
    if git_head(pricefm_repo) != PRICEFM_COMMIT:
        raise RuntimeError("frozen PriceFM source revision changed")
    config = load_config(config_path)
    config["pricefm"]["processed_dir"] = str(window_root)
    all_regions = list(pricefm_block(config)["regions"])
    targets = required_regions(data_root)
    if not set(targets).issubset(all_regions):
        raise RuntimeError("R108 target regions are absent from the PriceFM configuration")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    artifacts = []
    source_windows = []
    try:
        model = phase1.load_phase1_model(pricefm_repo, model_path)
        for fold in (1, 2, 3):
            windows = phase1.load_operational_windows(config, fold, "val", all_regions)
            for region in all_regions:
                source = phase1.window_npz_path(config, fold, region, "val")
                source_windows.append({
                    "role": "pricefm_validation_window",
                    "region": region,
                    "fold": fold,
                    "path": str(source.resolve()),
                    "bytes": source.stat().st_size,
                    "sha256": sha256_file(source),
                })
            for target in targets:
                x_lag, x_lead, gate, truth, anchors = phase1.stack_model_inputs(
                    windows, all_regions, target
                )
                prediction = np.asarray(
                    model.predict(
                        {"X_lag_all": x_lag, "X_lead_all": x_lead, "graph_gate": gate},
                        batch_size=int(args.batch_size),
                        verbose=0,
                    ),
                    dtype=float,
                )
                expected = (truth.shape[0], truth.shape[1], 7)
                if prediction.shape != expected or not np.isfinite(prediction).all():
                    raise RuntimeError(
                        "invalid PriceFM prediction geometry for {} fold {}".format(target, fold)
                    )
                path = temporary / "fold_{}".format(fold) / "region={}.npz".format(target)
                path.parent.mkdir(parents=True, exist_ok=True)
                np.savez_compressed(
                    path,
                    prediction_scaled=prediction.astype(np.float32),
                    truth_scaled=np.asarray(truth, dtype=np.float32),
                    anchors=np.asarray(anchors, dtype=str),
                    quantiles=np.asarray([0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]),
                )
                artifacts.append({
                    "role": "pricefm_validation_quantiles",
                    "region": target,
                    "fold": fold,
                    "path": str((output / path.relative_to(temporary)).resolve()),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        summary = {
            "stage": "R108",
            "status": "completed_pricefm_validation_driver_cache",
            "split": "validation_only",
            "window_mode": "operational",
            "regions": targets,
            "folds": [1, 2, 3],
            "model_path": str(model_path),
            "model_sha256": MODEL_SHA256,
            "pricefm_repo": str(pricefm_repo),
            "pricefm_repo_commit": PRICEFM_COMMIT,
            "data_config_path": str(config_path),
            "data_config_sha256": sha256_file(config_path),
            "window_root": str(window_root),
            "source_windows": source_windows,
            "source_script": str((scripts / "17_run_pricefm_phase1_predictions.py").resolve()),
            "source_script_sha256": sha256_file(scripts / "17_run_pricefm_phase1_predictions.py"),
            "checkpoint_training_provenance_complete": False,
            "scientific_use": "oracle_strength_driver_diagnosis_only",
            "test_opened": False,
            "model_fit_started": False,
            "registry_mutated": False,
            "article_mutated": False,
            "artifacts": artifacts,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ.setdefault(name, "1")
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
