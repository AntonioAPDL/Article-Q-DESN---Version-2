#!/usr/bin/env python3
"""Prepare the dependency-gated Part 1 quantile forecast launcher.

This launcher replaces the older all-at-once Part 1 quantile forecast schedule.
It keeps the already selected Part 1 Normal-DESN geometry fixed, fits the p50
AL readout first from the Normal RHS/VB fit, fans out to neighboring AL
quantiles, fits each exAL readout only after its matching AL readout exists,
and starts joint AL/exAL only after all seven corresponding independent fits
are available. No quantile synthesis is scheduled here.
"""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import textwrap


QUANTILES = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")
AL_CHAIN_DEPS = {
    "0.50": (),
    "0.35": ("independent_al_0p50",),
    "0.65": ("independent_al_0p50",),
    "0.20": ("independent_al_0p35",),
    "0.80": ("independent_al_0p65",),
    "0.05": ("independent_al_0p20",),
    "0.95": ("independent_al_0p80",),
}
AL_LAUNCH_ORDER = ("0.50", "0.35", "0.65", "0.20", "0.80", "0.05", "0.95")
DEFAULT_RUNTIME_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_part1_quantile_chain_warmstart_20260904"
)
DEFAULT_SCORE_PATH = (
    "local_trackers/runtime_configs/"
    "glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv"
)
DEFAULT_CONFIG = (
    "local_trackers/runtime_configs/"
    "glofas_fr09_shared_reference_input_p50_20260829/source/fr09_config_p50.yaml"
)
DEFAULT_RIDGE_CANDIDATE_ID = "part1wide_0150_D1_n3000__Y360_X180__a050_r090"
DEFAULT_RHS_CANDIDATE_ID = (
    "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1"
)
DEFAULT_NORMAL_RHS_FIT = (
    "local_trackers/runtime_configs/"
    "glofas_part1_all_model_forecasts_after_part2_ridge_20260903/normal_rhs_vb/"
    "objects/part1_usgs_current_winner_normal_rhs_vb_oracle_draw_recursive_fit.rds"
)
MANIFEST_COLUMNS = (
    "job_index",
    "job_id",
    "job_family",
    "likelihood",
    "quantile",
    "depends_on",
    "core_slots",
    "launch_status",
    "block_reason",
    "session_name",
    "run_label",
    "output_root",
    "fit_object_path",
    "init_fit_path",
    "init_fit_paths",
    "progress_path",
    "command",
)


def repo_root():
    return Path(__file__).resolve().parents[2]


def git_head(root):
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(root),
            universal_newlines=True,
        ).strip()
    except Exception:
        return "UNKNOWN"


