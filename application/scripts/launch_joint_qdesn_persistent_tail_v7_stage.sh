#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then echo "Usage: $0 ROOT {vb|mcmc|score}" >&2; exit 2; fi
ROOT=$1; STAGE=$2
CPU_LIST=${CPU_LIST:-}; R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
REPO_ROOT=$(git rev-parse --show-toplevel); cd "$REPO_ROOT"
case "$STAGE" in
  vb) PLAN=full_confirmation/vb_worker_plan.csv; ID=vb_worker_id; REQUIRED=launch_readiness.csv; TOKEN=V7_PREPARED_VB_READY_NOT_LAUNCHED ;;
  mcmc) PLAN=full_confirmation/mcmc_worker_plan.csv; ID=worker_id; REQUIRED=full_confirmation/mcmc_readiness.csv; TOKEN=V7_VB_COMPLETE_MCMC_READY_NOT_LAUNCHED ;;
  score) PLAN=full_confirmation/score_packet/score_worker_plan.csv; ID=score_worker_id; REQUIRED=full_confirmation/score_packet/score_launch_readiness.csv; TOKEN=V7_MCMC_COMPLETE_SCORE_READY_NOT_LAUNCHED ;;
  *) echo "Unknown V7 stage: $STAGE" >&2; exit 2 ;;
esac
[[ $(hostname -f) == jerez.be.ucsc.edu ]] || { echo "V7 production is Jerez-only." >&2; exit 2; }
[[ -x $R_BIN ]] && "$R_BIN" --version 2>&1 | head -1 | grep -q 'version 4.6.0' || {
  echo "Pinned R 4.6.0 is required." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST is required." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 15 )) || { echo "Use 1-15 physical CPU IDs." >&2; exit 2; }
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || {
  echo "CPU_LIST contains duplicates." >&2; exit 2;
}
declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID: $cpu" >&2; exit 2; }
  topo=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, -v cpu="$cpu" '$1==cpu && $4=="Y" {print $2 ":" $3}')
  [[ -n $topo && -z ${PHYSICAL[$topo]:-} ]] || { echo "CPU topology conflict: $cpu" >&2; exit 2; }
  PHYSICAL[$topo]=$cpu
done
[[ -z $(git status --porcelain) ]] || { echo "V7 worktree must be clean." >&2; exit 2; }
branch=$(git branch --show-current); upstream=$(git rev-parse --abbrev-ref '@{upstream}')
[[ $branch == work/joint-qdesn-persistent-tail-v7-full-confirmation-20261126 ]] || {
  echo "Unexpected execution branch: $branch" >&2; exit 2;
}
[[ $(git rev-list --left-right --count "$upstream...HEAD") == $'0\t0' ]] || {
  echo "V7 branch is not synchronized." >&2; exit 2;
}
[[ -f $ROOT/$PLAN && -f $ROOT/$REQUIRED ]] && grep -q "$TOKEN" "$ROOT/$REQUIRED" || {
  echo "V7 stage is not authorized by its frozen predecessor." >&2; exit 2;
}
active=$(ps -u "$USER" -o pid=,comm=,args= | awk '$2 ~ /^(R|Rscript)$/ && tolower($0) ~ /(joint_qdesn|glofas|pricefm)/ {print}')
[[ -z $active ]] || { echo "Another scientific R job is active:" >&2; printf '%s\n' "$active" >&2; exit 2; }
free_gib=$(df -BG --output=avail /data | tail -1 | tr -dc '0-9')
memory_gib=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 80 && memory_gib >= 128 )) || { echo "V7 storage/memory preflight failed." >&2; exit 2; }
mkdir -p "$ROOT/orchestration/$STAGE"
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" "${#CPUS[@]}" "$free_gib" "$memory_gib" "$(git rev-parse HEAD)" >> "$ROOT/${STAGE}_capacity_receipt.csv"
mapfile -t IDS < <("$R_BIN" -e 'x<-read.csv(commandArgs(TRUE)[1],check.names=FALSE);cat(x[[commandArgs(TRUE)[2]]],sep="\n")' "$ROOT/$PLAN" "$ID")
fifo="$ROOT/orchestration/$STAGE/cpu_fifo"; rm -f "$fifo"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done
for worker_id in "${IDS[@]}"; do
  IFS= read -r cpu <&9
  { log="$ROOT/orchestration/$STAGE/worker_$(printf '%04d' "$worker_id").log"
    taskset -c "$cpu" nice -n 10 env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      "$R_BIN" application/scripts/run_joint_qdesn_persistent_tail_v7_worker.R \
      "$ROOT" "$STAGE" "$worker_id" >"$log" 2>&1 || touch "$ROOT/orchestration/$STAGE/WORKER_FAILURE"
    printf '%s\n' "$cpu" >&9
  } &
done
wait; exec 9>&-
[[ ! -f $ROOT/orchestration/$STAGE/WORKER_FAILURE ]] || exit 1
