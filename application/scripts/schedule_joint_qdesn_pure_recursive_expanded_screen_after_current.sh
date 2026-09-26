#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
SOURCE_CONTROLLER="${2:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_controller_denseguard_recovery_20260925}"
TARGET_ROOT="${3:-application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925}"
POLL_SECONDS="${JOINT_EXPANDED_POLL_SECONDS:-120}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"

[[ "$(hostname -s)" == "jerez" ]] || { echo "Deferred expanded screening may run only on jerez." >&2; exit 2; }
mkdir -p "$(dirname "$TARGET_ROOT")"
printf 'status,source_root,source_controller,poll_seconds,scheduled_at_utc\nWAITING_FOR_SOURCE_PIPELINE,%s,%s,%s,%s\n' \
  "$SOURCE_ROOT" "$SOURCE_CONTROLLER" "$POLL_SECONDS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${TARGET_ROOT}.deferred_status.csv"

while :; do
  exit_ready=false
  status_ready=false
  [[ -f "$SOURCE_CONTROLLER/controller.exit" ]] && [[ "$(tr -d '[:space:]' <"$SOURCE_CONTROLLER/controller.exit")" == "0" ]] && exit_ready=true
  if [[ -f "$SOURCE_ROOT/final_pipeline_status.csv" ]] && \
      grep -q '^COMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS,' "$SOURCE_ROOT/final_pipeline_status.csv"; then
    status_ready=true
  fi
  if [[ "$exit_ready" == true && "$status_ready" == true ]]; then break; fi
  sleep "$POLL_SECONDS"
done

if pgrep -af 'run_joint_qdesn_pure_recursive_(quantile_worker|article_vb|article_mcmc)|joint_qdesn_recursive_mean_forecast_worker' >/dev/null; then
  echo "Source controller is terminal but related workers remain." >&2
  exit 2
fi

printf 'status,source_root,source_controller,released_at_utc\nSOURCE_PIPELINE_COMPLETE_CAPACITY_RELEASED,%s,%s,%s\n' \
  "$SOURCE_ROOT" "$SOURCE_CONTROLLER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${TARGET_ROOT}.deferred_status.csv"

exec bash application/scripts/launch_joint_qdesn_pure_recursive_expanded_screen.sh \
  "$TARGET_ROOT" "$SOURCE_ROOT"
