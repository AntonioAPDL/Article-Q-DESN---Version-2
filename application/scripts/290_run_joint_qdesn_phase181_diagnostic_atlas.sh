#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_ROOT="${JOINT_QDESN_PHASE181_SOURCE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2}"
OUTPUT_DIR="${JOINT_QDESN_PHASE181_ATLAS_OUTPUT_DIR:-${ROOT}/local_trackers/joint_qdesn_phase181_diagnostic_atlas_20260831}"
EXTRACT_CORES="${JOINT_QDESN_PHASE181_ATLAS_EXTRACT_CORES:-2}"
RENDER_WORKERS="${JOINT_QDESN_PHASE181_ATLAS_RENDER_WORKERS:-4}"

Rscript "${ROOT}/application/scripts/286_prepare_joint_qdesn_phase181_diagnostic_atlas.R" \
  --source-root "${SOURCE_ROOT}" \
  --output-dir "${OUTPUT_DIR}" \
  --cores "${EXTRACT_CORES}" \
  "$@"

active=0
for page in $(seq 1 40); do
  Rscript "${ROOT}/application/scripts/287_render_joint_qdesn_phase181_diagnostic_atlas_page.R" \
    --output-dir "${OUTPUT_DIR}" --page "${page}" &
  active=$((active + 1))
  if [[ "${active}" -ge "${RENDER_WORKERS}" ]]; then
    wait -n
    active=$((active - 1))
  fi
done
wait

Rscript "${ROOT}/application/scripts/288_finalize_joint_qdesn_phase181_diagnostic_atlas.R" \
  --output-dir "${OUTPUT_DIR}" --force
Rscript "${ROOT}/application/scripts/289_check_joint_qdesn_phase181_diagnostic_atlas.R" \
  --output-dir "${OUTPUT_DIR}"

printf 'JOINT Phase181 diagnostic atlas complete: %s\n' "${OUTPUT_DIR}"
