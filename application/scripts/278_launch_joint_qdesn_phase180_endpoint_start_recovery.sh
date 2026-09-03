#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"

CACHE_ROOT="${JOINT_QDESN_PHASE180_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
RECOVERY_FREEZE="$CACHE_ROOT/joint_qdesn_phase180_balanced_dgp_score_recovery_freeze_20260825"
ORCH="$CACHE_ROOT/joint_qdesn_phase180_balanced_dgp_score_recovery_20260825_orchestration"
SESSION="${JOINT_QDESN_PHASE180_RECOVERY_SESSION:-joint_qdesn_phase180_endpoint_recovery_20260825}"
MAX_PARALLEL="${JOINT_QDESN_PHASE180_RECOVERY_MAX_PARALLEL:-9}"
CPU_LIST="${JOINT_QDESN_PHASE180_RECOVERY_CPU_LIST:-}"
SCORE_CORES="${JOINT_QDESN_PHASE180_SCORE_CORES:-8}"

if [[ -z "$CPU_LIST" ]]; then
  echo "JOINT_QDESN_PHASE180_RECOVERY_CPU_LIST must be an audited CPU list." >&2
  exit 2
fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"

if [[ "${1:-}" != "--internal" ]]; then
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session already exists: $SESSION" >&2
    exit 2
  fi
  tmux new-session -d -s "$SESSION" \
    "env JOINT_QDESN_PHASE180_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_QDESN_PHASE180_RECOVERY_SESSION=$(printf '%q' "$SESSION") \
      JOINT_QDESN_PHASE180_RECOVERY_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_QDESN_PHASE180_RECOVERY_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_QDESN_PHASE180_SCORE_CORES=$(printf '%q' "$SCORE_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."
  exit 0
fi

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
finish() {
  code=$?
  trap - EXIT
  date --iso-8601=seconds >"$ORCH/launch_finished_at.txt"
  printf '%s\n' "$code" >"$ORCH/EXIT_CODE"
  exit "$code"
}
trap finish EXIT

date --iso-8601=seconds >"$ORCH/launch_started_at.txt"
git -C "$ROOT" rev-parse HEAD >"$ORCH/launch_code_commit.txt"
git -C "$ROOT" status --short >"$ORCH/launch_worktree_status.txt"
printf '%s\n' "$CPU_LIST" >"$ORCH/audited_cpu_list.txt"
printf '%s\n' "$MAX_PARALLEL" >"$ORCH/max_parallel.txt"

if [[ ! -f "$RECOVERY_FREEZE/artifact_manifest.csv" ]]; then
  Rscript "$ROOT/application/scripts/275_prepare_joint_qdesn_phase180_endpoint_start_recovery.R" \
    --cache-root "$CACHE_ROOT" >"$ORCH/preparation.log" 2>&1
fi

mapfile -t WORKERS < <(
  joint_exqdesn_chain_plan_worker_ids "$RECOVERY_FREEZE/recovery_worker_plan.csv"
)
if [[ "${#WORKERS[@]}" -ne 10 ]]; then
  echo "Recovery freeze must authorize exactly ten workers." >&2
  exit 2
fi

for worker in "${WORKERS[@]}"; do
  joint_exqdesn_cpu_queue_acquire
  cpu="$QUEUE_CPU"
  (
    set +e
    env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
      taskset -c "$cpu" Rscript \
      "$ROOT/application/scripts/276_run_joint_qdesn_phase180_endpoint_start_recovery.R" \
      --recovery-dir "$RECOVERY_FREEZE" --worker-id "$worker" \
      --failure-dir "$ORCH/failures" \
      >"$ORCH/logs/worker_$(printf '%04d' "$worker").log" 2>&1
    code=$?
    printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%04d' "$worker").exit"
    exit "$code"
  ) &
  joint_exqdesn_cpu_queue_register "$!" "$cpu"
done
joint_exqdesn_cpu_queue_wait_all

Rscript "$ROOT/application/scripts/277_check_joint_qdesn_phase180_endpoint_start_recovery.R" \
  --cache-root "$CACHE_ROOT" --write >"$ORCH/recovery_health.log" 2>&1
Rscript "$ROOT/application/scripts/270_check_joint_qdesn_phase180_balanced_score_completion.R" \
  --cache-root "$CACHE_ROOT" --write >"$ORCH/overall_health.log" 2>&1
Rscript "$ROOT/application/scripts/272_finalize_joint_qdesn_phase180_balanced_score_packet.R" \
  --cache-root "$CACHE_ROOT" --score-cores "$SCORE_CORES" \
  >"$ORCH/finalization.log" 2>&1
Rscript "$ROOT/application/scripts/273_stage_joint_qdesn_phase180_article_assets.R" \
  --cache-root "$CACHE_ROOT" >"$ORCH/article_staging.log" 2>&1
Rscript "$ROOT/application/scripts/274_freeze_joint_qdesn_phase180_integration_handoff.R" \
  --cache-root "$CACHE_ROOT" >"$ORCH/handoff.log" 2>&1
