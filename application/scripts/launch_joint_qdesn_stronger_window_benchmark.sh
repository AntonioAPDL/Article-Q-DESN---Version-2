#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_stronger_window_richer_screen_20261121}
CPU_LIST=${CPU_LIST:-0,1,2,3,4,5}

if [[ ${JOINT_SW_CONFIRM_BENCHMARK:-0} != 1 ]]; then
  echo "Refusing accidental launch. Set JOINT_SW_CONFIRM_BENCHMARK=1 after preflight." >&2
  exit 2
fi
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
if (( ${#CPUS[@]} < 1 || ${#CPUS[@]} > 6 )); then
  echo "Benchmark requires one to six distinct physical-core CPU IDs." >&2
  exit 2
fi
if [[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -ne ${#CPUS[@]} ]]; then
  echo "CPU_LIST contains duplicate IDs." >&2
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

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export BLIS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

if [[ ! -f $ROOT/benchmark_worker_plan.csv ]]; then
  "$R_BIN" "$REPO_ROOT/application/scripts/prepare_joint_qdesn_stronger_window_campaign.R" --output-dir="$ROOT"
fi
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$ROOT/benchmark_capacity_receipt.csv"
printf '%s,benchmark,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" >> "$ROOT/benchmark_capacity_receipt.csv"
mapfile -t ids < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1]); cat(x$benchmark_worker_id, sep="\n")' "$ROOT/benchmark_worker_plan.csv")
pids=()
for ((slot=0; slot<${#CPUS[@]}; slot++)); do
  (
    for ((index=slot; index<${#ids[@]}; index+=${#CPUS[@]})); do
      taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" \
        "$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_worker.R" \
        --root="$ROOT" --stage=benchmark --worker-id="${ids[$index]}"
    done
  ) &
  pids+=("$!")
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
(( failed == 0 )) || exit 4
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_stronger_window_stage.R" \
  --root="$ROOT" --stage=benchmark
