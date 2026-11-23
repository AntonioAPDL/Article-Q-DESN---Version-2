#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_persistent_regime_recalibration_v2_20261120}
WORKERS=${WORKERS:-15}
CPU_LIST=${CPU_LIST:-0,1,2,3,4,5,7,8,9,10,11,12,13,14,15}

if [[ ${JOINT_PR2_CONFIRM_LAUNCH:-0} != 1 ]]; then
  echo "Refusing an accidental launch. Set JOINT_PR2_CONFIRM_LAUNCH=1 after reviewing the v2 packet." >&2
  exit 2
fi
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
if (( WORKERS < 1 || WORKERS > 15 || ${#CPUS[@]} != WORKERS )); then
  echo "WORKERS and the number of distinct CPU_LIST entries must match and be at most 15." >&2
  exit 2
fi
if [[ $(printf '%s\n' "${CPUS[@]}" | sort -u | wc -l) -ne $WORKERS ]]; then
  echo "CPU_LIST contains duplicate logical CPUs." >&2
  exit 2
fi
free_gib=$(df -Pk /data | awk 'NR==2 {printf "%d", $4/1024/1024}')
if (( free_gib < 100 )); then
  echo "Capacity gate blocked: /data has only ${free_gib} GiB free." >&2
  exit 3
fi

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

run_stage() {
  local stage=$1 plan_name id_column plan_path
  case "$stage" in
    parity) plan_name=parity_worker_plan.csv; id_column=parity_worker_id ;;
    ridge) plan_name=ridge_worker_plan.csv; id_column=worker_id ;;
    seed_ridge) plan_name=seed_ridge_worker_plan.csv; id_column=seed_worker_id ;;
    rhs) plan_name=rhs_worker_plan.csv; id_column=rhs_worker_id ;;
    rhs_refine) plan_name=rhs_refine_worker_plan.csv; id_column=rhs_refine_worker_id ;;
    median_al) plan_name=median_al_worker_plan.csv; id_column=median_worker_id ;;
    tail_al) plan_name=tail_al_worker_plan.csv; id_column=tail_worker_id ;;
    *) echo "Unknown stage $stage" >&2; exit 4 ;;
  esac
  plan_path=$ROOT/$plan_name
  mapfile -t ids < <("$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1]); cat(x[[commandArgs(TRUE)[2]]], sep="\n")' "$plan_path" "$id_column")
  local pids=()
  for ((slot=0; slot<WORKERS; slot++)); do
    (
      for ((index=slot; index<${#ids[@]}; index+=WORKERS)); do
        taskset -c "${CPUS[$slot]}" nice -n 10 "$R_BIN" \
          "$REPO_ROOT/application/scripts/run_joint_qdesn_persistent_regime_worker_v2.R" \
          --root="$ROOT" --stage="$stage" --worker-id="${ids[$index]}"
      done
    ) &
    pids+=("$!")
  done
  local failed=0
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed == 0 )) || return 1
}

finalize_stage() {
  "$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_persistent_regime_stage_v2.R" \
    --root="$ROOT" --stage="$1"
}

if [[ ! -f $ROOT/parity_worker_plan.csv ]]; then
  "$R_BIN" "$REPO_ROOT/application/scripts/prepare_joint_qdesn_persistent_regime_recalibration_v2.R" --output-dir="$ROOT"
fi
for stage in parity ridge seed_ridge rhs rhs_refine median_al tail_al; do
  echo "[$(date -u +%FT%TZ)] starting $stage"
  run_stage "$stage"
  finalize_stage "$stage"
done
echo "[$(date -u +%FT%TZ)] v2 campaign stopped at the three-quantile AL transfer review gate: $ROOT"
