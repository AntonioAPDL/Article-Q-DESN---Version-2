#!/usr/bin/env bash
set -euo pipefail

if [[ ${JOINT_PR_ALLOW_SUPERSEDED_V1:-0} != 1 ]]; then
  echo "This v1 launcher is superseded by launch_joint_qdesn_persistent_regime_recalibration_v2.sh." >&2
  exit 2
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
R_BIN=${R_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
ROOT=${ROOT:-$REPO_ROOT/application/cache/joint_qdesn_persistent_regime_recalibration_20261120}
WORKERS=${WORKERS:-15}

if [[ ${JOINT_PR_CONFIRM_LAUNCH:-0} != 1 ]]; then
  echo "Refusing an accidental expensive launch. Set JOINT_PR_CONFIRM_LAUNCH=1 after reviewing the frozen packet." >&2
  exit 2
fi
if (( WORKERS < 1 || WORKERS > 15 )); then
  echo "WORKERS must be between 1 and 15." >&2
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
  local stage=$1 id_column=$2 plan=$ROOT/${stage}_worker_plan.csv
  "$R_BIN" -e 'x <- read.csv(commandArgs(TRUE)[1]); id <- commandArgs(TRUE)[2]; cat(x[[id]], sep="\n")' "$plan" "$id_column" |
    xargs -r -P"$WORKERS" -I{} nice -n 10 "$R_BIN" \
      "$REPO_ROOT/application/scripts/run_joint_qdesn_persistent_regime_worker.R" \
      --root="$ROOT" --stage="$stage" --worker-id={}
}

if [[ ! -f $ROOT/ridge_worker_plan.csv ]]; then
  "$R_BIN" "$REPO_ROOT/application/scripts/prepare_joint_qdesn_persistent_regime_recalibration.R" --output-dir="$ROOT"
fi
run_stage ridge worker_id
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_persistent_regime_stage.R" --root="$ROOT" --stage=ridge
run_stage rhs rhs_worker_id
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_persistent_regime_stage.R" --root="$ROOT" --stage=rhs
run_stage median_al median_worker_id
"$R_BIN" "$REPO_ROOT/application/scripts/finalize_joint_qdesn_persistent_regime_stage.R" --root="$ROOT" --stage=median_al

echo "Targeted campaign stopped at the frozen median-AL review gate: $ROOT"
