#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"

CACHE_ROOT="${JOINT_QDESN_PHASE181_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_qdesn_phase181_score_stability_extension_freeze_20260826"
ORCH="$CACHE_ROOT/joint_qdesn_phase181_score_stability_extension_20260826_orchestration"
SESSION="${JOINT_QDESN_PHASE181_SESSION:-joint_qdesn_phase181_score_stability_20260826}"
MAX_PARALLEL="${JOINT_QDESN_PHASE181_MAX_PARALLEL:-40}"
CPU_LIST="${JOINT_QDESN_PHASE181_CPU_LIST:-}"
VB_CORES="${JOINT_QDESN_PHASE181_VB_CORES:-8}"
SCORE_CORES="${JOINT_QDESN_PHASE181_SCORE_CORES:-8}"

if [[ -z "$CPU_LIST" ]]; then
  echo "JOINT_QDESN_PHASE181_CPU_LIST must be an audited comma-separated CPU list." >&2
  exit 2
fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"

if [[ "${1:-}" != "--internal" ]]; then
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session already exists: $SESSION" >&2
    exit 2
  fi
  tmux new-session -d -s "$SESSION" \
    "env JOINT_QDESN_PHASE181_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_QDESN_PHASE181_SESSION=$(printf '%q' "$SESSION") \
      JOINT_QDESN_PHASE181_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_QDESN_PHASE181_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_QDESN_PHASE181_VB_CORES=$(printf '%q' "$VB_CORES") \
      JOINT_QDESN_PHASE181_SCORE_CORES=$(printf '%q' "$SCORE_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."
  exit 0
fi

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
date --iso-8601=seconds >"$ORCH/launch_started_at.txt"
git -C "$ROOT" rev-parse HEAD >"$ORCH/launch_code_commit.txt"
git -C "$ROOT" status --porcelain >"$ORCH/launch_worktree_status.txt"
if [[ -s "$ORCH/launch_worktree_status.txt" ]]; then
  echo "Phase181 launch requires a clean worktree." >&2
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
  Rscript "$ROOT/application/scripts/279_prepare_joint_qdesn_phase181_score_stability_extension.R" \
    --cache-root "$CACHE_ROOT" --vb-cores "$VB_CORES" \
    >"$ORCH/preparation.log" 2>&1
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
      "$ROOT/application/scripts/280_run_joint_qdesn_phase181_score_stability_chain.R" \
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

Rscript "$ROOT/application/scripts/281_check_joint_qdesn_phase181_score_stability_extension.R" \
  --cache-root "$CACHE_ROOT" --write >"$ORCH/final_health.log" 2>&1
Rscript "$ROOT/application/scripts/282_finalize_joint_qdesn_phase181_score_stability_extension.R" \
  --cache-root "$CACHE_ROOT" --score-cores "$SCORE_CORES" \
  >"$ORCH/finalization.log" 2>&1
Rscript "$ROOT/application/scripts/283_stage_joint_qdesn_phase181_article_assets.R" \
  --cache-root "$CACHE_ROOT" >"$ORCH/article_staging.log" 2>&1
Rscript "$ROOT/application/tests/test_joint_qdesn_phase181_score_stability_extension.R" \
  >"$ORCH/test_phase181.log" 2>&1
Rscript "$ROOT/application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R" \
  >"$ORCH/test_phase180.log" 2>&1
Rscript "$ROOT/application/scripts/284_freeze_joint_qdesn_phase181_integration_handoff.R" \
  --cache-root "$CACHE_ROOT" >"$ORCH/handoff.log" 2>&1
