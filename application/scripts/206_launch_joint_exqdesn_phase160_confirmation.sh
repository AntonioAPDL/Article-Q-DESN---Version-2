#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FREEZE="${PHASE160_FREEZE_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_freeze_20260805}"
OUTPUT="${PHASE160_OUTPUT_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805}"
ORCH="${PHASE160_ORCHESTRATION_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805_orchestration}"
WORKERS="${PHASE160_WORKERS:-16}"
mkdir -p "$ORCH" "$OUTPUT"

if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript --vanilla "$ROOT/application/scripts/202_prepare_joint_exqdesn_phase160_confirmation.R" \
    --freeze-dir "$FREEZE" --output-dir "$OUTPUT"
fi

seq 1 16 | xargs -P "$WORKERS" -I{} bash -c '
  export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
  worker="$2"
  log="$3/worker_$(printf "%03d" "$worker").log"
  exit_file="$3/worker_$(printf "%03d" "$worker").exit"
  if Rscript --vanilla "$0/application/scripts/203_run_joint_exqdesn_phase160_worker.R" \
    --freeze-dir "$1" --worker-id "$worker" >"$log" 2>&1; then
    echo 0 >"$exit_file"
  else
    code=$?; echo "$code" >"$exit_file"; exit "$code"
  fi
' "$ROOT" "$FREEZE" {} "$ORCH"

Rscript --vanilla "$ROOT/application/scripts/204_finalize_joint_exqdesn_phase160_confirmation.R" \
  --freeze-dir "$FREEZE" --output-dir "$OUTPUT" >"$ORCH/finalize.log" 2>&1
echo 0 >"$ORCH/phase160.exit"
