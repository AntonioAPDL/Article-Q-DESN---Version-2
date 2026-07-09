# TT500 Validation Table Style Audit

Date: 2026-06-14

Scope: `main.tex`, `tables/qdesn_validation_tt500_current_comparison.tex`,
`tables/qdesn_validation_tt500_inference_companion.tex`,
`tables/qdesn_validation_tt500_current_comparison.csv`,
`tables/qdesn_validation_tt500_current_comparison_manifest.txt`, and
`scripts/build_validation_tt500_current_comparison_table.R`.

## Style Criteria Used

The audit follows `Academic_Writing_Style_Profile_v0.2.md`, especially:

- tables should be interpretable without excessive text;
- captions should state what is compared and what rows/columns mean;
- simulation reporting should state goals, DGPs, competitors, metrics, results,
  and limitations;
- claims should remain evidence-bounded and should not become a leaderboard
  when rows are incomplete or not comparable.

## Problems In The Previous Table

- The single longtable had 108 rows and mixed three error families, three
  quantile levels, six model variants, two inference modes, metric values, and
  workflow status in one visual block.
- Family labels repeated on every row, which made scanning harder without
  adding statistical information.
- The table started mid-page and continued across pages, so it looked like a
  workflow inventory rather than a manuscript comparison table.
- The caption carried too much operational explanation.
- The DGP table floated behind the validation table, so the table order in the
  PDF did not match the order of the simulation design.

## Final Presentation Decision

The manuscript presentation now uses three primary generated tables:

- `tab:simulation-tt500-normal`: Gaussian error family.
- `tab:simulation-tt500-laplace`: Laplace error family.
- `tab:simulation-tt500-gausmix`: Gaussian-mixture error family.

Two inference-stratified companion tables are generated separately for audits
and refresh checks, but are not included in the main manuscript by default:

- `tab:simulation-tt500-vb`: VB rows grouped by error family and target
  quantile.
- `tab:simulation-tt500-mcmc`: MCMC rows grouped by error family and target
  quantile.

The three family tables:

- groups rows by target quantile level;
- uses grouped metric columns for Fit, F100, and F1000;
- keeps RMSE and pinball loss side by side for each evaluation block;
- removes the status column from the manuscript presentation so the numerical
  comparison remains compact;
- bolds the lowest reported value within each error-family, quantile, and
  metric column, with ties after two-decimal rounding bolded together;
- marks Q-DESN VB forecast cells as `forecast not exported` rather than
  computing incomparable forecast values from sidecars;
- keeps running and pending Q-DESN MCMC rows as explicit placeholders;
- defines the fit window by sample size and the forecast windows as lengths
  100 and 1000, with the common rolling-origin horizon rule
  \(H_{\max}=30\) and origin stride 30.

The two inference-stratified companion tables use `longtable` because each
view contains all three error families and all three quantile levels for one
inference method. They use the same metric columns and the same bolding rule
as the family tables, but omit the inference column because it is fixed by
construction. They use the same forecast-window wording as the family tables.
Keeping them as generated companion artifacts avoids repeating the same
numerical comparison in the main article while preserving a one-command path
for VB-only and MCMC-only inspections.

The CSV remains a full 108-row detailed artifact for reproducibility. The
primary TeX file is the manuscript presentation layer generated from that
artifact, and the companion TeX file is the inference-stratified audit layer.
Status fields remain available for audits without occupying manuscript columns.

## Verification

Commands run:

```sh
Rscript scripts/build_validation_tt500_current_comparison_table.R
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Compile result:

- no unresolved references;
- no overfull table warnings;
- Table 3 now precedes Tables 4--6 in the compiled PDF;
- Tables 4--6 are placed in the simulation section rather than deferred to the
  end of the manuscript.

## Remaining Limits

- The tables are current validation snapshots, not final rankings.
- Q-DESN VB forecast metrics should remain blank until the shared validation
  workflow exports a comparable rolling-origin forecast interface for those
  rows.
- The four incomplete Gaussian median Q-DESN MCMC rows should be refreshed from
  the same builder after the validation campaign finishes.
