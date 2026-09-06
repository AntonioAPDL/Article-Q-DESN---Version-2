#!/usr/bin/env python3
"""Prepare a deferred launcher for GloFAS Part 2 RHS/VB closeout.

The chain is available, but manual-hold by default:
  1. wait for the active Part 1 forecast deliverables to finish cleanly;
  2. verify the latest Part 2 ridge screen evidence is complete and clean;
  3. prepare a Part 2 Normal RHS/VB screen from the top ridge candidates;
  3. launch that RHS screen when enough cores are free;
  4. wait for the RHS screen to finish cleanly;
  5. write a winner-driven post-RHS deliverable manifest.

The last manifest is fail-closed until the historical-bridge forecast and
quantile runners exist for the exact Part 2 contract. The generated script exits
unless GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH=1 is set explicitly.
"""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys
import textwrap


DEFAULT_CHAIN_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_normal_part2_rhs_after_part1_forecasts_20260903"
)
DEFAULT_RIDGE_RUNTIME_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_normal_part2_ridge_targeted_neighbors_20260903_154118"
)
DEFAULT_RIDGE_SCORES_PATH = (
    "local_trackers/runtime_configs/"
    "glofas_normal_part2_ridge_targeted_neighbors_20260903_154118/"
    "tables/combined_part2_ridge_scores_latest.csv"
)
DEFAULT_FORECAST_RUNTIME_ROOT = (
    "local_trackers/runtime_configs/"
    "glofas_part1_all_model_forecasts_after_part2_ridge_20260903"
)
DEFAULT_RHS_RUN_LABEL = "glofas_normal_part2_rhs_top50_after_part1_forecasts_20260903"
DEFAULT_BASE_CONFIG = (
    "local_trackers/runtime_configs/"
    "glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
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


def shell_quote(path_or_text):
    return shlex.quote(str(path_or_text))


def render_chain_script(
    root,
    chain_root,
    forecast_runtime_root,
    ridge_runtime_root,
    ridge_scores_path,
    rhs_run_label,
    base_config,
    top_n,
    workers,
    poll_seconds,
    tau0_reference_values,
    tau0_discrepancy_values,
    max_iter,
    min_iter,
    tol,
):
    rhs_runtime_root = str(Path("local_trackers/runtime_configs") / rhs_run_label)
    template = textwrap.dedent(
        """\
        #!/usr/bin/env bash
        set -euo pipefail

        REPO_ROOT=__REPO__
        CHAIN_ROOT="$REPO_ROOT/__CHAIN_ROOT__"
        FORECAST_RUNTIME_ROOT="$REPO_ROOT/__FORECAST_RUNTIME_ROOT__"
        RIDGE_RUNTIME_ROOT="$REPO_ROOT/__RIDGE_RUNTIME_ROOT__"
        RIDGE_SCORES_PATH="$REPO_ROOT/__RIDGE_SCORES_PATH__"
        RHS_RUN_LABEL=__RHS_RUN_LABEL__
        RHS_RUNTIME_ROOT="$REPO_ROOT/local_trackers/runtime_configs/$RHS_RUN_LABEL"
        BASE_CONFIG="$REPO_ROOT/__BASE_CONFIG__"
        TOP_N=__TOP_N__
        WORKERS=__WORKERS__
        MIN_RHS_FREE_CORES=__WORKERS__
        POLL_SECONDS=__POLL_SECONDS__
        TAU0_REFERENCE_VALUES=__TAU0_REFERENCE_VALUES__
        TAU0_DISCREPANCY_VALUES=__TAU0_DISCREPANCY_VALUES__
        MAX_ITER=__MAX_ITER__
        MIN_ITER=__MIN_ITER__
        TOL=__TOL__
        GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH="${GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH:-0}"

        export OMP_NUM_THREADS=1
        export OPENBLAS_NUM_THREADS=1
        export MKL_NUM_THREADS=1
        export VECLIB_MAXIMUM_THREADS=1
        export NUMEXPR_NUM_THREADS=1

        cd "$REPO_ROOT"
        mkdir -p "$CHAIN_ROOT/logs" "$CHAIN_ROOT/status" "$CHAIN_ROOT/configs" "$CHAIN_ROOT/tables"

        log() {
          echo "[$(date)] $*" | tee -a "$CHAIN_ROOT/logs/part2_rhs_then_closeout.log"
        }

        if [ "$GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH" != "1" ]; then
          log "manual hold: not launching RHS/closeout after Part 1 forecasts"
          log "set GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH=1 only after explicit operator approval"
          date > "$CHAIN_ROOT/status/part2_rhs_then_closeout.manual_hold"
          exit 4
        fi

        free_cores_ok() {
          python3 - "$1" <<'PY'
import math
import os
import sys

need = int(sys.argv[1])
with open("/proc/loadavg", encoding="utf-8") as handle:
    load1 = float(handle.read().split()[0])
cores = os.cpu_count() or 1
free = max(0, cores - int(math.ceil(load1)))
print("system_cores=%d load1=%.2f estimated_free_cores=%d need=%d" % (cores, load1, free, need))
sys.exit(0 if free >= need else 1)
PY
        }

        part1_forecasts_done() {
          python3 - "$FORECAST_RUNTIME_ROOT" <<'PY'
import csv
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = root / "configs" / "job_manifest.csv"
if not manifest.exists():
    print("missing_manifest=%s" % manifest)
    sys.exit(3)
rows = list(csv.DictReader(open(str(manifest), newline="", encoding="utf-8")))
ready = [row for row in rows if row.get("launch_status") == "ready"]
blocked = [row for row in rows if row.get("launch_status") != "ready"]
running = []
done = []
failed = []
for row in ready:
    session = row.get("session_name", "")
    if session and subprocess.call(
        ["tmux", "has-session", "-t", session],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) == 0:
        running.append(row["job_id"])
        continue
    output_root = Path(row.get("output_root", ""))
    if not output_root.is_absolute():
        output_root = root.parents[2] / output_root
    summaries = []
    if output_root.exists():
        summaries = list(output_root.glob("tables/*_summary.csv")) + list(output_root.glob("tables/*_forecast_scores.csv"))
    log = root / "logs" / ("%s.log" % row["job_id"])
    tail = ""
    if log.exists():
        text = log.read_text(errors="replace")
        tail = "\\n".join(text.splitlines()[-25:])
    error_like = bool(re.search(r"(Execution halted|Traceback|^Error:|\\bError in\\b|failed|cannot open|No such file|Missing)", tail, re.I | re.M))
    if error_like or not summaries:
        failed.append("%s(summary_files=%d,error_like=%s)" % (row["job_id"], len(summaries), error_like))
    else:
        done.append(row["job_id"])
print("part1_ready=%d done=%d running=%d failed=%d blocked=%d" % (
    len(ready), len(done), len(running), len(failed), len(blocked)
))
if failed:
    print("failed_jobs=%s" % ",".join(failed[:12]))
    sys.exit(3)
sys.exit(0 if not running and len(done) == len(ready) else 1)
PY
        }

        ridge_done() {
          Rscript application/scripts/42_check_glofas_normal_part2_ridge_screen.R \\
            --runtime_root "$RIDGE_RUNTIME_ROOT" \\
            >> "$CHAIN_ROOT/logs/ridge_gate_health.log" 2>&1 || return 1
          python3 - "$RIDGE_RUNTIME_ROOT/tables/health_latest.csv" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    row = list(csv.DictReader(handle))[-1]
total = int(float(row["total"]))
completed = int(float(row["completed"]))
running = int(float(row["running"]))
failed = int(float(row["failed"]))
pending = int(float(row["pending"]))
print("ridge_total=%d completed=%d running=%d failed=%d pending=%d" % (
    total, completed, running, failed, pending
))
if failed:
    sys.exit(3)
sys.exit(0 if completed == total and running == 0 and pending == 0 else 1)
PY
        }

        rhs_prepared() {
          test -f "$RHS_RUNTIME_ROOT/configs/part2_rhs_tau0_manifest.csv"
        }

        prepare_rhs() {
          log "preparing Part2 RHS/VB screen from latest combined ridge ranking"
          Rscript application/scripts/52_prepare_glofas_normal_part2_rhs_vb.R \\
            --base_config "$BASE_CONFIG" \\
            --ridge_runtime_root "$RIDGE_RUNTIME_ROOT" \\
            --ridge_scores_path "$RIDGE_SCORES_PATH" \\
            --run_label "$RHS_RUN_LABEL" \\
            --top_n "$TOP_N" \\
            --tau0_reference_values "$TAU0_REFERENCE_VALUES" \\
            --tau0_discrepancy_values "$TAU0_DISCREPANCY_VALUES" \\
            --max_iter "$MAX_ITER" \\
            --min_iter "$MIN_ITER" \\
            --tol "$TOL" \\
            --workers "$WORKERS" \\
            >> "$CHAIN_ROOT/logs/prepare_rhs.log" 2>&1
        }

        rhs_launched() {
          test -f "$RHS_RUNTIME_ROOT/configs/launch_manifest.csv"
        }

        launch_rhs() {
          log "launching Part2 RHS/VB screen with $WORKERS one-thread workers"
          Rscript application/scripts/56_launch_glofas_normal_part2_rhs_vb.R \\
            --runtime_root "$RHS_RUNTIME_ROOT" \\
            --workers "$WORKERS" \\
            --session_label "$RHS_RUN_LABEL" \\
            --poll_seconds 300 \\
            >> "$CHAIN_ROOT/logs/launch_rhs.log" 2>&1
        }

        rhs_done() {
          Rscript application/scripts/55_check_glofas_normal_part2_rhs_vb.R \\
            --runtime_root "$RHS_RUNTIME_ROOT" \\
            >> "$CHAIN_ROOT/logs/rhs_gate_health.log" 2>&1 || return 1
          python3 - "$RHS_RUNTIME_ROOT/tables/part2_rhs_health_latest.csv" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
ok = True
has_failure = False
parts = []
for row in rows:
    total = int(float(row["total"]))
    completed = int(float(row["completed"]))
    running = int(float(row["running"]))
    failed = int(float(row["failed"]))
    pending = int(float(row["pending"]))
    parts.append("%s=%d/%d run=%d fail=%d pend=%d" % (
        row["phase"], completed, total, running, failed, pending
    ))
    if failed:
        has_failure = True
    if failed or running or pending or completed != total:
        ok = False
print(" | ".join(parts))
if has_failure:
    sys.exit(3)
sys.exit(0 if ok else 1)
PY
        }

        write_post_rhs_manifest() {
          python3 - "$RHS_RUNTIME_ROOT/tables/part2_rhs_scores_latest.csv" \\
            "$CHAIN_ROOT/tables/post_rhs_deliverable_manifest.csv" \\
            "$CHAIN_ROOT/tables/selected_part2_rhs_winner.json" <<'PY'
import csv
import json
import sys

scores_path, manifest_path, winner_path = sys.argv[1:4]
with open(scores_path, newline="", encoding="utf-8") as handle:
    scores = [row for row in csv.DictReader(handle) if row.get("status") == "completed"]
if not scores:
    raise SystemExit("No completed Part2 RHS scores are available.")
def score_value(row, key):
    try:
        return float(row.get(key, "inf"))
    except ValueError:
        return float("inf")
scores.sort(key=lambda row: (
    score_value(row, "valid_mean_crps"),
    score_value(row, "valid_mae"),
    score_value(row, "valid_rmse"),
))
winner = scores[0]
quantiles = ["0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95"]
rows = []
def add(job_family, likelihood, quantile, core_slots, reason):
    idx = len(rows) + 1
    rows.append({
        "job_index": str(idx),
        "job_family": job_family,
        "likelihood": likelihood,
        "quantile": quantile,
        "core_slots": str(core_slots),
        "launch_status": "blocked_missing_runner",
        "block_reason": reason,
        "winner_rhs_candidate_id": winner.get("rhs_candidate_id", ""),
        "winner_ridge_candidate_id": winner.get("candidate_id", ""),
        "winner_valid_mean_crps": winner.get("valid_mean_crps", ""),
    })
add(
    "normal_ridge_bridge_forecast",
    "normal",
    "",
    1,
    "blocked_missing_part2_historical_bridge_forecast_runner",
)
add(
    "normal_rhs_bridge_forecast",
    "normal",
    "",
    0,
    "blocked_until_part2_rhs_forecast_adapter_uses_selected_completed_fit",
)
for likelihood in ["AL", "exAL"]:
    for q in quantiles:
        add(
            "independent_quantile_bridge",
            likelihood,
            q,
            1,
            "blocked_missing_part2_independent_quantile_bridge_runner",
        )
for likelihood in ["AL", "exAL"]:
    add(
        "joint_quantile_bridge",
        likelihood,
        "all7",
        1,
        "blocked_missing_part2_joint_quantile_bridge_runner",
    )
fieldnames = list(rows[0].keys())
with open(manifest_path, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
with open(winner_path, "w", encoding="utf-8") as handle:
    json.dump(winner, handle, indent=2, sort_keys=True)
    handle.write("\\n")
print("selected_rhs_candidate_id=%s" % winner.get("rhs_candidate_id", ""))
print("post_rhs_manifest_rows=%d core_slots=%d" % (
    len(rows), sum(int(row["core_slots"]) for row in rows)
))
PY
        }

        log "chain scheduler started"
        while true; do
          set +e
          forecast_status="$(part1_forecasts_done)"
          forecast_code="$?"
          set -e
          if [ "$forecast_code" = "0" ]; then
            log "Part 1 forecasts complete: $forecast_status"
            break
          fi
          if [ "$forecast_code" = "3" ]; then
            log "Part 1 forecast gate failed; refusing to launch Part 2 RHS: ${forecast_status:-no_status}"
            exit 3
          fi
          log "waiting for Part 1 forecasts: ${forecast_status:-no_status} code=$forecast_code"
          sleep "$POLL_SECONDS"
        done

        while true; do
          set +e
          ridge_status="$(ridge_done)"
          ridge_code="$?"
          set -e
          if [ "$ridge_code" = "0" ]; then
            log "ridge complete: $ridge_status"
            break
          fi
          if [ "$ridge_code" = "3" ]; then
            log "ridge screen reported failures; refusing to launch RHS: ${ridge_status:-no_status}"
            exit 3
          fi
          log "waiting for ridge screen: ${ridge_status:-no_status} code=$ridge_code"
          sleep "$POLL_SECONDS"
        done

        rhs_prepared || prepare_rhs

        while true; do
          if free_status="$(free_cores_ok "$MIN_RHS_FREE_CORES")"; then
            log "core gate passed for RHS: $free_status"
            break
          fi
          log "waiting for $MIN_RHS_FREE_CORES free cores: ${free_status:-no_status}"
          sleep "$POLL_SECONDS"
        done

        rhs_launched || launch_rhs

        while true; do
          set +e
          rhs_status="$(rhs_done)"
          rhs_code="$?"
          set -e
          if [ "$rhs_code" = "0" ]; then
            log "RHS complete: $rhs_status"
            break
          fi
          if [ "$rhs_code" = "3" ]; then
            log "RHS screen reported failures; refusing post-RHS closeout: ${rhs_status:-no_status}"
            exit 3
          fi
          log "waiting for RHS screen: ${rhs_status:-no_status} code=$rhs_code"
          sleep "$POLL_SECONDS"
        done

        write_post_rhs_manifest >> "$CHAIN_ROOT/logs/post_rhs_manifest.log" 2>&1
        date > "$CHAIN_ROOT/status/part2_rhs_then_closeout_manifest.done"
        log "post-RHS winner manifest prepared; closeout fit runners remain fail-closed until implemented"
        """
    )
    replacements = {
        "__REPO__": shell_quote(root),
        "__CHAIN_ROOT__": chain_root,
        "__FORECAST_RUNTIME_ROOT__": forecast_runtime_root,
        "__RIDGE_RUNTIME_ROOT__": ridge_runtime_root,
        "__RIDGE_SCORES_PATH__": ridge_scores_path,
        "__RHS_RUN_LABEL__": shell_quote(rhs_run_label),
        "__BASE_CONFIG__": base_config,
        "__TOP_N__": str(int(top_n)),
        "__WORKERS__": str(int(workers)),
        "__POLL_SECONDS__": str(int(poll_seconds)),
        "__TAU0_REFERENCE_VALUES__": shell_quote(tau0_reference_values),
        "__TAU0_DISCREPANCY_VALUES__": shell_quote(tau0_discrepancy_values),
        "__MAX_ITER__": str(int(max_iter)),
        "__MIN_ITER__": str(int(min_iter)),
        "__TOL__": shell_quote(tol),
    }
    for key, value in replacements.items():
        template = template.replace(key, value)
    return template


def render_readme(
    root,
    chain_root,
    forecast_runtime_root,
    ridge_runtime_root,
    ridge_scores_path,
    rhs_run_label,
    top_n,
    workers,
    tau0_reference_values,
    tau0_discrepancy_values,
    max_iter,
    min_iter,
    tol,
):
    return textwrap.dedent(
        """\
        # GloFAS Part 2 RHS Then Closeout Deferred Launcher

        This ignored runtime bundle records the next Part 2 workflow without
        interrupting the active Part 1 forecast jobs. It is manual-hold by
        default and exits unless `GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH=1` is set.

        ## Chain

        1. Poll the active Part 1 forecast bundle:
           `{forecast_runtime_root}`
        2. Verify the latest Part 2 ridge screen is complete and clean:
           `{ridge_runtime_root}`
        3. Prepare the Part 2 Normal RHS/VB screen from:
           `{ridge_scores_path}`
        4. Wait until approximately `{workers}` cores are free.
        5. Launch the RHS/VB screen with `{workers}` one-thread workers.
        6. Wait until all RHS warm starts and RHS fits finish cleanly.
        7. Freeze the selected RHS winner into a post-RHS deliverable manifest.

        ## Default RHS Screen

        - Reference DESN: fixed Part 1 USGS winner.
        - Discrepancy DESN: top `{top_n}` candidates from the combined Part 2
          ridge ranking. The audit showed this is mostly one strong basin
          (`disc_covars`, `D=1`, lags `360/180/360`), but the top 50 still span
          a meaningful CRPS range and ridge-to-RHS reordering is plausible.
        - Reference RHS `tau0`: `{tau0_reference_values}`.
        - Discrepancy RHS `tau0`: `{tau0_discrepancy_values}`.
        - Total RHS fits: `{total_rhs}`.
        - VB controls: `max_iter={max_iter}`, `min_iter={min_iter}`,
          `tol={tol}`.

        ## Closeout Guard

        The post-RHS deliverable manifest is winner-aware, but fail-closed. It
        records the requested Normal ridge, Normal RHS, independent AL/exAL,
        and joint AL/exAL closeout slots, but it does not launch them until
        audited Part 2 historical-bridge forecast and quantile runners exist.

        - Repository: `{root}`
        - Prepared at git HEAD: `{head}`
        - RHS run label: `{rhs_run_label}`
        """
    ).format(
        root=root,
        head=git_head(root),
        chain_root=chain_root,
        forecast_runtime_root=forecast_runtime_root,
        ridge_runtime_root=ridge_runtime_root,
        ridge_scores_path=ridge_scores_path,
        rhs_run_label=rhs_run_label,
        top_n=top_n,
        workers=workers,
        tau0_reference_values=tau0_reference_values,
        tau0_discrepancy_values=tau0_discrepancy_values,
        total_rhs=top_n * len([x for x in tau0_reference_values.split(",") if x.strip()]) * len([x for x in tau0_discrepancy_values.split(",") if x.strip()]),
        max_iter=max_iter,
        min_iter=min_iter,
        tol=tol,
    )


def prepare(args):
    root = repo_root()
    chain_root = require_repo_relative(args.chain_root, root)
    forecast_runtime_root = require_repo_relative(args.forecast_runtime_root, root)
    ridge_runtime_root = require_repo_relative(args.ridge_runtime_root, root)
    ridge_scores_path = require_repo_relative(args.ridge_scores_path, root)
    base_config = require_repo_relative(args.base_config, root)
    chain_abs = root / chain_root
    for name in ("configs", "logs", "status", "tables"):
        (chain_abs / name).mkdir(parents=True, exist_ok=True)

    script_path = chain_abs / "schedule_part2_rhs_then_closeout.sh"
    script_path.write_text(
        render_chain_script(
            root=root,
            chain_root=chain_root,
            forecast_runtime_root=forecast_runtime_root,
            ridge_runtime_root=ridge_runtime_root,
            ridge_scores_path=ridge_scores_path,
            rhs_run_label=args.rhs_run_label,
            base_config=base_config,
            top_n=args.top_n,
            workers=args.workers,
            poll_seconds=args.poll_seconds,
            tau0_reference_values=args.tau0_reference_values,
            tau0_discrepancy_values=args.tau0_discrepancy_values,
            max_iter=args.max_iter,
            min_iter=args.min_iter,
            tol=args.tol,
        ),
        encoding="utf-8",
    )
    script_path.chmod(0o755)

    readme_path = chain_abs / "README.md"
    readme_path.write_text(
        render_readme(
            root=root,
            chain_root=chain_root,
            forecast_runtime_root=forecast_runtime_root,
            ridge_runtime_root=ridge_runtime_root,
            ridge_scores_path=ridge_scores_path,
            rhs_run_label=args.rhs_run_label,
            top_n=args.top_n,
            workers=args.workers,
            tau0_reference_values=args.tau0_reference_values,
            tau0_discrepancy_values=args.tau0_discrepancy_values,
            max_iter=args.max_iter,
            min_iter=args.min_iter,
            tol=args.tol,
        ),
        encoding="utf-8",
    )
    metadata = {
        "repo_root": str(root),
        "git_head": git_head(root),
        "chain_root": chain_root,
        "forecast_runtime_root": forecast_runtime_root,
        "ridge_runtime_root": ridge_runtime_root,
        "ridge_scores_path": ridge_scores_path,
        "rhs_run_label": args.rhs_run_label,
        "rhs_runtime_root": str(Path("local_trackers/runtime_configs") / args.rhs_run_label),
        "top_n": args.top_n,
        "workers": args.workers,
        "tau0_reference_values": args.tau0_reference_values,
        "tau0_discrepancy_values": args.tau0_discrepancy_values,
        "max_iter": args.max_iter,
        "min_iter": args.min_iter,
        "tol": args.tol,
        "fail_closed_post_rhs": True,
        "manual_autolaunch_required": True,
        "manual_autolaunch_env": "GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH=1",
    }
    metadata_path = chain_abs / "configs" / "chain_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "chain_root": str(chain_abs),
        "script": str(script_path),
        "readme": str(readme_path),
        "metadata": str(metadata_path),
        "metadata_payload": metadata,
    }


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain-root", default=DEFAULT_CHAIN_ROOT)
    parser.add_argument("--forecast-runtime-root", default=DEFAULT_FORECAST_RUNTIME_ROOT)
    parser.add_argument("--ridge-runtime-root", default=DEFAULT_RIDGE_RUNTIME_ROOT)
    parser.add_argument("--ridge-scores-path", default=DEFAULT_RIDGE_SCORES_PATH)
    parser.add_argument("--rhs-run-label", default=DEFAULT_RHS_RUN_LABEL)
    parser.add_argument("--base-config", default=DEFAULT_BASE_CONFIG)
    parser.add_argument("--top-n", default=50, type=int)
    parser.add_argument("--workers", default=20, type=int)
    parser.add_argument("--poll-seconds", default=60, type=int)
    parser.add_argument("--tau0-reference-values", default="1")
    parser.add_argument("--tau0-discrepancy-values", default="1,0.1,0.01,0.001")
    parser.add_argument("--max-iter", default=100, type=int)
    parser.add_argument("--min-iter", default=30, type=int)
    parser.add_argument("--tol", default="1e-4")
    return parser.parse_args(argv)


def main(argv=None):
    result = prepare(parse_args(argv or sys.argv[1:]))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
