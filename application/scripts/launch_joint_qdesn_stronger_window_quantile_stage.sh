#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_stronger_window_richer_screen_20261121}
STAGE=${STAGE:-${1:-}}
CPU_LIST=${CPU_LIST:-}

case "$STAGE" in m1|q1) ;; *) echo "STAGE must be m1 or q1." >&2; exit 2 ;; esac
[[ ${JOINT_SWQ_CONFIRM_STAGE:-} == "$STAGE" ]] || {
  echo "Refusing accidental launch. Set JOINT_SWQ_CONFIRM_STAGE=$STAGE after review." >&2; exit 2;
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
if [[ $STAGE == m1 ]]; then
  plan="$ROOT/median_al_worker_plan.csv"; id_column=median_worker_id; stages=(all)
else
  plan="$ROOT/seven_al_worker_plan.csv"; id_column=q1_worker_id; stages=(1 2 3 4)
fi
[[ -f $plan ]] || { echo "Missing plan $plan." >&2; exit 3; }
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" >> "$ROOT/${STAGE}_capacity_receipt.csv"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Return each CPU to a shared token pool as soon as its worker completes. This
# avoids a long static-stride tail when candidate runtimes are heterogeneous.
cpu_fifo="$ROOT/.${STAGE}_cpu_pool_$$"
mkfifo "$cpu_fifo"
exec 9<>"$cpu_fifo"
rm -f "$cpu_fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done

for continuation_stage in "${stages[@]}"; do
  mapfile -t ids < <("$R_BIN" -e '
    x <- read.csv(commandArgs(TRUE)[1L]); id <- commandArgs(TRUE)[2L]
    stage <- commandArgs(TRUE)[3L]
    if (stage != "all") x <- x[as.integer(x$continuation_stage) == as.integer(stage), , drop=FALSE]
    stopifnot(id %in% names(x), nrow(x) > 0L); cat(x[[id]], sep="\n")
  ' "$plan" "$id_column" "$continuation_stage")
  pids=()
  for id in "${ids[@]}"; do
    IFS= read -r cpu <&9
    (
      set +e
      taskset -c "$cpu" nice -n 10 "$R_BIN" \
        "$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_quantile_worker.R" \
        --root="$ROOT" --stage="$STAGE" --worker-id="$id"
      rc=$?
      printf '%s\n' "$cpu" >&9
      exit "$rc"
    ) &
    pids+=("$!")
  done
  failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || exit 4
done
exec 9>&-
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_stronger_window_quantile_stage.R" \
  --root="$ROOT" --stage="$STAGE"
