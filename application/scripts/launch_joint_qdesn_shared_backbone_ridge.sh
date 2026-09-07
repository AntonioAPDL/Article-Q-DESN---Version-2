#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_shared_backbone_pilot_20260906}"
WORKERS="${JOINT_SHARED_WORKERS:-10}"
if [[ "$WORKERS" != "10" ]]; then
  echo "The frozen launch contract requires exactly 10 concurrent workers." >&2
  exit 2
fi
if [[ ! -f "$ROOT/ridge_worker_plan.csv" ]]; then
  echo "Missing ridge worker plan: $ROOT/ridge_worker_plan.csv" >&2
  exit 2
fi
mkdir -p "$ROOT/logs"
mapfile -t IDS < <(Rscript -e 'x<-read.csv(commandArgs(TRUE)[1]); cat(x$worker_id, sep="\n")' "$ROOT/ridge_worker_plan.csv")
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
printf '%s\n' "${IDS[@]}" | xargs -r -P "$WORKERS" -I '{}' bash -c '
  id="$1"; root="$2"
  done_path=$(printf "%s/workers/worker_%04d/DONE" "$root" "$id")
  failed_path=$(printf "%s/workers/worker_%04d/FAILED" "$root" "$id")
  if [[ -f "$done_path" || -f "$failed_path" ]]; then exit 0; fi
  nice -n 10 Rscript application/scripts/run_joint_qdesn_shared_backbone_ridge_worker.R \
    --root "$root" --worker-id "$id" >"$root/logs/worker_${id}.log" 2>&1
' _ '{}' "$ROOT"
Rscript application/scripts/check_joint_qdesn_shared_backbone_pilot.R --root "$ROOT"
