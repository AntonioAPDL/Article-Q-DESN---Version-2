# Shared Validation Table Integration Audit

Date: 2026-06-21

## Scope

This audit covers the Article-Q-DESN manuscript integration of the finalized
TT500 shared Q-DESN + exDQLM/DQLM fit-and-forecast validation handoff. It does
not certify TT5000 MCMC or any future TT100 handoff.

## Style Criteria Applied

- Keep simulation claims tied to the fixed dynamic source design.
- State the data-generating process, fit and forecast protocol, competitors,
  metrics, results, and limitations.
- Keep captions self-contained enough to interpret rows, columns, panels,
  forecast averaging, and boldface.
- Avoid leaderboard language and global winner claims.
- Keep operational status and failure fields in manifests and guarded
  interfaces rather than in manuscript tables.
- Generate manuscript tables from pinned configs and interface hashes, not by
  hand-editing table values.

## Integration Decisions

- The manuscript section is titled `Simulation Validation Study`, while the
  existing label `sec:simulation` is preserved.
- The validation block is split into data-generating processes, fit and
  forecast protocol, competing methods, criteria, TT500 results, and
  reproducibility limitations.
- A compact protocol table is generated before the three family result tables:
  `tables/qdesn_validation_tt500_final_protocol.tex`.
- The family result tables remain split by simulation family rather than by
  metric or inference method. This keeps each table interpretable as a
  family-specific comparison while preserving paired VB--LD and MCMC panels.
- Lead-level rows stay in the source interfaces and generated summary CSV. They
  are not printed in the manuscript.
- TT5000 and TT100 remain excluded until a separate final handoff pins source
  hashes, interface hashes, row counts, and article-side guards.

## Reproducibility Inputs

- Config: `application/config/shared_validation_tt500_final_fitforecast.yaml`
- Builder: `application/scripts/31_build_shared_validation_tt500_final_tables.R`
- Manifest: `tables/qdesn_validation_tt500_final_manifest.txt`
- Summary CSV: `tables/qdesn_validation_tt500_final_summary.csv`
- Source registry SHA-256:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- Validation branch: `validation/shared-fitforecast-v2-1.0.0`
- Validation HEAD at article sync:
  `437dc73385d0922cd2f79d13262947ff1ba01d77`

## Commands

```sh
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
Rscript application/tests/run_tests.R
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
rg "qdesn_validation_tt500_provisional_progress" main.tex
rg "0p5p0|0.5.0|/home/jaguir26/local/src" main.tex application/config/shared_validation_tt500_final_fitforecast.yaml
rg "tab:simulation-tt500-final" main.aux
```

## Verification Results

- `Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R`
  passed with `summary_rows: 108` and `lead_rows_consumed: 3240`.
- `Rscript application/tests/run_tests.R` passed. The run retained the existing
  skip for the unavailable Q-DESN discrepancy engine adapter and one plotting
  scale warning.
- `pdflatex -interaction=nonstopmode -halt-on-error main.tex` passed twice.
- The final PDF has 29 pages.
- `main.log` and `main.blg` have no overfull boxes, undefined references, or
  LaTeX warnings after the second compile.
- `main.tex` no longer includes the provisional TT500 progress table.
- The only `0.5.0` hit in `main.tex` is intentional guardrail prose stating
  that old validation paths are refused.
- Final validation table labels resolve to:
  `tab:simulation-tt500-final-protocol`,
  `tab:simulation-tt500-final-normal`,
  `tab:simulation-tt500-final-laplace`, and
  `tab:simulation-tt500-final-gausmix`.

## Expected Outputs

- `tables/qdesn_validation_tt500_final_protocol.tex`
- `tables/qdesn_validation_tt500_final_normal.tex`
- `tables/qdesn_validation_tt500_final_laplace.tex`
- `tables/qdesn_validation_tt500_final_gausmix.tex`
- `tables/qdesn_validation_tt500_final_tables.tex`
- `tables/qdesn_validation_tt500_final_summary.csv`
- `tables/qdesn_validation_tt500_final_manifest.txt`

## Promotion Rule

The validation-table work should be promoted to `main` through focused
cherry-picks only. Do not merge the full
`application-ensemble-likelihood-redesign` branch into `main`, because that
branch can contain unrelated application-development history.
