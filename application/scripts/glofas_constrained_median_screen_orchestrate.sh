#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "Usage: $0 OUTPUT_ROOT MANIFEST MAX_PARALLEL CORES MAX_LOAD MIN_MEMORY_GB MIN_DISK_GB RUN_FINALIZER CLEANUP" >&2
  exit 2
fi

OUTPUT_ROOT="$1"
MANIFEST="$2"
MAX_PARALLEL="$3"
CORES="$4"
MAX_LOAD="$5"
MIN_MEMORY_GB="$6"
MIN_DISK_GB="$7"
RUN_FINALIZER="$8"
CLEANUP="$9"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUS_PATH="${OUTPUT_ROOT}/orchestration_status.csv"

write_status() {
  local status="$1"
  local exit_code="${2:-}"
  printf 'status,timestamp,exit_code\n%s,%s,%s\n' \
    "$status" "$(date -Is)" "$exit_code" > "${STATUS_PATH}.tmp"
  mv "${STATUS_PATH}.tmp" "$STATUS_PATH"
}

on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    write_status "failed" "$exit_code"
  fi
}
trap on_exit EXIT

cd "$REPO_ROOT"
write_status "running"
python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "$MANIFEST" \
  --output-root "$OUTPUT_ROOT" \
  --max-parallel "$MAX_PARALLEL" \
  --cores "$CORES" \
  --max-load "$MAX_LOAD" \
  --min-memory-gb "$MIN_MEMORY_GB" \
  --min-disk-gb "$MIN_DISK_GB"

if [[ "$RUN_FINALIZER" == "true" ]]; then
  Rscript application/scripts/glofas_constrained_median_screen_finalize.R \
    --output_root "$OUTPUT_ROOT" \
    --cleanup "$CLEANUP"
fi

write_status "completed" "0"
