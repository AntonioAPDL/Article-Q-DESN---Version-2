#!/usr/bin/env python3
"""Prepare bounded exact-CRAN probes for the PriceFM R118 quantile repair."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json
from pricefm_r117_engine import fingerprint


SOURCE_TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")

ARMS = (
    {
        "arm_id": "al_reference",
        "family": "al",
        "sigmagam_freeze_warmup_iters": 0,
        "rhs_freeze_tau_warmup_iters": 0,
        "priority": 0,
    },
    {
        "arm_id": "exal_current",
        "family": "exal",
        "sigmagam_freeze_warmup_iters": 10,
        "rhs_freeze_tau_warmup_iters": 0,
        "priority": 3,
    },
    {
        "arm_id": "exal_delayed_sigmagam",
        "family": "exal",
        "sigmagam_freeze_warmup_iters": 100,
        "rhs_freeze_tau_warmup_iters": 0,
        "priority": 2,
    },
    {
        "arm_id": "exal_delayed_sigmagam_rhs",
        "family": "exal",
        "sigmagam_freeze_warmup_iters": 100,
        "rhs_freeze_tau_warmup_iters": 100,
        "priority": 1,
    },
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--subset-stride", type=int, default=8)
    value.add_argument("--max-iter", type=int, default=180)
    return value


def source_paths(artifact: Path) -> dict[str, Path]:
    data = artifact / "application/data_local/pricefm"
    campaign = data / "campaigns" / SOURCE_TAG
    control = data / "launch_prep" / SOURCE_TAG / "launch_control.json"
    r117 = json.loads(control.read_text())
    cran_manifest = Path(r117["cran_manifest"])
    cran = json.loads(cran_manifest.read_text())
    return {
        "source_campaign": campaign,
        "source_control": control,
        "winner": campaign / "winner/winner.json",
        "design_dir": campaign / "full_folds/fold=1/quantile_design",
        "parent_dir": campaign / "full_folds/fold=1/quantiles/al/tau=0.25",
        "cran_library": Path(r117["cran_library"]),
        "cran_manifest": cran_manifest,
        "cran_tarball": Path(cran["source_tarball"]["path"]),
        "rscript": Path(r117["rscript"]),
    }


def validate_sources(paths: dict[str, Path]) -> dict[str, Any]:
    required_files = (
        paths["source_control"],
        paths["winner"],
        paths["design_dir"] / "design.json",
        paths["design_dir"] / "terminal.json",
        paths["design_dir"] / "X.bin",
        paths["design_dir"] / "y.bin",
        paths["parent_dir"] / "terminal.json",
        paths["parent_dir"] / "beta_mean.bin",
        paths["parent_dir"] / "beta_cov.bin",
        paths["parent_dir"] / "parameter_summary.json",
        paths["parent_dir"] / "vb_trace.csv",
        paths["cran_manifest"],
        paths["cran_tarball"],
    )
    missing = [str(path) for path in required_files if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"missing R118 source files: {missing}")
    winner = json.loads(paths["winner"].read_text())
    design = json.loads((paths["design_dir"] / "design.json").read_text())
    parent = json.loads((paths["parent_dir"] / "terminal.json").read_text())
    cran = json.loads(paths["cran_manifest"].read_text())
    if winner.get("test_opened") or design.get("test_opened") or parent.get("test_opened"):
        raise RuntimeError("R118 source opened test data")
    if parent.get("family") != "al" or float(parent.get("tau")) != 0.25:
        raise RuntimeError("R118 probe parent must be the fold-1 AL tau=0.25 atom")
    if cran.get("status") != "installed_exact_cran_exdqlm_1.1.1":
        raise RuntimeError("R118 requires the exact CRAN exdqlm 1.1.1 runtime")
    if sha256_file(paths["cran_tarball"]) != cran["source_tarball"]["sha256"]:
        raise RuntimeError("R118 CRAN source tarball hash mismatch")
    return {
        "winner": winner,
        "design": design,
        "parent": parent,
        "cran": cran,
        "required_files": required_files,
    }


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if args.subset_stride < 2 or args.max_iter <= 135:
        raise ValueError("R118 probes require stride >= 2 and more than 135 iterations")
    paths = source_paths(artifact)
    source = validate_sources(paths)
    tau0 = float(source["winner"]["tau0"])
    design_terminal_sha = sha256_file(paths["design_dir"] / "terminal.json")
    parent_terminal_sha = sha256_file(paths["parent_dir"] / "terminal.json")
    target_shas = {
        family: fingerprint({
            "stage": "R118_probe",
            "fold": 1,
            "family": family,
            "tau": 0.25,
            "tau0": tau0,
            "subset_stride": args.subset_stride,
            "design_terminal_sha256": design_terminal_sha,
            "prior_sigma": {"a": 1, "b": 1},
            "prior_gamma": None if family == "al" else {"mu0": 0, "s20": 10},
            "beta_prior": "rhs_ns",
        })
        for family in ("al", "exal")
    }
    code_files = (
        code / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        code / "application/scripts/pricefm/403_prepare_pricefm_stage_r118_quantile_repair.py",
        code / "application/scripts/pricefm/404_probe_pricefm_stage_r118_quantile_mechanism.R",
        code / "application/scripts/pricefm/405_run_pricefm_stage_r118_quantile_repair.py",
    )
    missing_code = [str(path) for path in code_files if not path.is_file()]
    if missing_code:
        raise FileNotFoundError(f"missing R118 code files: {missing_code}")
    output.mkdir(parents=True, exist_ok=True)
    campaign.mkdir(parents=True, exist_ok=True)
    records = []
    for arm in ARMS:
        arm_id = str(arm["arm_id"])
        target_sha = target_shas[str(arm["family"])]
        config = {
            "stage": "R118_probe",
            "tag": TAG,
            "arm_id": arm_id,
            "family": arm["family"],
            "fold": 1,
            "tau": 0.25,
            "tau0": tau0,
            "design_dir": str(paths["design_dir"]),
            "design_terminal_sha256": design_terminal_sha,
            "parent_dir": str(paths["parent_dir"]),
            "parent_terminal_sha256": parent_terminal_sha,
            "output_dir": str(campaign / "mechanism_probes" / arm_id),
            "cran_library": str(paths["cran_library"]),
            "cran_manifest": str(paths["cran_manifest"]),
            "cran_manifest_sha256": sha256_file(paths["cran_manifest"]),
            "cran_tarball": str(paths["cran_tarball"]),
            "cran_tarball_sha256": sha256_file(paths["cran_tarball"]),
            "cran_adapter": str(code_files[0]),
            "cran_adapter_sha256": sha256_file(code_files[0]),
            "subset_stride": int(args.subset_stride),
            "max_iter": int(args.max_iter),
            "tol": 1e-5,
            "n_samp_xi": 200,
            "n_samp": 200,
            "sigmagam_freeze_warmup_iters": int(arm["sigmagam_freeze_warmup_iters"]),
            "rhs_freeze_tau_warmup_iters": int(arm["rhs_freeze_tau_warmup_iters"]),
            "structured_grid_size": 151,
            "structured_span_sd": 6.0,
            "min_postwarmup_updates": 35,
            "seed": 2026092518,
            "posterior_target_sha256": target_sha,
            "schedule_sha256": fingerprint(arm),
            "training_split": "fold1_train_only_deterministic_row_probe",
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        }
        config_path = output / "contracts" / f"{arm_id}.json"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        write_json(config_path, config)
        records.append({
            **arm,
            "config_path": str(config_path),
            "config_sha256": sha256_file(config_path),
            "output_dir": config["output_dir"],
            "posterior_target_sha256": target_sha,
            "test_access_authorized": False,
        })
    manifest = pd.DataFrame(records).sort_values(["family", "priority", "arm_id"], kind="mergesort")
    manifest.to_csv(output / "probe_manifest.csv", index=False)
    source_files = list(source["required_files"]) + list(code_files)
    write_json(output / "source_manifest.json", {
        "stage": "R118_probe",
        "status": "hash_sealed_training_only_sources",
        "files": [{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_files],
        "test_opened": False,
    })
    control = {
        "stage": "R118_probe",
        "tag": TAG,
        "status": "prepared_not_launched",
        "source_stage": "R117",
        "source_campaign": str(paths["source_campaign"]),
        "campaign_root": str(campaign),
        "probe_manifest": str(output / "probe_manifest.csv"),
        "source_manifest": str(output / "source_manifest.json"),
        "rscript": str(paths["rscript"]),
        "workers": 4,
        "cpu_list": [0, 1, 2, 3],
        "posterior_target_sha256_by_family": target_shas,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_model_fitted": False,
        "mcmc_fitted": False,
    }
    write_json(output / "launch_control.json", control)
    (output / "README.md").write_text(
        "# PriceFM R118 exact-CRAN quantile mechanism probes\n\n"
        "Four bounded fold-1 training-only probes compare one AL reference with three "
        "exAL release schedules. All exAL schedules share an identical posterior-target "
        "hash; only optimization timing differs. No test, registry, article, joint, or "
        "MCMC action is authorized.\n"
    )
    write_json(output / "terminal.json", {
        "status": "prepared_r118_probe_not_launched",
        "stage": "R118_probe",
        "arms": len(records),
        "posterior_target_sha256_by_family": target_shas,
        "manifest_sha256": sha256_file(output / "probe_manifest.csv"),
        "source_manifest_sha256": sha256_file(output / "source_manifest.json"),
        "test_opened": False,
    })
    return control


def main() -> int:
    result = prepare(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
