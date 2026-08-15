# PriceFM Stage-N Underperformance Closeout

Date: 2026-06-25

## Purpose

Stage N was a targeted median-only search over region/fold rows where the
current Q-DESN decision surface underperformed cached fold-aligned PriceFM
predictions.  The search was intentionally broad inside those targets, but its
selection contract remained conservative:

- candidate selection uses validation AQL only;
- test metrics are audit diagnostics and promotion guardrails only;
- test-oracle winners are diagnostic and must not be promoted directly;
- PriceFM comparisons are fold-aligned against the current cached PriceFM
  benchmark surface.

The closeout implemented in
`application/scripts/pricefm/74_closeout_pricefm_stage_n_underperformance.py`
formalizes this distinction.

## Inputs

- Stage-N manifest:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_n_underperformance_broad_20260625/manifest.csv`
- Stage-N run root:
  `application/data_local/pricefm/runs/pricefm_stage_n_underperformance_broad_20260625`
- Current decision surface:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv`

## Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/74_closeout_pricefm_stage_n_underperformance.py \
  --force true
```

## Outputs

Ignored local outputs are written to:

`application/data_local/pricefm/authoritative/pricefm_stage_n_underperformance_closeout_20260625/`

Important files:

- `stage_n_cell_method_metrics.csv`: canonical one-row-per-experiment-method
  table used by the closeout.
- `candidate_method_metrics.csv`: all completed experiment-method metrics.
- `validation_selected_closeout.csv`: one validation-selected row per
  region/fold target.
- `test_oracle_diagnostics.csv`: one test-best row per region/fold target,
  diagnostic only.
- `selection_instability_audit.csv`: validation-selected versus test-oracle
  mismatch table.
- `split_shift_summary.csv`: validation-to-test AQL shift diagnostics for the
  validation-selected and test-oracle views.
- `horizon_gap_summary.csv`: horizon-group comparison between the
  validation-selected and test-oracle candidates.
- `selection_rule_sensitivity.csv`: validation-only rule sensitivity table.
- `selection_rule_selected_rows.csv`: selected rows for each candidate
  validation-only selection rule.
- `promotion_candidates.csv`: conservative rows passing both validation and
  test guardrails.
- `remaining_pricefm_gap.csv`: validation-selected rows still behind PriceFM.
- `stage_n_underperformance_closeout_report.md`: compact local closeout report.
- `summary.json`: machine-readable summary.

## Closeout Results

Health checks:

- Manifest rows: 493.
- Completed cells with metric summaries: 493.
- Candidate method rows: 3451.
- Horizon metric rows: 662592.
- Horizon-group metric rows: 27608.
- Missing metric rows: 0.
- Failed cells: 0.
- Closeout runtime: 4:21.63 wall time, 2.69 GB max RSS.

Validation-selected view:

- Region/fold targets: 17.
- Beats previous Q-DESN test AQL: 7 / 17.
- Beats PriceFM test AQL: 0 / 17.
- Mean test-AQL delta versus previous Q-DESN: +0.053.
- Mean test-AQL delta versus PriceFM: +3.008.
- Promotion candidates under validation-plus-test guardrail: 7.

Test-oracle diagnostic view:

- Region/fold targets: 17.
- Beats previous Q-DESN test AQL: 14 / 17.
- Beats PriceFM test AQL: 0 / 17.
- Mean test-AQL delta versus previous Q-DESN: -0.586.
- Mean test-AQL delta versus PriceFM: +2.369.

The gap between these two views is the main finding.  Stage N found many
test-improving candidates, but the validation rule does not reliably select
them.  Therefore the next stage should improve selection robustness before any
larger hyperparameter launch.

Validation-only rule sensitivity:

| Rule | Test improvements | Mean test-AQL delta vs previous Q-DESN | Mean test-AQL delta vs PriceFM |
|---|---:|---:|---:|
| validation AQL minimum | 7 / 17 | +0.053 | +3.008 |
| validation MAE minimum | 7 / 17 | +0.053 | +3.008 |
| validation RMSE minimum | 6 / 17 | +0.348 | +3.303 |
| robust rank over validation AQL/MAE/RMSE | 8 / 17 | +0.001 | +2.956 |

The robust-rank rule is the best validation-only alternative among the simple
rules tested here, but it still does not beat PriceFM and should be treated as
a diagnostic candidate rule rather than an immediate replacement for the
current selection policy.

## Conservative Promotion Set

The validation-plus-test guardrail recommends only these 7 rows for possible
promotion:

| Region | Fold | Candidate | Method | Decision |
|---|---:|---|---|---|
| AT | 3 | `stagen_at_f3_g2_d2n160` | Q-DESN exAL RHS_NS | promote |
| BE | 3 | `stagen_be_f3_g1_d1n180` | Q-DESN exAL RHS_NS | promote |
| HU | 2 | `stagen_hu_f2_g1_l192` | Q-DESN exAL RHS_NS | promote |
| LT | 1 | `stagen_lt_f1_g1_d3n100` | Q-DESN AL RHS_NS | promote |
| NL | 3 | `stagen_nl_f3_g2_alow` | Q-DESN exAL RHS_NS | promote |
| RO | 1 | `stagen_ro_f1_g2_d2n120` | Q-DESN AL RHS_NS | promote |
| SE_4 | 1 | `stagen_se4_f1_g1_alow` | Q-DESN exAL RHS_NS | promote |

These rows still do not beat PriceFM; they only improve the current Q-DESN
surface under the conservative rule.

## Interpretation

Stage N should not replace the decision surface wholesale.  It is useful as a
closeout and diagnostic layer because it shows:

1. Q-DESN exAL RHS_NS remains the strongest default method family.
2. Some AL RHS_NS candidates remain competitive for specific region/fold rows.
3. The remaining PriceFM gap is not solved by this reservoir-geometry search.
4. The validation/test mismatch is the immediate bottleneck.
5. The next launch should be smaller and better controlled, not simply broader.

## Recommended Next Stage

Before launching a new model grid:

1. Freeze the Stage-N closeout as an audit artifact.
2. Patch or rebuild the current decision surface using only the 7 conservative
   promotion rows, or keep it as a candidate patch until reviewed.
3. Build a selection-instability diagnostic stage over the 10 non-promoted
   rows:
   - compare validation and test horizon-level AQL;
   - quantify whether validation misses are horizon-local or global;
   - flag rows where the oracle improvement is large but validation rejects it.
4. Revisit the selection rule:
   - require validation gain plus no test guardrail failure for promotion;
   - consider horizon-block validation or stability penalties;
   - avoid test-oracle promotion.
5. Only after the selection rule is stable, plan a smaller follow-up focused on
   remaining PriceFM gaps, likely emphasizing information-set parity and richer
   graph inputs rather than a pure reservoir-size expansion.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_n_closeout.py -q
```

The tests verify:

- `skipped_complete` cells count as completed;
- validation-selected and test-oracle candidates are separated;
- promotion requires validation gain and no test guardrail failure;
- expected closeout artifacts are written.
