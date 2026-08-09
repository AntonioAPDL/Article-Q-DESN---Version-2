#!/usr/bin/env python3
"""Prepare the frozen Stage-R50 PriceFM MCMC confirmation campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json

ARTIFACT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT / "application/data_local/pricefm"
SOURCE = Path(__file__).resolve().parents[3]
R48 = DATA / "authoritative/pricefm_stage_r48_frozen_test_audit_closeout_20260808"
R47_RUN = DATA / "runs/pricefm_stage_r47_frozen_test_audit_20260808/r47_no3_f3_nestedhorizonsep_81e260ce/cells/region=NO_3/fold=3"
EXDQLM = Path("/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration")
PREP = DATA / "authoritative/pricefm_stage_r50_mcmc_confirmation_launch_prep_20260809"
GRID = DATA / "experiment_grids/pricefm_stage_r50_mcmc_confirmation_20260809"
RUNS = DATA / "runs/pricefm_stage_r50_mcmc_confirmation_20260809"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
COMPONENTS = ["shared_static", "horizon_1_24"]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r48-dir", type=Path, default=R48)
    p.add_argument("--stage-r47-cell", type=Path, default=R47_RUN)
    p.add_argument("--exdqlm-path", type=Path, default=EXDQLM)
    p.add_argument("--output-dir", type=Path, default=PREP)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--chains", type=int, default=4)
    p.add_argument("--n-burn", type=int, default=1000)
    p.add_argument("--n-mcmc", type=int, default=1000)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def job_id(component, tau, chain):
    return f"r50_no3_f3_{component}_tau{int(round(tau * 100)):02d}_chain{chain}"


def run(args):
    if args.chains < 4 or args.n_burn < 500 or args.n_mcmc < 500:
        raise ValueError("Confirmatory R50 requires >=4 chains and >=500 burn/retained draws.")
    out, grid, runs = args.output_dir.resolve(), args.grid_dir.resolve(), args.run_dir.resolve()
    for path in (out, grid):
        if path.exists() and any(path.iterdir()) and not args.force:
            raise FileExistsError(f"Output exists: {path}")
        path.mkdir(parents=True, exist_ok=True)
    (grid / "configs").mkdir(parents=True, exist_ok=True)
    runs.mkdir(parents=True, exist_ok=True)

    queue_path = args.stage_r48_dir / "pricefm_stage_r48_mcmc_confirmation_queue.csv"
    queue = pd.read_csv(queue_path)
    if len(queue) != 1:
        raise RuntimeError(f"R50 requires exactly one R48 winner; observed {len(queue)}")
    winner = queue.iloc[0]
    if (winner.region, int(winner.fold)) != ("NO_3", 3) or not bool(winner.mcmc_confirmation_eligible):
        raise RuntimeError("Unexpected R48 winner contract")

    source_config = args.stage_r47_cell / "config.yaml"
    source_adapter = args.stage_r47_cell / "adapter"
    source_model = args.stage_r47_cell / "model"
    payload = yaml.safe_load(source_config.read_text())
    cfg = payload["pricefm_desn_smoke"]
    if cfg["region"] != "NO_3" or int(cfg["fold"]) != 3:
        raise RuntimeError("R47 source config is not NO_3 fold 3")
    if [float(x) for x in cfg["quantiles"]] != TAUS:
        raise RuntimeError("R47 quantile ladder changed")
    weight = 0.25
    if abs(float(winner.pooled_test_AQL) - 3.8318982860174926) > 1e-10:
        raise RuntimeError("R48 winner evidence changed")

    adapter_dir = runs / "frozen_adapter"
    adapter_cfg = json.loads(json.dumps(payload))
    acfg = adapter_cfg["pricefm_desn_smoke"]
    acfg["package_path"] = str(args.exdqlm_path.resolve())
    acfg["adapter"]["output_dir"] = str(adapter_dir)
    acfg["run"]["output_dir"] = str(runs / "unused_vb_model")
    adapter_cfg_path = grid / "r50_frozen_adapter.yaml"
    adapter_cfg_path.write_text(yaml.safe_dump(adapter_cfg, sort_keys=False))

    rows = []
    for component in COMPONENTS:
        for tau in TAUS:
            for chain in range(1, args.chains + 1):
                jid = job_id(component, tau, chain)
                job_out = runs / jid
                config = {
                    "pricefm_stage_r50_mcmc": {
                        "id": jid,
                        "region": "NO_3",
                        "fold": 3,
                        "component": component,
                        "horizon_block": "1-24" if component == "horizon_1_24" else "all",
                        "tau": float(tau),
                        "chain": chain,
                        "seed": 2026080900 + int(round(tau * 100)) * 10 + chain + (1000 if component == "horizon_1_24" else 0),
                        "adapter_dir": str(adapter_dir),
                        "source_adapter_dir": str(source_adapter.resolve()),
                        "source_model_dir": str(source_model.resolve()),
                        "exdqlm_path": str(args.exdqlm_path.resolve()),
                        "init_beta_path": str(out / "initialization" / f"{component}_tau{int(round(tau * 100)):02d}_beta.csv"),
                        "init_manifest": str(out / "pricefm_stage_r50_vb_initialization_manifest.csv"),
                        "output_dir": str(job_out),
                        "likelihood_family": "exal",
                        "prior_family": "rhs_ns",
                        "tau0": 1e-4,
                        "shrink_intercept": False,
                        "n_burn": args.n_burn,
                        "n_mcmc": args.n_mcmc,
                        "thin": 1,
                        "init_from_vb": False,
                        "training_weighting": {"focus": "25-48", "base_frequency": 4, "focused_frequency": 8, "expected_rows": 583200},
                        "frozen_pool_weight": weight,
                    }
                }
                config_path = grid / "configs" / f"{jid}.yaml"
                config_path.write_text(yaml.safe_dump(config, sort_keys=False))
                rows.append({
                    "id": jid, "region": "NO_3", "fold": 3, "component": component,
                    "tau": tau, "chain": chain, "seed": config["pricefm_stage_r50_mcmc"]["seed"],
                    "n_burn": args.n_burn, "n_mcmc": args.n_mcmc, "config": str(config_path),
                    "output_dir": str(job_out), "status": "prepared_not_launched",
                })
    manifest = pd.DataFrame(rows)
    manifest_path = out / "pricefm_stage_r50_launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)

    row_iterations = int(sum((583200 if c == "shared_static" else 116640) * (args.n_burn + args.n_mcmc) for c in manifest.component))
    gates = pd.DataFrame([
        {"gate": "single_r48_winner", "passed": True, "observed": "NO_3/fold=3"},
        {"gate": "seven_quantiles", "passed": manifest.tau.nunique() == 7, "observed": manifest.tau.nunique()},
        {"gate": "two_frozen_components", "passed": set(manifest.component) == set(COMPONENTS), "observed": manifest.component.nunique()},
        {"gate": "four_or_more_chains", "passed": manifest.chain.nunique() >= 4, "observed": manifest.chain.nunique()},
        {"gate": "design_rebuild_pending", "passed": False, "observed": "must match R47 hashes before launch"},
        {"gate": "vb_initialization_replay_pending", "passed": False, "observed": "must pass before launch"},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(out / "pricefm_stage_r50_prelaunch_gates.csv", index=False)
    sources = [Path(__file__).resolve(), queue_path, source_config, source_adapter / "adapter_manifest.json", source_adapter / "feature_map_matrix.npz", source_model / "model_predictions_scaled.csv", source_model / "model_parameter_summary.csv"]
    pd.DataFrame([{"path": str(p.resolve()), "sha256": digest(p), "bytes": p.stat().st_size} for p in sources]).to_csv(out / "source_manifest.csv", index=False)
    summary = {
        "status": "prepared_not_launched", "winner": "NO_3/fold=3", "jobs": len(manifest),
        "components": 2, "quantiles": 7, "chains": args.chains,
        "likelihood_row_iterations": row_iterations,
        "adapter_config": str(adapter_cfg_path), "adapter_dir": str(adapter_dir),
        "launch_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(out / "summary.json", summary)
    (out / "pricefm_stage_r50_mcmc_confirmation_launch_prep_report.md").write_text(
        "# PriceFM Stage-R50 MCMC confirmation prep\n\n"
        "R50 is restricted to the sole R48 winner, NO_3 fold 3. It freezes seven exAL/RHS_NS quantiles, a shared readout, the 1-24 horizon readout, four chains, and the validation-selected pooling weight 0.25.\n\n"
        "The R47 design matrices were cleaned, so launch remains blocked until the adapter is deterministically rebuilt and its X/y/row/feature-map hashes match R47. VB coefficient starts are recovered from frozen validation predictions and must replay those predictions before MCMC.\n\n"
        f"The exact replicated likelihood entails {row_iterations:,} likelihood row-iterations before additional sampler work. This cost is intentional and recorded; no reduced-row surrogate is authorized.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
