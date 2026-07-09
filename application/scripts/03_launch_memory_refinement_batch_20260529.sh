#!/usr/bin/env bash
set -euo pipefail

# Launch the prepared 2026-05-29 memory-refinement application batch. This
# script intentionally does not run during preparation; execute it only after
# explicit confirmation. Each run is pinned to the core recorded in the
# manifest and BLAS/OpenMP thread counts are forced to one.

MANIFEST="${1:-application/config/glofas_engine73c_memory_refine16_20260529_launch_manifest.csv}"
SESSION="${SESSION:-glofas_engine73c_memory_refine16_20260529}"
LOG_DIR="${LOG_DIR:-application/logs/${SESSION}}"

cd "$(dirname "$0")/../.."

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
cp "$MANIFEST" "$LOG_DIR/launch_manifest.csv"

while IFS=, read -r _ _ _ _ _ _ _ engine_path _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _; do
  engine_path="${engine_path%\"}"
  engine_path="${engine_path#\"}"
  if [[ "$engine_path" != "engine_path" && ! -f "${engine_path}/src/exdqlm.so" ]]; then
    echo "Missing compiled local engine shared object: ${engine_path}/src/exdqlm.so" >&2
    exit 1
  fi
done < "$MANIFEST"

tmux new-session -d -s "$SESSION" -n launcher "bash"

Rscript -e 'm <- read.csv(commandArgs(TRUE)[1], stringsAsFactors = FALSE, check.names = FALSE); write.table(m, file = stdout(), sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE, na = "")' "$MANIFEST" |
while IFS=$'\t' read -r batch_id run_index relaunch_group source_config target_config source_model_grid target_model_grid engine_path engine_branch engine_commit run_id core role D n m alpha rho pi_w pi_in win_scale_global win_scale_bias rhs_tau0 rhs_alpha_tau0 seed launch_status; do
  window_name="$(printf 'mr%02d' "$run_index")"
  log_path="${LOG_DIR}/${run_id}.log"
  cmd=$(
    printf '%q ' bash -lc "cd '$PWD' && \
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 && \
echo START \$(date -Is) batch_id='$batch_id' group='$relaunch_group' role='$role' run_id='$run_id' config='$target_config' core='$core' engine_commit='$engine_commit' && \
taskset -c '$core' Rscript application/scripts/run_all.R --config '$target_config' --run_id '$run_id' --preflight true --confirm_final_launch true && \
echo DONE \$(date -Is) batch_id='$batch_id' run_id='$run_id'"
  )
  if [[ "$run_index" == "1" ]]; then
    tmux rename-window -t "${SESSION}:0" "$window_name"
    tmux send-keys -t "${SESSION}:${window_name}" "$cmd > '$log_path' 2>&1" C-m
  else
    tmux new-window -t "$SESSION" -n "$window_name" "$cmd > '$log_path' 2>&1"
  fi
done

echo "Launched ${SESSION} from ${MANIFEST}"
