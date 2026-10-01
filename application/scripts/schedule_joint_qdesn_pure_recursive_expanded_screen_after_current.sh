#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
CONFIRMATION_ROOT="${2:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${3:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
TARGET_ROOT="${4:-application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925}"
POLL_SECONDS="${JOINT_EXPANDED_POLL_SECONDS:-120}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
SOURCE_PROCESS_PATTERN='run_joint_qdesn_pure_recursive_(quantile_worker|article_vb|article_mcmc)|run_joint_qdesn_recursive_(dgp_oracle_worker|mean_forecast_worker)|prepare_joint_qdesn_pure_recursive_score_packet|finalize_joint_qdesn_recursive_mean_forecast'

[[ "$(hostname -s)" == "jerez" ]] || { echo "Deferred expanded screening may run only on jerez." >&2; exit 2; }
mkdir -p "$(dirname "$TARGET_ROOT")"
printf 'status,source_root,confirmation_root,score_root,poll_seconds,scheduled_at_utc\nWAITING_FOR_VERIFIED_SOURCE_PIPELINE,%s,%s,%s,%s,%s\n' \
  "$SOURCE_ROOT" "$CONFIRMATION_ROOT" "$SCORE_ROOT" "$POLL_SECONDS" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${TARGET_ROOT}.deferred_status.csv"

while :; do
  status_ready=false
  if [[ -f "$SOURCE_ROOT/final_pipeline_status.csv" ]] && \
      grep -q '^COMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS,' "$SOURCE_ROOT/final_pipeline_status.csv"; then
    status_ready=true
  fi
  manifests_ready=false
  if [[ -f "$CONFIRMATION_ROOT/mcmc_final_manifest_verification.csv" ]] && \
      [[ -f "$SCORE_ROOT/final_packet/artifact_manifest_verification.csv" ]] && \
      [[ -f "$SCORE_ROOT/final_packet/DONE" ]]; then
    if "$R_BIN" -e '
      truth <- function(x) tolower(trimws(as.character(x))) %in% c("true", "t", "1")
      args <- commandArgs(TRUE)
      mcmc <- read.csv(args[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
      score <- read.csv(args[[2L]], stringsAsFactors = FALSE, check.names = FALSE)
      stopifnot("verified" %in% names(mcmc), "verified" %in% names(score),
        nrow(mcmc) > 0L, nrow(score) > 0L,
        all(truth(mcmc$verified)), all(truth(score$verified)))
    ' "$CONFIRMATION_ROOT/mcmc_final_manifest_verification.csv" \
      "$SCORE_ROOT/final_packet/artifact_manifest_verification.csv" \
      >/dev/null 2>&1; then
      manifests_ready=true
    fi
  fi
  workers_idle=false
  if ! pgrep -af "$SOURCE_PROCESS_PATTERN" >/dev/null; then
    workers_idle=true
  fi
  if [[ "$status_ready" == true && "$manifests_ready" == true && \
        "$workers_idle" == true ]]; then
    break
  fi
  sleep "$POLL_SECONDS"
done

printf 'status,source_root,confirmation_root,score_root,released_at_utc\nVERIFIED_SOURCE_PIPELINE_COMPLETE_CAPACITY_RELEASED,%s,%s,%s,%s\n' \
  "$SOURCE_ROOT" "$CONFIRMATION_ROOT" "$SCORE_ROOT" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${TARGET_ROOT}.deferred_status.csv"

exec bash application/scripts/launch_joint_qdesn_pure_recursive_expanded_screen.sh \
  "$TARGET_ROOT" "$SOURCE_ROOT"
