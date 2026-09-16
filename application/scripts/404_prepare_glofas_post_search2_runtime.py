#!/usr/bin/env python3
"""Prepare the post-Search-II Part 1-4 GloFAS execution DAG."""

import argparse
import csv
import hashlib
import json
import shlex
import subprocess
from datetime import datetime, timezone
from pathlib import Path


TAUS = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")
AL_ORDER = ("0.50", "0.35", "0.65", "0.20", "0.80", "0.05", "0.95")
AL_PARENT = {"0.50": None, "0.35": "0.50", "0.65": "0.50", "0.20": "0.35",
             "0.80": "0.65", "0.05": "0.20", "0.95": "0.80"}


def repo_root():
    return Path(__file__).resolve().parents[2]


def resolve(path):
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def relative(path):
    try:
        return str(path.resolve().relative_to(repo_root()))
    except ValueError:
        return str(path.resolve())


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*args):
    return subprocess.check_output(["git"] + list(args), cwd=str(repo_root()),
                                   universal_newlines=True).strip()


def source_files(args):
    files = list((repo_root() / "application" / "R").glob("*.R"))
    files += [repo_root() / "application" / "scripts" / name for name in (
        "381_run_glofas_dec25_final_refit_job.R",
        "386_run_glofas_part4_latent_family_job.R",
        "403_run_glofas_post_search2_support_job.R",
        "404_prepare_glofas_post_search2_runtime.py",
        "405_launch_glofas_post_search2_dag.py",
        "406_check_glofas_post_search2_dag.py",
    )]
    files += [
        repo_root() / "application" / "src" / "glofas_external_driver_forecast.cpp",
        resolve(args.part4_base_config), resolve(args.selected_components), resolve(args.base_config),
    ]
    return sorted(set(path.resolve() for path in files))


def qslug(tau):
    return "q" + tau.replace(".", "p")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def add(rows, job_id, part, stage, command,
        dependencies=(), model_family="", tau="", role=""):
    rows.append({
        "job_id": job_id,
        "part": part,
        "stage": stage,
        "model_family": model_family,
        "tau": tau,
        "dependencies": "|".join(dependencies),
        "worker_slots": 1,
        "role": role,
        "command_json": json.dumps(command),
    })


def common_support(args, runtime, job_id, job_type):
    return [
        "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
        "--runtime_root", relative(runtime), "--job_id", job_id, "--job_type", job_type,
        "--base_config", args.base_config,
        "--selected_components", args.selected_components,
        "--calibration_path", relative(runtime / "configs" / "full_data_rhs_calibration.csv"),
        "--part2_runtime_root", relative(runtime), "--part3_runtime_root", relative(runtime),
        "--part4_runtime_root", relative(resolve(args.part4_runtime_root)),
        "--part4_base_config", args.part4_base_config, "--part4_run_label", args.part4_run_label,
        "--max_iter", str(args.max_iter), "--min_iter", str(args.min_iter),
        "--tol", str(args.tol), "--n_draws", str(args.n_draws),
        "--seed", str(args.seed), "--forecast_backend", args.forecast_backend,
        "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
        "--min_beta_updates", str(args.min_beta_updates),
    ]


def bridge_command(args, runtime, part, job_id, job_type,
                   model_family="", tau="", fit_job_id="", init_ids="", method=""):
    return [
        "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        "--runtime_root", relative(runtime), "--part", part, "--job_id", job_id,
        "--job_type", job_type, "--model_family", model_family, "--tau", tau,
        "--fit_job_id", fit_job_id, "--init_fit_job_ids", init_ids,
        "--method", method, "--base_config", args.base_config,
        "--selected_components", args.selected_components,
        "--calibration_path", relative(runtime / "configs" / "full_data_rhs_calibration.csv"),
        "--normal_driver_bank_path", relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"),
        "--origin_date", "2022-12-25", "--horizon_days", "30",
        "--max_iter", str(args.max_iter), "--min_iter", str(args.min_iter),
        "--tol", str(args.tol), "--normal_draws", str(args.n_draws),
        "--seed", str(args.seed), "--forecast_backend", args.forecast_backend,
        "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
        "--min_beta_updates", str(args.min_beta_updates),
    ]


def support_command(args, runtime, job_id, job_type, **values):
    cmd = common_support(args, runtime, job_id, job_type)
    for name, value in values.items():
        cmd.extend(["--" + name, str(value)])
    return cmd


