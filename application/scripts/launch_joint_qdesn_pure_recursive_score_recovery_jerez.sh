#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RSCRIPT="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
CAMPAIGN_ROOT="${JOINT_PURE_CAMPAIGN_ROOT:-${REPO_ROOT}/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
SOURCE_ROOT="${JOINT_PURE_CONFIRMATION_ROOT:-${REPO_ROOT}/application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${JOINT_PURE_SCORE_ROOT:-${REPO_ROOT}/application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
CONTRACT_PATH="${JOINT_PURE_SCORE_CONTRACT:-${SOURCE_ROOT}/score_packet/pure_recursive_score_contract.csv}"
RECOVERY_CONTRACT="${JOINT_PURE_SCORE_RECOVERY_CONTRACT:-${REPO_ROOT}/application/config/joint_qdesn_pure_recursive_score_recovery_v1.csv}"
CPU_LIST="${JOINT_PURE_SCORE_RECOVERY_CPUS:-}"
SESSION="${JOINT_PURE_SCORE_RECOVERY_SESSION:-joint_pure_score_recovery_20261002}"
RUNTIME="${SCORE_ROOT}/score_recovery_v1"
MODE="${1:---preflight}"

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

require_contract() {
  [[ "${JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION:-}" == \
    "JEREZ_PURE_RECURSIVE_15_PHYSICAL_SHARED" ]] || {
    echo "Refusing score recovery without shared Jerez authorization." >&2
    exit 64
  }
  [[ -x "$RSCRIPT" && -d "$CAMPAIGN_ROOT" && -d "$SOURCE_ROOT" && \
    -d "$SCORE_ROOT" && -f "$CONTRACT_PATH" && -f "$RECOVERY_CONTRACT" ]] || {
    echo "Score-recovery paths are incomplete." >&2
    exit 64
  }
  [[ -z "$(git -C "$REPO_ROOT" status --short --untracked-files=no)" ]] || {
    echo "Tracked Jerez worktree changes block score recovery." >&2
    exit 64
  }
}

