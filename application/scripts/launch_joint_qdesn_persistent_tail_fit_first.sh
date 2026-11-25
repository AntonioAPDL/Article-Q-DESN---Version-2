#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 ROOT" >&2
  exit 2
fi
ROOT=$1
CPU_LIST=${CPU_LIST:-}
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

[[ $(hostname -f) == jerez.be.ucsc.edu ]] || {
  echo "This launch contract is authorized only on jerez.be.ucsc.edu." >&2; exit 2;
}
[[ -x $R_BIN ]] || { echo "Pinned R 4.6.0 is unavailable: $R_BIN" >&2; exit 2; }
"$R_BIN" --version 2>&1 | head -1 | grep -q 'version 4.6.0' || {
  echo "The fit-first campaign requires pinned R 4.6.0." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST must name reviewed physical-core CPU IDs." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 30 )) || {
  echo "The campaign requires 1-30 reviewed physical-core CPU IDs." >&2; exit 2;
}
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || {
  echo "CPU_LIST contains duplicate logical CPU IDs." >&2; exit 2;
}
declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID: $cpu" >&2; exit 2; }
  topo=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, -v cpu="$cpu" \
    '$1==cpu && $4=="Y" {print $2 ":" $3}')
  [[ -n $topo ]] || { echo "Cannot inspect online topology for CPU $cpu." >&2; exit 2; }
  [[ -z ${PHYSICAL[$topo]:-} ]] || {
    echo "CPU $cpu shares physical core $topo with CPU ${PHYSICAL[$topo]}." >&2; exit 2;
  }
  PHYSICAL[$topo]=$cpu
done

[[ -f $ROOT/worker_plan.csv ]] || { echo "Worker plan is absent." >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || { echo "The execution worktree must be clean." >&2; exit 2; }
branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
[[ -n $branch && -n $upstream ]] || { echo "The execution branch must track an upstream." >&2; exit 2; }
[[ $(git rev-list --left-right --count "$upstream...HEAD") == $'0\t0' ]] || {
  echo "The execution branch is not synchronized with its upstream." >&2; exit 2;
}
active_model_jobs=$(ps -u "$USER" -o pid=,comm=,args= | awk '
  $2 ~ /^(R|Rscript)$/ && tolower($0) ~ /(joint_qdesn|glofas|pricefm)/ {print}
')
[[ -z $active_model_jobs ]] || {
  echo "Another model Rscript is active on Jerez:" >&2
  printf '%s\n' "$active_model_jobs" >&2
  exit 2
}

"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_fit_first.R "$ROOT"
free_gib=$(df -BG --output=avail /data | tail -1 | tr -dc '0-9')
available_gib=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 80 )) || { echo "Jerez /data free space is below 80 GiB." >&2; exit 2; }
(( available_gib >= 128 )) || { echo "Jerez available memory is below 128 GiB." >&2; exit 2; }

lock="$ROOT/.launch_lock"
mkdir "$lock" 2>/dev/null || { echo "Launch lock already exists: $lock" >&2; exit 2; }
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
mkdir -p "$ROOT/orchestration"
printf 'recorded_at_utc,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head,branch,upstream\n' \
  > "$ROOT/capacity_receipt.csv"
printf '%s,"%s",%d,%d,%d,%s,%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$CPU_LIST" "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git rev-parse HEAD)" \
  "$branch" "$upstream" >> "$ROOT/capacity_receipt.csv"

mapfile -t IDS < <("$R_BIN" -e \
  'x <- read.csv(commandArgs(TRUE)[1], check.names=FALSE); cat(x$worker_id, sep="\n")' \
  "$ROOT/worker_plan.csv")
fifo="$ROOT/orchestration/cpu_fifo"
rm -f "$fifo"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done

status=0
for worker_id in "${IDS[@]}"; do
  IFS= read -r cpu <&9
  {
    log="$ROOT/orchestration/worker_$(printf '%05d' "$worker_id").log"
    if ! taskset -c "$cpu" nice -n 10 env \
      OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1 \
      VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      "$R_BIN" application/scripts/run_joint_qdesn_persistent_tail_fit_first_worker.R \
      "$ROOT" "$worker_id" >"$log" 2>&1; then
      printf 'worker %s failed on CPU %s\n' "$worker_id" "$cpu" >&2
      touch "$ROOT/orchestration/WORKER_FAILURE"
    fi
    printf '%s\n' "$cpu" >&9
  } &
done
wait || status=$?
exec 9>&-
if [[ -f $ROOT/orchestration/WORKER_FAILURE ]]; then status=1; fi
"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_fit_first.R "$ROOT" || status=1
printf '%s\n' "$status" > "$ROOT/orchestration/exit_status.txt"
exit "$status"