def path_sha256(path):
    h = hashlib.sha256()
    with open(str(path), "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def require_repo_relative(path_text, root):
    path = Path(path_text)
    if path.is_absolute():
        resolved = path.resolve()
        try:
            return str(resolved.relative_to(root.resolve()))
        except ValueError:
            raise ValueError("Path escapes repository root: %s" % path_text)
    if ".." in path.parts:
        raise ValueError("Repository-relative paths may not contain '..': %s" % path_text)
    return str(path)


def shell_join(args):
    return " ".join(shlex.quote(str(arg)) for arg in args)


def qslug(quantile):
    return quantile.replace(".", "p")


def fit_path(runtime_root, job_id, run_label):
    return str(Path(runtime_root) / job_id / "objects" / ("%s_fit.rds" % run_label))


def output_root(runtime_root, job_id):
    return str(Path(runtime_root) / job_id)


def progress_path(runtime_root, job_id):
    return str(Path(runtime_root) / "progress" / ("%s_progress.csv" % job_id))


def quantile_run_label(job_family, likelihood, quantile):
    return "part1_usgs_%s_%s_q%s" % (job_family, likelihood.lower(), qslug(quantile))


def quantile_command(
    config_path,
    score_path,
    runtime_root,
    run_label,
    model_family,
    quantile,
    init_fit_path,
    init_fit_paths,
    progress_path_value,
    max_iter,
    min_iter,
    tol,
    tau0,
    max_dense_dim,
    rhs_vb_inner,
    exal_prefit_max_iter,
    joint_backend,
    horizon_days,
):
    args = [
        "Rscript",
        "application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R",
        "--config", config_path,
        "--score_path", score_path,
        "--runtime_root", runtime_root,
        "--run_label", run_label,
        "--target", "usgs",
        "--model_family", model_family,
        "--quantile", quantile,
        "--rank", "1",
        "--candidate_id", DEFAULT_RIDGE_CANDIDATE_ID,
        "--rhs_candidate_id", DEFAULT_RHS_CANDIDATE_ID,
        "--horizon_days", str(horizon_days),
        "--max_iter", str(max_iter),
        "--tol", str(tol),
        "--min_iter", str(min_iter),
        "--tau0", str(tau0),
        "--max_dense_dim", str(max_dense_dim),
        "--rhs_vb_inner", str(rhs_vb_inner),
        "--exal_prefit_max_iter", str(exal_prefit_max_iter),
        "--joint_backend", joint_backend,
        "--progress_path", progress_path_value,
        "--progress_every", "1",
        "--forecast_backend", "auto",
    ]
    if init_fit_path:
        args.extend(["--init_fit_path", init_fit_path])
    if init_fit_paths:
        args.extend(["--init_fit_paths", init_fit_paths])
    return shell_join(args)


def build_manifest(
    root,
    runtime_root,
    config_path,
    score_path,
    normal_rhs_fit,
    max_iter,
    min_iter,
    tol,
    tau0,
    max_parallel,
    max_dense_dim,
    rhs_vb_inner,
    horizon_days,
    session_prefix,
):
    runner = root / "application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R"
    status = "ready" if runner.is_file() else "blocked_missing_runner"
    block_reason = "" if runner.is_file() else "missing Part 1 quantile forecast runner"
    rows = []
    al_paths = {}
    exal_paths = {}

    for quantile in AL_LAUNCH_ORDER:
        job_id = "independent_al_%s" % qslug(quantile)
        run_label = quantile_run_label("independent_quantile", "AL", quantile)
        out_root = output_root(runtime_root, job_id)
        init_path = normal_rhs_fit if quantile == "0.50" else al_paths[AL_CHAIN_DEPS[quantile][0]]
        row_fit_path = fit_path(runtime_root, job_id, run_label)
        al_paths[job_id] = row_fit_path
        rows.append(
            {
                "job_index": str(len(rows) + 1),
                "job_id": job_id,
                "job_family": "independent_quantile",
                "likelihood": "AL",
                "quantile": quantile,
                "depends_on": "|".join(AL_CHAIN_DEPS[quantile]),
                "core_slots": "1",
                "launch_status": status,
                "block_reason": block_reason,
                "session_name": "%s_%02d_%s" % (session_prefix, len(rows) + 1, job_id),
                "run_label": run_label,
                "output_root": out_root,
                "fit_object_path": row_fit_path,
                "init_fit_path": init_path,
                "init_fit_paths": "",
                "progress_path": progress_path(runtime_root, job_id),
                "command": quantile_command(
                    config_path=config_path,
                    score_path=score_path,
                    runtime_root=out_root,
                    run_label=run_label,
                    model_family="independent_al",
                    quantile=quantile,
                    init_fit_path=init_path,
                    init_fit_paths="",
                    progress_path_value=progress_path(runtime_root, job_id),
                    max_iter=max_iter,
                    min_iter=min_iter,
                    tol=tol,
                    tau0=tau0,
                    max_dense_dim=max_dense_dim,
                    rhs_vb_inner=rhs_vb_inner,
                    exal_prefit_max_iter=25,
                    joint_backend="auto",
                    horizon_days=horizon_days,
                ) if status == "ready" else "",
            }
        )

    for quantile in QUANTILES:
        al_job_id = "independent_al_%s" % qslug(quantile)
        job_id = "independent_exal_%s" % qslug(quantile)
        run_label = quantile_run_label("independent_quantile", "exAL", quantile)
        out_root = output_root(runtime_root, job_id)
        row_fit_path = fit_path(runtime_root, job_id, run_label)
        exal_paths[job_id] = row_fit_path
        rows.append(
            {
                "job_index": str(len(rows) + 1),
                "job_id": job_id,
                "job_family": "independent_quantile",
                "likelihood": "exAL",
                "quantile": quantile,
                "depends_on": al_job_id,
                "core_slots": "1",
                "launch_status": status,
                "block_reason": block_reason,
                "session_name": "%s_%02d_%s" % (session_prefix, len(rows) + 1, job_id),
                "run_label": run_label,
                "output_root": out_root,
                "fit_object_path": row_fit_path,
                "init_fit_path": al_paths[al_job_id],
                "init_fit_paths": "",
                "progress_path": progress_path(runtime_root, job_id),
                "command": quantile_command(
                    config_path=config_path,
                    score_path=score_path,
                    runtime_root=out_root,
                    run_label=run_label,
                    model_family="independent_exal",
                    quantile=quantile,
                    init_fit_path=al_paths[al_job_id],
                    init_fit_paths="",
                    progress_path_value=progress_path(runtime_root, job_id),
                    max_iter=max_iter,
                    min_iter=min_iter,
                    tol=tol,
                    tau0=tau0,
                    max_dense_dim=max_dense_dim,
                    rhs_vb_inner=rhs_vb_inner,
                    exal_prefit_max_iter=0,
                    joint_backend="auto",
                    horizon_days=horizon_days,
                ) if status == "ready" else "",
            }
        )

    for likelihood, paths, model_family in (
        ("AL", al_paths, "joint_al"),
        ("exAL", exal_paths, "joint_exal"),
    ):
        job_id = "joint_%s_all7" % likelihood.lower()
        run_label = "part1_usgs_joint_quantile_%s_all7" % likelihood.lower()
        out_root = output_root(runtime_root, job_id)
        dep_ids = sorted(paths)
        init_paths = "|".join(paths[job_id_value] for job_id_value in dep_ids)
        rows.append(
            {
                "job_index": str(len(rows) + 1),
                "job_id": job_id,
                "job_family": "joint_quantile",
                "likelihood": likelihood,
                "quantile": "all7",
                "depends_on": "|".join(dep_ids),
                "core_slots": "1",
                "launch_status": status,
                "block_reason": block_reason,
                "session_name": "%s_%02d_%s" % (session_prefix, len(rows) + 1, job_id),
                "run_label": run_label,
                "output_root": out_root,
                "fit_object_path": fit_path(runtime_root, job_id, run_label),
                "init_fit_path": "",
                "init_fit_paths": init_paths,
                "progress_path": progress_path(runtime_root, job_id),
                "command": quantile_command(
                    config_path=config_path,
                    score_path=score_path,
                    runtime_root=out_root,
                    run_label=run_label,
                    model_family=model_family,
                    quantile="all7",
                    init_fit_path="",
                    init_fit_paths=init_paths,
                    progress_path_value=progress_path(runtime_root, job_id),
                    max_iter=max_iter,
                    min_iter=min_iter,
                    tol=tol,
                    tau0=tau0,
                    max_dense_dim=max_dense_dim,
                    rhs_vb_inner=rhs_vb_inner,
                    exal_prefit_max_iter=0,
                    joint_backend="blockmf",
                    horizon_days=horizon_days,
                ) if status == "ready" else "",
            }
        )

    return rows


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(path), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def render_launch_script(repo_root_path, runtime_root, max_parallel, poll_seconds):
    template = textwrap.dedent(
        """\
        #!/usr/bin/env bash
        set -euo pipefail

        REPO_ROOT=__REPO_ROOT__
        RUNTIME_ROOT=__RUNTIME_ROOT__
        JOB_MANIFEST="$RUNTIME_ROOT/configs/job_manifest.csv"
        MAX_PARALLEL=__MAX_PARALLEL__
        POLL_SECONDS=__POLL_SECONDS__

        export OMP_NUM_THREADS=1
        export OPENBLAS_NUM_THREADS=1
        export MKL_NUM_THREADS=1
        export VECLIB_MAXIMUM_THREADS=1
        export NUMEXPR_NUM_THREADS=1

        cd "$REPO_ROOT"
        mkdir -p "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/status" "$RUNTIME_ROOT/progress"

        python3 - "$REPO_ROOT" "$RUNTIME_ROOT" "$JOB_MANIFEST" "$MAX_PARALLEL" "$POLL_SECONDS" <<'PY'
        import csv
        import datetime as dt
        import os
        from pathlib import Path
        import shlex
        import subprocess
        import sys
        import time

        repo = Path(sys.argv[1])
        runtime = Path(sys.argv[2])
        manifest_path = Path(sys.argv[3])
        max_parallel = int(sys.argv[4])
        poll_seconds = int(sys.argv[5])
        status_dir = runtime / "status"
        logs_dir = runtime / "logs"

        def read_rows():
            with open(manifest_path, newline="", encoding="utf-8") as handle:
                return list(csv.DictReader(handle))

        rows = read_rows()
        by_id = {row["job_id"]: row for row in rows}

        def marker(job_id, suffix):
            return status_dir / ("%s.%s" % (job_id, suffix))

        def has_session(session):
            return subprocess.run(
                ["tmux", "has-session", "-t", session],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ).returncode == 0

        def current_state(row):
            job_id = row["job_id"]
            if marker(job_id, "done").exists():
                return "completed"
            if marker(job_id, "failed").exists():
                return "failed"
            if has_session(row["session_name"]):
                return "running"
            if marker(job_id, "launched").exists():
                return "failed"
            if row["launch_status"] != "ready":
                return "blocked"
            return "pending"

        def split_paths(text):
            if not text:
                return []
            out = []
            for chunk in text.replace(";", "|").replace(",", "|").split("|"):
                chunk = chunk.strip()
                if chunk:
                    out.append(chunk)
            return out

        def artifact_exists(path_text):
            if not path_text:
                return True
            path = Path(path_text)
            if not path.is_absolute():
                path = repo / path
            return path.is_file()

        def deps_complete(row, states):
            deps = [x for x in split_paths(row.get("depends_on", "")) if x]
            if any(states.get(dep) != "completed" for dep in deps):
                return False
            for path_text in split_paths(row.get("init_fit_path", "")) + split_paths(row.get("init_fit_paths", "")):
                if not artifact_exists(path_text):
                    return False
            return True

        def write_health(states):
            health_path = status_dir / "health_latest.csv"
            counts = {state: list(states.values()).count(state) for state in ("completed", "running", "pending", "blocked", "failed")}
            row = {
                "timestamp": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "total": str(len(rows)),
                **{key: str(value) for key, value in counts.items()},
            }
            with open(health_path, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row.keys()))
                writer.writeheader()
                writer.writerow(row)

        def launch(row):
            job_id = row["job_id"]
            session = row["session_name"]
            stdout = logs_dir / ("%s.stdout.log" % job_id)
            stderr = logs_dir / ("%s.stderr.log" % job_id)
            command = row["command"]
            shell_cmd = (
                "cd {repo} && "
                "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
                "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 && "
                "mkdir -p {outdir} {status_dir} {logs_dir} && "
                "date > {launched} && "
                "({command}) > {stdout} 2> {stderr}; "
                "rc=$?; if [ $rc -eq 0 ]; then date > {done}; "
                "else echo $rc > {failed}; fi"
            ).format(
                repo=shlex.quote(str(repo)),
                outdir=shlex.quote(str(Path(row["output_root"]))),
                status_dir=shlex.quote(str(status_dir)),
                logs_dir=shlex.quote(str(logs_dir)),
                launched=shlex.quote(str(marker(job_id, "launched"))),
                command=command,
                stdout=shlex.quote(str(stdout)),
                stderr=shlex.quote(str(stderr)),
                done=shlex.quote(str(marker(job_id, "done"))),
                failed=shlex.quote(str(marker(job_id, "failed"))),
            )
            subprocess.check_call(["tmux", "new-session", "-d", "-s", session, shell_cmd])

        while True:
            states = {row["job_id"]: current_state(row) for row in rows}
            write_health(states)
            if all(state in ("completed", "blocked", "failed") for state in states.values()):
                sys.exit(0 if not any(state == "failed" for state in states.values()) else 9)
            active = sum(state == "running" for state in states.values())
            capacity = max(0, max_parallel - active)
            for row in rows:
                if capacity <= 0:
                    break
                if states[row["job_id"]] == "pending" and deps_complete(row, states):
                    launch(row)
                    states[row["job_id"]] = "running"
                    capacity -= 1
            write_health(states)
            time.sleep(poll_seconds)
        PY
        """
    )
    return (
        template
        .replace("__REPO_ROOT__", shlex.quote(str(repo_root_path)))
        .replace("__RUNTIME_ROOT__", shlex.quote(str(repo_root_path / runtime_root)))
        .replace("__MAX_PARALLEL__", str(max_parallel))
        .replace("__POLL_SECONDS__", str(poll_seconds))
    )


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--score-path", default=DEFAULT_SCORE_PATH)
    parser.add_argument("--normal-rhs-fit", default=DEFAULT_NORMAL_RHS_FIT)
    parser.add_argument("--max-iter", type=int, default=100)
    parser.add_argument("--min-iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--tau0", type=float, default=1.0)
    parser.add_argument("--max-parallel", type=int, default=20)
    parser.add_argument("--max-dense-dim", type=int, default=4000)
    parser.add_argument("--rhs-vb-inner", type=int, default=5)
    parser.add_argument("--horizon-days", type=int, default=30)
    parser.add_argument("--poll-seconds", type=int, default=300)
    parser.add_argument("--session-prefix", default="glofas_part1_quantile_chain_20260904")
    return parser.parse_args(argv)


def prepare(args):
    root = repo_root()
    runtime_root = require_repo_relative(args.runtime_root, root)
    config_path = require_repo_relative(args.config, root)
    score_path = require_repo_relative(args.score_path, root)
    normal_rhs_fit = require_repo_relative(args.normal_rhs_fit, root)
    if args.max_iter < 1 or args.min_iter < 1 or args.min_iter > args.max_iter:
        raise ValueError("--min-iter must be between 1 and --max-iter")
    if args.tol <= 0:
        raise ValueError("--tol must be positive for the dependency-chain VB launch")
    if args.max_parallel < 1:
        raise ValueError("--max-parallel must be positive")
    rows = build_manifest(
        root=root,
        runtime_root=runtime_root,
        config_path=config_path,
        score_path=score_path,
        normal_rhs_fit=normal_rhs_fit,
        max_iter=args.max_iter,
        min_iter=args.min_iter,
        tol=args.tol,
        tau0=args.tau0,
        max_parallel=args.max_parallel,
        max_dense_dim=args.max_dense_dim,
        rhs_vb_inner=args.rhs_vb_inner,
        horizon_days=args.horizon_days,
        session_prefix=args.session_prefix,
    )
    runtime = root / runtime_root
    config_dir = runtime / "configs"
    config_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = config_dir / "job_manifest.csv"
    metadata_path = config_dir / "launcher_metadata.json"
    launch_path = runtime / "launch_chain_when_ready.sh"
    write_csv(manifest_path, rows)
    launch_path.write_text(
        render_launch_script(root, runtime_root, args.max_parallel, args.poll_seconds),
        encoding="utf-8",
    )
    launch_path.chmod(0o755)
    metadata = {
        "runtime_root": runtime_root,
        "repo_root": str(root),
        "git_head": git_head(root),
        "chain_contract": "p50 AL -> adjacent AL branches -> matching exAL -> joint AL/exAL",
        "max_iter": args.max_iter,
        "min_iter": args.min_iter,
        "tol": args.tol,
        "tau0": args.tau0,
        "max_parallel": args.max_parallel,
        "n_jobs": len(rows),
        "total_cores_requested": sum(int(row["core_slots"]) for row in rows if row["launch_status"] == "ready"),
        "normal_rhs_fit": normal_rhs_fit,
        "normal_rhs_fit_exists": (root / normal_rhs_fit).is_file(),
        "normal_rhs_fit_sha256": path_sha256(root / normal_rhs_fit) if (root / normal_rhs_fit).is_file() else None,
        "synthesis_enabled": False,
        "joint_backend": "blockmf",
        "manifest_sha256": path_sha256(manifest_path),
        "launch_script": str(launch_path),
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    readme = runtime / "README.md"
    readme.write_text(
        textwrap.dedent(
            f"""\
            # GloFAS Part 1 Quantile Chain Warm-Start Launcher

            This runtime bundle fits and forecasts Part 1 USGS-only quantile DESN
            readouts without synthesis.

            Dependency order:

            1. Fit `0.50 AL` from the retained Normal RHS/VB fit.
            2. Fit `0.35 AL` and `0.65 AL` from `0.50 AL`.
            3. Fit `0.20 AL` from `0.35 AL`, and `0.80 AL` from `0.65 AL`.
            4. Fit `0.05 AL` from `0.20 AL`, and `0.95 AL` from `0.80 AL`.
            5. Fit each matching `tau exAL` only after the same `tau AL` exists.
            6. Fit joint AL after all seven AL fits exist.
            7. Fit joint exAL after all seven exAL fits exist.

            Controls: `max_iter={args.max_iter}`, `min_iter={args.min_iter}`,
            `tol={args.tol}`, `tau0={args.tau0}`, one core per model, up to
            `{args.max_parallel}` concurrent tmux workers.

            Launch manually with:

            ```bash
            tmux new-session -d -s {args.session_prefix}_scheduler \\
              "cd {root} && bash {launch_path}"
            ```
            """
        ),
        encoding="utf-8",
    )
    return {
        "runtime_root": str(runtime),
        "manifest": str(manifest_path),
        "metadata": str(metadata_path),
        "launcher": str(launch_path),
        "readme": str(readme),
    }


def main(argv=None):
    result = prepare(parse_args(argv))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
