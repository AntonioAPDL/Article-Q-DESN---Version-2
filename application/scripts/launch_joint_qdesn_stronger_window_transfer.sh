#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_stronger_window_richer_screen_20261121}
CPU_LIST=${CPU_LIST:-}
[[ ${JOINT_SWTX_CONFIRM_STAGE:-} == transfer ]] || {
  echo "Refusing accidental launch. Set JOINT_SWTX_CONFIRM_STAGE=transfer after review." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST is required." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 25 )) || { echo "Use 1-25 physical CPU IDs." >&2; exit 2; }
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || {
  echo "CPU_LIST contains duplicates." >&2; exit 2;
}
declare -A physical=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID $cpu." >&2; exit 2; }
  topology="/sys/devices/system/cpu/cpu${cpu}/topology"
  key="$(<"$topology/physical_package_id"):$(<"$topology/core_id")"
  [[ -z ${physical[$key]:-} ]] || { echo "CPU $cpu shares physical core $key." >&2; exit 2; }
  physical[$key]=$cpu
done
free_gib=$(df -Pk /data | awk 'NR==2 {printf "%d", $4/1024/1024}')
available_gib=$(awk '/MemAvailable:/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 150 && available_gib >= 96 )) || {
  echo "Capacity blocked: /data=${free_gib} GiB, memory=${available_gib} GiB." >&2; exit 3;
}
plan="$ROOT/transfer_worker_plan.csv"
[[ -f $plan ]] || { echo "Missing plan $plan." >&2; exit 3; }
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/transfer_capacity_receipt.csv"
printf '%s,transfer,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" >> "$ROOT/transfer_capacity_receipt.csv"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
cpu_fifo="$ROOT/.transfer_cpu_pool_$$"; mkfifo "$cpu_fifo"; exec 9<>"$cpu_fifo"; rm -f "$cpu_fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done
for transfer_stage in 1 2 3; do
  mapfile -t ids < <("$R_BIN" -e '
    x <- read.csv(commandArgs(TRUE)[1L]); stage <- as.integer(commandArgs(TRUE)[2L])
    x <- x[as.integer(x$transfer_stage) == stage, , drop=FALSE]
    stopifnot(nrow(x) > 0L); cat(x$transfer_worker_id, sep="\n")
  ' "$plan" "$transfer_stage")
  pids=()
  for id in "${ids[@]}"; do
    IFS= read -r cpu <&9
    (
      set +e
      taskset -c "$cpu" nice -n 10 "$R_BIN" \
        "$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_transfer_worker.R" \
        --root="$ROOT" --worker-id="$id"
      rc=$?; printf '%s\n' "$cpu" >&9; exit "$rc"
    ) &
    pids+=("$!")
  done
  failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || exit 4
done
exec 9>&-
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_stronger_window_transfer.R" --root="$ROOT"
