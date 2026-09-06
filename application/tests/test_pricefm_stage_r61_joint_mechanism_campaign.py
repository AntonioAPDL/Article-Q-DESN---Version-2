import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
TARGETS = (
    ("pricefm_joint_no_5_f2", "NO_5", "al", 2.0),
    ("pricefm_joint_se_2_f2", "SE_2", "exal", 3.0),
)


def load(name, filename):
    sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_prep_fixture(tmp_path, prep):
    r59 = tmp_path / "r59"
    authority = tmp_path / "authority"
    grid57 = tmp_path / "grid57"
    monitor60 = tmp_path / "monitor60"
    for path in (r59, authority, grid57, monitor60):
        path.mkdir()
    (r59 / "summary.json").write_text(json.dumps({
        "status": "completed_joint_scoring_contract_freeze",
        "joint_scoring_contract_frozen": True,
        "test_opened": False,
    }))
    (monitor60 / "summary.json").write_text(json.dumps({
        "status": "running", "pending_or_running": 2, "test_opened": False,
    }))

    decisions = []
    authority_rows = []
    manifest_rows = []
    atlas_rows = []
    for index, (case_id, region, likelihood, reference) in enumerate(TARGETS):
        source_config = tmp_path / f"{case_id}_source.yaml"
        source_config.write_text("source: fixture\n")
        smoke = tmp_path / f"{case_id}_smoke.yaml"
        smoke.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
            "region": region,
            "fold": 2,
            "splits": ["train", "val"],
            "quantiles": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
            "package_path": str(tmp_path / "package"),
            "data_config": str(tmp_path / "data.yaml"),
            "feature_policy": "target_only",
            "adapter": {
                "name": f"{region}_fold2",
                "output_dir": "old",
                "feature_dim": 120 if region == "NO_5" else 80,
                "depth": 1 if region == "NO_5" else 2,
                "units": [120] if region == "NO_5" else [80, 80],
                "alpha": 0.5,
                "rho": 0.9,
                "input_scale": 0.25 if region == "NO_5" else 0.2,
                "seed": 20260800 + index,
            },
            "run": {"output_dir": "old", "seed": 20260800 + index},
            "normal": {"omega_prior": {}, "vb_control": {}},
            "qdesn_vb": {
                "max_iter": 2, "min_iter_elbo": 1, "tol": 1e-4,
                "tol_par": 1e-4, "n_samp_xi": 2, "chunking": {},
                "prior_sigma": {}, "prior_gamma": {},
            },
            "rhs_ns": {"tau0": 0.001, "freeze_tau_iters": 5},
        }}, sort_keys=False))
        runtime = tmp_path / f"{case_id}_runtime.yaml"
        runtime.write_text(yaml.safe_dump({"pricefm_stage_r57_joint_vb": {
            "stage": "R57",
            "case_id": case_id,
            "region": region,
            "fold": 2,
            "likelihood_family": likelihood,
            "quantiles": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
            "a_sigma": 1.0,
            "b_sigma": 1.0,
            "max_dense_dim": 2000,
        }}, sort_keys=False))
        decisions.append({
            "case_id": case_id,
            "region": region,
            "fold": 2,
            "current_authoritative_validation_AQL": reference,
            "contract_validation_AQL": reference + 0.5,
        })
        authority_rows.append({
            "case_id": case_id,
            "region": region,
            "fold": 2,
            "likelihood_family": likelihood,
            "method_id": f"joint_{likelihood}",
            "source_method_id": f"qdesn_{likelihood}_rhs_ns_exact_chunked",
            "experiment_id": f"authority_{region}",
            "source_config": str(source_config),
            "source_config_sha256": digest(source_config),
            "current_authoritative_validation_AQL": reference,
            "feature_policy": "target_only",
            "depth": 1 if region == "NO_5" else 2,
            "units": "[120]" if region == "NO_5" else "[80, 80]",
            "tau0": 0.001,
        })
        manifest_rows.append({
            "case_id": case_id,
            "config": str(runtime),
            "smoke_config": str(smoke),
            "output_dir": str(tmp_path / "old_runs" / case_id),
        })
        fallback = prep.FALLBACKS[case_id]
        atlas_rows.append({
            "experiment_id": fallback["experiment_id"],
            "region": region,
            "fold": 2,
            "method_id": fallback["method_id"],
            "source_quantile_matches_target": True,
            "feature_dim": fallback["feature_dim"],
            "depth": fallback["depth"],
            "units": str(fallback["units"]),
            "alpha": fallback["alpha"],
            "rho": fallback["rho"],
            "input_scale": fallback["input_scale"],
            "seed": fallback["seed"],
            "val_AQL": fallback["validation_AQL"],
            "full_config": str(tmp_path / f"{case_id}_fallback.yaml"),
            "data_config": str(tmp_path / "data.yaml"),
        })
    pd.DataFrame(decisions).to_csv(
        r59 / "pricefm_stage_r59_joint_scoring_decisions.csv", index=False
    )
    pd.DataFrame(authority_rows).to_csv(
        authority / "pricefm_stage_r57_joint_case_authority.csv", index=False
    )
    pd.DataFrame(manifest_rows).to_csv(grid57 / "launch_manifest.csv", index=False)
    atlas = tmp_path / "atlas.csv"
    pd.DataFrame(atlas_rows).to_csv(atlas, index=False)
    return r59, authority, grid57, monitor60, atlas


