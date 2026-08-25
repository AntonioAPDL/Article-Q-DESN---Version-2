#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/data/jaguir26/local/src/Article-Q-DESN---Version-2"
SESSION="joint_exqdesn_phase146_sigma_gamma_geometry_20260725"
OUT_DIR="application/cache/joint_qdesn_phase146_sigma_gamma_geometry_student_t_20260725"
LOG_PATH="application/logs/joint_qdesn_phase146_sigma_gamma_geometry_student_t_20260725.log"

cd "$REPO_ROOT"
mkdir -p "$(dirname "$LOG_PATH")"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session already exists: $SESSION" >&2
  exit 1
fi
if [ -f "$OUT_DIR/artifact_manifest.csv" ]; then
  echo "Refusing to overwrite completed artifact directory: $OUT_DIR" >&2
  exit 1
fi

tmux new-session -d -s "$SESSION" \
  "cd '$REPO_ROOT' && { \
     echo START_PHASE146 \$(date -Is); \
     Rscript application/scripts/156_run_joint_exqdesn_phase146_sigma_gamma_geometry.R \
       --output-dir '$OUT_DIR' \
       --n-chains 8 \
       --mcmc-n-iter 12000 \
       --mcmc-burn 3000 \
       --mcmc-thin 3 \
       --n-cores 24 \
       --vb-n-cores 6 \
       --dry-run false; \
     code=\$?; \
     echo EXIT_CODE=\$code END_PHASE146 \$(date -Is); \
     exit \$code; \
   } > '$LOG_PATH' 2>&1"

echo "Launched: $SESSION"
echo "Log: $REPO_ROOT/$LOG_PATH"
echo "Output: $REPO_ROOT/$OUT_DIR"
