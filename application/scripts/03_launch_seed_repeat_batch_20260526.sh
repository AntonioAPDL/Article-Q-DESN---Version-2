#!/usr/bin/env bash
set -euo pipefail

# Launch a prepared seed-repeat application batch. Each run is pinned to the
# core recorded in the manifest and all BLAS/OpenMP thread counts are set to 1.

MANIFEST="${1:-application/config/glofas_seedrepeat16_20260526_seed20260526_launch_manifest.csv}"
SESSION="${SESSION:-glofas_seedrepeat16_parallel_20260526}"
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

tmux new-session -d -s "$SESSION" -n launcher "bash"

Rscript -e 'm <- read.csv(commandArgs(TRUE)[1], stringsAsFactors = FALSE, check.names = FALSE); write.table(m, file = stdout(), sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE, na = "")' "$MANIFEST" |
while IFS=$'\t' read -r batch_id run_index source_config seed_config source_model_grid seed_model_grid source_seed repeat_seed run_id core; do
  window_name="$(printf 's%02d' "$run_index")"
  log_path="${LOG_DIR}/${run_id}.log"
  cmd=$(
    printf '%q ' bash -lc "cd '$PWD' && \
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 && \
echo START \$(date -Is) batch_id='$batch_id' run_id='$run_id' config='$seed_config' core='$core' repeat_seed='$repeat_seed' && \
taskset -c '$core' Rscript application/scripts/run_all.R --config '$seed_config' --run_id '$run_id' --preflight true --confirm_final_launch true && \
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
