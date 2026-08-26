#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_nested_context_canary_20260826}"
MANIFEST="${OUTPUT_ROOT}/runtime_manifest.csv"
BACKEND_LIBRARY="$(readlink -f /lib64/libopenblas.so.0)"
BACKEND_SHA256="$(sha256sum "$BACKEND_LIBRARY" | awk '{print $1}')"
cd "$REPO_ROOT"
python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "$MANIFEST" --output-root "$OUTPUT_ROOT" \
  --state-name scheduler_state.csv --max-parallel 3 --max-load 60 \
  --min-memory-gb 64 --min-disk-gb 150 --poll-seconds 30 --cores auto \
  --numerical-backend openblas_serial --backend-threads 1 \
  --backend-library "$BACKEND_LIBRARY" --backend-sha256 "$BACKEND_SHA256" \
  --reference-feature-cache-root "${OUTPUT_ROOT}/common_cache/reference_feature_cache"
Rscript application/scripts/glofas_nested_context_canary_finalize.R --output_root "$OUTPUT_ROOT"
