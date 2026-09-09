#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"
for metric_role in fit_rmse forecast_mae forecast_check; do
  Rscript --vanilla scripts/build_independent_validation_dgp_oracle_figures_v14.R \
    --inference mcmc --metric-role "${metric_role}"
done
Rscript --vanilla scripts/build_independent_validation_dgp_oracle_figures_v14.R \
  --inference vb --metric-role fit_rmse
Rscript --vanilla scripts/finalize_independent_validation_dgp_oracle_figures_v14.R
Rscript --vanilla scripts/check_independent_validation_dgp_oracle_figures_v14.R