def prepare_campaign(tmp_path, monkeypatch):
    prep = load("r61_prep", "212_prepare_pricefm_stage_r61_joint_mechanism_campaign.py")
    monkeypatch.setattr(prep, "git_head", lambda _path: "c" * 40)
    r59, authority, grid57, monitor60, atlas = write_prep_fixture(tmp_path, prep)
    output = tmp_path / "prep"
    grid61 = tmp_path / "grid61"
    runs = tmp_path / "runs61"
    args = prep.parser().parse_args([
        "--artifact-repo", str(tmp_path),
        "--r59-dir", str(r59),
        "--r57-authority-dir", str(authority),
        "--r57-grid-dir", str(grid57),
        "--r60-monitor-dir", str(monitor60),
        "--r8-atlas", str(atlas),
        "--source-root", str(ROOT),
        "--output-dir", str(output),
        "--grid-dir", str(grid61),
        "--run-dir", str(runs),
        "--python-bin", sys.executable,
    ])
    summary = prep.run(args)
    return prep, summary, r59, output, grid61


def test_r61_prep_materializes_exact_case_specific_blocked_campaign(tmp_path, monkeypatch):
    prep, summary, _r59, output, grid = prepare_campaign(tmp_path, monkeypatch)
    manifest = pd.read_csv(grid / "launch_manifest.csv")
    arms = pd.read_csv(output / "pricefm_stage_r61_joint_mechanism_arm_contract.csv")
    launch = yaml.safe_load(
        (output / "pricefm_stage_r61_joint_mechanism_launch_blocked.yaml").read_text()
    )["pricefm_stage_r61_joint_mechanism_launch"]

    assert summary["status"] == "prepared_r61_joint_mechanism_campaign_not_launched"
    assert summary["prepared_cases"] == 14
    assert summary["launch_authorized"] is False
    assert manifest.groupby("source_case_id").size().eq(7).all()
    assert all(
        set(group.arm_id) == set(prep.ARM_IDS)
        for _, group in manifest.groupby("source_case_id")
    )
    assert manifest.launch_authorized.eq(False).all()
    assert manifest.test_access_authorized.eq(False).all()
    assert arms.r60_reference_reused_not_duplicated.eq(True).all()
    assert launch["launch_authorized"] is False
    assert launch["r60_closeout_must_be_checked_before_launch"] is True
    assert launch["drop_case_arms_if_r60_already_resolved"] is True

    for row in manifest.itertuples(index=False):
        cfg = yaml.safe_load(Path(row.config).read_text())[
            "pricefm_stage_r61_joint_mechanism"
        ]
        smoke = yaml.safe_load(Path(row.smoke_config).read_text())["pricefm_desn_smoke"]
        assert cfg["allowed_splits"] == ["train", "val"]
        assert cfg["test_access_authorized"] is False
        assert cfg["max_iter"] == 150
        assert set(cfg["rhs_control"]) == {
            "anchor_tau0", "innovation_tau0", "anchor_init_tau",
            "innovation_init_tau", "freeze_iters", "vb_inner",
        }
        assert smoke["splits"] == ["train", "val"]
        assert not any(key.endswith("test") for key in smoke.get("adapter", {}))

    alternate = manifest[manifest.arm_id.eq("alternate_likelihood")]
    assert alternate.set_index("source_case_id").likelihood_family.to_dict() == {
        "pricefm_joint_no_5_f2": "exal",
        "pricefm_joint_se_2_f2": "al",
    }


