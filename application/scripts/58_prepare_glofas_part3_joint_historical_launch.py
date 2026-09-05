#!/usr/bin/env python3
"""Prepare a fail-closed GloFAS Part 3 joint historical launch bundle.

This script does not launch models. It writes a reproducible launch manifest for
the stage that will combine a frozen G1 reference winner and a frozen G2
discrepancy winner. The real execution remains blocked until those winners are
selected and an operator explicitly runs the generated commands.
"""

import argparse
import csv
import datetime as _dt
import json
import shlex
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


QUANTILES = ["0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95"]

REQUIRED_WINNER_COLUMNS = {
    "component",
    "stage",
    "candidate_id",
    "source_runtime_root",
    "score_path",
    "method",
    "status",
    "winner_role",
    "n_vector",
    "m",
    "output_lag_max",
    "covariate_lag_max",
    "washout",
    "alpha",
    "rho",
    "seed",
    "rhs_tau0",
    "design_hash",
    "frozen",
}


def _truthy(value: object) -> bool:
    return str(value).strip().lower() in {"true", "t", "yes", "y", "1"}


def _read_csv(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_winner_manifest(path: Path, require_frozen: bool = True) -> Tuple[bool, str, Dict[str, str], Dict[str, str]]:
    if not path.exists():
        return False, f"winner manifest missing: {path}", {}, {}
    rows = _read_csv(path)
    if not rows:
        return False, "winner manifest is empty", {}, {}
    missing = sorted(REQUIRED_WINNER_COLUMNS.difference(rows[0].keys()))
    if missing:
        return False, "winner manifest missing columns: " + ", ".join(missing), {}, {}
    keyed = {}
    for row in rows:
        component = row["component"].strip().lower()
        stage = row["stage"].strip().upper()
        keyed[(component, stage)] = row
    expected = {
        ("reference", "G1"): "G1/reference",
        ("discrepancy", "G2"): "G2/discrepancy",
    }
    for key, label in expected.items():
        if key not in keyed:
            return False, f"winner manifest missing {label}", {}, {}
    selected = [keyed[("reference", "G1")], keyed[("discrepancy", "G2")]]
    if require_frozen and not all(_truthy(row["frozen"]) for row in selected):
        return False, "winner manifest is present but not frozen", selected[0], selected[1]
    return True, "winner manifest valid", selected[0], selected[1]


def build_manifest_rows(
    run_label: str,
    winner_status: Optional[Tuple[bool, str, Dict[str, str], Dict[str, str]]] = None,
) -> List[Dict[str, str]]:
    winner_valid = False
    winner_message = "no winner manifest supplied"
    ref = {}
    disc = {}
    if winner_status is not None:
        winner_valid, winner_message, ref, disc = winner_status

    rows = []

    def add(model_family: str, quantile: str = "", status: Optional[str] = None) -> None:
        depends_on = ""
        if status is None:
            if model_family == "normal_ridge_joint":
                status = "ready_after_operator_launch_approval" if winner_valid else "blocked_missing_frozen_g1_g2_winner_manifest"
            elif model_family == "normal_rhs_vb_joint":
                depends_on = "normal_ridge_joint"
                status = "blocked_until_normal_ridge_joint_completed" if winner_valid else "blocked_missing_frozen_g1_g2_winner_manifest"
            else:
                status = "implemented_via_separate_part3_quantile_forecast_continuation"
        rows.append(
            {
                "run_label": run_label,
                "job_id": model_family if not quantile else f"{model_family}_{quantile}",
                "model_family": model_family,
                "quantile": quantile,
                "depends_on": depends_on,
                "worker_slots": "1",
                "status": status,
                "winner_manifest_status": winner_message,
                "selected_reference_candidate_id": ref.get("candidate_id", ""),
                "selected_discrepancy_candidate_id": disc.get("candidate_id", ""),
                "launch_command": "",
            }
        )

    add("normal_ridge_joint")
    add("normal_rhs_vb_joint")
    for q in QUANTILES:
        add("independent_al_rhs_vb", q)
    for q in QUANTILES:
        add("independent_exal_rhs_vb", q)
    add("joint_al_rhs_vb")
    add("joint_exal_rhs_vb")
    return rows


def write_csv(path: Path, rows: Iterable[Dict[str, str]]) -> None:
    rows = list(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def prepare_bundle(args: argparse.Namespace) -> Dict[str, object]:
    repo_root = Path(args.repo_root).resolve()
    run_label = args.run_label
    runtime_root = Path(args.runtime_root) if args.runtime_root else repo_root / "local_trackers" / "runtime_configs" / run_label
    runtime_root = runtime_root.resolve()
    configs_dir = runtime_root / "configs"
    scripts_dir = runtime_root / "scripts"
    logs_dir = runtime_root / "logs"
    for directory in (configs_dir, scripts_dir, logs_dir):
        directory.mkdir(parents=True, exist_ok=True)

    winner_status = None
    if args.winner_manifest:
        winner_status = validate_winner_manifest(
            Path(args.winner_manifest).resolve(),
            require_frozen=not args.allow_unfrozen,
        )
    rows = build_manifest_rows(run_label, winner_status=winner_status)
    ridge_warm_start_path = runtime_root / "objects" / "normal_ridge_joint_warm_start.rds"
    if winner_status is not None and winner_status[0]:
        winner_manifest_path = str(Path(args.winner_manifest).resolve())
        for row in rows:
            if row["model_family"] in {"normal_ridge_joint", "normal_rhs_vb_joint"}:
                command = [
                    "Rscript",
                    "application/scripts/59_run_glofas_part3_joint_historical_worker.R",
                    "--base_config",
                    shlex.quote(args.base_config),
                    "--runtime_root",
                    shlex.quote(str(runtime_root)),
                    "--winner_manifest",
                    shlex.quote(winner_manifest_path),
                    "--model_family",
                    shlex.quote(row["model_family"]),
                    "--progress_every",
                    "1",
                ]
                if row["model_family"] == "normal_rhs_vb_joint":
                    command.extend(
                        [
                            "--ridge_warm_start_path",
                            shlex.quote(str(ridge_warm_start_path)),
                            "--ridge_warm_start_sha256",
                            '"$(sha256sum "' + str(ridge_warm_start_path) + '" | awk \'{print $1}\')"',
                        ]
                    )
                row["launch_command"] = " ".join(command)
    manifest_path = configs_dir / "part3_model_manifest.csv"
    write_csv(manifest_path, rows)

    launch_path = scripts_dir / "launch_part3_joint_historical.sh"
    ridge_command = next(
        (row["launch_command"] for row in rows if row["model_family"] == "normal_ridge_joint"),
        "",
    ) or 'echo "Part 3 launch is blocked: frozen G1/G2 winner manifest missing." >&2; exit 24'
    rhs_command = next(
        (row["launch_command"] for row in rows if row["model_family"] == "normal_rhs_vb_joint"),
        "",
    ) or 'echo "Part 3 launch is blocked: frozen G1/G2 winner manifest missing." >&2; exit 24'
    launch_path.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                f"cd {shlex.quote(str(repo_root))}",
                "export OMP_NUM_THREADS=1",
                "export OPENBLAS_NUM_THREADS=1",
                "export MKL_NUM_THREADS=1",
                "export VECLIB_MAXIMUM_THREADS=1",
                "export NUMEXPR_NUM_THREADS=1",
                f"RUNTIME_ROOT={shlex.quote(str(runtime_root))}",
                'RIDGE_DONE="$RUNTIME_ROOT/status/normal_ridge_joint.completed"',
                'RIDGE_RUNNING="$RUNTIME_ROOT/status/normal_ridge_joint.running"',
                'RIDGE_FAILED="$RUNTIME_ROOT/status/normal_ridge_joint.failed"',
                'RHS_DONE="$RUNTIME_ROOT/status/normal_rhs_vb_joint.completed"',
                'RHS_RUNNING="$RUNTIME_ROOT/status/normal_rhs_vb_joint.running"',
                'RHS_FAILED="$RUNTIME_ROOT/status/normal_rhs_vb_joint.failed"',
                'PREFLIGHT_DONE="$RUNTIME_ROOT/status/part3_preflight.completed"',
                'if [[ ! -f "$PREFLIGHT_DONE" ]]; then',
                "  Rscript application/scripts/70_preflight_glofas_part3_joint_historical.R "
                f"--base_config {shlex.quote(args.base_config)} "
                ' --runtime_root "$RUNTIME_ROOT" '
                f"--winner_manifest {shlex.quote(winner_manifest_path if winner_status is not None and winner_status[0] else '')}",
                "fi",
                'test -f "$PREFLIGHT_DONE"',
                'if [[ -f "$RIDGE_FAILED" || -f "$RHS_FAILED" ]]; then',
                '  echo "A prior Part 3 failure marker exists; inspect before retrying." >&2',
                "  exit 21",
                "fi",
                'if [[ -f "$RIDGE_RUNNING" && ! -f "$RIDGE_DONE" ]]; then',
                '  echo "Ridge has a running marker; refusing to duplicate it." >&2',
                "  exit 22",
                "fi",
                'if [[ ! -f "$RIDGE_DONE" ]]; then',
                f"  {ridge_command}",
                "fi",
                'test -f "$RIDGE_DONE"',
                f"test -f {shlex.quote(str(ridge_warm_start_path))}",
                'if [[ -f "$RHS_RUNNING" && ! -f "$RHS_DONE" ]]; then',
                '  echo "RHS has a running marker; refusing to duplicate it." >&2',
                "  exit 23",
                "fi",
                'if [[ ! -f "$RHS_DONE" ]]; then',
                f"  {rhs_command}",
                "fi",
                'test -f "$RHS_DONE"',
                "Rscript application/scripts/60_check_glofas_part3_joint_historical.R --runtime_root \"$RUNTIME_ROOT\"",
                "",
            ]
        ),
        encoding="utf-8",
    )
    launch_path.chmod(0o755)

    metadata = {
        "run_label": run_label,
        "created_at": _dt.datetime.now(_dt.timezone.utc).isoformat(),
        "repo_root": str(repo_root),
        "runtime_root": str(runtime_root),
        "base_config": args.base_config,
        "winner_manifest": args.winner_manifest,
        "manifest_path": str(manifest_path),
        "launch_path": str(launch_path),
        "preflight_required": True,
        "ridge_warm_start_path": str(ridge_warm_start_path),
        "model_slots": len(rows),
        "normal_slots": sum(row["model_family"].startswith("normal_") for row in rows),
        "quantile_slots": sum(
            row["model_family"]
            in {
                "independent_al_rhs_vb",
                "independent_exal_rhs_vb",
                "joint_al_rhs_vb",
                "joint_exal_rhs_vb",
            }
            for row in rows
        ),
        "launched": False,
    }
    metadata_path = configs_dir / "part3_launch_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="Repository/worktree root.")
    parser.add_argument("--run-label", default="glofas_part3_joint_historical_deferred_20260903")
    parser.add_argument("--runtime-root", default="", help="Optional output runtime root.")
    parser.add_argument(
        "--base-config",
        default="local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
        help="Base GloFAS p50 configuration to use when the deferred normal workers are eventually launched.",
    )
    parser.add_argument("--winner-manifest", default="", help="Frozen G1/G2 winner manifest CSV.")
    parser.add_argument("--allow-unfrozen", action="store_true", help="Testing-only: allow an unfrozen winner manifest.")
    return parser.parse_args()


def main() -> int:
    metadata = prepare_bundle(parse_args())
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
