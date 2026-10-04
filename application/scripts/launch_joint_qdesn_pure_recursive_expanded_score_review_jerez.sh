#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_WORKTREE="/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_expanded_continuation_20261003"
RSCRIPT="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
CAMPAIGN_ROOT="${JOINT_PURE_CAMPAIGN_ROOT:-${SOURCE_WORKTREE}/application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925}"
SOURCE_ROOT="${JOINT_PURE_CONFIRMATION_ROOT:-${SOURCE_WORKTREE}/application/cache/joint_qdesn_pure_recursive_expanded_continuation_confirmation_jerez_15core_20261003}"
SCORE_ROOT="${JOINT_PURE_SCORE_ROOT:-${SOURCE_WORKTREE}/application/cache/joint_qdesn_pure_recursive_expanded_continuation_score_jerez_15core_20261003}"
CONTRACT_PATH="${JOINT_PURE_SCORE_CONTRACT:-${SOURCE_ROOT}/score_packet/pure_recursive_score_contract.csv}"
RECOVERY_CONTRACT="${JOINT_PURE_SCORE_RECOVERY_CONTRACT:-${REPO_ROOT}/application/config/joint_qdesn_pure_recursive_expanded_score_recovery_v1_20261004.csv}"
REVIEW_CONTRACT="${JOINT_PURE_SCORE_REVIEW_CONTRACT:-${REPO_ROOT}/application/config/joint_qdesn_pure_recursive_expanded_score_review_closeout_v2_20261004.csv}"
CPU="${JOINT_PURE_SCORE_REVIEW_CPU:-}"
SESSION="${JOINT_PURE_SCORE_REVIEW_SESSION:-joint_pure_expanded_score_review_20261004}"
RUNTIME="${SCORE_ROOT}/score_recovery_v2"
EXPECTED_BRANCH="work/joint-qdesn-pure-desn-expanded-score-closeout-20261004"
MODE="${1:---preflight}"

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

require_contract() {
  [[ "${JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION:-}" == \
    "JEREZ_PURE_RECURSIVE_SCORE_REVIEW_V2" ]] || {
    echo "Refusing score review without its exact Jerez authorization." >&2
    exit 64
  }
  [[ -x "$RSCRIPT" && -d "$CAMPAIGN_ROOT" && -d "$SOURCE_ROOT" && \
    -d "$SCORE_ROOT" && -f "$CONTRACT_PATH" && -f "$RECOVERY_CONTRACT" && \
    -f "$REVIEW_CONTRACT" ]] || {
    echo "Expanded score-review paths are incomplete." >&2
    exit 64
  }
  [[ "$(git -C "$REPO_ROOT" branch --show-current)" == "$EXPECTED_BRANCH" ]] || {
    echo "Expanded score review must run from its dedicated branch." >&2
    exit 64
  }
  [[ -z "$(git -C "$REPO_ROOT" status --short --untracked-files=no)" ]] || {
    echo "Tracked Jerez worktree changes block score review." >&2
    exit 64
  }
  [[ "$(git -C "$REPO_ROOT" rev-list --left-right --count HEAD...@{upstream})" == \
    $'0\t0' ]] || {
    echo "Expanded score-review branch is not synchronized with upstream." >&2
    exit 64
  }
}