def make_completed_arm(model, source_case_id, contract_aql, raw_aql, final_change, slope):
    model.mkdir(parents=True, exist_ok=True)
    checkpoint = model / "joint_vb_initialization.rds"
    checkpoint.write_bytes(b"r61-v2-checkpoint")
    source_manifest = model / "source_manifest.csv"
    source_manifest.write_text("label,path,sha256\nfixture,fixture,abc\n")
    pd.DataFrame([{"block": "anchor", "tau": 0.1}]).to_csv(
        model / "rhs_block_diagnostics.csv", index=False
    )
    pd.DataFrame([
        {
            "prediction_role": "raw_joint", "split": "val",
            "unit": "original", "AQL": raw_aql,
        },
        {
            "prediction_role": "monotone_contract", "split": "val",
            "unit": "original", "AQL": contract_aql,
        },
    ]).to_csv(model / "raw_contract_metric_summary.csv", index=False)
    (model / "job_summary.json").write_text(json.dumps({
        "status": "completed",
        "postfit_repaired": True,
        "source_case_id": source_case_id,
        "converged": False,
        "final_max_change": final_change,
        "last5_change_slope": slope,
        "contract_crossing_pairs": 0,
        "checkpoint": str(checkpoint),
        "checkpoint_sha256": digest(checkpoint),
        "output_checkpoint_format": "pricefm_joint_vb_checkpoint_v2",
        "source_manifest": str(source_manifest),
        "source_manifest_sha256": digest(source_manifest),
        "split_firewall": "train_validation_only",
        "test_accessed": False,
    }))


def test_r61_closeout_freezes_validation_proposals_without_opening_test(tmp_path, monkeypatch):
    _prep, _summary, r59, _output, grid = prepare_campaign(tmp_path, monkeypatch)
    manifest_path = grid / "launch_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    for row in manifest.itertuples(index=False):
        reference = 2.0 if row.region == "NO_5" else 3.0
        if row.region == "NO_5" and row.arm_id == "joint_safe_tau_start":
            contract, final_change, slope = 1.8, 0.2, -0.01
        elif row.region == "SE_2" and row.arm_id == "alternate_likelihood":
            contract, final_change, slope = 2.8, 1.2, 0.01
        else:
            contract, final_change, slope = reference + 0.2, 0.3, -0.01
        make_completed_arm(
            Path(row.output_dir), row.source_case_id, contract,
            contract + 0.1, final_change, slope,
        )

    closeout = load("r61_closeout", "214_closeout_pricefm_stage_r61_joint_mechanism_campaign.py")
    output = tmp_path / "closeout"
    args = closeout.parser().parse_args([
        "--r59-dir", str(r59),
        "--manifest", str(manifest_path),
        "--output-dir", str(output),
    ])
    result = closeout.run(args)
    decisions = pd.read_csv(output / "pricefm_stage_r61_case_decisions.csv")
    test_queue = pd.read_csv(output / "pricefm_stage_r61_sealed_test_audit_queue.csv")
    continuation = pd.read_csv(output / "pricefm_stage_r61_exact_continuation_queue.csv")

    assert result["status"] == "completed_joint_mechanism_unresolved_or_unstable"
    assert result["stable_validation_winners"] == 1
    assert result["unstable_validation_winners"] == 1
    assert result["test_opened"] is False
    assert result["test_audit_authorized"] is False
    assert test_queue.source_case_id.tolist() == ["pricefm_joint_no_5_f2"]
    assert continuation.source_case_id.tolist() == ["pricefm_joint_se_2_f2"]
    assert test_queue.test_access_authorized.eq(False).all()
    assert decisions.test_opened.eq(False).all()


def test_r61_monitor_requires_rhs_diagnostics_and_treats_postfit_failure_as_repairable(tmp_path):
    monitor = load("r61_monitor", "215_monitor_pricefm_stage_r61_joint_mechanism_campaign.py")
    model = tmp_path / "model"
    model.mkdir()
    for name in (
        "model_predictions_scaled.csv",
        "model_trace_summary.csv",
        "model_parameter_summary.csv",
        "crossing_diagnostics.csv",
        "rhs_block_diagnostics.csv",
        "joint_vb_initialization.rds",
    ):
        (model / name).write_text("fixture\n")
    (model / "job_summary.json").write_text(json.dumps({
        "status": "failed", "error": "postfit summarizer failed", "test_accessed": False,
    }))
    manifest = pd.DataFrame([{
        "case_id": "arm", "source_case_id": "source", "region": "AA",
        "fold": 1, "arm_id": "safe", "output_dir": str(model),
    }])
    frame, counts = monitor.health(manifest)
    assert bool(frame.iloc[0].repairable)
    assert counts["repairable"] == 1
    assert counts["failed_unrepairable"] == 0

    (model / "rhs_block_diagnostics.csv").unlink()
    frame, counts = monitor.health(manifest)
    assert not bool(frame.iloc[0].repairable)
    assert counts["failed_unrepairable"] == 1


def test_r61_runner_is_validation_only_and_has_no_launcher_side_effect():
    text = (SCRIPT_DIR / "213_run_pricefm_stage_r61_joint_mechanism_case.R").read_text()
    assert 'c("train", "val")' in text
    assert "test_access_authorized" in text
    assert "rhs_freeze_iters" in text
    assert "anchor_init_tau" in text
    assert "training_only_independent_quantiles" in text
    assert "203_launch_pricefm_stage_r57_joint_vb.py" not in text
    assert "registry_mutation_authorized = FALSE" in text
    assert "article_mutation_authorized = FALSE" in text