def build_part123(args, runtime):
    rows = []
    add(rows, "part1_design", "part1", "design", support_command(args, runtime, "part1_design", "part1_design"), role="selected_reference_design")
    for part in ("part2", "part3"):
        jid = f"{part}_design"
        add(rows, jid, part, "design", bridge_command(args, runtime, part, jid, "design_cache"), role="selected_component_design")

    add(rows, "part1_fit_normal_ridge", "part1", "fit",
        support_command(args, runtime, "part1_fit_normal_ridge", "part1_fit", model_family="normal_ridge"),
        ("part1_design",), "normal_ridge", role="full_data_ridge")
    add(rows, "part2_fit_normal_ridge", "part2", "fit",
        bridge_command(args, runtime, "part2", "part2_fit_normal_ridge", "fit", model_family="normal_ridge"),
        ("part2_design",), "normal_ridge", role="full_data_ridge")
    add(rows, "full_data_rhs_calibration", "shared", "calibration",
        support_command(args, runtime, "full_data_rhs_calibration", "calibration"),
        ("part1_fit_normal_ridge", "part2_fit_normal_ridge"), role="full_data_tau0_calibration")

    add(rows, "part1_fit_normal_rhs_vb", "part1", "fit",
        support_command(args, runtime, "part1_fit_normal_rhs_vb", "part1_fit", model_family="normal_rhs_vb"),
        ("part1_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_rhs")
    add(rows, "part2_fit_normal_rhs_vb", "part2", "fit",
        bridge_command(args, runtime, "part2", "part2_fit_normal_rhs_vb", "fit", model_family="normal_rhs_vb"),
        ("part2_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_rhs")

    add(rows, "part3_fit_normal_ridge", "part3", "fit",
        bridge_command(args, runtime, "part3", "part3_fit_normal_ridge", "fit", model_family="normal_ridge"),
        ("part3_design",), "normal_ridge", role="full_data_joint_ridge")
    add(rows, "part3_fit_normal_rhs_vb", "part3", "fit",
        bridge_command(args, runtime, "part3", "part3_fit_normal_rhs_vb", "fit", model_family="normal_rhs_vb"),
        ("part3_fit_normal_ridge", "full_data_rhs_calibration"), "normal_rhs_vb", role="full_data_joint_rhs")

    for part in ("part1", "part2", "part3"):
        for method in ("normal_ridge", "normal_rhs_vb"):
            jid = f"{part}_forecast_{method}"
            fit_id = f"{part}_fit_{method}"
            if part == "part1":
                cmd = support_command(args, runtime, jid, "part1_forecast", model_family=method,
                                      fit_job_id=fit_id,
                                      normal_driver_bank_path=relative(runtime / "objects" / "part1_normal_rhs_driver_bank.rds"))
            else:
                cmd = bridge_command(args, runtime, part, jid, "forecast", model_family=method,
                                     fit_job_id=fit_id, method="ridge" if method == "normal_ridge" else "rhs")
            add(rows, jid, part, "forecast", cmd, (fit_id,), method, role="recursive_normal_forecast")

    for part in ("part1", "part2", "part3"):
        bank_job = f"{part}_forecast_normal_rhs_vb"
        worker = "support" if part == "part1" else "bridge"
        al_ids = []
        exal_ids = []
        for tau in AL_ORDER:
            slug = qslug(tau)
            jid = f"{part}_fit_independent_al_{slug}"
            parent_tau = AL_PARENT[tau]
            parent = f"{part}_fit_normal_rhs_vb" if parent_tau is None else f"{part}_fit_independent_al_{qslug(parent_tau)}"
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family="independent_al",
                                      tau=tau, likelihood="AL", fit_structure="independent",
                                      init_fit_job_ids=parent)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", "independent_al", tau,
                                     init_ids=parent)
                cmd.extend(["--likelihood", "AL", "--fit_structure", "independent"])
            add(rows, jid, part, "fit", cmd, (parent,), "independent_al", tau, "independent_al_rhs_vb")
            al_ids.append(jid)
            fjid = f"{part}_forecast_independent_al_{slug}"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family="independent_al",
                                       tau=tau, fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", "independent_al", tau, fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), "independent_al", tau, "external_normal_driver_forecast")

        for tau in TAUS:
            slug = qslug(tau)
            al_id = f"{part}_fit_independent_al_{slug}"
            jid = f"{part}_fit_independent_exal_{slug}"
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family="independent_exal",
                                      tau=tau, likelihood="exAL", fit_structure="independent",
                                      init_fit_job_ids=al_id)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", "independent_exal", tau, init_ids=al_id)
                cmd.extend(["--likelihood", "exAL", "--fit_structure", "independent"])
            add(rows, jid, part, "fit", cmd, (al_id,), "independent_exal", tau, "independent_exal_rhs_vb")
            exal_ids.append(jid)
            fjid = f"{part}_forecast_independent_exal_{slug}"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family="independent_exal",
                                       tau=tau, fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", "independent_exal", tau, fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), "independent_exal", tau, "external_normal_driver_forecast")

        for family, likelihood, dependencies in (("joint_al", "AL", al_ids), ("joint_exal", "exAL", exal_ids)):
            jid = f"{part}_fit_{family}_all7"
            init_ids = "|".join(dependencies)
            if worker == "support":
                cmd = support_command(args, runtime, jid, "part1_fit", model_family=family,
                                      tau="all7", likelihood=likelihood, fit_structure="joint",
                                      init_fit_job_ids=init_ids)
            else:
                cmd = bridge_command(args, runtime, part, jid, "fit", family, "all7", init_ids=init_ids)
                cmd.extend(["--likelihood", likelihood, "--fit_structure", "joint"])
            add(rows, jid, part, "fit", cmd, tuple(dependencies), family, "all7", f"{family}_rhs_vb")
            fjid = f"{part}_forecast_{family}_all7"
            if worker == "support":
                fcmd = support_command(args, runtime, fjid, "part1_forecast", model_family=family,
                                       tau="all7", fit_job_id=jid,
                                       normal_driver_bank_path=relative(runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds"))
            else:
                fcmd = bridge_command(args, runtime, part, fjid, "forecast", family, "all7", fit_job_id=jid)
            add(rows, fjid, part, "forecast", fcmd, (jid, bank_job), family, "all7", "external_normal_driver_forecast")
    return rows


def build_part4(args, runtime, rows):
    anchor = "post_search2_anchor_manifest"
    add(rows, anchor, "part4", "prepare", support_command(args, runtime, anchor, "anchor_manifest"),
        ("part1_fit_normal_rhs_vb", "part2_fit_normal_rhs_vb"), role="frozen_selected_anchors")
    prior = "part4_normal_driver_prior"
    add(rows, prior, "part4", "prepare",
        support_command(args, runtime, prior, "part4_prior",
                        normal_driver_bank_path=relative(runtime / "objects" / "part3_normal_rhs_driver_bank.rds")),
        ("part3_forecast_normal_rhs_vb",), role="truth_free_28_day_joint_gaussian_prior")
    prepared = "part4_prepare_runtime"
    add(rows, prepared, "part4", "prepare", support_command(args, runtime, prepared, "part4_prepare"),
        (anchor, prior), role="part4_manifest_and_configs")

    families = [("normal_ridge_diagnostic", None), ("normal_rhs_vb_diagnostic", None)]
    families += [("independent_al_rhs_vb", tau) for tau in AL_ORDER]
    families += [("independent_exal_rhs_vb", tau) for tau in TAUS]
    families += [("joint_al_rhs_vb", None), ("joint_exal_rhs_vb", None)]
    run_label = args.part4_run_label
    part4_root = relative(resolve(args.part4_runtime_root))

    def internal_id(family, tau):
        return f"{run_label}_{family}" + (f"_p{int(round(float(tau) * 100)):02d}" if tau else "")

    def internal_dependencies(family, tau):
        if family == "normal_ridge_diagnostic": return []
        if family == "normal_rhs_vb_diagnostic": return [internal_id("normal_ridge_diagnostic", None)]
        if family == "independent_al_rhs_vb":
            parent = AL_PARENT[tau]
            return [internal_id("normal_rhs_vb_diagnostic", None) if parent is None else internal_id(family, parent)]
        if family == "independent_exal_rhs_vb": return [internal_id("independent_al_rhs_vb", tau)]
        if family == "joint_al_rhs_vb": return [internal_id("independent_al_rhs_vb", q) for q in TAUS]
        if family == "joint_exal_rhs_vb": return [internal_id("independent_exal_rhs_vb", q) for q in TAUS]
        raise ValueError(family)

    all_internal = {internal_id(f, q): (f, q) for f, q in families}
    for family, tau in families:
        iid = internal_id(family, tau)
        jid = "part4__" + iid
        deps = [prepared] + ["part4__" + dep for dep in internal_dependencies(family, tau)]
        command = ["Rscript", "application/scripts/386_run_glofas_part4_latent_family_job.R",
                   "--runtime_root", part4_root, "--job_id", iid]
        add(rows, jid, "part4", "fit", command, tuple(dict.fromkeys(deps)), family, tau or "all7", "part4_latent_family_fit")
    assert len(all_internal) == 18


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", default="local_trackers/runtime_configs/glofas_post_search2_part14_20260916")
    parser.add_argument("--part4-runtime-root", default="local_trackers/runtime_configs/glofas_part4_post_search2_normal_driver_20260916")
    parser.add_argument("--part4-run-label", default="glofas_part4_post_search2_normal_driver_20260916")
    parser.add_argument("--base-config", required=True)
    parser.add_argument("--part4-base-config", default="application/config/glofas_latent_path_al_vb_dec25_main.yaml")
    parser.add_argument("--selected-components", required=True)
    parser.add_argument("--max-iter", type=int, default=100)
    parser.add_argument("--min-iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--n-draws", type=int, default=500)
    parser.add_argument("--seed", type=int, default=20260916)
    parser.add_argument("--forecast-backend", choices=("auto", "cpp", "r"), default="cpp")
    parser.add_argument("--freeze-beta-warmup-iters", type=int, default=20)
    parser.add_argument("--min-beta-updates", type=int, default=30)
    args = parser.parse_args()
    if args.n_draws != 500:
        raise SystemExit("The adopted recursive forecast contract requires exactly 500 paths.")
    if args.max_iter < args.min_iter or args.min_iter < 30 or args.freeze_beta_warmup_iters < 0:
        raise SystemExit("Invalid VB iteration controls.")
    for source in (resolve(args.base_config), resolve(args.part4_base_config), resolve(args.selected_components)):
        if not source.exists(): raise SystemExit(f"missing required input: {source}")
    dirty = git_output("status", "--porcelain", "--untracked-files=no")
    if dirty:
        raise SystemExit("tracked worktree must be clean before production preparation")
    runtime = resolve(args.runtime_root)
    for sub in ("configs", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "figures", "scripts", "docs"):
        (runtime / sub).mkdir(parents=True, exist_ok=True)
    resolve(args.part4_runtime_root).mkdir(parents=True, exist_ok=True)
    rows = build_part123(args, runtime)
    build_part4(args, runtime, rows)
    ids = [row["job_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate job IDs in post-Search-II DAG")
    known = set(ids)
    for row in rows:
        missing = set(filter(None, row["dependencies"].split("|"))) - known
        if missing: raise SystemExit(f"unknown dependencies for {row['job_id']}: {sorted(missing)}")
    manifest = runtime / "tables" / "post_search2_job_manifest.csv"
    write_csv(manifest, rows)
    frozen_sources = source_files(args)
    missing_sources = [str(path) for path in frozen_sources if not path.is_file()]
    if missing_sources: raise SystemExit("missing frozen sources: " + ", ".join(missing_sources))
    source_manifest = runtime / "configs" / "post_search2_source_manifest.csv"
    write_csv(source_manifest, [{
        "path": relative(path), "size_bytes": path.stat().st_size, "sha256": sha256(path)
    } for path in frozen_sources])
    metadata = {
        "schema_version": "glofas_post_search2_execution_dag_v1",
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": relative(runtime),
        "part4_runtime_root": relative(resolve(args.part4_runtime_root)),
        "selection_path": relative(resolve(args.selected_components)),
        "selection_sha256": sha256(resolve(args.selected_components)),
        "git_head": git_output("rev-parse", "HEAD"),
        "git_branch": git_output("rev-parse", "--abbrev-ref", "HEAD"),
        "source_manifest": relative(source_manifest),
        "source_manifest_sha256": sha256(source_manifest),
        "source_file_count": len(frozen_sources),
        "cutoff": "2022-12-25",
        "part123_forecast_window": ["2022-12-26", "2023-01-24"],
        "part4_issued_window_days": 28,
        "n_driver_paths": args.n_draws,
        "job_count": len(rows),
        "jobs_by_part": {part: sum(row["part"] == part for row in rows) for part in ("part1", "part2", "part3", "part4", "shared")},
        "production_launched": False,
    }
    (runtime / "configs" / "post_search2_execution_contract.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    launch = runtime / "scripts" / "launch.sh"
    launch.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
        f"python3 application/scripts/405_launch_glofas_post_search2_dag.py --runtime-root {shlex.quote(relative(runtime))} --workers 5 --background\n"
    )
    launch.chmod(0o755)
    print(f"runtime_root={relative(runtime)}")
    print(f"manifest={relative(manifest)}")
    print(f"jobs={len(rows)}")
    print(json.dumps(metadata["jobs_by_part"], sort_keys=True))
    print("production_launched=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
