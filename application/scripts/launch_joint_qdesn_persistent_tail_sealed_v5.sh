#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 V5_ROOT" >&2
  exit 2
fi
ROOT=$1
CPU_LIST=${CPU_LIST:-}
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

[[ $(hostname -f) == jerez.be.ucsc.edu ]] || {
  echo "This V5 launch is authorized only on jerez.be.ucsc.edu." >&2; exit 2;
}
[[ -x $R_BIN ]] || { echo "Pinned R 4.6.0 is unavailable: $R_BIN" >&2; exit 2; }
"$R_BIN" --version 2>&1 | head -1 | grep -q 'version 4.6.0' || {
  echo "V5 requires pinned R 4.6.0." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST must name 15 reviewed physical-core CPU IDs." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} == 15 )) || { echo "V5 requires exactly 15 physical cores." >&2; exit 2; }
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq 15 ]] || {
  echo "CPU_LIST contains duplicates." >&2; exit 2;
}
declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID: $cpu" >&2; exit 2; }
  topo=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, -v cpu="$cpu" '$1==cpu && $4=="Y" {print $2 ":" $3}')
  [[ -n $topo ]] || { echo "Cannot inspect CPU $cpu." >&2; exit 2; }
  [[ -z ${PHYSICAL[$topo]:-} ]] || {
    echo "CPU $cpu shares physical core $topo with CPU ${PHYSICAL[$topo]}." >&2; exit 2;
  }
  PHYSICAL[$topo]=$cpu
done
[[ -f $ROOT/s1_worker_plan.csv && -f $ROOT/selection_freeze.csv ]] || {
  echo "The frozen V5 plan is absent." >&2; exit 2;
}
[[ -z $(git status --porcelain) ]] || { echo "The V5 execution worktree must be clean." >&2; exit 2; }
branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
[[ -n $branch && -n $upstream ]] || { echo "The V5 branch must track an upstream." >&2; exit 2; }
[[ $(git rev-list --left-right --count "$upstream...HEAD") == $'0\t0' ]] || {
  echo "The V5 branch is not synchronized with upstream." >&2; exit 2;
}
active_model_jobs=$(ps -u "$USER" -o pid=,comm=,args= | awk '
  $2 ~ /^(R|Rscript)$/ && tolower($0) ~ /(joint_qdesn|glofas|pricefm)/ {print}
')
[[ -z $active_model_jobs ]] || {
  echo "Another model R process is active on Jerez:" >&2
  printf '%s\n' "$active_model_jobs" >&2
  exit 2
}
"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_sealed_v5.R "$ROOT"
free_gib=$(df -BG --output=avail /data | tail -1 | tr -dc '0-9')
available_gib=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 80 )) || { echo "Jerez /data free space is below 80 GiB." >&2; exit 2; }
(( available_gib >= 128 )) || { echo "Jerez available memory is below 128 GiB." >&2; exit 2; }

lock="$ROOT/.v5_launch_lock"
mkdir "$lock" 2>/dev/null || { echo "V5 launch lock exists: $lock" >&2; exit 2; }
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
mkdir -p "$ROOT/orchestration/s1"
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head,branch,upstream\n' \
  > "$ROOT/s1_capacity_receipt.csv"
printf '%s,s1,"%s",15,%d,%d,%s,%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CPU_LIST" \
  "$free_gib" "$available_gib" "$(git rev-parse HEAD)" "$branch" "$upstream" \
  >> "$ROOT/s1_capacity_receipt.csv"

mapfile -t IDS < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1], check.names=FALSE); cat(x$s1_worker_id, sep="\n")' \
  "$ROOT/s1_worker_plan.csv")
[[ ${#IDS[@]} -eq 15 ]] || { echo "V5 worker plan does not contain 15 workers." >&2; exit 2; }
status=0
for i in "${!IDS[@]}"; do
  worker_id=${IDS[$i]}; cpu=${CPUS[$i]}
  log="$ROOT/orchestration/s1/worker_$(printf '%05d' "$worker_id").log"
  {
    if ! taskset -c "$cpu" nice -n 10 env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
      MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      "$R_BIN" application/scripts/run_joint_qdesn_persistent_tail_sealed_v5_worker.R \
      "$ROOT" "$worker_id" >"$log" 2>&1; then
      touch "$ROOT/orchestration/s1/WORKER_FAILURE"
    fi
  } &
done
wait || status=$?
[[ ! -f $ROOT/orchestration/s1/WORKER_FAILURE ]] || status=1
"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_sealed_v5.R "$ROOT" || status=1
printf '%s\n' "$status" > "$ROOT/orchestration/s1/exit_status.txt"
exit "$status"
