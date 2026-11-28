#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 ROOT STAGE" >&2
  exit 2
fi
ROOT=$1
STAGE=$2
CPU_LIST=${CPU_LIST:-}
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

case "$STAGE" in
  sentinel_context) PLAN=sentinel_context_plan.csv ;;
  sentinel) PLAN=sentinel_plan.csv ;;
  screen_context) PLAN=screen_context_plan.csv ;;
  screen) PLAN=screen_plan.csv ;;
  qualification_context) PLAN=qualification_context_plan.csv ;;
  qualification) PLAN=qualification_plan.csv ;;
  mcmc) PLAN=mcmc_plan.csv ;;
  mcmc_score) PLAN=mcmc_score_plan.csv ;;
  *) echo "Unsupported V8 stage: $STAGE" >&2; exit 2 ;;
esac

[[ $(hostname -f) == jerez.be.ucsc.edu ]] || { echo "V8 production is authorized only on Jerez." >&2; exit 2; }
[[ -x $R_BIN ]] || { echo "Pinned R 4.6.0 is unavailable." >&2; exit 2; }
"$R_BIN" --version 2>&1 | head -1 | grep -q 'version 4.6.0' || { echo "V8 requires R 4.6.0." >&2; exit 2; }
[[ -n $CPU_LIST ]] || { echo "CPU_LIST is required." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 15 )) || { echo "V8 permits 1-15 physical workers." >&2; exit 2; }
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || { echo "Duplicate CPUs." >&2; exit 2; }
declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU: $cpu" >&2; exit 2; }
  topo=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, -v cpu="$cpu" '$1==cpu && $4=="Y" {print $2 ":" $3}')
  [[ -n $topo && -z ${PHYSICAL[$topo]:-} ]] || { echo "CPU topology is invalid or duplicated: $cpu" >&2; exit 2; }
  PHYSICAL[$topo]=$cpu
done

[[ -f $ROOT/$PLAN ]] || { echo "Stage plan is absent: $ROOT/$PLAN" >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || { echo "V8 execution worktree must be clean." >&2; exit 2; }
branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
[[ $branch == work/joint-qdesn-persistent-tail-v11-stable-gaussian-m0-20261128 ]] || { echo "Unexpected V8 correction branch." >&2; exit 2; }
[[ -n $upstream && $(git rev-list --left-right --count "$upstream...HEAD") == $'0\t0' ]] || { echo "V8 branch is not synchronized." >&2; exit 2; }

require_complete() {
  local prior=$1
  "$R_BIN" -e 'source("application/scripts/_joint_qdesn_persistent_tail_v8_bootstrap.R"); x <- app_joint_pht8_health(commandArgs(TRUE)[1], commandArgs(TRUE)[2]); if (x$completed != x$expected || x$failed != 0) quit(status=1)' "$ROOT" "$prior"
}
case "$STAGE" in
  sentinel) require_complete sentinel_context ;;
  screen_context) grep -q V8_SENTINEL_COMPLETE_SCREEN_AUTHORIZED "$ROOT/sentinel_decision.csv" ;;
  screen) require_complete screen_context ;;
  qualification_context) grep -q V8_SCREEN_COMPLETE_QUALIFICATION_AUTHORIZED "$ROOT/screen_decision.csv" ;;
  qualification) require_complete qualification_context ;;
  mcmc) grep -q V8_QUALIFICATION_COMPLETE_MCMC_AUTHORIZED "$ROOT/qualification_decision.csv" ;;
  mcmc_score) grep -q V8_MCMC_COMPLETE_SCORE_AUTHORIZED "$ROOT/mcmc_decision.csv" ;;
esac

active=$(ps -u "$USER" -o comm=,args= | awk '$1 ~ /^R/ && tolower($0) ~ /(joint_qdesn|glofas|pricefm)/ {print}')
[[ -z $active ]] || { echo "Another scientific R process is active on Jerez:" >&2; printf '%s\n' "$active" >&2; exit 2; }
free_gib=$(df -BG --output=avail /data | tail -1 | tr -dc '0-9')
available_gib=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 80 )) || { echo "Jerez free space is below 80 GiB." >&2; exit 2; }
(( available_gib >= 128 )) || { echo "Jerez available memory is below 128 GiB." >&2; exit 2; }

lock="$ROOT/.${STAGE}_launch_lock"
mkdir "$lock" 2>/dev/null || { echo "Stage launch lock exists." >&2; exit 2; }
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
mkdir -p "$ROOT/orchestration/$STAGE"
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git rev-parse HEAD)" >> "$ROOT/${STAGE}_capacity_receipt.csv"

mapfile -t IDS < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1], check.names=FALSE); cat(x$worker_id, sep="\n")' "$ROOT/$PLAN")
fifo="$ROOT/orchestration/$STAGE/cpu_fifo"; rm -f "$fifo"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done
status=0
for worker_id in "${IDS[@]}"; do
  IFS= read -r cpu <&9
  {
    log="$ROOT/orchestration/$STAGE/worker_$(printf '%05d' "$worker_id").log"
    if ! taskset -c "$cpu" nice -n 10 env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      "$R_BIN" application/scripts/run_joint_qdesn_persistent_tail_v8_worker.R "$ROOT" "$STAGE" "$worker_id" >"$log" 2>&1; then
      touch "$ROOT/orchestration/$STAGE/WORKER_FAILURE"
    fi
    printf '%s\n' "$cpu" >&9
  } &
done
wait || status=$?
exec 9>&-
[[ ! -f $ROOT/orchestration/$STAGE/WORKER_FAILURE ]] || status=1
"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_v8.R "$ROOT" || status=1
printf '%s\n' "$status" > "$ROOT/orchestration/$STAGE/exit_status.txt"
exit "$status"
