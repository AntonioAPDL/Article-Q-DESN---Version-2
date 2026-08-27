import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_case(repo, case_id, region, fold):
    run = repo / "legacy" / case_id
    cell = run / "cells" / f"region={region}" / f"fold={fold}"
    (cell / "adapter").mkdir(parents=True)
    data = repo / "data.yaml"
    data.write_text("pricefm:\n  regions: [AA]\n")
    smoke = {"pricefm_desn_smoke": {
        "data_config": "data.yaml", "package_path": str(repo / "package"),
        "region": region, "fold": fold, "splits": ["train", "val", "test"],
        "horizons": list(range(1, 97)), "quantiles": [0.5], "feature_policy": "target_only",
        "adapter": {"output_dir": str(cell / "adapter"), "feature_map": "window_reservoir_v1", "feature_dim": 8, "depth": 1, "units": [8], "alpha": 0.2, "rho": 0.95, "input_scale": 0.2, "projection_scale": 1.0, "recurrent_sparsity": 0.05, "state_output": "final_layer", "seed": 11},
        "run": {"output_dir": str(cell / "model"), "seed": 11},
        "rhs_ns": {"tau0": 0.001}, "qdesn_vb": {"likelihoods": ["al", "exal"]},
        "exact_equivalence": {"enabled": True, "quantile": 0.5},
        "training": {"train_origin_limit": 10, "train_origin_selection": "tail"},
        "warm_start": {"qdesn": {"al": {"tau_order": [0.5]}}},
    }}
    path = cell / "config.yaml"
    path.write_text(yaml.safe_dump(smoke, sort_keys=False))
    return run, path


def test_gap_prep_materializes_exact_train_validation_jobs(tmp_path, monkeypatch):
    module = load("r62gap_prep", "217_prepare_pricefm_stage_r62_gap_completion.py")
    repo = tmp_path / "repo"; repo.mkdir(); (repo / "package").mkdir()
    r62 = tmp_path / "r62"; r62.mkdir()
    gaps = []
    authority = []
    for index in range(2):
        case = f"pricefm_joint_aa_f{index + 1}"
        run, config = source_case(repo, case, "AA", index + 1)
        gaps.append({"case_id": case, "region": "AA", "fold": index + 1, "match_status": "exact_comparator_missing"})
        authority.append({"case_id": case, "source_config": str(config), "likelihood_family": "al"})
    pd.DataFrame(gaps).to_csv(r62 / "pricefm_stage_r62_exact_coverage_gaps.csv", index=False)
    authority_path = tmp_path / "authority.csv"; pd.DataFrame(authority).to_csv(authority_path, index=False)
    monkeypatch.setattr(module, "git_head", lambda _path: "a" * 40)
    args = module.parser().parse_args([
        "--artifact-repo", str(repo), "--r62-dir", str(r62),
        "--r57-authority", str(authority_path), "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"), "--output-dir", str(tmp_path / "output"),
        "--expected-gaps", "2",
    ])
    summary = module.run(args)
    manifest = pd.read_csv(tmp_path / "grid/launch_manifest.csv")
    assert summary["quantile_jobs"] == 14
    assert manifest.groupby("source_case_id").size().eq(7).all()
    assert manifest.launch_authorized.eq(False).all()
    for path in manifest.config:
        smoke = yaml.safe_load(Path(path).read_text())["pricefm_desn_smoke"]
        assert smoke["splits"] == ["train", "val"]
        assert smoke["python_bin"] == str(module.PYTHON.absolute())
        assert Path(smoke["data_config"]).is_absolute()
        assert Path(smoke["data_config"]).is_file()
        assert yaml.safe_load(Path(smoke["data_config"]).read_text())["pricefm"]["allow_absolute_local_paths"] is True
        assert smoke["qdesn_vb"]["likelihoods"] == ["al", "exal"]


def test_smoke_runner_accepts_configured_python_environment():
    source = (SCRIPTS / "08_run_desn_model_smoke.R").read_text()
    assert 'cfg$python_bin %||% "application/data_local/pricefm/venv/bin/python"' in source
    assert "system2(python_bin, cmd)" in source


def test_gap_closeout_recomputes_panel_validation_aql(tmp_path):
    module = load("r62gap_closeout", "219_closeout_pricefm_stage_r62_gap_completion.py")
    rows = []; status = []
    for index, tau in enumerate(module.METHODS and (0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9)):
        model = tmp_path / f"run{index}/model"; model.mkdir(parents=True)
        pd.DataFrame([
            {"method_id": module.METHODS[0], "split": "val", "unit": "original", "AQL": 1 + index, "AQCR": 0, "MAE": 2, "RMSE": 3},
            {"method_id": module.METHODS[1], "split": "val", "unit": "original", "AQL": 2 + index, "AQCR": 0, "MAE": 3, "RMSE": 4},
        ]).to_csv(model / "metric_summary.csv", index=False)
        rows.append({"case_id": f"case{index}", "region": "AA", "fold": 1, "tau": tau, "output_dir": str(model), "adapter_dir": str(model.parent / "adapter")})
        status.append({"case_id": f"case{index}", "status": "completed"})
    manifest = tmp_path / "manifest.csv"; launch = tmp_path / "status.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False); pd.DataFrame(status).to_csv(launch, index=False)
    args = module.parser().parse_args(["--manifest", str(manifest), "--launch-status", str(launch), "--output-dir", str(tmp_path / "output")])
    summary = module.run(args)
    metric = pd.read_csv(tmp_path / "output/panel_metric.csv")
    assert summary["complete_jobs"] == 7
    assert metric.loc[metric.method_id.eq(module.METHODS[0]), "AQL"].iloc[0] == 4.0
    assert set(metric.split) == {"val"}


def test_launcher_requires_explicit_authorization(tmp_path):
    module = load("r62gap_launch", "218_launch_pricefm_stage_r62_gap_completion.py")
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame([{"case_id": "x", "launch_authorized": False, "test_access_authorized": False}]).to_csv(manifest, index=False)
    args = module.parser().parse_args(["--code-root", str(ROOT), "--manifest", str(manifest), "--cpu-list", "1"])
    try:
        module.run(args)
    except RuntimeError as exc:
        assert "--authorize true" in str(exc)
    else:
        raise AssertionError("launcher did not enforce explicit authorization")


def test_launcher_recognizes_durable_fit_for_postfit_resume(tmp_path):
    module = load("r62gap_launch_resume", "218_launch_pricefm_stage_r62_gap_completion.py")
    output = tmp_path / "model"
    output.mkdir()
    assert not module.fit_artifacts_complete(output)
    for name in ("model_predictions_scaled.csv", "model_method_summary.csv", "run_manifest.json"):
        (output / name).write_text("durable\n")
    assert module.fit_artifacts_complete(output)


def test_launcher_preserves_virtualenv_symlink():
    source = (SCRIPTS / "218_launch_pricefm_stage_r62_gap_completion.py").read_text()
    assert "args.python_bin.absolute()" in source
    assert "args.python_bin.resolve()" not in source
