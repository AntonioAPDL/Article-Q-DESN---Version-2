#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925}"
SOURCE_ROOT="${2:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
BRANCH="work/joint-qdesn-pure-desn-expanded-screen-20260925"
CPU_LIST="2-16"
CPUS=(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

[[ "$(hostname -s)" == "jerez" ]] || { echo "Expanded screening may run only on jerez." >&2; exit 2; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || { echo "Wrong expanded-screen branch." >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Tracked worktree is dirty." >&2; exit 2; }
[[ "$(git rev-list --left-right --count '@{upstream}'...HEAD)" == $'0\t0' ]] || { echo "Expanded-screen branch is not synchronized." >&2; exit 2; }
[[ -x "$R_BIN" ]] || { echo "Pinned Rscript is unavailable." >&2; exit 2; }

declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  package="$(<"/sys/devices/system/cpu/cpu${cpu}/topology/physical_package_id")"
  core="$(<"/sys/devices/system/cpu/cpu${cpu}/topology/core_id")"
  key="${package}:${core}"
  [[ -z "${PHYSICAL[$key]:-}" ]] || { echo "CPU list repeats physical core $key." >&2; exit 2; }
  PHYSICAL[$key]=1
done
[[ "${#PHYSICAL[@]}" -eq 15 ]] || { echo "Expected 15 distinct physical cores." >&2; exit 2; }

free_gib="$(df -Pk /data | awk 'NR==2 {printf "%.0f", $4/1024/1024}')"
(( free_gib >= 100 )) || { echo "Less than 100 GiB is free on /data." >&2; exit 2; }
if pgrep -af 'run_joint_qdesn_pure_recursive_(quantile_worker|article_vb|article_mcmc)|joint_qdesn_recursive_mean_forecast_worker' >/dev/null; then
  echo "The source JOINT pipeline still owns compute workers." >&2
  exit 2
fi

run_pending_queue() {
  local stage="$1"
  mapfile -t ids < <("$R_BIN" application/scripts/emit_joint_qdesn_pure_recursive_expanded_pending.R \
    --root "$ROOT" --stage "$stage")
  [[ "${#ids[@]}" -gt 0 ]] || return 0
  local pids=()
  for slot in "${!CPUS[@]}"; do
    (
      for ((index=slot; index<${#ids[@]}; index+=15)); do
        taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" \
          application/scripts/run_joint_qdesn_pure_recursive_worker.R \
          --root "$ROOT" --stage "$stage" --worker-id "${ids[$index]}"
      done
    ) >"$ROOT/logs/${stage}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  local failed=0
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "$stage expanded worker queue failed." >&2; exit 1; }
}

if [[ ! -f "$ROOT/launch_readiness.csv" ]]; then
  "$R_BIN" application/scripts/prepare_joint_qdesn_pure_recursive_expanded_screen.R \
    --output-dir "$ROOT" --source-root "$SOURCE_ROOT" --require-pipeline-complete true
fi

mkdir -p "$ROOT/logs"
printf 'host,branch,head,cpu_affinity,physical_cores,data_free_gib,source_root,checked_at_utc\n%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$(hostname -f)" "$BRANCH" "$(git rev-parse HEAD)" "$CPU_LIST" "15" "$free_gib" "$SOURCE_ROOT" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ROOT/logs/launch_preflight.csv"

if [[ ! -f "$ROOT/ridge_final_health.csv" ]]; then
  run_pending_queue ridge
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R --root "$ROOT" --stage ridge
fi

if [[ ! -f "$ROOT/rhs_reuse_audit.csv" ]]; then
  "$R_BIN" application/scripts/import_joint_qdesn_pure_recursive_expanded_rhs.R \
    --root "$ROOT" --source-root "$SOURCE_ROOT"
fi

if [[ ! -f "$ROOT/rhs_final_health.csv" ]]; then
  run_pending_queue rhs
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R --root "$ROOT" --stage rhs
fi

if [[ ! -f "$ROOT/final_expanded_screen_status.csv" ]]; then
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_expanded_screen.R \
    --root "$ROOT" --source-root "$SOURCE_ROOT"
fi

printf 'status,completed_at_utc\nEXPANDED_SCREEN_COMPLETE_REVIEW_REQUIRED,%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ROOT/controller_terminal_status.csv"
