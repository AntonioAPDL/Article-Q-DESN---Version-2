#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_stronger_window_richer_screen_20261121}
STAGE=${STAGE:-}
CPU_LIST=${CPU_LIST:-}
[[ ${JOINT_SWCF_CONFIRM_STAGE:-} == "$STAGE" ]] || {
  echo "Set JOINT_SWCF_CONFIRM_STAGE to the requested STAGE." >&2; exit 2;
}
[[ $STAGE == sentinel || $STAGE == vb || $STAGE == mcmc ||
   $STAGE == oracle || $STAGE == score ]] || {
  echo "STAGE must be sentinel, vb, mcmc, oracle, or score." >&2; exit 2;
}
[[ -n $CPU_LIST ]] || { echo "CPU_LIST is required." >&2; exit 2; }
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= 1 && ${#CPUS[@]} <= 25 )) || { echo "Use 1-25 physical CPU IDs." >&2; exit 2; }
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
OUT="$ROOT/full_confirmation"
if [[ $STAGE == sentinel ]]; then
  PLAN="$OUT/mcmc_sentinel_plan.csv"; ID=sentinel_worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_confirmation_sentinel.R"
elif [[ $STAGE == vb ]]; then
  PLAN="$OUT/full_vb_plan.csv"; ID=vb_worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_full_vb.R"
elif [[ $STAGE == mcmc ]]; then
  PLAN="$OUT/mcmc_worker_plan.csv"; ID=worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_full_mcmc.R"
elif [[ $STAGE == oracle ]]; then
  PLAN="$OUT/score_packet/oracle_worker_plan.csv"; ID=oracle_worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_oracle.R"
else
  PLAN="$OUT/score_packet/score_worker_plan.csv"; ID=score_worker_id
  WORKER="$REPO_ROOT/application/scripts/run_joint_qdesn_stronger_window_score.R"
fi
[[ -f $PLAN ]] || { echo "Missing plan $PLAN." >&2; exit 3; }
printf 'recorded_at_utc,stage,cpu_list,physical_workers,data_free_gib,memory_available_gib,git_head\n' > "$OUT/${STAGE}_capacity_receipt.csv"
printf '%s,%s,"%s",%d,%d,%d,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STAGE" "$CPU_LIST" \
  "${#CPUS[@]}" "$free_gib" "$available_gib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" >> "$OUT/${STAGE}_capacity_receipt.csv"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
mapfile -t ids < <("$R_BIN" -e 'x<-read.csv(commandArgs(TRUE)[1]);cat(x[[commandArgs(TRUE)[2]]],sep="\n")' "$PLAN" "$ID")
fifo="$OUT/.${STAGE}_cpu_pool_$$"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"
for cpu in "${CPUS[@]}"; do printf '%s\n' "$cpu" >&9; done
pids=()
for id in "${ids[@]}"; do
  IFS= read -r cpu <&9
  ( set +e; taskset -c "$cpu" nice -n 10 "$R_BIN" "$WORKER" --root="$ROOT" --worker-id="$id"
    rc=$?; printf '%s\n' "$cpu" >&9; exit "$rc" ) &
  pids+=("$!")
done
failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
exec 9>&-
(( failed == 0 )) || exit 4
