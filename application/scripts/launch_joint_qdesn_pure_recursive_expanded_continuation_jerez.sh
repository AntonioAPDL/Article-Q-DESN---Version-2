#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
BRANCH="work/joint-qdesn-pure-desn-expanded-continuation-20261003"
SOURCE_WORKTREE="/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925"
EXPANDED_WORKTREE="/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_expanded_screen_20260925"
SOURCE_CAMPAIGN="$SOURCE_WORKTREE/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925"
SOURCE_CONFIRMATION="$SOURCE_WORKTREE/application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925"
EXPANDED_RUNTIME="$EXPANDED_WORKTREE/application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925"
CAMPAIGN_TAG="joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925"
CAMPAIGN_ROOT="$REPO_ROOT/application/cache/$CAMPAIGN_TAG"
CONFIRMATION_TAG="joint_qdesn_pure_recursive_expanded_continuation_confirmation_jerez_15core_20261003"
SCORE_TAG="joint_qdesn_pure_recursive_expanded_continuation_score_jerez_15core_20261003"
CONFIRMATION_ROOT="$REPO_ROOT/application/cache/$CONFIRMATION_TAG"
SCORE_ROOT="$REPO_ROOT/application/cache/$SCORE_TAG"
CONTRACT_PATH="$CONFIRMATION_ROOT/score_packet/pure_recursive_score_contract.csv"
CPU_LIST="0,1,8,9,12,13,19,20,24,25,27,28,29,30,31"
CPUS=(0 1 8 9 12 13 19 20 24 25 27 28 29 30 31)
SESSION="joint_pure_expanded_continuation_20261003"
MODE="${1:---preflight}"
CONTROL_ROOT="$REPO_ROOT/local_trackers/$SCORE_TAG"

cd "$REPO_ROOT"

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

require_repository() {
  [[ "$(hostname -s)" == jerez* ]] || {
    echo "Expanded continuation is frozen for Jerez." >&2; exit 64;
  }
  [[ -x "$R_BIN" ]] || { echo "Pinned R 4.6.0 is unavailable." >&2; exit 64; }
  [[ "$(git -C "$REPO_ROOT" branch --show-current)" == "$BRANCH" ]] || {
    echo "Wrong expanded-continuation branch." >&2; exit 64;
  }
  [[ -z "$(git -C "$REPO_ROOT" status --short --untracked-files=no)" ]] || {
    echo "Tracked worktree changes block continuation." >&2; exit 64;
  }
  [[ "$(git -C "$REPO_ROOT" rev-list --left-right --count HEAD...@{upstream})" == $'0\t0' ]] || {
    echo "Continuation branch is not synchronized with its upstream." >&2; exit 64;
  }
  [[ -d "$SOURCE_CAMPAIGN" && -d "$SOURCE_CONFIRMATION" && -d "$EXPANDED_RUNTIME" ]] || {
    echo "A frozen source runtime is missing." >&2; exit 64;
  }
}

ensure_campaign_link() {
  mkdir -p "$REPO_ROOT/application/cache"
  if [[ -L "$CAMPAIGN_ROOT" ]]; then
    [[ "$(readlink -f "$CAMPAIGN_ROOT")" == "$(readlink -f "$EXPANDED_RUNTIME")" ]] || {
      echo "Campaign runtime link points to an unexpected source." >&2; exit 64;
    }
  elif [[ -e "$CAMPAIGN_ROOT" ]]; then
    echo "Campaign runtime path exists but is not the frozen expanded-runtime link." >&2
    exit 64
  else
    ln -s "$EXPANDED_RUNTIME" "$CAMPAIGN_ROOT"
  fi
}

