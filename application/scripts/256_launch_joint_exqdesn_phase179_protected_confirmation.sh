#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_exqdesn_phase179_post_m0_winner_confirmation_freeze_20260813"
ORCH="$CACHE_ROOT/joint_exqdesn_phase179_post_m0_winner_confirmation_20260813_orchestration"
SESSION="${JOINT_EXQDESN_PHASE179_SESSION:-joint_exqdesn_phase179_protected_20260813}"
MAX_PARALLEL="${JOINT_EXQDESN_PHASE179_MAX_PARALLEL:-32}"
CPU_LIST="${JOINT_EXQDESN_PHASE179_CPU_LIST:-}"
VB_CORES="${JOINT_EXQDESN_PHASE179_VB_CORES:-8}"
SOURCE_ID="phase179_protected_winner_confirmation_freeze"

if [[ -z "$CPU_LIST" ]]; then echo "JOINT_EXQDESN_PHASE179_CPU_LIST is required." >&2; exit 2; fi
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
(( ${#CPUS[@]} >= MAX_PARALLEL )) || { echo "CPU list is shorter than MAX_PARALLEL." >&2; exit 2; }
if [[ "${1:-}" != "--internal" ]]; then
  tmux has-session -t "$SESSION" 2>/dev/null && { echo "Session exists: $SESSION" >&2; exit 2; }
  tmux new-session -d -s "$SESSION" \
    "env JOINT_EXQDESN_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_EXQDESN_PHASE179_SESSION=$(printf '%q' "$SESSION") \
      JOINT_EXQDESN_PHASE179_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_EXQDESN_PHASE179_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      JOINT_EXQDESN_PHASE179_VB_CORES=$(printf '%q' "$VB_CORES") \
      bash $(printf '%q' "$0") --internal"
  echo "Launched $SESSION."; exit 0
fi
mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
[[ -f "$FREEZE/artifact_manifest.csv" ]] || \
  Rscript "$ROOT/application/scripts/254_prepare_joint_exqdesn_phase179_protected_confirmation.R" --vb-cores "$VB_CORES" \
    >"$ORCH/preparation.log" 2>&1
mapfile -t WORKERS < <(awk -F, 'NR>1 {gsub(/"/,"",$1); print $1}' "$FREEZE/chain_plan.csv")
active=0; slot=0
for worker in "${WORKERS[@]}"; do
  cpu="${CPUS[$((slot % ${#CPUS[@]}))]}"; slot=$((slot + 1))
  (
    set +e
    taskset -c "$cpu" Rscript "$ROOT/application/scripts/251_run_joint_exqdesn_post_m0_chain.R" \
      --freeze-dir "$FREEZE" --source-id "$SOURCE_ID" --worker-id "$worker" \
      --failure-dir "$ORCH/failures" >"$ORCH/logs/worker_$(printf '%04d' "$worker").log" 2>&1
    code=$?; printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%04d' "$worker").exit"; exit "$code"
  ) &
  active=$((active + 1)); if (( active >= MAX_PARALLEL )); then wait -n || true; active=$((active - 1)); fi
done
wait
Rscript "$ROOT/application/scripts/255_check_joint_exqdesn_phase179_protected_confirmation.R" >"$ORCH/final_health.log" 2>&1
