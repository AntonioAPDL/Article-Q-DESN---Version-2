#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_discrepancy_transition_bridge_20260825}"
MAX_PARALLEL="${2:-20}"
MANIFEST="${OUTPUT_ROOT}/runtime_manifest.csv"
BACKEND_LIBRARY="$(readlink -f /lib64/libopenblas.so.0)"
BACKEND_SHA256="$(sha256sum "$BACKEND_LIBRARY" | awk '{print $1}')"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing prepared runtime manifest: $MANIFEST" >&2
  exit 2
fi
if [[ "$MAX_PARALLEL" -ne 20 ]]; then
  echo "The frozen bridge requires exactly 20 parallel one-thread workers." >&2
  exit 2
fi
if [[ -e "${OUTPUT_ROOT}/STOP" ]]; then
  echo "A STOP marker is present: ${OUTPUT_ROOT}/STOP" >&2
  exit 2
fi

cd "$REPO_ROOT"
python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "$MANIFEST" \
  --output-root "$OUTPUT_ROOT" \
  --max-parallel "$MAX_PARALLEL" \
  --max-load 60 \
  --min-memory-gb 64 \
  --min-disk-gb 150 \
  --poll-seconds 30 \
  --cores auto \
  --numerical-backend openblas_serial \
  --backend-threads 1 \
  --backend-library "$BACKEND_LIBRARY" \
  --backend-sha256 "$BACKEND_SHA256" \
  --reference-feature-cache-root "${OUTPUT_ROOT}/common_cache/reference_feature_cache"

Rscript application/scripts/glofas_discrepancy_transition_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --cleanup true
