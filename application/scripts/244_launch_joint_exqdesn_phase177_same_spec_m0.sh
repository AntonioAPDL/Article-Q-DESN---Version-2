#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
FREEZE="$CACHE_ROOT/joint_exqdesn_phase177_same_spec_m0_freeze_20260813"
ORCH="$CACHE_ROOT/joint_exqdesn_phase177_same_spec_m0_confirmation_20260813_orchestration"
SESSION="${JOINT_EXQDESN_PHASE177_SESSION:-joint_exqdesn_phase177_20260813}"
MAX_PARALLEL="${JOINT_EXQDESN_PHASE177_MAX_PARALLEL:-16}"
CPU_LIST="${JOINT_EXQDESN_PHASE177_CPU_LIST:-}"

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  Rscript "$ROOT/application/scripts/241_prepare_joint_exqdesn_phase177_same_spec_m0.R"
fi
if [[ -z "$CPU_LIST" ]]; then
  echo "JOINT_EXQDESN_PHASE177_CPU_LIST must be an audited comma-separated CPU list." >&2
  exit 2
fi
IFS=',' read -r -a CPUS <<< "$CPU_LIST"
if (( ${#CPUS[@]} < MAX_PARALLEL )); then
  echo "CPU list has fewer entries than MAX_PARALLEL." >&2
  exit 2
fi

if [[ "${1:-}" != "--internal" ]]; then
  tmux has-session -t "$SESSION" 2>/dev/null && {
    echo "tmux session already exists: $SESSION" >&2; exit 2;
  }
  tmux new-session -d -s "$SESSION" \
    "env JOINT_EXQDESN_CACHE_ROOT=$(printf '%q' "$CACHE_ROOT") \
      JOINT_EXQDESN_PHASE177_SESSION=$(printf '%q' "$SESSION") \
      JOINT_EXQDESN_PHASE177_MAX_PARALLEL=$(printf '%q' "$MAX_PARALLEL") \
      JOINT_EXQDESN_PHASE177_CPU_LIST=$(printf '%q' "$CPU_LIST") \
      bash $(printf '%q' "$0") --internal"
  planned=$(awk -F, 'END {print NR-1}' "$FREEZE/chain_plan.csv")
  echo "Launched $SESSION with $planned planned workers and max parallel $MAX_PARALLEL."
  exit 0
fi

mapfile -t WORKERS < <(awk -F, 'NR>1 {gsub(/"/,"",$1); print $1}' "$FREEZE/chain_plan.csv")
active=0
slot=0
for worker in "${WORKERS[@]}"; do
  worker_dir=$(awk -F, -v id="$worker" 'NR==1 {for(i=1;i<=NF;i++){gsub(/"/,"",$i); if($i=="worker_output_dir") c=i}} NR>1 {x=$1; gsub(/"/,"",x); if(x==id){v=$c; gsub(/^"|"$/,"",v); print v; exit}}' "$FREEZE/chain_plan.csv")
  [[ -f "$worker_dir/artifact_manifest.csv" ]] && continue
  cpu="${CPUS[$((slot % ${#CPUS[@]}))]}"; slot=$((slot + 1))
  (
    set +e
    taskset -c "$cpu" Rscript "$ROOT/application/scripts/242_run_joint_exqdesn_phase177_same_spec_m0_chain.R" \
      --freeze-dir "$FREEZE" --worker-id "$worker" --failure-dir "$ORCH/failures" \
      >"$ORCH/logs/worker_$(printf '%03d' "$worker").log" 2>&1
    code=$?
    printf '%s\n' "$code" >"$ORCH/exits/worker_$(printf '%03d' "$worker").exit"
    exit "$code"
  ) &
  active=$((active + 1))
  if (( active >= MAX_PARALLEL )); then wait -n || true; active=$((active - 1)); fi
done
wait
Rscript "$ROOT/application/scripts/243_check_joint_exqdesn_phase177_same_spec_m0.R" >"$ORCH/final_health.log" 2>&1
