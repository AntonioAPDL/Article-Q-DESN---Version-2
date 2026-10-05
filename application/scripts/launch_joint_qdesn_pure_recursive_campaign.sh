#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
CONFIRMATION_ROOT="${2:-application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${3:-application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
BRANCH="work/joint-qdesn-pure-desn-recursive-selection-20260925"
CPU_LIST="2-16"
CPUS=(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

[[ "$(hostname -s)" == "jerez" ]] || { echo "This campaign may run only on jerez." >&2; exit 2; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || { echo "Wrong execution branch." >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Tracked worktree is dirty." >&2; exit 2; }
[[ "$(git rev-list --left-right --count '@{upstream}'...HEAD)" == $'0\t0' ]] || { echo "Execution branch is not synchronized." >&2; exit 2; }
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

run_numbered_queue() {
  local stage="$1" count="$2" script="$3" id_flag="$4"
  local pids=()
  for slot in "${!CPUS[@]}"; do
    (
      for ((id=slot+1; id<=count; id+=15)); do
        taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" "$script" --root "$ROOT" --stage "$stage" "$id_flag" "$id"
      done
    ) >"$ROOT/logs/${stage}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  local failed=0
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "$stage worker queue failed." >&2; exit 1; }
}

run_score_queue() {
  local label="$1" script="$2" id_flag="$3"
  shift 3
  local jobs=("$@") pids=()
  mkdir -p "$SCORE_ROOT/logs"
  for slot in "${!CPUS[@]}"; do
    (
      for ((index=slot; index<${#jobs[@]}; index+=15)); do
        env JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION=JEREZ_PURE_RECURSIVE_15_PHYSICAL \
          taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" "$script" \
          --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
          --contract-path "$CONFIRMATION_ROOT/score_packet/pure_recursive_score_contract.csv" \
          "$id_flag" "${jobs[$index]}"
      done
    ) >"$SCORE_ROOT/logs/${label}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  local failed=0
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "$label score queue failed." >&2; exit 1; }
}

if [[ ! -f "$ROOT/launch_readiness.csv" ]]; then
  "$R_BIN" application/scripts/prepare_joint_qdesn_pure_recursive_campaign.R --output-dir "$ROOT"
fi

mkdir -p "$ROOT/logs"
printf 'host,branch,head,cpu_affinity,physical_cores,data_free_gib,checked_at_utc\n%s,%s,%s,%s,%s,%s,%s\n' \
  "$(hostname -f)" "$BRANCH" "$(git rev-parse HEAD)" "$CPU_LIST" "15" "$free_gib" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"$ROOT/logs/launch_preflight.csv"

ridge_count="$(awk -F, 'NR==2 {print $3}' "$ROOT/expected_work.csv")"
if [[ ! -f "$ROOT/ridge_final_health.csv" ]]; then
  run_numbered_queue ridge "$ridge_count" application/scripts/run_joint_qdesn_pure_recursive_worker.R --worker-id
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R --root "$ROOT" --stage ridge
fi

rhs_count="$(($(wc -l <"$ROOT/rhs_worker_plan.csv") - 1))"
if [[ ! -f "$ROOT/rhs_final_health.csv" ]]; then
  run_numbered_queue rhs "$rhs_count" application/scripts/run_joint_qdesn_pure_recursive_worker.R --worker-id
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R --root "$ROOT" --stage rhs
fi

if [[ ! -f "$ROOT/quantile_family_plan.csv" ]]; then
  "$R_BIN" application/scripts/prepare_joint_qdesn_pure_recursive_quantiles.R --root "$ROOT"
fi

for stage_order in 1 2 3 4 5 6 7 8; do
  case "$stage_order" in
    1|2|7|8) expected_stage_jobs=24 ;;
    3|4|5) expected_stage_jobs=48 ;;
    6) expected_stage_jobs=168 ;;
    *) echo "Unknown quantile stage $stage_order." >&2; exit 2 ;;
  esac
  mapfile -t JOBS < <("$R_BIN" application/scripts/emit_joint_qdesn_pure_recursive_quantile_jobs.R \
    --root "$ROOT" --stage-order "$stage_order")
  [[ "${#JOBS[@]}" -eq "$expected_stage_jobs" ]] || {
    echo "Quantile stage $stage_order emitted ${#JOBS[@]} jobs; expected $expected_stage_jobs." >&2
    exit 2
  }
  pids=()
  for slot in "${!CPUS[@]}"; do
    (
      for ((index=slot; index<${#JOBS[@]}; index+=15)); do
        IFS=$'\t' read -r qroot job_id <<<"${JOBS[$index]}"
        [[ -n "$qroot" && -n "$job_id" ]] || {
          echo "Quantile stage $stage_order emitted an empty root or job ID at index $index." >&2
          exit 2
        }
        taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" application/scripts/run_joint_qdesn_pure_recursive_quantile_worker.R \
          --root "$qroot" --job-id "$job_id"
      done
    ) >"$ROOT/logs/quantile_stage_${stage_order}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "Quantile stage $stage_order failed." >&2; exit 1; }
done

if [[ ! -f "$ROOT/quantile_final_health.csv" ]]; then
  "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R --root "$ROOT" --stage quantile
fi

if [[ ! -f "$CONFIRMATION_ROOT/launch_readiness.csv" ]]; then
  taskset -c "$CPU_LIST" "$R_BIN" application/scripts/prepare_joint_qdesn_pure_recursive_confirmation.R \
    --campaign-root "$ROOT" --output-dir "$CONFIRMATION_ROOT"
fi

if [[ ! -f "$CONFIRMATION_ROOT/vb_final_artifact_manifest.csv" ]]; then
  taskset -c "$CPU_LIST" "$R_BIN" application/scripts/run_joint_qdesn_pure_recursive_article_vb.R \
    --root "$CONFIRMATION_ROOT" --workers 15
fi

if [[ ! -f "$CONFIRMATION_ROOT/mcmc_final_artifact_manifest.csv" ]]; then
  taskset -c "$CPU_LIST" "$R_BIN" application/scripts/run_joint_qdesn_pure_recursive_article_mcmc.R \
    --root "$CONFIRMATION_ROOT" --workers 15
fi

if [[ ! -f "$SCORE_ROOT/preflight_artifact_manifest.csv" ]]; then
  taskset -c "$CPU_LIST" "$R_BIN" application/scripts/prepare_joint_qdesn_pure_recursive_score_packet.R \
    --source-root "$CONFIRMATION_ROOT" --score-root "$SCORE_ROOT"
fi

CONTRACT_PATH="$CONFIRMATION_ROOT/score_packet/pure_recursive_score_contract.csv"
if [[ ! -f "$SCORE_ROOT/dgp_oracle_manifest.csv" ]]; then
  mapfile -t PRIMARY_ORACLE_IDS < <("$R_BIN" -e '
    x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
    cat(x$worker_id[as.logical(x$is_primary)], sep="\n")
  ' "$SCORE_ROOT/oracle_plan.csv")
  run_score_queue oracle_primary application/scripts/run_joint_qdesn_recursive_dgp_oracle_worker.R \
    --worker-id "${PRIMARY_ORACLE_IDS[@]}"
  set +e
  "$R_BIN" application/scripts/check_joint_qdesn_recursive_mean_forecast.R \
    --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
    --contract-path "$CONTRACT_PATH" --aggregate-oracles true
  oracle_status=$?
  set -e
  if [[ "$oracle_status" -eq 20 ]]; then
    mapfile -t EXTENSION_ORACLE_IDS < <("$R_BIN" -e '
      x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
      cat(x$worker_id, sep="\n")
    ' "$SCORE_ROOT/oracle_extension_plan.csv")
    run_score_queue oracle_extension application/scripts/run_joint_qdesn_recursive_dgp_oracle_worker.R \
      --worker-id "${EXTENSION_ORACLE_IDS[@]}"
    "$R_BIN" application/scripts/check_joint_qdesn_recursive_mean_forecast.R \
      --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
      --contract-path "$CONTRACT_PATH" --aggregate-oracles true
  elif [[ "$oracle_status" -ne 0 ]]; then
    echo "Primary oracle aggregation failed." >&2
    exit "$oracle_status"
  fi
fi

if [[ ! -f "$SCORE_ROOT/final_packet/DONE" ]]; then
  mapfile -t SENTINEL_IDS < <("$R_BIN" -e '
    x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
    cat(x$worker_id[as.logical(x$sentinel)], sep="\n")
  ' "$SCORE_ROOT/cell_plan.csv")
  run_score_queue score_sentinel application/scripts/run_joint_qdesn_recursive_mean_forecast_worker.R \
    --worker-id "${SENTINEL_IDS[@]}"
  "$R_BIN" application/scripts/check_joint_qdesn_recursive_mean_forecast.R \
    --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
    --contract-path "$CONTRACT_PATH" --require-sentinels true
  mapfile -t SCORE_IDS < <("$R_BIN" -e '
    x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
    cat(x$worker_id, sep="\n")
  ' "$SCORE_ROOT/cell_plan.csv")
  run_score_queue score_all application/scripts/run_joint_qdesn_recursive_mean_forecast_worker.R \
    --worker-id "${SCORE_IDS[@]}"
  "$R_BIN" application/scripts/check_joint_qdesn_recursive_mean_forecast.R \
    --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
    --contract-path "$CONTRACT_PATH" --require-complete true
  "$R_BIN" application/scripts/finalize_joint_qdesn_recursive_mean_forecast.R \
    --root "$SCORE_ROOT" --contract-path "$CONTRACT_PATH"
fi

printf 'status,completed_at_utc\nCOMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"$ROOT/final_pipeline_status.csv"
