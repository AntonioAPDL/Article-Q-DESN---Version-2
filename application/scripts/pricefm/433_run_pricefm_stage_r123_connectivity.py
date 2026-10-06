#!/usr/bin/env python3
"""Bounded BG input-connectivity pilot -> Ridge -> RHS -> seven AL levels."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

for _key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
             "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS"):
    os.environ[_key] = "1"

import numpy as np
import pandas as pd
import scipy

from pricefm_common import sha256_file, write_json
from pricefm_r122_engine import RESERVOIR_SEEDS
import pricefm_r123_runtime as RT

SCRIPTS = Path(__file__).resolve().parent
_loader = importlib.util.spec_from_file_location("pricefm_r122_runner_for_r123", SCRIPTS / "429_run_pricefm_stage_r122_long_memory.py")
BACKEND = importlib.util.module_from_spec(_loader)
_loader.loader.exec_module(BACKEND)
BACKEND.RT = RT
# Backend workers must re-enter this adapter, not an unmodified R122 process.
BACKEND.__file__ = __file__
TAG = "pricefm_stage_r123_bg_input_connectivity_20261003"
BACKEND.TAG = TAG
ROOT = SCRIPTS.parents[2]
DEFAULT_DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
PROTOCOL = ROOT / "application/config/pricefm_stage_r123_connectivity_protocol_20261003.json"


def read(path):
    return json.loads(Path(path).read_text())


def immutable_json(path, value):
    path = Path(path)
    if path.exists():
        if read(path) != value:
            raise RuntimeError(f"immutable R123 contract changed: {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True); write_json(path, value)


def fingerprint(value):
    return RT.BASE.fingerprint(value)


def anchor():
    return dict(region="BG", feature_policy="graph_summary_mean", calendar="none", readout="pure_all_layers",
                m_y=2016, m_x=0, source_window=3120, warmup_steps=240, depth=2, units=[128, 128],
                alpha=.1, rho=.7, input_scale=.05, input_fan_in=8, recurrent_sparsity=.05,
                input_policy="uniform", interlayer_gain=.05)


def candidate(spec, phase):
    normalized = RT.normalize_spec(dict(spec, seed=int(RESERVOIR_SEEDS[0])))
    normalized.pop("seed")
    structure = fingerprint(normalized)
    channels = {"target_only": 3, "graph_summary_mean": 6, "graph_summary_mean_std": 9,
                "graph_neighbor_exogenous": 3 * len(RT.active_regions(dict(normalized, seed=int(RESERVOIR_SEEDS[0]))))}[normalized["feature_policy"]]
    return {"candidate_id": f"r123_{structure[:16]}", "structural_sha256": structure,
            "spec_json": json.dumps(normalized, sort_keys=True, separators=(",", ":")),
            "input_dimension": normalized["m_y"] + (normalized["m_x"] + 1) * channels,
            "readout_dimension": 1 + sum(normalized["units"]), "phase": phase,
            "test_access_authorized": False}


def pilot_manifest():
    rows = []
    for graph in ("target_only", "graph_summary_mean"):
        for mx in (0, 24, 96):
            for policy, fan in (("uniform", 8), ("coverage", 8), ("balanced", 8), ("balanced", 32)):
                spec = dict(anchor(), feature_policy=graph, m_x=mx, input_policy=policy, input_fan_in=fan)
                rows.append(candidate(spec, "pilot"))
    return pd.DataFrame(rows)


def search_manifest(protocol, policy):
    if policy not in ("coverage", "balanced"):
        raise ValueError("new search must retain mandatory input coverage")
    architectures = ([128, 128], [192, 192], [256, 256], [96] * 3, [128] * 3, [192] * 3,
                     [64] * 4, [96] * 4, [128] * 4, [48] * 6, [64] * 6, [96] * 6,
                     [32] * 8, [48] * 8, [64] * 8, [192, 128, 96], [128, 96, 64, 48])
    rng = np.random.default_rng(2026100301)
    rows, seen = [], set(pilot_manifest().structural_sha256)
    while len(rows) < int(protocol["new_search_structures"]):
        i = len(rows)
        # Exactly 36 deep sentinels and 60 long-exogenous-lag sentinels.
        choices = architectures[12:15] if i < 36 else architectures[:12] + architectures[15:]
        units = list(choices[int(rng.integers(len(choices)))])
        mx_values = protocol["m_x_sentinels"] if 36 <= i < 96 else protocol["m_x_primary"]
        spec = dict(anchor(), units=units, depth=len(units), input_policy=policy)
        for key in ("m_y", "alpha", "rho", "input_scale", "interlayer_gain", "input_fan_in", "recurrent_sparsity"):
            values = protocol[key]; spec[key] = values[int(rng.integers(len(values)))]
        spec["m_x"] = mx_values[int(rng.integers(len(mx_values)))]
        spec["feature_policy"] = ("target_only", "graph_summary_mean", "graph_summary_mean_std",
                                  "graph_neighbor_exogenous")[i % 4]
        row = candidate(spec, "search")
        if row["structural_sha256"] not in seen:
            seen.add(row["structural_sha256"]); rows.append(row)
    return pd.DataFrame(rows)


def execution(candidates, seeds):
    rows = []
    for row in candidates.to_dict("records"):
        for seed in seeds:
            digest = fingerprint({"structural_sha256": row["structural_sha256"], "reservoir_seed": int(seed)})
            rows.append(dict(row, fit_id=f"r123f_{digest[:16]}", fit_sha256=digest,
                             reservoir_seed=int(seed), role="search", canonical_seed=int(seed) == int(RESERVOIR_SEEDS[0])))
    return pd.DataFrame(rows)


def source_snapshot(code, parent_prep, parent_campaign):
    # Freeze the entire task Python/R inference surface, plus exact external runtime files.
    paths = sorted((code / "application/scripts/pricefm").glob("*.py"))
    paths += sorted((code / "application/scripts/pricefm").glob("*.R"))
    paths += [code / "application/R/pricefm_recursive_normal_fit.R", PROTOCOL,
              code / "application/tests/test_pricefm_stage_r123_prior_gate.R",
              parent_prep / "launch_control.json", parent_prep / "target_contract.json",
              parent_campaign / "terminal.json", parent_campaign / "frozen_internal_choice.json"]
    inherited = read(parent_prep / "launch_control.json")
    paths += sorted(Path(inherited["normal_runtime"]).glob("R/*.R"))
    paths += sorted(Path(inherited["normal_runtime"]).glob("src/*"))
    paths += sorted((Path(inherited["cran_library"]) / "exdqlm").glob("R/*"))
    paths += sorted((Path(inherited["cran_library"]) / "exdqlm").glob("libs/*"))
    paths += [Path(inherited["cran_manifest"]), Path(inherited["cran_library"]) / "exdqlm/DESCRIPTION"]
    paths += [parent_campaign / "broad/closeout/fit_metrics.csv", parent_campaign / "rhs/manifest.csv",
              parent_campaign / "al_internal/closeout/ranking.csv", parent_prep / "candidate_manifest.csv"]
    probe = dict(anchor(), feature_policy="graph_neighbor_exogenous", seed=int(RESERVOIR_SEEDS[0]))
    for region in RT.active_regions(probe):
        window = Path(inherited["runtime_processed"]) / f"windows/fold_1/region={region}/train_L3120_H96_contained_half_open.npz"
        paths += [window, window.with_suffix(".manifest.json")]
    # Freeze every compact parent initializer used by the no-refit replay.
    parents = pd.read_csv(parent_campaign / "rhs/manifest.csv")
    for identifier in pd.read_csv(parent_campaign / "al_internal/closeout/ranking.csv").candidate_id:
        for row in parents[parents.candidate_id.eq(identifier)].itertuples(index=False):
            paths += [Path(row.output_dir) / name for name in ("terminal.json", "beta_mean.bin", "beta_cov.bin")]
        for split in (1, 2, 3):
            for tau in RT.QUANTILES:
                output = parent_campaign / f"al_internal/{identifier}/split={split}/quantiles/al/tau={tau:.2f}"
                paths += [output / name for name in ("terminal.json", "beta_mean.bin", "beta_cov.bin")]
    # All potential unchanged pilot controls are protected before reuse.
    old = pd.read_csv(parent_campaign / "broad/closeout/fit_metrics.csv")
    pilot_specs = {json.dumps({k: v for k, v in json.loads(row.spec_json).items()
                               if k not in ("input_policy", "interlayer_gain")}, sort_keys=True)
                   for row in pilot_manifest().itertuples(index=False)
                   if json.loads(row.spec_json)["input_policy"] == "uniform"}
    for row in old.itertuples(index=False):
        if json.dumps(json.loads(row.spec_json), sort_keys=True) in pilot_specs:
            output = parent_campaign / f"ridge/fits/{row.fit_id}"
            paths += [output / name for name in ("terminal.json", "contract.json", "training_statistics.npz", "validation_metrics.csv")]
    paths = [path for path in paths if not path.is_dir()]
    missing = [str(path) for path in paths if not path.is_file()]
    if missing: raise FileNotFoundError(f"R123 required frozen source missing: {missing[:5]}")
    return [{"path": str(path.resolve()), "sha256": sha256_file(path), "bytes": path.stat().st_size,
             "mtime_ns": path.stat().st_mtime_ns} for path in sorted(set(paths))]


def prepare(args):
    prep, campaign = args.prep_dir.resolve(), args.campaign_root.resolve()
    protocol = read(args.protocol)
    if read(args.parent_campaign / "terminal.json")["status"] != "R122_INTERNAL_SPECIFICATION_FROZEN_TEST_BLOCKED":
        raise RuntimeError("R123 requires a completed frozen R122 campaign")
    if campaign == args.parent_campaign.resolve() or campaign.is_relative_to(args.parent_campaign.resolve()):
        raise ValueError("R123 output must not be inside frozen R122")
    for flag in ("official_validation_authorized", "official_test_authorized", "article_mutation_authorized",
                 "registry_mutation_authorized", "exal_authorized", "joint_authorized", "mcmc_authorized"):
        if protocol[flag] is not False: raise ValueError(f"forbidden authorization: {flag}")
    inherited = read(args.parent_prep / "launch_control.json")
    target = read(args.parent_prep / "target_contract.json")
    immutable_json(prep / "target_contract.json", target)
    immutable_json(prep / "protocol.json", protocol)
    git_head = subprocess.check_output(["git", "-C", str(args.code_root), "rev-parse", "HEAD"], text=True).strip()
    if subprocess.check_output(["git", "-C", str(args.code_root), "status", "--porcelain"], text=True).strip():
        raise RuntimeError("R123 launch requires a committed clean task worktree")
    control = dict(inherited)
    control.pop("continuation", None); control.pop("rhs_contract_namespace", None)
    for key in list(control):
        if key.startswith(("rhs_tau_", "stage0b_")): control.pop(key)
    git_branch = subprocess.check_output(["git", "-C", str(args.code_root), "branch", "--show-current"], text=True).strip()
    if not git_branch.startswith("work/pricefm-"):
        raise RuntimeError("R123 requires its dedicated PriceFM task branch")
    control.update(stage="R123", tag=TAG, code_head=git_head, code_branch=git_branch, campaign_root=str(campaign),
                   data_config=str(prep / "data_configs/data_L3120.json"),
                   parent_campaign=str(args.parent_campaign.resolve()), workers=int(args.workers),
                   search_structure_count=600, pilot_structure_count=24, total_fit_count=1248,
                   primary_fit_count=1200, control_fit_count=48, third_seed_top_k=50,
                   rhs_max_iter=protocol["rhs_max_iter"], rhs_top_k=protocol["rhs_top_k"],
                   rhs_score_max_origins_per_split=protocol["rhs_origins_per_split"],
                   broad_score_max_origins_per_split=protocol["broad_origins_per_split"],
                   al_final_max_iter=protocol["al_max_iter"], al_companion_max_iter=protocol["al_companion_max_iter"],
                   posterior_paths=protocol["posterior_paths"], frozen_sources=source_snapshot(args.code_root, args.parent_prep, args.parent_campaign))
    control["runtime_versions"] = dict(python=sys.version, numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    BACKEND._write_immutable_csv(pd.DataFrame(control["frozen_sources"]), prep / "source_manifest.csv")
    immutable_json(prep / "launch_control.json", control)
    BACKEND._write_immutable_csv(pilot_manifest(), prep / "candidate_manifest.csv")
    BACKEND._write_immutable_csv(execution(pilot_manifest(), RESERVOIR_SEEDS[:2]), prep / "execution_manifest.csv")
    # Existing backend selection loader needs only this training-support contract.
    immutable_json(prep / "data_configs/data_L3120.json", {"scope": "training_only"})
    immutable_json(prep / "identity.json", {name: sha256_file(prep / name) for name in
        ("launch_control.json", "protocol.json", "target_contract.json", "source_manifest.csv", "data_configs/data_L3120.json")})
    return control


def verify_preparation(prep):
    for name, digest in read(prep / "identity.json").items():
        if sha256_file(prep / name) != digest: raise RuntimeError(f"R123 preparation changed: {name}")


def verify_sources(control, lightweight=False):
    if control["runtime_versions"] != dict(python=sys.version, numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__):
        raise RuntimeError("R123 Python dependency versions changed")
    for record in control["frozen_sources"]:
        path = Path(record["path"])
        if lightweight and record["bytes"] > 2**20:
            valid = path.stat().st_size == record["bytes"] and path.stat().st_mtime_ns == record["mtime_ns"]
        else:
            valid = sha256_file(path) == record["sha256"]
        if not valid:
            raise RuntimeError(f"R123 source/input changed: {record['path']}")


def arrays(control, spec, prep):
    raw = RT.explicit_arrays(RT.load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    target = read(prep / "target_contract.json")
    return RT.contract_support(raw, target["expected_first_origin_utc"], target["expected_origin_count"])[0]


def validate_row(row):
    spec = json.loads(row["spec_json"])
    digest = fingerprint(spec)
    fit = fingerprint({"structural_sha256": digest, "reservoir_seed": int(row["reservoir_seed"])})
    if digest != row["structural_sha256"] or fit != row["fit_sha256"] or row["fit_id"] != f"r123f_{fit[:16]}":
        raise ValueError("R123 manifest identity differs")
    if str(row["test_access_authorized"]).lower() != "false": raise ValueError("forbidden test access")
    return RT.normalize_spec(dict(spec, seed=int(row["reservoir_seed"])))


def valid_ridge(output, fit_hash=None):
    try:
        value = read(output / "terminal.json")
        if value["status"] != "completed_r123_ridge_cell" or value["test_opened"] is not False:
            return False
        if fit_hash is not None and value["fit_sha256"] != fit_hash: return False
        return all(sha256_file(output / name) == digest for name, digest in value["output_sha256"].items())
    except (OSError, KeyError, ValueError):
        return False


BACKEND._ridge_valid = valid_ridge


def ridge_cell(args):
    prep, campaign = args.prep_dir, args.campaign_root
    verify_preparation(prep)
    control = read(prep / "launch_control.json"); verify_sources(control, lightweight=True)
    rows = pd.read_csv(prep / "execution_manifest.csv")
    third = campaign / "seed3/manifest.csv"
    if third.is_file(): rows = pd.concat([rows, pd.read_csv(third)], ignore_index=True)
    row = rows[rows.fit_id.eq(args.fit_id)]
    if len(row) != 1: raise ValueError("R123 fit ID not unique")
    row = row.iloc[0].to_dict(); spec = validate_row(row)
    output = campaign / "ridge/fits" / args.fit_id
    if valid_ridge(output, row["fit_sha256"]): return read(output / "terminal.json")
    if output.exists(): raise RuntimeError("existing invalid output preserved; use an audited new recovery namespace")
    data = arrays(control, spec, prep); splits = RT.internal_splits(len(data.response))
    washout_data, _ = RT.standardize_from_training_origins(data, splits[0]["train"])
    washout = RT.washout_audit(washout_data, spec, [0, 252, 505], read(prep / "protocol.json")["washout_absolute_tolerance"])
    metrics, payload, audits, scalers = [], {}, {}, {}
    # This check is score-blind and never licenses a silent washout change.
    if not washout["passed"]:
        output.mkdir(parents=True)
        write_json(output / "rejected_washout.json", washout)
        return dict(status="R123_WASHOUT_REJECTED", fit_id=args.fit_id)
    reused = None
    parent = Path(control["parent_campaign"])
    # Exact unchanged controls can reuse archived Ridge sufficient statistics/scores.
    if spec["input_policy"] == "uniform" and spec["interlayer_gain"] == spec["input_scale"]:
        parent_manifest = pd.read_csv(parent / "broad/closeout/fit_metrics.csv")
        legacy_spec = {k: v for k, v in spec.items() if k not in ("seed", "input_policy", "interlayer_gain")}
        for record in parent_manifest.to_dict("records"):
            if int(record["reservoir_seed"]) == spec["seed"] and json.loads(record["spec_json"]) == legacy_spec:
                reused = parent / "ridge/fits" / record["fit_id"]; break
    for item in splits:
        split = int(item["split"]); scaled, scaler = RT.standardize_from_training_origins(data, item["train"])
        scalers[str(split)] = scaler
        if reused is not None:
            original_contract = read(reused / "contract.json")
            original_metrics = pd.read_csv(reused / "validation_metrics.csv")
            _, _, audit = RT.make_reservoir(spec, int(row["input_dimension"]))
            if original_contract["reservoir_audit"][str(split)]["reservoir_sha256"] != audit["reservoir_sha256"]:
                raise RuntimeError("control reservoir differs; unsafe reuse")
            stats = BACKEND._stats_from_ridge(reused, split)
            score = original_metrics[original_metrics.split.eq(split)].iloc[0].to_dict()
        else:
            packet, audit = RT.teacher_forced_statistics(scaled, spec, {"train": item["train"]})
            stats = packet["train"]
            score = RT.recursive_normal_score(scaled, spec, RT.fit_scaled_ridge(stats), item["validation"],
                                              maximum_origins=int(control["broad_score_max_origins_per_split"]))
            for key in ("AQL", "late_AQL", "median_MAE", "interval_80_width"): score[key] *= float(scaler["price_scale"])
            score["split"] = split
        audits[str(split)] = audit; metrics.append(score)
        for name in ("XtX", "Xty", "yty", "n"):
            payload[f"split{split}_{name}"] = np.asarray(stats[name]) if name in ("XtX", "Xty") else np.asarray([stats[name]])
    verify_sources(control, lightweight=True)
    output.mkdir(parents=True)
    np.savez_compressed(output / "training_statistics.npz", **payload)
    pd.DataFrame(metrics).to_csv(output / "validation_metrics.csv", index=False)
    immutable_json(output / "contract.json", dict(stage="R123", spec=spec, reservoir_audit=audits,
        split_preprocessing=scalers, input_names=RT.input_names(spec, data.exog_names), washout=washout,
        reused_from=None if reused is None else str(reused), test_opened=False))
    terminal = dict(status="completed_r123_ridge_cell", fit_sha256=row["fit_sha256"],
                    fit_id=args.fit_id, candidate_id=row["candidate_id"], test_opened=False,
                    output_sha256={name: sha256_file(output / name) for name in
                                   ("contract.json", "training_statistics.npz", "validation_metrics.csv")})
    immutable_json(output / "terminal.json", terminal)
    return terminal


def rank(manifest, campaign, seeds):
    frames = []
    for row in manifest.to_dict("records"):
        root = campaign / "ridge/fits" / row["fit_id"]
        if valid_ridge(root, row["fit_sha256"]):
            metrics = pd.read_csv(root / "validation_metrics.csv")
            if len(metrics) != 3 or set(metrics.split) != {1, 2, 3}: raise RuntimeError("incomplete split metrics")
            frames.append(dict(row, mean_AQL=float(metrics.AQL.mean()), mean_late_AQL=float(metrics.late_AQL.mean()),
                               worst_AQL=float(metrics.AQL.max()), mean_coverage=float(metrics.interval_80_coverage.mean()),
                               mean_width=float(metrics.interval_80_width.mean())))
        elif not (root / "rejected_washout.json").is_file():
            raise RuntimeError(f"missing/corrupt Ridge output: {row['fit_id']}")
    if not frames: raise RuntimeError("no eligible Ridge structure")
    return BACKEND._structural_ranking(pd.DataFrame(frames), seeds)


def queue_ridge(args, manifest, label, cpus):
    tasks = []
    for row in manifest.to_dict("records"):
        output = args.campaign_root / "ridge/fits" / row["fit_id"]
        if valid_ridge(output, row["fit_sha256"]) or (output / "rejected_washout.json").is_file(): continue
        tasks.append((row["fit_id"], [sys.executable, str(Path(__file__).resolve()), "--mode", "ridge-cell",
            "--prep-dir", str(args.prep_dir), "--campaign-root", str(args.campaign_root),
            "--code-root", str(args.code_root), "--fit-id", row["fit_id"]],
            args.campaign_root / f"logs/{label}/{row['fit_id']}.log"))
    return BACKEND._run_queue(tasks, cpus, args.code_root, args.campaign_root / f"{label}/progress.json", len(manifest), fail_fast=True)


_normal_valid = BACKEND._normal_valid
_quantile_valid = BACKEND._quantile_output_valid
_command = BACKEND._command
_quantile_contract = BACKEND._quantile_contract
_write_design = BACKEND._write_design


def guarded_normal_valid(path):
    if not (path / "terminal.json").exists(): return False
    if not _normal_valid(path): raise RuntimeError(f"invalid Normal output preserved: {path}")
    terminal = read(path / "terminal.json")
    contract = read(path.parent.parent / f"contracts/{path.name}.json")
    if terminal["posterior_target_sha256"] != contract["posterior_target_sha256"]:
        raise RuntimeError("Normal resume target differs")
    for item in terminal["artifacts"]:
        if sha256_file(path / item["path"]) != item["sha256"]:
            raise RuntimeError("Normal output checksum differs")
    return True


def guarded_quantile_valid(path, target):
    if not (path / "terminal.json").exists(): return False
    if not _quantile_valid(path, target): raise RuntimeError(f"invalid AL output preserved: {path}")
    ledger = read(path / "r123_output_hashes.json")
    if any(sha256_file(path / name) != digest for name, digest in ledger.items()):
        raise RuntimeError("AL output checksum differs")
    return True


def guarded_command(command, code, log, cpu=None):
    if "--config" in command and "420_fit_pricefm_stage_r121_quantile_atom.R" in " ".join(command):
        contract = read(Path(command[command.index("--config") + 1]))
        output = Path(contract["output_dir"])
        if output.exists(): raise RuntimeError(f"partial AL output preserved: {output}")
        _command(command, code, log, cpu)
        immutable_json(output / "r123_output_hashes.json", {
            path.name: sha256_file(path) for path in output.iterdir() if path.is_file()})
    else:
        _command(command, code, log, cpu)


def quantile_contract(*args, **kwargs):
    result = _quantile_contract(*args, **kwargs)
    result["stage"] = "R123_internal_selection"
    result["atom_id"] = result["atom_id"].replace("r122_", "r123_", 1)
    return result


def guarded_design(path, design, response, metadata):
    if path.exists() and not (path / "terminal.json").exists():
        raise RuntimeError("partial design preserved")
    _write_design(path, design, response, metadata)
    terminal = read(path / "terminal.json")
    for name, array in (("X", design), ("y", response)):
        current = hashlib.sha256(np.ascontiguousarray(array, dtype="<f8").view(np.uint8)).hexdigest()
        if sha256_file(path / f"{name}.bin") != terminal[f"{name}_sha256"] or current != terminal[f"{name}_sha256"]:
            raise RuntimeError("saved quantile design differs from intended design")


def verify_generated(campaign):
    for label in ("center", "pilot"):
        for terminal in (campaign / f"rhs/{label}/fits").glob("*/terminal.json"):
            guarded_normal_valid(terminal.parent)
    for terminal in (campaign / "al_internal").rglob("terminal.json"):
        if read(terminal).get("status") != "completed_r121_quantile_atom": continue
        output = terminal.parent
        label = "final" if "quantiles" in output.parts else "companions"
        contract = read(output.parents[2] / f"contracts/{label}/{output.name}.json")
        guarded_quantile_valid(output, contract["posterior_target_sha256"])


BACKEND._normal_valid = guarded_normal_valid
BACKEND._quantile_output_valid = guarded_quantile_valid
BACKEND._command = guarded_command
BACKEND._quantile_contract = quantile_contract
BACKEND._write_design = guarded_design


def rhs_score(args):
    verify_preparation(args.prep_dir)
    verify_sources(read(args.prep_dir / "launch_control.json"), lightweight=True)
    return BACKEND.rhs_score(args)


def operator_cell(args):
    verify_preparation(args.prep_dir)
    control = read(args.prep_dir / "launch_control.json"); verify_sources(control, lightweight=True)
    parent = Path(control["parent_campaign"]); identifier = args.candidate_id; split = int(args.split)
    root = args.campaign_root / f"operators/cases/{identifier}/split={split}"
    if (root / "terminal.json").exists():
        terminal = read(root / "terminal.json")
        for name, digest in terminal["output_sha256"].items():
            if sha256_file(root / name) != digest: raise RuntimeError("operator output changed")
        return terminal
    if root.exists(): raise RuntimeError("partial diagnostic output preserved")
    parent_prep = args.parent_prep
    candidate_row = pd.read_csv(parent_prep / "candidate_manifest.csv")
    candidate_row = candidate_row[candidate_row.candidate_id.eq(identifier)]
    if len(candidate_row) != 1: raise ValueError("frozen diagnostic candidate missing")
    spec = RT.normalize_spec(dict(json.loads(candidate_row.iloc[0].spec_json), seed=int(RESERVOIR_SEEDS[0])))
    data = arrays(control, spec, args.prep_dir); item = RT.internal_splits(len(data.response))[split - 1]
    indices = item["validation"][np.linspace(0, len(item["validation"]) - 1, 12, dtype=int)]
    scaled, scaler = RT.standardize_from_training_origins(data, item["train"])
    ladder = parent / f"al_internal/{identifier}/split={split}"
    median = read(ladder / "contracts/final/tau=0.50.json")
    normal = RT.load_normal_fit(Path(median["parent_dir"]))
    quantiles = {q: RT.load_quantile_fit(ladder / f"quantiles/al/tau={q:.2f}") for q in RT.QUANTILES}
    values, interpretation = RT.recursive_operator_diagnostic(RT.subset_arrays(scaled, indices), spec,
        normal, quantiles, paths=500, seed=int(RESERVOIR_SEEDS[0]) + split)
    values = {key: value * scaler["price_scale"] + scaler["price_mean"] for key, value in values.items()}
    records = [dict(operator=key, candidate_id=identifier, split=split,
                    **RT.prediction_metrics(values["truth"], value)) for key, value in values.items() if key != "truth"]
    root.mkdir(parents=True)
    np.savez_compressed(root / "predictions.npz", anchors=data.anchors[indices], **values)
    pd.DataFrame(records).to_csv(root / "metrics.csv", index=False)
    immutable_json(root / "terminal.json", dict(status="R123_NO_REFIT_OPERATOR_CASE_COMPLETE", candidate_id=identifier,
        split=split, origins=12, paths=500, interpretation=interpretation, test_opened=False,
        official_validation_opened=False, output_sha256={name: sha256_file(root / name) for name in ("predictions.npz", "metrics.csv")}))
    return read(root / "terminal.json")


def operator_tasks(args):
    ranking = pd.read_csv(args.parent_campaign / "al_internal/closeout/ranking.csv")
    tasks = []
    for identifier in ranking.candidate_id:
        for split in (1, 2, 3):
            root = args.campaign_root / f"operators/cases/{identifier}/split={split}"
            if (root / "terminal.json").exists():
                operator_cell(argparse.Namespace(**dict(vars(args), candidate_id=identifier, split=split)))
                continue
            tasks.append((f"operator_{identifier}_s{split}", [sys.executable, __file__, "--mode", "operator-cell",
                "--prep-dir", str(args.prep_dir), "--campaign-root", str(args.campaign_root),
                "--parent-prep", str(args.parent_prep), "--candidate-id", identifier, "--split", str(split)],
                args.campaign_root / f"logs/operators/{identifier}_s{split}.log"))
    return tasks


def operator_closeout(campaign):
    frames = [pd.read_csv(path) for path in sorted((campaign / "operators/cases").glob("*/split=*/metrics.csv"))]
    if len(frames) != 9: raise RuntimeError("no-refit diagnostic incomplete")
    results = pd.concat(frames, ignore_index=True)
    results.to_csv(campaign / "operators/matched_metrics.csv", index=False)
    immutable_json(campaign / "operators/terminal.json", dict(status="R123_OPERATOR_DIAGNOSTIC_COMPLETE", cases=9,
        selection_authorized=False, tail_convention_not_identified=True,
        metrics_sha256=sha256_file(campaign / "operators/matched_metrics.csv"), test_opened=False))


def preflight(args, control):
    verify_sources(control)
    count = int(args.workers)
    if count < 9 or count > 15: raise ValueError("R123 requires 9..15 distinct physical workers")
    usage = BACKEND._cpu_snapshot(10)
    allowed = os.sched_getaffinity(0)
    groups = {}
    for cpu, percent in usage.items():
        groups.setdefault(BACKEND._physical(cpu), []).append((cpu, percent))
    selected = []
    for identity, siblings in sorted(groups.items()):
        representatives = [cpu for cpu, _ in siblings if cpu in allowed]
        if representatives and max(percent for _, percent in siblings) <= 20:
            selected.append(min(representatives))
    if len(selected) < count: raise RuntimeError(f"only {len(selected)} idle physical cores, need {count}")
    selected = selected[:count]
    mem = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:")) / 2**20
    disk = shutil.disk_usage(args.campaign_root.parent).free / 2**30
    if mem < 200 or disk < 200: raise RuntimeError(f"resource floor: memory={mem:.2f}, disk={disk:.2f} GiB")
    if Path(sys.executable).absolute() != Path(control["python_executable"]).absolute() or sys.prefix != control["python_prefix"]:
        raise RuntimeError("Python environment differs from frozen R122")
    result = dict(cpus=selected, workers=count, available_memory_gib=mem, free_disk_gib=disk,
                  maximum_physical_core_percent=20, sampled_seconds=10, test_opened=False)
    write_json(args.campaign_root / "preflight.json", result)
    return selected


def fit_stages(args, robust, cpus):
    prep, campaign, code = args.prep_dir, args.campaign_root, args.code_root
    control = read(prep / "launch_control.json"); protocol = read(prep / "protocol.json")
    candidates = BACKEND._ordered_candidates(prep, robust, protocol["rhs_top_k"])
    centers = {str(row.candidate_id): BACKEND._tau_center(int(row.readout_dimension), 766 * 96)
               for row in candidates.itertuples(index=False)}
    cells = BACKEND._rhs_cells(args, prep, campaign, code, cpus, candidates,
                               {key: [value] for key, value in centers.items()}, "center")
    ranking = BACKEND._complete_rhs(cells).sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"])
    if len(ranking) != protocol["rhs_top_k"]: raise RuntimeError("R123 Normal RHS shortlist incomplete")
    ids = ranking.head(protocol["rhs_tau_top_k"]).candidate_id.astype(str).tolist()
    pilot = BACKEND._rhs_cells(args, prep, campaign, code, cpus, candidates[candidates.candidate_id.isin(ids)],
        {key: [centers[key] * m for m in protocol["tau_multipliers"] if m != 1] for key in ids}, "pilot")
    pd.concat([pd.read_csv(campaign / "rhs/center/manifest.csv"), pd.read_csv(campaign / "rhs/pilot/manifest.csv")],
              ignore_index=True).to_csv(campaign / "rhs/manifest.csv", index=False)
    ranking = pd.concat([ranking, BACKEND._complete_rhs(pilot)], ignore_index=True).sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"])
    root = campaign / "rhs/closeout"; root.mkdir(parents=True, exist_ok=True)
    ranking.to_csv(root / "ranking.csv", index=False)
    chosen = BACKEND._unique_al_shortlist(ranking)
    # Existing nested public-API ladder retains fixed zero-centered priors.
    result = BACKEND._run_al(prep, campaign, code, cpus, chosen)
    return result


def controller(args):
    prep, campaign = args.prep_dir.resolve(), args.campaign_root.resolve()
    campaign.mkdir(parents=True, exist_ok=True)
    with (campaign / "controller.lock").open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        control_path = prep / "launch_control.json"
        if not control_path.exists(): prepare(args)
        verify_preparation(prep)
        control = read(control_path); verify_sources(control)
        verify_generated(campaign)
        if (campaign / "terminal.json").exists(): return read(campaign / "terminal.json")
        cpus = preflight(args, control); args.cpu_list = ",".join(map(str, cpus))
        os.sched_setaffinity(0, set(cpus))
        write_json(campaign / "running.json", dict(pid=os.getpid(), cpus=cpus, code_head=control["code_head"],
                                                    started_at_epoch=time.time(), test_opened=False))
        gate_path = prep / "prior_gate.json"
        if not gate_path.exists():
            BACKEND._command([control["rscript"], str(args.code_root / "application/tests/test_pricefm_stage_r123_prior_gate.R"),
                "--normal-runtime", control["normal_runtime"], "--cran-library", control["cran_library"],
                "--output", str(gate_path)], args.code_root, campaign / "logs/prior_gate.log", cpus[0])
        if read(gate_path).get("status") != "R123_PRIOR_GATE_PASS": raise RuntimeError("R123 prior gate failed")
        immutable_json(prep / "prior_gate_identity.json", {"sha256": sha256_file(gate_path)})
        pilot = execution(pilot_manifest(), RESERVOIR_SEEDS[:2])
        BACKEND._run_queue(operator_tasks(args), cpus, args.code_root, campaign / "operators/progress.json", 9, fail_fast=True)
        operator_closeout(campaign)
        queue_ridge(args, pilot, "pilot", cpus)
        ranked = rank(pilot, campaign, 2)
        if len(ranked) != 24: raise RuntimeError("paired connectivity pilot incomplete")
        joined = ranked.merge(pilot_manifest(), on="candidate_id", suffixes=("", "_design"))
        joined["input_policy"] = joined.spec_json.map(lambda x: json.loads(x)["input_policy"])
        # Fixed equal-weight six graph/lag blocks; exclude uniform from mandatory-coverage expansion.
        grouped = joined[joined.input_policy.ne("uniform")].groupby("input_policy").mean(numeric_only=True)
        policy = grouped.sort_values(["mean_AQL", "mean_late_AQL"]).index[0]
        immutable_json(campaign / "pilot/decision.json", dict(input_policy=str(policy),
            selection_scope="three_training_internal_splits_only", test_opened=False,
            coverage_is_model_restriction_not_proven_root_cause=True))
        ranked.to_csv(campaign / "pilot/ranking.csv", index=False)
        search = search_manifest(read(prep / "protocol.json"), str(policy))
        candidates = pd.concat([pilot_manifest(), search], ignore_index=True)
        all_fits = execution(candidates, RESERVOIR_SEEDS[:2])
        # Preparation evolves only at its declared DAG boundary, with a hash ledger.
        if len(pd.read_csv(prep / "candidate_manifest.csv")) == 24:
            candidates.to_csv(prep / "candidate_manifest.csv", index=False)
            all_fits.to_csv(prep / "execution_manifest.csv", index=False)
        else:
            BACKEND._write_immutable_csv(candidates, prep / "candidate_manifest.csv")
            BACKEND._write_immutable_csv(all_fits, prep / "execution_manifest.csv")
        immutable_json(campaign / "broad_design_identity.json", dict(
            candidate_sha256=sha256_file(prep / "candidate_manifest.csv"),
            execution_sha256=sha256_file(prep / "execution_manifest.csv"), policy=str(policy)))
        queue_ridge(args, all_fits, "broad", cpus)
        broad = rank(all_fits, campaign, 2)
        broad.to_csv(campaign / "broad/ranking.csv", index=False)
        admissible = set(candidates[candidates.spec_json.map(lambda x: json.loads(x)["input_policy"] != "uniform")].candidate_id)
        # Legacy uniform inputs remain displayed controls, not refitted quantile candidates.
        eligible_broad = broad[broad.candidate_id.isin(admissible)]
        chosen = candidates[candidates.candidate_id.isin(eligible_broad.head(50).candidate_id)].copy()
        if len(chosen) != 50: raise RuntimeError("fewer than 50 eligible third-seed structures")
        third = execution(chosen, RESERVOIR_SEEDS[2:])
        BACKEND._write_immutable_csv(third, campaign / "seed3/manifest.csv")
        queue_ridge(args, third, "seed3", cpus)
        pool = pd.concat([all_fits[all_fits.candidate_id.isin(chosen.candidate_id)], third], ignore_index=True)
        robust = rank(pool, campaign, 3)
        if len(robust) < 30: raise RuntimeError("fewer than 30 three-seed washout-eligible structures")
        robust.to_csv(campaign / "seed3/ranking.csv", index=False)
        cpus = preflight(args, control); args.cpu_list = ",".join(map(str, cpus))
        # Prior gate evidence is required before any RHS/quantile fit, not merely Ridge completion.
        gate = read(prep / "prior_gate.json")
        if gate.get("status") != "R123_PRIOR_GATE_PASS": raise RuntimeError("R123 prior gate incomplete")
        verify_sources(control)
        al = fit_stages(args, robust, cpus)
        verify_sources(control)
        verify_generated(campaign)
        completed = sum(1 for path in (campaign / "ridge/fits").glob("*/terminal.json") if valid_ridge(path.parent))
        rejected = len(list((campaign / "ridge/fits").glob("*/rejected_washout.json")))
        terminal = dict(status="R123_INTERNAL_COMPLETE_NOT_PROMOTED", tag=TAG, complete_al_families=len(al),
            ridge_completed_cells=completed, ridge_washout_rejected_cells=rejected,
            normal_rhs_completed_fits=len(pd.read_csv(campaign / "rhs/manifest.csv")), primary_al_atoms=63,
            code_head=control["code_head"], source_hashes_verified=True, test_opened=False,
            official_validation_opened=False, registry_mutated=False, article_mutated=False,
            integration_status="NOT_READY_FOR_INTEGRATION")
        immutable_json(campaign / "terminal.json", terminal)
        return terminal


def parser():
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--mode", choices=("controller", "ridge-cell", "rhs-score", "operator-cell"), default="controller")
    value.add_argument("--code-root", type=Path, default=ROOT)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_DATA.parents[2])
    value.add_argument("--prep-dir", type=Path, default=DEFAULT_DATA / "launch_prep" / TAG)
    value.add_argument("--campaign-root", type=Path, default=DEFAULT_DATA / "campaigns" / TAG)
    value.add_argument("--parent-prep", type=Path, default=DEFAULT_DATA / "launch_prep/pricefm_stage_r122_bg_long_memory_screen_20261001_rhs_calibrated_resume_20261002")
    value.add_argument("--parent-campaign", type=Path, default=DEFAULT_DATA / "campaigns/pricefm_stage_r122_bg_long_memory_screen_20261001")
    value.add_argument("--protocol", type=Path, default=PROTOCOL)
    value.add_argument("--workers", type=int, default=15)
    value.add_argument("--fit-id"); value.add_argument("--cpu-list", default="")
    value.add_argument("--candidate-id"); value.add_argument("--split", type=int); value.add_argument("--fit-dir", type=Path)
    return value


if __name__ == "__main__":
    args = parser().parse_args()
    try:
        operation = {"controller": controller, "ridge-cell": ridge_cell, "rhs-score": rhs_score,
                     "operator-cell": operator_cell}[args.mode]
        print(json.dumps(operation(args), sort_keys=True))
    except Exception as error:
        if args.mode == "controller":
            args.campaign_root.mkdir(parents=True, exist_ok=True)
            write_json(args.campaign_root / "blocked.json", dict(error_type=type(error).__name__, error=str(error),
                                                                 test_opened=False, updated_at_epoch=time.time()))
        raise
