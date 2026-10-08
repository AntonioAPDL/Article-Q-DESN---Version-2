#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
sha256sum -c INPUT_SHA256SUMS
Rscript scripts/reproduce_qdesn_joint_forecast.R
cmp expected/joint_qdesn_pure_desn_v1_score_table.tex tables/joint_qdesn_pure_desn_v1_score_table.tex
mkdir -p verification
for version in expected regenerated; do
  pdf=expected/joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf
  if [[ "$version" == regenerated ]]; then
    pdf=figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf
  fi
  pdftotext "$pdf" "verification/$version.txt"
  pdftoppm -r 150 -png -singlefile "$pdf" "verification/$version" >/dev/null 2>&1
done
cmp verification/expected.txt verification/regenerated.txt
cmp verification/expected.png verification/regenerated.png
echo "QDESN_REPRESENTATIVE_TABLE_BYTE_EQUAL_FIGURE_TEXT_AND_PIXELS_EQUAL=PASS"
