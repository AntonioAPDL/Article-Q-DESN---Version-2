#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/data/jaguir26/local/src/Article-Q-DESN---Version-2"
SESSION="joint_exqdesn_phase145_focus_long_student_t_20260724"
OUT_DIR="application/cache/joint_qdesn_phase145_gamma_sampler_focus_long_student_t_20260724"
LOG_PATH="application/logs/joint_qdesn_phase145_gamma_sampler_focus_long_student_t_20260724.log"

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
     echo START_PHASE145C \$(date -Is); \
     Rscript application/scripts/153_run_joint_exqdesn_phase145_gamma_sampler_root_cause_screen.R \
       --output-dir '$OUT_DIR' \
       --case-ids student_t_location_scale__joint_exqdesn_rhs_vb \
       --phase145-variant-ids phase145_logit_w4_vb_local,phase145_logit_w4_vb_refresh3_sigma_s \
       --n-chains 16 \
       --mcmc-n-iter 20000 \
       --mcmc-burn 5000 \
       --mcmc-thin 5 \
       --mcmc-seed-offset 14550 \
       --chain-seed-stride 100 \
       --sigma-upper-multiplier 50 \
       --distance-pass 5 \
       --chain-pass 5 \
       --n-cores 32 \
       --vb-n-cores 6 \
       --trace-write-stride 100 \
       --save-rdata false \
       --dry-run false; \
     code=\$?; \
     echo EXIT_CODE=\$code END_PHASE145C \$(date -Is); \
     exit \$code; \
   } > '$LOG_PATH' 2>&1"

echo "Launched $SESSION"
echo "Log: $REPO_ROOT/$LOG_PATH"
echo "Output: $REPO_ROOT/$OUT_DIR"
