#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_shared_backbone_family_campaign_20260906}"
WORKERS="${JOINT_SHARED_FAMILY_WORKERS:-10}"
if [[ "$WORKERS" != "10" ]]; then
  echo "The frozen family campaign requires exactly 10 concurrent one-thread workers." >&2
  exit 2
fi

export JOINT_SHARED_WORKERS="$WORKERS"
export JOINT_SHARED_QUANTILE_WORKERS="$WORKERS"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

mkdir -p "$ROOT"
STATUS_FILE="$ROOT/pipeline_exit_status.csv"
if [[ ! -f "$ROOT/launch_readiness.csv" ]]; then
  if [[ -n "$(find "$ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Campaign root is nonempty but has no launch readiness file: $ROOT" >&2
    exit 2
  fi
  Rscript application/scripts/prepare_joint_qdesn_shared_backbone_family_campaign.R \
    --output-dir "$ROOT"
fi

finish() {
  code=$?
  printf 'exit_code,finished_at_utc\n%s,%s\n' "$code" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$STATUS_FILE"
  exit "$code"
}
trap finish EXIT

mapfile -t SCENARIOS < <(Rscript -e '
  x <- read.csv(commandArgs(TRUE)[1L], check.names = FALSE)
  cat(x$scenario_id[order(x$scenario_order)], sep = "\n")
' "$ROOT/family_plan.csv")

for SCENARIO in "${SCENARIOS[@]}"; do
  mapfile -t PATHS < <(Rscript -e '
    x <- read.csv(commandArgs(TRUE)[1L], check.names = FALSE)
    row <- x[x$scenario_id == commandArgs(TRUE)[2L], , drop = FALSE]
    cat(row$screening_root, row$quantile_root, sep = "\n")
  ' "$ROOT/family_plan.csv" "$SCENARIO")
  SCREEN_ROOT="${PATHS[0]}"
  QUANTILE_ROOT="${PATHS[1]}"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting $SCENARIO Gaussian screen"
  bash application/scripts/launch_joint_qdesn_shared_backbone_pipeline.sh "$SCREEN_ROOT"
  if [[ ! -f "$QUANTILE_ROOT/launch_readiness.csv" ]]; then
    Rscript application/scripts/prepare_joint_qdesn_shared_backbone_family_quantile.R \
      --root "$ROOT" --scenario-id "$SCENARIO"
  fi
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting $SCENARIO quantile VB continuation"
  bash application/scripts/launch_joint_qdesn_shared_backbone_quantile_pilot.sh "$QUANTILE_ROOT"
  Rscript application/scripts/check_joint_qdesn_shared_backbone_family_campaign.R --root "$ROOT"
done

Rscript application/scripts/finalize_joint_qdesn_shared_backbone_family_campaign.R --root "$ROOT"
