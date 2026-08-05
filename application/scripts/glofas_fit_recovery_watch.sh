#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${1:?usage: glofas_fit_recovery_watch.sh OUTPUT_ROOT FINALIZER [POLL_SECONDS]}"
FINALIZER="${2:?usage: glofas_fit_recovery_watch.sh OUTPUT_ROOT FINALIZER [POLL_SECONDS]}"
POLL_SECONDS="${3:-${POLL_SECONDS:-300}}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

case "$FINALIZER" in
  application/scripts/glofas_fit_recovery_triage_finalize.R|application/scripts/glofas_fit_recovery_blocked_finalize.R|application/scripts/glofas_fit_recovery_full7_finalize.R)
    ;;
  *)
    printf 'Refusing non-allowlisted finalizer: %s\n' "$FINALIZER" >&2
    exit 64
    ;;
esac

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
    printf '%s Finalization blocked by failed/stale fits.\n' "$(date -Is)" >> "$LOG"
    exit 1
  fi
  if (( completed == total && total > 0 )); then
    Rscript "$FINALIZER" --output_root "$OUTPUT_ROOT" >> "$LOG" 2>&1
    printf '%s Finalization completed with %s.\n' "$(date -Is)" "$FINALIZER" >> "$LOG"
    exit 0
  fi
  if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
    printf '%s STOP detected; watcher exiting without finalization.\n' "$(date -Is)" >> "$LOG"
    exit 2
  fi
  sleep "$POLL_SECONDS"
done