preflight() {
  require_repository
  ensure_campaign_link
  declare -A physical=()
  local cpu package core key free_gib busy_processes affinity broad_affinity
  local psr pcpu pid command pinned_conflicts=""
  for cpu in "${CPUS[@]}"; do
    package="$(<"/sys/devices/system/cpu/cpu${cpu}/topology/physical_package_id")"
    core="$(<"/sys/devices/system/cpu/cpu${cpu}/topology/core_id")"
    key="${package}:${core}"
    [[ -z "${physical[$key]:-}" ]] || {
      echo "CPU list repeats physical core $key." >&2; exit 64;
    }
    physical[$key]=1
  done
  [[ "${#physical[@]}" -eq 15 ]] || {
    echo "Expected 15 distinct physical cores." >&2; exit 64;
  }
  free_gib="$(df -Pk /data | awk 'NR==2 {printf "%.0f", $4/1024/1024}')"
  (( free_gib >= 50 )) || { echo "Less than 50 GiB is free on /data." >&2; exit 64; }
  busy_processes="$(ps -eLo psr=,pcpu=,pid=,comm=,args= | awk \
    -v list=",${CPU_LIST}," '
      index(list, "," $1 ",") && $2 + 0 >= 20 {print}
    ')"
  broad_affinity="0-$(lscpu -p=CPU | grep -v '^#' | sort -n | tail -1)"
  : >"$CONTROL_ROOT/high_cpu_background_affinity.csv"
  echo "pid,current_cpu,pcpu,affinity,classification,command" \
    >"$CONTROL_ROOT/high_cpu_background_affinity.csv"
  while read -r psr pcpu pid command; do
    [[ -n "${pid:-}" ]] || continue
    affinity="$(taskset -pc "$pid" 2>/dev/null | sed 's/^.*: //')"
    if [[ "$affinity" == "$broad_affinity" ]]; then
      classification="broad_affinity_background_allowed"
    else
      classification="pinned_or_restricted_conflict"
      pinned_conflicts+="${pid}:${affinity}:${command}"$'\n'
    fi
    printf '%s,%s,%s,"%s",%s,"%s"\n' "$pid" "$psr" "$pcpu" \
      "$affinity" "$classification" "${command//\"/\"\"}" \
      >>"$CONTROL_ROOT/high_cpu_background_affinity.csv"
  done <<<"$busy_processes"
  [[ -z "$pinned_conflicts" ]] || {
    echo "A selected continuation core has a pinned/restricted conflict:" >&2
    printf '%s' "$pinned_conflicts" >&2
    exit 64
  }
  if pgrep -af 'run_joint_qdesn_pure_recursive_(quantile_worker|article_vb|article_mcmc)|run_joint_qdesn_recursive_(dgp_oracle_worker|mean_forecast_worker)' >/dev/null; then
    echo "Another JOINT continuation worker or controller is active." >&2; exit 64
  fi
  mkdir -p "$CONTROL_ROOT"
  {
    echo "host,branch,head,cpu_affinity,physical_cores,data_free_gib,source_campaign,expanded_runtime,checked_at_utc,status"
    printf '%s,%s,%s,"%s",15,%s,%s,%s,%s,pass\n' \
      "$(hostname -f)" "$BRANCH" "$(git -C "$REPO_ROOT" rev-parse HEAD)" \
      "$CPU_LIST" "$free_gib" "$SOURCE_CAMPAIGN" "$EXPANDED_RUNTIME" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$CONTROL_ROOT/continuation_preflight.csv"
}

run_quantile_stage() {
  local stage_order="$1" expected_stage_jobs jobs=() pids=() failed=0
  case "$stage_order" in
    1|2|7|8) expected_stage_jobs=24 ;;
    3|4|5) expected_stage_jobs=48 ;;
    6) expected_stage_jobs=168 ;;
    *) echo "Unknown quantile stage $stage_order." >&2; exit 64 ;;
  esac
  mapfile -t jobs < <("$R_BIN" "$SCRIPT_DIR/emit_joint_qdesn_pure_recursive_quantile_jobs.R" \
    --root "$CAMPAIGN_ROOT" --stage-order "$stage_order")
  [[ "${#jobs[@]}" -eq "$expected_stage_jobs" ]] || {
    echo "Quantile stage $stage_order emitted ${#jobs[@]} jobs; expected $expected_stage_jobs." >&2
    exit 64
  }
  for slot in "${!CPUS[@]}"; do
    (
      for ((index=slot; index<${#jobs[@]}; index+=15)); do
        IFS=$'\t' read -r qroot job_id <<<"${jobs[$index]}"
        taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" \
          "$SCRIPT_DIR/run_joint_qdesn_pure_recursive_quantile_worker.R" \
          --root "$qroot" --job-id "$job_id"
      done
    ) >"$CAMPAIGN_ROOT/logs/expanded_quantile_stage_${stage_order}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "Quantile stage $stage_order failed." >&2; exit 1; }
}

run_score_queue() {
  local label="$1" script="$2" id_flag="$3"; shift 3
  local jobs=("$@") pids=() failed=0
  for slot in "${!CPUS[@]}"; do
    (
      for ((index=slot; index<${#jobs[@]}; index+=15)); do
        env JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION=JEREZ_PURE_RECURSIVE_15_PHYSICAL_SHARED \
          taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" "$script" \
          --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
          --contract-path "$CONTRACT_PATH" "$id_flag" "${jobs[$index]}"
      done
    ) >"$SCORE_ROOT/logs/${label}_slot_$(printf '%02d' "$slot").log" 2>&1 &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || { echo "$label score queue failed." >&2; exit 1; }
}

run_internal() {
  preflight
  mkdir -p "$CAMPAIGN_ROOT/logs"

  if [[ ! -f "$CAMPAIGN_ROOT/final_expanded_screen_status.csv" ]]; then
    "$R_BIN" "$SCRIPT_DIR/finalize_joint_qdesn_pure_recursive_expanded_screen.R" \
      --root "$CAMPAIGN_ROOT" --source-root "$SOURCE_CAMPAIGN"
  fi
  printf 'status,completed_at_utc\nEXPANDED_SCREEN_COMPLETE_REVIEWED_FOR_SELECTIVE_CONTINUATION,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CAMPAIGN_ROOT/controller_terminal_status.csv"

  if [[ ! -f "$CAMPAIGN_ROOT/quantile_family_plan.csv" ]]; then
    "$R_BIN" "$SCRIPT_DIR/prepare_joint_qdesn_pure_recursive_quantiles.R" \
      --root "$CAMPAIGN_ROOT"
  fi
  if [[ ! -f "$CAMPAIGN_ROOT/quantile_reuse_audit.csv" ]]; then
    "$R_BIN" "$SCRIPT_DIR/import_joint_qdesn_pure_recursive_selective_reuse.R" \
      --stage quantile --target-root "$CAMPAIGN_ROOT" \
      --source-root "$SOURCE_CAMPAIGN"
  fi
  if [[ ! -f "$CAMPAIGN_ROOT/quantile_final_health.csv" ]]; then
    "$R_BIN" -e '
      source(commandArgs(TRUE)[[1L]])
      h <- app_joint_pure_quantile_health(commandArgs(TRUE)[[2L]])
      stopifnot(h$expected == 408L, h$completed >= 306L,
        h$completed <= 408L, h$failed == 0L,
        h$remaining == 408L - h$completed)
    ' "$SCRIPT_DIR/_joint_qdesn_pure_recursive_bootstrap.R" "$CAMPAIGN_ROOT"
    for stage_order in 1 2 3 4 5 6 7 8; do
      run_quantile_stage "$stage_order"
    done
    "$R_BIN" "$SCRIPT_DIR/finalize_joint_qdesn_pure_recursive_stage.R" \
      --root "$CAMPAIGN_ROOT" --stage quantile
  else
    "$R_BIN" -e '
      source(commandArgs(TRUE)[[1L]])
      root <- commandArgs(TRUE)[[2L]]
      h <- app_joint_pure_quantile_health(root)
      manifest <- file.path(root, "quantile_artifact_manifest.csv")
      verification <- app_joint_shared_verify_manifest(root, manifest)
      stopifnot(h$expected == 408L, h$completed == 408L,
        h$failed == 0L, h$remaining == 0L,
        nrow(verification) > 0L, all(verification$verified))
    ' "$SCRIPT_DIR/_joint_qdesn_pure_recursive_bootstrap.R" "$CAMPAIGN_ROOT"
  fi

  if [[ ! -f "$CONFIRMATION_ROOT/launch_readiness.csv" ]]; then
    taskset -c "$CPU_LIST" "$R_BIN" \
      "$SCRIPT_DIR/prepare_joint_qdesn_pure_recursive_confirmation.R" \
      --campaign-root "$CAMPAIGN_ROOT" --output-dir "$CONFIRMATION_ROOT" \
      --execution-branch "$BRANCH" --run-tag "$CONFIRMATION_TAG" \
      --source-worktree "$REPO_ROOT" \
      --contract-version joint_qdesn_pure_recursive_article_confirmation_v3
  fi
  if [[ ! -f "$CONFIRMATION_ROOT/vb_reuse_audit.csv" ]]; then
    "$R_BIN" "$SCRIPT_DIR/import_joint_qdesn_pure_recursive_selective_reuse.R" \
      --stage vb --target-root "$CONFIRMATION_ROOT" \
      --source-root "$SOURCE_CONFIRMATION" \
      --target-campaign-root "$CAMPAIGN_ROOT" \
      --source-campaign-root "$SOURCE_CAMPAIGN"
  fi
  "$R_BIN" -e '
    source(commandArgs(TRUE)[[1L]])
    h <- app_joint_article_vb_health(commandArgs(TRUE)[[2L]])
    stopifnot(h$expected == 136L, h$completed == 102L,
      h$failed == 0L, h$remaining == 34L)
  ' "$SCRIPT_DIR/_joint_qdesn_pure_recursive_bootstrap.R" "$CONFIRMATION_ROOT"
  if [[ ! -f "$CONFIRMATION_ROOT/vb_final_artifact_manifest.csv" ]]; then
    taskset -c "$CPU_LIST" "$R_BIN" \
      "$SCRIPT_DIR/run_joint_qdesn_pure_recursive_article_vb.R" \
      --root "$CONFIRMATION_ROOT" --workers 15
  fi

  if [[ ! -f "$CONFIRMATION_ROOT/mcmc_reuse_audit.csv" ]]; then
    "$R_BIN" "$SCRIPT_DIR/import_joint_qdesn_pure_recursive_selective_reuse.R" \
      --stage mcmc --target-root "$CONFIRMATION_ROOT" \
      --source-root "$SOURCE_CONFIRMATION" \
      --target-campaign-root "$CAMPAIGN_ROOT" \
      --source-campaign-root "$SOURCE_CAMPAIGN"
  fi
  "$R_BIN" -e '
    source(commandArgs(TRUE)[[1L]])
    p <- app_read_csv(file.path(commandArgs(TRUE)[[2L]], "mcmc_worker_plan.csv"))
    s <- app_joint_article_mcmc_worker_state(commandArgs(TRUE)[[2L]], p)
    stopifnot(nrow(s) == 160L, sum(s$done) == 120L,
      sum(s$failed) == 0L, sum(!s$done & !s$failed) == 40L)
  ' "$SCRIPT_DIR/_joint_qdesn_pure_recursive_bootstrap.R" "$CONFIRMATION_ROOT"
  if [[ ! -f "$CONFIRMATION_ROOT/mcmc_final_artifact_manifest.csv" ]]; then
    taskset -c "$CPU_LIST" "$R_BIN" \
      "$SCRIPT_DIR/run_joint_qdesn_pure_recursive_article_mcmc.R" \
      --root "$CONFIRMATION_ROOT" --workers 15
  fi

  if [[ ! -f "$SCORE_ROOT/preflight_artifact_manifest.csv" ]]; then
    taskset -c "$CPU_LIST" "$R_BIN" \
      "$SCRIPT_DIR/prepare_joint_qdesn_pure_recursive_score_packet.R" \
      --source-root "$CONFIRMATION_ROOT" --score-root "$SCORE_ROOT"
  fi
  mkdir -p "$SCORE_ROOT/logs"
  if [[ ! -f "$SCORE_ROOT/dgp_oracle_manifest.csv" ]]; then
    mapfile -t oracle_ids < <("$R_BIN" -e '
      x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
      cat(x$worker_id[as.logical(x$is_primary)], sep="\n")
    ' "$SCORE_ROOT/oracle_plan.csv")
    run_score_queue oracle_primary \
      "$SCRIPT_DIR/run_joint_qdesn_recursive_dgp_oracle_worker.R" \
      --worker-id "${oracle_ids[@]}"
    set +e
    "$R_BIN" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
      --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
      --contract-path "$CONTRACT_PATH" --aggregate-oracles true
    oracle_status=$?
    set -e
    if [[ "$oracle_status" -eq 20 ]]; then
      mapfile -t extension_ids < <("$R_BIN" -e '
        x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
        cat(x$worker_id, sep="\n")
      ' "$SCORE_ROOT/oracle_extension_plan.csv")
      run_score_queue oracle_extension \
        "$SCRIPT_DIR/run_joint_qdesn_recursive_dgp_oracle_worker.R" \
        --worker-id "${extension_ids[@]}"
      "$R_BIN" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
        --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
        --contract-path "$CONTRACT_PATH" --aggregate-oracles true
    elif [[ "$oracle_status" -ne 0 ]]; then
      exit "$oracle_status"
    fi
  fi
  if [[ ! -f "$SCORE_ROOT/final_packet/DONE" ]]; then
    mapfile -t sentinel_ids < <("$R_BIN" -e '
      x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
      cat(x$worker_id[as.logical(x$sentinel)], sep="\n")
    ' "$SCORE_ROOT/cell_plan.csv")
    run_score_queue score_sentinel \
      "$SCRIPT_DIR/run_joint_qdesn_recursive_mean_forecast_worker.R" \
      --worker-id "${sentinel_ids[@]}"
    "$R_BIN" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
      --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
      --contract-path "$CONTRACT_PATH" --require-sentinels true
    mapfile -t score_ids < <("$R_BIN" -e '
      x <- read.csv(commandArgs(TRUE)[1L], stringsAsFactors=FALSE)
      cat(x$worker_id, sep="\n")
    ' "$SCORE_ROOT/cell_plan.csv")
    run_score_queue score_all \
      "$SCRIPT_DIR/run_joint_qdesn_recursive_mean_forecast_worker.R" \
      --worker-id "${score_ids[@]}"
    "$R_BIN" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
      --root "$SCORE_ROOT" --source-root "$CONFIRMATION_ROOT" \
      --contract-path "$CONTRACT_PATH" --require-complete true
    "$R_BIN" "$SCRIPT_DIR/finalize_joint_qdesn_recursive_mean_forecast.R" \
      --root "$SCORE_ROOT" --contract-path "$CONTRACT_PATH"
  fi
  printf 'status,completed_at_utc\nCOMPLETE_WITH_EXPANDED_TWO_FAMILY_REFIT_AND_VERIFIED_SIX_FAMILY_REUSE,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"$CAMPAIGN_ROOT/final_expanded_continuation_status.csv"
}

case "$MODE" in
  --preflight) preflight ;;
  --internal) run_internal ;;
  --launch)
    require_repository
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Continuation tmux session already exists." >&2; exit 64
    fi
    mkdir -p "$CONTROL_ROOT"
    tmux new-session -d -s "$SESSION" \
      "bash $(printf '%q' "$0") --internal >$(printf '%q' "$CONTROL_ROOT/controller.log") 2>&1; code=\$?; printf '%s\n' \"\$code\" >$(printf '%q' "$CONTROL_ROOT/controller.exit"); exit \"\$code\""
    echo "Launched $SESSION."
    ;;
  *) echo "Usage: $0 [--preflight|--internal|--launch]" >&2; exit 64 ;;
esac
