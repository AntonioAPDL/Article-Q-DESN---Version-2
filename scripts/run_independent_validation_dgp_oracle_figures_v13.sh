#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"
for inference in mcmc vb; do
  for metric_role in fit_rmse forecast_mae forecast_check; do
    Rscript --vanilla scripts/build_independent_validation_dgp_oracle_figures_v13.R \
      --inference "${inference}" --metric-role "${metric_role}"
  done
done
Rscript --vanilla scripts/finalize_independent_validation_dgp_oracle_figures_v13.R
Rscript --vanilla scripts/check_independent_validation_dgp_oracle_figures_v13.R
