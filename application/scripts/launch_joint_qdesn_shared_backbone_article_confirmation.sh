#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RSCRIPT="${JOINT_ARTICLE_CONFIRMATION_RSCRIPT:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}"
ROOT="${JOINT_ARTICLE_CONFIRMATION_ROOT:-${REPO_ROOT}/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907}"
MODE="${1:---dry-run}"

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

case "${MODE}" in
  --dry-run|--preflight)
    "${RSCRIPT}" "${SCRIPT_DIR}/prepare_joint_qdesn_shared_backbone_article_confirmation.R" --output-dir "${ROOT}"
    "${RSCRIPT}" "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_vb.R" --root "${ROOT}"
    ;;
  --launch-vb)
    if [[ "${JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION:-}" != "VB" ]]; then
      echo "Refusing VB launch: set JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=VB after explicit authorization." >&2
      exit 64
    fi
    "${RSCRIPT}" "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_vb.R" --root "${ROOT}"
    "${RSCRIPT}" "${SCRIPT_DIR}/run_joint_qdesn_shared_backbone_article_vb_queue.R" \
      --root "${ROOT}" --max-workers "${JOINT_ARTICLE_CONFIRMATION_VB_WORKERS:-32}"
    ;;
  --launch-mcmc)
    if [[ "${JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION:-}" != "MCMC" ]]; then
      echo "Refusing MCMC launch: set JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC after explicit authorization." >&2
      exit 64
    fi
    "${RSCRIPT}" "${SCRIPT_DIR}/check_joint_qdesn_shared_backbone_article_mcmc.R" --root "${ROOT}"
    echo "MCMC launch authorization detected; submit chain workers with run_joint_qdesn_shared_backbone_article_mcmc_worker.R." >&2
    ;;
  *)
    echo "Usage: $0 [--dry-run|--preflight|--launch-vb|--launch-mcmc]" >&2
    exit 64
    ;;
esac
