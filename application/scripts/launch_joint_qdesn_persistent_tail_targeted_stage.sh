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

case "$STAGE" in
  r1a) PLAN=r1a_worker_plan.csv; ID=r1a_worker_id ;;
  r1b) PLAN=r1b_worker_plan.csv; ID=r1b_worker_id ;;
  r2) PLAN=r2_worker_plan.csv; ID=r2_worker_id ;;
  h1) PLAN=h1_worker_plan.csv; ID=h1_worker_id ;;
  h2) PLAN=h2_worker_plan.csv; ID=h2_worker_id ;;
  m1) PLAN=median_al_worker_plan.csv; ID=median_worker_id ;;
  *) echo "Unsupported stage: $STAGE" >&2; exit 2 ;;
esac

[[ $(hostname -f) == jerez.be.ucsc.edu ]] || {
  echo "This launch contract is authorized only on jerez.be.ucsc.edu." >&2; exit 2;
}
[[ -x $R_BIN ]] || { echo "Pinned R 4.6.0 is unavailable: $R_BIN" >&2; exit 2; }
"$R_BIN" --version 2>&1 | head -1 | grep -q 'version 4.6.0' || {
  echo "The targeted campaign requires pinned R 4.6.0." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST must explicitly name reviewed physical-core CPU IDs." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 30 )) || {
  echo "A stage requires 1-30 reviewed physical-core CPU IDs." >&2; exit 2;
}
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || {
  echo "CPU_LIST contains duplicate logical CPU IDs." >&2; exit 2;
}
declare -A PHYSICAL=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID: $cpu" >&2; exit 2; }
  topo=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, -v cpu="$cpu" '$1==cpu && $4=="Y" {print $2 ":" $3}')
  [[ -n $topo ]] || { echo "Cannot inspect online topology for CPU $cpu." >&2; exit 2; }
  [[ -z ${PHYSICAL[$topo]:-} ]] || {
    echo "CPU $cpu shares physical core $topo with CPU ${PHYSICAL[$topo]}." >&2; exit 2;
  }
  PHYSICAL[$topo]=$cpu
done

[[ -f $ROOT/$PLAN ]] || { echo "Stage plan is absent: $ROOT/$PLAN" >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || {
  echo "The Jerez execution worktree must be clean." >&2; exit 2;
}
branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
[[ -n $branch && -n $upstream ]] || { echo "The execution branch must track an upstream." >&2; exit 2; }
[[ $(git rev-list --left-right --count "$upstream...HEAD") == $'0\t0' ]] || {
  echo "The execution branch is not exactly synchronized with its upstream." >&2; exit 2;
}
active_model_jobs=$(pgrep -u "$USER" -af '[R]script.*(joint_qdesn|glofas|pricefm)' || true)
[[ -z $active_model_jobs ]] || {
  echo "Another model Rscript is active on Jerez; refusing a competing launch:" >&2
  printf '%s\n' "$active_model_jobs" >&2
  exit 2
}

"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
free_gib=$(df -BG --output=avail /data | tail -1 | tr -dc '0-9')
available_gib=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 80 )) || { echo "Jerez /data free space is below 80 GiB." >&2; exit 2; }
(( available_gib >= 128 )) || { echo "Jerez available memory is below 128 GiB." >&2; exit 2; }

lock="$ROOT/.${STAGE}_launch_lock"
mkdir "$lock" 2>/dev/null || { echo "Stage launch lock already exists: $lock" >&2; exit 2; }
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
mkdir -p "$ROOT/orchestration/$STAGE"
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head,branch,upstream\n' \
  > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s,%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" \
  "$CPU_LIST" "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git rev-parse HEAD)" "$branch" "$upstream" \
  >> "$ROOT/${STAGE}_capacity_receipt.csv"

mapfile -t IDS < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1], check.names=FALSE); cat(x[[commandArgs(TRUE)[2]]], sep="\n")' \
  "$ROOT/$PLAN" "$ID")
fifo="$ROOT/orchestration/$STAGE/cpu_fifo"
rm -f "$fifo"
mkfifo "$fifo"
exec 9<>"$fifo"
rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done

status=0
for worker_id in "${IDS[@]}"; do
  IFS= read -r cpu <&9
  {
    log="$ROOT/orchestration/$STAGE/worker_$(printf '%05d' "$worker_id").log"
    if ! taskset -c "$cpu" nice -n 10 "$R_BIN" \
      application/scripts/run_joint_qdesn_persistent_tail_targeted_worker.R \
      "$ROOT" "$STAGE" "$worker_id" >"$log" 2>&1; then
      printf 'worker %s failed on CPU %s\n' "$worker_id" "$cpu" >&2
      touch "$ROOT/orchestration/$STAGE/WORKER_FAILURE"
    fi
    printf '%s\n' "$cpu" >&9
  } &
done
wait || status=$?
exec 9>&-

if [[ -f $ROOT/orchestration/$STAGE/WORKER_FAILURE ]]; then status=1; fi
"$R_BIN" application/scripts/check_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT" || status=1
printf '%s\n' "$status" > "$ROOT/orchestration/$STAGE/exit_status.txt"
exit "$status"
