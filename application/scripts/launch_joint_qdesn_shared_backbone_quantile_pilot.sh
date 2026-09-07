#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_shared_backbone_quantile_pilot_20260906}"
WORKERS="${JOINT_SHARED_QUANTILE_WORKERS:-10}"
NICE_LEVEL="${JOINT_SHARED_QUANTILE_NICE:-10}"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

if [[ "$WORKERS" -lt 1 || "$WORKERS" -gt 10 ]]; then
  echo "JOINT_SHARED_QUANTILE_WORKERS must be between 1 and 10." >&2
  exit 2
fi

if [[ ! -f "$ROOT/launch_readiness.csv" ]]; then
  Rscript application/scripts/prepare_joint_qdesn_shared_backbone_quantile_pilot.R \
    --output-dir "$ROOT"
fi

for STAGE in 1 2 3 4 5 6 7 8; do
  mapfile -t JOB_IDS < <(
    Rscript -e '
      args <- commandArgs(TRUE)
      plan <- read.csv(args[[1L]], check.names = FALSE)
      ids <- plan$job_id[plan$stage_order == as.integer(args[[2L]])]
      cat(ids, sep = "\n")
    ' "$ROOT/worker_plan.csv" "$STAGE"
  )
  if [[ "${#JOB_IDS[@]}" -eq 0 ]]; then
    echo "No jobs found for stage $STAGE." >&2
    exit 3
  fi
  printf '%s\n' "${JOB_IDS[@]}" | xargs -P "$WORKERS" -I{} \
    nice -n "$NICE_LEVEL" Rscript \
      application/scripts/run_joint_qdesn_shared_backbone_quantile_worker.R \
      --root "$ROOT" --job-id "{}"
  Rscript application/scripts/check_joint_qdesn_shared_backbone_quantile_pilot.R --root "$ROOT"
done

Rscript application/scripts/finalize_joint_qdesn_shared_backbone_quantile_pilot.R --root "$ROOT"
