#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RSCRIPT="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
TASKSET="$(command -v taskset)"
CPU_AFFINITY="0-24"
ROOT="${REPO_ROOT}/application/cache/joint_qdesn_corrected_article_comparison_muscat_25core_20260909"
SOURCE_ROOT="/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_shared_backbone_evidence_detached_muscat_20260909/application/cache/joint_qdesn_shared_backbone_family_campaign_20260906"
CONTRACT="${REPO_ROOT}/application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v3.csv"
SCORE_CONTRACT="${REPO_ROOT}/application/config/joint_qdesn_corrected_article_score_contract_v3.csv"
MODE="${1:---preflight}"

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

run_pinned_r() {
  "${TASKSET}" -c "${CPU_AFFINITY}" "${RSCRIPT}" "$@"
}

case "${MODE}" in
  --dry-run|--preflight)
    run_pinned_r "${SCRIPT_DIR}/prepare_joint_qdesn_shared_backbone_article_confirmation.R" \
      --output-dir "${ROOT}" --source-root "${SOURCE_ROOT}" \
      --contract-path "${CONTRACT}"
    run_pinned_r "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_vb.R" \
      --root "${ROOT}"
    ;;
  --launch-vb)
    if [[ "${JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION:-}" != "VB" ]]; then
      printf '%s\n' "Refusing VB launch without phase-specific authorization." >&2
      exit 64
    fi
    if [[ "${JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED:-}" != "MUSCAT_25_PHYSICAL_IDLE" ]]; then
      printf '%s\n' "Refusing VB launch without a fresh Muscat 25-physical-core capacity approval." >&2
      exit 64
    fi
    run_pinned_r "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_vb.R" \
      --root "${ROOT}"
    run_pinned_r "${SCRIPT_DIR}/run_joint_qdesn_shared_backbone_article_vb_queue.R" \
      --root "${ROOT}" --max-workers 25
    ;;
  --launch-mcmc)
    if [[ "${JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION:-}" != "MCMC" ]]; then
      printf '%s\n' "Refusing MCMC launch without phase-specific authorization." >&2
      exit 64
    fi
    if [[ "${JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED:-}" != "MUSCAT_25_PHYSICAL_IDLE" ]]; then
      printf '%s\n' "Refusing MCMC launch without a fresh Muscat 25-physical-core capacity approval." >&2
      exit 64
    fi
    run_pinned_r "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_vb.R" \
      --root "${ROOT}" --require-complete true
    run_pinned_r "${SCRIPT_DIR}/run_joint_qdesn_shared_backbone_article_mcmc_queue.R" \
      --root "${ROOT}" --max-workers 25
    ;;
  --finalize-score)
    run_pinned_r "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_mcmc.R" \
      --root "${ROOT}"
    run_pinned_r "${SCRIPT_DIR}/finalize_joint_qdesn_shared_backbone_article_score_packet.R" \
      --root "${ROOT}" --contract-path "${SCORE_CONTRACT}" --score-cores 4
    ;;
  *)
    printf '%s\n' \
      "Usage: $0 [--preflight|--launch-vb|--launch-mcmc|--finalize-score]" >&2
    exit 64
    ;;
esac
