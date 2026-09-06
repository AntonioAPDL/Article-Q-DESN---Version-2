#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_shared_backbone_pilot_20260906}"
export JOINT_SHARED_WORKERS=10
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

if [[ ! -f "$ROOT/launch_readiness.csv" ]]; then
  Rscript application/scripts/prepare_joint_qdesn_shared_backbone_pilot.R --output-dir "$ROOT"
fi

bash application/scripts/launch_joint_qdesn_shared_backbone_ridge.sh "$ROOT"
Rscript application/scripts/finalize_joint_qdesn_shared_backbone_ridge.R --root "$ROOT"
bash application/scripts/launch_joint_qdesn_shared_backbone_rhs.sh "$ROOT"
Rscript application/scripts/finalize_joint_qdesn_shared_backbone_rhs.R --root "$ROOT"
