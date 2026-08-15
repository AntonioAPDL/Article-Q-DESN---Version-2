# PriceFM Stage-W Priority-0 Closeout

Date: 2026-06-30

## Purpose

This note records the formal closeout of the Stage-W Priority-0 region/fold
screen.  Stage W tested whether a targeted graph-input or graph-geometry screen
could rescue the severe PriceFM comparison rows without changing the Stage-M
decision surface.  Selection remains validation-only; test metrics are used
only as audit evidence.

## Reproducible Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/85_closeout_pricefm_stage_w_priority0.py \
  --force true
```

Generated closeout artifacts are intentionally local and ignored:

```text
application/data_local/pricefm/authoritative/pricefm_stage_w_priority0_closeout_20260630/
```

The main generated report is:

```text
application/data_local/pricefm/authoritative/pricefm_stage_w_priority0_closeout_20260630/stage_w_priority0_report.md
```

## Inputs

| Item | Path |
|---|---|
| Stage-W grid root | `application/data_local/pricefm/experiment_grids/pricefm_stage_w_region_fold_screening_20260629` |
| Stage-W run root | `application/data_local/pricefm/runs/pricefm_stage_w_region_fold_screening_20260629` |
| Stage-W plan | `application/data_local/pricefm/authoritative/pricefm_stage_w_region_fold_screening_plan_20260629` |
| Stage-W time log | `application/data_local/pricefm/logs/stage_w_priority0_20260630_012938.time.log` |

## Health Check

| Check | Result |
|---|---:|
| Priority-0 experiments expected | 96 |
| Launch experiments completed | 96 |
| Completed cell-status rows | 96 |
| Metric files | 96 |
| Exact-equivalence rows | 96 |
| Exact-equivalence passed | 96 |
| Nonzero launch return codes | 0 |
| Binary `.rds/.rda/.RData/.rdata` artifacts | 0 |
| Stage-M surface changed | false |
| Run clean | true |
| Wall time | 2:07:41 |
| Max RSS | 1,825,304 KB |

## Validation-Selected Outcomes

| Region | Fold | Selected Stage-W test AQL | Current Q-DESN AQL | PriceFM AQL | Decision |
|---|---:|---:|---:|---:|---|
| AT | 3 | 9.7599 | 7.6466 | 6.7550 | reject |
| FI | 1 | 14.7799 | 10.5548 | 9.2534 | reject |
| HU | 2 | 8.1769 | 8.6841 | 7.3222 | candidate-only improvement |
| LT | 1 | 17.0560 | 14.4806 | 12.4899 | reject |
| SE_4 | 1 | 9.2404 | 8.4824 | 7.7024 | reject |
| SK | 3 | 11.7337 | 8.8067 | 7.5037 | reject |

Summary:

- Validation-selected PriceFM wins: 0.
- Validation-selected candidate-only wins over the current Q-DESN: 1, for HU fold 2.
- Validation-selected rejections: 5.
- Priority 1 is not recommended from this evidence.

## Test-Oracle Audit

The test-oracle audit is not a selection rule.  It checks whether the search
family contained a promising candidate that validation failed to select.

| Region | Fold | Best Stage-W test AQL | Current Q-DESN AQL | PriceFM AQL | Test-oracle interpretation |
|---|---:|---:|---:|---:|---|
| AT | 3 | 8.6236 | 7.6466 | 6.7550 | worse than current and PriceFM |
| FI | 1 | 13.3572 | 10.5548 | 9.2534 | worse than current and PriceFM |
| HU | 2 | 8.1511 | 8.6841 | 7.3222 | improves current, not PriceFM |
| LT | 1 | 15.5458 | 14.4806 | 12.4899 | worse than current and PriceFM |
| SE_4 | 1 | 9.2165 | 8.4824 | 7.7024 | worse than current and PriceFM |
| SK | 3 | 10.2832 | 8.8067 | 7.5037 | worse than current and PriceFM |

The test oracle improves the current Q-DESN in only one of six targets and never
beats PriceFM.  This means the failed validation-selected result is not merely a
selection accident; this Priority-0 search neighborhood itself is not the right
rescue family for these rows.

## Validation/Test Transfer

| Region | Fold | Validation-selected test AQL | Test-oracle AQL | Regret | Spearman(val, test) |
|---|---:|---:|---:|---:|---:|
| AT | 3 | 9.7599 | 8.6236 | 1.1363 | 0.4271 |
| FI | 1 | 14.7799 | 13.3572 | 1.4227 | 0.0872 |
| HU | 2 | 8.1769 | 8.1511 | 0.0258 | 0.8237 |
| LT | 1 | 17.0560 | 15.5458 | 1.5102 | 0.0616 |
| SE_4 | 1 | 9.2404 | 9.2165 | 0.0238 | 0.6199 |
| SK | 3 | 11.7337 | 10.2832 | 1.4504 | 0.5007 |

The low validation/test rank correlations for FI and LT, plus large regrets for
AT, FI, LT, and SK, show that the current single validation ranking is unstable
for this rescue family.

## Decision

Do not launch Stage-W Priority 1.  Do not change the Stage-M decision surface.
Keep HU fold 2 as diagnostic evidence that graph-geometry refinement can improve
the current Q-DESN in one row, but do not promote it because it still trails
PriceFM.

## Required Next Stage

The next stage should be diagnostic, not another broad brute-force launch:

1. Build a horizon-aware selection failure contract using existing completed
   outputs.
2. Quantify which horizon blocks drive the validation/test disconnect.
3. Decide whether selection should use stability across horizon blocks or
   multiple validation blocks before any new fit family is launched.
4. Only after this diagnostic contract is complete, design a narrow fit launch
   targeted to the diagnosed failure mode.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_w_priority0_closeout.py -q
```

Result: 2 passed.
