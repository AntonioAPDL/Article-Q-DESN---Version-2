# PriceFM Stage-O Selection And Promotion Hardening

Date: 2026-06-26

## Purpose

Stage O is a non-fitting decision layer after the completed Stage-N
underperformance search.  It keeps the Stage-N result scientifically bounded:

- Stage N is median-only evidence.
- Selection remains validation-only.
- Test metrics are audit diagnostics and promotion guardrails only.
- Test-oracle rows are never promoted.
- The Stage-M article decision surface is not overwritten from median-only
  evidence.

The stage produces a conservative median patch candidate and a queued Stage-P
seven-quantile confirmation grid.  Stage-P is required before any article-facing
PriceFM comparison surface can be changed.

## Implemented Tooling

New script:

```text
application/scripts/pricefm/75_harden_pricefm_stage_o_selection_promotions.py
```

New tests:

```text
application/tests/test_pricefm_stage_o_selection_promotions.py
```

The script consumes the Stage-N closeout artifacts and writes ignored local
outputs under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/
```

It also writes the queued Stage-P grid config under ignored local config space:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_p_stage_n_promotions_quantile_confirmation_20260626.yaml
```

## Inputs

Current median registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv
```

Current article-facing decision surface:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv
```

Stage-N closeout:

```text
application/data_local/pricefm/authoritative/pricefm_stage_n_underperformance_closeout_20260625/
```

Stage-N generated config root:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_n_underperformance_broad_20260625/
```

## Commands

Run Stage O:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
mkdir -p application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_o.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/75_harden_pricefm_stage_o_selection_promotions.py \
  --force true
```

Dry-run the queued Stage-P grid without fitting models:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_p_stage_n_promotions_quantile_confirmation_20260626.yaml \
  --priorities 0 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows false \
  --dry-run true \
  --resume true \
  --force false
```

Validate generated Stage-P configs:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_p_stage_n_promotions_quantile_confirmation_20260626.yaml \
  --priorities 0 \
  --write-generated \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626 \
  --output-json application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_p_grid_validation/summary.json \
  --output-csv application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_p_grid_validation/artifact_status.csv
```

## Outputs

Important Stage-O outputs:

```text
stage_o_health.csv
stage_o_median_patch_candidates.csv
stage_o_promotion_queue.csv
stage_o_do_not_promote.csv
stage_o_selection_rule_audit.csv
stage_o_selection_rule_selected_rows.csv
stage_o_horizon_stability_audit.csv
stage_o_selection_instability_audit.csv
patched_median_registry_candidate.csv
stage_p_quantile_confirmation_registry.csv
stage_p_quantile_confirmation_grid.yaml
stage_o_selection_promotion_report.md
summary.json
```

Generated Stage-P dry-run/validation outputs:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626/
application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_p_grid_validation/
```

## Results

Stage-O health checks passed:

| Check | Value |
|---|---:|
| current median rows | 42 |
| current decision-surface rows | 42 |
| Stage-N validation-selected rows | 17 |
| Stage-N conservative promotion rows | 7 |
| patched registry rows | 42 |
| patch rows | 7 |
| Stage-M surface mutated | 0 |
| test-oracle rows promoted | 0 |

Conservative median promotion queue:

| Region | Fold | Candidate | Method | Test AQL gain vs current | Gap vs PriceFM |
|---|---:|---|---|---:|---:|
| AT | 3 | `stagen_at_f3_g2_d2n160` | Q-DESN exAL RHS_NS | -0.582 | 2.155 |
| BE | 3 | `stagen_be_f3_g1_d1n180` | Q-DESN exAL RHS_NS | -0.408 | 2.155 |
| HU | 2 | `stagen_hu_f2_g1_l192` | Q-DESN exAL RHS_NS | -0.014 | 2.772 |
| LT | 1 | `stagen_lt_f1_g1_d3n100` | Q-DESN AL RHS_NS | -1.107 | 3.851 |
| NL | 3 | `stagen_nl_f3_g2_alow` | Q-DESN exAL RHS_NS | -2.628 | 1.737 |
| RO | 1 | `stagen_ro_f1_g2_d2n120` | Q-DESN AL RHS_NS | -0.408 | 2.325 |
| SE_4 | 1 | `stagen_se4_f1_g1_alow` | Q-DESN exAL RHS_NS | -1.570 | 1.424 |

Do-not-promote rows:

| Category | Rows |
|---|---:|
| validation gain failed test guardrail | 9 |
| do not promote | 1 |

The robust validation-only rank rule remains diagnostic.  It is the best simple
validation-only rule in the Stage-N sensitivity table, but Stage O does not
adopt it automatically and does not use it to patch the registry.

Stage-P queue:

| Quantity | Value |
|---|---:|
| median promotion rows | 7 |
| paper quantiles | 7 |
| queued experiments | 49 |
| generated config validation | passed |

## Interpretation

Stage O confirms that Stage-N is useful as a median rescue layer, but not yet
an article-surface update.  The only safe rows are the seven conservative
median improvements.  Even these rows remain behind PriceFM on the median
comparison and require seven-quantile confirmation before they can affect the
paper-grid registry.

The main bottleneck remains selection stability: many test-oracle candidates
are better than the validation-selected row, but promoting them would violate
the validation-only contract.  The follow-up should therefore be a small
Stage-P confirmation run for the seven queued rows, not a new broad search.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_o_selection_promotions.py -q
```

Result:

```text
2 passed
```

Compile check:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/75_harden_pricefm_stage_o_selection_promotions.py
```

Result: passed.

Stage-P dry run:

```text
n_selected_experiments = 49
dry_run = true
```

Stage-P artifact validation:

```text
status = passed
n_selected = 49
```

## Next Step

Review the seven-row Stage-P queue.  If approved, launch only:

```text
pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626
```

Then freeze Stage-P quantile decisions with the existing PriceFM comparison
machinery.  Only rows that beat cached fold-aligned PriceFM on the paper
quantile grid should be eligible for article-surface promotion.