preflight() {
  require_contract
  mkdir -p "$RUNTIME/logs" "$RUNTIME/exits"
  [[ "$(hostname -s)" == jerez* ]] || {
    echo "This score review is frozen for Jerez." >&2
    exit 64
  }
  [[ "$CPU" =~ ^[0-9]+$ ]] || {
    echo "Exactly one logical CPU is required." >&2
    exit 64
  }
  local topology key sibling_cpus busy free_kib free_mem_kib state
  topology="$(lscpu -p=CPU,CORE,SOCKET | grep -v '^#')"
  printf '%s\n' "$topology" >"$RUNTIME/physical_core_inventory.csv"
  key="$(printf '%s\n' "$topology" | awk -F, -v cpu="$CPU" '$1 == cpu {print $3 ":" $2}')"
  [[ -n "$key" ]] || { echo "Selected CPU is absent from topology." >&2; exit 64; }
  sibling_cpus="$(printf '%s\n' "$topology" | awk -F, -v key="$key" \
    '$3 ":" $2 == key {printf "%s%s", sep, $1; sep=","}')"
  busy="$(ps -eLo psr=,pcpu=,pid=,comm= | awk -v list=",${sibling_cpus}," '
    index(list, "," $1 ",") && $2 + 0 >= 20 {seen[$3]=1}
    END {print length(seen)}
  ')"
  [[ "$busy" == 0 ]] || { echo "The selected physical core is busy." >&2; exit 64; }
  taskset -c "$CPU" true
  free_kib="$(df -Pk "$SCORE_ROOT" | awk 'NR==2 {print $4}')"
  free_mem_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
  (( free_kib >= 20 * 1024 * 1024 )) || { echo "Score review requires 20 GiB free." >&2; exit 64; }
  (( free_mem_kib >= 8 * 1024 * 1024 )) || { echo "Score review requires 8 GiB memory." >&2; exit 64; }
  if pgrep -af 'run_joint_qdesn_pure_recursive_(article_vb|article_mcmc)|run_joint_qdesn_recursive_(dgp_oracle_worker|mean_forecast_worker)' >/dev/null; then
    echo "Another JOINT confirmation or score worker is active." >&2
    exit 64
  fi
  state="$("$RSCRIPT" -e '
    r <- commandArgs(TRUE)[1L]
    p <- read.csv(file.path(r, "cell_plan.csv"), stringsAsFactors=FALSE)
    s <- vapply(p$worker_id, function(i) {
      d <- file.path(r, "cells", sprintf("worker_%04d", i))
      if (file.exists(file.path(d, "DONE"))) "complete" else
        if (file.exists(file.path(d, "FAILED"))) "failed" else "pending"
    }, "")
    cat(paste(sum(s == "complete"), sum(s == "failed"), sum(s == "pending"),
      paste(p$worker_id[s == "failed"], collapse = ";"), sep = ","))
  ' "$SCORE_ROOT")"
  [[ "$state" == "63,1,0,41" ]] || {
    echo "Frozen expanded review entry state differs: $state" >&2
    exit 64
  }
  [[ ! -e "$SCORE_ROOT/final_packet/DONE" ]] || { echo "Final packet already exists." >&2; exit 64; }
  "$RSCRIPT" -e '
    args <- commandArgs(TRUE)
    source(file.path(args[[1L]], "application/scripts",
      "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
    review <- app_joint_recursive_read_review_contract(args[[2L]])
    stopifnot(app_sha256_file(args[[3L]]) == review$parent_contract_sha256,
      app_sha256_file(file.path(args[[4L]], "cell_plan.csv")) ==
        review$cell_plan_sha256,
      app_sha256_file(args[[5L]]) == review$prior_recovery_contract_sha256,
      app_sha256_file(file.path(args[[4L]], "cells", "worker_0056",
        "artifact_manifest.csv")) == review$completed_worker_manifest_sha256)
  ' "$REPO_ROOT" "$REVIEW_CONTRACT" "$CONTRACT_PATH" "$SCORE_ROOT" "$RECOVERY_CONTRACT"
  {
    echo "host,cpu,sibling_cpus,entry_state,free_disk_kib,available_memory_kib,git_head,checked_at,status"
    printf '%s,%s,"%s","%s",%s,%s,%s,%s,pass\n' "$(hostname -s)" "$CPU" \
      "$sibling_cpus" "$state" "$free_kib" "$free_mem_kib" \
      "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$RUNTIME/review_preflight.csv"
}

run_internal() {
  preflight
  set +e
  taskset -c "$CPU" "$RSCRIPT" \
    "$SCRIPT_DIR/closeout_joint_qdesn_pure_recursive_score_review.R" \
    --root "$SCORE_ROOT" --source-root "$SOURCE_ROOT" \
    --contract-path "$CONTRACT_PATH" \
    --recovery-contract-path "$RECOVERY_CONTRACT" \
    --review-contract-path "$REVIEW_CONTRACT" \
    >"$RUNTIME/logs/worker_0041_review.log" 2>&1
  code=$?
  set -e
  printf '%s\n' "$code" >"$RUNTIME/exits/worker_0041_review.exit"
  [[ "$code" == 0 ]] || { echo "Score review worker failed: worker41=$code" >&2; exit 1; }
  "$RSCRIPT" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
    --root "$SCORE_ROOT" --source-root "$SOURCE_ROOT" \
    --contract-path "$CONTRACT_PATH" --require-complete true
  "$RSCRIPT" "$SCRIPT_DIR/finalize_joint_qdesn_recursive_mean_forecast.R" \
    --root "$SCORE_ROOT" --contract-path "$CONTRACT_PATH"
  "$RSCRIPT" -e '
    root <- commandArgs(TRUE)[1L]
    status <- read.csv(file.path(root, "final_packet", "packet_status.csv"),
      stringsAsFactors=FALSE)
    stopifnot(nrow(status) == 1L,
      status$status[[1L]] == "COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW",
      status$strict_score_pass_cells[[1L]] == 63L,
      status$score_review_cells[[1L]] == 1L,
      status$completed_cells[[1L]] == 64L)
  ' "$SCORE_ROOT"
  printf 'status,score_stability_review_cells,completed_at_utc\nCOMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS,1,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CAMPAIGN_ROOT/final_expanded_continuation_status.csv"
  date -u +%Y-%m-%dT%H:%M:%SZ >"$RUNTIME/completed_at_utc"
}

case "$MODE" in
  --preflight) preflight ;;
  --internal) run_internal ;;
  --launch)
    require_contract
    [[ -n "$CPU" ]] || { echo "JOINT_PURE_SCORE_REVIEW_CPU is required." >&2; exit 64; }
    mkdir -p "$RUNTIME/logs" "$RUNTIME/exits"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Expanded score-review tmux session already exists." >&2
      exit 64
    fi
    tmux new-session -d -s "$SESSION" \
      "env JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION=JEREZ_PURE_RECURSIVE_SCORE_REVIEW_V2 JOINT_PURE_SCORE_REVIEW_CPU=$(printf '%q' "$CPU") bash $(printf '%q' "$0") --internal >$(printf '%q' "$RUNTIME/controller.log") 2>&1; code=\$?; printf '%s\\n' \"\$code\" >$(printf '%q' "$RUNTIME/controller.exit"); exit \"\$code\""
    echo "Launched $SESSION on CPU $CPU."
    ;;
  *) echo "Usage: $0 [--preflight|--internal|--launch]" >&2; exit 64 ;;
esac
