#!/usr/bin/env bash

# Completion-aware CPU leasing for heterogeneous scientific workers.
# The caller launches a child, then registers its PID against QUEUE_CPU.

declare -ag JOINT_EXQDESN_QUEUE_FREE_CPUS=()
declare -Ag JOINT_EXQDESN_QUEUE_PID_CPU=()
declare -gi JOINT_EXQDESN_QUEUE_ACTIVE=0
QUEUE_CPU=""

joint_exqdesn_chain_plan_worker_ids() {
  local chain_plan="$1"
  Rscript - "$chain_plan" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- read.csv(args[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
if (!"worker_id" %in% names(x) || anyNA(x$worker_id) ||
    anyDuplicated(x$worker_id) || any(x$worker_id != as.integer(x$worker_id))) {
  stop("chain_plan.csv requires unique integer worker_id values.", call. = FALSE)
}
cat(as.integer(x$worker_id), sep = "\n")
RS
}

joint_exqdesn_cpu_queue_init() {
  local cpu_list="$1" max_parallel="$2" cpu
  local -A seen=()

  [[ "$max_parallel" =~ ^[1-9][0-9]*$ ]] || {
    echo "MAX_PARALLEL must be a positive integer." >&2
    return 2
  }
  IFS=',' read -r -a JOINT_EXQDESN_QUEUE_FREE_CPUS <<< "$cpu_list"
  (( ${#JOINT_EXQDESN_QUEUE_FREE_CPUS[@]} >= max_parallel )) || {
    echo "CPU list is shorter than MAX_PARALLEL." >&2
    return 2
  }
  JOINT_EXQDESN_QUEUE_FREE_CPUS=("${JOINT_EXQDESN_QUEUE_FREE_CPUS[@]:0:max_parallel}")
  for cpu in "${JOINT_EXQDESN_QUEUE_FREE_CPUS[@]}"; do
    [[ "$cpu" =~ ^[0-9]+$ ]] || { echo "Invalid CPU id: $cpu" >&2; return 2; }
    [[ -z "${seen[$cpu]:-}" ]] || { echo "Duplicate CPU id: $cpu" >&2; return 2; }
    seen[$cpu]=1
  done
  JOINT_EXQDESN_QUEUE_PID_CPU=()
  JOINT_EXQDESN_QUEUE_ACTIVE=0
}

joint_exqdesn_cpu_queue_reap_one() {
  local completed_pid="" completed_cpu="" pid live_pid
  (( JOINT_EXQDESN_QUEUE_ACTIVE > 0 )) || return 0
  while [[ -z "$completed_pid" ]]; do
    local -A live=()
    while read -r live_pid; do
      [[ -n "$live_pid" ]] && live[$live_pid]=1
    done < <(jobs -pr)
    for pid in "${!JOINT_EXQDESN_QUEUE_PID_CPU[@]}"; do
      if [[ -z "${live[$pid]:-}" ]]; then
        completed_pid="$pid"
        break
      fi
    done
    [[ -n "$completed_pid" ]] || sleep 0.10
  done
  if wait "$completed_pid"; then :; else :; fi
  completed_cpu="${JOINT_EXQDESN_QUEUE_PID_CPU[$completed_pid]:-}"
  [[ -n "$completed_cpu" ]] || {
    echo "CPU queue lost the completed PID lease: $completed_pid" >&2
    return 2
  }
  JOINT_EXQDESN_QUEUE_FREE_CPUS+=("$completed_cpu")
  unset 'JOINT_EXQDESN_QUEUE_PID_CPU[$completed_pid]'
  JOINT_EXQDESN_QUEUE_ACTIVE=$((JOINT_EXQDESN_QUEUE_ACTIVE - 1))
}

joint_exqdesn_cpu_queue_acquire() {
  while (( ${#JOINT_EXQDESN_QUEUE_FREE_CPUS[@]} == 0 )); do
    joint_exqdesn_cpu_queue_reap_one
  done
  QUEUE_CPU="${JOINT_EXQDESN_QUEUE_FREE_CPUS[0]}"
  JOINT_EXQDESN_QUEUE_FREE_CPUS=("${JOINT_EXQDESN_QUEUE_FREE_CPUS[@]:1}")
}

joint_exqdesn_cpu_queue_register() {
  local pid="$1" cpu="$2"
  [[ "$pid" =~ ^[1-9][0-9]*$ && -n "$cpu" ]] || return 2
  JOINT_EXQDESN_QUEUE_PID_CPU[$pid]="$cpu"
  JOINT_EXQDESN_QUEUE_ACTIVE=$((JOINT_EXQDESN_QUEUE_ACTIVE + 1))
}

joint_exqdesn_cpu_queue_wait_all() {
  while (( JOINT_EXQDESN_QUEUE_ACTIVE > 0 )); do
    joint_exqdesn_cpu_queue_reap_one
  done
}
