#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_stronger_window_richer_screen_20261121}
STAGE=${STAGE:-${1:-}}
CPU_LIST=${CPU_LIST:-}

case "$STAGE" in
  r1a|r1b|r2|r3|h1|h2|h3) ;;
  *) echo "STAGE must be one of r1a,r1b,r2,r3,h1,h2,h3." >&2; exit 2 ;;
esac
if [[ ${JOINT_SW_CONFIRM_STAGE:-} != "$STAGE" ]]; then
  echo "Refusing accidental launch. Set JOINT_SW_CONFIRM_STAGE=$STAGE after review." >&2
  exit 2
fi
if [[ -z $CPU_LIST ]]; then
  echo "CPU_LIST must explicitly name reviewed physical-core CPU IDs." >&2
  exit 2
fi
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
if (( ${#CPUS[@]} < 1 || ${#CPUS[@]} > 25 )); then
  echo "A stage requires 1-25 reviewed physical-core CPU IDs." >&2
  exit 2
fi
if [[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -ne ${#CPUS[@]} ]]; then
  echo "CPU_LIST contains duplicate logical CPU IDs." >&2
  exit 2
fi

declare -A physical=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || { echo "Invalid CPU ID: $cpu" >&2; exit 2; }
  topology="/sys/devices/system/cpu/cpu${cpu}/topology"
  [[ -r $topology/core_id && -r $topology/physical_package_id ]] || {
    echo "Cannot inspect topology for CPU $cpu." >&2; exit 2;
  }
  key="$(<"$topology/physical_package_id"):$(<"$topology/core_id")"
  [[ -z ${physical[$key]:-} ]] || {
    echo "CPU $cpu shares physical core $key with CPU ${physical[$key]}." >&2; exit 2;
  }
  physical[$key]=$cpu
done

free_gib=$(df -Pk /data | awk 'NR==2 {printf "%d", $4/1024/1024}')
available_gib=$(awk '/MemAvailable:/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if (( free_gib < 150 || available_gib < 96 )); then
  echo "Capacity blocked: /data=${free_gib} GiB free, memory=${available_gib} GiB available." >&2
  exit 3
fi

plan="$ROOT/${STAGE}_worker_plan.csv"
[[ -f $plan ]] || { echo "Missing reviewed plan: $plan" >&2; exit 3; }
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" >> "$ROOT/${STAGE}_capacity_receipt.csv"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

id_column="${STAGE}_worker_id"
mapfile -t ids < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1]); id <- commandArgs(TRUE)[2]; stopifnot(id %in% names(x)); cat(x[[id]], sep="\n")' "$plan" "$id_column")
if (( ${#ids[@]} == 0 )); then
  echo "Reviewed plan has no workers." >&2
  exit 3
fi

pids=()
for ((slot=0; slot<${#CPUS[@]}; slot++)); do
  (
    for ((index=slot; index<${#ids[@]}; index+=${#CPUS[@]})); do
      taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" \
        "$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_worker.R" \
        --root="$ROOT" --stage="$STAGE" --worker-id="${ids[$index]}"
    done
  ) &
  pids+=("$!")
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
(( failed == 0 )) || exit 4
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_stronger_window_stage.R" \
  --root="$ROOT" --stage="$STAGE"
