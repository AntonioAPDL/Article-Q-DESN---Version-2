#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"

CACHE_ROOT="${JOINT_QDESN_PHASE182_CACHE_ROOT:-$ROOT/application/cache}"
SOURCE_CACHE_ROOT="${JOINT_QDESN_PHASE182_SOURCE_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_qdesn_phase182_dense_grid_crossing_freeze_20260831"
ORCH="$CACHE_ROOT/joint_qdesn_phase182_dense_grid_crossing_20260831_orchestration"
SESSION="${JOINT_QDESN_PHASE182_SESSION:-joint_qdesn_phase182_dense_grid_crossing_20260831}"
MAX_PARALLEL="${JOINT_QDESN_PHASE182_MAX_PARALLEL:-20}"
CPU_LIST="${JOINT_QDESN_PHASE182_CPU_LIST:-}"
VB_CORES="${JOINT_QDESN_PHASE182_VB_CORES:-8}"
SCORE_CORES="${JOINT_QDESN_PHASE182_SCORE_CORES:-8}"

if [[ -z "$CPU_LIST" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    CPU_LIST="$(seq -s, 0 "$(( $(nproc) - 1 ))")"
  else
    echo "JOINT_QDESN_PHASE182_CPU_LIST must be set when nproc is unavailable." >&2
    exit 2
  fi
fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"

if [[ "${1:-}" != "--internal" ]]; then
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session already exists: $SESSION" >&2
    exit 2
  fi
  tmux new-session -d -s "$SESSION" \
    "env JOINT_QDESN_PHASE182_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_QDESN_PHASE182_SOURCE_CACHE_ROOT=$(printf '%q' "$SOURCE_CACHE_ROOT") \
      JOINT_QDESN_PHASE182_SESSION=$(printf '%q' "$SESSION") \
      JOINT_QDESN_PHASE182_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_QDESN_PHASE182_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_QDESN_PHASE182_VB_CORES=$(printf '%q' "$VB_CORES") \
      JOINT_QDESN_PHASE182_SCORE_CORES=$(printf '%q' "$SCORE_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."
  exit 0
fi

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
date --iso-8601=seconds >"$ORCH/launch_started_at.txt"
git -C "$ROOT" rev-parse HEAD >"$ORCH/launch_code_commit.txt"
git -C "$ROOT" status --porcelain >"$ORCH/launch_worktree_status.txt"
if [[ -s "$ORCH/launch_worktree_status.txt" ]]; then
  echo "Phase182 launch requires a clean worktree." >&2
  exit 2
fi

finish() {
  code=$?
  trap - EXIT
  date --iso-8601=seconds >"$ORCH/launch_finished_at.txt"
  printf '%s\n' "$code" >"$ORCH/EXIT_CODE"
  exit "$code"
}
trap finish EXIT

if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript "$ROOT/application/scripts/291_prepare_joint_qdesn_phase182_dense_grid_crossing.R" \
    --cache-root "$CACHE_ROOT" --source-cache-root "$SOURCE_CACHE_ROOT" \
    --vb-cores "$VB_CORES" >"$ORCH/preparation.log" 2>&1
fi

mapfile -t WORKERS < <(joint_exqdesn_chain_plan_worker_ids "$FREEZE/worker_plan.csv")
for worker in "${WORKERS[@]}"; do
  joint_exqdesn_cpu_queue_acquire
  cpu="$QUEUE_CPU"
  (
    set +e
    env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      taskset -c "$cpu" Rscript \
      "$ROOT/application/scripts/292_run_joint_qdesn_phase182_dense_grid_chain.R" \
      --freeze-dir "$FREEZE" --worker-id "$worker" \
      --failure-dir "$ORCH/failures" \
      >"$ORCH/logs/worker_$(printf '%04d' "$worker").log" 2>&1
    code=$?
    printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%04d' "$worker").exit"
    exit "$code"
  ) &
  joint_exqdesn_cpu_queue_register "$!" "$cpu"
done
joint_exqdesn_cpu_queue_wait_all

Rscript "$ROOT/application/scripts/293_check_joint_qdesn_phase182_dense_grid_crossing.R" \
  --cache-root "$CACHE_ROOT" --source-cache-root "$SOURCE_CACHE_ROOT" \
  --write >"$ORCH/final_health.log" 2>&1
Rscript "$ROOT/application/scripts/294_finalize_joint_qdesn_phase182_dense_grid_crossing.R" \
  --cache-root "$CACHE_ROOT" --source-cache-root "$SOURCE_CACHE_ROOT" \
  --score-cores "$SCORE_CORES" >"$ORCH/finalization.log" 2>&1
Rscript "$ROOT/application/tests/test_joint_qdesn_phase182_dense_grid_crossing.R" \
  >"$ORCH/test_phase182.log" 2>&1

date --iso-8601=seconds >"$ORCH/launch_finished_at.txt"
printf '%s\n' 0 >"$ORCH/EXIT_CODE"
