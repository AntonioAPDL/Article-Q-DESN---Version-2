#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_superfinal_predictive_stability_20261122}
SOURCE_ROOT=${SOURCE_ROOT:?SOURCE_ROOT is required}
STAGE=${STAGE:?STAGE is required}
CPU_LIST=${CPU_LIST:?CPU_LIST is required}
[[ ${JOINT_SUPERFINAL_STAGE:-} == "$STAGE" ]] || { echo "Stage token mismatch." >&2; exit 2; }
[[ $STAGE == mcmc || $STAGE == score ]] || { echo "STAGE must be mcmc or score." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 15 )) || { echo "Use 1-15 physical CPUs." >&2; exit 2; }
[[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -eq ${#CPUS[@]} ]] || exit 2
declare -A physical=()
for cpu in "${CPUS[@]}"; do
  [[ $cpu =~ ^[0-9]+$ ]] || exit 2
  topology="/sys/devices/system/cpu/cpu${cpu}/topology"
  key="$(<"$topology/physical_package_id"):$(<"$topology/core_id")"
  [[ -z ${physical[$key]:-} ]] || { echo "CPU $cpu shares physical core $key." >&2; exit 2; }
  physical[$key]=$cpu
done
free_gib=$(df -Pk /data | awk 'NR==2 {printf "%d", $4/1024/1024}')
available_gib=$(awk '/MemAvailable:/ {printf "%d", $2/1024/1024}' /proc/meminfo)
(( free_gib >= 150 && available_gib >= 96 )) || exit 3
if [[ $STAGE == mcmc ]]; then
  PLAN="$ROOT/full_confirmation/mcmc_worker_plan.csv"; ID=worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_superfinal_mcmc.R"
else
  PLAN="$ROOT/target_registry.csv"; ID=target_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_superfinal_score.R"
fi
[[ -f $PLAN ]] || { echo "Missing plan $PLAN." >&2; exit 3; }
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head,source_root\n' > "$ROOT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$SOURCE_ROOT" >> "$ROOT/${STAGE}_capacity_receipt.csv"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
mapfile -t ids < <("$R_BIN" -e 'x<-read.csv(commandArgs(TRUE)[1]);cat(x[[commandArgs(TRUE)[2]]],sep="\n")' "$PLAN" "$ID")
fifo="$ROOT/.${STAGE}_cpu_pool_$$"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done
pids=()
for id in "${ids[@]}"; do
  IFS= read -r cpu <&9
  if [[ $STAGE == mcmc ]]; then
    ( set +e; taskset -c "$cpu" nice -n 10 "$R_BIN" "$WORKER" --root="$ROOT" --worker-id="$id"
      rc=$?; printf '%s\n' "$cpu" >&9; exit "$rc" ) &
  else
    ( set +e; taskset -c "$cpu" nice -n 10 "$R_BIN" "$WORKER" --source-root="$SOURCE_ROOT" --root="$ROOT" --target-id="$id"
      rc=$?; printf '%s\n' "$cpu" >&9; exit "$rc" ) &
  fi
  pids+=("$!")
done
failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
exec 9>&-
printf '%d\n' "$failed" > "$ROOT/${STAGE}_pipeline.exit"
(( failed == 0 )) || exit 4
