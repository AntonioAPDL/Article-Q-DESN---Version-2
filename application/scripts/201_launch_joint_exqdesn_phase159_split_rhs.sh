#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FREEZE="${PHASE159_FREEZE_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804}"
OUTPUT="${PHASE159_OUTPUT_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804}"
ORCH="${PHASE159_ORCHESTRATION_DIR:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804_orchestration}"
WORKERS="${PHASE159_WORKERS:-24}"
mkdir -p "$ORCH" "$OUTPUT"

if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript --vanilla "$ROOT/application/scripts/197_prepare_joint_exqdesn_phase159_split_rhs.R" \
    --freeze-dir "$FREEZE" --output-dir "$OUTPUT"
fi

seq 1 96 | xargs -P "$WORKERS" -I{} bash -c '
  export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
  Rscript --vanilla "$0/application/scripts/198_run_joint_exqdesn_phase159_worker.R" \
    --freeze-dir "$1" --worker-id "$2" >"$3/worker_$(printf "%03d" "$2").log" 2>&1
' "$ROOT" "$FREEZE" {} "$ORCH"

Rscript --vanilla "$ROOT/application/scripts/199_finalize_joint_exqdesn_phase159_split_rhs.R" \
  --freeze-dir "$FREEZE" --output-dir "$OUTPUT" >"$ORCH/finalize.log" 2>&1
echo 0 >"$ORCH/phase159.exit"
