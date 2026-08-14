#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/application/scripts/_joint_exqdesn_cpu_queue.sh"

joint_exqdesn_cpu_queue_init "11,12" 2
joint_exqdesn_cpu_queue_acquire; first_cpu="$QUEUE_CPU"
(sleep 0.20) & first_pid=$!
joint_exqdesn_cpu_queue_register "$first_pid" "$first_cpu"
joint_exqdesn_cpu_queue_acquire; second_cpu="$QUEUE_CPU"
(sleep 0.35) & second_pid=$!
joint_exqdesn_cpu_queue_register "$second_pid" "$second_cpu"

[[ "$first_cpu" != "$second_cpu" ]]
start_ns=$(date +%s%N)
joint_exqdesn_cpu_queue_acquire; recycled_cpu="$QUEUE_CPU"
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
(( elapsed_ms >= 120 ))
[[ "$recycled_cpu" == "$first_cpu" ]]
(sleep 0.05) & recycled_pid=$!
joint_exqdesn_cpu_queue_register "$recycled_pid" "$recycled_cpu"
joint_exqdesn_cpu_queue_wait_all
(( JOINT_EXQDESN_QUEUE_ACTIVE == 0 ))
(( ${#JOINT_EXQDESN_QUEUE_FREE_CPUS[@]} == 2 ))

if (joint_exqdesn_cpu_queue_init "11,11" 2 >/dev/null 2>&1); then
  echo "Duplicate CPU ids were not rejected." >&2
  exit 1
fi

plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
printf '%s\n' '"case_id","notes","worker_id"' '"case_a","quoted, comma",7' '"case_b","ok",12' > "$plan"
mapfile -t parsed_workers < <(joint_exqdesn_chain_plan_worker_ids "$plan")
[[ "${parsed_workers[*]}" == "7 12" ]]

for launcher in 249 253 256 259; do
  file=$(find "$ROOT/application/scripts" -maxdepth 1 -name "${launcher}_launch_joint_exqdesn_*.sh")
  grep -q 'joint_exqdesn_cpu_queue_acquire' "$file"
  ! grep -q 'slot %' "$file"
  if [[ "$launcher" != "249" ]]; then
    grep -q 'joint_exqdesn_chain_plan_worker_ids' "$file"
  fi
done

echo "joint exQDESN completion-aware CPU queue tests passed"
