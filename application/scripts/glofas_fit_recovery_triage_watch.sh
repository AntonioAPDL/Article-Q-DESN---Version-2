#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${1:-local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731}"
POLL_SECONDS="${POLL_SECONDS:-300}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$OUTPUT_ROOT" != /* ]]; then
  OUTPUT_ROOT="${REPO_ROOT}/${OUTPUT_ROOT}"
fi
MANIFEST="${OUTPUT_ROOT}/runtime_manifest.csv"
LOG="${OUTPUT_ROOT}/logs/finalizer_watch.log"

mkdir -p "${OUTPUT_ROOT}/logs"
cd "$REPO_ROOT"

while true; do
  python3 application/scripts/glofas_fit_recovery_health.py \
    --manifest "$MANIFEST" \
    --output-root "$OUTPUT_ROOT" >> "$LOG" 2>&1

  read -r completed failed stale total < <(python3 - "$OUTPUT_ROOT" <<'PY'
import csv
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rows = list(csv.DictReader((root / "health_summary.csv").open()))
completed = sum(row["status"] in {"completed", "completed_existing"} for row in rows)
failed = sum(row["status"].startswith("failed") for row in rows)
stale = sum(row["status"] == "stale" for row in rows)
print(completed, failed, stale, len(rows))
PY
  )
  printf '%s completed=%s failed=%s stale=%s total=%s\n' \
    "$(date -Is)" "$completed" "$failed" "$stale" "$total" >> "$LOG"

  if (( failed > 0 || stale > 0 )); then
    printf '%s Stage A finalization blocked by failed/stale fits.\n' "$(date -Is)" >> "$LOG"
    exit 1
  fi
  if (( completed == total && total > 0 )); then
    Rscript application/scripts/glofas_fit_recovery_triage_finalize.R \
      --output_root "$OUTPUT_ROOT" \
      --cleanup false >> "$LOG" 2>&1
    printf '%s Stage A finalization completed.\n' "$(date -Is)" >> "$LOG"
    exit 0
  fi
  if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
    printf '%s STOP detected; watcher exiting without finalization.\n' "$(date -Is)" >> "$LOG"
    exit 2
  fi
  sleep "$POLL_SECONDS"
done
