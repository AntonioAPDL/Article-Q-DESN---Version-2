#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_exqdesn_phase178_post_m0_case_specific_screen_freeze_20260813"
ORCH="$CACHE_ROOT/joint_exqdesn_phase178_post_m0_case_specific_screen_20260813_orchestration"
SESSION="${JOINT_EXQDESN_PHASE178_VB_SESSION:-joint_exqdesn_phase178_vb_20260813}"
MAX_PARALLEL="${JOINT_EXQDESN_PHASE178_VB_MAX_PARALLEL:-24}"
CPU_LIST="${JOINT_EXQDESN_PHASE178_VB_CPU_LIST:-}"

if [[ -z "$CPU_LIST" ]]; then
  echo "JOINT_EXQDESN_PHASE178_VB_CPU_LIST must be an audited comma-separated CPU list." >&2
  exit 2
fi
joint_exqdesn_cpu_queue_init "$CPU_LIST" "$MAX_PARALLEL"

if [[ "${1:-}" != "--internal" ]]; then
  tmux has-session -t "$SESSION" 2>/dev/null && { echo "Session exists: $SESSION" >&2; exit 2; }
  tmux new-session -d -s "$SESSION" \
    "env JOINT_EXQDESN_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_EXQDESN_PHASE178_VB_SESSION=$(printf '%q' "$SESSION") \
      JOINT_EXQDESN_PHASE178_VB_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_EXQDESN_PHASE178_VB_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."
  exit 0
fi

mkdir -p "$ORCH/logs" "$ORCH/exits"
[[ -f "$FREEZE/artifact_manifest.csv" ]] || \
  Rscript "$ROOT/application/scripts/246_prepare_joint_exqdesn_phase178_post_m0_screen.R" \
    >"$ORCH/preparation.log" 2>&1
planned=$(awk -F, 'END {print NR-1}' "$FREEZE/vb_candidate_registry.csv")
for row in $(seq 1 "$planned"); do
  joint_exqdesn_cpu_queue_acquire; cpu="$QUEUE_CPU"
  (
    set +e
    taskset -c "$cpu" Rscript "$ROOT/application/scripts/247_run_joint_exqdesn_phase178_vb_rows.R" \
      --row-indices "$row" >"$ORCH/logs/row_$(printf '%04d' "$row").log" 2>&1
    code=$?; printf '%s\n' "$code" >"$ORCH/exits/row_$(printf '%04d' "$row").exit"; exit "$code"
  ) &
  joint_exqdesn_cpu_queue_register "$!" "$cpu"
done
joint_exqdesn_cpu_queue_wait_all
Rscript "$ROOT/application/scripts/248_check_joint_exqdesn_phase178_vb_screen.R" >"$ORCH/final_health.log" 2>&1
