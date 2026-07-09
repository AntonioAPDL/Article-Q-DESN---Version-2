#!/usr/bin/env bash
# Copy the revised jerez input lineage into ignored article-side directories.
# This script is intentionally narrow: it copies the frozen shared inputs,
# manifest, audit reports, deterministic precipitation and soil handoff
# documents, and GloFAS/GEFS artifacts needed to verify the application data
# contract. GDPC and climate-index products are not model inputs for the active
# Q-DESN discrepancy workflow.

set -euo pipefail

JEREZ_HOST="${JEREZ_HOST:-jerez}"
JEREZ_ROOT="${JEREZ_ROOT:-/data/muscat_data/jaguir26/project1_ucsc_phd}"
DEST_ROOT="${DEST_ROOT:-application/data_local/upstream_jerez}"
DRY_RUN="${DRY_RUN:-0}"
SSH_BATCH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)
if [[ -n "${SSH_CONTROL_PATH:-}" ]]; then
  SSH_BATCH_OPTS+=(-o "ControlPath=${SSH_CONTROL_PATH}" -o ControlMaster=no)
fi

usage() {
  cat <<'EOF'
Usage:
  application/scripts/import_authoritative_jerez_inputs.sh [--dry-run]

Environment overrides:
  JEREZ_HOST   Remote host alias. Default: jerez
  JEREZ_ROOT   Remote project root. Default: /data/muscat_data/jaguir26/project1_ucsc_phd
  DEST_ROOT    Local ignored destination. Default: application/data_local/upstream_jerez
  SSH_CONTROL_PATH
              Optional OpenSSH control socket path for password-authenticated
              sessions opened outside this script.

The copied files remain untracked under application/data_local/.
The script uses non-interactive SSH and fails before copying if the
remote project root is not reachable.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f main.tex || ! -d application ]]; then
  echo "Run this script from the Article-Q-DESN repository root." >&2
  exit 2
fi

RSYNC_FLAGS=(-av --progress)
RSYNC_RSH="ssh"
for opt in "${SSH_BATCH_OPTS[@]}"; do
  RSYNC_RSH+=" $(printf '%q' "$opt")"
done
RSYNC_FLAGS+=(-e "$RSYNC_RSH")
if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_FLAGS+=(--dry-run)
fi

mkdir -p "$DEST_ROOT"

if ! ssh "${SSH_BATCH_OPTS[@]}" "$JEREZ_HOST" "test -d '$JEREZ_ROOT'"; then
  cat >&2 <<EOF
Could not access the jerez project root non-interactively:
  ${JEREZ_HOST}:${JEREZ_ROOT}

Fix SSH access from this host, or run rsync from a machine that can read
the jerez path and copy into:
  ${DEST_ROOT}
EOF
  exit 1
fi

copy_dir() {
  local remote_path="$1"
  local local_path="$2"
  mkdir -p "$local_path"
  rsync "${RSYNC_FLAGS[@]}" "${JEREZ_HOST}:${remote_path}/" "${local_path}/"
}

copy_file() {
  local remote_path="$1"
  local local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  rsync "${RSYNC_FLAGS[@]}" "${JEREZ_HOST}:${remote_path}" "$local_path"
}

copy_dir \
  "${JEREZ_ROOT}/repro/frozen_shared_inputs/exalm_t1_authoritative_20260505" \
  "${DEST_ROOT}/frozen_shared_inputs/exalm_t1_authoritative_20260505"

copy_dir \
  "/data/muscat_data/jaguir26/project1_ucsc_phd_runtime/multimodel_v8_histfix_20260407/stable_inputs/site=11160500/cutoff_date=2022-12-25/run_id=20260407_long_history_r01" \
  "${DEST_ROOT}/histfix_stable_inputs/site=11160500/cutoff_date=2022-12-25/run_id=20260407_long_history_r01"

copy_file \
  "${JEREZ_ROOT}/repro/manifests/exalm_t1_authoritative_runs_20260505.csv" \
  "${DEST_ROOT}/manifests/exalm_t1_authoritative_runs_20260505.csv"

copy_dir \
  "${JEREZ_ROOT}/Evironmetrics---REVISED-DOC-2/reports/five_cutoff_setup_support_review" \
  "${DEST_ROOT}/reports/five_cutoff_setup_support_review"

copy_file \
  "${JEREZ_ROOT}/config/deterministic_climate_handoff.site11160500.yaml" \
  "${DEST_ROOT}/deterministic_climate_handoff/deterministic_climate_handoff.site11160500.yaml"

copy_dir \
  "/data/muscat_data/jaguir26/project1_ucsc_phd_runtime/data_recovery/site=11160500/recovery_run=site11160500_recovery_20260406T185022Z/family=gefs_forecasts/full_runs/source_native_tranche1_20260406T194500Z/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z" \
  "${DEST_ROOT}/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z"

for rel in \
  "repro/DETERMINISTIC_CLIMATE_HANDOFF_PREP_20260415.md" \
  "repro/NWS_NWM_GLOFAS_DATA_AUDIT_PLAN.md" \
  "repro/GEFS_NWM_FORECAST_AUDIT_TRACKER.md" \
  "repro/GLOFAS_OPERATIONAL_MEDIUMRANGE_WORKFLOW_RUNBOOK.md" \
  "repro/GLOFAS_HARMONIZATION_QA_SPEC.md" \
  "repro/WEIGHTED_CUSTOM_FILLED_FORENSICS.md"; do
  copy_file "${JEREZ_ROOT}/${rel}" "${DEST_ROOT}/${rel}"
done

cat <<EOF

Copied authoritative jerez inputs into:
  ${DEST_ROOT}

Next audit command:
  Rscript application/scripts/00_audit_authoritative_source_bundle.R \\
    --bundle_root ${DEST_ROOT}/frozen_shared_inputs/exalm_t1_authoritative_20260505 \\
    --cutoff_date 2022-12-25 \\
    --extra_root ${DEST_ROOT}/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z,${DEST_ROOT}/histfix_stable_inputs/site=11160500/cutoff_date=2022-12-25/run_id=20260407_long_history_r01 \\
    --run_id authoritative_source_audit_20260511
EOF