preflight() {
  require_contract
  mkdir -p "$RUNTIME/logs" "$RUNTIME/exits"
  [[ "$(hostname -s)" == jerez* ]] || {
    echo "This recovery is frozen for Jerez." >&2
    exit 64
  }
  IFS=',' read -r -a cpus <<< "$CPU_LIST"
  [[ "${#cpus[@]}" == 2 ]] || { echo "Exactly two CPUs are required." >&2; exit 64; }
  [[ "$(printf '%s\n' "${cpus[@]}" | sort -nu | wc -l)" == 2 ]] || {
    echo "Recovery CPU list contains duplicates." >&2
    exit 64
  }
  local topology selected_keys sibling_cpus busy free_kib free_mem_kib state
  topology="$(lscpu -p=CPU,CORE,SOCKET | grep -v '^#')"
  printf '%s\n' "$topology" >"$RUNTIME/physical_core_inventory.csv"
  selected_keys="$(printf '%s\n' "$topology" | awk -F, -v list=",${CPU_LIST}," '
    index(list, "," $1 ",") {print $3 ":" $2}
  ')"
  [[ "$(printf '%s\n' "$selected_keys" | sort -u | wc -l)" == 2 ]] || {
    echo "Recovery CPUs do not map to two distinct physical cores." >&2
    exit 64
  }
  sibling_cpus="$(printf '%s\n' "$topology" | awk -F, -v keys="$selected_keys" '
    BEGIN {n=split(keys,a,"\n"); for(i=1;i<=n;i++) keep[a[i]]=1}
    keep[$3 ":" $2] {printf "%s%s", sep, $1; sep=","}
  ')"
  busy="$(ps -eLo psr=,pcpu=,pid=,comm= | awk -v list=",${sibling_cpus}," '
    index(list, "," $1 ",") && $2 + 0 >= 20 {seen[$3]=1}
    END {print length(seen)}
  ')"
  [[ "$busy" == 0 ]] || {
    echo "A selected physical core is already busy." >&2
    exit 64
  }
  for cpu in "${cpus[@]}"; do taskset -c "$cpu" true; done
  free_kib="$(df -Pk "$REPO_ROOT" | awk 'NR==2 {print $4}')"
  free_mem_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
  (( free_kib >= 20 * 1024 * 1024 )) || { echo "Recovery requires 20 GiB free." >&2; exit 64; }
  (( free_mem_kib >= 8 * 1024 * 1024 )) || { echo "Recovery requires 8 GiB memory." >&2; exit 64; }
  state="$("$RSCRIPT" -e '
    r <- commandArgs(TRUE)[1L]
    p <- read.csv(file.path(r, "cell_plan.csv"), stringsAsFactors=FALSE)
    s <- vapply(p$worker_id, function(i) {
      d <- file.path(r, "cells", sprintf("worker_%04d", i))
      if (file.exists(file.path(d, "DONE"))) "complete" else
        if (file.exists(file.path(d, "FAILED"))) "failed" else "pending"
    }, "")
    cat(paste(sum(s == "complete"), sum(s == "failed"), sum(s == "pending"),
      paste(p$worker_id[s == "failed"], collapse = ";"),
      paste(p$worker_id[s == "pending"], collapse = ";"), sep = ","))
  ' "$SCORE_ROOT")"
  [[ "$state" == "62,1,1,41,56" ]] || {
    echo "Frozen recovery entry state differs: $state" >&2
    exit 64
  }
  "$RSCRIPT" -e '
    source(commandArgs(TRUE)[1L]); app_set_repo_root(commandArgs(TRUE)[2L])
    for (f in c("00_packages.R", "joint_qdesn_recursive_mean_score_packet.R"))
      source(file.path(commandArgs(TRUE)[2L], "application/R", f))
    recovery <- app_joint_recursive_read_recovery_contract(commandArgs(TRUE)[3L])
    stopifnot(app_sha256_file(commandArgs(TRUE)[4L]) == recovery$parent_contract_sha256,
      app_sha256_file(file.path(commandArgs(TRUE)[5L], "cell_plan.csv")) == recovery$cell_plan_sha256)
  ' "$REPO_ROOT/application/R/00_packages.R" "$REPO_ROOT" "$RECOVERY_CONTRACT" \
    "$CONTRACT_PATH" "$SCORE_ROOT"
  {
    echo "host,cpu_list,sibling_cpus,entry_state,free_disk_kib,available_memory_kib,git_head,checked_at,status"
    printf '%s,"%s","%s","%s",%s,%s,%s,%s,pass\n' "$(hostname -s)" "$CPU_LIST" \
      "$sibling_cpus" "$state" "$free_kib" "$free_mem_kib" \
      "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$RUNTIME/recovery_preflight.csv"
}

run_internal() {
  preflight
  IFS=',' read -r -a cpus <<< "$CPU_LIST"
  set +e
  taskset -c "${cpus[0]}" "$RSCRIPT" \
    "$SCRIPT_DIR/run_joint_qdesn_recursive_mean_forecast_worker.R" \
    --root "$SCORE_ROOT" --source-root "$SOURCE_ROOT" \
    --contract-path "$CONTRACT_PATH" --worker-id 56 \
    >"$RUNTIME/logs/worker_0056.log" 2>&1 &
  pid56=$!
  taskset -c "${cpus[1]}" "$RSCRIPT" \
    "$SCRIPT_DIR/recover_joint_qdesn_pure_recursive_score_cell.R" \
    --root "$SCORE_ROOT" --source-root "$SOURCE_ROOT" \
    --contract-path "$CONTRACT_PATH" \
    --recovery-contract-path "$RECOVERY_CONTRACT" \
    >"$RUNTIME/logs/worker_0041_recovery.log" 2>&1 &
  pid41=$!
  wait "$pid56"; code56=$?
  wait "$pid41"; code41=$?
  set -e
  printf '%s\n' "$code56" >"$RUNTIME/exits/worker_0056.exit"
  printf '%s\n' "$code41" >"$RUNTIME/exits/worker_0041_recovery.exit"
  [[ "$code56" == 0 && "$code41" == 0 ]] || {
    echo "Score recovery workers failed: worker41=$code41 worker56=$code56" >&2
    exit 1
  }
  "$RSCRIPT" "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
    --root "$SCORE_ROOT" --source-root "$SOURCE_ROOT" \
    --contract-path "$CONTRACT_PATH" --require-complete true
  "$RSCRIPT" "$SCRIPT_DIR/finalize_joint_qdesn_recursive_mean_forecast.R" \
    --root "$SCORE_ROOT" --contract-path "$CONTRACT_PATH"
  printf 'status,completed_at_utc\nCOMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CAMPAIGN_ROOT/final_pipeline_status.csv"
  date -u +%Y-%m-%dT%H:%M:%SZ >"$RUNTIME/completed_at_utc"
}

case "$MODE" in
  --preflight) preflight ;;
  --internal) run_internal ;;
  --launch)
    require_contract
    [[ -n "$CPU_LIST" ]] || { echo "JOINT_PURE_SCORE_RECOVERY_CPUS is required." >&2; exit 64; }
    mkdir -p "$RUNTIME/logs" "$RUNTIME/exits"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Recovery tmux session already exists." >&2
      exit 64
    fi
    tmux new-session -d -s "$SESSION" \
      "env JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION=JEREZ_PURE_RECURSIVE_15_PHYSICAL_SHARED JOINT_PURE_SCORE_RECOVERY_CPUS=$(printf '%q' "$CPU_LIST") bash $(printf '%q' "$0") --internal >$(printf '%q' "$RUNTIME/controller.log") 2>&1; code=\$?; printf '%s\\n' \"\$code\" >$(printf '%q' "$RUNTIME/controller.exit"); exit \"\$code\""
    echo "Launched $SESSION on CPUs $CPU_LIST."
    ;;
  *) echo "Usage: $0 [--preflight|--internal|--launch]" >&2; exit 64 ;;
esac
