#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
CONFIRMATION_ROOT="${2:-application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${3:-application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
CONTROL_ROOT="${4:-application/cache/joint_qdesn_pure_recursive_controller_seedfix_recovery_20260925}"
POLL_SECONDS="${JOINT_CAPACITY_POLL_SECONDS:-120}"
REQUIRED_CLEAN_POLLS="${JOINT_CAPACITY_CLEAN_POLLS:-5}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
BRANCH="work/joint-qdesn-pure-desn-recursive-selection-20260925"
TARGET_CPU_MIN=2
TARGET_CPU_MAX=16

[[ "$(hostname -s)" == "jerez" ]] || { echo "Recovery may run only on jerez." >&2; exit 2; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || { echo "Wrong execution branch." >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Tracked worktree is dirty." >&2; exit 2; }
[[ "$(git rev-list --left-right --count '@{upstream}'...HEAD)" == $'0\t0' ]] || {
  echo "Execution branch is not synchronized." >&2
  exit 2
}
[[ -x "$R_BIN" ]] || { echo "Pinned Rscript is unavailable." >&2; exit 2; }

mkdir -p "$CONTROL_ROOT"
printf 'status,source_root,required_cpu_affinity,poll_seconds,required_clean_polls,updated_at_utc\nFINALIZING_QUANTILE_VB,%s,2-16,%s,%s,%s\n' \
  "$ROOT" "$POLL_SECONDS" "$REQUIRED_CLEAN_POLLS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"$CONTROL_ROOT/resume_status.csv"

if [[ ! -f "$ROOT/quantile_final_health.csv" ]]; then
  taskset -c 2 "$R_BIN" application/scripts/finalize_joint_qdesn_pure_recursive_stage.R \
    --root "$ROOT" --stage quantile
fi

printf 'checked_at_utc,blocker_count,clean_poll_count\n' >"$CONTROL_ROOT/capacity_history.csv"
clean_polls=0
while (( clean_polls < REQUIRED_CLEAN_POLLS )); do
  blocker_file="$CONTROL_ROOT/capacity_blockers.csv"
  printf 'pid,last_cpu,pcpu,command\n' >"$blocker_file"
  ps -u "$USER" -o pid=,psr=,pcpu=,args= | awk \
    -v self="$$" -v parent="$PPID" -v cpu_min="$TARGET_CPU_MIN" -v cpu_max="$TARGET_CPU_MAX" '
      {
        pid = $1; cpu = $2; pcpu = $3
        $1 = $2 = $3 = ""; sub(/^ +/, ""); command = $0
        if (pid == self || pid == parent) next
        if (command ~ /^awk -v self=/) next
        known_controller = command ~ /pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925/ ||
          command ~ /run_joint_qdesn_pure_recursive_(quantile_worker|article_vb|article_mcmc)/ ||
          command ~ /joint_qdesn_recursive_mean_forecast_worker/
        hot_on_target = cpu >= cpu_min && cpu <= cpu_max && pcpu + 0 >= 20
        if (known_controller || hot_on_target) {
          gsub(/,/, ";", command)
          printf "%s,%s,%s,%s\n", pid, cpu, pcpu, command
        }
      }
    ' >>"$blocker_file"
  blocker_count="$(($(wc -l <"$blocker_file") - 1))"
  if (( blocker_count == 0 )); then
    clean_polls=$((clean_polls + 1))
  else
    clean_polls=0
  fi
  printf '%s,%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$blocker_count" "$clean_polls" \
    >>"$CONTROL_ROOT/capacity_history.csv"
  printf 'status,source_root,required_cpu_affinity,blocker_count,clean_poll_count,required_clean_polls,updated_at_utc\nWAITING_FOR_EXCLUSIVE_CAPACITY,%s,2-16,%s,%s,%s,%s\n' \
    "$ROOT" "$blocker_count" "$clean_polls" "$REQUIRED_CLEAN_POLLS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"$CONTROL_ROOT/resume_status.csv"
  (( clean_polls >= REQUIRED_CLEAN_POLLS )) || sleep "$POLL_SECONDS"
done

printf 'status,source_root,required_cpu_affinity,released_at_utc\nCAPACITY_RELEASED_RESUMING_PIPELINE,%s,2-16,%s\n' \
  "$ROOT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CONTROL_ROOT/resume_status.csv"

exec bash application/scripts/launch_joint_qdesn_pure_recursive_campaign.sh \
  "$ROOT" "$CONFIRMATION_ROOT" "$SCORE_ROOT"
