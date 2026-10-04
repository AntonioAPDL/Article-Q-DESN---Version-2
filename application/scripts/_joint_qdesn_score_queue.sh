#!/usr/bin/env bash

# Run every job assigned to one queue slot even when an earlier job fails.
# The caller supplies a callback that accepts one numeric worker ID.
joint_qdesn_run_fail_isolated_jobs() {
  local receipt_dir="$1" callback="$2"
  shift 2
  local worker_id code receipt tmp failed=0

  mkdir -p "$receipt_dir"
  for worker_id in "$@"; do
    [[ "$worker_id" =~ ^[0-9]+$ ]] || {
      echo "Queue worker ID is not numeric: $worker_id" >&2
      return 64
    }
    if "$callback" "$worker_id"; then
      code=0
    else
      code=$?
      failed=1
    fi
    receipt="$receipt_dir/worker_$(printf '%04d' "$worker_id").exit"
    tmp="${receipt}.tmp.$$"
    printf '%s\n' "$code" >"$tmp"
    mv "$tmp" "$receipt"
  done
  return "$failed"
}
