import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r71", SCRIPTS / "241_audit_pricefm_stage_r71_r70_closeout.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_atom(model, tau, likelihood, converged=True, beta_l2=2.0, sigma=0.3):
    slug = f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")
    root = model / "components" / f"tau={slug}"
    root.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([{"pred_scaled": 0.1}]).to_csv(root / f"{likelihood}_predictions_scaled.csv", index=False)
    pd.DataFrame([{"converged": converged}]).to_csv(root / f"{likelihood}_method_summary.csv", index=False)
    pd.DataFrame([{"beta_l2": beta_l2, "sigma": sigma, "gamma": 0.0}]).to_csv(
        root / f"{likelihood}_parameter_summary.csv", index=False
    )
    pd.DataFrame([{"iter": 1}]).to_csv(root / f"{likelihood}_trace.csv", index=False)
    pd.DataFrame([{"beta_mean": 0.1}]).to_csv(root / f"{likelihood}_beta_mean.csv", index=False)
    pd.DataFrame([{"beta_cov_diag": 0.2}]).to_csv(root / f"{likelihood}_beta_cov_diag.csv", index=False)


def write_terminal(model, tau):
    slug = f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")
    root = model / "components" / f"tau={slug}"
    (root / "component_terminal.json").write_text(json.dumps({"selection_eligible": False}))


def fixture(tmp_path):
    rows, statuses = [], []
    for index, complete in enumerate((True, False)):
        case = f"case_{index}"
        model = tmp_path / "runs" / case / "model"
        model.mkdir(parents=True)
        terminal_taus = TAUS if complete else TAUS[:1]
        for tau in terminal_taus:
            for likelihood in ("al", "exal"):
                write_atom(model, tau, likelihood, converged=likelihood == "al")
            write_terminal(model, tau)
        if complete:
            pd.DataFrame([
                {"method_id": "al_method", "split": "val", "unit": "original", "AQL": 9.0},
                {"method_id": "exal_method", "split": "val", "unit": "original", "AQL": 100.0},
                {"method_id": "naive1", "split": "val", "unit": "original", "AQL": 12.0},
            ]).to_csv(model / "metric_summary.csv", index=False)
        worker = model.parent / "worker.log"
        worker.write_text(
            "END returncode=0\n" if complete
            else "Error: the leading minor of order 7 is not positive\nExecution halted\n"
        )
        rows.append({
            "case_id": case, "region": f"R{index}", "fold": index + 1,
            "output_dir": str(model), "paper_quantiles": json.dumps(TAUS),
            "expected_al_method_id": "al_method", "expected_exal_method_id": "exal_method",
            "r69a_validation_AQL_recomputed": 8.0,
            "qdesn_minus_operational_pricefm_AQL": 1.0,
            "qdesn_minus_cached_pricefm_AQL": -2.0,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "joint_model_authorized": False,
            "mcmc_authorized": False,
        })
        statuses.append({
            "case_id": case,
            "status": "completed_with_quarantine" if complete else "failed",
            "returncode": 0 if complete else 1,
            "elapsed_seconds": 10,
            "worker_log": str(worker),
        })
    manifest = tmp_path / "manifest.csv"
    status = tmp_path / "status.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False)
    pd.DataFrame(statuses).to_csv(status, index=False)
    return manifest, status


def test_r71_closes_out_and_builds_atomic_salvage_ledger(tmp_path):
    module = load()
    manifest, status = fixture(tmp_path)
    output = tmp_path / "out"
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--launch-status", str(status),
        "--output-dir", str(output), "--expected-cases", "2",
        "--expected-complete", "1", "--expected-failed", "1",
        "--expected-terminal-components", "8",
    ])
    summary = module.run(args)
    atoms = pd.read_csv(output / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv")
    failures = pd.read_csv(output / "pricefm_stage_r71_failure_atlas.csv")
    assert summary["status"] == "r70_frozen_closed_out_no_promotion"
    assert summary["terminal_paired_components"] == 8
    assert summary["missing_or_invalid_al_atoms"] == 6
    assert len(atoms) == 2 * 7 * 2
    assert set(atoms[atoms.likelihood_family == "exal"].disposition) == {
        "quarantine_r70_structured_exal_instability", "missing_exal_blocked"
    }
    assert failures.iloc[0].failure_class == "qbeta_cholesky_non_positive_definite"
    assert failures.iloc[0].leading_minor_order == 7
    assert not list(output.rglob("*.yaml"))


def test_r71_fails_closed_if_test_access_is_authorized(tmp_path):
    module = load()
    manifest, status = fixture(tmp_path)
    frame = pd.read_csv(manifest)
    frame.loc[0, "test_access_authorized"] = True
    frame.to_csv(manifest, index=False)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--launch-status", str(status),
        "--output-dir", str(tmp_path / "out"), "--expected-cases", "2",
        "--expected-complete", "1", "--expected-failed", "1",
        "--expected-terminal-components", "8",
    ])
    try:
        module.run(args)
    except RuntimeError as error:
        assert "firewall" in str(error)
    else:
        raise AssertionError("R71 accepted test access")
