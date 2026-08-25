#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_qdesn_phase179_dgp_score_confirmation_freeze_20260819"
ORCH="$CACHE_ROOT/joint_qdesn_phase179_dgp_score_confirmation_20260819_orchestration"
SESSION="${JOINT_QDESN_PHASE179_SCORE_SESSION:-joint_qdesn_phase179_dgp_score_20260819}"
MAX_PARALLEL="${JOINT_QDESN_PHASE179_SCORE_MAX_PARALLEL:-48}"
CPU_LIST="${JOINT_QDESN_PHASE179_SCORE_CPU_LIST:-}"
VB_CORES="${JOINT_QDESN_PHASE179_SCORE_VB_CORES:-12}"
SCORE_CORES="${JOINT_QDESN_PHASE179_SCORE_FINALIZE_CORES:-12}"
SOURCE_ID="phase179_case_specific_dgp_score_confirmation_freeze"

if [[ -z "$CPU_LIST" ]]; then
  echo "JOINT_QDESN_PHASE179_SCORE_CPU_LIST must be an audited comma-separated CPU list." >&2
  exit 2
fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"

if [[ "${1:-}" != "--internal" ]]; then
  tmux has-session -t "$SESSION" 2>/dev/null && {
    echo "Session exists: $SESSION" >&2
    exit 2
  }
  tmux new-session -d -s "$SESSION" \
    "env JOINT_EXQDESN_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_QDESN_PHASE179_SCORE_SESSION=$(printf '%q' "$SESSION") \
      JOINT_QDESN_PHASE179_SCORE_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_QDESN_PHASE179_SCORE_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_QDESN_PHASE179_SCORE_VB_CORES=$(printf '%q' "$VB_CORES") \
      JOINT_QDESN_PHASE179_SCORE_FINALIZE_CORES=$(printf '%q' "$SCORE_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."
  exit 0
fi

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
printf '%s\n' "$(date --iso-8601=seconds)" >"$ORCH/launch_started_at.txt"
git -C "$ROOT" rev-parse HEAD >"$ORCH/launch_code_commit.txt"
if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript "$ROOT/application/scripts/264_prepare_joint_qdesn_phase179_dgp_score_confirmation.R" \
    --cache-root "$CACHE_ROOT" --vb-cores "$VB_CORES" \
    >"$ORCH/preparation.log" 2>&1
fi
mapfile -t WORKERS < <(joint_exqdesn_chain_plan_worker_ids "$FREEZE/chain_plan.csv")
for worker in "${WORKERS[@]}"; do
  joint_exqdesn_cpu_queue_acquire
  cpu="$QUEUE_CPU"
  (
    set +e
    taskset -c "$cpu" Rscript "$ROOT/application/scripts/251_run_joint_exqdesn_post_m0_chain.R" \
      --freeze-dir "$FREEZE" --source-id "$SOURCE_ID" --worker-id "$worker" \
      --failure-dir "$ORCH/failures" \
      >"$ORCH/logs/worker_$(printf '%04d' "$worker").log" 2>&1
    code=$?
    printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%04d' "$worker").exit"
    exit "$code"
  ) &
  joint_exqdesn_cpu_queue_register "$!" "$cpu"
done
joint_exqdesn_cpu_queue_wait_all
Rscript "$ROOT/application/scripts/265_check_joint_qdesn_phase179_dgp_score_confirmation.R" \
  --cache-root "$CACHE_ROOT" --score-cores "$SCORE_CORES" \
  >"$ORCH/final_health.log" 2>&1
printf '%s\n' "$(date --iso-8601=seconds)" >"$ORCH/launch_finished_at.txt"
