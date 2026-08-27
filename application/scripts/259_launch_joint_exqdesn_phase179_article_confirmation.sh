#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_exqdesn_phase179_article_fixture_confirmation_freeze_20260813"
ORCH="$CACHE_ROOT/joint_exqdesn_phase179_article_fixture_confirmation_20260813_orchestration"
SESSION="${JOINT_EXQDESN_PHASE179_ARTICLE_SESSION:-joint_exqdesn_phase179_article_20260813}"
MAX_PARALLEL="${JOINT_EXQDESN_PHASE179_ARTICLE_MAX_PARALLEL:-32}"
CPU_LIST="${JOINT_EXQDESN_PHASE179_ARTICLE_CPU_LIST:-}"
VB_CORES="${JOINT_EXQDESN_PHASE179_ARTICLE_VB_CORES:-8}"
SOURCE_ID="phase179_frozen_article_fixture_exact_M0_freeze"

if [[ -z "$CPU_LIST" ]]; then echo "JOINT_EXQDESN_PHASE179_ARTICLE_CPU_LIST is required." >&2; exit 2; fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"
if [[ "${1:-}" != "--internal" ]]; then
  tmux has-session -t "$SESSION" 2>/dev/null && { echo "Session exists: $SESSION" >&2; exit 2; }
  tmux new-session -d -s "$SESSION" \
    "env JOINT_EXQDESN_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_EXQDESN_PHASE179_ARTICLE_SESSION=$(printf '%q' "$SESSION") \
      JOINT_EXQDESN_PHASE179_ARTICLE_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_EXQDESN_PHASE179_ARTICLE_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_EXQDESN_PHASE179_ARTICLE_VB_CORES=$(printf '%q' "$VB_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."; exit 0
fi
mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
Rscript "$ROOT/application/scripts/257_prepare_joint_exqdesn_phase179_article_confirmation.R" --vb-cores "$VB_CORES" \
  >"$ORCH/preparation.log" 2>&1
if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript "$ROOT/application/scripts/258_check_joint_exqdesn_phase179_article_confirmation.R" >"$ORCH/final_health.log" 2>&1
  exit 0
fi
mapfile -t WORKERS < <(joint_exqdesn_chain_plan_worker_ids "$FREEZE/chain_plan.csv")
for worker in "${WORKERS[@]}"; do
  joint_exqdesn_cpu_queue_acquire; cpu="$QUEUE_CPU"
  (
    set +e
    taskset -c "$cpu" Rscript "$ROOT/application/scripts/251_run_joint_exqdesn_post_m0_chain.R" \
      --freeze-dir "$FREEZE" --source-id "$SOURCE_ID" --worker-id "$worker" \
      --failure-dir "$ORCH/failures" >"$ORCH/logs/worker_$(printf '%04d' "$worker").log" 2>&1
    code=$?; printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%04d' "$worker").exit"; exit "$code"
  ) &
  joint_exqdesn_cpu_queue_register "$!" "$cpu"
done
joint_exqdesn_cpu_queue_wait_all
Rscript "$ROOT/application/scripts/258_check_joint_exqdesn_phase179_article_confirmation.R" >"$ORCH/final_health.log" 2>&1
