#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
CONFIRMATION_ROOT="${2:-application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${3:-application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
RECOVERY_ROOT="${4:-application/cache/joint_qdesn_pure_recursive_mcmc_preflight_recovery_v1_20260928}"
R_BIN="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
BRANCH="work/joint-qdesn-pure-desn-recursive-selection-20260925"
CPU_LIST="1,8,9,12,13,15,19,20,24,25,27,28,29,30,31"
CAPACITY_TOKEN="JEREZ_PURE_RECURSIVE_15_PHYSICAL_SHARED"

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC
export JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED="$CAPACITY_TOKEN"

[[ "$(hostname -s)" == "jerez" ]] || { echo "Recovery may run only on jerez." >&2; exit 2; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || { echo "Wrong execution branch." >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Tracked worktree is dirty." >&2; exit 2; }
[[ "$(git rev-list --left-right --count '@{upstream}'...HEAD)" == $'0\t0' ]] || {
  echo "Execution branch is not synchronized." >&2
  exit 2
}
[[ -x "$R_BIN" ]] || { echo "Pinned Rscript is unavailable." >&2; exit 2; }
[[ ! -d "$CONFIRMATION_ROOT/mcmc_queue.lock" ]] || {
  echo "An MCMC queue lock already exists." >&2
  exit 2
}

if [[ ! -f "$RECOVERY_ROOT/recovery_summary.csv" ]]; then
  taskset -c "$CPU_LIST" "$R_BIN" \
    application/scripts/recover_joint_qdesn_pure_recursive_mcmc_preflight_failure.R \
    --root "$CONFIRMATION_ROOT" --recovery-root "$RECOVERY_ROOT"
fi

recovery_status="$(awk -F, 'NR==2 {gsub(/"/, ""); print $1}' \
  "$RECOVERY_ROOT/recovery_summary.csv")"
[[ "$recovery_status" == "INFRASTRUCTURE_FAILURES_ARCHIVED_READY_TO_RESUME" ]] || {
  echo "Recovery summary is not resume-ready." >&2
  exit 2
}

exec bash application/scripts/launch_joint_qdesn_pure_recursive_confirmation_shared_jerez.sh \
  "$SOURCE_ROOT" "$CONFIRMATION_ROOT" "$SCORE_ROOT"
