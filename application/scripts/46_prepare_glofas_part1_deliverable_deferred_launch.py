#!/usr/bin/env python3
"""Prepare a deferred launcher for GloFAS Part 1 deliverables.

The launcher writes the requested Part 1 closeout bundle: Normal ridge, Normal
RHS/VB, seven independent AL fit-then-forecast jobs, seven independent exAL
fit-then-forecast jobs, and two explicit joint-quantile rows. It never schedules
quantile synthesis. The two normal forecasts reuse the optimized oracle
forecast adapter, and the independent quantile jobs use the audited no-synthesis
Part 1 quantile forecast runner. True joint-quantile rows remain fail-closed
unless explicitly armed because the current high-dimensional Part 1 winner
requires a scalable joint backend, not the dense prototype.
"""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import textwrap


QUANTILES = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")
DEFAULT_RUNTIME_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_part1_deliverable_bundle_deferred_20260903"
)
DEFAULT_PART2_RUNTIME_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_normal_part2_ridge_input_arch_screen_20260902_r2"
)
DEFAULT_SCORE_PATH = (
    "local_trackers/runtime_configs/"
    "glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv"
)
DEFAULT_CONFIG = (
    "local_trackers/runtime_configs/"
    "glofas_fr09_shared_reference_input_p50_20260829/source/fr09_config_p50.yaml"
)
DEFAULT_RHS_CANDIDATE_ID = (
    "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1"
)
DEFAULT_RIDGE_CANDIDATE_ID = "part1wide_0150_D1_n3000__Y360_X180__a050_r090"
DEFAULT_RHS_FIT_OBJECT = (
    "local_trackers/runtime_configs/"
    "glofas_normal_part1_oracle_realized_forecast_20260902/objects/"
    "part1_usgs_current_winner_oracle_realized_fit.rds"
)
DEFAULT_QUANTILE_MAX_ITER = 100
DEFAULT_QUANTILE_TOL = 0
DEFAULT_QUANTILE_MAX_DENSE_DIM = 4000
MANIFEST_COLUMNS = (
    "job_index",
    "job_id",
    "job_family",
    "likelihood",
    "quantile",
    "core_slots",
    "launch_status",
    "block_reason",
    "session_name",
    "run_label",
    "output_root",
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


def script_exists(root, relative_path):
    return (root / relative_path).is_file()


def normal_ridge_command(runtime_root, config_path, score_path, seed, n_draws, horizon_days):
    output_root = str(Path(runtime_root) / "normal_ridge")
    run_label = "part1_usgs_current_winner_normal_ridge_oracle_draw_recursive"
    return (
        run_label,
        output_root,
        shell_join(
            [
                "Rscript",
                "application/scripts/44_run_glofas_normal_part1_oracle_forecast.R",
                "--config",
                config_path,
                "--score_path",
                score_path,
                "--runtime_root",
                output_root,
                "--run_label",
                run_label,
                "--target",
                "usgs",
                "--method",
                "ridge",
                "--rank",
                "1",
                "--candidate_id",
                DEFAULT_RIDGE_CANDIDATE_ID,
                "--forecast_mode",
                "draw_recursive",
                "--forecast_backend",
                "auto",
                "--n_draws",
                str(n_draws),
                "--seed",
                str(seed),
                "--retain_draws",
                "false",
                "--horizon_days",
                str(horizon_days),
            ]
        ),
    )


def normal_rhs_command(runtime_root, config_path, score_path, seed, n_draws, horizon_days, rhs_fit_object):
    output_root = str(Path(runtime_root) / "normal_rhs_vb")
    run_label = "part1_usgs_current_winner_normal_rhs_vb_oracle_draw_recursive"
    return (
        run_label,
        output_root,
        shell_join(
            [
                "Rscript",
                "application/scripts/44_run_glofas_normal_part1_oracle_forecast.R",
                "--config",
                config_path,
                "--score_path",
                score_path,
                "--runtime_root",
                output_root,
                "--run_label",
                run_label,
                "--target",
                "usgs",
                "--method",
                "rhs",
                "--rank",
                "1",
                "--rhs_candidate_id",
                DEFAULT_RHS_CANDIDATE_ID,
                "--fit_object_path",
                rhs_fit_object,
                "--reuse_fit",
                "true",
                "--forecast_mode",
                "draw_recursive",
                "--forecast_backend",
                "auto",
                "--progress_every",
                "50",
                "--n_draws",
                str(n_draws),
                "--seed",
                str(seed),
                "--retain_draws",
                "false",
                "--horizon_days",
                str(horizon_days),
            ]
        ),
    )


def quantile_job_id(family, likelihood, quantile):
    like = likelihood.lower()
    q = quantile.replace(".", "p")
    if family == "joint_quantile":
        return "%s_%s_%s" % (family, like, q)
    return "%s_%s_%s" % (family, like, q)


def quantile_command(
    runtime_root,
    config_path,
    score_path,
    family,
    likelihood,
    quantile,
    max_iter,
    tol,
    max_dense_dim,
    horizon_days,
):
    model_family = {
        ("independent_quantile", "AL"): "independent_al",
        ("independent_quantile", "exAL"): "independent_exal",
        ("joint_quantile", "AL"): "joint_al",
        ("joint_quantile", "exAL"): "joint_exal",
    }[(family, likelihood)]
    job_id = quantile_job_id(family, likelihood, quantile)
    run_label = "part1_usgs_%s_%s_q%s" % (
        family,
        likelihood.lower(),
        quantile.replace(".", "p"),
    )
    output_root = str(Path(runtime_root) / job_id)
    command = shell_join(
        [
            "Rscript",
            "application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R",
            "--config",
            config_path,
            "--score_path",
            score_path,
            "--runtime_root",
            output_root,
            "--run_label",
            run_label,
            "--target",
            "usgs",
            "--model_family",
            model_family,
            "--quantile",
            quantile,
            "--rank",
            "1",
            "--candidate_id",
            DEFAULT_RIDGE_CANDIDATE_ID,
            "--rhs_candidate_id",
            DEFAULT_RHS_CANDIDATE_ID,
            "--horizon_days",
            str(horizon_days),
            "--max_iter",
            str(max_iter),
            "--tol",
            str(tol),
            "--max_dense_dim",
            str(max_dense_dim),
            "--forecast_backend",
            "auto",
        ]
    )
    return run_label, output_root, command


def quantile_row(
    index,
    family,
    likelihood,
    quantile,
    runtime_root,
    session_prefix,
    root,
    enable_forecast_jobs,
    enable_joint_quantile_jobs,
    max_iter,
    tol,
    max_dense_dim,
    config_path,
    score_path,
    horizon_days,
):
    job_id = quantile_job_id(family, likelihood, quantile)
    run_label, output_root, command = quantile_command(
        runtime_root=runtime_root,
        config_path=config_path,
        score_path=score_path,
        family=family,
        likelihood=likelihood,
        quantile=quantile,
        max_iter=max_iter,
        tol=tol,
        max_dense_dim=max_dense_dim,
        horizon_days=horizon_days,
    )
    runner_exists = script_exists(
        root, "application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R"
    )
    if not runner_exists:
        status = "blocked_missing_runner"
        reason = "missing application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R"
    elif not enable_forecast_jobs:
        status = "blocked_manual_hold"
        reason = "blocked_manual_hold: rerun preparation with --enable-forecast-jobs to arm audited concrete rows"
    elif family == "joint_quantile" and not enable_joint_quantile_jobs:
        status = "blocked_missing_scalable_joint_backend"
        reason = (
            "true joint Part 1 quantile job is intentionally not armed: current "
            "winner has about 3000 reservoir features and available joint AL/exAL "
            "VB engines store dense K*p covariance; use --enable-joint-quantile-jobs "
            "only after a scalable backend is validated"
        )
    else:
        status = "ready"
        reason = ""
    return {
        "job_index": str(index),
        "job_id": job_id,
        "job_family": family,
        "likelihood": likelihood,
        "quantile": quantile,
        "core_slots": "1",
        "launch_status": status,
        "block_reason": reason,
        "session_name": "%s_%02d_%s" % (session_prefix, index, job_id),
        "run_label": run_label,
        "output_root": output_root,
        "command": command if status == "ready" else "",
    }


def blocked_quantile_row(index, family, likelihood, quantile, runtime_root, session_prefix):
    job_id = quantile_job_id(family, likelihood, quantile)
    run_label = "part1_usgs_%s_%s_q%s" % (
        family,
        likelihood.lower(),
        quantile.replace(".", "p"),
    )
    if family.startswith("independent"):
        reason = (
            "blocked_missing_part1_quantile_deliverable_runner: the current "
            "GloFAS app has training-only qdesn_reference helpers, but no "
            "audited Part 1 seven-quantile AL/exAL forecast/scoring runner."
        )
    else:
        reason = (
            "blocked_missing_glofas_part1_joint_quantile_runner: joint AL/exAL "
            "validation engines exist, but no audited GloFAS Part 1 fixture, "
            "forecast, and scoring wrapper is present yet."
        )
    return {
        "job_index": str(index),
        "job_id": job_id,
        "job_family": family,
        "likelihood": likelihood,
        "quantile": quantile,
        "core_slots": "1",
        "launch_status": "blocked_missing_runner",
        "block_reason": reason,
        "session_name": "%s_%02d_%s" % (session_prefix, index, job_id),
        "run_label": run_label,
        "output_root": str(Path(runtime_root) / job_id),
        "command": "",
    }


def build_job_manifest(
    root,
    runtime_root,
    config_path,
    score_path,
    seed,
    n_draws,
    horizon_days,
    rhs_fit_object=DEFAULT_RHS_FIT_OBJECT,
    enable_forecast_jobs=False,
    enable_joint_quantile_jobs=False,
    quantile_max_iter=DEFAULT_QUANTILE_MAX_ITER,
    quantile_tol=DEFAULT_QUANTILE_TOL,
    quantile_max_dense_dim=DEFAULT_QUANTILE_MAX_DENSE_DIM,
):
    rows = []
    session_prefix = "glofas_part1_deliverables_20260903"

    run_label, output_root, command = normal_ridge_command(
        runtime_root=runtime_root,
        config_path=config_path,
        score_path=score_path,
        seed=seed,
        n_draws=n_draws,
        horizon_days=horizon_days,
    )
    ridge_runner_exists = script_exists(
        root, "application/scripts/44_run_glofas_normal_part1_oracle_forecast.R"
    )
    ridge_ready = ridge_runner_exists and bool(enable_forecast_jobs)
    ridge_block_reason = ""
    ridge_status = "ready" if ridge_ready else "blocked_manual_hold"
    if not ridge_runner_exists:
        ridge_status = "blocked_missing_runner"
        ridge_block_reason = "missing application/scripts/44_run_glofas_normal_part1_oracle_forecast.R"
    elif not enable_forecast_jobs:
        ridge_block_reason = "blocked_manual_hold: rerun preparation with --enable-forecast-jobs to arm audited concrete rows"
    rows.append(
        {
            "job_index": "1",
            "job_id": "normal_ridge",
            "job_family": "normal_ridge",
            "likelihood": "normal",
            "quantile": "",
            "core_slots": "1",
            "launch_status": ridge_status,
            "block_reason": ridge_block_reason,
            "session_name": "%s_01_normal_ridge" % session_prefix,
            "run_label": run_label,
            "output_root": output_root,
            "command": command if ridge_ready else "",
        }
    )

    run_label, output_root, command = normal_rhs_command(
        runtime_root=runtime_root,
        config_path=config_path,
        score_path=score_path,
        seed=seed + 1,
        n_draws=n_draws,
        horizon_days=horizon_days,
        rhs_fit_object=rhs_fit_object,
    )
    rhs_fit_exists = (root / rhs_fit_object).is_file()
    rhs_ready = ridge_runner_exists and rhs_fit_exists and bool(enable_forecast_jobs)
    rhs_block_reason = ""
    rhs_status = "ready" if rhs_ready else "blocked_manual_hold"
    if not ridge_runner_exists:
        rhs_status = "blocked_missing_runner"
        rhs_block_reason = "missing application/scripts/44_run_glofas_normal_part1_oracle_forecast.R"
    elif not rhs_fit_exists:
        rhs_status = "blocked_missing_runner"
        rhs_block_reason = "missing reusable RHS/VB fit object: %s" % rhs_fit_object
    elif not enable_forecast_jobs:
        rhs_block_reason = "blocked_manual_hold: rerun preparation with --enable-forecast-jobs to arm audited concrete rows"
    rows.append(
        {
            "job_index": "2",
            "job_id": "normal_rhs_vb",
            "job_family": "normal_rhs_vb",
            "likelihood": "normal",
            "quantile": "",
            "core_slots": "1",
            "launch_status": rhs_status,
            "block_reason": rhs_block_reason,
            "session_name": "%s_02_normal_rhs_vb" % session_prefix,
            "run_label": run_label,
            "output_root": output_root,
            "command": command if rhs_ready else "",
        }
    )

    index = 3
    for likelihood in ("AL", "exAL"):
        for quantile in QUANTILES:
            rows.append(
                quantile_row(
                    index=index,
                    family="independent_quantile",
                    likelihood=likelihood,
                    quantile=quantile,
                    runtime_root=runtime_root,
                    session_prefix=session_prefix,
                    root=root,
                    enable_forecast_jobs=enable_forecast_jobs,
                    enable_joint_quantile_jobs=enable_joint_quantile_jobs,
                    max_iter=quantile_max_iter,
                    tol=quantile_tol,
                    max_dense_dim=quantile_max_dense_dim,
                    config_path=config_path,
                    score_path=score_path,
                    horizon_days=horizon_days,
                )
            )
            index += 1

    for likelihood in ("AL", "exAL"):
        rows.append(
            quantile_row(
                index=index,
                family="joint_quantile",
                likelihood=likelihood,
                quantile="all7",
                runtime_root=runtime_root,
                session_prefix=session_prefix,
                root=root,
                enable_forecast_jobs=enable_forecast_jobs,
                enable_joint_quantile_jobs=enable_joint_quantile_jobs,
                max_iter=quantile_max_iter,
                tol=quantile_tol,
                max_dense_dim=quantile_max_dense_dim,
                config_path=config_path,
                score_path=score_path,
                horizon_days=horizon_days,
            )
        )
        index += 1

    return rows


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(path), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def render_launch_script(repo_root_path, runtime_root, part2_runtime_root, poll_seconds):
    repo_q = shlex.quote(str(repo_root_path))
    runtime_q = shlex.quote(str(repo_root_path / runtime_root))
    part2_q = shlex.quote(str(repo_root_path / part2_runtime_root))
    return textwrap.dedent(
        """\
        #!/usr/bin/env bash
        set -euo pipefail

        REPO_ROOT={repo}
        RUNTIME_ROOT={runtime}
        PART2_RUNTIME_ROOT={part2}
        JOB_MANIFEST="$RUNTIME_ROOT/configs/job_manifest.csv"
        POLL_SECONDS={poll_seconds}
        ALLOW_PARTIAL="${{ALLOW_PARTIAL:-0}}"
        GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH="${{GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH:-0}}"

        export OMP_NUM_THREADS=1
        export OPENBLAS_NUM_THREADS=1
        export MKL_NUM_THREADS=1
        export VECLIB_MAXIMUM_THREADS=1
        export NUMEXPR_NUM_THREADS=1

        cd "$REPO_ROOT"
        mkdir -p "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/status"

        if [ "$GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH" != "1" ]; then
          echo "Deferred forecast launcher is on manual hold." | tee -a "$RUNTIME_ROOT/logs/launch_when_ready.log"
          echo "Set GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH=1 only after the optimized forecast engine is audited." | tee -a "$RUNTIME_ROOT/logs/launch_when_ready.log"
          date > "$RUNTIME_ROOT/status/deferred_forecast_launcher.manual_hold"
          exit 4
        fi

        bundle_ready() {{
          python3 - "$JOB_MANIFEST" "$ALLOW_PARTIAL" <<'PY'
import csv
import sys

manifest, allow_partial = sys.argv[1], sys.argv[2] in ("1", "true", "TRUE", "yes")
with open(manifest, newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
ready = [row for row in rows if row.get("launch_status") == "ready"]
blocked = [row for row in rows if row.get("launch_status") != "ready"]
print("manifest_total=%d ready=%d blocked=%d" % (len(rows), len(ready), len(blocked)))
if not rows:
    sys.exit(1)
if blocked and not allow_partial:
    print("blocked_job_families=" + ",".join(sorted(set(row["job_family"] for row in blocked))))
    sys.exit(2)
if not ready:
    sys.exit(3)
PY
        }}

        part2_done() {{
          Rscript application/scripts/42_check_glofas_normal_part2_ridge_screen.R \\
            --runtime_root "$PART2_RUNTIME_ROOT" >> "$RUNTIME_ROOT/logs/part2_gate.log" 2>&1 || return 1
          python3 - "$PART2_RUNTIME_ROOT/tables/health_latest.csv" <<'PY'
import csv
import sys

health_path = sys.argv[1]
with open(health_path, newline="", encoding="utf-8") as handle:
    row = list(csv.DictReader(handle))[-1]
total = int(float(row["total"]))
completed = int(float(row["completed"]))
running = int(float(row["running"]))
failed = int(float(row["failed"]))
pending = int(float(row["pending"]))
print("part2_total=%d completed=%d running=%d failed=%d pending=%d" % (
    total, completed, running, failed, pending
))
sys.exit(0 if completed == total and running == 0 and failed == 0 and pending == 0 else 1)
PY
        }}

        free_cores_ok() {{
          need="$(python3 - "$JOB_MANIFEST" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    rows = [row for row in csv.DictReader(handle) if row.get("launch_status") == "ready"]
print(sum(int(float(row.get("core_slots") or 0)) for row in rows))
PY
)"
          if [ "$need" -lt 1 ]; then
            echo "no ready forecast jobs in manifest"
            return 1
          fi
          MIN_FREE_CORES="$need"
          python3 - "$MIN_FREE_CORES" <<'PY'
import math
import os
import sys

need = int(sys.argv[1])
with open("/proc/loadavg", encoding="utf-8") as handle:
    load1 = float(handle.read().split()[0])
cores = os.cpu_count() or 1
free = max(0, cores - int(math.ceil(load1)))
print("system_cores=%d load1=%.2f estimated_free_cores=%d need=%d" % (
    cores, load1, free, need
))
sys.exit(0 if free >= need else 1)
PY
        }}

        launch_ready_jobs() {{
          python3 - "$JOB_MANIFEST" "$RUNTIME_ROOT/status/ready_jobs.tsv" <<'PY'
import csv
import sys

manifest, out_path = sys.argv[1], sys.argv[2]
with open(manifest, newline="", encoding="utf-8") as handle:
    rows = [row for row in csv.DictReader(handle) if row.get("launch_status") == "ready"]
with open(out_path, "w", encoding="utf-8") as out:
    for row in rows:
        log_path = "%s/logs/%s.log" % (sys.argv[2].rsplit("/status/", 1)[0], row["job_id"])
        out.write("%s\\t%s\\t%s\\t%s\\n" % (
            row["job_id"], row["session_name"], log_path, row["command"]
        ))
PY
          while IFS=$'\\t' read -r job_id session_name log_path command; do
            if tmux has-session -t "$session_name" 2>/dev/null; then
              echo "session_exists job_id=$job_id session=$session_name"
              continue
            fi
            echo "launching job_id=$job_id session=$session_name log=$log_path"
            tmux new-session -d -s "$session_name" \\
              "cd '$REPO_ROOT' && export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 && $command > '$log_path' 2>&1"
          done < "$RUNTIME_ROOT/status/ready_jobs.tsv"
          date > "$RUNTIME_ROOT/status/deferred_launcher.launched"
        }}

        if ! bundle_ready > "$RUNTIME_ROOT/status/bundle_readiness.txt" 2>&1; then
          cat "$RUNTIME_ROOT/status/bundle_readiness.txt"
          echo "Deferred launcher blocked: not every requested job family has an audited runner."
          echo "Use ALLOW_PARTIAL=1 only for manual debugging, not for scientific closeout."
          exit 2
        fi

        while true; do
          if part2_done && free_cores_ok; then
            launch_ready_jobs
            exit 0
          fi
          date >> "$RUNTIME_ROOT/status/deferred_launcher.waiting"
          sleep "$POLL_SECONDS"
        done
        """
    ).format(
        repo=repo_q,
        runtime=runtime_q,
        part2=part2_q,
        poll_seconds=int(poll_seconds),
    )


def render_readme(root, runtime_root, part2_runtime_root, rows, config_path, score_path):
    ready = [row for row in rows if row["launch_status"] == "ready"]
    blocked = [row for row in rows if row["launch_status"] != "ready"]
    head = git_head(root)
    return textwrap.dedent(
        """\
        # GloFAS Part 1 Deferred Deliverable Launcher

        This ignored runtime bundle stages the requested Part 1 closeout launch
        while the Part 2 ridge screen is still running. The bundle is explicit
        about what is runnable now and what is deferred. It never runs quantile
        synthesis.

        The shell launcher exits unless
        `GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH=1`, and the manifest does not
        mark concrete forecast jobs ready unless the preparation command is run
        with `--enable-forecast-jobs`. When armed, the launcher waits for Part 2
        ridge completion and uses the number of ready manifest rows as the
        minimum core gate.

        ## Current Launch Contract

        - Repository: `{repo}`
        - Git HEAD at preparation: `{head}`
        - Runtime root: `{runtime_root}`
        - Part 2 gate root: `{part2_runtime_root}`
        - Part 2 completion gate: `completed == total`, `running == 0`,
          `failed == 0`, `pending == 0` in `tables/health_latest.csv`
        - Minimum available cores before launch: sum of ready manifest `core_slots`
        - Per-model threading: BLAS/OpenMP environment variables set to `1`
        - Synthesis: disabled and intentionally absent from every command
        - Config source: `{config_path}`
        - Normal RHS score source for the current Part 1 winner:
          `{score_path}`

        ## Requested 18 Slots

        - 1 Normal ridge forecast job
        - 1 Normal RHS/VB forecast job using a saved fit object
        - 7 independent quantile AL fit-then-forecast jobs
        - 7 independent quantile exAL fit-then-forecast jobs
        - 1 joint-quantile AL row
        - 1 joint-quantile exAL row

        ## Readiness Summary

        - Ready rows: `{ready_count}`
        - Blocked rows: `{blocked_count}`

        The Normal ridge and Normal RHS/VB forecast runners use the optimized
        Part 1 oracle-realized forecast engine. The RHS/VB row reuses the
        retained fit object instead of refitting. The independent AL/exAL rows
        use `application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R`
        and fit one quantile per job, then immediately forecast that quantile.

        The true joint AL/exAL rows are present as explicit deliverables but
        remain blocked unless `--enable-joint-quantile-jobs` is used. For the
        current winner, the existing joint engines store dense `K*p` beta
        covariance; with about 3000 reservoir features and seven quantiles, that
        is not a validated scalable launch path. Keeping these rows blocked is
        intentional and avoids silently running a fake joint approximation.

        ## Current Part 1 Winner Used As The DESN Template

        - Candidate: `{candidate_id}`
        - Normal RHS candidate: `{rhs_candidate_id}`
        - DESN: `D=1`, `n=3000`, no hidden layer transform, `m=360`
        - Reservoir lags: USGS output `1:360`, ppt/soil `0:180`
        - Dynamics: `alpha=0.5`, `rho=0.9`, seed `20260512`, washout `500`
        - Readout: no direct input block for the Part 1 Normal screen
        - RHS prior: `tau0=1`, `max_iter=100`, `min_iter=30`

        ## How To Arm

        1. Prepare the bundle with `--enable-forecast-jobs`.
        2. Launch with explicit operator opt-in:

           ```bash
           GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH=1 ALLOW_PARTIAL=1 bash {runtime_root}/launch_when_ready.sh
           ```

        The launcher will then wait for Part 2 to finish cleanly and for at
        least the ready-job core count before creating tmux sessions. Use
        `ALLOW_PARTIAL=1` only because the true joint quantile rows remain
        intentionally deferred until a scalable backend exists.
        """
    ).format(
        repo=root,
        head=head,
        runtime_root=runtime_root,
        part2_runtime_root=part2_runtime_root,
        config_path=config_path,
        score_path=score_path,
        ready_count=len(ready),
        blocked_count=len(blocked),
        candidate_id=DEFAULT_RIDGE_CANDIDATE_ID,
        rhs_candidate_id=DEFAULT_RHS_CANDIDATE_ID,
    )


def prepare(args):
    root = repo_root()
    runtime_root = require_repo_relative(args.runtime_root, root)
    part2_runtime_root = require_repo_relative(args.part2_runtime_root, root)
    config_path = require_repo_relative(args.config, root)
    score_path = require_repo_relative(args.score_path, root)
    rhs_fit_object = require_repo_relative(args.rhs_fit_object, root)

    rows = build_job_manifest(
        root=root,
        runtime_root=runtime_root,
        config_path=config_path,
        score_path=score_path,
        seed=args.seed,
        n_draws=args.n_draws,
        horizon_days=args.horizon_days,
        rhs_fit_object=rhs_fit_object,
        enable_forecast_jobs=args.enable_forecast_jobs,
        enable_joint_quantile_jobs=args.enable_joint_quantile_jobs,
        quantile_max_iter=args.quantile_max_iter,
        quantile_tol=args.quantile_tol,
        quantile_max_dense_dim=args.quantile_max_dense_dim,
    )
    runtime_abs = root / runtime_root
    (runtime_abs / "configs").mkdir(parents=True, exist_ok=True)
    (runtime_abs / "logs").mkdir(parents=True, exist_ok=True)
    (runtime_abs / "status").mkdir(parents=True, exist_ok=True)

    manifest_path = runtime_abs / "configs" / "job_manifest.csv"
    write_csv(manifest_path, rows)

    metadata = {
        "repo_root": str(root),
        "git_head": git_head(root),
        "runtime_root": runtime_root,
        "part2_runtime_root": part2_runtime_root,
        "rhs_fit_object": rhs_fit_object,
        "requested_total_jobs": len(rows),
        "requested_total_cores": sum(int(row["core_slots"]) for row in rows),
        "ready_jobs": sum(row["launch_status"] == "ready" for row in rows),
        "ready_cores": sum(
            int(row["core_slots"]) for row in rows if row["launch_status"] == "ready"
        ),
        "blocked_jobs": sum(row["launch_status"] != "ready" for row in rows),
        "quantiles": list(QUANTILES),
        "fail_closed": True,
        "manual_forecast_launch_required": True,
        "enable_forecast_jobs": bool(args.enable_forecast_jobs),
        "enable_joint_quantile_jobs": bool(args.enable_joint_quantile_jobs),
        "synthesis_enabled": False,
        "quantile_max_iter": args.quantile_max_iter,
        "quantile_tol": args.quantile_tol,
        "quantile_max_dense_dim": args.quantile_max_dense_dim,
    }
    metadata_path = runtime_abs / "configs" / "launcher_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    launch_path = runtime_abs / "launch_when_ready.sh"
    launch_path.write_text(
        render_launch_script(
            repo_root_path=root,
            runtime_root=runtime_root,
            part2_runtime_root=part2_runtime_root,
            poll_seconds=args.poll_seconds,
        ),
        encoding="utf-8",
    )
    launch_path.chmod(0o755)

    readme_path = runtime_abs / "README.md"
    readme_path.write_text(
        render_readme(
            root=root,
            runtime_root=runtime_root,
            part2_runtime_root=part2_runtime_root,
            rows=rows,
            config_path=config_path,
            score_path=score_path,
        ),
        encoding="utf-8",
    )

    checks = []
    for rel in [
        "application/scripts/44_run_glofas_normal_part1_oracle_forecast.R",
        "application/scripts/63_run_glofas_part1_quantile_oracle_forecast.R",
        "application/scripts/42_check_glofas_normal_part2_ridge_screen.R",
        "application/R/glofas_part1_quantile_oracle_forecast.R",
        "application/R/glofas_normal_oracle_forecast.R",
        "application/R/joint_qvp_qdesn.R",
        "application/R/joint_exqdesn_exact_structured_inference.R",
        "application/R/joint_exqdesn_inference_dispatch.R",
        "application/src/glofas_oracle_desn_forecast.cpp",
    ]:
        path = root / rel
        checks.append(
            {
                "path": rel,
                "exists": path.is_file(),
                "sha256": path_sha256(path) if path.is_file() else "",
            }
        )
    checks_path = runtime_abs / "configs" / "source_checks.json"
    checks_path.write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    return {
        "runtime_root": str(runtime_abs),
        "manifest": str(manifest_path),
        "metadata": str(metadata_path),
        "launcher": str(launch_path),
        "readme": str(readme_path),
        "source_checks": str(checks_path),
        "metadata_payload": metadata,
    }


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--part2-runtime-root", default=DEFAULT_PART2_RUNTIME_ROOT)
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--score-path", default=DEFAULT_SCORE_PATH)
    parser.add_argument("--rhs-fit-object", default=DEFAULT_RHS_FIT_OBJECT)
    parser.add_argument("--seed", default=20260903, type=int)
    parser.add_argument("--n-draws", default=500, type=int)
    parser.add_argument("--horizon-days", default=30, type=int)
    parser.add_argument("--poll-seconds", default=900, type=int)
    parser.add_argument("--quantile-max-iter", default=DEFAULT_QUANTILE_MAX_ITER, type=int)
    parser.add_argument("--quantile-tol", default=DEFAULT_QUANTILE_TOL, type=float)
    parser.add_argument("--quantile-max-dense-dim", default=DEFAULT_QUANTILE_MAX_DENSE_DIM, type=int)
    parser.add_argument(
        "--enable-forecast-jobs",
        action="store_true",
        help=(
            "Opt in to ready forecast rows after the optimized forecast engine "
            "has been audited. Default is manual-hold/no forecast auto-launch."
        ),
    )
    parser.add_argument(
        "--enable-joint-quantile-jobs",
        action="store_true",
        help=(
            "Testing/advanced opt-in only. Arms true joint AL/exAL rows; do not "
            "use for the current high-dimensional Part 1 winner until a scalable "
            "joint backend is validated."
        ),
    )
    return parser.parse_args(argv)


def main(argv=None):
    result = prepare(parse_args(argv or sys.argv[1:]))
    print(json.dumps(result, indent=2, sort_keys=True))
    if result["metadata_payload"]["blocked_jobs"]:
        print(
            "Prepared fail-closed launcher with blocked rows. Ready rows can be "
            "launched with explicit GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH=1 and "
            "ALLOW_PARTIAL=1; blocked rows remain inert until audited runners exist.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
