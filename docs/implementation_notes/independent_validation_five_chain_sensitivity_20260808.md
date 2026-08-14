# Independent Five-Chain MCMC Sensitivity Integration

## Scope

This article-only integration reports the completed five-chain robustness
sensitivity for the independent single-quantile Gaussian simulation at
`p = 0.25`. It does not modify validation code, application code, the primary
MCMC metric-envelope tables, or the primary heatmap.

## Evidence Decision

The validation campaign completed 12 of 12 fresh fits and all 11 planned
five-chain designs. The frozen estimator is
`median_of_chain_posterior_point_paths_v1`: each chain first supplies one
posterior point path, and the sensitivity path is their coordinatewise median.
This is not pooled posterior sampling.

The evidence is suitable for a labeled supplemental robustness analysis, but
not for silent replacement of the primary article table. The primary table is
a single-chain, metric-wise calibration envelope, whereas each supplemental
row uses one coherent design summarized across five chains. Mixing those
estimators inside the primary table would make its columns methodologically
heterogeneous.

## Reported Comparison

| Model | Evidence | Fit RMSE | Forecast MAE | Forecast check loss |
|---|---|---:|---:|---:|
| Q-DESN AL-RHS | Primary metric envelope | 2.176359 | 2.361033 | 3.296627 |
| Q-DESN AL-RHS | Five-chain coherent design | 1.993347 | 2.323410 | 3.308644 |
| Q-DESN exAL-RHS | Primary metric envelope | 1.709534 | 2.708697 | 3.332522 |
| Q-DESN exAL-RHS | Five-chain coherent design | 1.395960 | 2.473180 | 3.318909 |

The coherent AL-RHS design improves fit RMSE and forecast MAE; its check loss
is 0.4% higher. The coherent exAL-RHS design improves all three displayed
criteria. These are within-model sensitivity comparisons, not a replacement
ranking across DQLM and exDQLM.

## Frozen Provenance

- Validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__qdesn_mcmc_chain_aggregate_confirm_v1_1p0p0`
- Validation branch:
  `validation/qdesn-mcmc-chain-aggregate-confirm-v1-1.0.0`
- Frozen bundle commit:
  `a2ac8fc7dfacc52008babc6d8c61e57f3fead32f`
- Run tag:
  `qdesn-cagc1-full-20260808_161301__git-8cfd304`
- Source-registry hash:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- Frozen bundle manifest hash:
  `996f5647cf9ae9133d11d4cac95377059298055d6118a8bbf5601cfb083274a2`

The article-facing CSV and its manifest retain the exact coherent designs,
reservoir settings, prior scale, chain identifiers, estimator identity, run
provenance, and artifact hashes.

## Article Changes

- `main.tex`: one sentence points readers to the supplemental sensitivity.
- `qdesn-supplement.tex`: methods disclosure and interpretation.
- `tables/qdesn_validation_mcmc_five_chain_sensitivity.csv`: machine-readable
  values and provenance.
- `tables/qdesn_validation_mcmc_five_chain_sensitivity.tex`: generated display
  table.
- `tables/qdesn_validation_mcmc_five_chain_sensitivity_manifest.txt`: hashes
  and source identities.

## Verification

`latexmk` was unavailable. The documented repository fallback was used for
both `main.tex` and `qdesn-supplement.tex`: one `pdflatex` pass, one `bibtex`
pass, and repeated `pdflatex` passes until references converged. The final PDFs
contain 40 and 38 pages, respectively. Final log scans found no LaTeX/package
warnings, unresolved references, undefined citations, overfull boxes, fatal
errors, or multiply defined labels. The supplemental table was also inspected
from the rendered PDF and fits cleanly on the page.
