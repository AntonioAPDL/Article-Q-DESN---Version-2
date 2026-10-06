#!/usr/bin/env python3
"""Prepare the validation-only PriceFM R117 corrected BG pilot."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r117_engine import POLICIES, fingerprint, normalize_spec


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
GEOMETRIES = (
    (48,), (64,), (96,), (128,),
    (48, 48), (64, 64), (80, 80), (96, 48), (120, 64),
    (40, 40, 40), (48, 48, 48), (64, 64, 64), (96, 64, 48),
)
LAGS = (48, 96, 168, 240)
ALPHAS = (0.25, 0.35, 0.40, 0.45, 0.50, 0.55)
RHOS = (0.82, 0.90, 0.95)
INPUT_SCALES = (0.15, 0.20, 0.25, 0.35, 0.50)
SPARSITIES = (0.05, 0.10, 0.20)
CALENDARS = ("none", "compact3")
SEED = 2026092501


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    p.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    p.add_argument("--output-dir", type=Path)
    p.add_argument("--campaign-root", type=Path)
    p.add_argument("--workers", type=int, default=15)
    p.add_argument("--candidate-count", type=int, default=240)
    p.add_argument("--ridge-top-k", type=int, default=50)
    p.add_argument("--force", action="store_true")
    return p


def _historical_control(registry: Path) -> dict[str, Any]:
    rows = pd.read_csv(registry, low_memory=False)
    selected = rows[rows.region.eq("BG")].sort_values("fold").iloc[0]
    units = [int(value) for value in json.loads(str(selected.units))]
    return normalize_spec({
        "region": "BG", "feature_policy": "target_only", "calendar": "none",
        "readout": "pure_all_layers", "lag_window": int(selected.lag_window),
        "depth": len(units), "units": units, "alpha": float(selected.alpha),
        "rho": float(selected.rho), "input_scale": float(selected.input_scale),
        "recurrent_sparsity": 0.05, "seed": SEED,
    })


def _coverage_key(spec: dict[str, Any], field: str) -> str:
    value = spec[field]
    return json.dumps(value, separators=(",", ":")) if isinstance(value, list) else str(value)


def _balanced_policy_candidates(policy: str, count: int, control: dict[str, Any] | None) -> list[dict[str, Any]]:
    pool = []
    for units, lag, alpha, rho, input_scale, sparsity, calendar in itertools.product(
        GEOMETRIES, LAGS, ALPHAS, RHOS, INPUT_SCALES, SPARSITIES, CALENDARS
    ):
        spec = normalize_spec({
            "region": "BG", "feature_policy": policy, "calendar": calendar,
            "readout": "pure_all_layers", "lag_window": lag,
            "depth": len(units), "units": list(units), "alpha": alpha,
            "rho": rho, "input_scale": input_scale,
            "recurrent_sparsity": sparsity, "seed": SEED,
        })
        identity = fingerprint(spec)
        pool.append((fingerprint({"stage": "R117", "identity": identity}), identity, spec))
    pool.sort(key=lambda value: value[0])
    selected: list[dict[str, Any]] = []
    seen: set[str] = set()
    if control is not None:
        selected.append(dict(control))
        seen.add(fingerprint(control))
    fields = ("units", "lag_window", "alpha", "rho", "input_scale", "recurrent_sparsity", "calendar")
    uncovered = {
        (field, _coverage_key(spec, field))
        for _, _, spec in pool for field in fields
    }
    for spec in selected:
        uncovered -= {(field, _coverage_key(spec, field)) for field in fields}
    while uncovered and len(selected) < count:
        best = max(
            (item for item in pool if item[1] not in seen),
            key=lambda item: (
                sum((field, _coverage_key(item[2], field)) in uncovered for field in fields),
                -int(item[0][:16], 16),
            ),
        )
        selected.append(best[2])
        seen.add(best[1])
        uncovered -= {(field, _coverage_key(best[2], field)) for field in fields}
    for _, identity, spec in pool:
        if len(selected) == count:
            break
        if identity not in seen:
            selected.append(spec)
            seen.add(identity)
    if len(selected) != count or uncovered:
        raise RuntimeError(f"failed to construct balanced R117 bank for {policy}")
    for field in fields:
        expected = {_coverage_key(spec, field) for _, _, spec in pool}
        observed = {_coverage_key(spec, field) for spec in selected}
        if observed != expected:
            raise RuntimeError(f"R117 bank omitted {field} levels for {policy}")
    return selected


def candidate_frame(registry: Path, count: int) -> pd.DataFrame:
    if count != 240 or count % len(POLICIES):
        raise ValueError("production R117 requires 240 candidates balanced over four policies")
    control = _historical_control(registry)
    rows = []
    per_policy = count // len(POLICIES)
    for policy in POLICIES:
        policy_control = control if policy == "target_only" else None
        for position, spec in enumerate(_balanced_policy_candidates(policy, per_policy, policy_control), start=1):
            identity = fingerprint(spec)
            rows.append({
                "candidate_id": f"r117_bg_{policy}_{position:03d}_{identity[:10]}",
                "candidate_role": "R98_geometry_control_corrected_contract"
                if policy == "target_only" and position == 1 else "balanced_search",
                "semantic_sha256": identity,
                "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
                **spec,
                "units": json.dumps(spec["units"], separators=(",", ":")),
                "selection_split": "fold1_train_internal_expanding_validation",
                "test_access_authorized": False,
            })
    frame = pd.DataFrame(rows)
    if len(frame) != count or frame.candidate_id.duplicated().any() or frame.semantic_sha256.duplicated().any():
        raise RuntimeError("R117 candidate identity contract failed")
    return frame


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if args.workers != 15 or args.candidate_count != 240 or args.ridge_top_k != 50:
        raise ValueError("R117 production contract is 15 workers, 240 Ridge candidates, top 50 RHS")
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    registry = data / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913/pricefm_stage_r98_authoritative_registry.csv"
    candidates = candidate_frame(registry, args.candidate_count)
    candidate_path = output / "pricefm_stage_r117_candidate_manifest.csv"
    candidates.to_csv(candidate_path, index=False)

    source_processed = data / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/processed_validation"
    runtime_processed = campaign / "processed"
    base_path = data / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/regions/AT/surface_grid/configs/train_validation_data.yaml"
    base_text = base_path.read_text()
    base = yaml.safe_load(base_text)
    base["pricefm"]["processed_dir"] = str(runtime_processed)
    base["pricefm"]["splits"] = [item for item in base["pricefm"]["splits"] if "test" not in item]
    config_dir = output / "data_configs"
    config_dir.mkdir(exist_ok=True)
    base_snapshot = config_dir / "source_train_validation_data.yaml"
    base_snapshot.write_text(base_text)
    data_configs = {}
    for lag in LAGS:
        config = json.loads(json.dumps(base))
        config["pricefm"]["windows"]["lag_window"] = int(lag)
        path = config_dir / f"data_L{lag}.yaml"
        path.write_text(yaml.safe_dump(config, sort_keys=False))
        data_configs[str(lag)] = str(path)

    code_root = args.code_root.resolve()
    source_paths = [
        Path(__file__).resolve(),
        SCRIPT_DIR / "pricefm_r117_engine.py",
        SCRIPT_DIR / "400_run_pricefm_stage_r117_bg_pilot.py",
        SCRIPT_DIR / "401_fit_pricefm_stage_r117_quantile_atom.R",
        code_root / "application/R/pricefm_recursive_normal_fit.R",
        code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R",
        code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        registry,
        base_snapshot,
        *(Path(path) for path in data_configs.values()),
        data / "authoritative/pricefm_stage_r116_transfer_closeout_20260924/summary.json",
    ]
    missing = [str(path) for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"R117 source file(s) missing: {missing}")
    sources = pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths])
    sources.to_csv(output / "source_manifest.csv", index=False)
    control = {
        "stage": "R117", "tag": TAG, "status": "prepared_not_launched",
        "target_region": "BG", "workers": 15, "cpu_list": list(range(15)),
        "candidate_count": 240, "ridge_top_k": 50,
        "rhs_tau_reference": 1e-4, "rhs_tau_reference_dimension": 128,
        "rhs_tau_multipliers": [0.25, 1.0, 4.0],
        "quantiles": list((0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)),
        "posterior_paths": 500, "source_processed": str(source_processed),
        "runtime_processed": str(runtime_processed), "campaign_root": str(campaign),
        "data_configs": data_configs,
        "normal_runtime": str(data / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
        "cran_library": str(data / "runtime_libraries/exdqlm_cran_1p1p1"),
        "cran_manifest": str(data / "runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json"),
        "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        "r_version": "4.6.0",
        "selection_contract": "Fold1 training internal temporal validation only",
        "outer_contract": "Fold1 freezes family/operator; Folds2-3 evaluate frozen choice",
        "test_opened": False, "joint_model_authorized": False, "mcmc_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    gates = pd.DataFrame([
        ("candidate_count", len(candidates) == 240, len(candidates)),
        ("policy_balance", candidates.feature_policy.value_counts().eq(60).all(), candidates.feature_policy.value_counts().to_dict()),
        ("pure_readout_only", candidates.readout.eq("pure_all_layers").all(), ";".join(sorted(candidates.readout.unique()))),
        ("concat_all_layers", True, "readout constructed from every layer by R117 engine"),
        ("fixed_seed", candidates.seed.nunique() == 1, int(candidates.seed.iloc[0])),
        ("test_absent", not candidates.test_access_authorized.astype(bool).any(), False),
        ("workers", args.workers == 15, args.workers),
    ], columns=["gate", "passed", "observed"])
    gates.to_csv(output / "gates.csv", index=False)
    if not gates.passed.all():
        raise RuntimeError("R117 preparation gate failed")
    hashes = {
        "candidate_manifest": sha256_file(candidate_path),
        "source_manifest": sha256_file(output / "source_manifest.csv"),
        "launch_control": sha256_file(output / "launch_control.json"),
        "gates": sha256_file(output / "gates.csv"),
    }
    summary = {**control, "output_sha256": hashes, "launch_authorized": True}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
