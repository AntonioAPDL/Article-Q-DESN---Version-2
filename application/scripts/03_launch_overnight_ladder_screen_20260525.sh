#!/usr/bin/env bash
set -euo pipefail

# Launch a sharded reservoir-screening-only campaign. This script does not run
# VB/MCMC application fits and does not promote manuscript outputs.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"

RUN_PREFIX="${RUN_PREFIX:-reservoir_overnight_ladder_full_20260525}"
N_SHARDS="${N_SHARDS:-48}"
CONFIG="${CONFIG:-application/config/glofas_latent_path_al_vb_dec25_d1n300_focused_screen.yaml}"
GRID="${GRID:-application/config/reservoir_candidate_grid_latent_path_overnight_ladder_20260525.csv}"
SEEDS="${SEEDS:-20260512}"
DIAGNOSTIC_TARGET="${DIAGNOSTIC_TARGET:-both}"

if [[ ! -f "$GRID" ]]; then
  echo "Missing candidate grid: $GRID" >&2
  exit 1
fi

mkdir -p application/logs

N_ROWS="$(awk 'END {print NR - 1}' "$GRID")"
if [[ "$N_ROWS" -le 0 ]]; then
  echo "Candidate grid has no rows: $GRID" >&2
  exit 1
fi

echo "Launching $RUN_PREFIX with $N_ROWS candidates across $N_SHARDS shards"
echo "Config: $CONFIG"
echo "Grid:   $GRID"
echo "Seeds:  $SEEDS"
echo "Target: $DIAGNOSTIC_TARGET"

pids=()
failed=0
for shard in $(seq 1 "$N_SHARDS"); do
  start=$(( (shard - 1) * N_ROWS / N_SHARDS + 1 ))
  end=$(( shard * N_ROWS / N_SHARDS ))
  if [[ "$start" -gt "$end" ]]; then
    continue
  fi
  shard_id="$(printf "%02d" "$shard")"
  run_id="${RUN_PREFIX}_s${shard_id}"
  log_path="application/logs/${run_id}.log"
  echo "[$(date)] shard $shard_id: rows $start-$end -> $run_id"
  (
    Rscript application/scripts/03_screen_reservoir_candidate_grid.R \
      --config "$CONFIG" \
      --candidate_grid "$GRID" \
      --run_id "$run_id" \
      --seeds "$SEEDS" \
      --diagnostic_target "$DIAGNOSTIC_TARGET" \
      --cheap_validation false \
      --start_index "$start" \
      --end_index "$end"
  ) >"$log_path" 2>&1 &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "At least one shard failed. Inspect application/logs/${RUN_PREFIX}_s*.log" >&2
  exit 1
fi

echo "[$(date)] all shards finished; collecting"
collect_dir="$(Rscript application/scripts/03_collect_reservoir_screening_shards.R \
  --run_id_prefix "$RUN_PREFIX" \
  --require_completed true | tail -n 1)"

echo "Collected: $collect_dir"
echo "[$(date)] writing pilot triage"
Rscript application/scripts/03_rank_reservoir_screening_for_pilots.R \
  --screening_dir "$collect_dir"

echo "[$(date)] done"
